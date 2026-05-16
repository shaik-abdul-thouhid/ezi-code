const std = @import("std");
const timer = @import("timer.zig");
const track_allocator = @import("track_allocator.zig");
const ezi = @import("ezi_code");
const utf8 = ezi.utf8;
const utf16 = ezi.utf16;

const config = @import("config.zig");
const report = @import("report.zig");

/// Bench-only: builds UTF-16 units from a valid UTF-8 corpus until a transcoding module exists.
fn buildUtf16Corpus(allocator: std.mem.Allocator, utf8_corpus: []const u8) ![]u16 {
    const scratch = try allocator.alloc(u16, utf8_corpus.len);
    errdefer allocator.free(scratch);

    var i: usize = 0;
    var o: usize = 0;
    while (i < utf8_corpus.len) {
        const cp = try utf8.validateAndDecodeCodePointBytes(utf8_corpus, i);
        o += @as(usize, try utf16.encodeCodePoint(cp.code_point, scratch[o..]));
        i += @as(usize, cp.len);
    }

    const owned = try allocator.alloc(u16, o);
    @memcpy(owned, scratch[0..o]);
    allocator.free(scratch);
    return owned;
}

fn benchReverseFullScan(corpus: []const u16) !void {
    var off = corpus.len;
    while (off > 0) {
        const cp = try utf16.bufToUTF16CodePointReverseChecked(corpus[0..off]);
        off -= @as(usize, cp.len);
    }
}

pub fn runSuite(comptime suite_title: []const u8, utf8_corpus: []const u8, inner: config.Utf16InnerPasses) !void {
    const corpus = try buildUtf16Corpus(std.heap.page_allocator, utf8_corpus);
    defer std.heap.page_allocator.free(corpus);

    if (corpus.len == 0) return;

    var corpus_h_buf: [80]u8 = undefined;
    const corpus_human = report.formatBytes(@as(u128, @intCast(corpus.len * @sizeOf(u16))), &corpus_h_buf);

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

    const wl_utf16 = "UTF-16 code units examined / parsed";

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
                    const cp = try utf16.bufToUTF16CodePointChecked(corpus, i);
                    i += @as(usize, cp.len);
                }
            }
            const t1 = timer.monotonicNanos();
            time_sum += t1 - t0;
            peak_sum += tr.peak_in_use;
            vol_sum += tr.total_allocated;
        }

        report.printRow(
            "bufToUTF16CodePointChecked full corpus scan (× inner iterations)",
            time_sum / config.sample_runs,
            @intCast(peak_sum / config.sample_runs),
            @intCast(vol_sum / config.sample_runs),
            @as(u128, @intCast(corpus.len)) * inner.validate_scan,
            wl_utf16,
        );
    }

    // --- initUTF16View ---
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
                _ = try utf16.initUTF16View(corpus, .little, &unicode_str_len);
            }
            const t1 = timer.monotonicNanos();
            time_sum += t1 - t0;
            peak_sum += tr.peak_in_use;
            vol_sum += tr.total_allocated;
        }

        report.printRow(
            "initUTF16View(corpus) (× inner iterations)",
            time_sum / config.sample_runs,
            @intCast(peak_sum / config.sample_runs),
            @intCast(vol_sum / config.sample_runs),
            @as(u128, @intCast(corpus.len)) * inner.init_view,
            wl_utf16,
        );
    }

    // --- countScalar ---
    {
        var time_sum: u128 = 0;
        var peak_sum: u128 = 0;
        var vol_sum: u128 = 0;
        var tr = track_allocator.TrackAllocator.init(std.heap.page_allocator);
        const view = utf16.initUTF16ViewUnchecked(corpus, .little);

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
            "UTF16View.countScalar (unchecked view)",
            time_sum / config.sample_runs,
            @intCast(peak_sum / config.sample_runs),
            @intCast(vol_sum / config.sample_runs),
            @as(u128, @intCast(corpus.len)) * inner.count_scalar,
            wl_utf16,
        );
    }

    // --- sliceScalars + utf16ViewToUTF16String ---
    {
        var time_sum: u128 = 0;
        var peak_sum: u128 = 0;
        var vol_sum: u128 = 0;
        var tr = track_allocator.TrackAllocator.init(std.heap.page_allocator);
        var unicode_str_len: usize = 0;
        const view = try utf16.initUTF16View(corpus, .little, &unicode_str_len);
        const take = @min(unicode_str_len, 4000);
        const workload_slice_units: u128 =
            @as(u128, @intCast((try view.sliceScalars(0, take)).data.len)) * inner.slice_iter;
        var scratch: [4096]u21 = undefined;

        for (0..config.sample_runs) |_| {
            tr.resetStats();
            const t0 = timer.monotonicNanos();
            var r: usize = 0;
            while (r < inner.slice_iter) : (r += 1) {
                const slice = try view.sliceScalars(0, take);
                _ = try utf16.utf16ViewToUTF16String(&slice, scratch[0..take]);
            }
            const t1 = timer.monotonicNanos();
            time_sum += t1 - t0;
            peak_sum += tr.peak_in_use;
            vol_sum += tr.total_allocated;
        }

        report.printRow(
            "sliceScalars(0,n) + utf16ViewToUTF16String into stack buffer",
            time_sum / config.sample_runs,
            @intCast(peak_sum / config.sample_runs),
            @intCast(vol_sum / config.sample_runs),
            workload_slice_units,
            wl_utf16,
        );
    }

    // --- bufToUTF16String ---
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
                const s = try utf16.bufToUTF16String(a, corpus, .little);
                a.free(s);
            }
            const t1 = timer.monotonicNanos();
            time_sum += t1 - t0;
            peak_sum += tr.peak_in_use;
            vol_sum += tr.total_allocated;
        }

        report.printRow(
            "bufToUTF16String alloc+free (× inner iterations)",
            time_sum / config.sample_runs,
            @intCast(peak_sum / config.sample_runs),
            @intCast(vol_sum / config.sample_runs),
            @as(u128, @intCast(corpus.len)) * inner.to_string,
            wl_utf16,
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
            "reverse scalar walk (bufToUTF16CodePointReverseChecked, full corpus × inner iterations)",
            time_sum / config.sample_runs,
            @intCast(peak_sum / config.sample_runs),
            @intCast(vol_sum / config.sample_runs),
            @as(u128, @intCast(corpus.len)) * inner.reverse_checked,
            wl_utf16,
        );
    }
}
