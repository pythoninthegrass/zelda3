// Port of snes/cart.c: cartridge ROM/SRAM mapping — the LoROM/HiROM address
// decoders behind cart_read/cart_write, plus load/reset/saveload. Every
// function keeps its exact C-ABI name and signature (callconv(.c), C-pointer
// types) so the remaining .c callers (snes.c, snes_other.c) link unchanged.
// The Cart struct layout itself stays C-owned in snes/cart.h —
// zelda_cpu_infra.c pokes rom/romSize/ram/ramSize directly — so this module
// mirrors that layout field-for-field rather than redefining it.

const std = @import("std");

// cart.c only reads snes->openBus; the prefix mirrors struct Snes in
// snes/snes.h field-for-field up to openBus, with the subsystem pointers
// opaque (only ever dereferenced by their own modules).
pub const Snes = extern struct {
    cpu: ?*anyopaque,
    apu: ?*anyopaque,
    ppu: ?*anyopaque,
    dma: ?*anyopaque,
    cart: ?*Cart,
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
    // snes.h continues (ram, ramAdr); cart.c never touches those.
};

// Mirrors struct Cart in snes/cart.h (C keeps ownership of the layout;
// zelda_cpu_infra.c reads rom/ram through it directly).
pub const Cart = extern struct {
    snes: ?*Snes,
    type: u8,
    rom: ?[*]u8,
    romSize: u32,
    ram: ?[*]u8,
    ramSize: u32,
};

// Same type as SaveLoadFunc in snes/saveload.h.
const SaveLoadFunc = fn (ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void;

extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;

// See input.zig: dead-code stub for Zig 0.16's std.start analysis; the C
// main in src/main.c is the real entry point.
pub fn main() callconv(.c) c_int {
    return 0;
}

pub export fn cart_init(snes: ?*Snes) ?*Cart {
    const cart: *Cart = @ptrCast(@alignCast(malloc(@sizeOf(Cart)) orelse return null));
    cart.snes = snes;
    cart.type = 0;
    cart.rom = null;
    cart.romSize = 0;
    cart.ramSize = 0x2000;
    cart.ram = @ptrCast(@alignCast(malloc(cart.ramSize)));
    return cart;
}

pub export fn cart_free(cart: ?*Cart) void {
    free(cart);
}

pub export fn cart_reset(cart: *Cart) void {
    if (cart.ramSize > 0 and cart.ram != null) @memset(cart.ram.?[0..cart.ramSize], 0); // for now
}

pub export fn cart_saveload(cart: *Cart, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) void {
    func.?(ctx, cart.ram, cart.ramSize);
}

pub export fn cart_load(cart: *Cart, cart_type: c_int, rom: [*]u8, romSize: c_int, ramSize: c_int) void {
    cart.type = @truncate(@as(c_uint, @bitCast(cart_type)));
    if (cart.rom != null) free(cart.rom);
    const rom_size: usize = @intCast(romSize);
    cart.rom = @ptrCast(@alignCast(malloc(rom_size)));
    cart.romSize = @intCast(romSize);
    // C's assert(): both operands convert to unsigned int before comparing.
    std.debug.assert(@as(u32, @bitCast(ramSize)) == cart.ramSize);
    const ram_size: usize = @intCast(ramSize);
    if (cart.ram != null) @memset(cart.ram.?[0..ram_size], 0);
    cart.ramSize = @intCast(ramSize);
    @memcpy(cart.rom.?[0..rom_size], rom[0..rom_size]);
}

pub export fn cart_read(cart: *Cart, bank: u8, adr: u16) u8 {
    if (cart.type == 1)
        return cart_readLorom(cart, bank, adr);

    switch (cart.type) {
        0 => return cart.snes.?.openBus,
        1, 2 => return cart_readHirom(cart, bank, adr),
        else => {},
    }
    return cart.snes.?.openBus;
}

pub export fn cart_write(cart: *Cart, bank: u8, adr: u16, val: u8) void {
    switch (cart.type) {
        0 => {},
        1 => cart_writeLorom(cart, bank, adr, val),
        2 => cart_writeHirom(cart, bank, adr, val),
        else => {},
    }
}

fn cart_readLorom(cart: *Cart, bank: u8, adr: u16) u8 {
    if (adr >= 0x8000) {
        // adr 8000-ffff in all banks or all addresses in banks 40-7f and c0-ff
        return cart.rom.?[((@as(u32, bank) << 15) | (adr & 0x7fff)) & (cart.romSize - 1)];
    }
    if (((bank >= 0x70 and bank < 0x7e) or bank >= 0xf0) and adr < 0x8000 and cart.ramSize > 0) {
        // banks 70-7e and f0-ff, adr 0000-7fff
        return cart.ram.?[((@as(u32, bank & 0xf) << 15) | adr) & (cart.ramSize - 1)];
    }
    if (bank & 0x40 != 0) {
        // adr 8000-ffff in all banks or all addresses in banks 40-7f and c0-ff
        return cart.rom.?[((@as(u32, bank) << 15) | (adr & 0x7fff)) & (cart.romSize - 1)];
    }
    return cart.snes.?.openBus;
}

fn cart_writeLorom(cart: *Cart, bank: u8, adr: u16, val: u8) void {
    if (((bank >= 0x70 and bank < 0x7e) or bank > 0xf0) and adr < 0x8000 and cart.ramSize > 0) {
        // banks 70-7e and f0-ff, adr 0000-7fff
        cart.ram.?[((@as(u32, bank & 0xf) << 15) | adr) & (cart.ramSize - 1)] = val;
    }
}

fn cart_readHirom(cart: *Cart, bank_arg: u8, adr: u16) u8 {
    const bank = bank_arg & 0x7f;
    if (bank < 0x40 and adr >= 0x6000 and adr < 0x8000 and cart.ramSize > 0) {
        // banks 00-3f and 80-bf, adr 6000-7fff
        return cart.ram.?[((@as(u32, bank & 0x3f) << 13) | (adr & 0x1fff)) & (cart.ramSize - 1)];
    }
    if (adr >= 0x8000 or bank >= 0x40) {
        // adr 8000-ffff in all banks or all addresses in banks 40-7f and c0-ff
        return cart.rom.?[((@as(u32, bank & 0x3f) << 16) | adr) & (cart.romSize - 1)];
    }
    return cart.snes.?.openBus;
}

fn cart_writeHirom(cart: *Cart, bank_arg: u8, adr: u16, val: u8) void {
    const bank = bank_arg & 0x7f;
    if (bank < 0x40 and adr >= 0x6000 and adr < 0x8000 and cart.ramSize > 0) {
        // banks 00-3f and 80-bf, adr 6000-7fff
        cart.ram.?[((@as(u32, bank & 0x3f) << 13) | (adr & 0x1fff)) & (cart.ramSize - 1)] = val;
    }
}
