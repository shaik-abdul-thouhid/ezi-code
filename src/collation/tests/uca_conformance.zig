const std = @import("std");
const builtin = @import("builtin");

const collation = @import("../root.zig");

const testing = std.testing;
const Allocator = std.mem.Allocator;
const CodePoint = @import("encoding").CodePoint;

const zip_path = "ucd/CollationTest.zip";
const extracted_root = "CollationTest";

fn cleanLine(raw: []const u8) []const u8 {
    const without_hash = if (std.mem.indexOfScalar(u8, raw, '#')) |idx| raw[0..idx] else raw;
    const without_semicolon = if (std.mem.indexOfScalar(u8, without_hash, ';')) |idx| without_hash[0..idx] else without_hash;
    return std.mem.trim(u8, without_semicolon, " \t\r");
}

fn parseCodePointSequence(allocator: Allocator, line: []const u8, out: *std.ArrayListUnmanaged(CodePoint)) !void {
    out.clearRetainingCapacity();
    if (line.len == 0) return;

    var it = std.mem.splitAny(u8, line, " \t");
    while (it.next()) |token_raw| {
        const token = std.mem.trim(u8, token_raw, " \t\r");
        if (token.len == 0) continue;
        const cp = try std.fmt.parseInt(CodePoint, token, 16);
        try out.append(allocator, cp);
    }
}

fn extractCollationTestZip(dest: std.Io.Dir) !void {
    const io = testing.io;
    var zip_file = try std.Io.Dir.cwd().openFile(io, zip_path, .{});
    defer zip_file.close(io);

    var reader_buf: [64 * 1024]u8 = undefined;
    var fr = std.Io.File.Reader.init(zip_file, io, &reader_buf);
    try std.zip.extract(dest, &fr, .{});
}

fn runConformanceFile(
    allocator: Allocator,
    dir: std.Io.Dir,
    relative_path: []const u8,
    options: collation.Options,
) !void {
    const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ extracted_root, relative_path });
    defer allocator.free(full_path);

    const text = try dir.readFileAlloc(testing.io, full_path, allocator, .limited(80 * 1024 * 1024));
    defer allocator.free(text);

    var collator = collation.Collator.init(options);

    var prev_key: collation.Key = .{};
    defer prev_key.deinit(allocator);
    var curr_key: collation.Key = .{};
    defer curr_key.deinit(allocator);

    var cps: std.ArrayListUnmanaged(CodePoint) = .empty;
    defer cps.deinit(allocator);

    var have_prev = false;
    var line_no: usize = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        line_no += 1;
        const line = cleanLine(raw_line);
        if (line.len == 0) continue;
        if (line[0] == '#') continue;

        try parseCodePointSequence(allocator, line, &cps);
        try collator.buildKey(allocator, cps.items, &curr_key);

        if (have_prev) {
            const order = collator.compareKeys(&prev_key, &curr_key);
            if (order == .gt) {
                std.debug.print("UCA conformance failed in {s} at input line {d}\n", .{ relative_path, line_no });
                return error.TestExpectedEqual;
            }
        } else {
            have_prev = true;
        }

        std.mem.swap(collation.Key, &prev_key, &curr_key);
    }
}

test "uca conformance: NON_IGNORABLE (short)" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try extractCollationTestZip(tmp.dir);

    try runConformanceFile(
        testing.allocator,
        tmp.dir,
        "CollationTest_NON_IGNORABLE_SHORT.txt",
        .{ .variable_weighting = .non_ignorable, .strength = .identical },
    );
}

test "uca conformance: SHIFTED (short)" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try extractCollationTestZip(tmp.dir);

    try runConformanceFile(
        testing.allocator,
        tmp.dir,
        "CollationTest_SHIFTED_SHORT.txt",
        .{ .variable_weighting = .shifted, .strength = .identical },
    );
}

test "uca conformance: NON_IGNORABLE (full)" {
    if (builtin.mode == .Debug) return;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try extractCollationTestZip(tmp.dir);

    try runConformanceFile(
        testing.allocator,
        tmp.dir,
        "CollationTest_NON_IGNORABLE.txt",
        .{ .variable_weighting = .non_ignorable, .strength = .identical },
    );
}

test "uca conformance: SHIFTED (full)" {
    if (builtin.mode == .Debug) return;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try extractCollationTestZip(tmp.dir);

    try runConformanceFile(
        testing.allocator,
        tmp.dir,
        "CollationTest_SHIFTED.txt",
        .{ .variable_weighting = .shifted, .strength = .identical },
    );
}
