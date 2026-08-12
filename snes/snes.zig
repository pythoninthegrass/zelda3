// Port of snes/snes.c: top-level SNES machine wiring — the glue that ties
// cpu/ppu/apu/dma/cart/input together with memory map decoding ($2100-$21ff
// B-bus, $4016/$4017 joypad, $4200-$421f control/status, $4300-$437f DMA
// regs), bank switching, and the main read/write/cpuRead/cpuWrite entry
// points. Every function keeps its exact C-ABI name and signature
// (callconv(.c), C-pointer types) so the remaining .c callers link unchanged.
//
// apu/ppu/dma/cart/input are all already-ported Zig modules (see their own
// files). snes.c pokes apu->inPorts/outPorts and input->latchLine directly,
// so this file locally mirrors just the Apu/Input fields it touches,
// field-for-field, up to (and including) the last field it reads or writes —
// trailing fields (Apu.timer/.hist, Input.currentState/.latchedState) are
// never touched here and are omitted, same truncation approach dma.zig/
// cart.zig use for their own local Snes mirrors. Cpu/Dma/Ppu/Cart stay
// opaque: snes.c never dereferences their fields directly (the one
// exception, cpu->irqWanted, goes through a tiny cpu_clearIrqWanted()
// accessor added to cpu.c rather than mirroring the whole ~20-field Cpu
// struct for one bool).

const std = @import("std");

const SaveLoadFunc = fn (ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void;

const Cpu = opaque {};
const Ppu = opaque {};
const Dma = opaque {};
const Cart = opaque {};

// Mirrors struct Apu in snes/apu.h up through outPorts (see file header).
const Apu = extern struct {
    spc: ?*anyopaque,
    dsp: ?*anyopaque,
    ram: [0x10000]u8,
    romReadable: bool,
    dspAdr: u8,
    cycles: u32,
    inPorts: [6]u8,
    outPorts: [4]u8,
};

// Mirrors struct Input in snes/input.h up through latchLine (see file header).
const Input = extern struct {
    snes: ?*anyopaque,
    type: u8,
    latchLine: bool,
};

extern fn cpu_init(mem: ?*anyopaque, memType: c_int) callconv(.c) *Cpu;
extern fn cpu_free(cpu: *Cpu) callconv(.c) void;
extern fn cpu_reset(cpu: *Cpu) callconv(.c) void;
extern fn cpu_saveload(cpu: *Cpu, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) callconv(.c) void;
extern fn cpu_clearIrqWanted(cpu: *Cpu) callconv(.c) void;

extern fn apu_init() callconv(.c) ?*Apu;
extern fn apu_free(apu: ?*Apu) callconv(.c) void;
extern fn apu_reset(apu: *Apu) callconv(.c) void;
extern fn apu_cycle(apu: *Apu) callconv(.c) void;
extern fn apu_saveload(apu: *Apu, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) callconv(.c) void;

extern fn dma_init(snes: ?*anyopaque) callconv(.c) ?*Dma;
extern fn dma_free(dma: ?*Dma) callconv(.c) void;
extern fn dma_reset(dma: *Dma) callconv(.c) void;
extern fn dma_saveload(dma: *Dma, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) callconv(.c) void;
extern fn dma_read(dma: *Dma, adr: u16) callconv(.c) u8;
extern fn dma_write(dma: *Dma, adr: u16, val: u8) callconv(.c) void;
extern fn dma_startDma(dma: *Dma, val: u8, hdma: bool) callconv(.c) void;

extern fn ppu_init() callconv(.c) ?*Ppu;
extern fn ppu_free(ppu: ?*Ppu) callconv(.c) void;
extern fn ppu_reset(ppu: *Ppu) callconv(.c) void;
extern fn ppu_saveload(ppu: *Ppu, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) callconv(.c) void;
extern fn ppu_read(ppu: *Ppu, adr: u8) callconv(.c) u8;
extern fn ppu_write(ppu: *Ppu, adr: u8, val: u8) callconv(.c) void;

extern fn cart_init(snes: ?*anyopaque) callconv(.c) ?*Cart;
extern fn cart_free(cart: ?*Cart) callconv(.c) void;
extern fn cart_reset(cart: *Cart) callconv(.c) void;
extern fn cart_saveload(cart: *Cart, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) callconv(.c) void;
extern fn cart_read(cart: *Cart, bank: u8, adr: u16) callconv(.c) u8;
extern fn cart_write(cart: *Cart, bank: u8, adr: u16, val: u8) callconv(.c) void;

extern fn input_init(snes: ?*anyopaque) callconv(.c) ?*Input;
extern fn input_free(input: ?*Input) callconv(.c) void;
extern fn input_reset(input: *Input) callconv(.c) void;
extern fn input_cycle(input: *Input) callconv(.c) void;
extern fn input_read(input: *Input) callconv(.c) u8;

extern fn getProcessorStateCpu(snes: ?*anyopaque, line: [*]u8) callconv(.c) void;
extern fn printf(fmt: [*:0]const u8, ...) callconv(.c) c_int;
extern var stdout: *anyopaque;
extern fn fflush(stream: ?*anyopaque) callconv(.c) c_int;
extern fn malloc(size: usize) callconv(.c) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) callconv(.c) void;

pub const Snes = extern struct {
    cpu: *Cpu,
    apu: *Apu,
    ppu: *Ppu,
    dma: *Dma,
    cart: *Cart,
    debug_cycles: bool,
    disableHpos: bool,
    input1: *Input,
    input2: *Input,
    hPos: u16,
    vPos: u16,
    frames: u32,
    cpuCyclesLeft: u8,
    cpuMemOps: u8,
    apuCatchupCycles: f64,
    hIrqEnabled: bool,
    vIrqEnabled: bool,
    nmiEnabled: bool,
    hTimer: u16,
    vTimer: u16,
    inNmi: bool,
    inIrq: bool,
    inVblank: bool,
    portAutoRead: [4]u16,
    autoJoyRead: bool,
    autoJoyTimer: u16,
    ppuLatch: bool,
    multiplyA: u8,
    multiplyResult: u16,
    divideA: u16,
    divideResult: u16,
    fastMem: bool,
    openBus: u8,
    ram: [*]u8,
    ramAdr: u32,
};

// See input.zig: dead-code stub for Zig 0.16's std.start analysis; the C
// main in src/main.c is the real entry point.
pub fn main() callconv(.c) c_int {
    return 0;
}

pub export fn snes_init(ram: [*]u8) ?*Snes {
    const snes: *Snes = @ptrCast(@alignCast(malloc(@sizeOf(Snes)) orelse return null));
    snes.ram = ram;
    snes.cpu = cpu_init(@ptrCast(snes), 0);
    snes.apu = apu_init() orelse return null;
    snes.dma = dma_init(@ptrCast(snes)) orelse return null;
    snes.ppu = ppu_init() orelse return null;
    snes.cart = cart_init(@ptrCast(snes)) orelse return null;
    snes.input1 = input_init(@ptrCast(snes)) orelse return null;
    snes.input2 = input_init(@ptrCast(snes)) orelse return null;
    snes.debug_cycles = false;
    snes.disableHpos = false;
    return snes;
}

pub export fn snes_free(snes: *Snes) void {
    cpu_free(snes.cpu);
    apu_free(snes.apu);
    dma_free(snes.dma);
    ppu_free(snes.ppu);
    cart_free(snes.cart);
    input_free(snes.input1);
    input_free(snes.input2);
    free(@ptrCast(snes));
}

pub export fn snes_saveload(snes: *Snes, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) void {
    cpu_saveload(snes.cpu, func, ctx);
    apu_saveload(snes.apu, func, ctx);
    dma_saveload(snes.dma, func, ctx);
    ppu_saveload(snes.ppu, func, ctx);
    cart_saveload(snes.cart, func, ctx);
    func.?(ctx, &snes.hPos, @offsetOf(Snes, "openBus") + 1 - @offsetOf(Snes, "hPos"));
    func.?(ctx, snes.ram, 0x20000);
    func.?(ctx, &snes.ramAdr, 4);
    snes.disableHpos = false;
}

pub export fn snes_reset(snes: *Snes, hard: bool) void {
    cart_reset(snes.cart);
    cpu_reset(snes.cpu);
    apu_reset(snes.apu);
    dma_reset(snes.dma);
    ppu_reset(snes.ppu);
    input_reset(snes.input1);
    input_reset(snes.input2);
    if (hard) @memset(snes.ram[0..0x20000], 0);
    snes.ramAdr = 0;
    snes.hPos = 0;
    snes.vPos = 0;
    snes.frames = 0;
    snes.cpuCyclesLeft = 52;
    snes.cpuMemOps = 0;
    snes.apuCatchupCycles = 0.0;
    snes.hIrqEnabled = false;
    snes.vIrqEnabled = false;
    snes.nmiEnabled = false;
    snes.hTimer = 0x1ff;
    snes.vTimer = 0x1ff;
    snes.inNmi = false;
    snes.inIrq = false;
    snes.inVblank = false;
    @memset(&snes.portAutoRead, 0);
    snes.autoJoyRead = false;
    snes.autoJoyTimer = 0;
    snes.ppuLatch = false;
    snes.multiplyA = 0xff;
    snes.multiplyResult = 0xfe01;
    snes.divideA = 0xffff;
    snes.divideResult = 0x101;
    snes.fastMem = false;
    snes.openBus = 0;
}

pub export fn snes_printCpuLine(snes: *Snes) void {
    if (snes.debug_cycles) {
        var line: [80]u8 = undefined;
        getProcessorStateCpu(@ptrCast(snes), &line);
        _ = printf("%s\n", &line);
        _ = fflush(stdout);
    }
}

fn snes_catchupApu(snes: *Snes) void {
    const catchupCycles: i32 = @intFromFloat(snes.apuCatchupCycles);
    var i: i32 = 0;
    while (i < catchupCycles) : (i += 1) {
        apu_cycle(snes.apu);
    }
    snes.apuCatchupCycles -= @as(f64, @floatFromInt(catchupCycles));
}

pub export fn snes_doAutoJoypad(snes: *Snes) void {
    @memset(&snes.portAutoRead, 0);
    snes.input1.latchLine = true;
    snes.input2.latchLine = true;
    input_cycle(snes.input1); // latches the controllers
    input_cycle(snes.input2);
    snes.input1.latchLine = false;
    snes.input2.latchLine = false;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        const val = input_read(snes.input1);
        snes.portAutoRead[0] |= @as(u16, val & 1) << @intCast(15 - i);
        snes.portAutoRead[2] |= @as(u16, (val >> 1) & 1) << @intCast(15 - i);
        const val2 = input_read(snes.input2);
        snes.portAutoRead[1] |= @as(u16, val2 & 1) << @intCast(15 - i);
        snes.portAutoRead[3] |= @as(u16, (val2 >> 1) & 1) << @intCast(15 - i);
    }
}

pub export fn snes_readBBus(snes: *Snes, adr: u8) u8 {
    if (adr < 0x40) return ppu_read(snes.ppu, adr);
    if (adr < 0x80) return snes.apu.outPorts[adr & 3];
    if (adr == 0x80) {
        const ret = snes.ram[snes.ramAdr];
        snes.ramAdr = (snes.ramAdr + 1) & 0x1ffff;
        return ret;
    }
    return snes.openBus;
}

pub export fn snes_writeBBus(snes: *Snes, adr: u8, val: u8) void {
    if (adr < 0x40) {
        ppu_write(snes.ppu, adr, val);
        return;
    }
    if (adr < 0x80) {
        snes_catchupApu(snes); // catch up the apu before writing
        snes.apu.inPorts[adr & 3] = val;
        return;
    }
    switch (adr) {
        0x80 => {
            snes.ram[snes.ramAdr] = val;
            snes.ramAdr = (snes.ramAdr + 1) & 0x1ffff;
        },
        0x81 => snes.ramAdr = (snes.ramAdr & 0x1ff00) | val,
        0x82 => snes.ramAdr = (snes.ramAdr & 0x100ff) | (@as(u32, val) << 8),
        0x83 => snes.ramAdr = (snes.ramAdr & 0x0ffff) | (@as(u32, val & 1) << 16),
        else => {},
    }
}

fn snes_readReg(snes: *Snes, adr: u16) u8 {
    return switch (adr) {
        0x4210 => blk: {
            var val: u8 = 0x2; // CPU version (4 bit)
            val |= @as(u8, @intFromBool(snes.inNmi)) << 7;
            snes.inNmi = false;
            break :blk val | (snes.openBus & 0x70);
        },
        0x4211 => blk: {
            const val: u8 = @as(u8, @intFromBool(snes.inIrq)) << 7;
            snes.inIrq = false;
            cpu_clearIrqWanted(snes.cpu);
            break :blk val | (snes.openBus & 0x7f);
        },
        0x4212 => @as(u8, @intFromBool(snes.autoJoyTimer > 0)) | @as(u8, @intFromBool(snes.hPos >= 1024)) << 6 | @as(u8, @intFromBool(snes.inVblank)) << 7 | (snes.openBus & 0x3e),
        0x4213 => @as(u8, @intFromBool(snes.ppuLatch)) << 7,
        0x4214 => @truncate(snes.divideResult & 0xff),
        0x4215 => @truncate(snes.divideResult >> 8),
        0x4216 => @truncate(snes.multiplyResult & 0xff),
        0x4217 => @truncate(snes.multiplyResult >> 8),
        0x4218, 0x421a, 0x421c, 0x421e => @truncate(snes.portAutoRead[@intCast((adr - 0x4218) / 2)] & 0xff),
        0x4219, 0x421b, 0x421d, 0x421f => @truncate(snes.portAutoRead[@intCast((adr - 0x4219) / 2)] >> 8),
        else => snes.openBus,
    };
}

fn snes_writeReg(snes: *Snes, adr: u16, val: u8) void {
    switch (adr) {
        0x4200 => {
            snes.autoJoyRead = (val & 1) != 0;
            if (!snes.autoJoyRead) snes.autoJoyTimer = 0;
            snes.hIrqEnabled = (val & 0x10) != 0;
            snes.vIrqEnabled = (val & 0x20) != 0;
            snes.nmiEnabled = (val & 0x80) != 0;
            if (!snes.hIrqEnabled and !snes.vIrqEnabled) {
                snes.inIrq = false;
                cpu_clearIrqWanted(snes.cpu);
            }
        },
        0x4201 => {
            if ((val & 0x80) == 0 and snes.ppuLatch) {
                _ = ppu_read(snes.ppu, 0x37); // latch the ppu
            }
            snes.ppuLatch = (val & 0x80) != 0;
        },
        0x4202 => snes.multiplyA = val,
        0x4203 => snes.multiplyResult = @as(u16, snes.multiplyA) * @as(u16, val),
        0x4204 => snes.divideA = (snes.divideA & 0xff00) | val,
        0x4205 => snes.divideA = (snes.divideA & 0x00ff) | (@as(u16, val) << 8),
        0x4206 => if (val == 0) {
            snes.divideResult = 0xffff;
            snes.multiplyResult = snes.divideA;
        } else {
            snes.divideResult = snes.divideA / val;
            snes.multiplyResult = snes.divideA % val;
        },
        0x4207 => snes.hTimer = (snes.hTimer & 0x100) | val,
        0x4208 => snes.hTimer = (snes.hTimer & 0x0ff) | (@as(u16, val & 1) << 8),
        0x4209 => snes.vTimer = (snes.vTimer & 0x100) | val,
        0x420a => snes.vTimer = (snes.vTimer & 0x0ff) | (@as(u16, val & 1) << 8),
        0x420b => dma_startDma(snes.dma, val, false),
        0x420c => dma_startDma(snes.dma, val, true),
        0x420d => snes.fastMem = (val & 1) != 0,
        else => {},
    }
}

fn snes_rread(snes: *Snes, adr: u32) u8 {
    const bank = @as(u8, @truncate(adr >> 16));
    const addr = @as(u16, @truncate(adr & 0xffff));
    if ((bank & 0x7f) < 0x40 and addr < 0x4380) {
        if (addr < 0x2000) return snes.ram[addr];
        if (addr >= 0x2100 and addr < 0x2200) return snes_readBBus(snes, @truncate(addr & 0xff));
        if (addr == 0x4016) return input_read(snes.input1) | (snes.openBus & 0xfc);
        if (addr == 0x4017) return input_read(snes.input2) | (snes.openBus & 0xe0) | 0x1c;
        if (addr >= 0x4200 and addr < 0x4220) return snes_readReg(snes, addr);
        if (addr >= 0x4300 and addr < 0x4380) return dma_read(snes.dma, addr);
    } else if ((bank & ~@as(u8, 1)) == 0x7e) {
        return snes.ram[@as(usize, (@as(u32, bank & 1) << 16) | addr)];
    }
    return cart_read(snes.cart, bank, addr);
}

pub export fn snes_write(snes: *Snes, adr: u32, val: u8) void {
    snes.openBus = val;
    const bank = @as(u8, @truncate(adr >> 16));
    const addr = @as(u16, @truncate(adr & 0xffff));
    if (bank == 0x7e or bank == 0x7f) {
        snes.ram[@as(usize, (@as(u32, bank & 1) << 16) | addr)] = val;
    } else if (bank < 0x40 or (bank >= 0x80 and bank < 0xc0)) {
        if (addr < 0x2000) {
            snes.ram[addr] = val;
        } else if (addr >= 0x2100 and addr < 0x2200) {
            snes_writeBBus(snes, @truncate(addr & 0xff), val);
        } else if (addr == 0x4016) {
            snes.input1.latchLine = (val & 1) != 0;
            snes.input2.latchLine = (val & 1) != 0;
        } else if (addr >= 0x4200 and addr < 0x4220) {
            snes_writeReg(snes, addr, val);
        } else if (addr >= 0x4300 and addr < 0x4380) {
            dma_write(snes.dma, addr, val);
        }
    }
    cart_write(snes.cart, bank, addr, val);
}

pub export fn snes_read(snes: *Snes, adr: u32) u8 {
    const val = snes_rread(snes, adr);
    snes.openBus = val;
    return val;
}

pub export fn snes_cpuRead(snes: *Snes, adr: u32) u8 {
    snes.cpuMemOps += 1;
    snes.cpuCyclesLeft += 6;
    return snes_read(snes, adr);
}

pub export fn snes_cpuWrite(snes: *Snes, adr: u32, val: u8) void {
    snes.cpuMemOps += 1;
    snes.cpuCyclesLeft += 6;
    snes_write(snes, adr, val);
}
