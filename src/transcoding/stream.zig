//! Incremental, allocation-light UTF-8 stream decoder for data that arrives in
//! discrete `[]const u8` chunks (e.g. socket reads or file segments). Pushed
//! slices are referenced, not owned, and code points are decoded one at a time
//! across chunk boundaries, transparently stitching scalars that are split
//! between two buffers.
//!
//! - Use `nextCodePoint` for strict decoding: invalid sequences surface as
//!   errors and the stream state is rolled back so the caller may retry.
//! - Use `nextCodePointLossy` to substitute the replacement code point for
//!   invalid bytes instead of erroring.
//! - When a scalar is split across chunks and no further chunk is available,
//!   the decoders return `error.NeedMoreBytes`; call `finish` once no more
//!   input will arrive so a trailing partial sequence is reported instead.

const std = @import("std");

const encoding = @import("encoding");
const utf8 = encoding.utf8;

const UTF8Stream = struct {
    /// Buffer for storing the slice reference.
    /// The underlying slices are not owned by the stream
    buffers: ?[][]const u8 = null,
    /// Inclusive index pointing to the next buffer to read from
    current_buffer_index: ?usize = null,
    buffers_filled: usize = 0,
    /// Inclusive index pointing to the next buffer to read from
    current_byte_index: usize = 0,
    /// Buffer holds the possible partial bytes, but the byte index is not progressed.
    partial_buffer: [4]u8 = @splat(0),
    /// The length is exclusive and points to `last_index + 1`
    partial_buffer_len: u3 = 0,
    /// Reduce the checks for code point length.
    cached_partial_expected_len: u3 = 0,
    eof: bool = false,

    /// Free the stream's internal buffer-reference array and destroy the
    /// stream itself. The pushed slices are not owned and are left untouched;
    /// `allocator` must be the same one passed to `initUTF8Stream`.
    ///
    /// @stable-since: v0.1.0
    pub fn deinit(self: *UTF8Stream, allocator: std.mem.Allocator) void {
        if (self.buffers) |buffers| allocator.free(buffers);

        allocator.destroy(self);
    }

    /// Mark the stream as end-of-input. After this call the decoders no longer
    /// return `error.NeedMoreBytes`; a trailing partial sequence is instead
    /// reported as `error.EOFReached` (strict) or as a replacement code point
    /// (lossy). Call once when no more chunks will be pushed.
    ///
    /// @stable-since: v0.1.0
    pub fn finish(self: *UTF8Stream) void {
        self.eof = true;
    }

    /// Clear all read progress and pending partial-sequence state, returning
    /// the stream to its initial empty condition for reuse. The backing
    /// buffer-reference array is retained for subsequent pushes.
    ///
    /// @stable-since: v0.1.0
    pub fn reset(self: *UTF8Stream) void {
        self.buffers_filled = 0;
        self.current_buffer_index = null;
        self.current_byte_index = 0;
        self.partial_buffer_len = 0;
        self.cached_partial_expected_len = 0;
        self.eof = false;
    }

    /// Append a chunk to the stream's read queue. `slice` is referenced, not
    /// copied, so it must stay valid until it has been fully consumed by the
    /// decoders. Grows the internal reference array as needed and may therefore
    /// return an allocator error. Empty slices are accepted and skipped on read.
    ///
    /// @stable-since: v0.1.0
    pub fn push(self: *UTF8Stream, allocator: std.mem.Allocator, slice: []const u8) !void {
        if (self.buffers) |buffers| {
            @branchHint(.likely);

            // check if there is space in buffers
            if (self.buffers_filled == buffers.len) {
                const current_len = buffers.len;

                const new_len =
                    if (current_len == 0)
                        8
                    else if (current_len * 2 > 128)
                        current_len + 10
                    else
                        current_len * 2;

                const realloc = try allocator.realloc(buffers, new_len);
                self.buffers = realloc;
            }

            self.buffers.?[self.buffers_filled] = slice;

            self.buffers_filled += 1;
            return;
        }

        // If buffers is null, we allocate and fill the first buffer
        const new_buffer = try allocator.alloc([]const u8, 2);
        errdefer allocator.free(new_buffer);
        self.current_buffer_index = 0;
        new_buffer[self.current_buffer_index.?] = slice;
        self.buffers = new_buffer;
        self.buffers_filled = 1;
    }

    /// Strictly decode the next code point, transparently stitching scalars
    /// that span chunk boundaries. Returns `null` once the stream is fully
    /// drained. If `out_buf` is non-null the raw bytes of the scalar are copied
    /// into it; pass `null` to decode without copying.
    ///
    /// Errors: `BufferTooSmall` if `out_buf` cannot hold the scalar;
    /// `NeedMoreBytes` if a scalar is split and more input may still be pushed;
    /// `EOFReached` if a trailing partial scalar remains after `finish`; plus
    /// the `UTF8ValidationError` set for malformed input. On any error the
    /// stream position is rolled back so the call can be retried. Prefer
    /// `nextCodePointLossy` when invalid bytes should be tolerated.
    ///
    /// @stable-since: v0.1.0
    pub fn nextCodePoint(self: *UTF8Stream, out_buf: ?[]u8) (error{ BufferTooSmall, NeedMoreBytes, EOFReached } || utf8.UTF8ValidationError)!?encoding.utf8.DecodedCodePoint {
        if (self.buffers == null or self.buffers_filled == 0) return null;

        const buffers = self.buffers.?;

        self.current_buffer_index = self.current_buffer_index orelse 0;

        const save_current_buffer_index = self.current_buffer_index.?;
        const save_current_byte_index = self.current_byte_index;
        const save_partial_buffer_len = self.partial_buffer_len;
        const save_partial_buf = self.partial_buffer;
        const save_cached_partial_expected_len = self.cached_partial_expected_len;

        // rollback in case of error
        errdefer {
            self.current_buffer_index = save_current_buffer_index;
            self.current_byte_index = save_current_byte_index;
            self.partial_buffer_len = save_partial_buffer_len;
            self.partial_buffer = save_partial_buf;
            self.cached_partial_expected_len = save_cached_partial_expected_len;
        }

        loop: while (self.current_buffer_index.? < self.buffers_filled) {
            const current_buffer_idx = self.current_buffer_index.?;
            const current_buffer = buffers[current_buffer_idx];

            // Empty buffer, skip it.
            if (current_buffer.len == 0) {
                self.current_buffer_index.? += 1;
                self.current_byte_index = 0;
                continue;
            }

            // Current buffer fully consumed.
            if (self.current_byte_index >= current_buffer.len) {
                self.current_buffer_index.? += 1;
                self.current_byte_index = 0;
                continue;
            }

            // Complete previously cached partial sequence.
            if (self.partial_buffer_len != 0) {
                const expected_len = self.cached_partial_expected_len;

                if (out_buf != null and out_buf.?.len < expected_len) {
                    return error.BufferTooSmall;
                }

                const next_buffer_idx = current_buffer_idx + 1;

                if (next_buffer_idx >= self.buffers_filled) {
                    if (self.eof) {
                        self.reset();
                        return error.EOFReached;
                    }

                    return error.NeedMoreBytes;
                }

                const next_buffer = buffers[next_buffer_idx];

                const bytes_needed = expected_len - self.partial_buffer_len;

                if (next_buffer.len < bytes_needed) {
                    if (next_buffer_idx == self.buffers_filled - 1) {
                        if (self.eof) {
                            self.reset();
                            return error.EOFReached;
                        }

                        return error.NeedMoreBytes;
                    }

                    @memcpy(
                        self.partial_buffer[self.partial_buffer_len .. self.partial_buffer_len + next_buffer.len],
                        next_buffer[0..next_buffer.len],
                    );

                    self.partial_buffer_len += @intCast(next_buffer.len);
                    self.current_buffer_index = next_buffer_idx;
                    self.current_byte_index = next_buffer.len;

                    continue :loop;
                }

                var src_idx: usize = 0;
                var dst_idx: usize = self.partial_buffer_len;

                while (dst_idx < expected_len) {
                    self.partial_buffer[dst_idx] = next_buffer[src_idx];
                    dst_idx += 1;
                    src_idx += 1;
                }

                const decoded = try utf8.validateAndDecodeCodePointBytes(&self.partial_buffer, 0);

                if (out_buf) |out| {
                    @memcpy(out[0..expected_len], self.partial_buffer[0..expected_len]);
                }

                self.partial_buffer_len = 0;
                self.cached_partial_expected_len = 0;

                self.current_buffer_index = next_buffer_idx;
                self.current_byte_index = src_idx;

                // Move forward if the next buffer was fully consumed.
                if (src_idx >= next_buffer.len) {
                    self.current_buffer_index.? += 1;
                    self.current_byte_index = 0;
                }

                return decoded;
            }

            const current_byte_idx = self.current_byte_index;
            const leading_byte = current_buffer[current_byte_idx];

            // ASCII fast path.
            if (encoding.isAscii(leading_byte)) {
                if (out_buf) |out| {
                    if (out.len < 1) {
                        return error.BufferTooSmall;
                    }
                    out[0] = leading_byte;
                }

                if (current_byte_idx + 1 >= current_buffer.len) {
                    self.current_buffer_index.? += 1;
                    self.current_byte_index = 0;
                } else {
                    self.current_byte_index += 1;
                }

                return .{ .len = 1, .code_point = @as(encoding.CodePoint, leading_byte) };
            }

            const expected_len = try utf8.codePointLen(leading_byte);
            const remaining_len = current_buffer.len - current_byte_idx;
            if (remaining_len < expected_len) {
                self.partial_buffer_len = @intCast(remaining_len);
                self.cached_partial_expected_len = expected_len;
                @memcpy(self.partial_buffer[0..self.partial_buffer_len], current_buffer[current_byte_idx..]);

                if (current_buffer_idx == self.buffers_filled - 1) {
                    if (self.eof) {
                        self.reset();
                        return error.EOFReached;
                    }

                    return error.NeedMoreBytes;
                } else {
                    continue :loop;
                }
            }

            const decoded = try utf8.validateAndDecodeCodePointBytes(current_buffer, current_byte_idx);
            const decoded_len = decoded.len;

            if (out_buf) |out| {
                if (out.len < decoded_len) {
                    return error.BufferTooSmall;
                }

                @memcpy(out[0..decoded_len], current_buffer[current_byte_idx .. current_byte_idx + decoded_len]);
            }

            self.current_byte_index += decoded_len;

            // Advance buffer if fully consumed.
            if (self.current_byte_index >= current_buffer.len) {
                self.current_buffer_index.? += 1;
                self.current_byte_index = 0;
            }

            return decoded;
        }

        // Stream fully consumed.
        self.buffers_filled = 0;
        self.current_buffer_index = null;
        self.current_byte_index = 0;
        self.partial_buffer_len = 0;
        self.cached_partial_expected_len = 0;

        return null;
    }

    /// Lossily decode the next code point: malformed sequences are reported as
    /// `encoding.INVALID_CODE_POINT` (with `len` covering the offending bytes)
    /// rather than raised as validation errors. Returns `null` once the stream
    /// is fully drained. If `out_buf` is non-null the raw bytes are copied into
    /// it; pass `null` to decode without copying.
    ///
    /// Errors: `BufferTooSmall` if `out_buf` cannot hold the bytes;
    /// `NeedMoreBytes` if a sequence is split and more input may still arrive.
    /// After `finish`, a trailing partial sequence is emitted as a single
    /// replacement code point instead. Prefer the strict `nextCodePoint` when
    /// invalid input should surface as an error.
    ///
    /// @stable-since: v0.1.0
    pub fn nextCodePointLossy(self: *UTF8Stream, out_buf: ?[]u8) (error{ BufferTooSmall, NeedMoreBytes, EOFReached } || utf8.UTF8ValidationLossyError)!?encoding.utf8.DecodedCodePointLossy {
        if (self.buffers == null or self.buffers_filled == 0) return null;

        const buffers = self.buffers.?;

        self.current_buffer_index = self.current_buffer_index orelse 0;

        const save_current_buffer_index = self.current_buffer_index.?;
        const save_current_byte_index = self.current_byte_index;
        const save_partial_buffer_len = self.partial_buffer_len;
        const save_partial_buf = self.partial_buffer;
        const save_cached_partial_expected_len = self.cached_partial_expected_len;

        // rollback in case of error
        errdefer {
            self.current_buffer_index = save_current_buffer_index;
            self.current_byte_index = save_current_byte_index;
            self.partial_buffer_len = save_partial_buffer_len;
            self.partial_buffer = save_partial_buf;
            self.cached_partial_expected_len = save_cached_partial_expected_len;
        }

        loop: while (self.current_buffer_index.? < self.buffers_filled) {
            const current_buffer_idx = self.current_buffer_index.?;
            const current_buffer = buffers[current_buffer_idx];

            // Empty buffer, skip it.
            if (current_buffer.len == 0) {
                self.current_buffer_index.? += 1;
                self.current_byte_index = 0;
                continue;
            }

            // Current buffer fully consumed.
            if (self.current_byte_index >= current_buffer.len) {
                self.current_buffer_index.? += 1;
                self.current_byte_index = 0;
                continue;
            }

            // Complete previously cached partial sequence.
            if (self.partial_buffer_len != 0) {
                const expected_len = self.cached_partial_expected_len;

                if (out_buf != null and out_buf.?.len < expected_len) {
                    return error.BufferTooSmall;
                }

                const next_buffer_idx = current_buffer_idx + 1;

                if (next_buffer_idx >= self.buffers_filled) {
                    if (self.eof) {
                        if (out_buf) |out| {
                            if (out.len < self.partial_buffer_len) {
                                return error.BufferTooSmall;
                            }

                            @memcpy(
                                out[0..self.partial_buffer_len],
                                self.partial_buffer[0..self.partial_buffer_len],
                            );
                        }
                        self.reset();
                        return .{ .len = self.partial_buffer_len, .code_point = encoding.INVALID_CODE_POINT };
                    }

                    return error.NeedMoreBytes;
                }

                const next_buffer = buffers[next_buffer_idx];

                const bytes_needed = expected_len - self.partial_buffer_len;

                if (next_buffer.len < bytes_needed) {
                    if (next_buffer_idx == self.buffers_filled - 1) {
                        if (self.eof) {
                            @memcpy(
                                self.partial_buffer[self.partial_buffer_len .. self.partial_buffer_len + next_buffer.len],
                                next_buffer[0..next_buffer.len],
                            );

                            self.partial_buffer_len += @intCast(next_buffer.len);

                            if (out_buf) |out| {
                                if (out.len < self.partial_buffer_len) {
                                    return error.BufferTooSmall;
                                }
                                @memcpy(
                                    out[0..self.partial_buffer_len],
                                    self.partial_buffer[0..self.partial_buffer_len],
                                );
                            }
                            self.reset();

                            return .{
                                .len = self.partial_buffer_len,
                                .code_point = encoding.INVALID_CODE_POINT,
                            };
                        }
                        return error.NeedMoreBytes;
                    }

                    @memcpy(
                        self.partial_buffer[self.partial_buffer_len .. self.partial_buffer_len + next_buffer.len],
                        next_buffer[0..next_buffer.len],
                    );

                    self.partial_buffer_len += @intCast(next_buffer.len);
                    self.current_buffer_index = next_buffer_idx;
                    self.current_byte_index = next_buffer.len;

                    continue :loop;
                }

                var src_idx: usize = 0;
                var dst_idx: usize = self.partial_buffer_len;

                while (dst_idx < expected_len) {
                    self.partial_buffer[dst_idx] = next_buffer[src_idx];
                    dst_idx += 1;
                    src_idx += 1;
                }

                const decoded = try utf8.validateAndDecodeCodePointBytesLossy(&self.partial_buffer, 0);

                if (out_buf) |out| {
                    @memcpy(out[0..expected_len], self.partial_buffer[0..expected_len]);
                }

                self.partial_buffer_len = 0;
                self.cached_partial_expected_len = 0;

                self.current_buffer_index = next_buffer_idx;
                self.current_byte_index = src_idx;

                // Move forward if the next buffer was fully consumed.
                if (src_idx >= next_buffer.len) {
                    self.current_buffer_index.? += 1;
                    self.current_byte_index = 0;
                }

                return decoded;
            }

            const current_byte_idx = self.current_byte_index;
            const leading_byte = current_buffer[current_byte_idx];

            // ASCII fast path.
            if (encoding.isAscii(leading_byte)) {
                if (out_buf) |out| {
                    if (out.len < 1) {
                        return error.BufferTooSmall;
                    }
                    out[0] = leading_byte;
                }

                if (current_byte_idx + 1 >= current_buffer.len) {
                    self.current_buffer_index.? += 1;
                    self.current_byte_index = 0;
                } else {
                    self.current_byte_index += 1;
                }

                return .{ .len = 1, .code_point = @as(encoding.CodePoint, leading_byte) };
            }

            const expected_len = utf8.codePointLenLossy(leading_byte);
            if (expected_len == 0) {
                @branchHint(.cold);

                var i: usize = 0;

                const start_buffer_idx = self.current_buffer_index.?;
                const start_byte_idx = self.current_byte_index;

                while (self.current_buffer_index.? < self.buffers_filled) {
                    if (self.current_byte_index >= buffers[self.current_buffer_index.?].len) {
                        self.current_buffer_index.? += 1;
                        self.current_byte_index = 0;
                        continue;
                    }

                    const current_byte = buffers[self.current_buffer_index.?][self.current_byte_index];

                    if (utf8.isLeaderByte(current_byte) or encoding.isAscii(current_byte)) {
                        break;
                    }

                    self.current_byte_index += 1;
                    i += 1;
                }

                const len = i;

                if (out_buf) |out| {
                    if (out.len < i) {
                        return error.BufferTooSmall;
                    }

                    i = 0;

                    for (start_buffer_idx..(self.current_buffer_index.? + 1)) |buf_idx| {
                        if (buf_idx == start_buffer_idx) {
                            const slice = buffers[buf_idx][start_byte_idx..];
                            @memcpy(out[i .. i + slice.len], slice);
                            i += slice.len;
                        } else if (buf_idx == self.current_buffer_index.?) {
                            const slice = buffers[buf_idx][0..self.current_byte_index];
                            @memcpy(out[i .. i + slice.len], slice);
                            i += slice.len;
                        } else {
                            const slice = buffers[buf_idx];
                            @memcpy(out[i .. i + slice.len], slice);
                            i += slice.len;
                        }
                    }
                }

                return .{ .len = len, .code_point = encoding.INVALID_CODE_POINT };
            }

            const remaining_len = current_buffer.len - current_byte_idx;
            if (remaining_len < expected_len) {
                self.partial_buffer_len = @intCast(remaining_len);
                self.cached_partial_expected_len = expected_len;
                @memcpy(self.partial_buffer[0..self.partial_buffer_len], current_buffer[current_byte_idx..]);

                if (current_buffer_idx == self.buffers_filled - 1) {
                    if (self.eof) {
                        if (out_buf) |out| {
                            if (out.len < self.partial_buffer_len) {
                                return error.BufferTooSmall;
                            }

                            @memcpy(
                                out[0..self.partial_buffer_len],
                                self.partial_buffer[0..self.partial_buffer_len],
                            );
                        }
                        self.reset();
                        return .{ .len = self.partial_buffer_len, .code_point = encoding.INVALID_CODE_POINT };
                    }

                    return error.NeedMoreBytes;
                } else {
                    continue :loop;
                }
            }

            const decoded = try utf8.validateAndDecodeCodePointBytesLossy(current_buffer, current_byte_idx);
            const decoded_len = decoded.len;

            if (out_buf) |out| {
                if (out.len < decoded_len) {
                    return error.BufferTooSmall;
                }

                @memcpy(out[0..decoded_len], current_buffer[current_byte_idx .. current_byte_idx + decoded_len]);
            }

            self.current_byte_index += decoded_len;

            // Advance buffer if fully consumed.
            if (self.current_byte_index >= current_buffer.len) {
                self.current_buffer_index.? += 1;
                self.current_byte_index = 0;
            }

            return decoded;
        }

        // Stream fully consumed.
        self.reset();

        return null;
    }
};

/// Configuration for `initUTF8Stream`. Currently empty; reserved for future
/// tuning knobs so call sites can pass `.{}` without later signature churn.
pub const UTF8StreamOptions = struct {};

/// Allocate and initialize a new UTF-8 stream. The returned stream is empty;
/// feed it chunks with `push` and consume code points with `nextCodePoint` /
/// `nextCodePointLossy`. Caller owns the result and must release it with
/// `deinit` using the same `allocator`.
///
/// @stable-since: v0.1.0
pub fn initUTF8Stream(allocator: std.mem.Allocator, options: UTF8StreamOptions) !*UTF8Stream {
    _ = options;

    const stream = try allocator.create(UTF8Stream);
    errdefer allocator.destroy(stream);

    stream.* = .{};

    return stream;
}

test "UTF8Stream.nextCodePoint returns null on empty stream" {
    const allocator = std.testing.allocator;
    var stream = try initUTF8Stream(allocator, .{});
    defer stream.deinit(allocator);

    const maybe_decoded = try stream.nextCodePoint(null);
    try std.testing.expect(maybe_decoded == null);
}

test "UTF8Stream.nextCodePoint skips empty buffer and decodes ascii" {
    const allocator = std.testing.allocator;
    var stream = try initUTF8Stream(allocator, .{});
    defer stream.deinit(allocator);

    const empty: []const u8 = &.{};
    try stream.push(allocator, empty);
    try stream.push(allocator, "A");

    var out: [1]u8 = undefined;
    const decoded_opt = try stream.nextCodePoint(&out);
    const decoded = decoded_opt.?;

    try std.testing.expectEqual(decoded.len, 1);
    try std.testing.expectEqual(decoded.code_point, @as(encoding.CodePoint, 'A'));
    try std.testing.expectEqualSlices(u8, out[0..1], "A");

    const maybe_decoded = try stream.nextCodePoint(null);
    try std.testing.expect(maybe_decoded == null);
}

test "UTF8Stream.nextCodePoint decodes split four-byte scalar across buffers" {
    const allocator = std.testing.allocator;
    var stream = try initUTF8Stream(allocator, .{});
    defer stream.deinit(allocator);

    const bytes: [4]u8 = .{ 0xF0, 0x9F, 0x98, 0x8A };
    try stream.push(allocator, bytes[0..2]);
    try stream.push(allocator, bytes[2..4]);

    var out: [4]u8 = undefined;
    const decoded_opt = try stream.nextCodePoint(&out);
    const decoded = decoded_opt.?;

    try std.testing.expectEqual(decoded.len, 4);
    try std.testing.expectEqual(decoded.code_point, @as(encoding.CodePoint, 0x1F60A));
    try std.testing.expectEqualSlices(u8, out[0..4], bytes[0..4]);

    const maybe_decoded = try stream.nextCodePoint(null);
    try std.testing.expect(maybe_decoded == null);
}

test "UTF8Stream.nextCodePoint preserves state when output buffer is too small" {
    const allocator = std.testing.allocator;
    var stream = try initUTF8Stream(allocator, .{});
    defer stream.deinit(allocator);

    const bytes: [3]u8 = .{ 0xE2, 0x82, 0xAC };
    try stream.push(allocator, bytes[0..3]);

    var out_small: [2]u8 = undefined;
    try std.testing.expectError(error.BufferTooSmall, stream.nextCodePoint(&out_small));

    var out_full: [3]u8 = undefined;
    const decoded_opt = try stream.nextCodePoint(&out_full);
    const decoded = decoded_opt.?;
    try std.testing.expectEqual(decoded.len, 3);
    try std.testing.expectEqual(decoded.code_point, @as(encoding.CodePoint, 0x20AC));
    try std.testing.expectEqualSlices(u8, out_full[0..3], bytes[0..3]);
}

test "UTF8Stream.nextCodePoint returns NeedMoreBytes for partial scalar split across buffers" {
    const allocator = std.testing.allocator;
    var stream = try initUTF8Stream(allocator, .{});
    defer stream.deinit(allocator);

    const bytes: [4]u8 = .{ 0xF0, 0x9F, 0x98, 0x82 };
    try stream.push(allocator, bytes[0..2]);

    var out: [4]u8 = undefined;
    try std.testing.expectError(error.NeedMoreBytes, stream.nextCodePoint(&out));
}

test "UTF8Stream.nextCodePointLossy decodes invalid continuation bytes across buffer boundary" {
    const allocator = std.testing.allocator;
    var stream = try initUTF8Stream(allocator, .{});
    defer stream.deinit(allocator);

    try stream.push(allocator, &.{0x80});
    try stream.push(allocator, &.{0x80});
    try stream.push(allocator, &.{ 0xC2, 0xA2 });

    var out: [2]u8 = undefined;
    const decoded_opt = try stream.nextCodePointLossy(&out);
    const decoded = decoded_opt.?;

    try std.testing.expectEqual(decoded.len, 2);
    try std.testing.expectEqual(decoded.code_point, encoding.INVALID_CODE_POINT);
    try std.testing.expectEqualSlices(u8, out[0..2], &.{ 0x80, 0x80 });
}

test "UTF8Stream.nextCodePointLossy preserves state when output buffer is too small" {
    const allocator = std.testing.allocator;
    var stream = try initUTF8Stream(allocator, .{});
    defer stream.deinit(allocator);

    const bytes: [3]u8 = .{ 0xE2, 0x82, 0xAC };
    try stream.push(allocator, bytes[0..3]);

    var out_small: [2]u8 = undefined;
    try std.testing.expectError(error.BufferTooSmall, stream.nextCodePointLossy(&out_small));

    var out_full: [3]u8 = undefined;
    const decoded_opt = try stream.nextCodePointLossy(&out_full);
    const decoded = decoded_opt.?;
    try std.testing.expectEqual(decoded.len, 3);
    try std.testing.expectEqual(decoded.code_point, @as(encoding.CodePoint, 0x20AC));
    try std.testing.expectEqualSlices(u8, out_full[0..3], bytes[0..3]);
}

test "UTF8Stream.nextCodePoint skips only empty buffers and returns null" {
    const allocator = std.testing.allocator;
    var stream = try initUTF8Stream(allocator, .{});
    defer stream.deinit(allocator);

    try stream.push(allocator, &.{});
    try stream.push(allocator, &.{});
    try stream.push(allocator, &.{});

    const maybe_decoded = try stream.nextCodePoint(null);
    try std.testing.expect(maybe_decoded == null);
}

test "UTF8Stream.nextCodePoint preserves state across invalid continuation bytes" {
    const allocator = std.testing.allocator;
    var stream = try initUTF8Stream(allocator, .{});
    defer stream.deinit(allocator);

    try stream.push(allocator, &.{ 0xE2, 0x28, 0xA1 });

    try std.testing.expectError(utf8.UTF8ValidationError.InvalidContinuationByte, stream.nextCodePoint(null));
    try std.testing.expectError(utf8.UTF8ValidationError.InvalidContinuationByte, stream.nextCodePoint(null));
}

test "UTF8Stream.nextCodePoint handles null output buffer on split scalar" {
    const allocator = std.testing.allocator;
    var stream = try initUTF8Stream(allocator, .{});
    defer stream.deinit(allocator);

    const bytes: [4]u8 = .{ 0xF0, 0x9F, 0x98, 0x8A };
    try stream.push(allocator, bytes[0..2]);
    try stream.push(allocator, bytes[2..4]);

    const decoded_opt = try stream.nextCodePoint(null);
    const decoded = decoded_opt.?;
    try std.testing.expectEqual(decoded.len, 4);
    try std.testing.expectEqual(decoded.code_point, @as(encoding.CodePoint, 0x1F60A));
}

test "UTF8Stream.nextCodePointLossy reports BufferTooSmall on orphaned continuation across buffers" {
    const allocator = std.testing.allocator;
    var stream = try initUTF8Stream(allocator, .{});
    defer stream.deinit(allocator);

    try stream.push(allocator, &.{0x80});
    try stream.push(allocator, &.{0x80});

    var out_small: [1]u8 = undefined;
    try std.testing.expectError(error.BufferTooSmall, stream.nextCodePointLossy(&out_small));
}

test "UTF8Stream.nextCodePoint can be reused after full drain" {
    const allocator = std.testing.allocator;
    var stream = try initUTF8Stream(allocator, .{});
    defer stream.deinit(allocator);

    try stream.push(allocator, "A");

    var out: [1]u8 = undefined;
    const first_opt = try stream.nextCodePoint(&out);
    const first = first_opt.?;
    try std.testing.expectEqual(first.code_point, @as(encoding.CodePoint, 'A'));

    const maybe_empty = try stream.nextCodePoint(null);
    try std.testing.expect(maybe_empty == null);

    try stream.push(allocator, "B");
    const second_opt = try stream.nextCodePoint(&out);
    const second = second_opt.?;
    try std.testing.expectEqual(second.code_point, @as(encoding.CodePoint, 'B'));
}

test "UTF8Stream push grows internal buffer and preserves read order" {
    const allocator = std.testing.allocator;
    var stream = try initUTF8Stream(allocator, .{});
    defer stream.deinit(allocator);

    const slices: [20][]const u8 = .{
        "a", "b", "c", "d", "e", "f", "g", "h", "i", "j",
        "k", "l", "m", "n", "o", "p", "q", "r", "s", "t",
    };

    for (slices) |slice| {
        try stream.push(allocator, slice);
    }

    try std.testing.expectEqual(stream.buffers_filled, @as(usize, 20));

    var out_buf: [1]u8 = undefined;
    var idx: usize = 0;
    while (true) {
        const decoded_opt = try stream.nextCodePoint(&out_buf);
        if (decoded_opt == null) break;
        const decoded = decoded_opt.?;
        try std.testing.expectEqual(decoded.len, 1);
        try std.testing.expectEqual(decoded.code_point, @as(encoding.CodePoint, slices[idx][0]));
        idx += 1;
    }
    try std.testing.expectEqual(idx, @as(usize, 20));
}

test "B1/B2 regression: stream error set is { BufferTooSmall, NeedMoreBytes, EOFReached } (no dead BufferIsEmpty)" {
    const allocator = std.testing.allocator;
    var stream = try initUTF8Stream(allocator, .{});
    defer stream.deinit(allocator);

    // A 3-byte euro sign with a 2-byte output buffer: the unified
    // BufferTooSmall is raised (formerly the layer-local OutputBufferTooSmall).
    const euro: [3]u8 = .{ 0xE2, 0x82, 0xAC };
    try stream.push(allocator, euro[0..3]);
    var out_small: [2]u8 = undefined;

    // Exhaustively switching the strict error set WITHOUT a BufferIsEmpty arm
    // only compiles because that dead variant was removed — this is the
    // compile-time proof, with a runtime check that BufferTooSmall is the path.
    if (stream.nextCodePoint(&out_small)) |_| {
        try std.testing.expect(false);
    } else |err| switch (err) {
        error.BufferTooSmall => {}, // expected
        error.NeedMoreBytes,
        error.EOFReached,
        error.OverlongEncoding,
        error.InvalidContinuationByte,
        error.InvalidByteSequence,
        error.SurrogateCodePoint,
        error.CodePointTooLarge,
        error.ZeroLengthBytes,
        error.IndexOutOfBounds,
        => try std.testing.expect(false),
    }
}
