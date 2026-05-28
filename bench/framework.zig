//! Generic benchmark runner: each Case is sampled N=sample_runs times with a
//! warmup, time + memory tracked, then summarized as mean ± stddev with
//! min / max / median, plus throughput in bytes/sec and ops/sec.
//!
//! To add a new module: create a file in `bench/modules/` that exports
//!   pub const suite: framework.Suite = .{ ... };
//! and register it in `bench/main.zig`.

const std = @import("std");
const timer = @import("timer.zig");
const TrackAllocator = @import("track_allocator.zig").TrackAllocator;
const report = @import("report.zig");

pub const warmup_runs: usize = 1;

/// Shared input data passed to every case in a suite.
pub const Corpus = struct {
    name: []const u8,
    bytes: []const u8,
};

/// Mutable per-case execution context.
pub const Context = struct {
    allocator: std.mem.Allocator,
    corpus: *const Corpus,
    /// Cases can stash setup-derived state here (e.g. pre-decoded code points)
    /// and read it back in their `run` function.
    user: ?*anyopaque = null,
};

/// Result of a single timed execution.
pub const RunResult = struct {
    /// Throughput is measured against this number of "work bytes" processed.
    /// For encoding/transcoding, use input byte length × inner iterations.
    /// For property predicates, use code_points × inner_iterations × @sizeOf(CodePoint).
    bytes_processed: u64,
    /// Number of discrete operations performed (code points decoded, predicates
    /// evaluated, etc.). Used for ops/sec reporting. Use 0 to suppress.
    ops: u64 = 0,
};

pub const RunFn = *const fn (ctx: *Context) anyerror!RunResult;
pub const HookFn = *const fn (ctx: *Context) anyerror!void;

pub const Case = struct {
    name: []const u8,
    notes: []const u8 = "",
    /// Runs once before any timing. Use for things like pre-decoding a corpus
    /// into a buffer once and stashing the pointer in `ctx.user`.
    setup: ?HookFn = null,
    /// Runs once after the final sample (success or failure).
    teardown: ?HookFn = null,
    /// The measured function. Called once per warmup run and once per sample.
    run: RunFn,
};

pub const Suite = struct {
    module_name: []const u8,
    description: []const u8 = "",
    cases: []const Case,
};

const Sample = struct {
    ns: f64,
    peak_bytes: usize,
    total_alloc_bytes: usize,
    bytes_processed: u64,
    ops: u64,
};

const Stats = struct {
    mean: f64,
    median: f64,
    stddev: f64,
    min: f64,
    max: f64,
};

fn computeStats(allocator: std.mem.Allocator, sample_runs: usize, values: []const f64) Stats {
    std.debug.assert(values.len > 0);
    var sum: f64 = 0;
    var mn = std.math.inf(f64);
    var mx = -std.math.inf(f64);
    for (values) |v| {
        sum += v;
        if (v < mn) mn = v;
        if (v > mx) mx = v;
    }
    const n: f64 = @floatFromInt(values.len);
    const mean = sum / n;

    var sq: f64 = 0;
    for (values) |v| {
        const d = v - mean;
        sq += d * d;
    }
    const stddev = @sqrt(sq / n);

    var sorted = allocator.alloc(f64, sample_runs) catch @panic("unable to alloc sorted");
    defer allocator.free(sorted);

    for (values, 0..) |v, i| sorted[i] = v;
    std.mem.sort(f64, sorted[0..values.len], {}, std.sort.asc(f64));
    const mid = values.len / 2;
    const median = if (values.len % 2 == 1)
        sorted[mid]
    else
        (sorted[mid - 1] + sorted[mid]) / 2.0;

    return .{ .mean = mean, .median = median, .stddev = stddev, .min = mn, .max = mx };
}

fn meanU(values: []const usize) f64 {
    var sum: f64 = 0;
    for (values) |v| sum += @floatFromInt(v);
    return sum / @as(f64, @floatFromInt(values.len));
}

fn meanU64(values: []const u64) f64 {
    var sum: f64 = 0;
    for (values) |v| sum += @floatFromInt(v);
    return sum / @as(f64, @floatFromInt(values.len));
}

const CaseRunError = error{ SampleFailed, SetupFailed };

fn runOneSample(case: Case, ctx: *Context, sample: *Sample) anyerror!void {
    var tr = TrackAllocator.init(std.heap.page_allocator);
    const tracked = tr.allocator();
    // Swap context allocator to the tracked one for this sample only.
    const saved = ctx.allocator;
    ctx.allocator = tracked;
    defer ctx.allocator = saved;

    tr.resetStats();
    const t0 = timer.monotonicNanos();
    const result = try case.run(ctx);
    const t1 = timer.monotonicNanos();
    sample.* = .{
        .ns = @floatFromInt(t1 - t0),
        .peak_bytes = tr.peak_in_use,
        .total_alloc_bytes = tr.total_allocated,
        .bytes_processed = result.bytes_processed,
        .ops = result.ops,
    };
}

fn printCorpusRow(allocator: std.mem.Allocator, sample_runs: usize, corpus_name: []const u8, samples: []const Sample) void {
    var ns_vals = allocator.alloc(f64, sample_runs) catch @panic("unable to allocate ns_vals");
    var peak_vals = allocator.alloc(usize, sample_runs) catch @panic("unable to allocate peak_vals");
    var tot_vals = allocator.alloc(usize, sample_runs) catch @panic("unable to allocate tot_vals");

    defer {
        allocator.free(ns_vals);
        allocator.free(peak_vals);
        allocator.free(tot_vals);
    }

    for (samples, 0..) |s, i| {
        ns_vals[i] = s.ns;
        peak_vals[i] = s.peak_bytes;
        tot_vals[i] = s.total_alloc_bytes;
    }
    const time_stats = computeStats(allocator, sample_runs, ns_vals[0..samples.len]);
    const peak_mean = meanU(peak_vals[0..samples.len]);
    const tot_mean = meanU(tot_vals[0..samples.len]);

    var bytes_sum: u128 = 0;
    var ops_sum: u128 = 0;
    for (samples) |s| {
        bytes_sum += s.bytes_processed;
        ops_sum += s.ops;
    }
    const bytes_avg: u64 = @intCast(bytes_sum / samples.len);
    const ops_avg: u64 = @intCast(ops_sum / samples.len);

    var bm: [40]u8 = undefined;
    var bs: [40]u8 = undefined;
    var bth: [40]u8 = undefined;
    var bop: [40]u8 = undefined;
    var bpk: [40]u8 = undefined;
    var btot: [40]u8 = undefined;

    const mean_s = report.formatDuration(time_stats.mean, &bm);
    const sd_s = report.formatDuration(time_stats.stddev, &bs);
    const th_s = if (bytes_avg > 0)
        report.formatThroughput(bytes_avg, time_stats.mean, &bth)
    else
        "—";
    const op_s = if (ops_avg > 0)
        report.formatOpsPerSec(ops_avg, time_stats.mean, &bop)
    else
        "—";
    const pk_s = report.formatBytesFloat(peak_mean, &bpk);
    const tot_s = report.formatBytesFloat(tot_mean, &btot);

    // Single line per corpus. Mean ± stddev over `sample_runs` samples.
    std.debug.print(
        "  {s:<12}  {s:>10} ± {s:<8}  {s:>12}  {s:>12}  mem peak {s} / alloc {s}\n",
        .{ corpus_name, mean_s, sd_s, th_s, op_s, pk_s, tot_s },
    );
}

fn runCaseOnCorpus(case: Case, base_allocator: std.mem.Allocator, sample_runs: usize, corpus: *const Corpus) ?[]Sample {
    var ctx: Context = .{ .allocator = base_allocator, .corpus = corpus };

    if (case.setup) |setup| {
        setup(&ctx) catch |err| {
            std.debug.print("  {s:<12}  setup error: {s}\n", .{ corpus.name, @errorName(err) });
            return null;
        };
    }
    defer if (case.teardown) |td| {
        td(&ctx) catch |err| {
            std.debug.print("  {s:<12}  teardown error: {s}\n", .{ corpus.name, @errorName(err) });
        };
    };

    // Warmup (untimed).
    var w: usize = 0;
    while (w < warmup_runs) : (w += 1) {
        var s: Sample = undefined;
        runOneSample(case, &ctx, &s) catch |err| {
            std.debug.print("  {s:<12}  warmup error: {s}\n", .{ corpus.name, @errorName(err) });
            return null;
        };
    }

    var samples = base_allocator.alloc(Sample, sample_runs) catch @panic("unable to allocate samples");

    var i: usize = 0;
    while (i < sample_runs) : (i += 1) {
        runOneSample(case, &ctx, &samples[i]) catch |err| {
            std.debug.print("  {s:<12}  sample {d} error: {s}\n", .{ corpus.name, i + 1, @errorName(err) });
            return null;
        };
    }
    return samples;
}

pub fn runSuite(suite: Suite, allocator: std.mem.Allocator, sample_runs: usize, corpora: []const Corpus) void {
    std.debug.print("\n## {s}\n", .{suite.module_name});
    if (suite.description.len > 0) {
        std.debug.print("   {s}\n", .{suite.description});
    }
    std.debug.print(
        "   columns: corpus  mean ± stddev (n={d})  throughput  ops/sec  memory\n",
        .{sample_runs},
    );

    for (suite.cases) |case| {
        std.debug.print("\n• {s}", .{case.name});
        if (case.notes.len > 0) {
            std.debug.print("   — {s}", .{case.notes});
        }
        std.debug.print("\n", .{});

        for (corpora) |c| {
            const samples = runCaseOnCorpus(case, allocator, sample_runs, &c) orelse continue;
            printCorpusRow(allocator, sample_runs, c.name, samples);
            allocator.free(samples);
        }
    }
}
