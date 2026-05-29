//! Benchmarks for the Tier-4 metadata property lookups (UAX #44):
//! Numeric_Type, Numeric_Value, Block, Hangul_Syllable_Type, and Age. All are
//! deduplicated 2-level page tables, so this measures the cost of the two
//! array indexes plus the per-property post-processing.

const std = @import("std");
const framework = @import("../framework.zig");
const ezi = @import("ezi_code");
const ts = ezi.transcoding;
const numeric = ezi.unicode.numeric;
const blocks = ezi.unicode.blocks;
const hangul = ezi.unicode.hangul;
const age_mod = ezi.unicode.age;

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

fn caseNumericType(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    var accum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (cps) |cp| {
            accum +%= @intFromEnum(numeric.numericType(cp));
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

fn caseNumericValue(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    var accum: i64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (cps) |cp| {
            if (numeric.numericValue(cp)) |v| accum +%= v.numerator;
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

fn caseBlock(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    var accum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (cps) |cp| {
            accum +%= @intFromEnum(blocks.block(cp));
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

fn caseHangulSyllableType(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    var accum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (cps) |cp| {
            accum +%= @intFromEnum(hangul.hangulSyllableType(cp));
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

fn caseAge(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    var accum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (cps) |cp| {
            accum +%= @intFromEnum(age_mod.age(cp));
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

pub const suite: framework.Suite = .{
    .module_name = "unicode/numeric-metadata",
    .description = "Numeric_Type/Value, Block, Hangul_Syllable_Type, and Age lookups (UAX #44).",
    .cases = &.{
        .{ .name = "numericType()", .run = caseNumericType, .setup = setup, .teardown = teardown },
        .{ .name = "numericValue()", .run = caseNumericValue, .setup = setup, .teardown = teardown },
        .{ .name = "block()", .run = caseBlock, .setup = setup, .teardown = teardown },
        .{ .name = "hangulSyllableType()", .run = caseHangulSyllableType, .setup = setup, .teardown = teardown },
        .{ .name = "age()", .run = caseAge, .setup = setup, .teardown = teardown },
    },
};
