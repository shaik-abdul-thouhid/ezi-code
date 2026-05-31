//! Benchmarks for `encoding/utf16`. Uses the UTF-8 corpus transcoded to u16.

const std = @import("std");
const framework = @import("../framework.zig");
const ezi = @import("ezi_code");
const utf16 = ezi.utf16;
const ts = ezi.transcoding;

const Case = framework.Case;
const Context = framework.Context;
const RunResult = framework.RunResult;

const native_endian: utf16.Endian = if (@import("builtin").cpu.arch.endian() == .little) .little else .big;

const inner_scan: u32 = 6;
const inner_view: u32 = 6;
const inner_alloc: u32 = 3;

/// Per-corpus state: a heap-allocated u16 buffer with native endianness.
const State = struct {
    allocator: std.mem.Allocator,
    units: []u16,
};

fn state(ctx: *Context) *State {
    return @ptrCast(@alignCast(ctx.user.?));
}

fn setup(ctx: *Context) anyerror!void {
    const heap = std.heap.page_allocator;
    const units = try ts.utf8ToUtf16(heap, ctx.corpus.bytes);
    const st = try heap.create(State);
    st.* = .{ .allocator = heap, .units = units };
    ctx.user = st;
}

fn teardown(ctx: *Context) anyerror!void {
    const st = state(ctx);
    st.allocator.free(st.units);
    st.allocator.destroy(st);
    ctx.user = null;
}

fn unitsBytes(units: []const u16) u64 {
    return @as(u64, units.len) * 2;
}

fn caseValidateForward(ctx: *Context) !RunResult {
    const units = state(ctx).units;
    var sink: u32 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_scan) : (n += 1) {
        var i: usize = 0;
        while (i < units.len) {
            const cp = try utf16.validateAndDecodeU16CodePoint(units, i);
            sink +%= @intCast(cp.code_point);
            i += @as(usize, cp.len);
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(sink);
    return .{ .bytes_processed = unitsBytes(units) * inner_scan, .ops = ops };
}

fn caseValidateLossyForward(ctx: *Context) !RunResult {
    const units = state(ctx).units;
    var sink: u32 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_scan) : (n += 1) {
        var i: usize = 0;
        while (i < units.len) {
            const cp = try utf16.validateAndDecodeU16CodePointLossy(units, i);
            sink +%= @intCast(cp.code_point);
            i += cp.len;
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(sink);
    return .{ .bytes_processed = unitsBytes(units) * inner_scan, .ops = ops };
}

fn caseReverseWalk(ctx: *Context) !RunResult {
    const units = state(ctx).units;
    var sink: u32 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_scan) : (n += 1) {
        var off = units.len;
        while (off > 0) {
            const cp = try utf16.validateAndDecodeU16CodePointReverse(units, off - 1);
            sink +%= @intCast(cp.code_point);
            off -= @as(usize, cp.len);
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(sink);
    return .{ .bytes_processed = unitsBytes(units) * inner_scan, .ops = ops };
}

fn caseViewIterator(ctx: *Context) !RunResult {
    const units = state(ctx).units;
    const view = utf16.initUTF16ViewUnchecked(units);
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
    return .{ .bytes_processed = unitsBytes(units) * inner_view, .ops = ops };
}

fn caseLossyIterator(ctx: *Context) !RunResult {
    const units = state(ctx).units;
    var sink: u32 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_view) : (n += 1) {
        var it = utf16.lossyIterator(units);
        while (it.next()) |cp| {
            sink +%= @intCast(cp);
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(sink);
    return .{ .bytes_processed = unitsBytes(units) * inner_view, .ops = ops };
}

fn caseCountScalarUnchecked(ctx: *Context) !RunResult {
    const units = state(ctx).units;
    const view = utf16.initUTF16ViewUnchecked(units);
    var total: u64 = 0;
    var n: u32 = 0;
    while (n < inner_view) : (n += 1) {
        total += view.countScalar();
    }
    std.mem.doNotOptimizeAway(total);
    return .{ .bytes_processed = unitsBytes(units) * inner_view, .ops = total };
}

fn caseInitUTF16View(ctx: *Context) !RunResult {
    const units = state(ctx).units;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_view) : (n += 1) {
        var len: usize = 0;
        _ = try utf16.initUTF16View(units, &len);
        ops += len;
    }
    return .{ .bytes_processed = unitsBytes(units) * inner_view, .ops = ops };
}

fn caseBufToUTF16String(ctx: *Context) !RunResult {
    const units = state(ctx).units;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_alloc) : (n += 1) {
        const s = try utf16.bufToUTF16String(ctx.allocator, units);
        ops += s.len;
        ctx.allocator.free(s);
    }
    return .{ .bytes_processed = unitsBytes(units) * inner_alloc, .ops = ops };
}

fn caseEncodeRoundTrip(ctx: *Context) !RunResult {
    const units = state(ctx).units;
    var buf: [2]u16 = undefined;
    var sink: u16 = 0;
    var ops: u64 = 0;
    var written_units: u64 = 0;
    var n: u32 = 0;
    while (n < inner_scan) : (n += 1) {
        var i: usize = 0;
        while (i < units.len) {
            const cp = try utf16.validateAndDecodeU16CodePoint(units, i);
            const len = try utf16.encodeCodePoint(cp.code_point, &buf);
            sink +%= buf[0];
            i += @as(usize, cp.len);
            written_units += len;
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(sink);
    return .{ .bytes_processed = written_units * 2, .ops = ops };
}

pub const suite: framework.Suite = .{
    .module_name = "encoding/utf16",
    .description = "UTF-16 validation, iteration, and encoding round-trip. Corpus is the UTF-8 input pre-transcoded to native-endian u16.",
    .cases = &.{
        .{ .name = "validateAndDecodeU16CodePoint (forward)", .run = caseValidateForward, .setup = setup, .teardown = teardown },
        .{ .name = "validateAndDecodeU16CodePointLossy (forward)", .run = caseValidateLossyForward, .setup = setup, .teardown = teardown },
        .{ .name = "validateAndDecodeU16CodePointReverse (reverse walk)", .run = caseReverseWalk, .setup = setup, .teardown = teardown },
        .{ .name = "UTF16View.iter().next() loop", .run = caseViewIterator, .setup = setup, .teardown = teardown },
        .{ .name = "lossyIterator.next() loop", .run = caseLossyIterator, .setup = setup, .teardown = teardown },
        .{ .name = "UTF16View.countScalar (unchecked)", .run = caseCountScalarUnchecked, .setup = setup, .teardown = teardown },
        .{ .name = "initUTF16View (validate + count pass)", .run = caseInitUTF16View, .setup = setup, .teardown = teardown },
        .{ .name = "bufToUTF16String (alloc + decode + free)", .run = caseBufToUTF16String, .setup = setup, .teardown = teardown },
        .{ .name = "decode + encodeCodePoint round-trip", .run = caseEncodeRoundTrip, .setup = setup, .teardown = teardown },
    },
};
