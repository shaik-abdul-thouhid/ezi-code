const std = @import("std");
const some = @import("src/utils/root.zig").some;

const TestEnum = enum {
    all,
    encoding,
    transcoding,
    unicode,
    utils,
    conformance,
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const include_tests = b.option(
        []const TestEnum,
        "include-test",
        "Tests to include in the `zig build test` run",
    ) orelse &[_]TestEnum{.all};

    const utils_module = b.addModule("utils", .{
        .root_source_file = b.path("src/utils/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const utils: std.Build.Module.Import = .{ .name = "utils", .module = utils_module };

    const encoding_module = b.addModule("encoding", .{
        .root_source_file = b.path("src/encoding/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{utils},
    });
    const encoding: std.Build.Module.Import = .{ .name = "encoding", .module = encoding_module };

    const transcoding_module = b.addModule("transcoding", .{
        .root_source_file = b.path("src/transcoding/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{ utils, encoding },
    });

    const transcoding: std.Build.Module.Import = .{ .name = "transcoding", .module = transcoding_module };

    const unicode_build_options = b.addOptions();
    unicode_build_options.addOption(bool, "include_conformance", some(TestEnum, {}, include_tests, struct {
        fn predicate(_: void, a: TestEnum, _: usize) bool {
            return a == .all or a == .conformance;
        }
    }.predicate));

    const build_option_module: std.Build.Module.Import = .{
        .name = "build_options",
        .module = unicode_build_options.createModule(),
    };

    const unicode_module = b.addModule("unicode", .{
        .root_source_file = b.path("src/unicode/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{ utils, encoding, build_option_module },
    });

    const unicode: std.Build.Module.Import = .{ .name = "unicode", .module = unicode_module };

    const ezi_code_module = b.addModule("ezi_code", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{ utils, encoding, transcoding, unicode },
    });

    const root: std.Build.Module.Import = .{ .name = "ezi_code", .module = ezi_code_module };

    const exe = b.addExecutable(.{
        .name = "ezi_code",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{root},
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Unicode table generation step
    const generate_unicode_exe = b.addExecutable(.{
        .name = "generator",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/generate.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{root},
        }),
    });

    const generate_unicode_step = b.step("generate", "Generate Unicode tables");

    const generate_unicode_cmd = b.addRunArtifact(generate_unicode_exe);
    generate_unicode_step.dependOn(&generate_unicode_cmd.step);

    const utils_tests = b.addTest(.{ .root_module = utils_module });
    const encoding_tests = b.addTest(.{ .root_module = encoding_module });
    const transcoding_tests = b.addTest(.{ .root_module = transcoding_module });
    const unicode_tests = b.addTest(.{ .root_module = unicode_module });
    const mod_tests = b.addTest(.{ .root_module = ezi_code_module });

    const run_mod_tests = b.addRunArtifact(mod_tests);
    const run_utils_tests = b.addRunArtifact(utils_tests);
    const run_encoding_tests = b.addRunArtifact(encoding_tests);
    const run_transcoding_tests = b.addRunArtifact(transcoding_tests);
    const run_unicode_tests = b.addRunArtifact(unicode_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    if (some(
        TestEnum,
        {},
        include_tests,
        struct {
            fn predicate(_: void, i: TestEnum, _: usize) bool {
                return i == .utils or i == .all;
            }
        }.predicate,
    )) {
        test_step.dependOn(&run_utils_tests.step);
    }

    if (some(
        TestEnum,
        {},
        include_tests,
        struct {
            fn predicate(_: void, i: TestEnum, _: usize) bool {
                return i == .encoding or i == .all;
            }
        }.predicate,
    )) {
        test_step.dependOn(&run_encoding_tests.step);
    }

    if (some(
        TestEnum,
        {},
        include_tests,
        struct {
            fn predicate(_: void, i: TestEnum, _: usize) bool {
                return i == .transcoding or i == .all;
            }
        }.predicate,
    )) {
        test_step.dependOn(&run_transcoding_tests.step);
    }

    if (some(
        TestEnum,
        {},
        include_tests,
        struct {
            fn predicate(_: void, i: TestEnum, _: usize) bool {
                return i == .unicode or i == .conformance or i == .all;
            }
        }.predicate,
    )) {
        test_step.dependOn(&run_unicode_tests.step);
    }

    // Benchmarks need optimization — Debug mode is so slow on the segmentation
    // iterators (table-driven property lookups, per-codepoint lookahead) that
    // a 16 KiB corpus appears to hang. Build a dedicated tree of modules at
    // `bench_optimize` so library code is compiled with the same optimization
    // as the benchmark driver. Honor `-Dbench-optimize=...` to override.
    const bench_optimize = b.option(
        std.builtin.OptimizeMode,
        "bench-optimize",
        "Optimization level for the bench executable (default ReleaseFast)",
    ) orelse .ReleaseFast;

    const bench_utils_module = b.createModule(.{
        .root_source_file = b.path("src/utils/root.zig"),
        .target = target,
        .optimize = bench_optimize,
    });
    const bench_utils: std.Build.Module.Import = .{ .name = "utils", .module = bench_utils_module };

    const bench_encoding_module = b.createModule(.{
        .root_source_file = b.path("src/encoding/root.zig"),
        .target = target,
        .optimize = bench_optimize,
        .imports = &.{bench_utils},
    });
    const bench_encoding: std.Build.Module.Import = .{ .name = "encoding", .module = bench_encoding_module };

    const bench_transcoding_module = b.createModule(.{
        .root_source_file = b.path("src/transcoding/root.zig"),
        .target = target,
        .optimize = bench_optimize,
        .imports = &.{ bench_utils, bench_encoding },
    });
    const bench_transcoding: std.Build.Module.Import = .{ .name = "transcoding", .module = bench_transcoding_module };

    const bench_unicode_module = b.createModule(.{
        .root_source_file = b.path("src/unicode/root.zig"),
        .target = target,
        .optimize = bench_optimize,
        .imports = &.{ bench_utils, bench_encoding },
    });
    const bench_unicode: std.Build.Module.Import = .{ .name = "unicode", .module = bench_unicode_module };

    const bench_ezi_code_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = bench_optimize,
        .imports = &.{ bench_utils, bench_encoding, bench_transcoding, bench_unicode },
    });
    const bench_root: std.Build.Module.Import = .{ .name = "ezi_code", .module = bench_ezi_code_module };

    const bench_exe = b.addExecutable(.{
        .name = "bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/main.zig"),
            .target = target,
            .optimize = bench_optimize,
            .imports = &.{ bench_root, bench_utils },
        }),
    });
    const run_bench = b.addRunArtifact(bench_exe);
    if (b.args) |args| {
        run_bench.addArgs(args);
    }
    const bench_step = b.step("bench", "Run Benchmarks");
    bench_step.dependOn(&run_bench.step);

    const transcoding_fuzz_exe = b.addExecutable(.{
        .name = "transcoding_fuzz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/fuzz/transcoding.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{root},
        }),
    });

    const utf32_fuzz_exe = b.addExecutable(.{
        .name = "utf32_fuzz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/fuzz/utf32.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{root},
        }),
    });

    const utf16_fuzz_exe = b.addExecutable(.{
        .name = "utf16_fuzz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/fuzz/utf16.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{root},
        }),
    });

    const utf8_fuzz_exe = b.addExecutable(.{
        .name = "utf8_fuzz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/fuzz/utf8.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{root},
        }),
    });

    const transcoding_fuzz = b.addRunArtifact(transcoding_fuzz_exe);
    const utf32_fuzz = b.addRunArtifact(utf32_fuzz_exe);
    const utf16_fuzz = b.addRunArtifact(utf16_fuzz_exe);
    const utf8_fuzz = b.addRunArtifact(utf8_fuzz_exe);

    const fuzz_step = b.step("fuzz", "Run all fuzz in tests/fuzz directory");
    fuzz_step.dependOn(&transcoding_fuzz.step);
    fuzz_step.dependOn(&utf32_fuzz.step);
    fuzz_step.dependOn(&utf16_fuzz.step);
    fuzz_step.dependOn(&utf8_fuzz.step);
}
