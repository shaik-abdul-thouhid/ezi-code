//! Benchmarks `utils.slices` u8⟷u16 buffer and allocator conversions.

const std = @import("std");
const timer = @import("timer.zig");
const track_allocator = @import("track_allocator.zig");
const slices = @import("ezi_code").slices;

const config = @import("config.zig");
const report = @import("report.zig");

fn evenCorpus(raw: []const u8) []const u8 {
    return raw[0 .. raw.len - (raw.len & 1)];
}

pub fn runSuite(comptime suite_title: []const u8, raw_corpus: []const u8) !void {
    const corpus = evenCorpus(raw_corpus);
    if (corpus.len == 0) return;

    const n_pairs = corpus.len / 2;
    const u16_scratch = try std.heap.page_allocator.alloc(u16, n_pairs);
    defer std.heap.page_allocator.free(u16_scratch);
    const u8_scratch = try std.heap.page_allocator.alloc(u8, corpus.len);
    defer std.heap.page_allocator.free(u8_scratch);

    var corpus_h_buf: [80]u8 = undefined;
    const corpus_human = report.formatBytes(@as(u128, @intCast(corpus.len)), &corpus_h_buf);

    const inner_buf = config.inner_u16_buffer_passes;
    const inner_alloc = config.inner_u16_alloc_passes;
    const wl = "input bytes (even-length u8 ↔ u16 LE/BE pairs)";

    std.debug.print("\n{s}\n", .{suite_title});
    std.debug.print(
        \\corpus (even-length prefix): {s} — inner buffer passes={d}, inner alloc passes={d}
        \\
    , .{ corpus_human, inner_buf, inner_alloc });

    // --- bytes → u16 buffer (big-endian) ---
    {
        var time_sum: u128 = 0;
        var peak_sum: u128 = 0;
        var vol_sum: u128 = 0;
        var tr = track_allocator.TrackAllocator.init(std.heap.page_allocator);

        for (0..config.sample_runs) |_| {
            tr.resetStats();
            const t0 = timer.monotonicNanos();
            var r: usize = 0;
            while (r < inner_buf) : (r += 1) {
                _ = try slices.bytesToU16SliceBuffer(corpus, u16_scratch, .big, null);
            }
            const t1 = timer.monotonicNanos();
            time_sum += t1 - t0;
            peak_sum += tr.peak_in_use;
            vol_sum += tr.total_allocated;
        }

        report.printRow(
            "bytesToU16SliceBuffer big-endian (× inner iterations)",
            time_sum / config.sample_runs,
            @intCast(peak_sum / config.sample_runs),
            @intCast(vol_sum / config.sample_runs),
            @as(u128, @intCast(corpus.len)) * inner_buf,
            wl,
        );
    }

    // --- bytes → u16 buffer (little-endian) ---
    {
        var time_sum: u128 = 0;
        var peak_sum: u128 = 0;
        var vol_sum: u128 = 0;
        var tr = track_allocator.TrackAllocator.init(std.heap.page_allocator);

        for (0..config.sample_runs) |_| {
            tr.resetStats();
            const t0 = timer.monotonicNanos();
            var r: usize = 0;
            while (r < inner_buf) : (r += 1) {
                _ = try slices.bytesToU16SliceBuffer(corpus, u16_scratch, .little, null);
            }
            const t1 = timer.monotonicNanos();
            time_sum += t1 - t0;
            peak_sum += tr.peak_in_use;
            vol_sum += tr.total_allocated;
        }

        report.printRow(
            "bytesToU16SliceBuffer little-endian (× inner iterations)",
            time_sum / config.sample_runs,
            @intCast(peak_sum / config.sample_runs),
            @intCast(vol_sum / config.sample_runs),
            @as(u128, @intCast(corpus.len)) * inner_buf,
            wl,
        );
    }

    // --- u16 → bytes buffer (big-endian): scratch primed each sample ---
    {
        var time_sum: u128 = 0;
        var peak_sum: u128 = 0;
        var vol_sum: u128 = 0;
        var tr = track_allocator.TrackAllocator.init(std.heap.page_allocator);

        for (0..config.sample_runs) |_| {
            _ = try slices.bytesToU16SliceBuffer(corpus, u16_scratch, .big, null);
            tr.resetStats();
            const t0 = timer.monotonicNanos();
            var r: usize = 0;
            while (r < inner_buf) : (r += 1) {
                _ = try slices.u16SliceToBytesBuffer(u16_scratch, u8_scratch, .big);
            }
            const t1 = timer.monotonicNanos();
            time_sum += t1 - t0;
            peak_sum += tr.peak_in_use;
            vol_sum += tr.total_allocated;
        }

        report.printRow(
            "u16SliceToBytesBuffer big-endian (× inner iterations)",
            time_sum / config.sample_runs,
            @intCast(peak_sum / config.sample_runs),
            @intCast(vol_sum / config.sample_runs),
            @as(u128, @intCast(corpus.len)) * inner_buf,
            wl,
        );
    }

    // --- u16 → bytes buffer (little-endian) ---
    {
        var time_sum: u128 = 0;
        var peak_sum: u128 = 0;
        var vol_sum: u128 = 0;
        var tr = track_allocator.TrackAllocator.init(std.heap.page_allocator);

        for (0..config.sample_runs) |_| {
            _ = try slices.bytesToU16SliceBuffer(corpus, u16_scratch, .little, null);
            tr.resetStats();
            const t0 = timer.monotonicNanos();
            var r: usize = 0;
            while (r < inner_buf) : (r += 1) {
                _ = try slices.u16SliceToBytesBuffer(u16_scratch, u8_scratch, .little);
            }
            const t1 = timer.monotonicNanos();
            time_sum += t1 - t0;
            peak_sum += tr.peak_in_use;
            vol_sum += tr.total_allocated;
        }

        report.printRow(
            "u16SliceToBytesBuffer little-endian (× inner iterations)",
            time_sum / config.sample_runs,
            @intCast(peak_sum / config.sample_runs),
            @intCast(vol_sum / config.sample_runs),
            @as(u128, @intCast(corpus.len)) * inner_buf,
            wl,
        );
    }

    // --- round-trip buffer: decode BE then encode BE ---
    {
        var time_sum: u128 = 0;
        var peak_sum: u128 = 0;
        var vol_sum: u128 = 0;
        var tr = track_allocator.TrackAllocator.init(std.heap.page_allocator);

        for (0..config.sample_runs) |_| {
            tr.resetStats();
            const t0 = timer.monotonicNanos();
            var r: usize = 0;
            while (r < inner_buf) : (r += 1) {
                _ = try slices.bytesToU16SliceBuffer(corpus, u16_scratch, .big, null);
                _ = try slices.u16SliceToBytesBuffer(u16_scratch, u8_scratch, .big);
            }
            const t1 = timer.monotonicNanos();
            time_sum += t1 - t0;
            peak_sum += tr.peak_in_use;
            vol_sum += tr.total_allocated;
        }

        report.printRow(
            "round-trip bytes→u16→bytes buffer big-endian (× inner iterations)",
            time_sum / config.sample_runs,
            @intCast(peak_sum / config.sample_runs),
            @intCast(vol_sum / config.sample_runs),
            @as(u128, @intCast(corpus.len)) * inner_buf * 2,
            wl,
        );
    }

    // --- allocator: bytesToU16Slice + free ---
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
            while (r < inner_alloc) : (r += 1) {
                const dec = try slices.bytesToU16Slice(a, corpus, .big, null);
                a.free(dec);
            }
            const t1 = timer.monotonicNanos();
            time_sum += t1 - t0;
            peak_sum += tr.peak_in_use;
            vol_sum += tr.total_allocated;
        }

        report.printRow(
            "bytesToU16Slice alloc+free big-endian (× inner iterations)",
            time_sum / config.sample_runs,
            @intCast(peak_sum / config.sample_runs),
            @intCast(vol_sum / config.sample_runs),
            @as(u128, @intCast(corpus.len)) * inner_alloc,
            wl,
        );
    }

    // Seed u16_scratch once per sample for alloc encode benchmark
    {
        var time_sum: u128 = 0;
        var peak_sum: u128 = 0;
        var vol_sum: u128 = 0;
        var tr = track_allocator.TrackAllocator.init(std.heap.page_allocator);
        const a = tr.allocator();

        for (0..config.sample_runs) |_| {
            _ = try slices.bytesToU16SliceBuffer(corpus, u16_scratch, .little, null);
            tr.resetStats();
            const t0 = timer.monotonicNanos();
            var r: usize = 0;
            while (r < inner_alloc) : (r += 1) {
                const enc = try slices.u16SliceToBytes(a, u16_scratch, .little);
                a.free(enc);
            }
            const t1 = timer.monotonicNanos();
            time_sum += t1 - t0;
            peak_sum += tr.peak_in_use;
            vol_sum += tr.total_allocated;
        }

        report.printRow(
            "u16SliceToBytes alloc+free little-endian (× inner iterations)",
            time_sum / config.sample_runs,
            @intCast(peak_sum / config.sample_runs),
            @intCast(vol_sum / config.sample_runs),
            @as(u128, @intCast(corpus.len)) * inner_alloc,
            wl,
        );
    }
}
