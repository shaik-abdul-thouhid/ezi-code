const std = @import("std");
const config = @import("config.zig");

pub fn durationMs(ns: u128) f64 {
    return @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(std.time.ns_per_ms));
}

pub fn formatBytes(n: u128, buf: []u8) []const u8 {
    if (n == 0) return "none";

    const KiB: u128 = 1024;
    const MiB = KiB * 1024;
    const GiB = MiB * 1024;

    if (n < KiB) {
        return std.fmt.bufPrint(buf, "{d} bytes", .{n}) catch unreachable;
    }
    if (n < MiB) {
        const v = @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(KiB));
        return std.fmt.bufPrint(buf, "{d:.2} KiB", .{v}) catch unreachable;
    }
    if (n < GiB) {
        const v = @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(MiB));
        return std.fmt.bufPrint(buf, "{d:.2} MiB", .{v}) catch unreachable;
    }
    const v = @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(GiB));
    return std.fmt.bufPrint(buf, "{d:.2} GiB", .{v}) catch unreachable;
}

pub fn printRow(
    name: []const u8,
    avg_ns: u128,
    avg_peak: usize,
    avg_total_alloc: usize,
    workload_bytes_per_run: u128,
    workload_caption: []const u8,
) void {
    var b1: [72]u8 = undefined;
    var b2: [72]u8 = undefined;
    var b3: [72]u8 = undefined;

    const work = formatBytes(workload_bytes_per_run, &b1);
    const peak = formatBytes(@as(u128, @intCast(avg_peak)), &b2);
    const volume = formatBytes(@as(u128, @intCast(avg_total_alloc)), &b3);

    std.debug.print("{s}\n", .{name});
    std.debug.print("  mean wall time ({d} samples): {d:.3} ms\n", .{ config.sample_runs, durationMs(avg_ns) });
    std.debug.print("  workload per timed run ({s}): {s}\n", .{ workload_caption, work });
    std.debug.print("  mean peak allocator footprint: {s}\n", .{peak});
    std.debug.print("  mean total allocation volume: {s}\n", .{volume});
}
