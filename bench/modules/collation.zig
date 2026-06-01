//! Benchmarks for the `collation` module (UCA / DUCET).
//!
//! Four groups:
//!   1. buildKey — full sort key construction from a pre-decoded code-point slice.
//!   2. serializeAlloc — buildKey + serialize to an owned byte slice.
//!   3. compareCodePoints — end-to-end pairwise comparison (builds + compares keys).
//!   4. compareSerial — compare two pre-built serialized keys (allocation-free memcmp).
//!
//! Each group runs against the ASCII / Multilingual / Pathological corpora.

const std = @import("std");
const framework = @import("../framework.zig");
const ezi = @import("ezi_code");
const ts = ezi.transcoding;
const col = ezi.collation;

const Case = framework.Case;
const Context = framework.Context;
const RunResult = framework.RunResult;

const CodePoint = u21;

// Fewer inner iterations than the pure-predicate benchmarks; key building
// involves NFD normalization and DUCET lookups, making it significantly heavier.
const inner: u32 = 2;
const inner_serial: u32 = 16;

// ============================================================================
// Shared state: pre-decoded code-point array + collator
// ============================================================================

const State = struct {
    allocator: std.mem.Allocator,
    code_points: []CodePoint,
    collator: col.Collator,
};

fn st(ctx: *Context) *State {
    return @ptrCast(@alignCast(ctx.user.?));
}

fn setup(ctx: *Context) anyerror!void {
    const heap = std.heap.page_allocator;
    const cps32 = try ts.utf8ToUtf32(heap, ctx.corpus.bytes);
    defer heap.free(cps32);
    const cp21 = try heap.alloc(CodePoint, cps32.len);
    for (cps32, 0..) |u, i| cp21[i] = @intCast(u);
    const s = try heap.create(State);
    s.* = .{ .allocator = heap, .code_points = cp21, .collator = col.Collator.init(.{}) };
    ctx.user = s;
}

fn teardown(ctx: *Context) anyerror!void {
    const s = st(ctx);
    s.allocator.free(s.code_points);
    s.allocator.destroy(s);
    ctx.user = null;
}

fn cpBytes(cps: []const CodePoint) u64 {
    return @as(u64, cps.len) * @sizeOf(CodePoint);
}

// ============================================================================
// Group 1: buildKey — NFD + CE expansion into primary / secondary / tertiary arrays
// ============================================================================

fn caseBuildKey(ctx: *Context) !RunResult {
    const s = st(ctx);
    var key: col.Key = .{};
    defer key.deinit(ctx.allocator);
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        try s.collator.buildKey(ctx.allocator, s.code_points, &key);
        key.clearRetainingCapacity();
    }
    std.mem.doNotOptimizeAway(key.primary.capacity);
    return .{ .bytes_processed = cpBytes(s.code_points) * inner, .ops = @as(u64, s.code_points.len) * inner };
}

// ============================================================================
// Group 2: serializeAlloc — buildKey + serialize to owned bytes
// ============================================================================

fn caseSerializeAlloc(ctx: *Context) !RunResult {
    const s = st(ctx);
    var sum: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        var key: col.Key = .{};
        defer key.deinit(ctx.allocator);
        try s.collator.buildKey(ctx.allocator, s.code_points, &key);
        const bytes = try key.serializeAlloc(ctx.allocator, s.collator.options);
        defer ctx.allocator.free(bytes);
        sum +%= bytes.len;
    }
    std.mem.doNotOptimizeAway(sum);
    return .{ .bytes_processed = cpBytes(s.code_points) * inner, .ops = @as(u64, inner) };
}

// ============================================================================
// Group 3: compareCodePoints — end-to-end comparison of two half-corpus slices
// ============================================================================

fn caseCompareCodePoints(ctx: *Context) !RunResult {
    const s = st(ctx);
    const half = s.code_points.len / 2;
    const a = s.code_points[0..half];
    const b = s.code_points[half .. half * 2];
    var accum: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        const order = try s.collator.compareCodePoints(ctx.allocator, a, b);
        accum +%= @intFromEnum(order);
    }
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = cpBytes(s.code_points) * inner, .ops = @as(u64, inner) };
}

// ============================================================================
// Group 4: compareSerial — memcmp on pre-built serialized sort keys
// (no allocation; measures the comparison cost in isolation)
// ============================================================================

const SerialState = struct {
    base: State,
    serial_a: []u8,
    serial_b: []u8,
};

fn sst(ctx: *Context) *SerialState {
    return @ptrCast(@alignCast(ctx.user.?));
}

fn setupSerial(ctx: *Context) anyerror!void {
    const heap = std.heap.page_allocator;
    const cps32 = try ts.utf8ToUtf32(heap, ctx.corpus.bytes);
    defer heap.free(cps32);
    const cp21 = try heap.alloc(CodePoint, cps32.len);
    for (cps32, 0..) |u, i| cp21[i] = @intCast(u);
    errdefer heap.free(cp21);

    const collator = col.Collator.init(.{});
    const half = cp21.len / 2;

    var key_a: col.Key = .{};
    defer key_a.deinit(heap);
    var key_b: col.Key = .{};
    defer key_b.deinit(heap);

    try collator.buildKey(heap, cp21[0..half], &key_a);
    try collator.buildKey(heap, cp21[half .. half * 2], &key_b);

    const sa = try key_a.serializeAlloc(heap, collator.options);
    errdefer heap.free(sa);
    const sb = try key_b.serializeAlloc(heap, collator.options);
    errdefer heap.free(sb);

    const s = try heap.create(SerialState);
    s.* = .{
        .base = .{ .allocator = heap, .code_points = cp21, .collator = collator },
        .serial_a = sa,
        .serial_b = sb,
    };
    ctx.user = s;
}

fn teardownSerial(ctx: *Context) anyerror!void {
    const s = sst(ctx);
    s.base.allocator.free(s.base.code_points);
    s.base.allocator.free(s.serial_a);
    s.base.allocator.free(s.serial_b);
    s.base.allocator.destroy(s);
    ctx.user = null;
}

fn caseCompareSerial(ctx: *Context) !RunResult {
    const s = sst(ctx);
    var accum: u64 = 0;
    var n: u32 = 0;
    while (n < inner_serial) : (n += 1) {
        const order = col.compareSerializedKeys(s.serial_a, s.serial_b);
        accum +%= @intFromEnum(order);
    }
    std.mem.doNotOptimizeAway(accum);
    // bytes_processed: total bytes compared across both keys × iterations
    const compared: u64 = (@as(u64, s.serial_a.len) + s.serial_b.len) * inner_serial;
    return .{ .bytes_processed = compared, .ops = @as(u64, inner_serial) };
}

pub const suite: framework.Suite = .{
    .module_name = "collation",
    .description = "UCA / DUCET sort key construction, serialization, and comparison.",
    .cases = &.{
        .{
            .name = "buildKey()",
            .notes = "NFD normalization + DUCET CE expansion → key arrays",
            .setup = setup,
            .teardown = teardown,
            .run = caseBuildKey,
        },
        .{
            .name = "serializeAlloc()",
            .notes = "buildKey() + serialize to owned byte slice",
            .setup = setup,
            .teardown = teardown,
            .run = caseSerializeAlloc,
        },
        .{
            .name = "compareCodePoints()",
            .notes = "end-to-end: build both keys, compare (corpus first half vs second half)",
            .setup = setup,
            .teardown = teardown,
            .run = caseCompareCodePoints,
        },
        .{
            .name = "compareSerial()",
            .notes = "allocation-free memcmp on pre-built serialized sort keys",
            .setup = setupSerial,
            .teardown = teardownSerial,
            .run = caseCompareSerial,
        },
    },
};
