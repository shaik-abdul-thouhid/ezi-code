//! Monotonic time in nanoseconds (platform-specific).
const std = @import("std");
const builtin = @import("builtin");

pub fn monotonicNanos() u128 {
    switch (builtin.os.tag) {
        .linux => {
            var ts: std.os.linux.timespec = undefined;
            const rc = std.os.linux.clock_gettime(.MONOTONIC, &ts);
            std.debug.assert(rc == 0);
            const sec: u128 = @intCast(@max(ts.sec, 0));
            const nsec: u128 = @intCast(@max(ts.nsec, 0));
            return sec * std.time.ns_per_s + nsec;
        },
        .macos, .ios, .tvos, .watchos, .visionos, .maccatalyst => {
            var info: std.c.mach_timebase_info_data = undefined;
            _ = std.c.mach_timebase_info(&info);
            const ticks = std.c.mach_absolute_time();
            return @as(u128, ticks) * @as(u128, info.numer) / @as(u128, info.denom);
        },
        .windows => {
            const S = struct {
                var freq_hz: ?u128 = null;
            };
            if (S.freq_hz == null) {
                var f: std.os.windows.LARGE_INTEGER = undefined;
                std.debug.assert(std.os.windows.ntdll.RtlQueryPerformanceFrequency(&f) != 0);
                const hz: u128 = @intCast(@max(f, 1));
                S.freq_hz = hz;
            }
            var c: std.os.windows.LARGE_INTEGER = undefined;
            std.debug.assert(std.os.windows.ntdll.RtlQueryPerformanceCounter(&c) != 0);
            const ct: u64 = @intCast(@max(c, 0));
            return @as(u128, ct) * std.time.ns_per_s / S.freq_hz.?;
        },
        else => {
            @compileError("bench/timer.zig: add monotonicNanos() for this OS");
        },
    }
}
