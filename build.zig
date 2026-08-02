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
};

// Tier-B differential tests: behavioral-equivalence checks between a
// pre-port C object (symbols renamed via objcopy) and its ported .zig
// module, run over randomized inputs. Empty until a module is ported;
// each port task wires its own differential harness here.
const diff_test_files = [_][]const u8{
    "src/util_difftest.zig",
    "src/config_difftest.zig",
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

// Compile src/<name>.zig as its own object (a ported C module, exporting the
// C-ABI symbols the remaining .c files consume) for linking into the exe or
// a test binary.
fn addPortedModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, name: []const u8) std.Build.LazyPath {
    const mod = b.createModule(.{
        .root_source_file = b.path(b.fmt("src/{s}.zig", .{name})),
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
    mod.addCSourceFile(.{ .file = b.path("other/sdl_keyname_stub.c") });
    const obj = b.addObject(.{
        .name = "sdl_keyname_stub",
        .root_module = mod,
    });
    return obj.getEmittedBin();
}

// Tier-B differential tests link a pre-port C object (symbols renamed with a
// c_ prefix via objcopy) against the ported .zig module, so the test can call
// both and diff their outputs over randomized inputs. Each ported module that
// has a pre-port C reference wires its own (test file, C source, rename list)
// entry here.
fn addDiffTestStep(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const step = b.step("difftest", "Run Tier-B differential tests for ported Zig modules");

    const util_ref = compileRenamedCRef(b, target, optimize, "util_c_ref", "src/util.c", &.{
        "NextDelim",           "StringEqualsNoCase",       "StringStartsWithNoCase",
        "ReadWholeFile",       "NextLineStripComments",    "NextPossiblyQuotedString",
        "ReplaceFilenameWithNewPath", "SplitKeyValue",     "SkipPrefix",
        "StrSet",              "ByteArray_Resize",         "ByteArray_Destroy",
        "ByteArray_AppendData", "ByteArray_AppendByte",    "FindIndexInMemblk",
        "ApplyBps",
    });

    // config_difftest.zig's C-reference flavour: config.c plus a renamed
    // util.c (it shares the util helpers; the rename list must cover both,
    // since objcopy only renames definitions, not references).
    const config_ref = compileRenamedCRef(b, target, optimize, "config_c_ref", "src/config.c", &.{
        "ParseConfigFile",     "ParseBool",                "FindCmdForSdlKey",
        "FindCmdForGamepadButton", "g_config",             "SDL_GetKeyFromName",
    });
    const config_util_ref = compileRenamedCRef(b, target, optimize, "config_util_c_ref", "src/util.c", &.{
        "NextDelim",           "StringEqualsNoCase",       "StringStartsWithNoCase",
        "ReadWholeFile",       "NextLineStripComments",    "NextPossiblyQuotedString",
        "ReplaceFilenameWithNewPath", "SplitKeyValue",     "SkipPrefix",
        "StrSet",              "ByteArray_Resize",         "ByteArray_Destroy",
        "ByteArray_AppendData", "ByteArray_AppendByte",    "FindIndexInMemblk",
        "ApplyBps",
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
            // state each run); config.zig's plain util externs resolve
            // against util.o here, and config_c_ref's renamed c_util_* calls
            // resolve against config_util_c_ref (objcopy renames definitions
            // but not references, so the C side needs its own c_ util copy).
            mod_test.root_module.addObjectFile(addPortedModule(b, target, optimize, "util"));
            mod_test.root_module.addObjectFile(config_ref);
            mod_test.root_module.addObjectFile(config_util_ref);
            mod_test.root_module.addObjectFile(addSdlKeyStub(b, target, optimize));
            mod_test.root_module.addObjectFile(addRenamedSdlKeyStub(b, target, optimize));
        }
        const run_test = b.addRunArtifact(mod_test);
        step.dependOn(&run_test.step);
    }
}

// The config_c_ref object calls SDL_GetKeyFromName; under objcopy that
// reference is renamed too (it's in the rename list), so the C flavour needs
// a c_SDL_GetKeyFromName definition — the same key table, symbol renamed.
fn addRenamedSdlKeyStub(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) std.Build.LazyPath {
    const stub = addSdlKeyStub(b, target, optimize);
    const objcopy = b.addSystemCommand(&.{"objcopy"});
    objcopy.addArgs(&.{ "--redefine-sym", "SDL_GetKeyFromName=c_SDL_GetKeyFromName" });
    objcopy.addFileArg(stub);
    return objcopy.addOutputFileArg("sdl_keyname_stub_renamed.o");
}

// Compile a pre-port C source to an object, then rename each exported symbol
// to c_<name> via objcopy so it links alongside the ported Zig module (which
// owns the original names) without colliding. Returns the renamed object as a
// LazyPath for mod_test.addObjectFile.
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
    ref_mod.addCSourceFile(.{ .file = b.path(src) });
    const ref_obj = b.addObject(.{
        .name = name,
        .root_module = ref_mod,
    });

    const objcopy = b.addSystemCommand(&.{"objcopy"});
    for (syms) |sym| {
        objcopy.addArgs(&.{ "--redefine-sym", b.fmt("{s}=c_{s}", .{ sym, sym }) });
    }
    objcopy.addFileArg(ref_obj.getEmittedBin());
    return objcopy.addOutputFileArg(b.fmt("{s}_renamed.o", .{name}));
}

// Same source list as taskfile.yml's SOURCES var: src/*.c + snes/*.c at
// maxdepth 1 (excludes src/platform/*), plus the two vendored third_party
// C files the C build compiles. Kept as a static list (rather than directory
// iteration) since Zig 0.16's filesystem APIs require plumbing an `Io`
// instance through build.zig for no benefit here — new .c files are rare and
// this mirrors `find src snes -maxdepth 1 -name '*.c'` as of this writing.
const sources = [_][]const u8{
    "snes/apu.c",
    "snes/cart.c",
    "snes/cpu.c",
    "snes/dma.c",
    "snes/dsp.c",
    "snes/input.c",
    "snes/ppu.c",
    "snes/snes_other.c",
    "snes/snes.c",
    "snes/spc.c",
    "snes/tracing.c",
    "src/ancilla.c",
    "src/attract.c",
    "src/audio.c",
    "src/dungeon.c",
    "src/ending.c",
    "src/glsl_shader.c",
    "src/hud.c",
    "src/load_gfx.c",
    "src/main.c",
    "src/messaging.c",
    "src/misc.c",
    "src/nmi.c",
    "src/opengl.c",
    "src/overlord.c",
    "src/overworld.c",
    "src/player_oam.c",
    "src/player.c",
    "src/poly.c",
    "src/select_file.c",
    "src/spc_player.c",
    "src/sprite_main.c",
    "src/sprite.c",
    "src/tagalong.c",
    "src/tile_detect.c",
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
