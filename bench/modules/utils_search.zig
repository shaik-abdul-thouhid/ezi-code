//! Benchmarks for `utils/search` — binary search + range search used by all
//! property/range lookups in the unicode tables.

const std = @import("std");
const framework = @import("../framework.zig");
const ezi = @import("ezi_code");
const ts = ezi.transcoding;
const search = @import("utils").search;

const Context = framework.Context;
const RunResult = framework.RunResult;

const CodePoint = u21;
const inner: u32 = 6;

const TABLE_LEN: usize = 4096;
const Range = struct { start: u32, end: u32, tag: u32 };

const State = struct {
    allocator: std.mem.Allocator,
    code_points: []CodePoint,
    sorted: [TABLE_LEN]u32,
    ranges: [TABLE_LEN]Range,
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
    st.* = .{
        .allocator = heap,
        .code_points = cp21,
        .sorted = undefined,
        .ranges = undefined,
    };

    // Deterministic sorted u32 table covering the entire code-point space.
    const step: u32 = 0x10FFFF / TABLE_LEN;
    for (0..TABLE_LEN) |i| {
        const v: u32 = @intCast(i);
        st.sorted[i] = v * step;
        st.ranges[i] = .{
            .start = v * step,
            .end = v * step + step - 1,
            .tag = v,
        };
    }
    ctx.user = st;
}

fn teardown(ctx: *Context) anyerror!void {
    const st = state(ctx);
    st.allocator.free(st.code_points);
    st.allocator.destroy(st);
    ctx.user = null;
}

fn cmpU32(needle: u32, item: u32) std.math.Order {
    return std.math.order(needle, item);
}

fn caseBinarySearch(ctx: *Context) !RunResult {
    const st = state(ctx);
    var hits: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (st.code_points) |cp| {
            if (search.binarySearch(u32, &st.sorted, @as(u32, cp), cmpU32) != null) hits += 1;
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(hits);
    return .{ .bytes_processed = @as(u64, st.code_points.len) * @sizeOf(CodePoint) * inner, .ops = ops };
}

fn caseSearchRange(ctx: *Context) !RunResult {
    const st = state(ctx);
    var hits: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (st.code_points) |cp| {
            if (search.searchRange(Range, u32, "start", "end", &st.ranges, @as(u32, cp)) != null) hits += 1;
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(hits);
    return .{ .bytes_processed = @as(u64, st.code_points.len) * @sizeOf(CodePoint) * inner, .ops = ops };
}

fn caseContainsInRange(ctx: *Context) !RunResult {
    const st = state(ctx);
    var hits: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (st.code_points) |cp| {
            if (search.containsInRange(Range, u32, "start", "end", &st.ranges, @as(u32, cp))) hits += 1;
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(hits);
    return .{ .bytes_processed = @as(u64, st.code_points.len) * @sizeOf(CodePoint) * inner, .ops = ops };
}

pub const suite: framework.Suite = .{
    .module_name = "utils/search",
    .description = "Binary search and range search over a 4096-entry synthetic table, keyed on each corpus code point.",
    .cases = &.{
        .{ .name = "binarySearch (u32, 4096 entries)", .run = caseBinarySearch, .setup = setup, .teardown = teardown },
        .{ .name = "searchRange (4096 disjoint ranges)", .run = caseSearchRange, .setup = setup, .teardown = teardown },
        .{ .name = "containsInRange (4096 disjoint ranges)", .run = caseContainsInRange, .setup = setup, .teardown = teardown },
    },
};
