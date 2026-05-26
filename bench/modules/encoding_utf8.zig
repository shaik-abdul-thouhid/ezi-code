//! Benchmarks for `encoding/utf8`.

const std = @import("std");
const framework = @import("../framework.zig");
const ezi = @import("ezi_code");
const utf8 = ezi.utf8;

const Case = framework.Case;
const Context = framework.Context;
const RunResult = framework.RunResult;

const inner_scan: u32 = 4;
const inner_view: u32 = 4;
const inner_encode: u32 = 2;
const inner_alloc: u32 = 2;

fn caseValidateForward(ctx: *Context) !RunResult {
    const corpus = ctx.corpus.bytes;
    var sink: u32 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_scan) : (n += 1) {
        var i: usize = 0;
        while (i < corpus.len) {
            const cp = try utf8.validateAndDecodeCodePointBytes(corpus, i);
            sink +%= @intCast(cp.code_point);
            i += @as(usize, cp.len);
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(sink);
    return .{ .bytes_processed = @as(u64, corpus.len) * inner_scan, .ops = ops };
}

fn caseValidateLossyForward(ctx: *Context) !RunResult {
    const corpus = ctx.corpus.bytes;
    var sink: u32 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_scan) : (n += 1) {
        var i: usize = 0;
        while (i < corpus.len) {
            const cp = try utf8.validateAndDecodeCodePointBytesLossy(corpus, i);
            sink +%= @intCast(cp.code_point);
            i += cp.len;
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(sink);
    return .{ .bytes_processed = @as(u64, corpus.len) * inner_scan, .ops = ops };
}

fn caseReverseWalk(ctx: *Context) !RunResult {
    const corpus = ctx.corpus.bytes;
    var sink: u32 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_scan) : (n += 1) {
        var off = corpus.len;
        while (off > 0) {
            const cp = try utf8.validateAndDecodeCodePointBytesReverse(corpus, off - 1);
            sink +%= @intCast(cp.code_point);
            off -= @as(usize, cp.len);
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(sink);
    return .{ .bytes_processed = @as(u64, corpus.len) * inner_scan, .ops = ops };
}

fn caseViewIterator(ctx: *Context) !RunResult {
    const corpus = ctx.corpus.bytes;
    const view = utf8.initUTF8ViewUnchecked(corpus);
    var sink: u32 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_view) : (n += 1) {
        var it = view.iter();
        while (it.next()) |cp| {
            sink +%= @intCast(cp);
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(sink);
    return .{ .bytes_processed = @as(u64, corpus.len) * inner_view, .ops = ops };
}

fn caseLossyIterator(ctx: *Context) !RunResult {
    const corpus = ctx.corpus.bytes;
    var sink: u32 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_view) : (n += 1) {
        var it = utf8.lossyIterator(corpus);
        while (it.next()) |cp| {
            sink +%= @intCast(cp);
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(sink);
    return .{ .bytes_processed = @as(u64, corpus.len) * inner_view, .ops = ops };
}

fn caseCountScalarUnchecked(ctx: *Context) !RunResult {
    const corpus = ctx.corpus.bytes;
    const view = utf8.initUTF8ViewUnchecked(corpus);
    var total: u64 = 0;
    var n: u32 = 0;
    while (n < inner_view) : (n += 1) {
        total += view.countScalar();
    }
    std.mem.doNotOptimizeAway(total);
    return .{ .bytes_processed = @as(u64, corpus.len) * inner_view, .ops = total };
}

fn caseInitUTF8View(ctx: *Context) !RunResult {
    const corpus = ctx.corpus.bytes;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_view) : (n += 1) {
        var len: usize = 0;
        _ = try utf8.initUTF8View(corpus, &len);
        ops += len;
    }
    return .{ .bytes_processed = @as(u64, corpus.len) * inner_view, .ops = ops };
}

fn caseBytesToUTF8String(ctx: *Context) !RunResult {
    const corpus = ctx.corpus.bytes;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_alloc) : (n += 1) {
        const s = try utf8.bytesToUTF8String(ctx.allocator, corpus);
        ops += s.len;
        ctx.allocator.free(s);
    }
    return .{ .bytes_processed = @as(u64, corpus.len) * inner_alloc, .ops = ops };
}

fn caseEncodeRoundTrip(ctx: *Context) !RunResult {
    const corpus = ctx.corpus.bytes;
    var buf: [4]u8 = undefined;
    var sink: u32 = 0;
    var ops: u64 = 0;
    var written: u64 = 0;
    var n: u32 = 0;
    while (n < inner_encode) : (n += 1) {
        var i: usize = 0;
        while (i < corpus.len) {
            const cp = try utf8.validateAndDecodeCodePointBytes(corpus, i);
            const len = try utf8.encodeCodePoint(cp.code_point, &buf);
            sink +%= buf[0];
            i += @as(usize, cp.len);
            written += len;
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(sink);
    return .{ .bytes_processed = written, .ops = ops };
}

pub const suite: framework.Suite = .{
    .module_name = "encoding/utf8",
    .description = "Validation, iteration, view construction, and encode round-trip.",
    .cases = &.{
        .{ .name = "validateAndDecodeCodePointBytes (forward scan)", .run = caseValidateForward, .notes = "Hot path: strict validation + decode." },
        .{ .name = "validateAndDecodeCodePointBytesLossy (forward scan)", .run = caseValidateLossyForward, .notes = "Replaces malformed bytes with U+FFFD instead of erroring." },
        .{ .name = "validateAndDecodeCodePointBytesReverse (reverse walk)", .run = caseReverseWalk, .notes = "Backward iteration cost." },
        .{ .name = "UTF8View.iter().next() loop", .run = caseViewIterator, .notes = "Iterator overhead on unchecked view." },
        .{ .name = "lossyIterator.next() loop", .run = caseLossyIterator },
        .{ .name = "UTF8View.countScalar (unchecked)", .run = caseCountScalarUnchecked },
        .{ .name = "initUTF8View (validate + count pass)", .run = caseInitUTF8View },
        .{ .name = "bytesToUTF8String (alloc + decode + free)", .run = caseBytesToUTF8String },
        .{ .name = "decode + encodeCodePoint round-trip", .run = caseEncodeRoundTrip },
    },
};
