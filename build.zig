const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const utils_module = b.addModule("utils", .{
        .root_source_file = b.path("src/utils/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const encoding_module = b.addModule("encoding", .{
        .root_source_file = b.path("src/encoding/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "utils", .module = utils_module },
        },
    });

    const transcoding_module = b.addModule("transcoding", .{
        .root_source_file = b.path("src/transcoding/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "utils", .module = utils_module },
            .{ .name = "encoding", .module = encoding_module },
        },
    });

    const ezi_code_module = b.addModule("ezi_code", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "utils", .module = utils_module },
            .{ .name = "encoding", .module = encoding_module },
            .{ .name = "transcoding", .module = transcoding_module },
        },
    });

    const exe = b.addExecutable(.{
        .name = "ezi_code",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ezi_code", .module = ezi_code_module },
            },
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

    const utils_tests = b.addTest(.{
        .root_module = utils_module,
    });
    const encoding_tests = b.addTest(.{
        .root_module = encoding_module,
    });
    const transcoding_tests = b.addTest(.{
        .root_module = transcoding_module,
    });
    const mod_tests = b.addTest(.{
        .root_module = ezi_code_module,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);
    const run_utils_tests = b.addRunArtifact(utils_tests);
    const run_encoding_tests = b.addRunArtifact(encoding_tests);
    const run_transcoding_tests = b.addRunArtifact(transcoding_tests);

    // const exe_tests = b.addTest(.{
    //     .root_module = exe.root_module,
    // });

    // const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_utils_tests.step);
    test_step.dependOn(&run_encoding_tests.step);
    test_step.dependOn(&run_transcoding_tests.step);

    const bench_exe = b.addExecutable(.{
        .name = "bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ezi_code", .module = ezi_code_module },
            },
        }),
    });
    const run_bench = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Run UTF-8, UTF-16, UTF-32, and u8↔u16 benchmarks (mean of 7 samples)");
    bench_step.dependOn(&run_bench.step);

    const transcoding_fuzz_exe = b.addExecutable(.{
        .name = "utf16_fuzz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/fuzz/transcoding.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ezi_code", .module = ezi_code_module },
            },
        }),
    });

    const utf32_fuzz_exe = b.addExecutable(.{
        .name = "utf16_fuzz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/fuzz/utf32.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ezi_code", .module = ezi_code_module },
            },
        }),
    });

    const utf16_fuzz_exe = b.addExecutable(.{
        .name = "utf16_fuzz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/fuzz/utf16.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ezi_code", .module = ezi_code_module },
            },
        }),
    });

    const utf8_fuzz_exe = b.addExecutable(.{
        .name = "utf8_fuzz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/fuzz/utf8.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ezi_code", .module = ezi_code_module },
            },
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
