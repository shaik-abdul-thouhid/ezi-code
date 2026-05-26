//! Benchmarks for `utils/slices` — byte ↔ u16 / u32 conversions, both endians.

const std = @import("std");
const framework = @import("../framework.zig");
const ezi = @import("ezi_code");
const slices = ezi.slices;

const Context = framework.Context;
const RunResult = framework.RunResult;

const inner: u32 = 12;

const State = struct {
    allocator: std.mem.Allocator,
    /// Power-of-two-aligned bytes — guarantees clean splits into u16/u32.
    bytes: []u8,
    /// Scratch buffers for the various conversion targets.
    u16_buf: []u16,
    u32_buf: []u32,
    u8_buf: []u8,
};

fn state(ctx: *Context) *State {
    return @ptrCast(@alignCast(ctx.user.?));
}

fn setup(ctx: *Context) anyerror!void {
    const heap = std.heap.page_allocator;
    // Pad to multiple of 4 so u32 reads cover the whole buffer.
    const src = ctx.corpus.bytes;
    const len = src.len & ~@as(usize, 3);
    const bytes = try heap.alloc(u8, len);
    @memcpy(bytes, src[0..len]);

    const u16_buf = try heap.alloc(u16, len / 2);
    const u32_buf = try heap.alloc(u32, len / 4);
    const u8_buf = try heap.alloc(u8, len);

    const st = try heap.create(State);
    st.* = .{
        .allocator = heap,
        .bytes = bytes,
        .u16_buf = u16_buf,
        .u32_buf = u32_buf,
        .u8_buf = u8_buf,
    };
    ctx.user = st;
}

fn teardown(ctx: *Context) anyerror!void {
    const st = state(ctx);
    st.allocator.free(st.bytes);
    st.allocator.free(st.u16_buf);
    st.allocator.free(st.u32_buf);
    st.allocator.free(st.u8_buf);
    st.allocator.destroy(st);
    ctx.user = null;
}

fn caseBytesToU16LE(ctx: *Context) !RunResult {
    const st = state(ctx);
    var written: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        written += try slices.bytesToU16SliceBuffer(st.bytes, st.u16_buf, .little, null);
    }
    return .{ .bytes_processed = @as(u64, st.bytes.len) * inner, .ops = written };
}

fn caseBytesToU16BE(ctx: *Context) !RunResult {
    const st = state(ctx);
    var written: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        written += try slices.bytesToU16SliceBuffer(st.bytes, st.u16_buf, .big, null);
    }
    return .{ .bytes_processed = @as(u64, st.bytes.len) * inner, .ops = written };
}

fn caseBytesToU32LE(ctx: *Context) !RunResult {
    const st = state(ctx);
    var written: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        written += try slices.bytesToU32SliceBuffer(st.bytes, st.u32_buf, .little, null);
    }
    return .{ .bytes_processed = @as(u64, st.bytes.len) * inner, .ops = written };
}

fn caseBytesToU32BE(ctx: *Context) !RunResult {
    const st = state(ctx);
    var written: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        written += try slices.bytesToU32SliceBuffer(st.bytes, st.u32_buf, .big, null);
    }
    return .{ .bytes_processed = @as(u64, st.bytes.len) * inner, .ops = written };
}

fn caseU16ToBytesLE(ctx: *Context) !RunResult {
    const st = state(ctx);
    // Prime u16_buf with bytes interpreted as little-endian u16s.
    _ = try slices.bytesToU16SliceBuffer(st.bytes, st.u16_buf, .little, null);
    var written: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        written += try slices.u16SliceToBytesBuffer(st.u16_buf, st.u8_buf, .little);
    }
    return .{ .bytes_processed = @as(u64, st.u16_buf.len) * 2 * inner, .ops = written };
}

fn caseU32ToBytesLE(ctx: *Context) !RunResult {
    const st = state(ctx);
    _ = try slices.bytesToU32SliceBuffer(st.bytes, st.u32_buf, .little, null);
    var written: u64 = 0;
    var n: u32 = 0;
    while (n < inner) : (n += 1) {
        written += try slices.u32SliceToBytesBuffer(st.u32_buf, st.u8_buf, .little);
    }
    return .{ .bytes_processed = @as(u64, st.u32_buf.len) * 4 * inner, .ops = written };
}

pub const suite: framework.Suite = .{
    .module_name = "utils/slices",
    .description = "Endianness-aware byte ↔ u16/u32 buffer conversions used by encoding/transcoding hot paths.",
    .cases = &.{
        .{ .name = "bytesToU16SliceBuffer (little)", .run = caseBytesToU16LE, .setup = setup, .teardown = teardown },
        .{ .name = "bytesToU16SliceBuffer (big)", .run = caseBytesToU16BE, .setup = setup, .teardown = teardown },
        .{ .name = "bytesToU32SliceBuffer (little)", .run = caseBytesToU32LE, .setup = setup, .teardown = teardown },
        .{ .name = "bytesToU32SliceBuffer (big)", .run = caseBytesToU32BE, .setup = setup, .teardown = teardown },
        .{ .name = "u16SliceToBytesBuffer (little)", .run = caseU16ToBytesLE, .setup = setup, .teardown = teardown },
        .{ .name = "u32SliceToBytesBuffer (little)", .run = caseU32ToBytesLE, .setup = setup, .teardown = teardown },
    },
};
