//! Benchmarks for `unicode/properties` — predicate lookups over a code-point array.

const std = @import("std");
const framework = @import("../framework.zig");
const ezi = @import("ezi_code");
const ts = ezi.transcoding;
const properties = ezi.unicode.properties;

const Case = framework.Case;
const Context = framework.Context;
const RunResult = framework.RunResult;

const CodePoint = u21;
const inner: u32 = 8;

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
    // u32 → u21; valid because corpus contains real code points.
    const out: []CodePoint = @as([*]CodePoint, @ptrCast(cps.ptr))[0..cps.len];
    _ = out;
    // Allocate a fresh u21 slice; downcasting u32→u21 in place is unsafe (sizes differ).
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

fn runPredicate(ctx: *Context, predicate: *const fn (CodePoint) bool) !RunResult {
    const cps = state(ctx).code_points;
    var truthy: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (cps) |cp| {
            if (predicate(cp)) truthy += 1;
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(truthy);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

fn caseIsLetter(ctx: *Context) !RunResult {
    return runPredicate(ctx, properties.isLetter);
}
fn caseIsAlphabetic(ctx: *Context) !RunResult {
    return runPredicate(ctx, properties.isAlphabetic);
}
fn caseIsUpperCase(ctx: *Context) !RunResult {
    return runPredicate(ctx, properties.isUpperCase);
}
fn caseIsLowerCase(ctx: *Context) !RunResult {
    return runPredicate(ctx, properties.isLowerCase);
}
fn caseIsNumeric(ctx: *Context) !RunResult {
    return runPredicate(ctx, properties.isNumeric);
}
fn caseIsWhitespace(ctx: *Context) !RunResult {
    return runPredicate(ctx, properties.isWhitespace);
}
fn caseIsPrintable(ctx: *Context) !RunResult {
    return runPredicate(ctx, properties.isPrintable);
}
fn caseIsHexDigit(ctx: *Context) !RunResult {
    return runPredicate(ctx, properties.isHexDigit);
}
fn caseIsIdStart(ctx: *Context) !RunResult {
    return runPredicate(ctx, properties.isIdStart);
}
fn caseIsIdContinue(ctx: *Context) !RunResult {
    return runPredicate(ctx, properties.isIdContinue);
}
fn caseIsAscii(ctx: *Context) !RunResult {
    return runPredicate(ctx, properties.isAscii);
}
fn caseIsPunctuation(ctx: *Context) !RunResult {
    return runPredicate(ctx, properties.isPunctuation);
}
fn caseIsSymbol(ctx: *Context) !RunResult {
    return runPredicate(ctx, properties.isSymbol);
}
fn caseIsMark(ctx: *Context) !RunResult {
    return runPredicate(ctx, properties.isMark);
}
fn caseIsEmoji(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    var truthy: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (cps) |cp| {
            if (ezi.unicode.segmentation.isEmoji(cp)) truthy += 1;
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(truthy);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

fn caseGeneralCategory(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    var accum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (cps) |cp| {
            accum +%= @intFromEnum(properties.generalCategory(cp));
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

fn caseBidiClass(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    var accum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (cps) |cp| {
            accum +%= @intFromEnum(properties.bidiClass(cp));
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

fn caseCanonicalCombiningClass(ctx: *Context) !RunResult {
    const cps = state(ctx).code_points;
    var accum: u64 = 0;
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        for (cps) |cp| {
            accum +%= @intFromEnum(properties.canonicalCombiningClass(cp));
            ops += 1;
        }
    }
    std.mem.doNotOptimizeAway(accum);
    return .{ .bytes_processed = cpBytes(cps) * inner, .ops = ops };
}

pub const suite: framework.Suite = .{
    .module_name = "unicode/properties",
    .description = "Property predicates and table lookups over a pre-decoded code-point array.",
    .cases = &.{
        .{ .name = "generalCategory()", .run = caseGeneralCategory, .setup = setup, .teardown = teardown },
        .{ .name = "bidiClass()", .run = caseBidiClass, .setup = setup, .teardown = teardown },
        .{ .name = "canonicalCombiningClass()", .run = caseCanonicalCombiningClass, .setup = setup, .teardown = teardown },
        .{ .name = "isLetter()", .run = caseIsLetter, .setup = setup, .teardown = teardown },
        .{ .name = "isAlphabetic()", .run = caseIsAlphabetic, .setup = setup, .teardown = teardown },
        .{ .name = "isUpperCase()", .run = caseIsUpperCase, .setup = setup, .teardown = teardown },
        .{ .name = "isLowerCase()", .run = caseIsLowerCase, .setup = setup, .teardown = teardown },
        .{ .name = "isNumeric()", .run = caseIsNumeric, .setup = setup, .teardown = teardown },
        .{ .name = "isWhitespace()", .run = caseIsWhitespace, .setup = setup, .teardown = teardown },
        .{ .name = "isPrintable()", .run = caseIsPrintable, .setup = setup, .teardown = teardown },
        .{ .name = "isHexDigit()", .run = caseIsHexDigit, .setup = setup, .teardown = teardown },
        .{ .name = "isIdStart()", .run = caseIsIdStart, .setup = setup, .teardown = teardown },
        .{ .name = "isIdContinue()", .run = caseIsIdContinue, .setup = setup, .teardown = teardown },
        .{ .name = "isAscii()", .run = caseIsAscii, .setup = setup, .teardown = teardown },
        .{ .name = "isPunctuation()", .run = caseIsPunctuation, .setup = setup, .teardown = teardown },
        .{ .name = "isSymbol()", .run = caseIsSymbol, .setup = setup, .teardown = teardown },
        .{ .name = "isMark()", .run = caseIsMark, .setup = setup, .teardown = teardown },
        .{ .name = "isEmoji()", .run = caseIsEmoji, .setup = setup, .teardown = teardown },
    },
};
