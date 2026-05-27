//! Benchmarks for `unicode/scripts` — the Script and Script_Extensions
//! property lookups (UAX #24).

const std = @import("std");
const framework = @import("../framework.zig");
const ezi = @import("ezi_code");
const ts = ezi.transcoding;
const scripts = ezi.unicode.scripts;

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

fn caseScriptType(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    var accum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (cps) |cp| {
            accum +%= @intFromEnum(scripts.scriptType(cp));
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

fn caseScriptExtensions(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    var accum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (cps) |cp| {
            // Touch every element so the slice (and the @missing fallback
            // singleton) is actually materialized, not optimized away.
            for (scripts.scriptExtensions(cp)) |s| accum +%= @intFromEnum(s);
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

fn caseHasScriptExtension(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    var hits: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (cps) |cp| {
            if (scripts.hasScriptExtension(cp, .latin)) hits +%= 1;
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(hits);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

pub const suite: framework.Suite = .{
    .module_name = "unicode/scripts",
    .description = "Script property and Script_Extensions set lookups (UAX #24).",
    .cases = &.{
        .{ .name = "scriptType()", .run = caseScriptType, .setup = setup, .teardown = teardown },
        .{ .name = "scriptExtensions()", .run = caseScriptExtensions, .setup = setup, .teardown = teardown },
        .{ .name = "hasScriptExtension(.latin)", .run = caseHasScriptExtension, .setup = setup, .teardown = teardown },
    },
};
