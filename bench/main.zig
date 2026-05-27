//! Benchmark driver. Runs every registered module against ASCII / multilingual
//! / pathological corpora; prints mean (of 7 runs) ± stddev, memory, throughput.
//!
//! Usage:
//!   zig build bench                                 # run everything
//!   zig build bench -- encoding/utf8                # one module
//!   zig build bench -- encoding/utf8 transcoding    # several modules
//!   zig build bench -- --list                       # list registered modules
//!   zig build bench -- --size=524288 unicode/properties  # custom corpus size
//!
//! Adding a new module:
//!   1. Drop a file in `bench/modules/your_module.zig`
//!   2. Export `pub const suite: framework.Suite = .{ ... };`
//!   3. Add it to the `registry` array below.

const std = @import("std");
const framework = @import("framework.zig");
const corpus = @import("corpus.zig");

const encoding_utf8 = @import("modules/encoding_utf8.zig");
const encoding_utf16 = @import("modules/encoding_utf16.zig");
const encoding_utf32 = @import("modules/encoding_utf32.zig");
const transcoding = @import("modules/transcoding.zig");
const unicode_properties = @import("modules/unicode_properties.zig");
const unicode_casing = @import("modules/unicode_casing.zig");
const unicode_segmentation = @import("modules/unicode_segmentation.zig");
const unicode_width = @import("modules/unicode_width.zig");
const unicode_normalization = @import("modules/unicode_normalization.zig");
const unicode_scripts = @import("modules/unicode_scripts.zig");
const utils_slices = @import("modules/utils_slices.zig");
const utils_search = @import("modules/utils_search.zig");

const registry: []const framework.Suite = &.{
    encoding_utf8.suite,
    encoding_utf16.suite,
    encoding_utf32.suite,
    transcoding.suite,
    unicode_properties.suite,
    unicode_casing.suite,
    unicode_segmentation.suite,
    unicode_width.suite,
    unicode_normalization.suite,
    unicode_scripts.suite,
    utils_slices.suite,
    utils_search.suite,
};

fn printUsage() void {
    std.debug.print(
        \\Usage:
        \\  bench                       run all modules
        \\  bench MOD [MOD ...]         run only the listed modules
        \\  bench --list                list registered modules
        \\  bench --size=N              corpus size per type in bytes (default {d})
        \\
        \\Registered modules:
        \\
    , .{corpus.default_size});
    for (registry) |s| {
        std.debug.print("  {s}\n", .{s.module_name});
    }
}

fn parseSize(s: []const u8) ?usize {
    return std.fmt.parseInt(usize, s, 10) catch null;
}

fn moduleMatches(suite_name: []const u8, query: []const u8) bool {
    if (std.mem.eql(u8, suite_name, query)) return true;
    // Allow `encoding_utf8` form too.
    var swap_buf: [128]u8 = undefined;
    if (suite_name.len > swap_buf.len) return false;
    for (suite_name, 0..) |c, i| swap_buf[i] = if (c == '/') '_' else c;
    return std.mem.eql(u8, swap_buf[0..suite_name.len], query);
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var arg_it = try init.minimal.args.iterateAllocator(allocator);
    defer arg_it.deinit();
    _ = arg_it.skip(); // argv[0]

    var corpus_size: usize = corpus.default_size;
    var selected: std.ArrayList([]const u8) = .empty;
    defer selected.deinit(allocator);

    while (arg_it.next()) |a| {
        if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) {
            printUsage();
            return;
        } else if (std.mem.eql(u8, a, "--list")) {
            std.debug.print("Registered benchmark modules:\n", .{});
            for (registry) |s| std.debug.print("  {s}\n", .{s.module_name});
            return;
        } else if (std.mem.startsWith(u8, a, "--size=")) {
            const v = a["--size=".len..];
            corpus_size = parseSize(v) orelse {
                std.debug.print("invalid --size value: '{s}'\n", .{v});
                return;
            };
        } else if (std.mem.startsWith(u8, a, "--")) {
            std.debug.print("unknown flag: '{s}'\n", .{a});
            printUsage();
            return;
        } else {
            // Arg slice is borrowed from arg iterator's internal buffer; copy.
            const copy = try allocator.dupe(u8, a);
            try selected.append(allocator, copy);
        }
    }
    defer for (selected.items) |s| allocator.free(s);

    var corpora_set = try corpus.CorpusSet.init(allocator, corpus_size);
    defer corpora_set.deinit();

    std.debug.print(
        \\ezicode benchmarks
        \\==================
        \\samples per case: {d} (plus 1 warmup, discarded)
        \\corpus size:      {d} bytes × 3 (ASCII / Multilingual / Pathological)
        \\
    , .{ framework.sample_runs, corpus_size });

    var ran_any = false;
    for (registry) |s| {
        if (selected.items.len > 0) {
            var matched = false;
            for (selected.items) |q| {
                if (moduleMatches(s.module_name, q)) {
                    matched = true;
                    break;
                }
            }
            if (!matched) continue;
        }
        framework.runSuite(s, allocator, &corpora_set.corpora);
        ran_any = true;
    }

    if (selected.items.len > 0 and !ran_any) {
        std.debug.print(
            "\nNo modules matched the selection. Use --list to see registered modules.\n",
            .{},
        );
    }

    std.debug.print("\nDone.\n", .{});
}
