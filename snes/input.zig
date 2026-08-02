// Port of snes/input.c: SNES controller input — the serial-shift model
// behind $4016/$4017 and the auto-joypad read. Every function keeps its
// exact C-ABI name and signature (callconv(.c), C-pointer types) so the
// remaining .c callers (snes.c, zelda_cpu_infra.c) link unchanged. The
// Input struct layout itself stays C-owned in snes/input.h — snes.c pokes
// latchLine/currentState directly — so this module mirrors that layout
// field-for-field rather than redefining it.
//
// First snes/ module ported; the build.zig/taskfile.yml wiring that lets a
// snes/*.zig object replace its .c sibling follows the src/*.zig precedent.

const std = @import("std");

// Snes is opaque here: input.c only stores the back-pointer, never reads it.
const Snes = opaque {};

// Mirrors struct Input in snes/input.h (C keeps ownership of the layout;
// the bool is one byte, padding after it implicit like the C side).
pub const Input = extern struct {
    snes: ?*Snes,
    type: u8,
    // latchline
    latchLine: bool,
    // for controller
    currentState: u16, // actual state
    latchedState: u16,
};

extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;

// Zig 0.16's std.start semantically analyzes root.main whenever it emits an
// executable, even with the entry point disabled (the C main in src/main.c
// is the real entry; this stub is dead code that the linker discards because
// it is never exported).
pub fn main() callconv(.c) c_int {
    return 0;
}

pub export fn input_init(snes: ?*Snes) ?*Input {
    const input: *Input = @ptrCast(@alignCast(malloc(@sizeOf(Input)) orelse return null));
    input.snes = snes;
    // TODO: handle (where?)
    input.type = 1;
    input.currentState = 0;
    return input;
}

pub export fn input_free(input: ?*Input) void {
    free(input);
}

pub export fn input_reset(input: *Input) void {
    input.latchLine = false;
    input.latchedState = 0;
}

pub export fn input_cycle(input: *Input) void {
    if (input.latchLine) {
        input.latchedState = input.currentState;
    }
}

pub export fn input_read(input: *Input) u8 {
    const ret: u8 = @truncate(input.latchedState & 1);
    input.latchedState >>= 1;
    input.latchedState |= 0x8000;
    return ret;
}

