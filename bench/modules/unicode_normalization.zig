//! Benchmarks for `unicode/normalization`.
//!
//! Two groups:
//!   1. DerivedNormalizationProps lookups — Quick_Check / casefold / expands /
//!      exclusion predicates over a pre-decoded code-point array.
//!   2. Full normalization — `normalize(form, allocator, input)` for every
//!      form, plus `isNormalized` for the QC-only fast-path comparison.
//!
//! Each case runs against the ASCII / Multilingual / Pathological corpora.
//! ASCII should be dominated by the QC fast-path (every cp is `.yes` so
//! `normalize` reduces to `allocator.dupe`).

const std = @import("std");
const framework = @import("../framework.zig");
const ezi = @import("ezi_code");
const ts = ezi.transcoding;
const normalization = ezi.unicode.normalization;

const Case = framework.Case;
const Context = framework.Context;
const RunResult = framework.RunResult;

const CodePoint = u21;
const inner: u32 = 8;
const inner_normalize: u32 = 2; // normalize is much heavier; fewer inner reps

const State = struct {
    allocator: std.mem.Allocator,
    code_points: []CodePoint,
};

fn state(ctx: *Context) *State {
    return @ptrCast(@alignCast(ctx.user.?));
}

fn setup(ctx: *Context) anyerror!void {
    const heap = std.heap.page_allocator;
    const cps = try ts.utf8ToUtf32(heap, ctx.corpus.bytes);
    const cp21 = try heap.alloc(CodePoint, cps.len);
    for (cps, 0..) |u, i| cp21[i] = @intCast(u);
    heap.free(cps);

    const st = try heap.create(State);
    st.* = .{ .allocator = heap, .code_points = cp21 };
    ctx.user = st;
}

fn teardown(ctx: *Context) anyerror!void {
    const st = state(ctx);
    st.allocator.free(st.code_points);
    st.allocator.destroy(st);
    ctx.user = null;
}

fn cpBytes(cps: []const CodePoint) u64 {
    return @as(u64, cps.len) * @sizeOf(CodePoint);
}

// ============================================================================
// Group 1: DerivedNormalizationProps per-codepoint lookups
// ============================================================================

fn runBoolPredicate(ctx: *Context, comptime predicate: anytype) !RunResult {
    const cps = state(ctx).code_points;
    var truthy: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (cps) |cp| {
            if (predicate(cp)) truthy += 1;
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(truthy);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

fn caseIsFullCompositionExclusion(ctx: *Context) !RunResult {
    return runBoolPredicate(ctx, normalization.isFullCompositionExclusion);
}
fn caseIsChangesWhenNfkcCasefolded(ctx: *Context) !RunResult {
    return runBoolPredicate(ctx, normalization.isChangesWhenNfkcCasefolded);
}
fn caseIsExpandsOnNfd(ctx: *Context) !RunResult {
    return runBoolPredicate(ctx, normalization.isExpandsOnNfd);
}
fn caseIsExpandsOnNfkc(ctx: *Context) !RunResult {
    return runBoolPredicate(ctx, normalization.isExpandsOnNfkc);
}

fn runQuickCheck(ctx: *Context, comptime form: normalization.QuickCheckForm) !RunResult {
    const cps = state(ctx).code_points;
    var accum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (cps) |cp| {
            accum +%= @intFromEnum(normalization.quickCheck(form, cp));
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

fn caseQuickCheckNfc(ctx: *Context) !RunResult {
    return runQuickCheck(ctx, .nfc);
}
fn caseQuickCheckNfd(ctx: *Context) !RunResult {
    return runQuickCheck(ctx, .nfd);
}
fn caseQuickCheckNfkc(ctx: *Context) !RunResult {
    return runQuickCheck(ctx, .nfkc);
}
fn caseQuickCheckNfkd(ctx: *Context) !RunResult {
    return runQuickCheck(ctx, .nfkd);
}

fn runCasefoldMap(ctx: *Context, comptime kind: normalization.CasefoldKind) !RunResult {
    const cps = state(ctx).code_points;
    var accum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (cps) |cp| {
            if (normalization.casefoldMap(kind, cp)) |s| accum +%= s.len;
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

fn caseNfkcCaseFold(ctx: *Context) !RunResult {
    return runCasefoldMap(ctx, .nfkc_cf);
}
fn caseNfkcSimpleCaseFold(ctx: *Context) !RunResult {
    return runCasefoldMap(ctx, .nfkc_scf);
}
fn caseFcNfkc(ctx: *Context) !RunResult {
    return runCasefoldMap(ctx, .fc_nfkc);
}

// ============================================================================
// Group 2: full normalize() and isNormalized() over each corpus
// ============================================================================

fn runNormalize(ctx: *Context, comptime form: normalization.NormalizationForm) !RunResult {
    const cps = state(ctx).code_points;
    var sum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_normalize) : (n += 1) {
        const out = try normalization.normalize(form, ctx.allocator, cps);
        defer ctx.allocator.free(out);
        sum +%= out.len;
        ops += cps.len;
    }
    std.mem.doNotOptimizeAway(sum);
    return .{ .bytes_processed = cpBytes(cps) * inner_normalize, .ops = ops };
}

fn caseNormalizeNfc(ctx: *Context) !RunResult {
    return runNormalize(ctx, .nfc);
}
fn caseNormalizeNfd(ctx: *Context) !RunResult {
    return runNormalize(ctx, .nfd);
}
fn caseNormalizeNfkc(ctx: *Context) !RunResult {
    return runNormalize(ctx, .nfkc);
}
fn caseNormalizeNfkd(ctx: *Context) !RunResult {
    return runNormalize(ctx, .nfkd);
}

fn runDecompose(ctx: *Context, comptime form: normalization.DecompositionForm) !RunResult {
    const cps = state(ctx).code_points;
    var sum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_normalize) : (n += 1) {
        const out = try normalization.decompose(form, ctx.allocator, cps);
        defer ctx.allocator.free(out);
        sum +%= out.len;
        ops += cps.len;
    }
    std.mem.doNotOptimizeAway(sum);
    return .{ .bytes_processed = cpBytes(cps) * inner_normalize, .ops = ops };
}

fn caseDecomposeNfd(ctx: *Context) !RunResult {
    return runDecompose(ctx, .nfd);
}
fn caseDecomposeNfkd(ctx: *Context) !RunResult {
    return runDecompose(ctx, .nfkd);
}

fn runCompose(ctx: *Context, comptime form: normalization.CompositionForm) !RunResult {
    const cps = state(ctx).code_points;
    var sum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_normalize) : (n += 1) {
        const out = try normalization.compose(form, ctx.allocator, cps);
        defer ctx.allocator.free(out);
        sum +%= out.len;
        ops += cps.len;
    }
    std.mem.doNotOptimizeAway(sum);
    return .{ .bytes_processed = cpBytes(cps) * inner_normalize, .ops = ops };
}

fn caseComposeNfc(ctx: *Context) !RunResult {
    return runCompose(ctx, .nfc);
}
fn caseComposeNfkc(ctx: *Context) !RunResult {
    return runCompose(ctx, .nfkc);
}

fn runIsNormalized(ctx: *Context, comptime form: normalization.NormalizationForm) !RunResult {
    const cps = state(ctx).code_points;
    var truthy: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        if (normalization.isNormalized(form, cps)) truthy += 1;
        ops += cps.len;
    }
    std.mem.doNotOptimizeAway(truthy);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

fn caseIsNormalizedNfc(ctx: *Context) !RunResult {
    return runIsNormalized(ctx, .nfc);
}
fn caseIsNormalizedNfd(ctx: *Context) !RunResult {
    return runIsNormalized(ctx, .nfd);
}

// ============================================================================
// Streaming Normalizer — push one cp at a time, drain into scratch buffer.
// ============================================================================

fn runStreaming(ctx: *Context, comptime form: normalization.NormalizationForm) !RunResult {
    const cps = state(ctx).code_points;
    var sum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_normalize) : (n += 1) {
        var norm = normalization.Normalizer(form).init();
        var scratch: [normalization.MAX_DECOMP_LEN]CodePoint = undefined;
        for (cps) |cp| {
            const emitted = norm.feed(cp, &scratch);
            sum +%= emitted.len;
            ops += 1;
        }
        const tail = norm.flush(&scratch);
        sum +%= tail.len;
    }
    std.mem.doNotOptimizeAway(sum);
    return .{ .bytes_processed = cpBytes(cps) * inner_normalize, .ops = ops };
}

fn caseStreamingNfc(ctx: *Context) !RunResult {
    return runStreaming(ctx, .nfc);
}
fn caseStreamingNfd(ctx: *Context) !RunResult {
    return runStreaming(ctx, .nfd);
}

pub const suite: framework.Suite = .{
    .module_name = "unicode/normalization",
    .description = "Quick_Check + casefold predicates AND full NFC/NFD/NFKC/NFKD normalization (batch + streaming).",
    .cases = &.{
        // ----- Full normalization (allocating) -----
        .{ .name = "normalize(.nfc)", .run = caseNormalizeNfc, .setup = setup, .teardown = teardown },
        .{ .name = "normalize(.nfd)", .run = caseNormalizeNfd, .setup = setup, .teardown = teardown },
        .{ .name = "normalize(.nfkc)", .run = caseNormalizeNfkc, .setup = setup, .teardown = teardown },
        .{ .name = "normalize(.nfkd)", .run = caseNormalizeNfkd, .setup = setup, .teardown = teardown },
        // ----- Decompose/compose primitives -----
        .{ .name = "decompose(.nfd)", .run = caseDecomposeNfd, .setup = setup, .teardown = teardown },
        .{ .name = "decompose(.nfkd)", .run = caseDecomposeNfkd, .setup = setup, .teardown = teardown },
        .{ .name = "compose(.nfc)", .run = caseComposeNfc, .setup = setup, .teardown = teardown },
        .{ .name = "compose(.nfkc)", .run = caseComposeNfkc, .setup = setup, .teardown = teardown },
        // ----- Streaming Normalizer (no allocation) -----
        .{ .name = "Normalizer(.nfc).feed()", .run = caseStreamingNfc, .setup = setup, .teardown = teardown },
        .{ .name = "Normalizer(.nfd).feed()", .run = caseStreamingNfd, .setup = setup, .teardown = teardown },
        // ----- QC fast-path -----
        .{ .name = "isNormalized(.nfc)", .run = caseIsNormalizedNfc, .setup = setup, .teardown = teardown },
        .{ .name = "isNormalized(.nfd)", .run = caseIsNormalizedNfd, .setup = setup, .teardown = teardown },
        // ----- DNP per-codepoint lookups (the originals) -----
        .{ .name = "quickCheck(.nfc)", .run = caseQuickCheckNfc, .setup = setup, .teardown = teardown },
        .{ .name = "quickCheck(.nfd)", .run = caseQuickCheckNfd, .setup = setup, .teardown = teardown },
        .{ .name = "quickCheck(.nfkc)", .run = caseQuickCheckNfkc, .setup = setup, .teardown = teardown },
        .{ .name = "quickCheck(.nfkd)", .run = caseQuickCheckNfkd, .setup = setup, .teardown = teardown },
        .{ .name = "casefoldMap(.nfkc_cf)", .run = caseNfkcCaseFold, .setup = setup, .teardown = teardown },
        .{ .name = "casefoldMap(.nfkc_scf)", .run = caseNfkcSimpleCaseFold, .setup = setup, .teardown = teardown },
        .{ .name = "casefoldMap(.fc_nfkc)", .run = caseFcNfkc, .setup = setup, .teardown = teardown },
        .{ .name = "isFullCompositionExclusion()", .run = caseIsFullCompositionExclusion, .setup = setup, .teardown = teardown },
        .{ .name = "isChangesWhenNfkcCasefolded()", .run = caseIsChangesWhenNfkcCasefolded, .setup = setup, .teardown = teardown },
        .{ .name = "isExpandsOnNfd()", .run = caseIsExpandsOnNfd, .setup = setup, .teardown = teardown },
        .{ .name = "isExpandsOnNfkc()", .run = caseIsExpandsOnNfkc, .setup = setup, .teardown = teardown },
    },
};
