// Tier-B differential test for snes/cart.zig: links the pre-port snes/cart.c
// (symbols renamed with a c_ prefix via the preprocessor (-D), wired in build.zig's
// difftest step) against the ported Zig module and diffs their observable
// state over fixed-seed randomized read/write streams.
//
// The Cart struct layout mirrors snes/cart.h (C keeps ownership of it;
// zelda_cpu_infra.c pokes fields directly). The harness runs randomized
// streams of cart_read/cart_write across all three mapping types on
// identical rom/ram images and diffs every read's return value plus the
// post-stream sram contents. Both flavours read openBus from the same fake
// Snes image (openBus sits at byte offset 121 in struct Snes).
// cart.zig is not @import'ed here: its exports come from the linked object,
// so the test only needs the extern declarations and the mirrored layout.

const std = @import("std");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

// Mirrors struct Cart in snes/cart.h; Snes is opaque (only openBus is read,
// via the fake image below).
pub const Cart = extern struct {
    snes: ?*anyopaque,
    type: u8,
    rom: ?[*]u8,
    romSize: u32,
    ram: ?[*]u8,
    ramSize: u32,
};

// The Zig port's exported symbols resolve against the linked cart.o (the
// ported module); the C reference via the c_* externs (preprocessor-renamed).
extern fn cart_init(snes: ?*anyopaque) ?*Cart;
extern fn cart_free(cart: ?*Cart) void;
extern fn cart_reset(cart: *Cart) void;
extern fn cart_load(cart: *Cart, cart_type: c_int, rom: [*]u8, romSize: c_int, ramSize: c_int) void;
extern fn cart_read(cart: *Cart, bank: u8, adr: u16) u8;
extern fn cart_write(cart: *Cart, bank: u8, adr: u16, val: u8) void;
extern fn cart_saveload(cart: *Cart, func: ?*const fn (?*anyopaque, ?*anyopaque, usize) callconv(.c) void, ctx: ?*anyopaque) void;

extern fn c_cart_init(snes: ?*anyopaque) ?*Cart;
extern fn c_cart_free(cart: ?*Cart) void;
extern fn c_cart_reset(cart: *Cart) void;
extern fn c_cart_load(cart: *Cart, cart_type: c_int, rom: [*]u8, romSize: c_int, ramSize: c_int) void;
extern fn c_cart_read(cart: *Cart, bank: u8, adr: u16) u8;
extern fn c_cart_write(cart: *Cart, bank: u8, adr: u16, val: u8) void;
extern fn c_cart_saveload(cart: *Cart, func: ?*const fn (?*anyopaque, ?*anyopaque, usize) callconv(.c) void, ctx: ?*anyopaque) void;

var prng: ?std.Random.DefaultPrng = null;
fn rnd() std.Random {
    if (prng == null)
        prng = std.Random.DefaultPrng.init(0x5ca77ab1);
    return prng.?.random();
}

var c_openbus: u8 = 0;
var z_openbus: u8 = 0;

// One fake Snes image per flavour: an opaque buffer with openBus at its
// snes.h offset (121). Kept separate so a buggy port scribbling on snes
// state can't hide behind the shared byte.
var c_snes_buf: [128]u8 = undefined;
var z_snes_buf: [128]u8 = undefined;

fn resetSnesImages(open_bus: u8) void {
    c_snes_buf = [_]u8{0} ** 128;
    z_snes_buf = [_]u8{0} ** 128;
    c_snes_buf[121] = open_bus;
    z_snes_buf[121] = open_bus;
}

const rom_cap = 0x400000;
const ram_cap = 0x10000;

var c_rom: [rom_cap]u8 = undefined;
var z_rom: [rom_cap]u8 = undefined;
var c_ram: [ram_cap]u8 = undefined;
var z_ram: [ram_cap]u8 = undefined;

// Diff one (type, romSize, ramSize) configuration over a randomized op
// stream. Rom contents are identical across flavours; sram starts zeroed
// like after cart_load.
fn runStreamAndDiff(cart_type: u8, rom_size: u32, ram_size: u32, ops: []const u8) !void {
    rnd().bytes(c_rom[0..rom_size]);
    @memcpy(z_rom[0..rom_size], c_rom[0..rom_size]);
    @memset(c_ram[0..ram_size], 0);
    @memset(z_ram[0..ram_size], 0);
    resetSnesImages(rnd().int(u8));

    var c_cart: Cart = .{
        .snes = @ptrCast(&c_snes_buf),
        .type = cart_type,
        .rom = &c_rom,
        .romSize = rom_size,
        .ram = if (ram_size > 0) &c_ram else null,
        .ramSize = ram_size,
    };
    var z_cart: Cart = .{
        .snes = @ptrCast(&z_snes_buf),
        .type = cart_type,
        .rom = &z_rom,
        .romSize = rom_size,
        .ram = if (ram_size > 0) &z_ram else null,
        .ramSize = ram_size,
    };

    for (ops, 0..) |op, i| {
        const bank: u8 = op ^ @as(u8, @truncate(i));
        const adr: u16 = (@as(u16, op) << 8) | @as(u16, op *% 0x3D) +% @as(u16, @truncate(i *% 7));
        const val: u8 = op *% 0x1F +% @as(u8, @truncate(i));
        if (op & 1 == 0) {
            const c_ret = c_cart_read(&c_cart, bank, adr);
            const z_ret = cart_read(&z_cart, bank, adr);
            if (c_ret != z_ret) {
                std.debug.print("op {d}: type {d} read {X:0>2}:{X:0>4}: c=0x{X:0>2} z=0x{X:0>2}\n", .{ i, cart_type, bank, adr, c_ret, z_ret });
                return error.ReadMismatch;
            }
        } else {
            c_cart_write(&c_cart, bank, adr, val);
            cart_write(&z_cart, bank, adr, val);
        }
    }

    if (ram_size > 0 and !std.mem.eql(u8, c_ram[0..ram_size], z_ram[0..ram_size])) {
        for (c_ram[0..ram_size], 0..) |b, i| {
            if (b != z_ram[i]) {
                std.debug.print("type {d} sram[{X:0>4}]: c=0x{X:0>2} z=0x{X:0>2}\n", .{ cart_type, i, b, z_ram[i] });
                break;
            }
        }
        return error.SramMismatch;
    }
    try expectEqualSlices(u8, c_ram[0..ram_cap], z_ram[0..ram_cap]);
    try expectEqualSlices(u8, &c_snes_buf, &z_snes_buf);
}

test "diff read/write streams over all three cart types" {
    const rom_sizes = [_]u32{ 0x8000, 0x80000, 0x100000, 0x400000 };
    const ram_sizes = [_]u32{ 0, 0x2000, 0x8000, 0x10000 };
    var iter: usize = 0;
    while (iter < 2000) : (iter += 1) {
        const cart_type: u8 = rnd().intRangeAtMost(u8, 0, 2);
        const rom_size = rom_sizes[rnd().intRangeAtMost(usize, 0, rom_sizes.len - 1)];
        const ram_size = ram_sizes[rnd().intRangeAtMost(usize, 0, ram_sizes.len - 1)];
        var ops_buf: [128]u8 = undefined;
        const n = rnd().intRangeAtMost(usize, 1, ops_buf.len);
        for (ops_buf[0..n]) |*op| op.* = rnd().int(u8);
        try runStreamAndDiff(cart_type, rom_size, ram_size, ops_buf[0..n]);
    }
}

// Captured callback results for the saveload diff (file scope: Zig
// containers can't capture locals).
var seen_c: Seen = .{};
var seen_z: Seen = .{};
const Seen = struct { data: ?*anyopaque = null, size: usize = 0 };

fn saveloadCbC(ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void {
    _ = ctx;
    seen_c = .{ .data = data, .size = data_size };
}

fn saveloadCbZ(ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void {
    _ = ctx;
    seen_z = .{ .data = data, .size = data_size };
}

test "diff init/load/reset/saveload lifecycle" {
    seen_c = .{};
    seen_z = .{};

    resetSnesImages(0x5A);
    const c_cart = c_cart_init(@ptrCast(&c_snes_buf)) orelse return error.OutOfMemory;
    defer c_cart_free(c_cart);
    const z_cart = cart_init(@ptrCast(&z_snes_buf)) orelse return error.OutOfMemory;
    defer cart_free(z_cart);

    try expectEqual(c_cart.type, z_cart.type);
    try expectEqual(c_cart.romSize, z_cart.romSize);
    try expectEqual(c_cart.ramSize, z_cart.ramSize);
    try expectEqual(@as(?[*]u8, null), z_cart.rom);
    try expectEqual(false, z_cart.ram == null);

    // load a LoROM image: identical rom contents, identical observable state
    const rom_size: usize = 0x80000;
    rnd().bytes(c_rom[0..rom_size]);
    @memcpy(z_rom[0..rom_size], c_rom[0..rom_size]);
    c_cart_load(c_cart, 1, &c_rom, rom_size, 0x2000);
    cart_load(z_cart, 1, &z_rom, rom_size, 0x2000);
    try expectEqual(c_cart.type, z_cart.type);
    try expectEqual(c_cart.romSize, z_cart.romSize);
    try expectEqual(c_cart.ramSize, z_cart.ramSize);
    try expectEqualSlices(u8, c_cart.rom.?[0..rom_size], z_cart.rom.?[0..rom_size]);
    try expectEqualSlices(u8, c_cart.ram.?[0..0x2000], z_cart.ram.?[0..0x2000]);

    // reset zeroes both flavours' sram identically (it is already zeroed by
    // load; poke junk first to make reset observable)
    c_cart.ram.?[0] = 0xAA;
    z_cart.ram.?[0] = 0xAA;
    c_cart_reset(c_cart);
    cart_reset(z_cart);
    try expectEqualSlices(u8, c_cart.ram.?[0..0x2000], z_cart.ram.?[0..0x2000]);

    // saveload passes the same (ram, ramSize) triple to the callback
    c_cart_saveload(c_cart, saveloadCbC, null);
    cart_saveload(z_cart, saveloadCbZ, null);
    try expectEqual(@as(?*anyopaque, @ptrCast(c_cart.ram)), seen_c.data);
    try expectEqual(@as(?*anyopaque, @ptrCast(z_cart.ram)), seen_z.data);
    try expectEqual(seen_c.size, seen_z.size);
}
