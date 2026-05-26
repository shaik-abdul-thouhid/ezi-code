//! Benchmarks for `transcoding` — all six pairs plus lossy variants.

const std = @import("std");
const framework = @import("../framework.zig");
const ezi = @import("ezi_code");
const ts = ezi.transcoding;

const Case = framework.Case;
const Context = framework.Context;
const RunResult = framework.RunResult;

const inner_buf: u32 = 3;
const inner_alloc: u32 = 2;

const State = struct {
    allocator: std.mem.Allocator,
    /// UTF-8 bytes (== ctx.corpus.bytes; held just for convenience).
    u8s: []const u8,
    /// Same content, encoded as u16.
    u16s: []u16,
    /// Same content, encoded as u32.
    u32s: []u32,
    /// Scratch buffers sized for the worst-case output of each conversion.
    u8_scratch: []u8,
    u16_scratch: []u16,
    u32_scratch: []u32,
};

fn state(ctx: *Context) *State {
    return @ptrCast(@alignCast(ctx.user.?));
}

fn setup(ctx: *Context) anyerror!void {
    const heap = std.heap.page_allocator;
    const u16s = try ts.utf8ToUtf16(heap, ctx.corpus.bytes);
    errdefer heap.free(u16s);
    const u32s = try ts.utf8ToUtf32(heap, ctx.corpus.bytes);
    errdefer heap.free(u32s);

    // Worst case for buffer output:
    //   u16→u8: each scalar can grow from 1 unit to 4 bytes -> ×4
    //   u32→u8: same -> ×4 bytes per u32 unit
    //   u8→u16: ASCII expands 1B → 1 u16 (2B), supplementary stays 4B → 2 u16 (4B); ×2
    //   u8→u32: ASCII 1B → 4B, supplementary 4B → 4B; ×4
    const u8_scratch = try heap.alloc(u8, ctx.corpus.bytes.len + 4);
    errdefer heap.free(u8_scratch);
    const u16_scratch = try heap.alloc(u16, ctx.corpus.bytes.len + 4);
    errdefer heap.free(u16_scratch);
    const u32_scratch = try heap.alloc(u32, ctx.corpus.bytes.len + 4);
    errdefer heap.free(u32_scratch);

    const st = try heap.create(State);
    st.* = .{
        .allocator = heap,
        .u8s = ctx.corpus.bytes,
        .u16s = u16s,
        .u32s = u32s,
        .u8_scratch = u8_scratch,
        .u16_scratch = u16_scratch,
        .u32_scratch = u32_scratch,
    };
    ctx.user = st;
}

fn teardown(ctx: *Context) anyerror!void {
    const st = state(ctx);
    st.allocator.free(st.u16s);
    st.allocator.free(st.u32s);
    st.allocator.free(st.u8_scratch);
    st.allocator.free(st.u16_scratch);
    st.allocator.free(st.u32_scratch);
    st.allocator.destroy(st);
    ctx.user = null;
}

fn caseUtf8ToUtf16Buffer(ctx: *Context) !RunResult {
    const st = state(ctx);
    var total: u64 = 0;
    var n: u32 = 0;
    while (n < inner_buf) : (n += 1) {
        const w = try ts.utf8ToUtf16Buffer(st.u8s, st.u16_scratch);
        total += w;
    }
    return .{ .bytes_processed = @as(u64, st.u8s.len) * inner_buf, .ops = total };
}

fn caseUtf8ToUtf32Buffer(ctx: *Context) !RunResult {
    const st = state(ctx);
    var total: u64 = 0;
    var n: u32 = 0;
    while (n < inner_buf) : (n += 1) {
        const w = try ts.utf8ToUtf32Buffer(st.u8s, st.u32_scratch);
        total += w;
    }
    return .{ .bytes_processed = @as(u64, st.u8s.len) * inner_buf, .ops = total };
}

fn caseUtf16ToUtf8Buffer(ctx: *Context) !RunResult {
    const st = state(ctx);
    var total: u64 = 0;
    var n: u32 = 0;
    while (n < inner_buf) : (n += 1) {
        const w = try ts.utf16ToUtf8Buffer(st.u16s, st.u8_scratch);
        total += w;
    }
    return .{ .bytes_processed = @as(u64, st.u16s.len) * 2 * inner_buf, .ops = total };
}

fn caseUtf16ToUtf32Buffer(ctx: *Context) !RunResult {
    const st = state(ctx);
    var total: u64 = 0;
    var n: u32 = 0;
    while (n < inner_buf) : (n += 1) {
        const w = try ts.utf16ToUtf32Buffer(st.u16s, st.u32_scratch);
        total += w;
    }
    return .{ .bytes_processed = @as(u64, st.u16s.len) * 2 * inner_buf, .ops = total };
}

fn caseUtf32ToUtf8Buffer(ctx: *Context) !RunResult {
    const st = state(ctx);
    var total: u64 = 0;
    var n: u32 = 0;
    while (n < inner_buf) : (n += 1) {
        const w = try ts.utf32ToUtf8Buffer(st.u32s, st.u8_scratch);
        total += w;
    }
    return .{ .bytes_processed = @as(u64, st.u32s.len) * 4 * inner_buf, .ops = total };
}

fn caseUtf32ToUtf16Buffer(ctx: *Context) !RunResult {
    const st = state(ctx);
    var total: u64 = 0;
    var n: u32 = 0;
    while (n < inner_buf) : (n += 1) {
        const w = try ts.utf32ToUtf16Buffer(st.u32s, st.u16_scratch);
        total += w;
    }
    return .{ .bytes_processed = @as(u64, st.u32s.len) * 4 * inner_buf, .ops = total };
}

fn caseUtf8ToUtf16Alloc(ctx: *Context) !RunResult {
    const st = state(ctx);
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_alloc) : (n += 1) {
        const out = try ts.utf8ToUtf16(ctx.allocator, st.u8s);
        ops += out.len;
        ctx.allocator.free(out);
    }
    return .{ .bytes_processed = @as(u64, st.u8s.len) * inner_alloc, .ops = ops };
}

fn caseUtf8ToUtf32Alloc(ctx: *Context) !RunResult {
    const st = state(ctx);
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_alloc) : (n += 1) {
        const out = try ts.utf8ToUtf32(ctx.allocator, st.u8s);
        ops += out.len;
        ctx.allocator.free(out);
    }
    return .{ .bytes_processed = @as(u64, st.u8s.len) * inner_alloc, .ops = ops };
}

fn caseUtf16ToUtf8Alloc(ctx: *Context) !RunResult {
    const st = state(ctx);
    var ops: u64 = 0;
    var n: u32 = 0;
    while (n < inner_alloc) : (n += 1) {
        const out = try ts.utf16ToUtf8(ctx.allocator, st.u16s);
        ops += out.len;
        ctx.allocator.free(out);
    }
    return .{ .bytes_processed = @as(u64, st.u16s.len) * 2 * inner_alloc, .ops = ops };
}

fn caseUtf8ToUtf16LossyBuffer(ctx: *Context) !RunResult {
    const st = state(ctx);
    var total: u64 = 0;
    var n: u32 = 0;
    while (n < inner_buf) : (n += 1) {
        const w = try ts.utf8ToUtf16LossyBuffer(st.u8s, st.u16_scratch);
        total += w;
    }
    return .{ .bytes_processed = @as(u64, st.u8s.len) * inner_buf, .ops = total };
}

fn caseUtf16ToUtf8LossyBuffer(ctx: *Context) !RunResult {
    const st = state(ctx);
    var total: u64 = 0;
    var n: u32 = 0;
    while (n < inner_buf) : (n += 1) {
        const w = try ts.utf16ToUtf8LossyBuffer(st.u16s, st.u8_scratch);
        total += w;
    }
    return .{ .bytes_processed = @as(u64, st.u16s.len) * 2 * inner_buf, .ops = total };
}

pub const suite: framework.Suite = .{
    .module_name = "transcoding",
    .description = "All UTF-N to UTF-M conversions, buffer (zero-alloc) and allocator paths.",
    .cases = &.{
        .{ .name = "utf8ToUtf16Buffer (in-place)", .run = caseUtf8ToUtf16Buffer, .setup = setup, .teardown = teardown },
        .{ .name = "utf8ToUtf32Buffer (in-place)", .run = caseUtf8ToUtf32Buffer, .setup = setup, .teardown = teardown },
        .{ .name = "utf16ToUtf8Buffer (in-place)", .run = caseUtf16ToUtf8Buffer, .setup = setup, .teardown = teardown },
        .{ .name = "utf16ToUtf32Buffer (in-place)", .run = caseUtf16ToUtf32Buffer, .setup = setup, .teardown = teardown },
        .{ .name = "utf32ToUtf8Buffer (in-place)", .run = caseUtf32ToUtf8Buffer, .setup = setup, .teardown = teardown },
        .{ .name = "utf32ToUtf16Buffer (in-place)", .run = caseUtf32ToUtf16Buffer, .setup = setup, .teardown = teardown },
        .{ .name = "utf8ToUtf16 (alloc + free)", .run = caseUtf8ToUtf16Alloc, .setup = setup, .teardown = teardown },
        .{ .name = "utf8ToUtf32 (alloc + free)", .run = caseUtf8ToUtf32Alloc, .setup = setup, .teardown = teardown },
        .{ .name = "utf16ToUtf8 (alloc + free)", .run = caseUtf16ToUtf8Alloc, .setup = setup, .teardown = teardown },
        .{ .name = "utf8ToUtf16LossyBuffer (in-place)", .run = caseUtf8ToUtf16LossyBuffer, .setup = setup, .teardown = teardown },
        .{ .name = "utf16ToUtf8LossyBuffer (in-place)", .run = caseUtf16ToUtf8LossyBuffer, .setup = setup, .teardown = teardown },
    },
};
