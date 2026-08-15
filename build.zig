const std = @import("std");

// Phase 0 of the C -> Zig port: compile the existing, unmodified C codebase
// with Zig's build system so the toolchain and RAM-compare parity workflow
// are proven before any game code is translated. Mirrors taskfile.yml's
// `build`/`compile` tasks exactly (same source list, same flags).
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // Default to ReleaseFast (parity with the C build's -O2) rather than
    // Debug; `zig build -Doptimize=Debug` still overrides for local debugging.
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Prioritize performance, safety, or binary size") orelse .ReleaseFast;

    // The exe module's root_source_file is the first ported Zig module that
    // exports C-ABI symbols consumed by the remaining C translation units
    // (util.zig replaces util.c; StrFmt stays in C in util_strfmt.c). Zig
    // compiles it into the same object set as the C sources below, so the
    // C callers link unchanged. Later ports (config.zig) are separate
    // compilation units: b.addObject + addObjectFile wires them in.
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/util.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const exe = b.addExecutable(.{
        .name = "zelda3",
        .root_module = exe_mod,
    });
    // The C main() in src/main.c is the program entry point; the Zig root
    // module only exports C-ABI symbols consumed by the C side.
    exe.entry = .disabled;

    exe_mod.addIncludePath(b.path("."));

    exe_mod.addCSourceFiles(.{
        .files = &sources,
        .flags = &.{"-DSYSTEM_VOLUME_MIXER_AVAILABLE=0"},
    });

    exe.root_module.addObjectFile(addPortedModule(b, target, optimize, "config"));
    exe.root_module.addObjectFile(addPortedModule(b, target, optimize, "spc_player"));
    exe.root_module.addObjectFile(addPortedModule(b, target, optimize, "poly"));
    exe.root_module.addObjectFile(addPortedModule(b, target, optimize, "tile_detect"));
    exe.root_module.addObjectFile(addPortedModule(b, target, optimize, "load_gfx"));
    exe.root_module.addObjectFile(addPortedModule(b, target, optimize, "nmi"));
    exe.root_module.addObjectFile(addPortedModule(b, target, optimize, "overlord"));
    exe.root_module.addObjectFile(addPortedModule(b, target, optimize, "player_oam"));
    exe.root_module.addObjectFile(addPortedModuleAt(b, target, optimize, "input", "snes/input.zig"));
    exe.root_module.addObjectFile(addPortedModuleAt(b, target, optimize, "cart", "snes/cart.zig"));
    exe.root_module.addObjectFile(addPortedModuleAt(b, target, optimize, "apu", "snes/apu.zig"));
    exe.root_module.addObjectFile(addPortedModuleAt(b, target, optimize, "dma", "snes/dma.zig"));
    exe.root_module.addObjectFile(addPortedModuleAt(b, target, optimize, "dsp", "snes/dsp.zig"));
    exe.root_module.addObjectFile(addPortedModuleAt(b, target, optimize, "spc", "snes/spc.zig"));
    exe.root_module.addObjectFile(addPortedModuleAt(b, target, optimize, "ppu", "snes/ppu.zig"));
    exe.root_module.addObjectFile(addPortedModuleAt(b, target, optimize, "snes", "snes/snes.zig"));
    exe.root_module.addObjectFile(addPortedModuleAt(b, target, optimize, "snes_other", "snes/snes_other.zig"));

    linkSdl2(b, exe_mod);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the zelda3 binary");
    run_step.dependOn(&run_cmd.step);

    addTestStep(b, "test", "Run Tier-A unit tests for ported Zig modules", &unit_test_files, target, optimize);
    addDiffTestStep(b, target, optimize);
}

// Tier-A unit tests for ported Zig modules (zig build test). Empty until a
// C module is ported to idiomatic Zig; each port task appends its own
// .zig test file here rather than this being wired up speculatively.
const unit_test_files = [_][]const u8{
    "src/types_test.zig",
    "src/variables_test.zig",
    "src/config_test.zig",
    "src/config_test2.zig",
    "src/config_test3.zig",
    "src/config_test4.zig",
    "src/config_test5.zig",
    "src/poly_test.zig",
    "src/tile_detect_test.zig",
    "src/util_test.zig",
    "snes/input_test.zig",
    "snes/cart_test.zig",
    "snes/apu_test.zig",
    "snes/dma_test.zig",
    "snes/dsp_test.zig",
    "snes/spc_test.zig",
    "snes/ppu_test.zig",
};

// Tier-B differential tests: behavioral-equivalence checks between a
// pre-port C object (symbols renamed via the preprocessor) and its ported .zig
// module, run over randomized inputs. Empty until a module is ported;
// each port task wires its own differential harness here.
const diff_test_files = [_][]const u8{
    "src/util_difftest.zig",
    "src/config_difftest.zig",
    "src/poly_difftest.zig",
    "src/tile_detect_difftest.zig",
    "snes/input_difftest.zig",
    "snes/cart_difftest.zig",
    "snes/apu_difftest.zig",
    "snes/dma_difftest.zig",
    "snes/dsp_difftest.zig",
    "snes/spc_difftest.zig",
    "snes/ppu_difftest.zig",
};

fn addTestStep(b: *std.Build, name: []const u8, desc: []const u8, files: []const []const u8, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const step = b.step(name, desc);
    for (files) |file| {
        const test_mod = b.createModule(.{
            .root_source_file = b.path(file),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        const mod_test = b.addTest(.{
            .root_module = test_mod,
        });
        // config_test*.zig exercise ParseConfigFile through SDL key name
        // lookups, stubbed via other/sdl_keyname_stub.c (compiles against the
        // real SDL2 headers for exact keycode values). config.zig's plain
        // util externs resolve against util.o (the same split the exe uses).
        if (std.mem.startsWith(u8, file, "src/config_test")) {
            mod_test.root_module.addObjectFile(addSdlKeyStub(b, target, optimize));
            mod_test.root_module.addObjectFile(addPortedModule(b, target, optimize, "util"));
        }
        const run_test = b.addRunArtifact(mod_test);
        step.dependOn(&run_test.step);
    }
}

// Compile <name>.zig as its own object (a ported C module, exporting the
// C-ABI symbols the remaining .c files consume) for linking into the exe or
// a test binary. addPortedModule covers the src/*.zig ports; ported snes/
// modules pass their explicit path through addPortedModuleAt.
fn addPortedModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, name: []const u8) std.Build.LazyPath {
    return addPortedModuleAt(b, target, optimize, name, b.fmt("src/{s}.zig", .{name}));
}

fn addPortedModuleAt(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, name: []const u8, path: []const u8) std.Build.LazyPath {
    const mod = b.createModule(.{
        .root_source_file = b.path(path),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addIncludePath(b.path("."));
    const obj = b.addObject(.{
        .name = name,
        .root_module = mod,
    });
    return obj.getEmittedBin();
}

// SDL_GetKeyFromName keycode table: SDL_GetKeyFromName is kept in C (SDL.h
// drags in all of SDL), so the test harnesses compile this 20-line table
// from the real key names instead of linking SDL just for lookups.
fn addSdlKeyStub(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) std.Build.LazyPath {
    return sdlKeyStubObj(b, target, optimize, false);
}

fn sdlKeyStubObj(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, renamed: bool) std.Build.LazyPath {
    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const cflags = b.run(&.{ "sdl2-config", "--cflags" });
    var it = std.mem.tokenizeAny(u8, cflags, " \n\t");
    while (it.next()) |flag| {
        if (std.mem.startsWith(u8, flag, "-I"))
            mod.addIncludePath(.{ .cwd_relative = flag[2..] });
    }
    // The renamed flavour renames its SDL_GetKeyFromName definition to
    // c_SDL_GetKeyFromName at the preprocessor level (see compileRenamedCRef),
    // matching config_c_ref's renamed reference to it.
    const src_flags: []const []const u8 = if (renamed)
        &.{"-DSDL_GetKeyFromName=c_SDL_GetKeyFromName"}
    else
        &.{};
    mod.addCSourceFile(.{ .file = b.path("other/sdl_keyname_stub.c"), .flags = src_flags });
    const obj = b.addObject(.{
        .name = if (renamed) "sdl_keyname_stub_renamed" else "sdl_keyname_stub",
        .root_module = mod,
    });
    return obj.getEmittedBin();
}

// Tier-B differential tests link a pre-port C object (symbols renamed with a
// c_ prefix via the preprocessor) against the ported .zig module, so the test can call
// both and diff their outputs over randomized inputs. Each ported module that
// has a pre-port C reference wires its own (test file, C source, rename list)
// entry here.
fn addDiffTestStep(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const step = b.step("difftest", "Run Tier-B differential tests for ported Zig modules");

    const util_ref = compileRenamedCRef(b, target, optimize, "util_c_ref", "src/util.c", &.{
        "NextDelim",                  "StringEqualsNoCase",    "StringStartsWithNoCase",
        "ReadWholeFile",              "NextLineStripComments", "NextPossiblyQuotedString",
        "ReplaceFilenameWithNewPath", "SplitKeyValue",         "SkipPrefix",
        "StrSet",                     "ByteArray_Resize",      "ByteArray_Destroy",
        "ByteArray_AppendData",       "ByteArray_AppendByte",  "FindIndexInMemblk",
        "ApplyBps",
    });

    // config_difftest.zig's C-reference flavour: config.c plus a separately
    // renamed util.c copy. config.c's util references aren't in its own rename
    // list, so they stay plain and resolve against util.zig; the c_-renamed
    // util.c copy supplies matching c_<util> definitions.
    const config_ref = compileRenamedCRef(b, target, optimize, "config_c_ref", "src/config.c", &.{
        "ParseConfigFile",         "ParseBool", "FindCmdForSdlKey",
        "FindCmdForGamepadButton", "g_config",  "SDL_GetKeyFromName",
    });
    const config_util_ref = compileRenamedCRef(b, target, optimize, "config_util_c_ref", "src/util.c", &.{
        "NextDelim",                  "StringEqualsNoCase",    "StringStartsWithNoCase",
        "ReadWholeFile",              "NextLineStripComments", "NextPossiblyQuotedString",
        "ReplaceFilenameWithNewPath", "SplitKeyValue",         "SkipPrefix",
        "StrSet",                     "ByteArray_Resize",      "ByteArray_Destroy",
        "ByteArray_AppendData",       "ByteArray_AppendByte",  "FindIndexInMemblk",
        "ApplyBps",
    });

    // poly_difftest.zig's C reference: every poly.h entry point renamed to
    // c_<name>. poly.c's only externs are g_ram/g_zenv, which the test owns.
    const poly_ref = compileRenamedCRef(b, target, optimize, "poly_c_ref", "src/poly.c", &.{
        "Poly_Divide",                   "Poly_RunFrame",
        "Polyhedral_SetShapePointer",    "Polyhedral_SetRotationMatrix",
        "Polyhedral_OperateRotation",    "Polyhedral_RotatePoint",
        "Polyhedral_ProjectPoint",       "Polyhedral_DrawPolyhedron",
        "Polyhedral_SetForegroundColor", "Polyhedral_CalculateCrossProduct",
        "Polyhedral_SetColorMask",       "Polyhedral_EmptyBitMapBuffer",
        "Polyhedral_DrawFace",           "Polyhedral_FillLine",
        "Polyhedral_SetLeft",            "Polyhedral_SetRight",
    });

    // tile_detect_difftest.zig's C reference: every tile_detect.h entry point
    // renamed to c_<name>, plus its cross-module externs (also in the rename
    // list, so tile_detect.c's references to them become c_<name> too) resolved
    // by the per-module stubs in other/tile_detect_difftest_stubs/, which define
    // those c_ names directly. g_ram/g_zenv are the test's own.
    const tile_detect_ref = compileRenamedCRef(b, target, optimize, "tile_detect_c_ref", "src/tile_detect.c", &.{
        "Overworld_GetTileAttributeAtLocation", "TileDetect_Movement_Y",
        "TileDetect_Movement_X",                "TileDetect_Movement_VerticalSlopes",
        "TileDetect_Movement_HorizontalSlopes", "Player_TileDetectNearby",
        "Hookshot_CheckTileCollision",          "Hookshot_CheckSingleLayerTileCollision",
        "HandleNudgingInADoor",                 "TileCheckForMirrorBonk",
        "TileDetect_SwordSwingDeepInDoor",      "TileDetect_ResetState",
        "TileDetection_Execute",                "TileDetect_ExecuteInner",
        "GetMap16toMap8Table",                  "GetMap8toTileAttr",
        "Ancilla_GetX",                         "Ancilla_GetY",
    });
    const tile_detect_ancilla_stub = compileCStub(b, target, optimize, "tile_detect_ancilla_stub", "other/tile_detect_difftest_stubs/ancilla_stub.c");
    const tile_detect_overworld_stub = compileCStub(b, target, optimize, "tile_detect_overworld_stub", "other/tile_detect_difftest_stubs/overworld_stub.c");

    // input_difftest.zig's C reference: every input.h entry point renamed to
    // c_<name>. input_free renames cleanly too — only its own name is in the
    // rename list, so its libc free() call is left untouched.
    const input_ref = compileRenamedCRef(b, target, optimize, "input_c_ref", "snes/input.c", &.{
        "input_init", "input_free", "input_reset", "input_cycle", "input_read",
    });

    // cart_difftest.zig's C reference: every cart.h entry point renamed to
    // c_<name>. cart.c's only externs are libc (malloc/free/memcpy/memset),
    // which the rename list omits, so they stay unrenamed.
    const cart_ref = compileRenamedCRef(b, target, optimize, "cart_c_ref", "snes/cart.c", &.{
        "cart_init", "cart_free", "cart_reset", "cart_load", "cart_read", "cart_write", "cart_saveload",
    });

    // apu_difftest.zig's C reference: every apu.h entry point renamed to
    // c_<name>. apu.c's cross-module calls to spc_* are NOT renamed —
    // spc.c isn't ported yet, so both the C reference and the Zig port call
    // the same real spc.o object (compiled unrenamed below, shared between
    // flavours). Its dsp_* calls now resolve against the real ported
    // dsp.zig module instead (dsp.c is ported; apu.zig/apu_c_ref both treat
    // Dsp as opaque, so either flavour driving the real port is correct).
    const apu_ref = compileRenamedCRef(b, target, optimize, "apu_c_ref", "snes/apu.c", &.{
        "apu_init", "apu_free", "apu_reset", "apu_cycle", "apu_cpuRead", "apu_cpuWrite", "apu_saveload",
    });
    const apu_spc_obj = addPortedModuleAt(b, target, optimize, "apu_difftest_spc", "snes/spc.zig");
    const apu_dsp_obj = addPortedModuleAt(b, target, optimize, "apu_difftest_dsp", "snes/dsp.zig");

    // dma_difftest.zig's C reference: every dma.h entry point renamed to
    // c_<name>. dma.c's snes_read/snes_write/snes_readBBus/snes_writeBBus
    // externs are NOT renamed — snes.c isn't ported yet, so both flavours
    // get them from the difftest file's own export fn stubs (pointer-identity
    // dispatched per flavour), rather than a real snes.o.
    const dma_ref = compileRenamedCRef(b, target, optimize, "dma_c_ref", "snes/dma.c", &.{
        "dma_init",  "dma_free",     "dma_reset",    "dma_read",
        "dma_write", "dma_doDma",    "dma_initHdma", "dma_doHdma",
        "dma_cycle", "dma_startDma", "dma_saveload",
    });

    // dsp_difftest.zig's C reference: every dsp.h entry point renamed to
    // c_<name>. dsp.c only touches memory through the apu_ram pointer passed
    // to dsp_init (no cross-module externs), so no stubs are needed here.
    const dsp_ref = compileRenamedCRef(b, target, optimize, "dsp_c_ref", "snes/dsp.c", &.{
        "dsp_init",  "dsp_free",       "dsp_reset",    "dsp_cycle", "dsp_read",
        "dsp_write", "dsp_getSamples", "dsp_saveload",
    });

    // spc_difftest.zig's C reference: every spc.h entry point renamed to
    // c_<name>. spc.c's cross-module calls to apu_cpuRead/apu_cpuWrite are
    // NOT renamed — the difftest file exports those stubs itself (shared
    // between both flavours), so no separate bus stub is needed.
    const spc_ref = compileRenamedCRef(b, target, optimize, "spc_c_ref", "snes/spc.c", &.{
        "spc_init", "spc_free", "spc_reset", "spc_runOpcode", "spc_saveload",
    });

    // ppu_difftest.zig's C reference: every ppu.h entry point renamed to
    // c_<name>. ppu.c has no cross-module externs (it only touches its own
    // Ppu struct, passed by pointer), so no stubs are needed here.
    const ppu_ref = compileRenamedCRef(b, target, optimize, "ppu_c_ref", "snes/ppu.c", &.{
        "ppu_init",                         "ppu_free",             "ppu_reset",
        "ppu_runLine",                      "ppu_read",             "ppu_write",
        "ppu_saveload",                     "PpuBeginDrawing",      "PpuGetCurrentRenderScale",
        "PpuSetMode7PerspectiveCorrection", "PpuSetExtraSideSpace",
    });

    for (&diff_test_files) |file| {
        const test_mod = b.createModule(.{
            .root_source_file = b.path(file),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        const mod_test = b.addTest(.{
            .root_module = test_mod,
        });
        if (std.mem.eql(u8, file, "src/util_difftest.zig")) {
            mod_test.root_module.addObjectFile(util_ref);
        } else if (std.mem.eql(u8, file, "src/config_difftest.zig")) {
            // The parent re-execs itself per randomized ini (fresh keymap
            // state each run); config.zig's plain util externs resolve against
            // util.o here. config_c_ref's own util references stay plain (not
            // in its rename list) and also resolve against util.o; the c_-
            // renamed config_util_c_ref copy carries the matching c_util_*
            // definitions.
            mod_test.root_module.addObjectFile(addPortedModule(b, target, optimize, "util"));
            mod_test.root_module.addObjectFile(config_ref);
            mod_test.root_module.addObjectFile(config_util_ref);
            mod_test.root_module.addObjectFile(addSdlKeyStub(b, target, optimize));
            mod_test.root_module.addObjectFile(addRenamedSdlKeyStub(b, target, optimize));
        } else if (std.mem.eql(u8, file, "src/poly_difftest.zig")) {
            // poly.zig exports the Poly_* symbols; the renamed poly_c_ref
            // carries the C reference behind c_* names. The test defines
            // g_ram/g_zenv itself, so both flavours share one buffer.
            mod_test.root_module.addObjectFile(addPortedModule(b, target, optimize, "poly"));
            mod_test.root_module.addObjectFile(poly_ref);
        } else if (std.mem.eql(u8, file, "src/tile_detect_difftest.zig")) {
            // tile_detect.zig exports the plain symbols; the renamed
            // tile_detect_c_ref carries the C reference behind c_* names,
            // its cross-module calls satisfied by the per-module stubs.
            mod_test.root_module.addObjectFile(addPortedModule(b, target, optimize, "tile_detect"));
            mod_test.root_module.addObjectFile(tile_detect_ref);
            mod_test.root_module.addObjectFile(tile_detect_ancilla_stub);
            mod_test.root_module.addObjectFile(tile_detect_overworld_stub);
        } else if (std.mem.eql(u8, file, "snes/input_difftest.zig")) {
            // input.zig exports the plain symbols; the renamed input_c_ref
            // carries the C reference behind c_* names (input_free's body
            // stays unrenamed — it is only a libc free wrapper — so the test
            // frees the C flavour's allocations through the ported one).
            mod_test.root_module.addObjectFile(addPortedModuleAt(b, target, optimize, "input", "snes/input.zig"));
            mod_test.root_module.addObjectFile(input_ref);
        } else if (std.mem.eql(u8, file, "snes/cart_difftest.zig")) {
            // cart.zig exports the plain symbols; the renamed cart_c_ref
            // carries the C reference behind c_* names. Both flavours own
            // their mallocs, so the test frees each through its own free.
            mod_test.root_module.addObjectFile(addPortedModuleAt(b, target, optimize, "cart", "snes/cart.zig"));
            mod_test.root_module.addObjectFile(cart_ref);
        } else if (std.mem.eql(u8, file, "snes/apu_difftest.zig")) {
            // apu.zig exports the plain symbols; the renamed apu_c_ref
            // carries the C reference behind c_* names. Both flavours drive
            // the same real spc.o/dsp.o objects (unrenamed, shared).
            mod_test.root_module.addObjectFile(addPortedModuleAt(b, target, optimize, "apu", "snes/apu.zig"));
            mod_test.root_module.addObjectFile(apu_ref);
            mod_test.root_module.addObjectFile(apu_spc_obj);
            mod_test.root_module.addObjectFile(apu_dsp_obj);
        } else if (std.mem.eql(u8, file, "snes/dma_difftest.zig")) {
            // dma.zig exports the plain symbols; the renamed dma_c_ref
            // carries the C reference behind c_* names. Both flavours get
            // their snes_read/snes_write/snes_readBBus/snes_writeBBus from
            // the difftest file's own stubs, dispatched by Snes* identity.
            mod_test.root_module.addObjectFile(addPortedModuleAt(b, target, optimize, "dma", "snes/dma.zig"));
            mod_test.root_module.addObjectFile(dma_ref);
        } else if (std.mem.eql(u8, file, "snes/dsp_difftest.zig")) {
            // dsp.zig exports the plain symbols; the renamed dsp_c_ref
            // carries the C reference behind c_* names. dsp.c only touches
            // memory through the apu_ram pointer the test owns, so no bus
            // stubs are needed.
            mod_test.root_module.addObjectFile(addPortedModuleAt(b, target, optimize, "dsp", "snes/dsp.zig"));
            mod_test.root_module.addObjectFile(dsp_ref);
        } else if (std.mem.eql(u8, file, "snes/spc_difftest.zig")) {
            // spc.zig exports the plain symbols; the renamed spc_c_ref
            // carries the C reference behind c_* names. Both flavours share
            // the difftest's own apu_cpuRead/apu_cpuWrite stubs (no separate
            // bus object needed).
            mod_test.root_module.addObjectFile(addPortedModuleAt(b, target, optimize, "spc", "snes/spc.zig"));
            mod_test.root_module.addObjectFile(spc_ref);
        } else if (std.mem.eql(u8, file, "snes/ppu_difftest.zig")) {
            // ppu.zig exports the plain symbols; the renamed ppu_c_ref
            // carries the C reference behind c_* names. Both flavours own
            // their own Ppu struct (allocated via ppu_init), no shared state.
            mod_test.root_module.addObjectFile(addPortedModuleAt(b, target, optimize, "ppu", "snes/ppu.zig"));
            mod_test.root_module.addObjectFile(ppu_ref);
        }
        const run_test = b.addRunArtifact(mod_test);
        step.dependOn(&run_test.step);
    }
}

// config_c_ref renames its SDL_GetKeyFromName reference to c_SDL_GetKeyFromName,
// so the C flavour needs a c_SDL_GetKeyFromName definition — the same key table,
// symbol renamed at compile time.
fn addRenamedSdlKeyStub(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) std.Build.LazyPath {
    return sdlKeyStubObj(b, target, optimize, true);
}

// Compile a pre-port C source to an object with each exported symbol renamed
// to c_<name> so it links alongside the ported Zig module (which owns the
// original names) without colliding. The rename is done at the preprocessor
// level (`-D<sym>=c_<sym>`) rather than post-hoc with objcopy: the preprocessor
// rewrites every token occurrence in the TU (the definition and any same-TU
// references), which matches objcopy's symbol-table rewrite (definitions plus
// undefined cross-TU references) and, unlike objcopy, needs no external tool
// and works identically on ELF and Mach-O (whose leading-underscore symbol
// names silently defeated the bare-name objcopy invocation on macOS).
fn compileRenamedCRef(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, name: []const u8, src: []const u8, syms: []const []const u8) std.Build.LazyPath {
    const ref_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    ref_mod.addIncludePath(b.path("."));
    // SDL headers for the sources that include them (config.h).
    const cflags = b.run(&.{ "sdl2-config", "--cflags" });
    var it = std.mem.tokenizeAny(u8, cflags, " \n\t");
    while (it.next()) |flag| {
        if (std.mem.startsWith(u8, flag, "-I"))
            ref_mod.addIncludePath(.{ .cwd_relative = flag[2..] });
    }
    const dflags = b.allocator.alloc([]const u8, syms.len) catch @panic("OOM");
    for (syms, 0..) |sym, i|
        dflags[i] = b.fmt("-D{s}=c_{s}", .{ sym, sym });
    ref_mod.addCSourceFile(.{ .file = b.path(src), .flags = dflags });
    const ref_obj = b.addObject(.{
        .name = name,
        .root_module = ref_mod,
    });
    return ref_obj.getEmittedBin();
}

// Compile a difftest-side C stub (a per-module shim satisfying a renamed C
// reference's cross-module externs) to an object for mod_test.addObjectFile.
fn compileCStub(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, name: []const u8, src: []const u8) std.Build.LazyPath {
    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addIncludePath(b.path("."));
    mod.addCSourceFile(.{ .file = b.path(src) });
    const obj = b.addObject(.{
        .name = name,
        .root_module = mod,
    });
    return obj.getEmittedBin();
}

// Same source list as taskfile.yml's SOURCES var: src/*.c + snes/*.c at
// maxdepth 1 (excludes src/platform/* and the ported util.c/config.c/
// poly.c/tile_detect.c/input.c/cart.c), plus the two vendored third_party C
// files the C build compiles. Kept as a static list (rather than directory
// iteration) since Zig 0.16's filesystem APIs require plumbing an `Io`
// instance through build.zig for no benefit here — new .c files are rare and
// this mirrors the taskfile's `find ... ! -name ...` exclusions.
const sources = [_][]const u8{
    "snes/cpu.c",
    "snes/tracing.c",
    "src/ancilla.c",
    "src/attract.c",
    "src/audio.c",
    "src/dungeon.c",
    "src/ending.c",
    "src/glsl_shader.c",
    "src/hud.c",
    "src/main.c",
    "src/messaging.c",
    "src/misc.c",
    "src/opengl.c",
    "src/overworld.c",
    "src/player.c",
    "src/select_file.c",
    "src/sprite_main.c",
    "src/sprite.c",
    "src/tagalong.c",
    "src/util_strfmt.c",
    "src/zelda_cpu_infra.c",
    "src/zelda_rtl.c",
    "third_party/gl_core/gl_core_3_1.c",
    "third_party/opus-1.3.1-stripped/opus_decoder_amalgam.c",
};

// Shells out to sdl2-config, same as taskfile.yml's `$(sdl2-config --cflags)`
// / `$(sdl2-config --libs)`, and translates the resulting flags into the
// equivalent Zig build-graph calls.
fn linkSdl2(b: *std.Build, mod: *std.Build.Module) void {
    const cflags = b.run(&.{ "sdl2-config", "--cflags" });
    var cflags_it = std.mem.tokenizeAny(u8, cflags, " \n\t");
    while (cflags_it.next()) |flag| {
        if (std.mem.startsWith(u8, flag, "-I")) {
            mod.addIncludePath(.{ .cwd_relative = flag[2..] });
        } else if (std.mem.startsWith(u8, flag, "-D")) {
            const define = flag[2..];
            if (std.mem.indexOfScalar(u8, define, '=')) |eq| {
                mod.addCMacro(define[0..eq], define[eq + 1 ..]);
            } else {
                mod.addCMacro(define, "1");
            }
        }
        // Other flags (e.g. -D_THREAD_SAFE handled above) are ignored; none
        // of the remaining sdl2-config --cflags output applies to Zig's
        // build graph.
    }

    const libs = b.run(&.{ "sdl2-config", "--libs" });
    var libs_it = std.mem.tokenizeAny(u8, libs, " \n\t");
    while (libs_it.next()) |flag| {
        if (std.mem.startsWith(u8, flag, "-L")) {
            mod.addLibraryPath(.{ .cwd_relative = flag[2..] });
        } else if (std.mem.startsWith(u8, flag, "-l")) {
            mod.linkSystemLibrary(flag[2..], .{});
        } else if (std.mem.startsWith(u8, flag, "-Wl,-framework,")) {
            var it = std.mem.splitScalar(u8, flag, ',');
            _ = it.next(); // "-Wl"
            _ = it.next(); // "-framework"
            if (it.next()) |framework| mod.linkFramework(framework, .{});
        }
    }

    mod.linkSystemLibrary("m", .{});
}
