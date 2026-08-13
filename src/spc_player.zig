// Port of src/spc_player.c: the reimplemented SPC music/sfx player driving the
// bundled S-DSP. It decodes the game's music/sfx command streams (8 channels,
// port0=music, port1/2/3=sfx), maintains volume/pan/pitch/vibrato/tremolo/echo
// fades, and pokes DSP registers via dsp_write. Every exported symbol keeps its
// exact C-ABI name and signature (callconv(.c), C-pointer types) so the
// remaining .c callers (audio.c, zelda_rtl.c) and the ported dsp.zig link
// unchanged.
//
// The Channel and SpcPlayer struct layouts stay C-owned in src/spc_player.h --
// mirrored here field-for-field (extern struct) so audio.c can keep reading
// p->input_ports / p->ram, and so SpcPlayer_CopyVariablesTo/FromRam's offsetof
// table copies land on the same bytes. The Dsp/DspChannel and DspRegWriteHistory
// mirrors match snes/dsp.zig / snes/dsp.h; this file only ever reads
// dsp->sampleOffset and the reg_write_history tail, but the full layouts are
// needed so those two fields sit at the correct offsets.
//
// The `#if WITH_SPC_PLAYER_DEBUGGING` block at the tail of spc_player.c (the
// SDL-driven CompareSpcImpls/RunAudioPlayer harness, compiled out with the flag
// at 0) is dropped rather than translated, matching dsp.zig dropping its own
// disabled branch. Not_Implemented / assert(0)-unreachable paths become
// @panic (the classic `task build` compiles with assert() active, no -DNDEBUG);
// GenerateSamples' invariant asserts become std.debug.assert.

const std = @import("std");

// ---- C-ABI struct mirrors --------------------------------------------------

const DspRegWriteHistory = extern struct {
    count: u32,
    addr: [256]u8,
    val: [256]u8,
};

// Mirrors DspChannel in snes/dsp.h (see snes/dsp.zig for the same mirror).
const DspChannel = extern struct {
    pitch: u16,
    pitchCounter: u16,
    pitchModulation: bool,
    decodeBuffer: [19]i16,
    srcn: u8,
    decodeOffset: u16,
    previousFlags: u8,
    old: i16,
    older: i16,
    useNoise: bool,
    adsrRates: [4]u16,
    rateCounter: u16,
    adsrState: u8,
    sustainLevel: u16,
    useGain: bool,
    gainMode: u8,
    directGain: bool,
    gainValue: u16,
    gain: u16,
    keyOn: bool,
    keyOff: bool,
    sampleOut: i16,
    volumeL: i8,
    volumeR: i8,
    echoEnable: bool,
};

// Mirrors struct Dsp in snes/dsp.h; only sampleOffset is read here.
const Dsp = extern struct {
    apu_ram: [*]u8,
    ram: [0x80]u8,
    channel: [8]DspChannel,
    dirPage: u16,
    evenCycle: bool,
    mute: bool,
    reset: bool,
    masterVolumeL: i8,
    masterVolumeR: i8,
    noiseSample: i16,
    noiseRate: u16,
    noiseCounter: u16,
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
    sampleBuffer: [534 * 2]i16,
    sampleOffset: u16,
};

// Mirrors struct Channel in src/spc_player.h.
pub const Channel = extern struct {
    pattern_order_ptr_for_chan: u16,
    note_ticks_left: u8,
    note_keyoff_ticks_left: u8,
    subroutine_num_loops: u8,
    volume_fade_ticks: u8,
    pan_num_ticks: u8,
    pitch_slide_length: u8,
    pitch_slide_delay_left: u8,
    vibrato_hold_count: u8,
    vib_depth: u8,
    tremolo_hold_count: u8,
    tremolo_depth: u8,
    vibrato_change_count: u8,
    note_length: u8,
    note_gate_off_fixedpt: u8,
    channel_volume_master: u8,
    instrument_id: u8,
    instrument_pitch_base: u16,
    saved_pattern_ptr: u16,
    pattern_start_ptr: u16,
    pitch_envelope_num_ticks: u8,
    pitch_envelope_delay: u8,
    pitch_envelope_direction: u8,
    pitch_envelope_slide_value: u8,
    vibrato_count: u8,
    vibrato_rate: u8,
    vibrato_delay_ticks: u8,
    vibrato_fade_num_ticks: u8,
    vibrato_fade_add_per_tick: u8,
    vibrato_depth_target: u8,
    tremolo_count: u8,
    tremolo_rate: u8,
    tremolo_delay_ticks: u8,
    channel_transposition: u8,
    channel_volume: u16,
    volume_fade_addpertick: u16,
    volume_fade_target: u8,
    final_volume: u8,
    pan_value: u16,
    pan_add_per_tick: u16,
    pan_target_value: u8,
    pan_flag_with_phase_invert: u8,
    pitch: u16,
    pitch_add_per_tick: u16,
    pitch_target: u8,
    fine_tune: u8,
    sfx_sound_ptr: u16,
    sfx_which_sound: u8,
    sfx_arr_countdown: u8,
    sfx_note_length_left: u8,
    sfx_note_length: u8,
    sfx_pan: u8,
    index: u8,
};

// Mirrors struct SpcPlayer in src/spc_player.h.
pub const SpcPlayer = extern struct {
    reg_write_history: ?*DspRegWriteHistory,
    timer_cycles: u8,
    dsp: ?*Dsp,
    new_value_from_snes: [4]u8,
    port_to_snes: [4]u8,
    last_value_from_snes: [4]u8,
    counter_sf0c: u8,
    _always_zero: u16,
    temp_accum: u16,
    ttt: u8,
    did_affect_volumepitch_flag: u8,
    addr0: u16,
    addr1: u16,
    lfsr_value: u16,
    is_chan_on: u8,
    fast_forward: u8,
    sfx_start_arg_pan: u8,
    sfx_sound_ptr_cur: u16,
    music_ptr_toplevel: u16,
    block_count: u8,
    sfx_timer_accum: u8,
    chn: u8,
    key_ON: u8,
    key_OFF: u8,
    cur_chan_bit: u8,
    reg_FLG: u8,
    reg_NON: u8,
    reg_EON: u8,
    reg_PMON: u8,
    echo_stored_time: u8,
    echo_parameter_EDL: u8,
    reg_EFB: u8,
    global_transposition: u8,
    main_tempo_accum: u8,
    tempo: u16,
    tempo_fade_num_ticks: u8,
    tempo_fade_final: u8,
    tempo_fade_add: u16,
    master_volume: u16,
    master_volume_fade_ticks: u8,
    master_volume_fade_target: u8,
    master_volume_fade_add_per_tick: u16,
    vol_dirty: u8,
    percussion_base_id: u8,
    echo_volume_left: u16,
    echo_volume_right: u16,
    echo_volume_fade_add_left: u16,
    echo_volume_fade_add_right: u16,
    echo_volume_fade_ticks: u8,
    echo_volume_fade_target_left: u8,
    echo_volume_fade_target_right: u8,
    sfx_channel_index: u8,
    current_bit: u8,
    dsp_register_index: u8,
    echo_channels: u8,
    byte_3C4: u8,
    byte_3C5: u8,
    echo_fract_incr: u8,
    sfx_channel_index2: u8,
    sfx_channel_bit: u8,
    pause_music_ctr: u8,
    port2_active: u8,
    port2_current_bit: u8,
    port3_active: u8,
    port3_current_bit: u8,
    port1_active: u8,
    port1_current_bit: u8,
    byte_3E1: u8,
    sfx_play_echo_flag: u8,
    sfx_channels_echo_mask2: u8,
    port1_counter: u8,
    channel_67_volume: u8,
    cutk_always_zero: u8,
    last_written_edl: u8,
    input_ports: [4]u8,
    channel: [8]Channel,
    ram: [65536]u8,
};

// ---- externs ---------------------------------------------------------------

extern fn dsp_write(dsp: *Dsp, adr: u8, val: u8) callconv(.c) void;
extern fn dsp_init(apu_ram: [*]u8) callconv(.c) ?*Dsp;
extern fn dsp_reset(dsp: *Dsp) callconv(.c) void;
extern fn dsp_cycle(dsp: *Dsp) callconv(.c) void;
extern fn malloc(size: usize) callconv(.c) ?*anyopaque;

// ---- DSP register constants (snes/dsp_regs.h) ------------------------------

const V0VOLL: u8 = 0x00;
const V0VOLR: u8 = 0x01;
const V0PITCHL: u8 = 0x02;
const V0PITCHH: u8 = 0x03;
const V0SRCN: u8 = 0x04;
const V0ADSR1: u8 = 0x05;
const V0ADSR2: u8 = 0x06;
const V0GAIN: u8 = 0x07;
const MVOLL: u8 = 0x0C;
const EFB: u8 = 0x0D;
const FIR0: u8 = 0x0F;
const MVOLR: u8 = 0x1C;
const EVOLL: u8 = 0x2C;
const PMON: u8 = 0x2D;
const EVOLR: u8 = 0x3C;
const NON: u8 = 0x3D;
const KON: u8 = 0x4C;
const EON: u8 = 0x4D;
const KOF: u8 = 0x5C;
const DIR: u8 = 0x5D;
const V6VOLL: u8 = 0x60;
const V6VOLR: u8 = 0x61;
const FLG: u8 = 0x6C;
const ESA: u8 = 0x6D;
const V7VOLL: u8 = 0x70;
const V7VOLR: u8 = 0x71;
const EDL: u8 = 0x7D;

// ---- helpers mirroring C macros --------------------------------------------

inline fn hi(v: u16) u8 {
    return @truncate(v >> 8);
}

inline fn setHi(v: *u16, b: u8) void {
    v.* = (v.* & 0x00ff) | (@as(u16, b) << 8);
}

// WORD(ram[x]): little-endian 16-bit read, matching *(uint16*)&ram[x].
inline fn word(ram: *const [65536]u8, x: usize) u16 {
    return @as(u16, ram[x]) | (@as(u16, ram[x + 1]) << 8);
}

// p->ram[c->pattern_order_ptr_for_chan++]
inline fn readCh(p: *SpcPlayer, c: *Channel) u8 {
    const v = p.ram[c.pattern_order_ptr_for_chan];
    c.pattern_order_ptr_for_chan +%= 1;
    return v;
}

// ---- memmap tables ---------------------------------------------------------

const MemMap = struct { off: u16, org_off: u16 };
const MemMapSized = struct { off: u16, org_off: u16, size: u16 };

fn cmap(comptime field: []const u8, org_off: u16) MemMap {
    return .{ .off = @offsetOf(Channel, field), .org_off = org_off };
}

fn pmap(comptime field: []const u8, org_off: u16, size: u16) MemMapSized {
    return .{ .off = @offsetOf(SpcPlayer, field), .org_off = org_off, .size = size };
}

const kChannel_Maps = [_]MemMap{
    cmap("pattern_order_ptr_for_chan", 0x8030),
    cmap("note_ticks_left", 0x70),
    cmap("note_keyoff_ticks_left", 0x71),
    cmap("subroutine_num_loops", 0x80),
    cmap("volume_fade_ticks", 0x90),
    cmap("pan_num_ticks", 0x91),
    cmap("pitch_slide_length", 0xa0),
    cmap("pitch_slide_delay_left", 0xa1),
    cmap("vibrato_hold_count", 0xb0),
    cmap("vib_depth", 0xb1),
    cmap("tremolo_hold_count", 0xc0),
    cmap("tremolo_depth", 0xc1),
    cmap("vibrato_change_count", 0x100),
    cmap("note_length", 0x200),
    cmap("note_gate_off_fixedpt", 0x201),
    cmap("channel_volume_master", 0x210),
    cmap("instrument_id", 0x211),
    cmap("instrument_pitch_base", 0x8220),
    cmap("saved_pattern_ptr", 0x8230),
    cmap("pattern_start_ptr", 0x8240),
    cmap("pitch_envelope_num_ticks", 0x280),
    cmap("pitch_envelope_delay", 0x281),
    cmap("pitch_envelope_direction", 0x290),
    cmap("pitch_envelope_slide_value", 0x291),
    cmap("vibrato_count", 0x2a0),
    cmap("vibrato_rate", 0x2a1),
    cmap("vibrato_delay_ticks", 0x2b0),
    cmap("vibrato_fade_num_ticks", 0x2b1),
    cmap("vibrato_fade_add_per_tick", 0x2c0),
    cmap("vibrato_depth_target", 0x2c1),
    cmap("tremolo_count", 0x2d0),
    cmap("tremolo_rate", 0x2d1),
    cmap("tremolo_delay_ticks", 0x2e0),
    cmap("channel_transposition", 0x2f0),
    cmap("channel_volume", 0x8300),
    cmap("volume_fade_addpertick", 0x8310),
    cmap("volume_fade_target", 0x320),
    cmap("final_volume", 0x321),
    cmap("pan_value", 0x8330),
    cmap("pan_add_per_tick", 0x8340),
    cmap("pan_target_value", 0x350),
    cmap("pan_flag_with_phase_invert", 0x351),
    cmap("pitch", 0x8360),
    cmap("pitch_add_per_tick", 0x8370),
    cmap("pitch_target", 0x380),
    cmap("fine_tune", 0x381),
    cmap("sfx_sound_ptr", 0x8390),
    cmap("sfx_which_sound", 0x3a0),
    cmap("sfx_arr_countdown", 0x3a1),
    cmap("sfx_note_length_left", 0x3b0),
    cmap("sfx_note_length", 0x3b1),
    cmap("sfx_pan", 0x3d0),
};

const kSpcPlayer_Maps = [_]MemMapSized{
    pmap("new_value_from_snes", 0x0, 4),
    pmap("port_to_snes", 0x4, 4),
    pmap("last_value_from_snes", 0x8, 4),
    pmap("counter_sf0c", 0xc, 1),
    pmap("_always_zero", 0xe, 2),
    pmap("temp_accum", 0x10, 2),
    pmap("ttt", 0x12, 1),
    pmap("did_affect_volumepitch_flag", 0x13, 1),
    pmap("addr0", 0x14, 2),
    pmap("addr1", 0x16, 2),
    pmap("lfsr_value", 0x18, 2),
    pmap("is_chan_on", 0x1a, 1),
    pmap("fast_forward", 0x1b, 1),
    pmap("sfx_start_arg_pan", 0x20, 1),
    pmap("sfx_sound_ptr_cur", 0x2c, 2),
    pmap("music_ptr_toplevel", 0x40, 2),
    pmap("block_count", 0x42, 1),
    pmap("sfx_timer_accum", 0x43, 1),
    pmap("chn", 0x44, 1),
    pmap("key_ON", 0x45, 1),
    pmap("key_OFF", 0x46, 1),
    pmap("cur_chan_bit", 0x47, 1),
    pmap("reg_FLG", 0x48, 1),
    pmap("reg_NON", 0x49, 1),
    pmap("reg_EON", 0x4a, 1),
    pmap("reg_PMON", 0x4b, 1),
    pmap("echo_stored_time", 0x4c, 1),
    pmap("echo_parameter_EDL", 0x4d, 1),
    pmap("reg_EFB", 0x4e, 1),
    pmap("global_transposition", 0x50, 1),
    pmap("main_tempo_accum", 0x51, 1),
    pmap("tempo", 0x52, 2),
    pmap("tempo_fade_num_ticks", 0x54, 1),
    pmap("tempo_fade_final", 0x55, 1),
    pmap("tempo_fade_add", 0x56, 2),
    pmap("master_volume", 0x58, 2),
    pmap("master_volume_fade_ticks", 0x5a, 1),
    pmap("master_volume_fade_target", 0x5b, 1),
    pmap("master_volume_fade_add_per_tick", 0x5c, 2),
    pmap("vol_dirty", 0x5e, 1),
    pmap("percussion_base_id", 0x5f, 1),
    pmap("echo_volume_left", 0x60, 2),
    pmap("echo_volume_right", 0x62, 2),
    pmap("echo_volume_fade_add_left", 0x64, 2),
    pmap("echo_volume_fade_add_right", 0x66, 2),
    pmap("echo_volume_fade_ticks", 0x68, 1),
    pmap("echo_volume_fade_target_left", 0x69, 1),
    pmap("echo_volume_fade_target_right", 0x6a, 1),
    pmap("sfx_channel_index", 0x3c0, 1),
    pmap("current_bit", 0x3c1, 1),
    pmap("dsp_register_index", 0x3c2, 1),
    pmap("echo_channels", 0x3c3, 1),
    pmap("byte_3C4", 0x3c4, 1),
    pmap("byte_3C5", 0x3c5, 1),
    pmap("echo_fract_incr", 0x3c7, 1),
    pmap("sfx_channel_index2", 0x3c8, 1),
    pmap("sfx_channel_bit", 0x3c9, 1),
    pmap("pause_music_ctr", 0x3ca, 1),
    pmap("port2_active", 0x3cb, 1),
    pmap("port2_current_bit", 0x3cc, 1),
    pmap("port3_active", 0x3cd, 1),
    pmap("port3_current_bit", 0x3ce, 1),
    pmap("port1_active", 0x3cf, 1),
    pmap("port1_current_bit", 0x3e0, 1),
    pmap("byte_3E1", 0x3e1, 1),
    pmap("sfx_play_echo_flag", 0x3e2, 1),
    pmap("sfx_channels_echo_mask2", 0x3e3, 1),
    pmap("port1_counter", 0x3e4, 1),
    pmap("channel_67_volume", 0x3e5, 1),
    pmap("cutk_always_zero", 0x3ff, 1),
};

// ---- implementation --------------------------------------------------------

fn Dsp_Write(p: *SpcPlayer, reg: u8, value: u8) void {
    if (p.reg_write_history) |hist| {
        if (hist.count < 256) {
            hist.addr[hist.count] = reg;
            hist.val[hist.count] = value;
            hist.count += 1;
        }
    }
    if (p.dsp) |dsp| dsp_write(dsp, reg, value);
}

fn Not_Implemented() void {
    @panic("Not Implemented");
}

fn SpcDivHelper(a_in: i32, b: u8) u16 {
    var a = a_in;
    const org_a = a;
    if ((a & 0x100) != 0) a = -a;
    const bb: i32 = b;
    const am = a & 0xff;
    const q: i32 = if (b != 0) @divTrunc(am, bb) else 0xff;
    const r: i32 = if (b != 0) @rem(am, bb) else am;
    const t: i32 = (q << 8) + (if (b != 0) (@divTrunc(r << 8, bb) & 0xff) else 0xff);
    const res: i32 = if ((org_a & 0x100) != 0) -t else t;
    return @truncate(@as(u32, @bitCast(res)));
}

inline fn Chan_DoAnyFade(ptr: *u16, add: u16, target: u8, cont: u8) void {
    if (cont == 0) {
        ptr.* = @as(u16, target) << 8;
    } else {
        ptr.* +%= add;
    }
}

fn SetupEchoParameter_EDL(p: *SpcPlayer, a_in: u8) void {
    var a = a_in;
    p.echo_parameter_EDL = a;
    if (a != p.last_written_edl) {
        a = (p.last_written_edl & 0xf) ^ 0xff;
        if ((p.echo_stored_time & 0x80) != 0) a +%= p.echo_stored_time;
        p.echo_stored_time = a;

        Dsp_Write(p, EON, 0);
        Dsp_Write(p, EFB, 0);
        Dsp_Write(p, EVOLR, 0);
        Dsp_Write(p, EVOLL, 0);
        Dsp_Write(p, FLG, p.reg_FLG | 0x20);

        p.last_written_edl = p.echo_parameter_EDL;
        Dsp_Write(p, EDL, p.echo_parameter_EDL);
    }
    Dsp_Write(p, ESA, @truncate(((@as(u16, p.echo_parameter_EDL) * 8) ^ 0xff) + 0xd1));
}

fn WriteVolumeToDsp(p: *SpcPlayer, c: *Channel, volume_in: u16) void {
    const kVolumeTable = [22]u8{ 0, 1, 3, 7, 13, 21, 30, 41, 52, 66, 81, 94, 103, 110, 115, 119, 122, 124, 125, 126, 127, 127 };
    if ((p.is_chan_on & p.cur_chan_bit) != 0) return;
    var volume = volume_in;
    var i: usize = 0;
    while (i < 2) : (i += 1) {
        const j: usize = volume >> 8;
        const vlo: i32 = @as(u8, @truncate(volume));
        var t: u8 = undefined;
        if (j >= 21) {
            const base: i32 = p.ram[j + 0x1178];
            const nxt: i32 = p.ram[j + 0x1179];
            t = @truncate(@as(u32, @bitCast(base + (((nxt - base) * vlo) >> 8))));
        } else {
            const base: i32 = kVolumeTable[j];
            const nxt: i32 = kVolumeTable[j + 1];
            t = @truncate(@as(u32, @bitCast(base + (((nxt - base) * vlo) >> 8))));
        }
        t = @truncate((@as(u16, t) * @as(u16, c.final_volume)) >> 8);
        if (((@as(u16, c.pan_flag_with_phase_invert) << @as(u4, @intCast(i))) & 0x80) != 0)
            t = 0 -% t;
        Dsp_Write(p, V0VOLL +% @as(u8, @intCast(i)) +% (c.index *% 16), t);
        volume = @as(u16, 0x1400) -% volume;
    }
}

fn WritePitch(p: *SpcPlayer, c: *Channel, pitch_in: u16) void {
    const kBaseNoteFreqs = [13]u16{ 2143, 2270, 2405, 2548, 2700, 2860, 3030, 3211, 3402, 3604, 3818, 4045, 4286 };
    var pitch = pitch_in;
    const hp: i32 = pitch >> 8;
    if (hp >= 0x34) {
        pitch +%= @as(u16, @bitCast(@as(i16, @intCast(hp - 0x34))));
    } else if (hp < 0x13) {
        const inner: u8 = @truncate(@as(u32, @bitCast((hp - 0x13) * 2)));
        pitch +%= @as(u16, @bitCast(@as(i16, inner) - 256));
    }

    const pp: u8 = @as(u8, @truncate(pitch >> 8)) & 0x7f;
    var q: u8 = pp / 12;
    const r: u8 = pp % 12;
    const plo: u8 = @truncate(pitch);
    const d: u8 = @truncate(kBaseNoteFreqs[r + 1] -% kBaseNoteFreqs[r]);
    const term: u16 = (@as(u16, d) * @as(u16, plo)) >> 8;
    var t: u16 = kBaseNoteFreqs[r] +% term;
    t *%= 2;
    while (q != 6) {
        t >>= 1;
        q +%= 1;
    }

    t = @truncate((@as(u32, c.instrument_pitch_base) * @as(u32, t)) >> 8);
    if ((p.cur_chan_bit & p.is_chan_on) == 0) {
        const reg: u8 = c.index *% 16;
        Dsp_Write(p, reg +% V0PITCHL, @truncate(t));
        Dsp_Write(p, reg +% V0PITCHH, @truncate(t >> 8));
    }
}

fn Music_ResetChan(p: *SpcPlayer) void {
    p.cur_chan_bit = 0x80;
    var ci: usize = 7;
    while (true) {
        const c = &p.channel[ci];
        setHi(&c.channel_volume, 0xff);
        c.pan_flag_with_phase_invert = 10;
        c.pan_value = 10 << 8;
        c.instrument_id = 0;
        c.fine_tune = 0;
        c.channel_transposition = 0;
        c.pitch_envelope_num_ticks = 0;
        c.vib_depth = 0;
        c.tremolo_depth = 0;
        p.cur_chan_bit >>= 1;
        if (p.cur_chan_bit == 0) break;
        ci -= 1;
    }
    p.master_volume_fade_ticks = 0;
    p.echo_volume_fade_ticks = 0;
    p.tempo_fade_num_ticks = 0;
    p.global_transposition = 0;
    p.block_count = 0;
    p.percussion_base_id = 0;
    setHi(&p.master_volume, 0xc0);
    setHi(&p.tempo, 0x20);
}

fn Channel_SetInstrument(p: *SpcPlayer, c: *Channel, instrument_in: u8) void {
    var instrument = instrument_in;
    c.instrument_id = instrument;
    if ((instrument & 0x80) != 0) instrument = instrument +% 54 +% p.percussion_base_id;
    const ip = p.ram[@as(usize, instrument) * 6 + 0x3d00 ..];
    if ((p.is_chan_on & p.cur_chan_bit) != 0) return;
    const reg: u8 = c.index *% 16;
    if ((ip[0] & 0x80) != 0) {
        // noise
        p.reg_FLG = (p.reg_FLG & 0x20) | (ip[0] & 0x1f);
        p.reg_NON |= p.cur_chan_bit;
        Dsp_Write(p, reg +% V0SRCN, 0);
    } else {
        Dsp_Write(p, reg +% V0SRCN, ip[0]);
    }
    Dsp_Write(p, reg +% V0ADSR1, ip[1]);
    Dsp_Write(p, reg +% V0ADSR2, ip[2]);
    Dsp_Write(p, reg +% V0GAIN, ip[3]);
    c.instrument_pitch_base = (@as(u16, ip[4]) << 8) | ip[5];
}

fn ComputePitchAdd(c: *Channel, pitch: u8) void {
    c.pitch_target = pitch & 0x7f;
    c.pitch_add_per_tick = SpcDivHelper(@as(i32, c.pitch_target) - @as(i32, hi(c.pitch)), c.pitch_slide_length);
}

fn PitchSlideToNote_Check(p: *SpcPlayer, c: *Channel) void {
    if (c.pitch_slide_length != 0 or p.ram[c.pattern_order_ptr_for_chan] != 0xf9)
        return;

    if ((p.cur_chan_bit & p.is_chan_on) != 0) {
        c.pattern_order_ptr_for_chan +%= 4;
        return;
    }
    c.pattern_order_ptr_for_chan +%= 1;
    c.pitch_slide_delay_left = readCh(p, c);
    c.pitch_slide_length = readCh(p, c);
    const arg = readCh(p, c);
    ComputePitchAdd(c, @truncate(@as(u16, arg) + @as(u16, p.global_transposition) + @as(u16, c.channel_transposition)));
}

const kEffectByteLength = [27]u8{ 1, 1, 2, 3, 0, 1, 2, 1, 2, 1, 1, 3, 0, 1, 2, 3, 1, 3, 3, 0, 1, 3, 0, 3, 3, 3, 1 };

fn HandleEffect(p: *SpcPlayer, c: *Channel, effect: u8) void {
    const arg: u8 = if (kEffectByteLength[effect - 0xe0] != 0) readCh(p, c) else 0;

    switch (effect) {
        0xe0 => {
            Channel_SetInstrument(p, c, arg);
        },
        0xe1 => {
            c.pan_flag_with_phase_invert = arg;
            c.pan_value = @as(u16, arg & 0x1f) << 8;
        },
        0xe2 => {
            c.pan_num_ticks = arg;
            c.pan_target_value = readCh(p, c);
            c.pan_add_per_tick = SpcDivHelper(@as(i32, c.pan_target_value) - @as(i32, hi(c.pan_value)), arg);
        },
        0xe3 => { // vibrato on
            c.vibrato_delay_ticks = arg;
            c.vibrato_rate = readCh(p, c);
            c.vib_depth = readCh(p, c);
            c.vibrato_depth_target = c.vib_depth;
            c.vibrato_fade_num_ticks = 0;
        },
        0xe4 => { // vibrato off
            c.vib_depth = 0;
            c.vibrato_depth_target = 0;
            c.vibrato_fade_num_ticks = 0;
        },
        0xe5 => {
            if (p.pause_music_ctr == 0 and p.byte_3E1 == 0)
                p.master_volume = @as(u16, arg) << 8;
        },
        0xe6 => {
            p.master_volume_fade_ticks = arg;
            p.master_volume_fade_target = readCh(p, c);
            p.master_volume_fade_add_per_tick = SpcDivHelper(@as(i32, p.master_volume_fade_target) - @as(i32, hi(p.master_volume)), arg);
        },
        0xe7 => {
            p.tempo = @as(u16, arg) << 8;
        },
        0xe8 => {
            p.tempo_fade_num_ticks = arg;
            p.tempo_fade_final = readCh(p, c);
            p.tempo_fade_add = SpcDivHelper(@as(i32, p.tempo_fade_final) - @as(i32, hi(p.tempo)), arg);
        },
        0xe9 => {
            p.global_transposition = arg;
        },
        0xea => {
            c.channel_transposition = arg;
        },
        0xeb => {
            c.tremolo_delay_ticks = arg;
            c.tremolo_rate = readCh(p, c);
            c.tremolo_depth = readCh(p, c);
        },
        0xec => {
            c.tremolo_depth = 0;
        },
        0xed => {
            c.channel_volume = @as(u16, arg) << 8;
        },
        0xee => {
            c.volume_fade_ticks = arg;
            c.volume_fade_target = readCh(p, c);
            c.volume_fade_addpertick = SpcDivHelper(@as(i32, c.volume_fade_target) - @as(i32, hi(c.channel_volume)), arg);
        },
        0xef => {
            c.pattern_start_ptr = (@as(u16, readCh(p, c)) << 8) | arg;
            c.subroutine_num_loops = readCh(p, c);
            c.saved_pattern_ptr = c.pattern_order_ptr_for_chan;
            c.pattern_order_ptr_for_chan = c.pattern_start_ptr;
        },
        0xf0 => {
            c.vibrato_fade_num_ticks = arg;
            c.vibrato_fade_add_per_tick = if (arg != 0) c.vib_depth / arg else 0xff;
        },
        0xf4 => {
            c.fine_tune = arg;
        },
        0xf5 => {
            p.echo_channels = arg;
            p.reg_EON = arg;
            p.echo_volume_left = @as(u16, readCh(p, c)) << 8;
            p.echo_volume_right = @as(u16, readCh(p, c)) << 8;
            p.reg_FLG &= ~@as(u8, 0x20);
        },
        0xf6 => { // echo off
            p.echo_volume_left = 0;
            p.echo_volume_right = 0;
            p.reg_FLG |= 0x20;
        },
        0xf7 => {
            const kEchoFirParameters = [32]i8{
                127, 0,   0,   0,   0,   0,  0,   0,
                88,  -65, -37, -16, -2,  7,  12,  12,
                12,  33,  43,  43,  19,  -2, -13, -7,
                52,  51,  0,   -39, -27, 1,  -4,  -21,
            };
            SetupEchoParameter_EDL(p, arg);
            p.reg_EFB = readCh(p, c);
            const base: usize = @as(usize, readCh(p, c)) * 8;
            var i: usize = 0;
            while (i < 8) : (i += 1)
                Dsp_Write(p, FIR0 +% @as(u8, @intCast(i * 16)), @bitCast(kEchoFirParameters[base + i]));
        },
        0xf8 => {
            p.echo_volume_fade_ticks = arg;
            p.echo_volume_fade_target_left = readCh(p, c);
            p.echo_volume_fade_target_right = readCh(p, c);
            p.echo_volume_fade_add_left = SpcDivHelper(@as(i32, p.echo_volume_fade_target_left) - @as(i32, hi(p.echo_volume_left)), arg);
            p.echo_volume_fade_add_right = SpcDivHelper(@as(i32, p.echo_volume_fade_target_right) - @as(i32, hi(p.echo_volume_right)), arg);
        },
        0xf9 => {
            c.pitch_slide_delay_left = arg;
            c.pitch_slide_length = readCh(p, c);
            const note = readCh(p, c);
            ComputePitchAdd(c, @truncate(@as(u16, note) + @as(u16, p.global_transposition) + @as(u16, c.channel_transposition)));
        },
        0xfa => {
            p.percussion_base_id = arg;
        },
        else => Not_Implemented(),
    }
}

fn WantWriteKof(p: *SpcPlayer, c: *Channel) bool {
    var loops: i32 = c.subroutine_num_loops;
    var ptr: usize = c.pattern_order_ptr_for_chan;

    while (true) {
        var cmd = p.ram[ptr];
        ptr += 1;
        if (cmd == 0) {
            if (loops == 0)
                return true;
            loops -= 1;
            ptr = if (loops == 0) c.saved_pattern_ptr else c.pattern_start_ptr;
        } else {
            while ((cmd & 0x80) == 0) {
                cmd = p.ram[ptr];
                ptr += 1;
            }
            if (cmd == 0xc8)
                return false;
            if (cmd == 0xef) {
                ptr = @as(usize, p.ram[ptr]) | (@as(usize, p.ram[ptr + 1]) << 8);
            } else if (cmd >= 0xe0) {
                ptr += kEffectByteLength[cmd - 0xe0];
            } else {
                return true;
            }
        }
    }
}

fn HandleTremolo(p: *SpcPlayer, c: *Channel) void {
    _ = p;
    _ = c;
    Not_Implemented();
}

fn CalcVibratoAddPitch(p: *SpcPlayer, c: *Channel, pitch: u16, value: u8) void {
    var t: i32 = @as(i32, value) << 2;
    t ^= if ((t & 0x100) != 0) 0xff else 0;
    const tlo: i32 = @as(u8, @truncate(@as(u32, @bitCast(t))));
    const r: i32 = if (c.vib_depth >= 0xf1)
        tlo * @as(i32, c.vib_depth & 0xf)
    else
        (tlo * @as(i32, c.vib_depth)) >> 8;
    const delta: i32 = if ((value & 0x80) != 0) -r else r;
    WritePitch(p, c, pitch +% @as(u16, @bitCast(@as(i16, @truncate(delta)))));
}

fn HandlePanAndSweep(p: *SpcPlayer, c: *Channel) void {
    p.did_affect_volumepitch_flag = 0;
    if (c.tremolo_depth != 0) {
        c.tremolo_hold_count = c.tremolo_delay_ticks;
        HandleTremolo(p, c);
    }

    var volume: u16 = c.pan_value;

    if (c.pan_num_ticks != 0) {
        p.did_affect_volumepitch_flag = 0x80;
        const t: i32 = @divTrunc(@as(i32, p.main_tempo_accum) * @as(i32, @as(i16, @bitCast(c.pan_add_per_tick))), 256);
        volume +%= @as(u16, @bitCast(@as(i16, @truncate(t))));
    }

    if (p.did_affect_volumepitch_flag != 0)
        WriteVolumeToDsp(p, c, volume);

    p.did_affect_volumepitch_flag = 0;
    var pitch: u16 = c.pitch;
    if (c.pitch_slide_length != 0 and c.pitch_slide_delay_left == 0) {
        p.did_affect_volumepitch_flag |= 0x80;
        const t: i32 = @divTrunc(@as(i32, p.main_tempo_accum) * @as(i32, @as(i16, @bitCast(c.pitch_add_per_tick))), 256);
        pitch +%= @as(u16, @bitCast(@as(i16, @truncate(t))));
    }

    if (c.vib_depth != 0 and c.vibrato_delay_ticks == c.vibrato_hold_count) {
        const v: u8 = @truncate((@as(u16, p.main_tempo_accum) * @as(u16, c.vibrato_rate) >> 8) +% c.vibrato_count);
        CalcVibratoAddPitch(p, c, pitch, v);
        return;
    }

    if (p.did_affect_volumepitch_flag != 0)
        WritePitch(p, c, pitch);
}

fn HandleNoteTick(p: *SpcPlayer, c: *Channel) void {
    if (c.note_keyoff_ticks_left != 0) {
        c.note_keyoff_ticks_left -%= 1;
        if (c.note_keyoff_ticks_left == 0 or c.note_ticks_left == 2) {
            if (WantWriteKof(p, c) and (p.cur_chan_bit & p.is_chan_on) == 0)
                Dsp_Write(p, KOF, p.cur_chan_bit);
        }
    }

    p.did_affect_volumepitch_flag = 0;
    if (c.pitch_slide_length != 0) {
        if (c.pitch_slide_delay_left != 0) {
            c.pitch_slide_delay_left -%= 1;
        } else if ((p.is_chan_on & p.cur_chan_bit) == 0) {
            p.did_affect_volumepitch_flag = 0x80;
            c.pitch_slide_length -%= 1;
            Chan_DoAnyFade(&c.pitch, c.pitch_add_per_tick, c.pitch_target, c.pitch_slide_length);
        }
    }

    const pitch: u16 = c.pitch;

    if (c.vib_depth != 0) {
        if (c.vibrato_delay_ticks == c.vibrato_hold_count) {
            if (c.vibrato_change_count == c.vibrato_fade_num_ticks) {
                c.vib_depth = c.vibrato_depth_target;
            } else {
                const old_ccc = c.vibrato_change_count;
                c.vibrato_change_count +%= 1;
                c.vib_depth = (if (old_ccc == 0) @as(u8, 0) else c.vib_depth) +% c.vibrato_fade_add_per_tick;
            }
            c.vibrato_count +%= c.vibrato_rate;
            CalcVibratoAddPitch(p, c, pitch, c.vibrato_count);
            return;
        }
        c.vibrato_hold_count +%= 1;
    }

    if (p.did_affect_volumepitch_flag != 0)
        WritePitch(p, c, pitch);
}

pub export fn CalcFinalVolume(p: *SpcPlayer, c: *Channel, vol: u8) callconv(.c) void {
    var t: u32 = (@as(u32, hi(p.master_volume)) * @as(u32, vol)) >> 8;
    t = (t * @as(u32, c.channel_volume_master)) >> 8;
    t = (t * @as(u32, hi(c.channel_volume))) >> 8;
    c.final_volume = @truncate((t * t) >> 8);
}

pub export fn CalcTremolo(p: *SpcPlayer, c: *Channel) callconv(.c) void {
    _ = p;
    _ = c;
    Not_Implemented();
}

fn Chan_HandleTick(p: *SpcPlayer, c: *Channel) void {
    if (c.volume_fade_ticks != 0) {
        c.volume_fade_ticks -%= 1;
        p.vol_dirty |= p.cur_chan_bit;
        Chan_DoAnyFade(&c.channel_volume, c.volume_fade_addpertick, c.volume_fade_target, 1);
    }
    if (c.tremolo_depth != 0) {
        if (c.tremolo_delay_ticks == c.tremolo_hold_count) {
            p.vol_dirty |= p.cur_chan_bit;
            if ((c.tremolo_count & 0x80) != 0 and c.tremolo_depth == 0xff) {
                c.tremolo_count = 0x80;
            } else {
                c.tremolo_count +%= c.tremolo_rate;
            }
            CalcTremolo(p, c);
        } else {
            c.tremolo_hold_count +%= 1;
            CalcFinalVolume(p, c, 0xff);
        }
    } else {
        CalcFinalVolume(p, c, 0xff);
    }

    if (c.pan_num_ticks != 0) {
        c.pan_num_ticks -%= 1;
        p.vol_dirty |= p.cur_chan_bit;
        Chan_DoAnyFade(&c.pan_value, c.pan_add_per_tick, c.pan_target_value, 1);
    }

    if ((p.vol_dirty & p.cur_chan_bit) != 0)
        WriteVolumeToDsp(p, c, c.pan_value);
}

fn HandleCmd_0xf0_PauseMusic(p: *SpcPlayer) void {
    p.key_OFF = p.is_chan_on ^ 0xff;
    p.port_to_snes[0] = 0;
    p.cur_chan_bit = 0;
}

fn handleCmd00(p: *SpcPlayer) void {
    if (p.port_to_snes[0] == 0)
        return;
    if (p.pause_music_ctr != 0) {
        p.pause_music_ctr -%= 1;
        if (p.pause_music_ctr == 0) {
            HandleCmd_0xf0_PauseMusic(p);
            return;
        }
    }

    var enter_at_label_a = false;
    if (p.counter_sf0c == 0) {
        enter_at_label_a = true;
    } else {
        p.counter_sf0c -%= 1;
        if (p.counter_sf0c != 0) {
            Music_ResetChan(p);
            return;
        }
    }

    var t: u16 = 0;
    phrase_loop: while (true) {
        if (!enter_at_label_a) {
            // next_phrase
            find_phrase: while (true) {
                t = word(&p.ram, p.music_ptr_toplevel);
                p.music_ptr_toplevel +%= 2;
                if ((t >> 8) != 0) break :find_phrase;
                if (t == 0) {
                    HandleCmd_0xf0_PauseMusic(p);
                    return;
                }
                if (t == 0x80) {
                    p.fast_forward = 0x80;
                } else if (t == 0x81) {
                    p.fast_forward = 0;
                } else {
                    p.block_count -%= 1;
                    if ((p.block_count & 0x80) != 0) p.block_count = @truncate(t);
                    t = word(&p.ram, p.music_ptr_toplevel);
                    p.music_ptr_toplevel +%= 2;
                    if (p.block_count != 0) p.music_ptr_toplevel = t;
                }
            }
            {
                var i: usize = 0;
                while (i < 8) : (i += 1) {
                    p.channel[i].pattern_order_ptr_for_chan = word(&p.ram, t);
                    t +%= 2;
                }
            }
            {
                var ci: usize = 0;
                p.cur_chan_bit = 1;
                while (true) {
                    const c = &p.channel[ci];
                    if (hi(c.pattern_order_ptr_for_chan) != 0 and c.instrument_id == 0)
                        Channel_SetInstrument(p, c, 0);
                    c.subroutine_num_loops = 0;
                    c.volume_fade_ticks = 0;
                    c.pan_num_ticks = 0;
                    c.note_ticks_left = 1;
                    p.cur_chan_bit *%= 2;
                    if (p.cur_chan_bit == 0) break;
                    ci += 1;
                }
            }
        }
        enter_at_label_a = false;

        // label_a
        p.vol_dirty = 0;
        var restart = false;
        {
            var ci: usize = 0;
            p.cur_chan_bit = 1;
            channel_loop: while (true) {
                const c = &p.channel[ci];
                if (hi(c.pattern_order_ptr_for_chan) != 0) {
                    c.note_ticks_left -%= 1;
                    if (c.note_ticks_left == 0) {
                        inner: while (true) {
                            var cmd = readCh(p, c);
                            if (cmd == 0) {
                                if (c.subroutine_num_loops == 0) {
                                    restart = true;
                                    break :channel_loop;
                                }
                                c.subroutine_num_loops -%= 1;
                                c.pattern_order_ptr_for_chan = if (c.subroutine_num_loops == 0) c.saved_pattern_ptr else c.pattern_start_ptr;
                                continue :inner;
                            }
                            if ((cmd & 0x80) == 0) {
                                const kNoteVol = [16]u8{ 25, 50, 76, 101, 114, 127, 140, 152, 165, 178, 191, 203, 216, 229, 242, 252 };
                                const kNoteGateOffPct = [8]u8{ 50, 101, 127, 152, 178, 203, 229, 252 };
                                c.note_length = cmd;
                                cmd = readCh(p, c);
                                if ((cmd & 0x80) == 0) {
                                    c.note_gate_off_fixedpt = kNoteGateOffPct[(cmd >> 4) & 7];
                                    c.channel_volume_master = kNoteVol[cmd & 0xf];
                                    cmd = readCh(p, c);
                                }
                            }
                            if (cmd >= 0xe0) {
                                HandleEffect(p, c, cmd);
                                continue :inner;
                            }
                            if (p.fast_forward == 0 and (p.is_chan_on & p.cur_chan_bit) == 0)
                                PlayNote(p, c, cmd);
                            c.note_ticks_left = c.note_length;
                            const tt: u16 = (@as(u16, c.note_ticks_left) * @as(u16, c.note_gate_off_fixedpt)) >> 8;
                            c.note_keyoff_ticks_left = if (tt != 0) @truncate(tt) else 1;
                            PitchSlideToNote_Check(p, c);
                            break :inner;
                        }
                    } else if (p.fast_forward == 0) {
                        HandleNoteTick(p, c);
                        PitchSlideToNote_Check(p, c);
                    }
                }
                p.cur_chan_bit *%= 2;
                if (p.cur_chan_bit == 0) break;
                ci += 1;
            }
        }
        if (restart) continue :phrase_loop;

        if (p.tempo_fade_num_ticks != 0) {
            p.tempo_fade_num_ticks -%= 1;
            p.tempo = if (p.tempo_fade_num_ticks == 0) (@as(u16, p.tempo_fade_final) << 8) else p.tempo +% p.tempo_fade_add;
        }
        if (p.echo_volume_fade_ticks != 0) {
            p.echo_volume_left +%= p.echo_volume_fade_add_left;
            p.echo_volume_right +%= p.echo_volume_fade_add_right;
            p.echo_volume_fade_ticks -%= 1;
            if (p.echo_volume_fade_ticks == 0) {
                p.echo_volume_left = @as(u16, p.echo_volume_fade_target_left) << 8;
                p.echo_volume_right = @as(u16, p.echo_volume_fade_target_right) << 8;
            }
        }
        if (p.master_volume_fade_ticks != 0) {
            p.master_volume_fade_ticks -%= 1;
            p.master_volume = if (p.master_volume_fade_ticks == 0) (@as(u16, p.master_volume_fade_target) << 8) else p.master_volume +% p.master_volume_fade_add_per_tick;
            p.vol_dirty = 0xff;
        }
        {
            var ci: usize = 0;
            p.cur_chan_bit = 1;
            while (true) {
                const c = &p.channel[ci];
                if (hi(c.pattern_order_ptr_for_chan) != 0)
                    Chan_HandleTick(p, c);
                p.cur_chan_bit *%= 2;
                if (p.cur_chan_bit == 0) break;
                ci += 1;
            }
        }
        break;
    }
}

fn Port0_HandleMusic(p: *SpcPlayer) void {
    const a = p.new_value_from_snes[0];

    if (a == 0) {
        handleCmd00(p);
    } else if (a == 0xff) {
        // Load new music
        Not_Implemented();
    } else if (a == 0xf1) { // continue music
        p.master_volume_fade_ticks = 0x80;
        p.pause_music_ctr = 0x80;
        p.master_volume_fade_target = 0;
        p.master_volume_fade_add_per_tick = SpcDivHelper(0 - @as(i32, hi(p.master_volume)), 0x80);
        handleCmd00(p);
    } else if (a == 0xf2) {
        if (p.byte_3E1 != 0) return;
        p.byte_3E1 = hi(p.master_volume);
        setHi(&p.master_volume, 0x70);
        handleCmd00(p);
    } else if (a == 0xf3) {
        if (p.byte_3E1 == 0) return;
        setHi(&p.master_volume, p.byte_3E1);
        p.byte_3E1 = 0;
        handleCmd00(p);
    } else if (a == 0xf0) {
        HandleCmd_0xf0_PauseMusic(p);
    } else {
        p.pause_music_ctr = 0;
        p.byte_3E1 = 0;
        p.port_to_snes[0] = a;
        p.music_ptr_toplevel = word(&p.ram, 0xD000 + (@as(usize, a) - 1) * 2);
        p.counter_sf0c = 2;
        p.key_OFF |= p.is_chan_on ^ 0xff;
    }
}

inline fn Asl(ptr: *u8) u8 {
    const old = ptr.*;
    ptr.* = ptr.* *% 2;
    return old >> 7;
}

fn Sfx_TurnOffChannel(p: *SpcPlayer, c: *Channel) void {
    c.sfx_which_sound = 0;
    p.is_chan_on &= ~p.current_bit;
    p.port1_active &= ~p.current_bit;
    p.port2_active &= ~p.current_bit;
    p.port3_active &= ~p.current_bit;
    Channel_SetInstrument(p, c, c.instrument_id);
    if ((p.echo_channels & p.current_bit) != 0 and (p.reg_EON & p.current_bit) == 0) {
        p.reg_EON |= p.current_bit;
        Dsp_Write(p, EON, p.reg_EON);
        p.sfx_channels_echo_mask2 &= ~p.current_bit;
    }
}

fn Write_KeyOn(p: *SpcPlayer, bit: u8) void {
    Dsp_Write(p, KOF, 0);
    Dsp_Write(p, KON, bit);
}

fn PlayNote(p: *SpcPlayer, c: *Channel, note_in: u8) void {
    var note = note_in;
    if (note >= 0xca) {
        Channel_SetInstrument(p, c, note);
        note = 0xa4;
    }

    if (note >= 0xc8 or (p.is_chan_on & p.cur_chan_bit) != 0)
        return;

    const sum: u32 = @as(u32, note & 0x7f) + @as(u32, p.global_transposition) + @as(u32, c.channel_transposition);
    c.pitch = @truncate((sum << 8) | c.fine_tune);
    c.vibrato_count = @truncate(@as(u16, c.vibrato_fade_num_ticks) << 7);
    c.vibrato_hold_count = 0;
    c.vibrato_change_count = 0;
    c.tremolo_count = 0;
    c.tremolo_hold_count = 0;
    p.vol_dirty |= p.cur_chan_bit;
    p.key_ON |= p.cur_chan_bit;
    c.pitch_slide_length = c.pitch_envelope_num_ticks;
    if (c.pitch_slide_length != 0) {
        c.pitch_slide_delay_left = c.pitch_envelope_delay;
        if (c.pitch_envelope_direction == 0)
            c.pitch -%= @as(u16, c.pitch_envelope_slide_value) << 8;
        ComputePitchAdd(c, @truncate(@as(u16, hi(c.pitch)) + @as(u16, c.pitch_envelope_slide_value)));
    }
    WritePitch(p, c, c.pitch);
}

fn Sfx_MaybeDisableEcho(p: *SpcPlayer) void {
    if ((p.port_to_snes[0] & 0x10) == 0 or (p.current_bit & p.sfx_channels_echo_mask2) != 0) {
        if ((p.current_bit & p.reg_EON) != 0) {
            p.reg_EON ^= p.current_bit;
            Dsp_Write(p, EON, p.reg_EON);
        }
    }
}

fn sfxNoteContinue(p: *SpcPlayer, c: *Channel) void {
    p.did_affect_volumepitch_flag = 0;
    if (c.pitch_slide_length != 0) {
        p.did_affect_volumepitch_flag = 0x80;
        c.pitch_slide_length -%= 1;
        Chan_DoAnyFade(&c.pitch, c.pitch_add_per_tick, c.pitch_target, c.pitch_slide_length);
        p.cur_chan_bit = 0; // force change through
        WritePitch(p, c, c.pitch);
    } else if (c.sfx_note_length_left == 2) {
        Dsp_Write(p, KOF, p.current_bit);
    }
}

fn Sfx_ChannelTick(p: *SpcPlayer, c: *Channel, is_continue: bool) void {
    if (is_continue) {
        Sfx_MaybeDisableEcho(p);
        p.sfx_channel_index = c.index *% 2;
        p.sfx_sound_ptr_cur = c.sfx_sound_ptr;
        c.sfx_note_length_left -%= 1;
        if (c.sfx_note_length_left != 0) {
            sfxNoteContinue(p, c);
            c.sfx_sound_ptr = p.sfx_sound_ptr_cur;
            return;
        }
        p.sfx_sound_ptr_cur +%= 1;
    }

    while (true) {
        p.dsp_register_index = p.sfx_channel_index *% 8;

        var cmd = p.ram[p.sfx_sound_ptr_cur];
        if (cmd == 0) {
            Sfx_TurnOffChannel(p, c);
            return;
        }

        if ((cmd & 0x80) == 0) {
            c.sfx_note_length = cmd;
            p.sfx_sound_ptr_cur +%= 1;
            cmd = p.ram[p.sfx_sound_ptr_cur];
            if ((cmd & 0x80) == 0) {
                if ((p.port1_active & p.current_bit) != 0) {
                    if (cmd == 0 or p.channel_67_volume == 0) {
                        const volume = cmd;
                        Dsp_Write(p, p.dsp_register_index +% V0VOLL, cmd);
                        p.sfx_sound_ptr_cur +%= 1;
                        cmd = p.ram[p.sfx_sound_ptr_cur];
                        if ((cmd & 0x80) != 0) {
                            Dsp_Write(p, p.dsp_register_index +% V0VOLR, volume);
                        } else {
                            Dsp_Write(p, p.dsp_register_index +% V0VOLR, cmd);
                            p.sfx_sound_ptr_cur +%= 1;
                            cmd = p.ram[p.sfx_sound_ptr_cur];
                        }
                    } else {
                        p.sfx_sound_ptr_cur +%= 1;
                        cmd = p.ram[p.sfx_sound_ptr_cur];
                    }
                } else {
                    c.final_volume = cmd *% 2;
                    c.pan_flag_with_phase_invert = 10;
                    const panv: u16 = @as(u16, if ((p.sfx_start_arg_pan & 0x80) != 0) 16 else if ((p.sfx_start_arg_pan & 0x40) != 0) 4 else 10) << 8;
                    WriteVolumeToDsp(p, c, panv);
                    p.sfx_sound_ptr_cur +%= 1;
                    cmd = p.ram[p.sfx_sound_ptr_cur];
                }
            }
        }
        // cmd_parsed
        if (cmd == 0xe0) {
            p.sfx_sound_ptr_cur +%= 1;
            const ip = p.ram[0x3E00 + @as(usize, p.ram[p.sfx_sound_ptr_cur]) * 9 ..];
            const reg: u8 = c.index *% 16;
            Dsp_Write(p, reg +% V0VOLL, ip[0]);
            Dsp_Write(p, reg +% V0VOLR, ip[1]);
            Dsp_Write(p, reg +% V0PITCHL, ip[2]);
            Dsp_Write(p, reg +% V0PITCHH, ip[3]);
            Dsp_Write(p, reg +% V0SRCN, ip[4]);
            Dsp_Write(p, reg +% V0ADSR1, ip[5]);
            Dsp_Write(p, reg +% V0ADSR2, ip[6]);
            Dsp_Write(p, reg +% V0GAIN, ip[7]);
            c.instrument_pitch_base = @as(u16, ip[8]) << 8;
            p.sfx_sound_ptr_cur +%= 1;
        } else if (cmd == 0xf9 or cmd == 0xf1) {
            if (cmd == 0xf9) {
                p.sfx_sound_ptr_cur +%= 1;
                PlayNote(p, c, p.ram[p.sfx_sound_ptr_cur]);
                Write_KeyOn(p, p.current_bit);
            }
            p.sfx_sound_ptr_cur +%= 1;
            c.pitch_slide_delay_left = p.ram[p.sfx_sound_ptr_cur];
            p.sfx_sound_ptr_cur +%= 1;
            c.pitch_slide_length = p.ram[p.sfx_sound_ptr_cur];
            p.sfx_sound_ptr_cur +%= 1;
            ComputePitchAdd(c, p.ram[p.sfx_sound_ptr_cur]);
            c.sfx_note_length_left = c.sfx_note_length;
            sfxNoteContinue(p, c);
            break;
        } else if (cmd == 0xff) {
            const idx: usize = @bitCast(@as(isize, 0x17C0) + (@as(isize, c.sfx_which_sound) - 1) * 2);
            const v = word(&p.ram, idx);
            c.sfx_sound_ptr = v;
            p.sfx_sound_ptr_cur = v;
        } else {
            PlayNote(p, c, cmd);
            Write_KeyOn(p, p.current_bit);
            c.sfx_note_length_left = c.sfx_note_length;
            sfxNoteContinue(p, c);
            break;
        }
    }
    c.sfx_sound_ptr = p.sfx_sound_ptr_cur;
}

fn Port1_Play_Inner(p: *SpcPlayer) void {
    p.port1_counter = 0;
    var c = &p.channel[7];
    c.sfx_which_sound = p.new_value_from_snes[1];
    c.sfx_arr_countdown = 3;
    c.pitch_envelope_num_ticks = 0;
    p.port1_active = 0x80;
    p.is_chan_on |= 0x80;
    Dsp_Write(p, KOF, 0x80);
    p.new_value_from_snes[1] = p.ram[0x1800 + @as(usize, p.new_value_from_snes[1]) - 1];
    if (p.new_value_from_snes[1] == 0)
        return;
    c = &p.channel[6];
    c.sfx_which_sound = p.new_value_from_snes[1];
    c.sfx_arr_countdown = 3;
    c.pitch_envelope_num_ticks = 0;
    p.port1_active = 0x40;
    p.is_chan_on |= 0x40;
    Dsp_Write(p, KOF, 0x40);
    p.port1_active = 0xc0;
    p.sfx_channels_echo_mask2 |= 0xc0;
    p.port2_active &= 0x3f;
    p.port3_active &= 0x3f;
}

fn Port1_StartNewSound(p: *SpcPlayer) void {
    if (p.port1_counter != 0) {
        p.port1_counter -%= 1;
        if (p.port1_counter == 0) {
            p.new_value_from_snes[1] = 5;
            Port1_Play_Inner(p);
            p.new_value_from_snes[1] = 0;
            return;
        }
        p.channel_67_volume = p.port1_counter >> 1;
        Dsp_Write(p, V7VOLL, p.channel_67_volume);
        Dsp_Write(p, V7VOLR, p.channel_67_volume);
        Dsp_Write(p, V6VOLL, p.channel_67_volume);
        Dsp_Write(p, V6VOLR, p.channel_67_volume);
    }
    p.port1_current_bit = p.port1_active;
    if (p.port1_current_bit == 0)
        return;
    var ci: usize = 7;
    p.current_bit = 0x80;
    while (true) {
        const c = &p.channel[ci];
        if (Asl(&p.port1_current_bit) != 0) {
            p.sfx_channel_index = c.index *% 2;
            p.dsp_register_index = c.index *% 16;
            p.sfx_start_arg_pan = c.sfx_pan;
            if (c.sfx_arr_countdown == 0) {
                if (c.sfx_which_sound != 0)
                    Sfx_ChannelTick(p, c, true);
            } else {
                p.sfx_channel_index = c.index *% 2;
                c.sfx_arr_countdown -%= 1;
                if (c.sfx_arr_countdown == 0) {
                    const idx: usize = @bitCast(@as(isize, 0x17C0) + (@as(isize, c.sfx_which_sound) - 1) * 2);
                    const v = word(&p.ram, idx);
                    c.sfx_sound_ptr = v;
                    p.sfx_sound_ptr_cur = v;
                    Sfx_ChannelTick(p, c, false);
                }
            }
        }
        ci -= 1;
        p.current_bit >>= 1;
        if (p.current_bit == 0x10) break;
    }
}

fn Port1_HandleCmd(p: *SpcPlayer) void {
    const a = p.new_value_from_snes[1];
    if ((a & 0x80) == 0) {
        if (a != 0) {
            p.port_to_snes[1] = a;
            if (a != 5 or p.port1_active != 0)
                Port1_Play_Inner(p);
        }
    } else {
        p.port_to_snes[1] = a;
        if (p.port1_active != 0)
            p.port1_counter = 0x78;
    }
}

fn Port2_StartNewSound(p: *SpcPlayer) void {
    p.port2_current_bit = p.port2_active;
    if (p.port2_current_bit == 0)
        return;
    var ci: usize = 7;
    p.current_bit = 0x80;
    while (true) {
        const c = &p.channel[ci];
        if (Asl(&p.port2_current_bit) != 0) {
            p.sfx_channel_index = c.index *% 2;
            p.dsp_register_index = c.index *% 16;
            p.sfx_start_arg_pan = c.sfx_pan;
            if (c.sfx_arr_countdown == 0) {
                if (c.sfx_which_sound != 0)
                    Sfx_ChannelTick(p, c, true);
            } else {
                p.sfx_channel_index = c.index *% 2;
                c.sfx_arr_countdown -%= 1;
                if (c.sfx_arr_countdown == 0) {
                    const idx: usize = @bitCast(@as(isize, 0x1820) + (@as(isize, c.sfx_which_sound) - 1) * 2);
                    const v = word(&p.ram, idx);
                    c.sfx_sound_ptr = v;
                    p.sfx_sound_ptr_cur = v;
                    Sfx_ChannelTick(p, c, false);
                }
            }
        }
        p.current_bit >>= 1;
        if (p.current_bit == 0) break;
        ci -= 1;
    }
}

fn Port2_AllocateChan(p: *SpcPlayer) *Channel {
    p.sfx_play_echo_flag = p.ram[0x18dd + @as(usize, p.new_value_from_snes[2] & 0x3f) - 1];
    var found: ?usize = null;
    {
        var ci: usize = 7;
        p.current_bit = 0x80;
        while (true) {
            const c = &p.channel[ci];
            if ((p.port2_active & p.current_bit) != 0 and (c.sfx_which_sound +% c.sfx_pan) == p.new_value_from_snes[2]) {
                found = ci;
                break;
            }
            p.current_bit >>= 1;
            if (p.current_bit == 0) break;
            ci -= 1;
        }
    }
    if (found == null) {
        var ci: usize = 7;
        p.current_bit = 0x80;
        while (true) {
            if ((p.is_chan_on & p.current_bit) == 0) {
                found = ci;
                break;
            }
            p.current_bit >>= 1;
            if (p.current_bit == 0) break;
            ci -= 1;
        }
    }
    const c = &p.channel[found orelse @panic("Port2_AllocateChan: no free channel")];
    p.sfx_channel_index = c.index *% 2;
    p.sfx_channel_index2 = p.sfx_channel_index;
    p.sfx_channel_bit = p.current_bit;
    p.is_chan_on |= p.current_bit;
    if (p.sfx_play_echo_flag != 0)
        p.sfx_channels_echo_mask2 |= p.current_bit;
    Sfx_MaybeDisableEcho(p);
    return c;
}

fn Port2_HandleCmd(p: *SpcPlayer) void {
    while (p.new_value_from_snes[2] != 0 and p.is_chan_on != 0xff) {
        const c = Port2_AllocateChan(p);
        c.sfx_pan = p.new_value_from_snes[2] & 0xc0;
        c.sfx_which_sound = p.new_value_from_snes[2] & 0x3f;
        c.sfx_arr_countdown = 3;
        c.pitch_envelope_num_ticks = 0;
        p.port2_active |= p.current_bit;
        Dsp_Write(p, KOF, p.current_bit);
        p.new_value_from_snes[2] = p.ram[0x189e + @as(usize, c.sfx_which_sound) - 1];
    }
}

fn Port3_StartNewSound(p: *SpcPlayer) void {
    p.port3_current_bit = p.port3_active;
    if (p.port3_current_bit == 0)
        return;
    var ci: usize = 7;
    p.current_bit = 0x80;
    while (true) {
        const c = &p.channel[ci];
        if (Asl(&p.port3_current_bit) != 0) {
            p.sfx_channel_index = c.index *% 2;
            p.dsp_register_index = c.index *% 16;
            p.sfx_start_arg_pan = c.sfx_pan;
            if (c.sfx_arr_countdown == 0) {
                if (c.sfx_which_sound != 0)
                    Sfx_ChannelTick(p, c, true);
            } else {
                p.sfx_channel_index = c.index *% 2;
                c.sfx_arr_countdown -%= 1;
                if (c.sfx_arr_countdown == 0) {
                    const idx: usize = @bitCast(@as(isize, 0x191C) + (@as(isize, c.sfx_which_sound) - 1) * 2);
                    const v = word(&p.ram, idx);
                    c.sfx_sound_ptr = v;
                    p.sfx_sound_ptr_cur = v;
                    Sfx_ChannelTick(p, c, false);
                }
            }
        }
        p.current_bit >>= 1;
        if (p.current_bit == 0) break;
        ci -= 1;
    }
}

fn Port3_AllocateChan(p: *SpcPlayer) *Channel {
    p.sfx_play_echo_flag = p.ram[0x19d8 + @as(usize, p.new_value_from_snes[3] & 0x3f)];
    var found: ?usize = null;
    {
        var ci: usize = 7;
        p.current_bit = 0x80;
        while (true) {
            const c = &p.channel[ci];
            if ((p.port3_active & p.current_bit) != 0 and (c.sfx_which_sound +% c.sfx_pan) == p.new_value_from_snes[3]) {
                found = ci;
                break;
            }
            p.current_bit >>= 1;
            if (p.current_bit == 0) break;
            ci -= 1;
        }
    }
    if (found == null) {
        var ci: usize = 7;
        p.current_bit = 0x80;
        while (true) {
            if ((p.is_chan_on & p.current_bit) == 0) {
                found = ci;
                break;
            }
            p.current_bit >>= 1;
            if (p.current_bit == 0) break;
            ci -= 1;
        }
    }
    const c = &p.channel[found orelse @panic("Port3_AllocateChan: no free channel")];
    p.sfx_channel_index = c.index *% 2;
    p.sfx_channel_index2 = p.sfx_channel_index;
    p.sfx_channel_bit = p.current_bit;
    p.is_chan_on |= p.current_bit;
    if (p.sfx_play_echo_flag != 0)
        p.sfx_channels_echo_mask2 |= p.current_bit;
    Sfx_MaybeDisableEcho(p);
    return c;
}

fn Port3_HandleCmd(p: *SpcPlayer) void {
    while (p.new_value_from_snes[3] != 0 and p.is_chan_on != 0xff) {
        const c = Port3_AllocateChan(p);
        c.sfx_pan = p.new_value_from_snes[3] & 0xc0;
        c.sfx_which_sound = p.new_value_from_snes[3] & 0x3f;
        c.sfx_arr_countdown = 3;
        c.pitch_envelope_num_ticks = 0;
        p.port3_active |= p.current_bit;
        Dsp_Write(p, KOF, p.current_bit);
        p.new_value_from_snes[3] = p.ram[0x199a + @as(usize, c.sfx_which_sound) - 1];
    }
}

fn ReadPortFromSnes(p: *SpcPlayer, port: usize) void {
    const old = p.last_value_from_snes[port];
    p.last_value_from_snes[port] = p.input_ports[port];
    if (p.input_ports[port] != old)
        p.new_value_from_snes[port] = p.input_ports[port]
    else
        p.new_value_from_snes[port] = 0;
}

fn Spc_Loop_Part1(p: *SpcPlayer) void {
    Dsp_Write(p, KOF, p.key_OFF);
    Dsp_Write(p, PMON, p.reg_PMON);
    Dsp_Write(p, NON, p.reg_NON);
    Dsp_Write(p, KOF, 0);
    Dsp_Write(p, KON, p.key_ON);
    if ((p.echo_stored_time & 0x80) == 0) {
        Dsp_Write(p, FLG, p.reg_FLG);
        if (p.echo_stored_time == p.echo_parameter_EDL) {
            Dsp_Write(p, EON, p.reg_EON);
            Dsp_Write(p, EFB, p.reg_EFB);
            Dsp_Write(p, EVOLR, hi(p.echo_volume_right));
            Dsp_Write(p, EVOLL, hi(p.echo_volume_left));
        }
    }
    p.key_OFF = 0;
    p.key_ON = 0;
}

fn Spc_Loop_Part2(p: *SpcPlayer, ticks: u8) void {
    const add1: u8 = @truncate(@as(u16, ticks) *% 0x38);
    const t1: u16 = @as(u16, p.sfx_timer_accum) + @as(u16, add1);
    p.sfx_timer_accum = @truncate(t1);
    if (t1 >= 256) {
        Port1_StartNewSound(p);
        Port1_HandleCmd(p);
        ReadPortFromSnes(p, 1);

        Port2_StartNewSound(p);
        Port2_HandleCmd(p);
        ReadPortFromSnes(p, 2);

        Port3_StartNewSound(p);
        Port3_HandleCmd(p);
        ReadPortFromSnes(p, 3);

        if (p.echo_stored_time != p.echo_parameter_EDL) {
            p.echo_fract_incr +%= 1;
            if ((p.echo_fract_incr & 1) == 0)
                p.echo_stored_time +%= 1;
        }
    }

    const add2: u8 = @truncate(@as(u16, ticks) *% @as(u16, hi(p.tempo)));
    const t2: u16 = @as(u16, p.main_tempo_accum) + @as(u16, add2);
    p.main_tempo_accum = @truncate(t2);
    if (t2 >= 256) {
        Port0_HandleMusic(p);
        ReadPortFromSnes(p, 0);
    } else if (p.port_to_snes[0] != 0) {
        var ci: usize = 0;
        p.cur_chan_bit = 1;
        while (p.cur_chan_bit != 0) : ({
            p.cur_chan_bit *%= 2;
            ci += 1;
        }) {
            const c = &p.channel[ci];
            if (hi(c.pattern_order_ptr_for_chan) != 0)
                HandlePanAndSweep(p, c);
        }
    }
}

fn Interrupt_Reset(p: *SpcPlayer) void {
    dsp_reset(p.dsp.?);

    const base: [*]u8 = @ptrCast(p);
    const start = @offsetOf(SpcPlayer, "new_value_from_snes");
    @memset(base[start..@sizeOf(SpcPlayer)], 0);
    for (0..8) |i| p.channel[i].index = @intCast(i);
    SetupEchoParameter_EDL(p, 1);
    p.reg_FLG |= 0x20;
    Dsp_Write(p, MVOLL, 0x60);
    Dsp_Write(p, MVOLR, 0x60);
    Dsp_Write(p, DIR, 0x3c);
    setHi(&p.tempo, 16);
    p.timer_cycles = 0;
}

pub export fn SpcPlayer_Create() callconv(.c) *SpcPlayer {
    const p: *SpcPlayer = @ptrCast(@alignCast(malloc(@sizeOf(SpcPlayer)).?));
    p.dsp = dsp_init(&p.ram);
    p.reg_write_history = null;
    return p;
}

pub export fn SpcPlayer_Initialize(p: *SpcPlayer) callconv(.c) void {
    Interrupt_Reset(p);
    Spc_Loop_Part1(p);
}

pub export fn SpcPlayer_CopyVariablesToRam(p: *SpcPlayer) callconv(.c) void {
    const pbytes: [*]u8 = @ptrCast(p);
    for (0..8) |i| {
        const cbytes: [*]u8 = @ptrCast(&p.channel[i]);
        for (kChannel_Maps) |m| {
            const dst = (m.org_off & 0x7fff) + i * 2;
            const n: usize = if ((m.org_off & 0x8000) != 0) 2 else 1;
            @memcpy(p.ram[dst..][0..n], cbytes[m.off..][0..n]);
        }
    }
    for (kSpcPlayer_Maps) |m| {
        @memcpy(p.ram[m.org_off..][0..m.size], pbytes[m.off..][0..m.size]);
    }
}

pub export fn SpcPlayer_CopyVariablesFromRam(p: *SpcPlayer) callconv(.c) void {
    const pbytes: [*]u8 = @ptrCast(p);
    for (0..8) |i| {
        const cbytes: [*]u8 = @ptrCast(&p.channel[i]);
        for (kChannel_Maps) |m| {
            const src = (m.org_off & 0x7fff) + i * 2;
            const n: usize = if ((m.org_off & 0x8000) != 0) 2 else 1;
            @memcpy(cbytes[m.off..][0..n], p.ram[src..][0..n]);
        }
    }
    for (kSpcPlayer_Maps) |m| {
        @memcpy(pbytes[m.off..][0..m.size], p.ram[m.org_off..][0..m.size]);
    }
}

pub export fn SpcPlayer_GenerateSamples(p: *SpcPlayer) callconv(.c) void {
    std.debug.assert(p.timer_cycles <= 64);
    std.debug.assert(p.dsp.?.sampleOffset <= 534);

    while (true) {
        if (p.timer_cycles >= 64) {
            Spc_Loop_Part2(p, p.timer_cycles >> 6);
            Spc_Loop_Part1(p);
            p.timer_cycles &= 63;
        }

        // sample rate 32000
        var n: i32 = 534 - @as(i32, p.dsp.?.sampleOffset);
        if (n > (64 - @as(i32, p.timer_cycles)))
            n = 64 - @as(i32, p.timer_cycles);

        p.timer_cycles +%= @intCast(n);

        var i: i32 = 0;
        while (i < n) : (i += 1)
            dsp_cycle(p.dsp.?);

        if (p.dsp.?.sampleOffset == 534)
            break;
    }
}

pub export fn SpcPlayer_Upload(p: *SpcPlayer, data_in: [*]const u8) callconv(.c) void {
    var data = data_in;
    Dsp_Write(p, EVOLL, 0);
    Dsp_Write(p, EVOLR, 0);
    Dsp_Write(p, KOF, 0xff);

    while (true) {
        var numbytes: u32 = @as(u16, data[0]) | (@as(u16, data[1]) << 8);
        if (numbytes == 0)
            break;
        var target: u16 = @as(u16, data[2]) | (@as(u16, data[3]) << 8);
        data += 4;
        while (true) {
            p.ram[target] = data[0];
            target +%= 1;
            data += 1;
            numbytes -= 1;
            if (numbytes == 0) break;
        }
    }
    p.pause_music_ctr = 0;
    p.port_to_snes[0] = 0;
    p.port1_active = 0;
    p.port2_active = 0;
    p.port3_active = 0;
    p.is_chan_on = 0;
    p.input_ports[0] = 0;
    p.input_ports[1] = 0;
    p.input_ports[2] = 0;
    p.input_ports[3] = 0;
}
