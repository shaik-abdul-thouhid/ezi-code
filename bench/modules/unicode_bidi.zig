//! Benchmarks for `unicode/bidi` — the Bidi_Mirroring_Glyph and
//! Bidi_Paired_Bracket / Bidi_Paired_Bracket_Type property lookups (UAX #9).

const std = @import("std");
const framework = @import("../framework.zig");
const ezi = @import("ezi_code");
const ts = ezi.transcoding;
const bidi = ezi.unicode.bidi;

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

fn caseMirroringGlyph(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    var accum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (cps) |cp| {
            accum +%= bidi.bidiMirroringGlyph(cp) orelse 0;
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

fn casePairedBracketType(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    var accum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (cps) |cp| {
            accum +%= @intFromEnum(bidi.bidiPairedBracketType(cp));
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

fn casePairedBracket(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    var accum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (cps) |cp| {
            accum +%= bidi.bidiPairedBracket(cp) orelse 0;
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

// The reordering pipeline (resolve levels + L2) over a bounded prefix of the
// corpus. We cap the working set so the O(n) scratch allocations stay modest
// regardless of the configured corpus size.
const bidi_work_cap: usize = 1 << 18; // ~256K scalars

fn caseResolveParagraph(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    const slice = cps[0..@min(cps.len, bidi_work_cap)];
    var p = try bidi.resolveParagraph(ctx.allocator, slice, .auto);
    defer p.deinit();
    var accum: u64 = 0;
    for (p.levels) |lv| accum +%= lv;
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = cpBytes(slice), .ops = @intCast(slice.len) };
}

fn caseReorderVisual(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    const slice = cps[0..@min(cps.len, bidi_work_cap)];
    var p = try bidi.resolveParagraph(ctx.allocator, slice, .auto);
    defer p.deinit();
    const order = try bidi.reorderVisual(ctx.allocator, p.levels);
    defer ctx.allocator.free(order);
    var accum: u64 = 0;
    for (order) |o| accum +%= o;
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = cpBytes(slice), .ops = @intCast(slice.len) };
}

pub const suite: framework.Suite = .{
    .module_name = "unicode/bidi",
    .description = "Property lookups plus the full UAX #9 pipeline (resolve levels + L2 reorder).",
    .cases = &.{
        .{ .name = "bidiMirroringGlyph()", .run = caseMirroringGlyph, .setup = setup, .teardown = teardown },
        .{ .name = "bidiPairedBracketType()", .run = casePairedBracketType, .setup = setup, .teardown = teardown },
        .{ .name = "bidiPairedBracket()", .run = casePairedBracket, .setup = setup, .teardown = teardown },
        .{ .name = "resolveParagraph()", .run = caseResolveParagraph, .setup = setup, .teardown = teardown },
        .{ .name = "reorderVisual()", .run = caseReorderVisual, .setup = setup, .teardown = teardown },
    },
};
