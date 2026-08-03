// Port of snes/dma.c: DMA/HDMA emulation — channel register read/write,
// general-purpose DMA transfers, and the two-phase (init/do) HDMA transfer
// used every scanline for gradients and raster effects. Every function keeps
// its exact C-ABI name and signature (callconv(.c), C-pointer types) so the
// remaining .c callers (snes.c, zelda_cpu_infra.c, zelda_rtl.c) link
// unchanged. The Dma/DmaChannel struct layout itself stays C-owned in
// snes/dma.h — zelda_cpu_infra.c memcpy's channel state directly
// (sizeof(Dma) - offsetof(Dma, channel)) and zelda_rtl.c's SimpleHdma_Init
// pokes DmaChannel fields directly — so this module mirrors that layout
// field-for-field rather than redefining it. snes.c (not yet ported) still
// owns snes_read/snes_write/snes_readBBus/snes_writeBBus; dma.zig calls them
// as opaque C-ABI bus callbacks, exactly as dma.c did.

const std = @import("std");

// dma.c only reads snes->openBus; the prefix mirrors struct Snes in
// snes/snes.h field-for-field up to openBus, with the subsystem pointers
// opaque (only ever dereferenced by their own modules).
pub const Snes = extern struct {
    cpu: ?*anyopaque,
    apu: ?*anyopaque,
    ppu: ?*anyopaque,
    dma: ?*anyopaque,
    cart: ?*anyopaque,
    debug_cycles: bool,
    disableHpos: bool,
    input1: ?*anyopaque,
    input2: ?*anyopaque,
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
    // snes.h continues (ram, ramAdr); dma.c never touches those.
};

// Mirrors struct DmaChannel in snes/dma.h.
pub const DmaChannel = extern struct {
    bAdr: u8,
    aBank: u8,
    indBank: u8, // hdma
    repCount: u8, // hdma
    aAdr: u16,
    size: u16, // also indirect hdma adr
    tableAdr: u16, // hdma
    unusedByte: u8,
    dmaActive: bool,
    hdmaActive: bool,
    mode: u8,
    fixed: bool,
    decrement: bool,
    indirect: bool, // hdma
    fromB: bool,
    unusedBit: bool,
    doTransfer: bool, // hdma
    terminated: bool, // hdma
    offIndex: u8,
};

// Mirrors struct Dma in snes/dma.h (C keeps ownership of the layout;
// zelda_cpu_infra.c memcpy's channel state directly, sized off offsetof).
pub const Dma = extern struct {
    snes: ?*Snes,
    channel: [8]DmaChannel,
    hdmaTimer: u16,
    dmaTimer: u32,
    dmaBusy: bool,
};

// Same type as SaveLoadFunc in snes/saveload.h.
const SaveLoadFunc = fn (ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void;

extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;

extern fn snes_readBBus(snes: ?*Snes, adr: u8) callconv(.c) u8;
extern fn snes_writeBBus(snes: ?*Snes, adr: u8, val: u8) callconv(.c) void;
extern fn snes_read(snes: ?*Snes, adr: u32) callconv(.c) u8;
extern fn snes_write(snes: ?*Snes, adr: u32, val: u8) callconv(.c) void;

const bAdrOffsets: [8][4]u8 = .{
    .{ 0, 0, 0, 0 },
    .{ 0, 1, 0, 1 },
    .{ 0, 0, 0, 0 },
    .{ 0, 0, 1, 1 },
    .{ 0, 1, 2, 3 },
    .{ 0, 1, 0, 1 },
    .{ 0, 0, 0, 0 },
    .{ 0, 0, 1, 1 },
};

const transferLength: [8]u8 = .{ 1, 2, 2, 4, 4, 4, 2, 4 };

// See input.zig: dead-code stub for Zig 0.16's std.start analysis; the C
// main in src/main.c is the real entry point.
pub fn main() callconv(.c) c_int {
    return 0;
}

pub export fn dma_init(snes: ?*Snes) ?*Dma {
    const dma: *Dma = @ptrCast(@alignCast(malloc(@sizeOf(Dma)) orelse return null));
    dma.snes = snes;
    return dma;
}

pub export fn dma_free(dma: ?*Dma) void {
    free(dma);
}

pub export fn dma_reset(dma: *Dma) void {
    for (0..8) |i| {
        dma.channel[i] = .{
            .bAdr = 0xff,
            .aBank = 0xff,
            .indBank = 0xff,
            .repCount = 0xff,
            .aAdr = 0xffff,
            .size = 0xffff,
            .tableAdr = 0xffff,
            .unusedByte = 0xff,
            .dmaActive = false,
            .hdmaActive = false,
            .mode = 7,
            .fixed = true,
            .decrement = true,
            .indirect = true,
            .fromB = true,
            .unusedBit = true,
            .doTransfer = false,
            .terminated = false,
            .offIndex = 0,
        };
    }
    dma.hdmaTimer = 0;
    dma.dmaTimer = 0;
    dma.dmaBusy = false;
}

pub export fn dma_saveload(dma: *Dma, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) void {
    const len = @sizeOf(Dma) - @offsetOf(Dma, "channel");
    func.?(ctx, &dma.channel, len);
}

pub export fn dma_read(dma: *Dma, adr: u16) u8 {
    const c: usize = @intCast((adr & 0x70) >> 4);
    switch (adr & 0xf) {
        0x0 => {
            var val: u8 = dma.channel[c].mode;
            val |= @as(u8, @intFromBool(dma.channel[c].fixed)) << 3;
            val |= @as(u8, @intFromBool(dma.channel[c].decrement)) << 4;
            val |= @as(u8, @intFromBool(dma.channel[c].unusedBit)) << 5;
            val |= @as(u8, @intFromBool(dma.channel[c].indirect)) << 6;
            val |= @as(u8, @intFromBool(dma.channel[c].fromB)) << 7;
            return val;
        },
        0x1 => return dma.channel[c].bAdr,
        0x2 => return @truncate(dma.channel[c].aAdr & 0xff),
        0x3 => return @truncate(dma.channel[c].aAdr >> 8),
        0x4 => return dma.channel[c].aBank,
        0x5 => return @truncate(dma.channel[c].size & 0xff),
        0x6 => return @truncate(dma.channel[c].size >> 8),
        0x7 => return dma.channel[c].indBank,
        0x8 => return @truncate(dma.channel[c].tableAdr & 0xff),
        0x9 => return @truncate(dma.channel[c].tableAdr >> 8),
        0xa => return dma.channel[c].repCount,
        0xb, 0xf => return dma.channel[c].unusedByte,
        else => return dma.snes.?.openBus,
    }
}

pub export fn dma_write(dma: *Dma, adr: u16, val: u8) void {
    const c: usize = @intCast((adr & 0x70) >> 4);
    switch (adr & 0xf) {
        0x0 => {
            dma.channel[c].mode = val & 0x7;
            dma.channel[c].fixed = val & 0x8 != 0;
            dma.channel[c].decrement = val & 0x10 != 0;
            dma.channel[c].unusedBit = val & 0x20 != 0;
            dma.channel[c].indirect = val & 0x40 != 0;
            dma.channel[c].fromB = val & 0x80 != 0;
        },
        0x1 => dma.channel[c].bAdr = val,
        0x2 => dma.channel[c].aAdr = (dma.channel[c].aAdr & 0xff00) | val,
        0x3 => dma.channel[c].aAdr = (dma.channel[c].aAdr & 0xff) | (@as(u16, val) << 8),
        0x4 => dma.channel[c].aBank = val,
        0x5 => dma.channel[c].size = (dma.channel[c].size & 0xff00) | val,
        0x6 => dma.channel[c].size = (dma.channel[c].size & 0xff) | (@as(u16, val) << 8),
        0x7 => dma.channel[c].indBank = val,
        0x8 => dma.channel[c].tableAdr = (dma.channel[c].tableAdr & 0xff00) | val,
        0x9 => dma.channel[c].tableAdr = (dma.channel[c].tableAdr & 0xff) | (@as(u16, val) << 8),
        0xa => dma.channel[c].repCount = val,
        0xb, 0xf => dma.channel[c].unusedByte = val,
        else => {},
    }
}

pub export fn dma_doDma(dma: *Dma) void {
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        if (dma.channel[i].dmaActive) break;
    }
    if (i == 8) {
        // no active channels
        dma.dmaBusy = false;
        return;
    }
    const ch = &dma.channel[i];
    const off_idx = ch.offIndex;
    dma_transferByte(dma, ch.aAdr, ch.aBank, ch.bAdr +% bAdrOffsets[ch.mode][off_idx], ch.fromB);
    ch.offIndex = (off_idx + 1) & 3;
    dma.dmaTimer += 6; // 8 cycles for each byte taken, -2 for this cycle
    if (!ch.fixed) {
        ch.aAdr +%= if (ch.decrement) @as(u16, 0xffff) else 1;
    }
    ch.size -%= 1;
    if (ch.size == 0) {
        ch.offIndex = 0; // reset offset index
        ch.dmaActive = false;
        dma.dmaTimer += 8; // 8 cycle overhead per channel
    }
}

pub export fn dma_initHdma(dma: *Dma) void {
    dma.hdmaTimer = 0;
    var hdmaHappened = false;
    for (0..8) |i| {
        const ch = &dma.channel[i];
        if (ch.hdmaActive) {
            hdmaHappened = true;
            // terminate any dma
            ch.dmaActive = false;
            ch.offIndex = 0;
            // load address, repCount, and indirect address if needed
            ch.tableAdr = ch.aAdr;
            const adr1: u32 = (@as(u32, ch.aBank) << 16) | ch.tableAdr;
            ch.tableAdr +%= 1;
            ch.repCount = snes_read(dma.snes, adr1);
            dma.hdmaTimer += 8; // 8 cycle overhead for each active channel
            if (ch.indirect) {
                const adr2: u32 = (@as(u32, ch.aBank) << 16) | ch.tableAdr;
                ch.tableAdr +%= 1;
                var size_val: u16 = snes_read(dma.snes, adr2);
                const adr3: u32 = (@as(u32, ch.aBank) << 16) | ch.tableAdr;
                ch.tableAdr +%= 1;
                size_val |= @as(u16, snes_read(dma.snes, adr3)) << 8;
                ch.size = size_val;
                dma.hdmaTimer += 16; // another 16 cycles for indirect (total 24)
            }
            ch.doTransfer = true;
        } else {
            ch.doTransfer = false;
        }
        ch.terminated = false;
    }
    if (hdmaHappened) dma.hdmaTimer += 16; // 18 cycles overhead, -2 for this cycle
}

pub export fn dma_doHdma(dma: *Dma) void {
    dma.hdmaTimer = 0;
    var hdmaHappened = false;
    for (0..8) |i| {
        const ch = &dma.channel[i];
        if (ch.hdmaActive and !ch.terminated) {
            hdmaHappened = true;
            // terminate any dma
            ch.dmaActive = false;
            ch.offIndex = 0;
            // do the hdma
            dma.hdmaTimer += 8; // 8 cycles overhead for each active channel
            if (ch.doTransfer) {
                var j: usize = 0;
                while (j < transferLength[ch.mode]) : (j += 1) {
                    dma.hdmaTimer += 8; // 8 cycles for each byte transferred
                    if (ch.indirect) {
                        const size_before = ch.size;
                        ch.size +%= 1;
                        dma_transferByte(dma, size_before, ch.indBank, ch.bAdr +% bAdrOffsets[ch.mode][j], ch.fromB);
                    } else {
                        const table_before = ch.tableAdr;
                        ch.tableAdr +%= 1;
                        dma_transferByte(dma, table_before, ch.aBank, ch.bAdr +% bAdrOffsets[ch.mode][j], ch.fromB);
                    }
                }
            }
            ch.repCount -%= 1;
            ch.doTransfer = (ch.repCount & 0x80) != 0;
            if ((ch.repCount & 0x7f) == 0) {
                const adr1: u32 = (@as(u32, ch.aBank) << 16) | ch.tableAdr;
                ch.tableAdr +%= 1;
                ch.repCount = snes_read(dma.snes, adr1);
                if (ch.indirect) {
                    // TODO: oddness with not fetching high byte if last active channel and reCount is 0
                    const adr2: u32 = (@as(u32, ch.aBank) << 16) | ch.tableAdr;
                    ch.tableAdr +%= 1;
                    var size_val: u16 = snes_read(dma.snes, adr2);
                    const adr3: u32 = (@as(u32, ch.aBank) << 16) | ch.tableAdr;
                    ch.tableAdr +%= 1;
                    size_val |= @as(u16, snes_read(dma.snes, adr3)) << 8;
                    ch.size = size_val;
                    dma.hdmaTimer += 16; // 16 cycles for new indirect address
                }
                if (ch.repCount == 0) ch.terminated = true;
                ch.doTransfer = true;
            }
        }
    }
    if (hdmaHappened) dma.hdmaTimer += 16; // 18 cycles overhead, -2 for this cycle
}

// TODO: invalid writes:
//   accesing b-bus via a-bus gives open bus,
//   $2180-$2183 while accessing ram via a-bus open busses $2180-$2183
//   cannot access $4300-$437f (dma regs), or $420b / $420c
fn dma_transferByte(dma: *Dma, aAdr: u16, aBank: u8, bAdr: u8, fromB: bool) void {
    if (fromB) {
        snes_write(dma.snes, (@as(u32, aBank) << 16) | aAdr, snes_readBBus(dma.snes, bAdr));
    } else {
        const data = snes_read(dma.snes, (@as(u32, aBank) << 16) | aAdr);
        snes_writeBBus(dma.snes, bAdr, data);
    }
}

pub export fn dma_cycle(dma: *Dma) bool {
    if (dma.hdmaTimer > 0) {
        dma.hdmaTimer -%= 2;
        return true;
    } else if (dma.dmaBusy) {
        dma_doDma(dma);
        return true;
    }
    return false;
}

pub export fn dma_startDma(dma: *Dma, val: u8, hdma: bool) void {
    for (0..8) |i| {
        const bit: u8 = @as(u8, 1) << @intCast(i);
        if (hdma) {
            dma.channel[i].hdmaActive = val & bit != 0;
        } else {
            dma.channel[i].dmaActive = val & bit != 0;
        }
    }
    if (!hdma) {
        dma.dmaBusy = val != 0;
        dma.dmaTimer += if (dma.dmaBusy) 16 else 0; // 12-24 cycle overhead for entire dma transfer
    }
}
