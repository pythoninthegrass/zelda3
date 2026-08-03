// Port of snes/dsp.c: the S-DSP audio processor — 8-voice BRR sample
// playback, ADSR/gain envelopes, Gaussian interpolation, pitch modulation,
// noise, and the FIR echo unit. Every function keeps its exact C-ABI name
// and signature (callconv(.c), C-pointer types) so the remaining .c callers
// (apu.c/apu.zig, spc_player.c, zelda_rtl.c) link unchanged. The
// DspChannel/Dsp struct layout itself stays C-owned in snes/dsp.h — mirrored
// here field-for-field (extern struct) rather than redefined, since
// dsp_saveload serializes the tail of Dsp byte-for-byte into saves/ref/
// Chapter*.sav reference saves, which must keep loading correctly.
//
// dsp.c has a `#define MY_CHANGES 1` compile-time switch selecting between
// two keyon/off timing schemes. Only the enabled (`#if MY_CHANGES`) branch —
// keyon/off applied immediately on register write, in dsp_write's KON/KOF
// cases — is ported; the disabled `#if !MY_CHANGES` branch (deferred to the
// next even cycle, in the old dsp_cycleChannel) never compiles today and is
// dropped rather than translated.

const std = @import("std");

pub const DspChannel = extern struct {
    // pitch
    pitch: u16,
    pitchCounter: u16,
    pitchModulation: bool,
    // brr decoding
    decodeBuffer: [19]i16, // 16 samples per brr-block, +3 for interpolation
    srcn: u8,
    decodeOffset: u16,
    previousFlags: u8, // from last sample
    old: i16,
    older: i16,
    useNoise: bool,
    // adsr, envelope, gain
    adsrRates: [4]u16, // attack, decay, sustain, gain
    rateCounter: u16,
    adsrState: u8, // 0: attack, 1: decay, 2: sustain, 3: gain, 4: release
    sustainLevel: u16,
    useGain: bool,
    gainMode: u8,
    directGain: bool,
    gainValue: u16, // for direct gain
    gain: u16,
    // keyon/off
    keyOn: bool,
    keyOff: bool,
    // output
    sampleOut: i16, // final sample, to be multiplied by channel volume
    volumeL: i8,
    volumeR: i8,
    echoEnable: bool,
};

pub const Dsp = extern struct {
    apu_ram: [*]u8,
    // mirror ram
    ram: [0x80]u8,
    // 8 channels
    channel: [8]DspChannel,
    // overarching
    dirPage: u16,
    evenCycle: bool,
    mute: bool,
    reset: bool,
    masterVolumeL: i8,
    masterVolumeR: i8,
    // noise
    noiseSample: i16,
    noiseRate: u16,
    noiseCounter: u16,
    // echo
    echoWrites: bool,
    echoVolumeL: i8,
    echoVolumeR: i8,
    feedbackVolume: i8,
    echoBufferAdr: u16,
    echoDelay: u16,
    echoRemain: u16,
    echoBufferIndex: u16,
    firBufferIndex: u8,
    firValues: [8]i8,
    firBufferL: [8]i16,
    firBufferR: [8]i16,
    // sample buffer (1 frame at 32040 Hz: 534 samples, *2 for stereo)
    sampleBuffer: [534 * 2]i16,
    sampleOffset: u16, // current offset in samplebuffer
};

// Same type as SaveLoadFunc in snes/saveload.h.
const SaveLoadFunc = fn (ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void;

extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;

const rateValues = [32]i32{
    0,   2048, 1536, 1280, 1024, 768, 640, 512,
    384, 320,  256,  192,  160,  128, 96,  80,
    64,  48,   40,   32,   24,   20,  16,  12,
    10,  8,    6,    5,    4,    3,   2,   1,
};

const gaussValues = [512]i32{
    0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000,
    0x001, 0x001, 0x001, 0x001, 0x001, 0x001, 0x001, 0x001, 0x001, 0x001, 0x001, 0x002, 0x002, 0x002, 0x002, 0x002,
    0x002, 0x002, 0x003, 0x003, 0x003, 0x003, 0x003, 0x004, 0x004, 0x004, 0x004, 0x004, 0x005, 0x005, 0x005, 0x005,
    0x006, 0x006, 0x006, 0x006, 0x007, 0x007, 0x007, 0x008, 0x008, 0x008, 0x009, 0x009, 0x009, 0x00A, 0x00A, 0x00A,
    0x00B, 0x00B, 0x00B, 0x00C, 0x00C, 0x00D, 0x00D, 0x00E, 0x00E, 0x00F, 0x00F, 0x00F, 0x010, 0x010, 0x011, 0x011,
    0x012, 0x013, 0x013, 0x014, 0x014, 0x015, 0x015, 0x016, 0x017, 0x017, 0x018, 0x018, 0x019, 0x01A, 0x01B, 0x01B,
    0x01C, 0x01D, 0x01D, 0x01E, 0x01F, 0x020, 0x020, 0x021, 0x022, 0x023, 0x024, 0x024, 0x025, 0x026, 0x027, 0x028,
    0x029, 0x02A, 0x02B, 0x02C, 0x02D, 0x02E, 0x02F, 0x030, 0x031, 0x032, 0x033, 0x034, 0x035, 0x036, 0x037, 0x038,
    0x03A, 0x03B, 0x03C, 0x03D, 0x03E, 0x040, 0x041, 0x042, 0x043, 0x045, 0x046, 0x047, 0x049, 0x04A, 0x04C, 0x04D,
    0x04E, 0x050, 0x051, 0x053, 0x054, 0x056, 0x057, 0x059, 0x05A, 0x05C, 0x05E, 0x05F, 0x061, 0x063, 0x064, 0x066,
    0x068, 0x06A, 0x06B, 0x06D, 0x06F, 0x071, 0x073, 0x075, 0x076, 0x078, 0x07A, 0x07C, 0x07E, 0x080, 0x082, 0x084,
    0x086, 0x089, 0x08B, 0x08D, 0x08F, 0x091, 0x093, 0x096, 0x098, 0x09A, 0x09C, 0x09F, 0x0A1, 0x0A3, 0x0A6, 0x0A8,
    0x0AB, 0x0AD, 0x0AF, 0x0B2, 0x0B4, 0x0B7, 0x0BA, 0x0BC, 0x0BF, 0x0C1, 0x0C4, 0x0C7, 0x0C9, 0x0CC, 0x0CF, 0x0D2,
    0x0D4, 0x0D7, 0x0DA, 0x0DD, 0x0E0, 0x0E3, 0x0E6, 0x0E9, 0x0EC, 0x0EF, 0x0F2, 0x0F5, 0x0F8, 0x0FB, 0x0FE, 0x101,
    0x104, 0x107, 0x10B, 0x10E, 0x111, 0x114, 0x118, 0x11B, 0x11E, 0x122, 0x125, 0x129, 0x12C, 0x130, 0x133, 0x137,
    0x13A, 0x13E, 0x141, 0x145, 0x148, 0x14C, 0x150, 0x153, 0x157, 0x15B, 0x15F, 0x162, 0x166, 0x16A, 0x16E, 0x172,
    0x176, 0x17A, 0x17D, 0x181, 0x185, 0x189, 0x18D, 0x191, 0x195, 0x19A, 0x19E, 0x1A2, 0x1A6, 0x1AA, 0x1AE, 0x1B2,
    0x1B7, 0x1BB, 0x1BF, 0x1C3, 0x1C8, 0x1CC, 0x1D0, 0x1D5, 0x1D9, 0x1DD, 0x1E2, 0x1E6, 0x1EB, 0x1EF, 0x1F3, 0x1F8,
    0x1FC, 0x201, 0x205, 0x20A, 0x20F, 0x213, 0x218, 0x21C, 0x221, 0x226, 0x22A, 0x22F, 0x233, 0x238, 0x23D, 0x241,
    0x246, 0x24B, 0x250, 0x254, 0x259, 0x25E, 0x263, 0x267, 0x26C, 0x271, 0x276, 0x27B, 0x280, 0x284, 0x289, 0x28E,
    0x293, 0x298, 0x29D, 0x2A2, 0x2A6, 0x2AB, 0x2B0, 0x2B5, 0x2BA, 0x2BF, 0x2C4, 0x2C9, 0x2CE, 0x2D3, 0x2D8, 0x2DC,
    0x2E1, 0x2E6, 0x2EB, 0x2F0, 0x2F5, 0x2FA, 0x2FF, 0x304, 0x309, 0x30E, 0x313, 0x318, 0x31D, 0x322, 0x326, 0x32B,
    0x330, 0x335, 0x33A, 0x33F, 0x344, 0x349, 0x34E, 0x353, 0x357, 0x35C, 0x361, 0x366, 0x36B, 0x370, 0x374, 0x379,
    0x37E, 0x383, 0x388, 0x38C, 0x391, 0x396, 0x39B, 0x39F, 0x3A4, 0x3A9, 0x3AD, 0x3B2, 0x3B7, 0x3BB, 0x3C0, 0x3C5,
    0x3C9, 0x3CE, 0x3D2, 0x3D7, 0x3DC, 0x3E0, 0x3E5, 0x3E9, 0x3ED, 0x3F2, 0x3F6, 0x3FB, 0x3FF, 0x403, 0x408, 0x40C,
    0x410, 0x415, 0x419, 0x41D, 0x421, 0x425, 0x42A, 0x42E, 0x432, 0x436, 0x43A, 0x43E, 0x442, 0x446, 0x44A, 0x44E,
    0x452, 0x455, 0x459, 0x45D, 0x461, 0x465, 0x468, 0x46C, 0x470, 0x473, 0x477, 0x47A, 0x47E, 0x481, 0x485, 0x488,
    0x48C, 0x48F, 0x492, 0x496, 0x499, 0x49C, 0x49F, 0x4A2, 0x4A6, 0x4A9, 0x4AC, 0x4AF, 0x4B2, 0x4B5, 0x4B7, 0x4BA,
    0x4BD, 0x4C0, 0x4C3, 0x4C5, 0x4C8, 0x4CB, 0x4CD, 0x4D0, 0x4D2, 0x4D5, 0x4D7, 0x4D9, 0x4DC, 0x4DE, 0x4E0, 0x4E3,
    0x4E5, 0x4E7, 0x4E9, 0x4EB, 0x4ED, 0x4EF, 0x4F1, 0x4F3, 0x4F5, 0x4F6, 0x4F8, 0x4FA, 0x4FB, 0x4FD, 0x4FF, 0x500,
    0x502, 0x503, 0x504, 0x506, 0x507, 0x508, 0x50A, 0x50B, 0x50C, 0x50D, 0x50E, 0x50F, 0x510, 0x511, 0x511, 0x512,
    0x513, 0x514, 0x514, 0x515, 0x516, 0x516, 0x517, 0x517, 0x517, 0x518, 0x518, 0x518, 0x518, 0x518, 0x519, 0x519,
};

// Register addresses, same values as enum DspReg in snes/dsp_regs.h.
const V0VOLL = 0x00;
const V0VOLR = 0x01;
const V0PITCHL = 0x02;
const V0PITCHH = 0x03;
const V0SRCN = 0x04;
const V0ADSR1 = 0x05;
const V0ADSR2 = 0x06;
const V0GAIN = 0x07;
const MVOLL = 0x0C;
const EFB = 0x0D;
const FIR0 = 0x0F;
const V1VOLL = 0x10;
const V1VOLR = 0x11;
const V1PL = 0x12;
const V1PH = 0x13;
const V1SRCN = 0x14;
const V1ADSR1 = 0x15;
const V1ADSR2 = 0x16;
const V1GAIN = 0x17;
const MVOLR = 0x1C;
const FIR1 = 0x1F;
const V2VOLL = 0x20;
const V2VOLR = 0x21;
const V2PL = 0x22;
const V2PH = 0x23;
const V2SRCN = 0x24;
const V2ADSR1 = 0x25;
const V2ADSR2 = 0x26;
const V2GAIN = 0x27;
const EVOLL = 0x2C;
const PMON = 0x2D;
const FIR2 = 0x2F;
const V3VOLL = 0x30;
const V3VOLR = 0x31;
const V3PL = 0x32;
const V3PH = 0x33;
const V3SRCN = 0x34;
const V3ADSR1 = 0x35;
const V3ADSR2 = 0x36;
const V3GAIN = 0x37;
const EVOLR = 0x3C;
const NON = 0x3D;
const FIR3 = 0x3F;
const V4VOLL = 0x40;
const V4VOLR = 0x41;
const V4PL = 0x42;
const V4PH = 0x43;
const V4SRCN = 0x44;
const V4ADSR1 = 0x45;
const V4ADSR2 = 0x46;
const V4GAIN = 0x47;
const KON = 0x4C;
const EON = 0x4D;
const FIR4 = 0x4F;
const V5VOLL = 0x50;
const V5VOLR = 0x51;
const V5PL = 0x52;
const V5PH = 0x53;
const V5SRCN = 0x54;
const V5ADSR1 = 0x55;
const V5ADSR2 = 0x56;
const V5GAIN = 0x57;
const KOF = 0x5C;
const DIR = 0x5D;
const FIR5 = 0x5F;
const V6VOLL = 0x60;
const V6VOLR = 0x61;
const V6PL = 0x62;
const V6PH = 0x63;
const V6SRCN = 0x64;
const V6ADSR1 = 0x65;
const V6ADSR2 = 0x66;
const V6GAIN = 0x67;
const FLG = 0x6C;
const ESA = 0x6D;
const FIR6 = 0x6F;
const V7VOLL = 0x70;
const V7VOLR = 0x71;
const V7PL = 0x72;
const V7PH = 0x73;
const V7SRCN = 0x74;
const V7ADSR1 = 0x75;
const V7ADSR2 = 0x76;
const V7GAIN = 0x77;
const ENDX = 0x7C;
const EDL = 0x7D;
const FIR7 = 0x7F;

fn clamp16(v: i32) i16 {
    return @intCast(std.math.clamp(v, -0x8000, 0x7fff));
}

// See input.zig: dead-code stub for Zig 0.16's std.start analysis; the C
// main in src/main.c is the real entry point.
pub fn main() callconv(.c) c_int {
    return 0;
}

pub export fn dsp_init(apu_ram: [*]u8) ?*Dsp {
    const dsp: *Dsp = @ptrCast(@alignCast(malloc(@sizeOf(Dsp)) orelse return null));
    dsp.apu_ram = apu_ram;
    return dsp;
}

pub export fn dsp_free(dsp: ?*Dsp) void {
    free(dsp);
}

pub export fn dsp_reset(dsp: *Dsp) void {
    dsp.ram = [_]u8{0} ** 0x80;
    dsp.ram[ENDX] = 0xff; // set ENDX bit for all channels
    for (0..8) |i| {
        dsp.channel[i] = .{
            .pitch = 0,
            .pitchCounter = 0,
            .pitchModulation = false,
            .decodeBuffer = [_]i16{0} ** 19,
            .srcn = 0,
            .decodeOffset = 0,
            .previousFlags = 0,
            .old = 0,
            .older = 0,
            .useNoise = false,
            .adsrRates = [_]u16{0} ** 4,
            .rateCounter = 0,
            .adsrState = 0,
            .sustainLevel = 0,
            .useGain = false,
            .gainMode = 0,
            .directGain = false,
            .gainValue = 0,
            .gain = 0,
            .keyOn = false,
            .keyOff = false,
            .sampleOut = 0,
            .volumeL = 0,
            .volumeR = 0,
            .echoEnable = false,
        };
    }
    dsp.dirPage = 0;
    dsp.evenCycle = false;
    dsp.mute = true;
    dsp.reset = true;
    dsp.masterVolumeL = 0;
    dsp.masterVolumeR = 0;
    dsp.noiseSample = -0x4000;
    dsp.noiseRate = 0;
    dsp.noiseCounter = 0;
    dsp.echoWrites = false;
    dsp.echoVolumeL = 0;
    dsp.echoVolumeR = 0;
    dsp.feedbackVolume = 0;
    dsp.echoBufferAdr = 0;
    dsp.echoDelay = 1;
    dsp.echoRemain = 1;
    dsp.echoBufferIndex = 0;
    dsp.firBufferIndex = 0;
    dsp.firValues = [_]i8{0} ** 8;
    dsp.firBufferL = [_]i16{0} ** 8;
    dsp.firBufferR = [_]i16{0} ** 8;
    dsp.sampleBuffer = [_]i16{0} ** (534 * 2);
    dsp.sampleOffset = 0;
}

pub export fn dsp_saveload(dsp: *Dsp, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) void {
    const len = @sizeOf(Dsp) - @offsetOf(Dsp, "ram");
    func.?(ctx, &dsp.ram, len);
}

pub export fn dsp_cycle(dsp: *Dsp) void {
    var totalL: i32 = 0;
    var totalR: i32 = 0;
    for (0..8) |i| {
        dspCycleChannel(dsp, i);
        totalL += (@as(i32, dsp.channel[i].sampleOut) * dsp.channel[i].volumeL) >> 6;
        totalR += (@as(i32, dsp.channel[i].sampleOut) * dsp.channel[i].volumeR) >> 6;
        totalL = std.math.clamp(totalL, -0x8000, 0x7fff);
        totalR = std.math.clamp(totalR, -0x8000, 0x7fff);
    }
    totalL = (totalL * dsp.masterVolumeL) >> 7;
    totalR = (totalR * dsp.masterVolumeR) >> 7;
    totalL = std.math.clamp(totalL, -0x8000, 0x7fff);
    totalR = std.math.clamp(totalR, -0x8000, 0x7fff);
    dspHandleEcho(dsp, &totalL, &totalR);
    if (dsp.mute) {
        totalL = 0;
        totalR = 0;
    }
    dspHandleNoise(dsp);
    // put it in the samplebuffer, if space
    if (dsp.sampleOffset < 534) {
        dsp.sampleBuffer[dsp.sampleOffset * 2] = @intCast(totalL);
        dsp.sampleBuffer[dsp.sampleOffset * 2 + 1] = @intCast(totalR);
        dsp.sampleOffset += 1;
    }
    dsp.evenCycle = !dsp.evenCycle;
}

fn dspHandleEcho(dsp: *Dsp, outputL: *i32, outputR: *i32) void {
    // get value out of ram
    const adr: u16 = dsp.echoBufferAdr +% dsp.echoBufferIndex *% 4;
    dsp.firBufferL[dsp.firBufferIndex] = @bitCast(@as(u16, dsp.apu_ram[adr]) + (@as(u16, dsp.apu_ram[adr +% 1]) << 8));
    dsp.firBufferL[dsp.firBufferIndex] >>= 1;
    dsp.firBufferR[dsp.firBufferIndex] = @bitCast(@as(u16, dsp.apu_ram[adr +% 2]) + (@as(u16, dsp.apu_ram[adr +% 3]) << 8));
    dsp.firBufferR[dsp.firBufferIndex] >>= 1;
    // calculate FIR-sum
    var sumL: i32 = 0;
    var sumR: i32 = 0;
    for (0..8) |i| {
        const idx: u8 = (dsp.firBufferIndex + @as(u8, @intCast(i)) + 1) & 0x7;
        sumL += (@as(i32, dsp.firBufferL[idx]) * dsp.firValues[i]) >> 6;
        sumR += (@as(i32, dsp.firBufferR[idx]) * dsp.firValues[i]) >> 6;
        if (i == 6) {
            // clip to 16-bit before last addition
            sumL = @as(i16, @bitCast(@as(u16, @truncate(@as(u32, @bitCast(sumL))))));
            sumR = @as(i16, @bitCast(@as(u16, @truncate(@as(u32, @bitCast(sumR))))));
        }
    }
    sumL = std.math.clamp(sumL, -0x8000, 0x7fff);
    sumR = std.math.clamp(sumR, -0x8000, 0x7fff);
    // modify output with sum
    const outL = outputL.* + ((sumL * dsp.echoVolumeL) >> 7);
    const outR = outputR.* + ((sumR * dsp.echoVolumeR) >> 7);
    outputL.* = std.math.clamp(outL, -0x8000, 0x7fff);
    outputR.* = std.math.clamp(outR, -0x8000, 0x7fff);
    // get echo input
    var inL: i32 = 0;
    var inR: i32 = 0;
    for (0..8) |i| {
        if (dsp.channel[i].echoEnable) {
            inL += (@as(i32, dsp.channel[i].sampleOut) * dsp.channel[i].volumeL) >> 6;
            inR += (@as(i32, dsp.channel[i].sampleOut) * dsp.channel[i].volumeR) >> 6;
            inL = std.math.clamp(inL, -0x8000, 0x7fff);
            inR = std.math.clamp(inR, -0x8000, 0x7fff);
        }
    }
    // write this to ram
    inL += (sumL * dsp.feedbackVolume) >> 7;
    inR += (sumR * dsp.feedbackVolume) >> 7;
    inL = std.math.clamp(inL, -0x8000, 0x7fff);
    inR = std.math.clamp(inR, -0x8000, 0x7fff);
    inL &= 0xfffe;
    inR &= 0xfffe;
    if (dsp.echoWrites) {
        dsp.apu_ram[adr] = @truncate(@as(u32, @bitCast(inL)));
        dsp.apu_ram[adr +% 1] = @truncate(@as(u32, @bitCast(inL)) >> 8);
        dsp.apu_ram[adr +% 2] = @truncate(@as(u32, @bitCast(inR)));
        dsp.apu_ram[adr +% 3] = @truncate(@as(u32, @bitCast(inR)) >> 8);
    }
    // handle indexes
    dsp.firBufferIndex +%= 1;
    dsp.firBufferIndex &= 7;
    dsp.echoBufferIndex +%= 1;
    dsp.echoRemain -%= 1;
    if (dsp.echoRemain == 0) {
        dsp.echoRemain = dsp.echoDelay;
        dsp.echoBufferIndex = 0;
    }
}

fn keyOnChannel(dsp: *Dsp, ch: usize) void {
    // restart current sample
    dsp.channel[ch].previousFlags = 0;
    const samplePointer: u16 = dsp.dirPage +% 4 *% @as(u16, dsp.channel[ch].srcn);
    dsp.channel[ch].decodeOffset = dsp.apu_ram[samplePointer];
    dsp.channel[ch].decodeOffset |= @as(u16, dsp.apu_ram[samplePointer +% 1]) << 8;
    dsp.channel[ch].decodeBuffer = [_]i16{0} ** 19;
    dsp.channel[ch].gain = 0;
    dsp.channel[ch].adsrState = if (dsp.channel[ch].useGain) 3 else 0;
}

fn dspCycleChannel(dsp: *Dsp, ch: usize) void {
    // handle pitch counter
    var pitch: u32 = dsp.channel[ch].pitch;
    if (ch > 0 and dsp.channel[ch].pitchModulation) {
        const factor: i32 = (@as(i32, dsp.channel[ch - 1].sampleOut) >> 4) + 0x400;
        const raw: i32 = (@as(i32, @intCast(pitch)) * factor) >> 10;
        const truncated: u16 = @truncate(@as(u32, @bitCast(raw)));
        pitch = if (truncated > 0x3fff) 0x3fff else truncated;
    }
    const newCounter: u32 = @as(u32, dsp.channel[ch].pitchCounter) + pitch;
    if (newCounter > 0xffff) {
        // next sample
        dspDecodeBrr(dsp, ch);
    }
    dsp.channel[ch].pitchCounter = @truncate(newCounter);
    var sample: i16 = 0;
    if (dsp.channel[ch].useNoise) {
        sample = dsp.noiseSample;
    } else {
        sample = dspGetSample(dsp, ch, dsp.channel[ch].pitchCounter >> 12, @truncate((dsp.channel[ch].pitchCounter >> 4) & 0xff));
    }
    // handle reset
    if (dsp.reset) {
        dsp.channel[ch].adsrState = 4;
        dsp.channel[ch].gain = 0;
    }
    // handle envelope/adsr
    const doingDirectGain = dsp.channel[ch].adsrState != 4 and dsp.channel[ch].useGain and dsp.channel[ch].directGain;
    const rate: u16 = if (dsp.channel[ch].adsrState == 4) 0 else dsp.channel[ch].adsrRates[dsp.channel[ch].adsrState];
    if (dsp.channel[ch].adsrState != 4 and !doingDirectGain and rate != 0) {
        dsp.channel[ch].rateCounter += 1;
    }
    if (dsp.channel[ch].adsrState == 4 or (!doingDirectGain and dsp.channel[ch].rateCounter >= rate and rate != 0)) {
        if (dsp.channel[ch].adsrState != 4) dsp.channel[ch].rateCounter = 0;
        dspHandleGain(dsp, ch);
    }
    if (doingDirectGain) dsp.channel[ch].gain = dsp.channel[ch].gainValue;
    // set outputs
    dsp.ram[(ch << 4) | 8] = @truncate(dsp.channel[ch].gain >> 4);
    sample = @truncate((@as(i32, sample) * @as(i32, dsp.channel[ch].gain)) >> 11);
    dsp.ram[(ch << 4) | 9] = @bitCast(@as(i8, @truncate(sample >> 7)));
    dsp.channel[ch].sampleOut = sample;
}

fn dspHandleGain(dsp: *Dsp, ch: usize) void {
    var gain: i32 = dsp.channel[ch].gain;
    const state = dsp.channel[ch].adsrState;
    switch (state) {
        0 => { // attack
            const rate = dsp.channel[ch].adsrRates[state];
            gain += if (rate == 1) 1024 else 32;
            if (gain >= 0x7e0) dsp.channel[ch].adsrState = 1;
            if (gain > 0x7ff) gain = 0x7ff;
        },
        1 => { // decay
            gain -= ((gain - 1) >> 8) + 1;
            if (gain < dsp.channel[ch].sustainLevel) dsp.channel[ch].adsrState = 2;
        },
        2 => { // sustain
            gain -= ((gain - 1) >> 8) + 1;
        },
        3 => { // gain
            switch (dsp.channel[ch].gainMode) {
                0 => { // linear decrease
                    gain -= 32;
                },
                1 => { // exponential decrease
                    gain -= ((gain - 1) >> 8) + 1;
                },
                2 => { // linear increase
                    gain += 32;
                },
                3 => { // bent increase
                    gain += if (gain < 0x600) 32 else 8;
                },
                else => unreachable,
            }
        },
        4 => { // release
            gain -= 8;
        },
        else => unreachable,
    }
    // decreasing below 0 (states 1/2 use the >>8 form and never go negative
    // here since gain is unsigned in the C source; states 0/3/4 rely on
    // uint16 underflow wrapping above 0x7ff)
    dsp.channel[ch].gain = @truncate(@as(u32, @bitCast(gain)) & 0xffff);
    if (state == 0 and dsp.channel[ch].gain > 0x7ff) dsp.channel[ch].gain = 0x7ff;
    if (state == 3) {
        switch (dsp.channel[ch].gainMode) {
            0, 2, 3 => if (dsp.channel[ch].gain > 0x7ff) {
                dsp.channel[ch].gain = 0;
            },
            else => {},
        }
    }
    if (state == 4 and dsp.channel[ch].gain > 0x7ff) dsp.channel[ch].gain = 0;
}

fn dspGetSample(dsp: *Dsp, ch: usize, sampleNum: u16, offset: u8) i16 {
    const news = dsp.channel[ch].decodeBuffer[sampleNum + 3];
    const olds = dsp.channel[ch].decodeBuffer[sampleNum + 2];
    const olders = dsp.channel[ch].decodeBuffer[sampleNum + 1];
    const oldests = dsp.channel[ch].decodeBuffer[sampleNum];
    const off: u16 = offset;
    var out: i32 = (gaussValues[0xff - off] * oldests) >> 10;
    out += (gaussValues[0x1ff - off] * olders) >> 10;
    out += (gaussValues[0x100 + off] * olds) >> 10;
    out = @as(i16, @bitCast(@as(u16, @truncate(@as(u32, @bitCast(out)))))); // clip 16-bit
    out += (gaussValues[offset] * news) >> 10;
    out = std.math.clamp(out, -0x8000, 0x7fff); // clamp 16-bit
    return @intCast(out >> 1);
}

fn dspDecodeBrr(dsp: *Dsp, ch: usize) void {
    // copy last 3 samples (16-18) to first 3 for interpolation
    dsp.channel[ch].decodeBuffer[0] = dsp.channel[ch].decodeBuffer[16];
    dsp.channel[ch].decodeBuffer[1] = dsp.channel[ch].decodeBuffer[17];
    dsp.channel[ch].decodeBuffer[2] = dsp.channel[ch].decodeBuffer[18];
    // handle flags from previous block
    if (dsp.channel[ch].previousFlags == 1 or dsp.channel[ch].previousFlags == 3) {
        // loop sample
        const samplePointer: u16 = dsp.dirPage +% 4 *% @as(u16, dsp.channel[ch].srcn);
        dsp.channel[ch].decodeOffset = dsp.apu_ram[samplePointer +% 2];
        dsp.channel[ch].decodeOffset |= @as(u16, dsp.apu_ram[samplePointer +% 3]) << 8;
        if (dsp.channel[ch].previousFlags == 1) {
            // also release and clear gain
            dsp.channel[ch].adsrState = 4;
            dsp.channel[ch].gain = 0;
        }
        dsp.ram[ENDX] |= @as(u8, 1) << @intCast(ch); // set ENDX bit for channel
    }
    const header = dsp.apu_ram[dsp.channel[ch].decodeOffset];
    dsp.channel[ch].decodeOffset +%= 1;
    const shift = header >> 4;
    const filter = (header & 0xc) >> 2;
    dsp.channel[ch].previousFlags = header & 0x3;
    var curByte: u8 = 0;
    var old: i32 = dsp.channel[ch].old;
    var older: i32 = dsp.channel[ch].older;
    for (0..16) |i| {
        var s: i32 = 0;
        if (i & 1 != 0) {
            s = curByte & 0xf;
        } else {
            curByte = dsp.apu_ram[dsp.channel[ch].decodeOffset];
            dsp.channel[ch].decodeOffset +%= 1;
            s = curByte >> 4;
        }
        if (s > 7) s -= 16;
        if (shift <= 0xc) {
            s = (s << @intCast(shift)) >> 1;
        } else {
            s = (s >> 3) << 12;
        }
        switch (filter) {
            1 => s += old + (-old >> 4),
            2 => s += 2 * old + ((3 * -old) >> 5) - older + (older >> 4),
            3 => s += 2 * old + ((13 * -old) >> 6) - older + ((3 * older) >> 4),
            else => {},
        }
        s = std.math.clamp(s, -0x8000, 0x7fff); // clamp 16-bit
        s = (@as(i16, @bitCast(@as(u16, @truncate((@as(u32, @bitCast(s)) & 0x7fff) << 1)))) >> 1); // clip 15-bit
        older = old;
        old = s;
        dsp.channel[ch].decodeBuffer[i + 3] = @intCast(s);
    }
    dsp.channel[ch].older = @intCast(older);
    dsp.channel[ch].old = @intCast(old);
}

fn dspHandleNoise(dsp: *Dsp) void {
    if (dsp.noiseRate != 0) {
        dsp.noiseCounter += 1;
    }
    if (dsp.noiseCounter >= dsp.noiseRate and dsp.noiseRate != 0) {
        const bit: i16 = (dsp.noiseSample & 1) ^ ((dsp.noiseSample >> 1) & 1);
        dsp.noiseSample = @bitCast(@as(u16, @bitCast((dsp.noiseSample >> 1) & 0x3fff)) | (@as(u16, @bitCast(bit)) << 14));
        dsp.noiseSample = (@as(i16, @bitCast(@as(u16, @truncate((@as(u32, @bitCast(@as(i32, dsp.noiseSample))) & 0x7fff) << 1)))) >> 1);
        dsp.noiseCounter = 0;
    }
}

pub export fn dsp_read(dsp: *Dsp, adr: u8) u8 {
    return dsp.ram[adr];
}

pub export fn dsp_write(dsp: *Dsp, adr: u8, val: u8) void {
    const ch: usize = adr >> 4;
    switch (adr) {
        V0VOLL, V1VOLL, V2VOLL, V3VOLL, V4VOLL, V5VOLL, V6VOLL, V7VOLL => {
            dsp.channel[ch].volumeL = @bitCast(val);
        },
        V0VOLL + 1, V1VOLL + 1, V2VOLL + 1, V3VOLL + 1, V4VOLL + 1, V5VOLL + 1, V6VOLL + 1, V7VOLL + 1 => {
            dsp.channel[ch].volumeR = @bitCast(val);
        },
        V0PITCHL, V1PL, V2PL, V3PL, V4PL, V5PL, V6PL, V7PL => {
            dsp.channel[ch].pitch = (dsp.channel[ch].pitch & 0x3f00) | val;
        },
        V0PITCHH, V1PH, V2PH, V3PH, V4PH, V5PH, V6PH, V7PH => {
            dsp.channel[ch].pitch = ((dsp.channel[ch].pitch & 0x00ff) | (@as(u16, val) << 8)) & 0x3fff;
        },
        V0SRCN, V1SRCN, V2SRCN, V3SRCN, V4SRCN, V5SRCN, V6SRCN, V7SRCN => {
            dsp.channel[ch].srcn = val;
        },
        V0ADSR1, V1ADSR1, V2ADSR1, V3ADSR1, V4ADSR1, V5ADSR1, V6ADSR1, V7ADSR1 => {
            dsp.channel[ch].adsrRates[0] = @intCast(rateValues[(val & 0xf) * 2 + 1]);
            dsp.channel[ch].adsrRates[1] = @intCast(rateValues[((val & 0x70) >> 4) * 2 + 16]);
            dsp.channel[ch].useGain = (val & 0x80) == 0;
        },
        V0ADSR2, V1ADSR2, V2ADSR2, V3ADSR2, V4ADSR2, V5ADSR2, V6ADSR2, V7ADSR2 => {
            dsp.channel[ch].adsrRates[2] = @intCast(rateValues[val & 0x1f]);
            dsp.channel[ch].sustainLevel = (@as(u16, (val & 0xe0) >> 5) + 1) * 0x100;
        },
        V0GAIN, V1GAIN, V2GAIN, V3GAIN, V4GAIN, V5GAIN, V6GAIN, V7GAIN => {
            dsp.channel[ch].directGain = (val & 0x80) == 0;
            if (val & 0x80 != 0) {
                dsp.channel[ch].gainMode = (val & 0x60) >> 5;
                dsp.channel[ch].adsrRates[3] = @intCast(rateValues[val & 0x1f]);
            } else {
                dsp.channel[ch].gainValue = @as(u16, val & 0x7f) * 16;
            }
        },
        MVOLL => dsp.masterVolumeL = @bitCast(val),
        MVOLR => dsp.masterVolumeR = @bitCast(val),
        EVOLL => dsp.echoVolumeL = @bitCast(val),
        EVOLR => dsp.echoVolumeR = @bitCast(val),
        KON => {
            for (0..8) |i| {
                const keyOn = val & (@as(u8, 1) << @intCast(i)) != 0;
                dsp.channel[i].keyOn = false;
                if (keyOn) keyOnChannel(dsp, i);
            }
        },
        KOF => {
            for (0..8) |i| {
                const keyOff = val & (@as(u8, 1) << @intCast(i)) != 0;
                dsp.channel[i].keyOff = keyOff;
                if (keyOff) dsp.channel[i].adsrState = 4; // go to release
            }
        },
        FLG => {
            dsp.reset = val & 0x80 != 0;
            dsp.mute = val & 0x40 != 0;
            dsp.echoWrites = (val & 0x20) == 0;
            dsp.noiseRate = @intCast(rateValues[val & 0x1f]);
        },
        ENDX => {
            dsp.ram[adr] = 0; // any write clears ENDx
            return;
        },
        EFB => dsp.feedbackVolume = @bitCast(val),
        PMON => {
            for (0..8) |i| dsp.channel[i].pitchModulation = val & (@as(u8, 1) << @intCast(i)) != 0;
        },
        NON => {
            for (0..8) |i| dsp.channel[i].useNoise = val & (@as(u8, 1) << @intCast(i)) != 0;
        },
        EON => {
            for (0..8) |i| dsp.channel[i].echoEnable = val & (@as(u8, 1) << @intCast(i)) != 0;
        },
        DIR => dsp.dirPage = @as(u16, val) << 8,
        ESA => dsp.echoBufferAdr = @as(u16, val) << 8,
        EDL => {
            dsp.echoDelay = @as(u16, val & 0xf) * 512; // 2048-byte steps, stereo sample is 4 bytes
            if (dsp.echoDelay == 0) dsp.echoDelay = 1;
        },
        FIR0, FIR1, FIR2, FIR3, FIR4, FIR5, FIR6, FIR7 => {
            dsp.firValues[ch] = @bitCast(val);
        },
        else => {},
    }
    dsp.ram[adr] = val;
}

pub export fn dsp_getSamples(dsp: *Dsp, sampleData: [*]i16, samplesPerFrame: c_int, numChannels: c_int) void {
    // resample from 534 samples per frame to wanted value
    const adder: f32 = 534.0 / @as(f32, @floatFromInt(samplesPerFrame));
    var location: f32 = 0.0;

    if (numChannels == 1) {
        var i: c_int = 0;
        while (i < samplesPerFrame) : (i += 1) {
            const idx: usize = @intFromFloat(location);
            const sampleL: i32 = dsp.sampleBuffer[idx * 2];
            const sampleR: i32 = dsp.sampleBuffer[idx * 2 + 1];
            sampleData[@intCast(i)] = @intCast((sampleL + sampleR) >> 1);
            location += adder;
        }
    } else {
        var i: c_int = 0;
        while (i < samplesPerFrame) : (i += 1) {
            const idx: usize = @intFromFloat(location);
            sampleData[@intCast(i * 2)] = dsp.sampleBuffer[idx * 2];
            sampleData[@intCast(i * 2 + 1)] = dsp.sampleBuffer[idx * 2 + 1];
            location += adder;
        }
    }
    dsp.sampleOffset = 0;
}
