//! Benchmarks for `unicode/casing`.

const std = @import("std");
const framework = @import("../framework.zig");
const ezi = @import("ezi_code");
const ts = ezi.transcoding;
const casing = ezi.unicode.casing;

const Case = framework.Case;
const Context = framework.Context;
const RunResult = framework.RunResult;

const CodePoint = u21;
const inner: u32 = 6;

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

fn runSimple(ctx: *Context, comptime fn_ptr: fn (CodePoint) CodePoint) !RunResult {
    const cps = state(ctx).code_points;
    var accum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (cps) |cp| {
            accum +%= fn_ptr(cp);
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

fn caseToUpperCase(ctx: *Context) !RunResult {
    return runSimple(ctx, casing.toUpperCase);
}
fn caseToLowerCase(ctx: *Context) !RunResult {
    return runSimple(ctx, casing.toLowerCase);
}
fn caseToTitleCase(ctx: *Context) !RunResult {
    return runSimple(ctx, casing.toTitleCase);
}
fn caseCaseFoldSimple(ctx: *Context) !RunResult {
    return runSimple(ctx, casing.caseFoldSimple);
}
fn caseCaseFoldSimpleTurkic(ctx: *Context) !RunResult {
    return runSimple(ctx, casing.caseFoldSimpleTurkic);
}

fn caseCaseFoldFull(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    var accum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (cps) |cp| {
            const r = casing.caseFoldFull(cp);
            for (r.slice()) |out| accum +%= out;
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

fn caseToLowerCaseFull(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    var accum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (cps) |cp| {
            const r = casing.toLowerCaseFull(cp, .none, .none);
            for (r.slice()) |out| accum +%= out;
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

fn caseToUpperCaseFull(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    var accum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (cps) |cp| {
            const r = casing.toUpperCaseFull(cp, .none, .none);
            for (r.slice()) |out| accum +%= out;
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

pub const suite: framework.Suite = .{
    .module_name = "unicode/casing",
    .description = "Simple and full case mappings over pre-decoded code points.",
    .cases = &.{
        .{ .name = "toUpperCase() (simple)", .run = caseToUpperCase, .setup = setup, .teardown = teardown },
        .{ .name = "toLowerCase() (simple)", .run = caseToLowerCase, .setup = setup, .teardown = teardown },
        .{ .name = "toTitleCase() (simple)", .run = caseToTitleCase, .setup = setup, .teardown = teardown },
        .{ .name = "caseFoldSimple()", .run = caseCaseFoldSimple, .setup = setup, .teardown = teardown },
        .{ .name = "caseFoldSimpleTurkic()", .run = caseCaseFoldSimpleTurkic, .setup = setup, .teardown = teardown },
        .{ .name = "caseFoldFull()", .run = caseCaseFoldFull, .setup = setup, .teardown = teardown },
        .{ .name = "toLowerCaseFull(.none, .none)", .run = caseToLowerCaseFull, .setup = setup, .teardown = teardown },
        .{ .name = "toUpperCaseFull(.none, .none)", .run = caseToUpperCaseFull, .setup = setup, .teardown = teardown },
    },
};
