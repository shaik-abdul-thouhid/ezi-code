//! Benchmarks for `unicode/width`.

const std = @import("std");
const framework = @import("../framework.zig");
const ezi = @import("ezi_code");
const ts = ezi.transcoding;
const width = ezi.unicode.width;

const Context = framework.Context;
const RunResult = framework.RunResult;

const CodePoint = u21;
const inner: u32 = 12;

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

fn caseEastAsianWidth(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    var accum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (cps) |cp| {
            accum +%= @intFromEnum(width.eastAsianWidth(cp));
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

fn caseTerminalColumnWidth(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    var accum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (cps) |cp| {
            accum +%= width.terminalColumnWidth(cp);
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

pub const suite: framework.Suite = .{
    .module_name = "unicode/width",
    .description = "East-Asian-Width property and computed terminal-column width.",
    .cases = &.{
        .{ .name = "eastAsianWidth()", .run = caseEastAsianWidth, .setup = setup, .teardown = teardown },
        .{ .name = "terminalColumnWidth()", .run = caseTerminalColumnWidth, .setup = setup, .teardown = teardown },
    },
};
