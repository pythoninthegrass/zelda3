// Port of snes/apu.c: APU wiring — the CPU-visible $2140-$21ff-style I/O
// registers, timers, and boot-ROM overlay that glue the Spc (SPC700 CPU) and
// Dsp (S-DSP) together. Every function keeps its exact C-ABI name and
// signature (callconv(.c), C-pointer types) so the remaining .c callers
// (snes.c, zelda_cpu_infra.c, spc_player.c, tracing.c) link unchanged. The
// Apu struct layout itself stays C-owned in snes/apu.h — spc_player.c and
// tracing.c reach through apu->ram/apu->hist/apu->spc directly — so this
// module mirrors that layout field-for-field rather than redefining it.
// spc.c/dsp.c are not yet ported: apu.zig calls their real spc_*/dsp_*
// C-ABI entry points as opaque handles, exactly as apu.c did.

const std = @import("std");

pub const Timer = extern struct {
    cycles: u8,
    divider: u8,
    target: u8,
    counter: u8,
    enabled: bool,
};

// Mirrors struct DspRegWriteHistory in snes/dsp.h.
pub const DspRegWriteHistory = extern struct {
    count: u32,
    addr: [256]u8,
    val: [256]u8,
};

// Mirrors the anonymous `union { DspRegWriteHistory hist; void *padpad; }`
// in struct Apu: the void* member forces 8-byte alignment on the union
// (and thus on the whole struct), matching the C layout exactly.
pub const HistUnion = extern union {
    value: DspRegWriteHistory,
    padpad: ?*anyopaque,
};

// Mirrors struct Apu in snes/apu.h. spc/dsp stay opaque here: apu.c only
// ever passes them straight through to spc_*/dsp_* calls, never dereferences
// their fields (those structs are fully defined only in spc.h/dsp.h, owned
// by their own not-yet-ported modules).
pub const Apu = extern struct {
    spc: ?*anyopaque,
    dsp: ?*anyopaque,
    ram: [0x10000]u8,
    romReadable: bool,
    dspAdr: u8,
    cycles: u32,
    inPorts: [6]u8,
    outPorts: [4]u8,
    timer: [3]Timer,
    cpuCyclesLeft: u8,
    hist: HistUnion,
};

// Same type as SaveLoadFunc in snes/saveload.h.
const SaveLoadFunc = fn (ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void;

extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;

extern fn spc_init(apu: *Apu) callconv(.c) ?*anyopaque;
extern fn spc_free(spc: ?*anyopaque) callconv(.c) void;
extern fn spc_reset(spc: ?*anyopaque) callconv(.c) void;
extern fn spc_runOpcode(spc: ?*anyopaque) callconv(.c) c_int;
extern fn spc_saveload(spc: ?*anyopaque, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) callconv(.c) void;

extern fn dsp_init(apu_ram: [*]u8) callconv(.c) ?*anyopaque;
extern fn dsp_free(dsp: ?*anyopaque) callconv(.c) void;
extern fn dsp_reset(dsp: ?*anyopaque) callconv(.c) void;
extern fn dsp_cycle(dsp: ?*anyopaque) callconv(.c) void;
extern fn dsp_read(dsp: ?*anyopaque, adr: u8) callconv(.c) u8;
extern fn dsp_write(dsp: ?*anyopaque, adr: u8, val: u8) callconv(.c) void;
extern fn dsp_saveload(dsp: ?*anyopaque, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) callconv(.c) void;

const boot_rom: [0x40]u8 = .{
    0xcd, 0xef, 0xbd, 0xe8, 0x00, 0xc6, 0x1d, 0xd0, 0xfc, 0x8f, 0xaa, 0xf4, 0x8f, 0xbb, 0xf5, 0x78,
    0xcc, 0xf4, 0xd0, 0xfb, 0x2f, 0x19, 0xeb, 0xf4, 0xd0, 0xfc, 0x7e, 0xf4, 0xd0, 0x0b, 0xe4, 0xf5,
    0xcb, 0xf4, 0xd7, 0x00, 0xfc, 0xd0, 0xf3, 0xab, 0x01, 0x10, 0xef, 0x7e, 0xf4, 0x10, 0xeb, 0xba,
    0xf6, 0xda, 0x00, 0xba, 0xf4, 0xc4, 0xf4, 0xdd, 0x5d, 0xd0, 0xdb, 0x1f, 0x00, 0x00, 0xc0, 0xff,
};

// See input.zig: dead-code stub for Zig 0.16's std.start analysis; the C
// main in src/main.c is the real entry point.
pub fn main() callconv(.c) c_int {
    return 0;
}

pub export fn apu_init() ?*Apu {
    const apu: *Apu = @ptrCast(@alignCast(malloc(@sizeOf(Apu)) orelse return null));
    apu.spc = spc_init(apu);
    apu.dsp = dsp_init(&apu.ram);
    return apu;
}

pub export fn apu_free(apu: ?*Apu) void {
    if (apu) |a| {
        spc_free(a.spc);
        dsp_free(a.dsp);
    }
    free(apu);
}

pub export fn apu_saveload(apu: *Apu, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) void {
    const ram_len = @offsetOf(Apu, "hist") - @offsetOf(Apu, "ram");
    func.?(ctx, &apu.ram, ram_len);
    dsp_saveload(apu.dsp, func, ctx);
    spc_saveload(apu.spc, func, ctx);
}

pub export fn apu_reset(apu: *Apu) void {
    apu.romReadable = true; // before resetting spc, because it reads reset vector from it
    spc_reset(apu.spc);
    dsp_reset(apu.dsp);
    @memset(&apu.ram, 0);
    apu.dspAdr = 0;
    apu.cycles = 0;
    @memset(&apu.inPorts, 0);
    @memset(&apu.outPorts, 0);
    for (0..3) |i| {
        apu.timer[i].cycles = 0;
        apu.timer[i].divider = 0;
        apu.timer[i].target = 0;
        apu.timer[i].counter = 0;
        apu.timer[i].enabled = false;
    }
    apu.cpuCyclesLeft = 7;
    apu.hist.value.count = 0;
}

pub export fn apu_cycle(apu: *Apu) void {
    if (apu.cpuCyclesLeft == 0) {
        apu.cpuCyclesLeft = @truncate(@as(u32, @bitCast(spc_runOpcode(apu.spc))));
    }
    apu.cpuCyclesLeft -%= 1;

    if ((apu.cycles & 0x1f) == 0) {
        // every 32 cycles
        dsp_cycle(apu.dsp);
    }

    // handle timers
    for (0..3) |i| {
        if (apu.timer[i].cycles == 0) {
            apu.timer[i].cycles = if (i == 2) 16 else 128;
            if (apu.timer[i].enabled) {
                apu.timer[i].divider +%= 1;
                if (apu.timer[i].divider == apu.timer[i].target) {
                    apu.timer[i].divider = 0;
                    apu.timer[i].counter +%= 1;
                    apu.timer[i].counter &= 0xf;
                }
            }
        }
        apu.timer[i].cycles -%= 1;
    }

    apu.cycles +%= 1;
}

pub export fn apu_cpuRead(apu: *Apu, adr: u16) u8 {
    switch (adr) {
        0xf0, 0xf1, 0xfa, 0xfb, 0xfc => return 0,
        0xf2 => return apu.dspAdr,
        0xf3 => return dsp_read(apu.dsp, apu.dspAdr & 0x7f),
        0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9 => return apu.inPorts[@as(usize, adr - 0xf4)],
        0xfd, 0xfe, 0xff => {
            const idx: usize = adr - 0xfd;
            const ret = apu.timer[idx].counter;
            apu.timer[idx].counter = 0;
            return ret;
        },
        else => {},
    }
    if (apu.romReadable and adr >= 0xffc0) {
        return boot_rom[adr - 0xffc0];
    }
    return apu.ram[adr];
}

pub export fn apu_cpuWrite(apu: *Apu, adr: u16, val: u8) void {
    switch (adr) {
        0xf0 => {}, // test register
        0xf1 => {
            for (0..3) |i| {
                const bit: u8 = @as(u8, 1) << @intCast(i);
                if (!apu.timer[i].enabled and (val & bit) != 0) {
                    apu.timer[i].divider = 0;
                    apu.timer[i].counter = 0;
                }
                apu.timer[i].enabled = (val & bit) != 0;
            }
            if (val & 0x10 != 0) {
                apu.inPorts[0] = 0;
                apu.inPorts[1] = 0;
            }
            if (val & 0x20 != 0) {
                apu.inPorts[2] = 0;
                apu.inPorts[3] = 0;
            }
            apu.romReadable = val & 0x80 != 0;
        },
        0xf2 => apu.dspAdr = val,
        0xf3 => {
            const i = apu.hist.value.count;
            if (i != 256) {
                apu.hist.value.count = i + 1;
                apu.hist.value.addr[@as(usize, i)] = apu.dspAdr;
                apu.hist.value.val[@as(usize, i)] = val;
            }
            if (apu.dspAdr < 0x80) dsp_write(apu.dsp, apu.dspAdr, val);
        },
        0xf4, 0xf5, 0xf6, 0xf7 => apu.outPorts[@as(usize, adr - 0xf4)] = val,
        0xf8, 0xf9 => apu.inPorts[@as(usize, adr - 0xf4)] = val,
        0xfa, 0xfb, 0xfc => apu.timer[@as(usize, adr - 0xfa)].target = val,
        else => {},
    }
    apu.ram[adr] = val;
}
