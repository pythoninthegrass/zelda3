// Port of snes/snes.c: top-level SNES machine wiring — the glue that ties
// cpu/ppu/apu/dma/cart/input together with memory map decoding ($2100-$21ff
// B-bus, $4016/$4017 joypad, $4200-$421f control/status, $4300-$437f DMA
// regs), bank switching, and the main read/write/cpuRead/cpuWrite entry
// points. Every function keeps its exact C-ABI name and signature
// (callconv(.c), C-pointer types) so the remaining .c callers link unchanged.

const std = @import("std");

const SaveLoadFunc = fn (ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void;

const Cpu = opaque {};
const Ppu = opaque {};
const Dma = opaque {};
const Cart = opaque {};
const Input = opaque {};

extern fn cpu_init(mem: ?*anyopaque, memType: c_int) callconv(.c) *Cpu;
extern fn cpu_free(cpu: *Cpu) callconv(.c) void;
extern fn cpu_reset(cpu: *Cpu) callconv(.c) void;
extern fn cpu_saveload(cpu: *Cpu, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) callconv(.c) void;
extern fn apu_init() callconv(.c) ?*anyopaque;
extern fn apu_free(apu: ?*anyopaque) callconv(.c) void;
extern fn apu_reset(apu: ?*anyopaque) callconv(.c) void;
extern fn apu_cycle(apu: ?*anyopaque) callconv(.c) void;
extern fn apu_saveload(apu: ?*anyopaque, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) callconv(.c) void;
extern fn dma_init(snes: ?*anyopaque) callconv(.c) ?*anyopaque;
extern fn dma_free(dma: ?*anyopaque) callconv(.c) void;
extern fn dma_reset(dma: ?*anyopaque) callconv(.c) void;
extern fn dma_saveload(dma: ?*anyopaque, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) callconv(.c) void;
extern fn dma_read(dma: ?*anyopaque, adr: u16) callconv(.c) u8;
extern fn dma_write(dma: ?*anyopaque, adr: u16, val: u8) callconv(.c) void;
extern fn dma_startDma(dma: ?*anyopaque, val: u8, hdma: bool) callconv(.c) void;
extern fn ppu_init(snes: ?*anyopaque) callconv(.c) ?*anyopaque;
extern fn ppu_free(ppu: ?*anyopaque) callconv(.c) void;
extern fn ppu_reset(ppu: ?*anyopaque) callconv(.c) void;
extern fn ppu_saveload(ppu: ?*anyopaque, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) callconv(.c) void;
extern fn ppu_read(ppu: ?*anyopaque, adr: u8) callconv(.c) u8;
extern fn ppu_write(ppu: ?*anyopaque, adr: u8, val: u8) callconv(.c) void;
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
extern fn getProcessorStateCpu(snes: ?*anyopaque, line: [*:0]u8) callconv(.c) void;
extern fn printf(fmt: [*:0]const u8, args: anytype) callconv(.c) c_int;
extern var stdout: *anyopaque;
extern fn fflush(stream: ?*anyopaque) callconv(.c) c_int;
extern fn malloc(size: usize) callconv(.c) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) callconv(.c) void;

pub var g_bp_addr: c_int = 0;

pub const Snes = extern struct {
    cpu: *Cpu,
    apu: ?*anyopaque,
    ppu: ?*anyopaque,
    dma: ?*anyopaque,
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

pub fn main() callconv(.c) c_int { return 0; }

pub export fn snes_init(ram: [*]u8) ?*Snes {
    const snes: *Snes = @ptrCast(@alignCast(malloc(@sizeOf(Snes)) orelse return null));
    snes.ram = ram;
    snes.cpu = cpu_init(@ptrCast(snes), 0);
    snes.apu = apu_init();
    snes.dma = dma_init(@ptrCast(snes));
    snes.ppu = ppu_init(@ptrCast(snes));
    snes.cart = cart_init(@ptrCast(snes));
    snes.input1 = @ptrCast(input_init(@ptrCast(snes)) orelse return null);
    snes.input2 = @ptrCast(input_init(@ptrCast(snes)) orelse return null);
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
    func.?(ctx, &snes.hPos, @sizeOf(u16) * 4);
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
        printf("%s\n", line);
        fflush(stdout);
    }
}

fn snes_catchupApu(snes: *Snes) void {
    const catchupCycles = @intCast(@as(i32, @intFromFloat(@floor(snes.apuCatchupCycles))));
    var i: i32 = 0;
    while (i < catchupCycles) : (i += 1) {
        apu_cycle(snes.apu);
    }
    snes.apuCatchupCycles -= @as(f64, @floatFromInt(catchupCycles));
}

pub export fn snes_doAutoJoypad(snes: *Snes) void {
    @memset(&snes.portAutoRead, 0);
    input_cycle(snes.input1);
    input_cycle(snes.input2);
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
    if (adr < 0x80) return @ptrCast(snes.apu.?.outPorts[adr & 3]);
    if (adr == 0x80) {
        const ret = snes.ram[snes.ramAdr];
        snes.ramAdr = (snes.ramAdr + 1) & 0x1ffff;
        return ret;
    }
    return snes.openBus;
}

pub export fn snes_writeBBus(snes: *Snes, adr: u8, val: u8) void {
    if (adr < 0x40) { ppu_write(snes.ppu, adr, val); return; }
    if (adr < 0x80) { snes_catchupApu(snes); @ptrCast(snes.apu.?.inPorts[adr & 3]) = val; return; }
    switch (adr) {
        0x80 => { snes.ram[snes.ramAdr] = val; snes.ramAdr = (snes.ramAdr + 1) & 0x1ffff; },
        0x81 => snes.ramAdr = (snes.ramAdr & 0x1ff00) | val,
        0x82 => snes.ramAdr = (snes.ramAdr & 0x100ff) | (val << 8),
        0x83 => snes.ramAdr = (snes.ramAdr & 0x0ffff) | ((val & 1) << 16),
        else => {},
    }
}

fn snes_readReg(snes: *Snes, adr: u16) u8 {
    return switch (adr) {
        0x4210 => { snes.inNmi = false; 0x2 | @as(u8, @intFromBool(snes.inNmi)) << 7 | (snes.openBus & 0x70) },
        0x4211 => { snes.inIrq = false; 0 | (snes.openBus & 0x7f) },
        0x4212 => @as(u8, @intFromBool(snes.autoJoyTimer > 0)) | @as(u8, @intFromBool(snes.hPos >= 1024)) << 6 | @as(u8, @intFromBool(snes.inVblank)) << 7 | (snes.openBus & 0x3e),
        0x4213 => @as(u8, @intFromBool(snes.ppuLatch)) << 7,
        0x4214 => @truncate(snes.divideResult & 0xff),
        0x4215 => @truncate(snes.divideResult >> 8),
        0x4216 => @truncate(snes.multiplyResult & 0xff),
        0x4217 => @truncate(snes.multiplyResult >> 8),
        0x4218, 0x421a, 0x421c, 0x421e => @truncate(snes.portAutoRead[@intCast((adr - 0x4218)/2)] & 0xff),
        0x4219, 0x421b, 0x421d, 0x421f => @truncate(snes.portAutoRead[@intCast((adr - 0x4219)/2)] >> 8),
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
        },
        0x4201 => { if ((val & 0x80) == 0 and snes.ppuLatch) { ppu_read(snes.ppu, 0x37); } snes.ppuLatch = (val & 0x80) != 0; },
        0x4202 => snes.multiplyA = val,
        0x4203 => snes.multiplyResult = snes.multiplyA * val,
        0x4204 => snes.divideA = (snes.divideA & 0xff00) | val,
        0x4205 => snes.divideA = (snes.divideA & 0x00ff) | (val << 8),
        0x4206 => if (val == 0) { snes.divideResult = 0xffff; snes.multiplyResult = snes.divideA; } else { snes.divideResult = snes.divideA / val; snes.multiplyResult = snes.divideA % val; },
        0x4207 => snes.hTimer = (snes.hTimer & 0x100) | val,
        0x4208 => snes.hTimer = (snes.hTimer & 0x0ff) | ((val & 1) << 8),
        0x4209 => snes.vTimer = (snes.vTimer & 0x100) | val,
        0x420a => snes.vTimer = (snes.vTimer & 0x0ff) | ((val & 1) << 8),
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
    } else if ((bank & ~@as(u8,1)) == 0x7e) {
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
            // latch line set via Input struct; input.zig exposes latchLine
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
