// Tier-A unit tests for snes/dsp.zig: golden-value checks for reset defaults,
// register read/write decode across the volume/pitch/srcn/adsr/gain/master/
// echo/KON/KOF/FLG/ENDX/EFB/PMON/NON/EON/DIR/ESA/EDL/FIR groups, dsp_cycle
// sample generation, dsp_saveload's byte range, and dsp_getSamples
// resampling — driven through the exported C-ABI functions only, using a
// local apu_ram buffer (dsp.zig only ever touches memory through the
// pointer passed to dsp_init).

const std = @import("std");
const dsp_mod = @import("dsp.zig");

const expectEqual = std.testing.expectEqual;

const Dsp = dsp_mod.Dsp;

var apu_ram: [0x10000]u8 = undefined;

fn freshDsp() *Dsp {
    apu_ram = [_]u8{0} ** 0x10000;
    const d = dsp_mod.dsp_init(&apu_ram) orelse unreachable;
    dsp_mod.dsp_reset(d);
    return d;
}

test "dsp_init seeds the apu_ram pointer" {
    apu_ram = [_]u8{0} ** 0x10000;
    const d = dsp_mod.dsp_init(&apu_ram) orelse return error.OutOfMemory;
    defer dsp_mod.dsp_free(d);
    try expectEqual(@as([*]u8, &apu_ram), d.apu_ram);
}

test "dsp_reset sets ENDX and echo delay/remain defaults" {
    const d = freshDsp();
    defer dsp_mod.dsp_free(d);
    try expectEqual(@as(u8, 0xff), d.ram[0x7c]); // ENDX
    try expectEqual(@as(u16, 1), d.echoDelay);
    try expectEqual(@as(u16, 1), d.echoRemain);
    try expectEqual(@as(i16, -0x4000), d.noiseSample);
    try expectEqual(true, d.mute);
    try expectEqual(true, d.reset);
    for (d.channel) |ch| {
        try expectEqual(@as(u16, 0), ch.pitch);
        try expectEqual(@as(u8, 0), ch.adsrState);
    }
}

test "dsp_write/dsp_read round-trip channel 0 volume/pitch/srcn" {
    const d = freshDsp();
    defer dsp_mod.dsp_free(d);
    dsp_mod.dsp_write(d, 0x00, 0x40);
    try expectEqual(@as(i8, 0x40), d.channel[0].volumeL);
    try expectEqual(@as(u8, 0x40), dsp_mod.dsp_read(d, 0x00));

    dsp_mod.dsp_write(d, 0x01, @bitCast(@as(i8, -10)));
    try expectEqual(@as(i8, -10), d.channel[0].volumeR);

    dsp_mod.dsp_write(d, 0x02, 0x34);
    dsp_mod.dsp_write(d, 0x03, 0x12);
    try expectEqual(@as(u16, 0x1234), d.channel[0].pitch);

    dsp_mod.dsp_write(d, 0x04, 0x07);
    try expectEqual(@as(u8, 7), d.channel[0].srcn);
}

test "dsp_write adsr1/adsr2 decode rates, sustain level, and useGain" {
    const d = freshDsp();
    defer dsp_mod.dsp_free(d);
    // adsr1: bit7=1 (adsr enabled -> useGain=false), decay=3, attack=5
    dsp_mod.dsp_write(d, 0x05, 0x80 | (3 << 4) | 5);
    try expectEqual(false, d.channel[0].useGain);
    try expectEqual(@as(u16, 192), d.channel[0].adsrRates[0]); // rateValues[11]
    try expectEqual(@as(u16, 16), d.channel[0].adsrRates[1]); // rateValues[22]

    // adsr1 bit7=0 -> useGain=true
    dsp_mod.dsp_write(d, 0x05, 0x00);
    try expectEqual(true, d.channel[0].useGain);

    dsp_mod.dsp_write(d, 0x06, (2 << 5) | 9); // sustain=2, decay rate idx 9
    try expectEqual(@as(u16, 320), d.channel[0].adsrRates[2]); // rateValues[9]
    try expectEqual(@as(u16, 0x300), d.channel[0].sustainLevel);
}

test "dsp_write gain register: direct vs rate mode" {
    const d = freshDsp();
    defer dsp_mod.dsp_free(d);
    dsp_mod.dsp_write(d, 0x07, 0x3f); // bit7=0 -> direct gain
    try expectEqual(true, d.channel[0].directGain);
    try expectEqual(@as(u16, 0x3f * 16), d.channel[0].gainValue);

    dsp_mod.dsp_write(d, 0x07, 0x80 | (1 << 5) | 5); // bit7=1 -> rate mode, gainMode=1
    try expectEqual(false, d.channel[0].directGain);
    try expectEqual(@as(u8, 1), d.channel[0].gainMode);
    try expectEqual(@as(u16, 768), d.channel[0].adsrRates[3]); // rateValues[5]
}

test "dsp_write master volume and echo volume" {
    const d = freshDsp();
    defer dsp_mod.dsp_free(d);
    dsp_mod.dsp_write(d, 0x0c, 0x60); // MVOLL
    dsp_mod.dsp_write(d, 0x1c, @bitCast(@as(i8, -0x20))); // MVOLR
    try expectEqual(@as(i8, 0x60), d.masterVolumeL);
    try expectEqual(@as(i8, -0x20), d.masterVolumeR);

    dsp_mod.dsp_write(d, 0x2c, 0x10); // EVOLL
    dsp_mod.dsp_write(d, 0x3c, 0x11); // EVOLR
    try expectEqual(@as(i8, 0x10), d.echoVolumeL);
    try expectEqual(@as(i8, 0x11), d.echoVolumeR);

    dsp_mod.dsp_write(d, 0x0d, 0x22); // EFB
    try expectEqual(@as(i8, 0x22), d.feedbackVolume);
}

test "dsp_write KON immediately keys on channels (MY_CHANGES behavior)" {
    const d = freshDsp();
    defer dsp_mod.dsp_free(d);
    // point channel 1's sample directory entry at a known brr offset
    d.dirPage = 0x0100;
    apu_ram[0x0100 + 4 * 1] = 0x00; // srcn=1 pointer low (start addr)
    apu_ram[0x0100 + 4 * 1 + 1] = 0x02;
    dsp_mod.dsp_write(d, 0x14, 1); // V1SRCN = 1
    d.ram[0x7c] = 0xff; // ENDX all set beforehand

    dsp_mod.dsp_write(d, 0x4c, 0b0000_0010); // KON channel 1
    try expectEqual(@as(u16, 0x0200), d.channel[1].decodeOffset);
    try expectEqual(@as(u8, 0), d.channel[1].previousFlags);
    try expectEqual(@as(u16, 0), d.channel[1].gain);
}

test "dsp_write KOF sets adsrState to release for selected channels" {
    const d = freshDsp();
    defer dsp_mod.dsp_free(d);
    d.channel[3].adsrState = 0;
    dsp_mod.dsp_write(d, 0x5c, 0b0000_1000); // KOF channel 3
    try expectEqual(@as(u8, 4), d.channel[3].adsrState);
    try expectEqual(true, d.channel[3].keyOff);
}

test "dsp_write FLG decodes reset/mute/echoWrites/noiseRate" {
    const d = freshDsp();
    defer dsp_mod.dsp_free(d);
    dsp_mod.dsp_write(d, 0x6c, 0x80 | 0x40 | 5); // reset+mute, noiseRate idx 5
    try expectEqual(true, d.reset);
    try expectEqual(true, d.mute);
    try expectEqual(true, d.echoWrites); // bit 0x20 clear in 0xC5 -> echoWrites=true
    try expectEqual(@as(u16, 768), d.noiseRate); // rateValues[5]
}

test "dsp_write ENDX write of any value clears it" {
    const d = freshDsp();
    defer dsp_mod.dsp_free(d);
    d.ram[0x7c] = 0xff;
    dsp_mod.dsp_write(d, 0x7c, 0x42);
    try expectEqual(@as(u8, 0), d.ram[0x7c]);
}

test "dsp_write PMON/NON/EON set per-channel bitmask flags" {
    const d = freshDsp();
    defer dsp_mod.dsp_free(d);
    dsp_mod.dsp_write(d, 0x2d, 0b0000_0110); // PMON channels 1,2
    try expectEqual(false, d.channel[0].pitchModulation);
    try expectEqual(true, d.channel[1].pitchModulation);
    try expectEqual(true, d.channel[2].pitchModulation);

    dsp_mod.dsp_write(d, 0x3d, 0b1000_0000); // NON channel 7
    try expectEqual(true, d.channel[7].useNoise);

    dsp_mod.dsp_write(d, 0x4d, 0b0000_0001); // EON channel 0
    try expectEqual(true, d.channel[0].echoEnable);
}

test "dsp_write DIR/ESA/EDL" {
    const d = freshDsp();
    defer dsp_mod.dsp_free(d);
    dsp_mod.dsp_write(d, 0x5d, 0x12); // DIR
    try expectEqual(@as(u16, 0x1200), d.dirPage);

    dsp_mod.dsp_write(d, 0x6d, 0x34); // ESA
    try expectEqual(@as(u16, 0x3400), d.echoBufferAdr);

    dsp_mod.dsp_write(d, 0x7d, 0x02); // EDL
    try expectEqual(@as(u16, 1024), d.echoDelay);

    dsp_mod.dsp_write(d, 0x7d, 0x00); // EDL=0 clamps to 1
    try expectEqual(@as(u16, 1), d.echoDelay);
}

test "dsp_write FIR taps" {
    const d = freshDsp();
    defer dsp_mod.dsp_free(d);
    dsp_mod.dsp_write(d, 0x0f, 0x7f); // FIR0
    dsp_mod.dsp_write(d, 0x7f, @bitCast(@as(i8, -1))); // FIR7
    try expectEqual(@as(i8, 0x7f), d.firValues[0]);
    try expectEqual(@as(i8, -1), d.firValues[7]);
}

test "dsp_cycle produces silence and stays clamped when all channels are quiet" {
    const d = freshDsp();
    defer dsp_mod.dsp_free(d);
    d.reset = false;
    d.mute = false;
    dsp_mod.dsp_cycle(d);
    try expectEqual(@as(i16, 0), d.sampleBuffer[0]);
    try expectEqual(@as(i16, 0), d.sampleBuffer[1]);
    try expectEqual(@as(u16, 1), d.sampleOffset);
}

test "dsp_cycle stops filling sampleBuffer once it's full" {
    const d = freshDsp();
    defer dsp_mod.dsp_free(d);
    d.reset = false;
    d.mute = false;
    d.sampleOffset = 534;
    dsp_mod.dsp_cycle(d);
    try expectEqual(@as(u16, 534), d.sampleOffset);
}

test "dsp_saveload hands the ram-tail and its exact size to the callback" {
    const d = freshDsp();
    defer dsp_mod.dsp_free(d);
    var seen: struct { data: ?*anyopaque = null, size: usize = 0 } = .{};
    const cb = struct {
        fn run(ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void {
            const s: *@TypeOf(seen) = @ptrCast(@alignCast(ctx));
            s.data = data;
            s.size = data_size;
        }
    }.run;
    dsp_mod.dsp_saveload(d, cb, &seen);
    try expectEqual(@as(?*anyopaque, @ptrCast(&d.ram)), seen.data);
    try expectEqual(@sizeOf(Dsp) - @offsetOf(Dsp, "ram"), seen.size);
}

test "dsp_getSamples mono downmixes L+R, resets sampleOffset" {
    const d = freshDsp();
    defer dsp_mod.dsp_free(d);
    d.sampleBuffer[0] = 100;
    d.sampleBuffer[1] = 200;
    d.sampleOffset = 1;
    var out: [4]i16 = undefined;
    dsp_mod.dsp_getSamples(d, &out, 4, 1);
    try expectEqual(@as(i16, 150), out[0]);
    try expectEqual(@as(u16, 0), d.sampleOffset);
}

test "dsp_getSamples stereo passes L/R through" {
    const d = freshDsp();
    defer dsp_mod.dsp_free(d);
    d.sampleBuffer[0] = 111;
    d.sampleBuffer[1] = 222;
    var out: [4]i16 = undefined;
    dsp_mod.dsp_getSamples(d, &out, 2, 2);
    try expectEqual(@as(i16, 111), out[0]);
    try expectEqual(@as(i16, 222), out[1]);
}
