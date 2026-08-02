// Tier-A unit tests for snes/cart.zig: golden-value checks for the LoROM /
// HiROM address decoders and the init/load/reset/saveload lifecycle, using
// reference behavior from the pre-port snes/cart.c. The Cart layout mirrors
// snes/cart.h; the tests drive it through the exported C-ABI functions only.

const std = @import("std");
const cart = @import("cart.zig");

const expectEqual = std.testing.expectEqual;

const Cart = cart.Cart;

// Stand-in for struct Snes in the tests: cart.zig only reads openBus, so a
// buffer with the byte at its snes.h offset (121) suffices.
const openbus_off = 121;
var fake_snes_buf: [128]u8 = undefined;

fn fakeSnes(open_bus: u8) *cart.Snes {
    fake_snes_buf = [_]u8{0} ** 128;
    fake_snes_buf[openbus_off] = open_bus;
    return @ptrCast(@alignCast(&fake_snes_buf));
}

fn makeCart(snes: *cart.Snes, cart_type: u8, rom: ?[*]u8, rom_size: u32, ram: ?[*]u8, ram_size: u32) Cart {
    return .{
        .snes = snes,
        .type = cart_type,
        .rom = rom,
        .romSize = rom_size,
        .ram = ram,
        .ramSize = ram_size,
    };
}

test "cart_init seeds type/rom/ram like cart.c" {
    const c = cart.cart_init(fakeSnes(0)) orelse return error.OutOfMemory;
    defer cart.cart_free(c);
    try expectEqual(@as(u8, 0), c.type);
    try expectEqual(@as(?[*]u8, null), c.rom);
    try expectEqual(@as(u32, 0), c.romSize);
    try expectEqual(@as(u32, 0x2000), c.ramSize);
    try expectEqual(false, c.ram == null);
}

test "cart_load copies the rom and zeroes sram" {
    const c = cart.cart_init(fakeSnes(0)) orelse return error.OutOfMemory;
    defer cart.cart_free(c);
    c.ram.?[0] = 0xAA;
    c.ram.?[c.ramSize - 1] = 0xBB;

    var rom_buf = [_]u8{0} ** 0x8000;
    rom_buf[0x123] = 0x5A;
    rom_buf[0x7FFF] = 0xC3;
    cart.cart_load(c, 1, &rom_buf, rom_buf.len, 0x2000);

    try expectEqual(@as(u8, 1), c.type);
    try expectEqual(@as(u32, 0x8000), c.romSize);
    try expectEqual(@as(u8, 0x5A), c.rom.?[0x123]);
    try expectEqual(@as(u8, 0xC3), c.rom.?[0x7FFF]);
    // load zeroes the whole sram, not just the poked bytes
    try expectEqual(@as(u8, 0), c.ram.?[0]);
    try expectEqual(@as(u8, 0), c.ram.?[0x1FFF]);
}

test "cart_load frees the previous rom and takes the new one" {
    const c = cart.cart_init(fakeSnes(0)) orelse return error.OutOfMemory;
    defer cart.cart_free(c);
    var rom_a = [_]u8{0x11} ** 0x8000;
    var rom_b = [_]u8{0x22} ** 0x10000;
    cart.cart_load(c, 1, &rom_a, rom_a.len, 0x2000);
    cart.cart_load(c, 2, &rom_b, rom_b.len, 0x2000);
    try expectEqual(@as(u8, 2), c.type);
    try expectEqual(@as(u32, 0x10000), c.romSize);
    try expectEqual(@as(u8, 0x22), c.rom.?[0x8000]);
}

test "cart_reset zeroes sram only when present" {
    var ram_buf = [_]u8{0xFF} ** 0x2000;
    var c = makeCart(fakeSnes(0), 0, null, 0, &ram_buf, 0x2000);
    cart.cart_reset(&c);
    try expectEqual(@as(u8, 0), ram_buf[0]);
    try expectEqual(@as(u8, 0), ram_buf[0x1FFF]);

    // ramSize 0 (no battery): reset is a no-op, nothing to touch
    var c0 = makeCart(fakeSnes(0), 0, null, 0, null, 0);
    cart.cart_reset(&c0);
}

test "cart_saveload hands ctx, ram pointer and ramSize to the callback" {
    var ram_buf = [_]u8{0x77} ** 0x2000;
    var c = makeCart(fakeSnes(0), 1, null, 0, &ram_buf, 0x2000);
    var seen = struct {
        ctx: ?*anyopaque = null,
        data: ?*anyopaque = null,
        size: usize = 0,
    }{};
    const cb = struct {
        fn run(ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void {
            const s: *@TypeOf(seen) = @ptrCast(@alignCast(ctx));
            s.ctx = ctx;
            s.data = data;
            s.size = data_size;
        }
    }.run;
    cart.cart_saveload(&c, cb, &seen);
    try expectEqual(@as(?*anyopaque, @ptrCast(&seen)), seen.ctx);
    try expectEqual(@as(?*anyopaque, @ptrCast(&ram_buf)), seen.data);
    try expectEqual(@as(usize, 0x2000), seen.size);
}

test "type 0 cart: reads return openBus, writes go nowhere" {
    var ram_buf = [_]u8{0x55} ** 0x2000;
    var c = makeCart(fakeSnes(0xAB), 0, null, 0, &ram_buf, 0x2000);
    try expectEqual(@as(u8, 0xAB), cart.cart_read(&c, 0x00, 0x0000));
    try expectEqual(@as(u8, 0xAB), cart.cart_read(&c, 0x80, 0x8000));
    try expectEqual(@as(u8, 0xAB), cart.cart_read(&c, 0x70, 0x0000));
    cart.cart_write(&c, 0x70, 0x0000, 0x99);
    try expectEqual(@as(u8, 0x55), ram_buf[0]);
}

test "unknown cart type: reads return openBus, writes ignored" {
    var rom_buf = [_]u8{0x33} ** 0x8000;
    var ram_buf = [_]u8{0x55} ** 0x2000;
    var c = makeCart(fakeSnes(0xCD), 3, &rom_buf, 0x8000, &ram_buf, 0x2000);
    try expectEqual(@as(u8, 0xCD), cart.cart_read(&c, 0x00, 0x8000));
    try expectEqual(@as(u8, 0xCD), cart.cart_read(&c, 0x70, 0x1234));
    cart.cart_write(&c, 0x70, 0x1234, 0x99);
    try expectEqual(@as(u8, 0x55), ram_buf[0x1234]);
}

test "LoROM: adr >= 0x8000 reads rom at (bank << 15 | adr & 0x7fff)" {
    var rom_buf = [_]u8{0} ** 0x80000;
    rom_buf[0x0123] = 0x11; // bank 0, adr 0x8123
    rom_buf[0x2456] = 0x22; // bank 0, adr 0xA456
    rom_buf[0x8001] = 0x33; // bank 1, adr 0x8001
    var c = makeCart(fakeSnes(0xEE), 1, &rom_buf, 0x80000, null, 0);
    try expectEqual(@as(u8, 0x11), cart.cart_read(&c, 0x00, 0x8123));
    try expectEqual(@as(u8, 0x22), cart.cart_read(&c, 0x00, 0xA456));
    try expectEqual(@as(u8, 0x33), cart.cart_read(&c, 0x01, 0x8001));
    // high banks mirror through the romSize mask (0x80 << 15 wraps)
    try expectEqual(@as(u8, 0x11), cart.cart_read(&c, 0x80, 0x8123));
}

test "LoROM: banks 70-7d and f0-ff, adr < 0x8000 hit sram" {
    var rom_buf = [_]u8{0} ** 0x80000;
    var ram_buf = [_]u8{0} ** 0x8000;
    ram_buf[0x0005] = 0x44; // bank 70, adr 0x0005
    ram_buf[0x0102] = 0x55; // bank 70, adr 0x0102
    var c = makeCart(fakeSnes(0xEE), 1, &rom_buf, 0x80000, &ram_buf, 0x8000);
    try expectEqual(@as(u8, 0x44), cart.cart_read(&c, 0x70, 0x0005));
    try expectEqual(@as(u8, 0x55), cart.cart_read(&c, 0x70, 0x0102));
    // bank 71 maps through (bank & 0xf) << 15: 0x8000 + adr, masked to 8K
    ram_buf[0x0007] = 0x66;
    try expectEqual(@as(u8, 0x66), cart.cart_read(&c, 0x71, 0x8007 & 0x7FFF));
    // banks 7e/7f aren't in the sram range; the bank & 0x40 catch-all below
    // mirrors rom instead (on real hardware these banks are console WRAM and
    // the access never reaches the cart, so the decoder doesn't special-case
    // them)
    rom_buf[(0x7E << 15) & 0x7FFFF] = 0x77;
    rom_buf[(0x7F << 15) & 0x7FFFF] = 0x78;
    try expectEqual(@as(u8, 0x77), cart.cart_read(&c, 0x7E, 0x0000));
    try expectEqual(@as(u8, 0x78), cart.cart_read(&c, 0x7F, 0x0000));
    // bank f0 reads sram too
    try expectEqual(@as(u8, 0x55), cart.cart_read(&c, 0xF0, 0x0102));
}

test "LoROM: write goes to sram for banks 70-7d and f1-ff (not f0), else nowhere" {
    var rom_buf = [_]u8{0} ** 0x80000;
    var ram_buf = [_]u8{0} ** 0x8000;
    var c = makeCart(fakeSnes(0xEE), 1, &rom_buf, 0x80000, &ram_buf, 0x8000);
    cart.cart_write(&c, 0x70, 0x0123, 0x42);
    try expectEqual(@as(u8, 0x42), ram_buf[0x0123]);
    // cart.c's write decoder uses bank > 0xf0 (reads use bank >= 0xf0):
    // bank f0 writes are dropped on the floor.
    cart.cart_write(&c, 0xF0, 0x0123, 0x99);
    try expectEqual(@as(u8, 0x42), ram_buf[0x0123]);
    cart.cart_write(&c, 0xF1, 0x0123, 0x99);
    try expectEqual(@as(u8, 0x99), ram_buf[0x0123]);
    // banks 7e/7f are console WRAM: cart ignores the write
    cart.cart_write(&c, 0x7E, 0x0123, 0x77);
    try expectEqual(@as(u8, 0x99), ram_buf[0x0123]);
    // adr >= 0x8000 is rom space: read-only
    cart.cart_write(&c, 0x70, 0x8123, 0x55);
    try expectEqual(@as(u8, 0), rom_buf[(0x70 << 15 | 0x0123) & (0x80000 - 1)]);
}

test "LoROM: bank 40-7f / c0-ff mirror rom for adr < 0x8000, other low reads are openBus" {
    var rom_buf = [_]u8{0} ** 0x80000;
    rom_buf[0x1234] = 0x88; // bank 40, adr 0x1234 (0x40 << 15 wraps to bank 0)
    rom_buf[0x5678 & 0x7FFF] = 0x99; // bank c0 maps to bank 0 after masking
    var c = makeCart(fakeSnes(0xEE), 1, &rom_buf, 0x80000, null, 0);
    try expectEqual(@as(u8, 0x88), cart.cart_read(&c, 0x40, 0x1234));
    try expectEqual(@as(u8, 0x99), cart.cart_read(&c, 0xC0, 0x5678));
    // bank 00-3f without the 0x40 bit: not rom below 0x8000
    try expectEqual(@as(u8, 0xEE), cart.cart_read(&c, 0x00, 0x1234));
    try expectEqual(@as(u8, 0xEE), cart.cart_read(&c, 0x00, 0x7FFF));
}

test "HiROM: banks 00-3f adr 6000-7fff hit sram, adr >= 0x8000 or bank >= 0x40 hit rom" {
    var rom_buf = [_]u8{0} ** 0x400000;
    var ram_buf = [_]u8{0} ** 0x2000;
    var c = makeCart(fakeSnes(0xEE), 2, &rom_buf, 0x400000, &ram_buf, 0x2000);

    // sram window: (bank & 0x3f) << 13 | (adr & 0x1fff)
    ram_buf[0x0010] = 0x12;
    try expectEqual(@as(u8, 0x12), cart.cart_read(&c, 0x20, 0x6010));
    // outside the sram window: openBus (bank < 0x40, adr < 0x6000)
    try expectEqual(@as(u8, 0xEE), cart.cart_read(&c, 0x20, 0x5FFF));
    try expectEqual(@as(u8, 0xEE), cart.cart_read(&c, 0x00, 0x0000));
    // rom window: (bank & 0x3f) << 16 | adr
    rom_buf[(0x02 << 16) | 0x8123] = 0x34;
    try expectEqual(@as(u8, 0x34), cart.cart_read(&c, 0x02, 0x8123));
    // rom window: (bank & 0x3f) << 16 | adr — bank 0x40 & 0x3f wraps to 0
    rom_buf[0x0000] = 0x56;
    try expectEqual(@as(u8, 0x56), cart.cart_read(&c, 0x40, 0x0000));
    // high banks wrap via bank &= 0x7f then romSize mask
    try expectEqual(@as(u8, 0x34), cart.cart_read(&c, 0x82, 0x8123));
}

test "HiROM: writes go to sram only in the 6000-7fff window" {
    var rom_buf = [_]u8{0} ** 0x400000;
    var ram_buf = [_]u8{0} ** 0x2000;
    var c = makeCart(fakeSnes(0xEE), 2, &rom_buf, 0x400000, &ram_buf, 0x2000);
    cart.cart_write(&c, 0x30, 0x6123, 0x66);
    try expectEqual(@as(u8, 0x66), ram_buf[0x0123]);
    // bank 80-ff mirror: 0xB0 & 0x7f = 0x30 hits the same sram cell
    cart.cart_write(&c, 0xB0, 0x6123, 0x77);
    try expectEqual(@as(u8, 0x77), ram_buf[0x0123]);
    // outside the window: dropped
    cart.cart_write(&c, 0x30, 0x8123, 0x99);
    try expectEqual(@as(u8, 0), rom_buf[(0x30 << 16) | 0x8123]);
    cart.cart_write(&c, 0x40, 0x6123, 0x99);
    try expectEqual(@as(u8, 0x77), ram_buf[0x0123]);
}
