const std = @import("std");
const timer = @import("timer.zig");
const track_allocator = @import("track_allocator.zig");
const ezi = @import("ezi_code");
const utf8 = ezi.encoding.utf8;
const utf32 = ezi.encoding.utf32;

const config = @import("config.zig");
const report = @import("report.zig");

/// Bench-only: builds UTF-32 code units from a valid UTF-8 corpus.
fn buildUtf32Corpus(allocator: std.mem.Allocator, utf8_corpus: []const u8) ![]u32 {
    const scratch = try allocator.alloc(u32, utf8_corpus.len);
    errdefer allocator.free(scratch);

    var i: usize = 0;
    var o: usize = 0;
    while (i < utf8_corpus.len) {
        const cp = try utf8.validateAndDecodeCodePointBytes(utf8_corpus, i);
        o += @as(usize, try utf32.encodeCodePoint(cp.code_point, scratch[o..]));
        i += @as(usize, cp.len);
    }

    const owned = try allocator.alloc(u32, o);
    @memcpy(owned, scratch[0..o]);
    allocator.free(scratch);
    return owned;
}

fn benchReverseFullScan(corpus: []const u32) !void {
    var off = corpus.len;
    while (off > 0) {
        const cp = try utf32.validateAndDecodeU32CodePointReverse(corpus[0..off]);
        off -= @as(usize, cp.len);
    }
}

pub fn runSuite(comptime suite_title: []const u8, utf8_corpus: []const u8, inner: config.Utf32InnerPasses) !void {
    const corpus = try buildUtf32Corpus(std.heap.page_allocator, utf8_corpus);
    defer std.heap.page_allocator.free(corpus);

    if (corpus.len == 0) return;

    var corpus_h_buf: [80]u8 = undefined;
    const corpus_human = report.formatBytes(@as(u128, @intCast(corpus.len * @sizeOf(u32))), &corpus_h_buf);

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

    const wl_utf32 = "UTF-32 code units examined / parsed";

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
                    const cp = try utf32.validateAndDecodeU32CodePoint(corpus, i);
                    i += @as(usize, cp.len);
                }
            }
            const t1 = timer.monotonicNanos();
            time_sum += t1 - t0;
            peak_sum += tr.peak_in_use;
            vol_sum += tr.total_allocated;
        }

        report.printRow(
            "validateAndDecodeU32CodePoint full corpus scan (× inner iterations)",
            time_sum / config.sample_runs,
            @intCast(peak_sum / config.sample_runs),
            @intCast(vol_sum / config.sample_runs),
            @as(u128, @intCast(corpus.len)) * inner.validate_scan,
            wl_utf32,
        );
    }

    // --- initUTF32View ---
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
                _ = try utf32.initUTF32View(corpus, .little, &unicode_str_len);
            }
            const t1 = timer.monotonicNanos();
            time_sum += t1 - t0;
            peak_sum += tr.peak_in_use;
            vol_sum += tr.total_allocated;
        }

        report.printRow(
            "initUTF32View(corpus) (× inner iterations)",
            time_sum / config.sample_runs,
            @intCast(peak_sum / config.sample_runs),
            @intCast(vol_sum / config.sample_runs),
            @as(u128, @intCast(corpus.len)) * inner.init_view,
            wl_utf32,
        );
    }

    // --- countScalar ---
    {
        var time_sum: u128 = 0;
        var peak_sum: u128 = 0;
        var vol_sum: u128 = 0;
        var tr = track_allocator.TrackAllocator.init(std.heap.page_allocator);
        const view = utf32.initUTF32ViewUnchecked(corpus, .little);

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
            "UTF32View.countScalar (unchecked view)",
            time_sum / config.sample_runs,
            @intCast(peak_sum / config.sample_runs),
            @intCast(vol_sum / config.sample_runs),
            @as(u128, @intCast(corpus.len)) * inner.count_scalar,
            wl_utf32,
        );
    }

    // --- sliceScalars + utf32ViewToUTF32String ---
    {
        var time_sum: u128 = 0;
        var peak_sum: u128 = 0;
        var vol_sum: u128 = 0;
        var tr = track_allocator.TrackAllocator.init(std.heap.page_allocator);
        var unicode_str_len: usize = 0;
        const view = try utf32.initUTF32View(corpus, .little, &unicode_str_len);
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
                _ = try utf32.utf32ViewToUTF32String(&slice, scratch[0..take]);
            }
            const t1 = timer.monotonicNanos();
            time_sum += t1 - t0;
            peak_sum += tr.peak_in_use;
            vol_sum += tr.total_allocated;
        }

        report.printRow(
            "sliceScalars(0,n) + utf32ViewToUTF32String into stack buffer",
            time_sum / config.sample_runs,
            @intCast(peak_sum / config.sample_runs),
            @intCast(vol_sum / config.sample_runs),
            workload_slice_units,
            wl_utf32,
        );
    }

    // --- bufToUTF32String ---
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
                const s = try utf32.bufToUTF32String(a, corpus, .little);
                a.free(s);
            }
            const t1 = timer.monotonicNanos();
            time_sum += t1 - t0;
            peak_sum += tr.peak_in_use;
            vol_sum += tr.total_allocated;
        }

        report.printRow(
            "bufToUTF32String alloc+free (× inner iterations)",
            time_sum / config.sample_runs,
            @intCast(peak_sum / config.sample_runs),
            @intCast(vol_sum / config.sample_runs),
            @as(u128, @intCast(corpus.len)) * inner.to_string,
            wl_utf32,
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
            "reverse scalar walk (validateAndDecodeU32CodePointReverse, full corpus × inner iterations)",
            time_sum / config.sample_runs,
            @intCast(peak_sum / config.sample_runs),
            @intCast(vol_sum / config.sample_runs),
            @as(u128, @intCast(corpus.len)) * inner.reverse_checked,
            wl_utf32,
        );
    }
}
