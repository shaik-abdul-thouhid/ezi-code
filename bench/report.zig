//! Human-readable formatters for time, memory, and throughput.

const std = @import("std");

pub const ns_per_us: f64 = 1_000.0;
pub const ns_per_ms: f64 = 1_000_000.0;
pub const ns_per_s: f64 = 1_000_000_000.0;

pub fn formatDuration(ns: f64, buf: []u8) []const u8 {
    if (ns < 1_000.0) {
        return std.fmt.bufPrint(buf, "{d:.2} ns", .{ns}) catch unreachable;
    }
    if (ns < 1_000_000.0) {
        return std.fmt.bufPrint(buf, "{d:.2} us", .{ns / ns_per_us}) catch unreachable;
    }
    if (ns < 1_000_000_000.0) {
        return std.fmt.bufPrint(buf, "{d:.3} ms", .{ns / ns_per_ms}) catch unreachable;
    }
    return std.fmt.bufPrint(buf, "{d:.3} s", .{ns / ns_per_s}) catch unreachable;
}

pub fn formatBytes(n_u128: u128, buf: []u8) []const u8 {
    const n: f64 = @floatFromInt(n_u128);
    const KiB: f64 = 1024.0;
    const MiB: f64 = KiB * 1024.0;
    const GiB: f64 = MiB * 1024.0;

    if (n_u128 == 0) return std.fmt.bufPrint(buf, "0 B", .{}) catch unreachable;
    if (n < KiB) return std.fmt.bufPrint(buf, "{d} B", .{n_u128}) catch unreachable;
    if (n < MiB) return std.fmt.bufPrint(buf, "{d:.2} KiB", .{n / KiB}) catch unreachable;
    if (n < GiB) return std.fmt.bufPrint(buf, "{d:.2} MiB", .{n / MiB}) catch unreachable;
    return std.fmt.bufPrint(buf, "{d:.2} GiB", .{n / GiB}) catch unreachable;
}

pub fn formatBytesFloat(n: f64, buf: []u8) []const u8 {
    const KiB: f64 = 1024.0;
    const MiB: f64 = KiB * 1024.0;
    const GiB: f64 = MiB * 1024.0;

    if (n < 1.0) return std.fmt.bufPrint(buf, "{d:.2} B", .{n}) catch unreachable;
    if (n < KiB) return std.fmt.bufPrint(buf, "{d:.0} B", .{n}) catch unreachable;
    if (n < MiB) return std.fmt.bufPrint(buf, "{d:.2} KiB", .{n / KiB}) catch unreachable;
    if (n < GiB) return std.fmt.bufPrint(buf, "{d:.2} MiB", .{n / MiB}) catch unreachable;
    return std.fmt.bufPrint(buf, "{d:.2} GiB", .{n / GiB}) catch unreachable;
}

/// Throughput in bytes/second, rendered with the right unit.
/// Returns "n/a" if ns is zero.
pub fn formatThroughput(bytes: u64, ns: f64, buf: []u8) []const u8 {
    if (ns <= 0.0 or bytes == 0) {
        return std.fmt.bufPrint(buf, "n/a", .{}) catch unreachable;
    }
    const bytes_f: f64 = @floatFromInt(bytes);
    const bps = bytes_f * ns_per_s / ns;

    const KiB: f64 = 1024.0;
    const MiB: f64 = KiB * 1024.0;
    const GiB: f64 = MiB * 1024.0;

    if (bps < KiB) return std.fmt.bufPrint(buf, "{d:.2} B/s", .{bps}) catch unreachable;
    if (bps < MiB) return std.fmt.bufPrint(buf, "{d:.2} KiB/s", .{bps / KiB}) catch unreachable;
    if (bps < GiB) return std.fmt.bufPrint(buf, "{d:.2} MiB/s", .{bps / MiB}) catch unreachable;
    return std.fmt.bufPrint(buf, "{d:.2} GiB/s", .{bps / GiB}) catch unreachable;
}

/// Operations / second. Renders with k/M/G suffixes.
pub fn formatOpsPerSec(ops: u64, ns: f64, buf: []u8) []const u8 {
    if (ns <= 0.0 or ops == 0) {
        return std.fmt.bufPrint(buf, "n/a", .{}) catch unreachable;
    }
    const ops_f: f64 = @floatFromInt(ops);
    const ops_per_s = ops_f * ns_per_s / ns;

    if (ops_per_s < 1_000.0) return std.fmt.bufPrint(buf, "{d:.2} op/s", .{ops_per_s}) catch unreachable;
    if (ops_per_s < 1_000_000.0) return std.fmt.bufPrint(buf, "{d:.2} kop/s", .{ops_per_s / 1_000.0}) catch unreachable;
    if (ops_per_s < 1_000_000_000.0) return std.fmt.bufPrint(buf, "{d:.2} Mop/s", .{ops_per_s / 1_000_000.0}) catch unreachable;
    return std.fmt.bufPrint(buf, "{d:.2} Gop/s", .{ops_per_s / 1_000_000_000.0}) catch unreachable;
}
