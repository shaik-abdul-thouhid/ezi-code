const std = @import("std");
const timer = @import("timer.zig");
const track_allocator = @import("track_allocator.zig");
const ezi = @import("ezi_code");
const utf8 = ezi.utf8;

const unicode = std.unicode;

const config = @import("config.zig");
const report = @import("report.zig");

fn benchReverseFullScan(corpus: []const u8) !void {
    var off = corpus.len;

    while (off > 0) {
        const cp = try utf8.validateAndDecodeCodePointBytesReverse(corpus, off - 1);
        const start = off - @as(usize, cp.len);
        const forward =
            try utf8.validateAndDecodeCodePointBytes(corpus, start);

        std.debug.assert(forward.code_point == cp.code_point);
        std.debug.assert(forward.len == cp.len);
        off -= @as(usize, cp.len);
    }
}

pub fn runSuite(comptime suite_title: []const u8, corpus: []const u8, inner: config.Utf8InnerPasses) !void {
    var corpus_h_buf: [80]u8 = undefined;
    const corpus_human = report.formatBytes(@as(u128, @intCast(corpus.len)), &corpus_h_buf);

    std.debug.print("\n{s}\n", .{suite_title});
    std.debug.print(
        \\
        \\corpus: {s} — inner passes: validate_scan={d}, init_view={d}, count_scalar={d},
        \\  slice_to_utf32={d}, to_string={d}, reverse_walk={d}
        \\
    , .{
        corpus_human,
        inner.validate_scan,
        inner.init_view,
        inner.count_scalar,
        inner.slice_iter,
        inner.to_string,
        inner.reverse_checked,
    });

    const wl_utf8 = "UTF-8 bytes examined / parsed";

    // --- validate + decode scan ---
    {
        var time_sum: u128 = 0;
        var peak_sum: u128 = 0;
        var vol_sum: u128 = 0;
        var tr = track_allocator.TrackAllocator.init(std.heap.page_allocator);

        for (0..config.sample_runs) |_| {
            tr.resetStats();
            const t0 = timer.monotonicNanos();
            var r: usize = 0;
            while (r < inner.validate_scan) : (r += 1) {
                var i: usize = 0;
                while (i < corpus.len) {
                    const cp = try utf8.validateAndDecodeCodePointBytes(corpus, i);
                    i += @as(usize, cp.len);
                }
            }
            const t1 = timer.monotonicNanos();
            time_sum += t1 - t0;
            peak_sum += tr.peak_in_use;
            vol_sum += tr.total_allocated;
        }

        report.printRow(
            "validateAndDecodeCodePointBytes full corpus scan (× inner iterations)",
            time_sum / config.sample_runs,
            @intCast(peak_sum / config.sample_runs),
            @intCast(vol_sum / config.sample_runs),
            @as(u128, @intCast(corpus.len)) * inner.validate_scan,
            wl_utf8,
        );
    }

    // --- initUTF8View ---
    {
        var time_sum: u128 = 0;
        var peak_sum: u128 = 0;
        var vol_sum: u128 = 0;
        var tr = track_allocator.TrackAllocator.init(std.heap.page_allocator);

        for (0..config.sample_runs) |_| {
            tr.resetStats();
            const t0 = timer.monotonicNanos();
            var r: usize = 0;
            while (r < inner.init_view) : (r += 1) {
                var unicode_str_len: usize = 0;
                _ = try utf8.initUTF8View(corpus, &unicode_str_len);
            }
            const t1 = timer.monotonicNanos();
            time_sum += t1 - t0;
            peak_sum += tr.peak_in_use;
            vol_sum += tr.total_allocated;
        }

        report.printRow(
            "initUTF8View(corpus) (× inner iterations)",
            time_sum / config.sample_runs,
            @intCast(peak_sum / config.sample_runs),
            @intCast(vol_sum / config.sample_runs),
            @as(u128, @intCast(corpus.len)) * inner.init_view,
            wl_utf8,
        );
    }

    // --- countScalar ---
    {
        var time_sum: u128 = 0;
        var peak_sum: u128 = 0;
        var vol_sum: u128 = 0;
        var tr = track_allocator.TrackAllocator.init(std.heap.page_allocator);
        const view = utf8.initUTF8ViewUnchecked(corpus);

        for (0..config.sample_runs) |_| {
            tr.resetStats();
            const t0 = timer.monotonicNanos();
            var r: usize = 0;
            while (r < inner.count_scalar) : (r += 1) {
                _ = view.countScalar();
            }
            const t1 = timer.monotonicNanos();
            time_sum += t1 - t0;
            peak_sum += tr.peak_in_use;
            vol_sum += tr.total_allocated;
        }

        report.printRow(
            "UTF8View.countScalar (unchecked view)",
            time_sum / config.sample_runs,
            @intCast(peak_sum / config.sample_runs),
            @intCast(vol_sum / config.sample_runs),
            @as(u128, @intCast(corpus.len)) * inner.count_scalar,
            wl_utf8,
        );
    }

    // --- sliceScalars + utf8ViewToUTF8String ---
    {
        var time_sum: u128 = 0;
        var peak_sum: u128 = 0;
        var vol_sum: u128 = 0;
        var tr = track_allocator.TrackAllocator.init(std.heap.page_allocator);
        var unicode_str_len: usize = 0;
        const view = try utf8.initUTF8View(corpus, &unicode_str_len);
        const take = @min(unicode_str_len, 4000);
        const workload_slice_bytes: u128 =
            @as(u128, @intCast((try view.sliceScalars(0, take)).data.len)) * inner.slice_iter;
        var scratch: [4096]u21 = undefined;

        for (0..config.sample_runs) |_| {
            tr.resetStats();
            const t0 = timer.monotonicNanos();
            var r: usize = 0;
            while (r < inner.slice_iter) : (r += 1) {
                const slice = try view.sliceScalars(0, take);
                _ = try utf8.utf8ViewToUTF8String(&slice, scratch[0..take]);
            }
            const t1 = timer.monotonicNanos();
            time_sum += t1 - t0;
            peak_sum += tr.peak_in_use;
            vol_sum += tr.total_allocated;
        }

        report.printRow(
            "sliceScalars(0,n) + utf8ViewToUTF8String into stack buffer",
            time_sum / config.sample_runs,
            @intCast(peak_sum / config.sample_runs),
            @intCast(vol_sum / config.sample_runs),
            workload_slice_bytes,
            wl_utf8,
        );
    }

    // --- bytesToUTF8String ---
    {
        var time_sum: u128 = 0;
        var peak_sum: u128 = 0;
        var vol_sum: u128 = 0;
        var tr = track_allocator.TrackAllocator.init(std.heap.page_allocator);
        const a = tr.allocator();

        for (0..config.sample_runs) |_| {
            tr.resetStats();
            const t0 = timer.monotonicNanos();
            var r: usize = 0;
            while (r < inner.to_string) : (r += 1) {
                const s = try utf8.bytesToUTF8String(a, corpus);
                a.free(s);
            }
            const t1 = timer.monotonicNanos();
            time_sum += t1 - t0;
            peak_sum += tr.peak_in_use;
            vol_sum += tr.total_allocated;
        }

        report.printRow(
            "bytesToUTF8String alloc+free (× inner iterations)",
            time_sum / config.sample_runs,
            @intCast(peak_sum / config.sample_runs),
            @intCast(vol_sum / config.sample_runs),
            @as(u128, @intCast(corpus.len)) * inner.to_string,
            wl_utf8,
        );
    }

    // --- reverse walk ---
    {
        var time_sum: u128 = 0;
        var peak_sum: u128 = 0;
        var vol_sum: u128 = 0;
        var tr = track_allocator.TrackAllocator.init(std.heap.page_allocator);

        for (0..config.sample_runs) |_| {
            tr.resetStats();
            const t0 = timer.monotonicNanos();
            var r: usize = 0;
            while (r < inner.reverse_checked) : (r += 1) {
                try benchReverseFullScan(corpus);
            }
            const t1 = timer.monotonicNanos();
            time_sum += t1 - t0;
            peak_sum += tr.peak_in_use;
            vol_sum += tr.total_allocated;
        }

        report.printRow(
            "reverse scalar walk (bytesToUTF8CodePointReverseChecked, full corpus × inner iterations)",
            time_sum / config.sample_runs,
            @intCast(peak_sum / config.sample_runs),
            @intCast(vol_sum / config.sample_runs),
            @as(u128, @intCast(corpus.len)) * inner.reverse_checked,
            wl_utf8,
        );
    }

    // --- std.unicode utf8ValidateSlice ---

    {
        var time_sum: u128 = 0;

        var peak_sum: u128 = 0;

        var vol_sum: u128 = 0;

        var tr = track_allocator.TrackAllocator.init(std.heap.page_allocator);

        for (0..config.sample_runs) |_| {
            tr.resetStats();

            const t0 = timer.monotonicNanos();

            var r: usize = 0;

            while (r < inner.validate_scan) : (r += 1) {
                _ = unicode.utf8ValidateSlice(corpus);
            }

            const t1 = timer.monotonicNanos();

            time_sum += t1 - t0;

            peak_sum += tr.peak_in_use;

            vol_sum += tr.total_allocated;
        }

        report.printRow(
            "std.unicode.utf8ValidateSlice (× inner iterations)",

            time_sum / config.sample_runs,

            @intCast(peak_sum / config.sample_runs),

            @intCast(vol_sum / config.sample_runs),

            @as(u128, @intCast(corpus.len)) * inner.validate_scan,

            wl_utf8,
        );
    }

    // --- std.unicode.Utf8View.init ---

    {
        var time_sum: u128 = 0;

        var peak_sum: u128 = 0;

        var vol_sum: u128 = 0;

        var tr = track_allocator.TrackAllocator.init(std.heap.page_allocator);

        for (0..config.sample_runs) |_| {
            tr.resetStats();

            const t0 = timer.monotonicNanos();

            var r: usize = 0;

            while (r < inner.init_view) : (r += 1) {
                _ = try unicode.Utf8View.init(corpus);
            }

            const t1 = timer.monotonicNanos();

            time_sum += t1 - t0;

            peak_sum += tr.peak_in_use;

            vol_sum += tr.total_allocated;
        }

        report.printRow(
            "std.unicode.Utf8View.init (× inner iterations)",

            time_sum / config.sample_runs,

            @intCast(peak_sum / config.sample_runs),

            @intCast(vol_sum / config.sample_runs),

            @as(u128, @intCast(corpus.len)) * inner.init_view,

            wl_utf8,
        );
    }
}
