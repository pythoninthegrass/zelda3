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

    const exe_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const exe = b.addExecutable(.{
        .name = "zelda3",
        .root_module = exe_mod,
    });

    exe_mod.addIncludePath(b.path("."));

    exe_mod.addCSourceFiles(.{
        .files = &sources,
        .flags = &.{"-DSYSTEM_VOLUME_MIXER_AVAILABLE=0"},
    });

    linkSdl2(b, exe_mod);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the zelda3 binary");
    run_step.dependOn(&run_cmd.step);

    addTestStep(b, "test", "Run Tier-A unit tests for ported Zig modules", &unit_test_files, target, optimize);
    addTestStep(b, "difftest", "Run Tier-B differential tests for ported Zig modules", &diff_test_files, target, optimize);
}

// Tier-A unit tests for ported Zig modules (zig build test). Empty until a
// C module is ported to idiomatic Zig; each port task appends its own
// .zig test file here rather than this being wired up speculatively.
const unit_test_files = [_][]const u8{};

// Tier-B differential tests: behavioral-equivalence checks between a
// pre-port C object (symbols renamed via objcopy) and its ported .zig
// module, run over randomized inputs. Empty until a module is ported;
// each port task wires its own differential harness here.
const diff_test_files = [_][]const u8{};

fn addTestStep(b: *std.Build, name: []const u8, desc: []const u8, files: []const []const u8, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const step = b.step(name, desc);
    for (files) |file| {
        const test_mod = b.createModule(.{
            .root_source_file = b.path(file),
            .target = target,
            .optimize = optimize,
        });
        const mod_test = b.addTest(.{
            .root_module = test_mod,
        });
        const run_test = b.addRunArtifact(mod_test);
        step.dependOn(&run_test.step);
    }
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
    "src/config.c",
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
    "src/util.c",
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
