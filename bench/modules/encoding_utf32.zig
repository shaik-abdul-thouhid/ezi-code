//! Benchmarks for `encoding/utf32`. Uses the UTF-8 corpus transcoded to u32.

const std = @import("std");
const framework = @import("../framework.zig");
const ezi = @import("ezi_code");
const utf32 = ezi.utf32;
const ts = ezi.transcoding;

const Case = framework.Case;
const Context = framework.Context;
const RunResult = framework.RunResult;

const native_endian: utf32.Endian = if (@import("builtin").cpu.arch.endian() == .little) .little else .big;

const inner_scan: u32 = 8;
const inner_view: u32 = 8;
const inner_alloc: u32 = 3;

const State = struct {
    allocator: std.mem.Allocator,
    units: []u32,
};

fn state(ctx: *Context) *State {
    return @ptrCast(@alignCast(ctx.user.?));
}

fn setup(ctx: *Context) anyerror!void {
    const heap = std.heap.page_allocator;
    const units = try ts.utf8ToUtf32(heap, ctx.corpus.bytes);
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

fn unitsBytes(units: []const u32) u64 {
    return @as(u64, units.len) * 4;
}

fn caseValidateForward(ctx: *Context) !RunResult {
    const units = state(ctx).units;
    var sink: u32 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_scan) : (n += 1) {
        var i: usize = 0;
        while (i < units.len) {
            const cp = try utf32.validateAndDecodeU32CodePoint(units, i);
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
            const cp = try utf32.validateAndDecodeU32CodePointLossy(units, i);
            sink +%= @intCast(cp.code_point);
            i += cp.len;
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(sink);
    return .{ .bytes_processed = unitsBytes(units) * inner_scan, .ops = ops };
}

fn caseViewIterator(ctx: *Context) !RunResult {
    const units = state(ctx).units;
    const view = utf32.initUTF32ViewUnchecked(units, native_endian);
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
        var it = utf32.lossyIterator(units);
        while (it.next()) |cp| {
            sink +%= @intCast(cp);
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(sink);
    return .{ .bytes_processed = unitsBytes(units) * inner_view, .ops = ops };
}

fn caseInitUTF32View(ctx: *Context) !RunResult {
    const units = state(ctx).units;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_view) : (n += 1) {
        var len: usize = 0;
        _ = try utf32.initUTF32View(units, native_endian, &len);
        ops += len;
    }
    return .{ .bytes_processed = unitsBytes(units) * inner_view, .ops = ops };
}

fn caseBufToUTF32String(ctx: *Context) !RunResult {
    const units = state(ctx).units;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_alloc) : (n += 1) {
        const s = try utf32.bufToUTF32String(ctx.allocator, units, native_endian);
        ops += s.len;
        ctx.allocator.free(s);
    }
    return .{ .bytes_processed = unitsBytes(units) * inner_alloc, .ops = ops };
}

fn caseEncodeRoundTrip(ctx: *Context) !RunResult {
    const units = state(ctx).units;
    var buf: [1]u32 = undefined;
    var sink: u32 = 0;
    var ops: u64 = 0;
    var written_units: u64 = 0;
    var n: u32 = 0;
    while (n < inner_scan) : (n += 1) {
        var i: usize = 0;
        while (i < units.len) {
            const cp = try utf32.validateAndDecodeU32CodePoint(units, i);
            const len = try utf32.encodeCodePoint(cp.code_point, &buf);
            sink +%= buf[0];
            i += @as(usize, cp.len);
            written_units += len;
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(sink);
    return .{ .bytes_processed = written_units * 4, .ops = ops };
}

pub const suite: framework.Suite = .{
    .module_name = "encoding/utf32",
    .description = "UTF-32 validation, iteration, and encode round-trip. Corpus is UTF-8 input pre-transcoded to native-endian u32.",
    .cases = &.{
        .{ .name = "validateAndDecodeU32CodePoint (forward)", .run = caseValidateForward, .setup = setup, .teardown = teardown },
        .{ .name = "validateAndDecodeU32CodePointLossy (forward)", .run = caseValidateLossyForward, .setup = setup, .teardown = teardown },
        .{ .name = "UTF32View.iter().next() loop", .run = caseViewIterator, .setup = setup, .teardown = teardown },
        .{ .name = "lossyIterator.next() loop", .run = caseLossyIterator, .setup = setup, .teardown = teardown },
        .{ .name = "initUTF32View (validate + count pass)", .run = caseInitUTF32View, .setup = setup, .teardown = teardown },
        .{ .name = "bufToUTF32String (alloc + decode + free)", .run = caseBufToUTF32String, .setup = setup, .teardown = teardown },
        .{ .name = "decode + encodeCodePoint round-trip", .run = caseEncodeRoundTrip, .setup = setup, .teardown = teardown },
    },
};
