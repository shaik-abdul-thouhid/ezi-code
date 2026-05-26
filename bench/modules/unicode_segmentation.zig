//! Benchmarks for `unicode/segmentation` — grapheme, word, sentence, and line iterators.

const std = @import("std");
const framework = @import("../framework.zig");
const ezi = @import("ezi_code");
const ts = ezi.transcoding;
const seg = ezi.unicode.segmentation;

const Case = framework.Case;
const Context = framework.Context;
const RunResult = framework.RunResult;

const CodePoint = u21;
const inner: u32 = 3;
const inner_classifier: u32 = 6;

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

fn caseGraphemeIterator(ctx: *Context) !RunResult {
    const corpus = ctx.corpus.bytes;
    var clusters: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        var it = seg.iterator(corpus);
        while (it.next() != null) clusters += 1;
    }
    return .{ .bytes_processed = @as(u64, corpus.len) * inner, .ops = clusters };
}

fn caseCodePointGraphemeIterator(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    var clusters: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        var it = seg.codePointIterator(cps);
        while (it.next() != null) clusters += 1;
    }
    return .{ .bytes_processed = @as(u64, cps.len) * @sizeOf(CodePoint) * inner, .ops = clusters };
}

fn caseCountGraphemes(ctx: *Context) !RunResult {
    const corpus = ctx.corpus.bytes;
    var clusters: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        clusters += seg.countGraphemes(corpus);
    }
    return .{ .bytes_processed = @as(u64, corpus.len) * inner, .ops = clusters };
}

fn caseWordIterator(ctx: *Context) !RunResult {
    const corpus = ctx.corpus.bytes;
    var words: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        var it = seg.wordIterator(corpus);
        while (it.next() != null) words += 1;
    }
    return .{ .bytes_processed = @as(u64, corpus.len) * inner, .ops = words };
}

fn caseCodePointWordIterator(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    var words: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        var it = seg.codePointWordIterator(cps);
        while (it.next() != null) words += 1;
    }
    return .{ .bytes_processed = @as(u64, cps.len) * @sizeOf(CodePoint) * inner, .ops = words };
}

fn caseSentenceIterator(ctx: *Context) !RunResult {
    const corpus = ctx.corpus.bytes;
    var sentences: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        var it = seg.sentenceIterator(corpus);
        while (it.next() != null) sentences += 1;
    }
    return .{ .bytes_processed = @as(u64, corpus.len) * inner, .ops = sentences };
}

fn caseLineBreakIterator(ctx: *Context) !RunResult {
    const corpus = ctx.corpus.bytes;
    var lines: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        var it = seg.lineBreakIterator(corpus);
        while (it.next() != null) lines += 1;
    }
    return .{ .bytes_processed = @as(u64, corpus.len) * inner, .ops = lines };
}

fn caseGraphemeBreakProperty(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    var accum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_classifier) : (n += 1) {
        for (cps) |cp| {
            accum +%= @intFromEnum(seg.graphemeBreakProperty(cp));
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = @as(u64, cps.len) * @sizeOf(CodePoint) * inner_classifier, .ops = ops };
}

fn caseWordBreakProperty(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    var accum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_classifier) : (n += 1) {
        for (cps) |cp| {
            accum +%= @intFromEnum(seg.wordBreakProperty(cp));
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = @as(u64, cps.len) * @sizeOf(CodePoint) * inner_classifier, .ops = ops };
}

fn caseLineBreakProperty(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    var accum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_classifier) : (n += 1) {
        for (cps) |cp| {
            accum +%= @intFromEnum(seg.lineBreak(cp));
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = @as(u64, cps.len) * @sizeOf(CodePoint) * inner_classifier, .ops = ops };
}

pub const suite: framework.Suite = .{
    .module_name = "unicode/segmentation",
    .description = "UAX #29/#14 grapheme, word, sentence, and line iterators plus raw property lookups.",
    .cases = &.{
        .{ .name = "graphemeBreakProperty()", .run = caseGraphemeBreakProperty, .setup = setup, .teardown = teardown },
        .{ .name = "wordBreakProperty()", .run = caseWordBreakProperty, .setup = setup, .teardown = teardown },
        .{ .name = "lineBreak() property", .run = caseLineBreakProperty, .setup = setup, .teardown = teardown },
        .{ .name = "GraphemeIterator (bytes)", .run = caseGraphemeIterator },
        .{ .name = "CodePointGraphemeIterator", .run = caseCodePointGraphemeIterator, .setup = setup, .teardown = teardown },
        .{ .name = "countGraphemes()", .run = caseCountGraphemes },
        .{ .name = "WordIterator (bytes)", .run = caseWordIterator },
        .{ .name = "CodePointWordIterator", .run = caseCodePointWordIterator, .setup = setup, .teardown = teardown },
        .{ .name = "SentenceIterator (bytes)", .run = caseSentenceIterator },
        .{ .name = "LineBreakIterator (bytes)", .run = caseLineBreakIterator, .notes = "Allocation-free streaming UAX #14." },
    },
};
