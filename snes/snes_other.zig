// Port of snes/snes_other.c: ROM loading — scoring the four possible SNES
// header locations to detect LoROM/HiROM/headered-ness, then expanding the
// ROM to a power-of-two size and handing it to the cart. Every exported
// function keeps its exact C-ABI name and signature (callconv(.c), C-pointer
// types) so the remaining .c callers (zelda_cpu_infra.c) link unchanged.
//
// cart_load lives in cart.zig and snes_reset lives in snes.zig; this file
// only ever touches snes->cart, so the local Snes mirror below is truncated
// to that one field (see cart.zig/snes.zig file headers for the same
// truncation convention). Cpu/Apu/Ppu/Dma/Cart stay opaque: this file never
// dereferences their fields, only forwards the cart pointer on to cart_load.

const std = @import("std");

const Cpu = opaque {};
const Apu = opaque {};
const Ppu = opaque {};
const Dma = opaque {};
const Cart = opaque {};

// Mirrors struct Snes in snes/snes.h up through cart (see file header).
pub const Snes = extern struct {
    cpu: ?*Cpu,
    apu: ?*Apu,
    ppu: ?*Ppu,
    dma: ?*Dma,
    cart: ?*Cart,
};

extern fn cart_load(cart: *Cart, cart_type: c_int, rom: [*]u8, romSize: c_int, ramSize: c_int) callconv(.c) void;
extern fn snes_reset(snes: *Snes, hard: bool) callconv(.c) void;
extern fn printf(fmt: [*:0]const u8, ...) callconv(.c) c_int;
extern fn malloc(size: usize) callconv(.c) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) callconv(.c) void;

const CartHeader = struct {
    // normal header
    headerVersion: u8 = 0, // 1, 2, 3
    name: [22]u8 = undefined, // $ffc0-$ffd4 (max 21 bytes + \0), $ffd4=$00: header V2
    speed: u8 = 0, // $ffd5.7-4 (always 2 or 3)
    type: u8 = 0, // $ffd5.3-0
    coprocessor: u8 = 0, // $ffd6.7-4
    chips: u8 = 0, // $ffd6.3-0
    romSize: u32 = 0, // $ffd7 (0x400 << x)
    ramSize: u32 = 0, // $ffd8 (0x400 << x)
    region: u8 = 0, // $ffd9 (also NTSC/PAL)
    maker: u8 = 0, // $ffda ($33: header V3)
    version: u8 = 0, // $ffdb
    checksumComplement: u16 = 0, // $ffdc,$ffdd
    checksum: u16 = 0, // $ffde,$ffdf
    // v2/v3 (v2 only exCoprocessor)
    makerCode: [3]u8 = undefined, // $ffb0,$ffb1: (2 chars + \0)
    gameCode: [5]u8 = undefined, // $ffb2-$ffb5: (4 chars + \0)
    flashSize: u32 = 0, // $ffbc (0x400 << x)
    exRamSize: u32 = 0, // $ffbd (0x400 << x) (used for GSU?)
    specialVersion: u8 = 0, // $ffbe
    exCoprocessor: u8 = 0, // $ffbf (if coprocessor = $f)
    // calculated stuff
    score: i16 = -50, // score for header, to see which mapping is most likely
    pal: bool = false, // if this is a rom for PAL regions instead of NTSC
    cartType: u8 = 0, // calculated type
};

// C shifts `0x400 << byte` where byte can be any of the 256 values a raw
// header candidate might contain; only the chosen header's shift amount is
// ever real (small), the rest are garbage from unused candidates and only
// their score (not romSize/ramSize) affects selection. Truncating to a
// 5-bit shift amount mirrors the x86 SHL masking the original C relied on.
fn shift1k(exponent: u8) u32 {
    return @as(u32, 0x400) << @as(u5, @truncate(exponent));
}

fn readHeader(data: [*]const u8, location: usize, header: *CartHeader) void {
    // read name, TODO: non-ASCII names?
    for (0..21) |i| {
        const ch = data[location + i];
        header.name[i] = if (ch >= 0x20 and ch < 0x7f) ch else '.';
    }
    header.name[21] = 0;
    // read rest
    header.speed = data[location + 0x15] >> 4;
    header.type = data[location + 0x15] & 0xf;
    header.coprocessor = data[location + 0x16] >> 4;
    header.chips = data[location + 0x16] & 0xf;
    header.romSize = shift1k(data[location + 0x17]);
    header.ramSize = shift1k(data[location + 0x18]);
    header.region = data[location + 0x19];
    header.maker = data[location + 0x1a];
    header.version = data[location + 0x1b];
    header.checksumComplement = (@as(u16, data[location + 0x1d]) << 8) + data[location + 0x1c];
    header.checksum = (@as(u16, data[location + 0x1f]) << 8) + data[location + 0x1e];
    // read v3 and/or v2
    header.headerVersion = 1;
    if (header.maker == 0x33) {
        header.headerVersion = 3;
        // maker code
        for (0..2) |i| {
            const ch = data[location - 0x10 + i];
            header.makerCode[i] = if (ch >= 0x20 and ch < 0x7f) ch else '.';
        }
        header.makerCode[2] = 0;
        // game code
        for (0..4) |i| {
            const ch = data[location - 0xe + i];
            header.gameCode[i] = if (ch >= 0x20 and ch < 0x7f) ch else '.';
        }
        header.gameCode[4] = 0;
        header.flashSize = shift1k(data[location - 4]);
        header.exRamSize = shift1k(data[location - 3]);
        header.specialVersion = data[location - 2];
        header.exCoprocessor = data[location - 1];
    } else if (data[location + 0x14] == 0) {
        header.headerVersion = 2;
        header.exCoprocessor = data[location - 1];
    }
    // get region
    header.pal = (header.region >= 0x2 and header.region <= 0xc) or header.region == 0x11;
    header.cartType = if (location < 0x9000) 1 else 2;
    // get score
    // TODO: check name, maker/game-codes (if V3) for ASCII, more vectors,
    //   more first opcode, rom-sizes (matches?), type (matches header location?)
    var score: i16 = 0;
    score += if (header.speed == 2 or header.speed == 3) 5 else -4;
    score += if (header.type <= 3 or header.type == 5) 5 else -2;
    score += if (header.coprocessor <= 5 or header.coprocessor >= 0xe) 5 else -2;
    score += if (header.chips <= 6 or header.chips == 9 or header.chips == 0xa) 5 else -2;
    score += if (header.region <= 0x14) 5 else -2;
    // C promotes both uint16_t operands to int before adding, so this never
    // overflows; widen to u32 to match instead of wrapping at 16 bits.
    score += if (@as(u32, header.checksum) + @as(u32, header.checksumComplement) == 0xffff) 8 else -6;
    const resetVector = @as(u16, data[location + 0x3c]) | (@as(u16, data[location + 0x3d]) << 8);
    score += if (resetVector >= 0x8000) 8 else -20;
    // check first opcode after reset
    const opcode = data[location + 0x40 - 0x8000 + (resetVector & 0x7fff)];
    if (opcode == 0x78 or opcode == 0x18) {
        // sei, clc (for clc:xce)
        score += 6;
    }
    if (opcode == 0x4c or opcode == 0x5c or opcode == 0x9c) {
        // jmp abs, jml abl, stz abs
        score += 3;
    }
    if (opcode == 0x00 or opcode == 0xff or opcode == 0xdb) {
        // brk, sbc alx, stp
        score -= 6;
    }
    header.score = score;
}

pub export fn snes_loadRom(snes: *Snes, data_arg: [*]u8, length_arg: c_int) bool {
    var data = data_arg;
    var length = length_arg;
    // if smaller than smallest possible, don't load
    if (length < 0x8000) {
        _ = printf("Failed to load rom: rom to small (%d bytes)\n", length);
        return false;
    }
    // check headers
    var headers: [4]CartHeader = .{ .{}, .{}, .{}, .{} };
    if (length >= 0x8000) readHeader(data, 0x7fc0, &headers[0]);
    if (length >= 0x8200) readHeader(data, 0x81c0, &headers[1]);
    if (length >= 0x10000) readHeader(data, 0xffc0, &headers[2]);
    if (length >= 0x10200) readHeader(data, 0x101c0, &headers[3]);
    // see which it is
    var max: i16 = 0;
    var used: usize = 0;
    for (0..4) |i| {
        if (headers[i].score > max) {
            max = headers[i].score;
            used = i;
        }
    }
    if (used & 1 != 0) {
        // odd-numbered ones are for headered roms
        data += 0x200; // move pointer past header
        length -= 0x200; // and subtract from size
    }
    // check if we can load it
    if (headers[used].cartType > 2) {
        _ = printf("Failed to load rom: unsupported type (%d)\n", headers[used].cartType);
        return false;
    }
    // expand to a power of 2
    var newLength: c_int = 0x8000;
    while (length > newLength) newLength *= 2;
    const newData: [*]u8 = @ptrCast(malloc(@intCast(newLength)) orelse return false);
    @memcpy(newData[0..@intCast(length)], data[0..@intCast(length)]);
    var chunk: c_int = 1;
    while (length != newLength) {
        if (length & chunk != 0) {
            @memcpy(newData[@intCast(length)..@intCast(length + chunk)], newData[@intCast(length - chunk)..@intCast(length)]);
            length += chunk;
        }
        chunk *= 2;
    }
    // load it
    _ = printf("Loaded %s rom\n\"%s\"\n", if (headers[used].cartType == 2) "HiROM" else "LoROM", &headers[used].name);
    cart_load(
        snes.cart.?,
        headers[used].cartType,
        newData,
        newLength,
        if (headers[used].chips > 0) @bitCast(headers[used].ramSize) else 0,
    );
    snes_reset(snes, true); // reset after loading
    free(newData);
    return true;
}
