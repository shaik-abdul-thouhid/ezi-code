//! This file contains APIs for encoding and decoding utf16 codepoints from
//! `[]const u16`. Contains functions for validating, Optimistic lengths,
//! traversal, decoding, encoding, and converting to []CodePoint slice.
//!
//! - "Optimistic length" returned by `xxxLen(...)` functions is the
//!   expected number of bytes to consume to decode a valid CodePoint.
//!   It reflects the length claimed by the lead byte; continuation bytes
//!   have not been validated yet.
//! - Lossy `xxxLen(...)` variants return 0 when the byte is invalid or
//!   the expected length cannot be inferred from it.

const std = @import("std");
const utils = @import("utils");
const encoding = @import("root.zig");

const CodePoint = encoding.CodePoint;
const INVALID_CODE_POINT = encoding.INVALID_CODE_POINT;

const MAX_ASCII = encoding.MAX_ASCII;

const encoding_range_end = 0x10FFFF;
const supplementary_offset: CodePoint = 0x10000;

pub const Endian = utils.Endian;

const surrogate_range_start: u16 = 0xD800;
const surrogate_range_end: u16 = 0xDFFF;

const surrogate_mask = 0b111111_0000000000;

const high_surrogate_range_start = 0b110110_0000000000;
const high_surrogate_range_end = 0b110110_1111111111;

const low_surrogate_range_start = 0b110111_0000000000;
const low_surrogate_range_end = 0b110111_1111111111;

const min_supplementary_code_point: CodePoint = 0x10000;
const max_supplementary_code_point: CodePoint = 0x10FFFF;

pub const DecodedCodePoint = struct {
    code_point: CodePoint,
    len: u2,
};

pub const DecodedCodePointLossy = struct {
    code_point: CodePoint,
    len: usize,
};

pub const UTF16ValidationError = error{
    ZeroLengthUnits,
    IndexOutOfBounds,
    InvalidLowSurrogate,
    InvalidHighSurrogate,
    SurrogateCodePoint,
    CodePointTooLarge,
};

pub const UTF16ValidationLossyError = error{
    ZeroLengthUnits,
    IndexOutOfBounds,
};

pub const UTF16EncodeError = error{
    CodePointTooLarge,
    BufferTooSmall,
    SurrogateCodePoint,
};

/// @stable-since: v0.1.0
pub fn isHighSurrogate(c16: u16) bool {
    return (c16 & surrogate_mask) == high_surrogate_range_start;
}

/// @stable-since: v0.1.0
pub fn isLowSurrogate(c16: u16) bool {
    return (c16 & surrogate_mask) == low_surrogate_range_start;
}

/// Returns optimistic length required by the u16 passed as argument.
/// Use `validateAndDecodeU16CodePoint` for script or `validateAndDecodeU16CodePointLossy`
/// for lossy decoding
///
/// @stable-since: v0.1.0
pub fn utf16SequenceLen(c16: u16) UTF16ValidationError!u2 {
    if (c16 <= MAX_ASCII) {
        return 1;
    }

    if (isHighSurrogate(c16)) {
        return 2;
    }

    if (isLowSurrogate(c16)) {
        return error.InvalidLowSurrogate;
    }

    return 1;
}

/// Returns optimistic length required by the u16 passed as argument,
/// returns `0` for invalid u16. Use `validateAndDecodeU16CodePoint` for script or
/// `validateAndDecodeU16CodePointLossy` for lossy decoding
///
/// @stable-since: v0.1.0
pub fn utf16SequenceLenLossy(c16: u16) u2 {
    if (c16 <= MAX_ASCII) {
        return 1;
    }

    if (isHighSurrogate(c16)) {
        return 2;
    }

    if (isLowSurrogate(c16)) {
        return 0;
    }

    return 1;
}

fn utf16SequenceLenUnchecked(c16: u16) u2 {
    if (isHighSurrogate(c16)) {
        return 2;
    }

    return 1;
}

/// Returns optimistic length required for decoding a valid CodePoint from the end_index(inclusive)
/// of the given buffer
///
/// @stable-since: v0.1.0
pub fn utf16SequenceLenReverse(buf: []const u16, end_index: usize) UTF16ValidationError!u2 {
    if (buf.len == 0) {
        return error.ZeroLengthUnits;
    } else if (buf.len <= end_index) {
        return error.IndexOutOfBounds;
    }

    if (buf[end_index] <= MAX_ASCII) {
        return 1;
    }

    const last = end_index;

    if (isLowSurrogate(buf[last])) {
        if (end_index < 1 or !isHighSurrogate(buf[end_index - 1])) {
            return error.InvalidLowSurrogate;
        }
        return 2;
    }

    if (isHighSurrogate(buf[last])) {
        return error.InvalidHighSurrogate;
    }

    return 1;
}

/// Returns the unit length of the code point ending at `end_index` (inclusive).
/// This is the unchecked variant: it never returns an error.
///
/// Contract: `end_index < buf.len` and `buf` is valid UTF-16 around
/// `end_index`. Preconditions are asserted / safety-checked (trap in
/// Debug/ReleaseSafe, undefined in ReleaseFast/ReleaseSmall), never
/// error-returned. Use the checked `utf16SequenceLenReverse` when the units'
/// validity is uncertain.
///
/// @stable-since: v0.1.0
pub fn utf16SequenceLenReverseUnchecked(buf: []const u16, end_index: usize) u2 {
    std.debug.assert(end_index < buf.len);

    if (buf[end_index] <= MAX_ASCII) {
        return 1;
    }

    if (isLowSurrogate(buf[end_index])) {
        return 2;
    }

    return 1;
}

/// Returns the length of the bytes needed to encode the CodePoint.
/// Caller is expected to make sure the code point is valid
///
/// @stable-since: v0.1.0
pub fn utf16EncodeLen(code_point: CodePoint) UTF16EncodeError!u2 {
    if (code_point < supplementary_offset) {
        return 1;
    }

    return 2;
}

/// Encodes the CodePoint to the bytes and returns the length of the bytes
/// encoded. Returns error if buffer length is less than the required length.
/// Expects valid CodePoint argument, Caller must make sure to pass a valid CodePoint
///
/// @stable-since: v0.1.0
pub fn encodeCodePoint(code_point: CodePoint, buf: []u16) UTF16EncodeError!u2 {
    const len = try utf16EncodeLen(code_point);

    if (buf.len < len) {
        return error.BufferTooSmall;
    }

    if (len == 1) {
        buf[0] = @truncate(code_point);
        return 1;
    }

    const temp = code_point - supplementary_offset;
    buf[0] = high_surrogate_range_start | @as(u16, @truncate(temp >> 10));
    buf[1] = low_surrogate_range_start | @as(u16, @truncate(temp & 0x3FF));
    return 2;
}

/// Encodes a valid `code_point` into `buf` and returns the number of code units
/// written. Neither the code point nor the buffer length is validated — the
/// caller must guarantee a valid scalar and that
/// `buf.len >= (utf16EncodeLen(code_point) catch unreachable)`. Use
/// `encodeCodePoint` when either invariant is uncertain.
///
/// Note: **a buffer shorter than the encoded length triggers `unreachable`
/// (checked illegal behavior in safe builds, UB in `ReleaseFast`).**
///
/// @stable-since: v0.2.0
pub fn encodeCodePointUnchecked(code_point: CodePoint, buf: []u16) u2 {
    return encodeCodePoint(code_point, buf) catch unreachable;
}

/// Encodes a valid `code_point` as UTF-16 and writes its code units to `writer`
/// as bytes in the given `endian` order, returning the number of code units
/// written (1 or 2; i.e. `2 * return` bytes are emitted). The code point is not
/// validated — same contract as `encodeCodePoint`. The only error returned is
/// the writer's own (`error.WriteFailed`).
///
/// @stable-since: v0.2.0
pub fn encodeCodePointWriter(code_point: CodePoint, endian: Endian, writer: *std.Io.Writer) std.Io.Writer.Error!u2 {
    var units: [2]u16 = undefined;
    const len = encodeCodePointUnchecked(code_point, &units);

    var bytes: [4]u8 = undefined;
    const byte_len = utils.slices.u16SliceToBytesBuffer(units[0..len], &bytes, endian) catch unreachable;

    try writer.writeAll(bytes[0..byte_len]);
    return len;
}

fn decode(buf: []const u16, offset: usize, len: u2) DecodedCodePoint {
    return switch (len) {
        1 => .{ .code_point = @as(CodePoint, buf[offset]), .len = 1 },
        2 => .{
            .code_point = supplementary_offset +
                (@as(CodePoint, buf[offset] - high_surrogate_range_start) << 10) |
                @as(CodePoint, buf[offset + 1] - low_surrogate_range_start),
            .len = 2,
        },
        else => unreachable,
    };
}

/// Validates the given buffer and returns the length to consume for a valid CodePoint
/// decodable u16 bytes.
///
/// @stable-since: v0.1.0
pub fn validateU16Sequence(buf: []const u16, offset: usize) UTF16ValidationError!u2 {
    if (buf.len == 0) {
        return error.ZeroLengthUnits;
    } else if (offset >= buf.len) {
        return error.IndexOutOfBounds;
    }

    if (buf[offset] <= MAX_ASCII) {
        return 1;
    }

    const len = try utf16SequenceLen(buf[offset]);

    if (buf.len - offset < @as(usize, len)) {
        return error.IndexOutOfBounds;
    } else if (len == 1) {
        return 1;
    }

    if (len == 2 and !isLowSurrogate(buf[offset + 1])) {
        return error.InvalidLowSurrogate;
    }

    return len;
}

/// Validates the given buffer and returns the length to consume for a valid CodePoint
/// decodable u16 bytes.
///
/// @stable-since: v0.1.0
pub fn validateU16CodePointReverse(buf: []const u16) UTF16ValidationError!u2 {
    if (buf.len == 0) {
        return error.ZeroLengthUnits;
    }

    if (buf[buf.len - 1] <= MAX_ASCII) {
        @branchHint(.likely);
        return 1;
    }

    const len = try utf16SequenceLenReverse(buf, buf.len - 1);

    if (len == 1) {
        return 1;
    }

    const start = buf.len - @as(usize, len);
    return try validateU16Sequence(buf, start);
}

fn validateAndDecodeU16CodePointWithLen(buf: []const u16, offset: usize, len: u2) UTF16ValidationError!DecodedCodePoint {
    if (buf.len == 0) {
        return error.ZeroLengthUnits;
    } else if (offset >= buf.len) {
        return error.IndexOutOfBounds;
    }

    if (buf.len - offset < @as(usize, len)) {
        return error.IndexOutOfBounds;
    }

    if (len == 1) {
        return .{ .code_point = @as(CodePoint, buf[offset]), .len = 1 };
    }

    if (len == 2) {
        if (!isHighSurrogate(buf[offset])) {
            return error.InvalidHighSurrogate;
        }
        if (!isLowSurrogate(buf[offset + 1])) {
            return error.InvalidLowSurrogate;
        }
    } else if (isLowSurrogate(buf[offset])) {
        return error.InvalidLowSurrogate;
    } else if (isHighSurrogate(buf[offset])) {
        return error.InvalidHighSurrogate;
    }

    const decoded = decode(buf, offset, len);
    try encoding.validateCodePoint(decoded.code_point);
    return decoded;
}

/// Validates the given buffer and returns the length and CodePoint
///
/// @stable-since: v0.1.0
pub fn validateAndDecodeU16CodePoint(buf: []const u16, offset: usize) UTF16ValidationError!DecodedCodePoint {
    const len = try validateU16Sequence(buf, offset);
    return decode(buf, offset, len);
}

/// Validates the given buffer and returns the length and CodePoint.
/// Invalid bytes are replaced with Replacement CodePoint. The consecutive
/// orphaned low surrogate bytes are crunched and replaced with
/// replacement codepoint
///
/// @stable-since: v0.1.0
pub fn validateAndDecodeU16CodePointLossy(buf: []const u16, offset: usize) UTF16ValidationLossyError!DecodedCodePointLossy {
    if (buf.len == 0) {
        return UTF16ValidationLossyError.ZeroLengthUnits;
    } else if (offset >= buf.len) {
        return UTF16ValidationLossyError.IndexOutOfBounds;
    }

    if (buf[offset] <= MAX_ASCII) {
        return .{ .code_point = @as(CodePoint, buf[offset]), .len = 1 };
    }

    const optimistic_len = utf16SequenceLenLossy(buf[offset]);
    const remaining = buf.len - offset;

    if (remaining < @as(usize, optimistic_len)) {
        // the only expected len that could cause this
        // branch is for 2 surrogate pairs
        return .{ .code_point = INVALID_CODE_POINT, .len = 1 };
    }

    if (optimistic_len == 1) {
        const code_point_offset = @as(CodePoint, buf[offset]);

        return .{ .code_point = code_point_offset, .len = 1 };
    } else if (optimistic_len == 2) {
        // the first byte is expected to be a high surrogate
        if (!isLowSurrogate(buf[offset + 1])) {
            return .{ .code_point = INVALID_CODE_POINT, .len = 1 };
        }

        const decoded = decode(buf, offset, optimistic_len);
        encoding.validateCodePoint(decoded.code_point) catch {
            return .{ .code_point = INVALID_CODE_POINT, .len = 2 };
        };

        return .{ .code_point = decoded.code_point, .len = decoded.len };
    }

    // crunch all low surrogates

    var i: usize = 0;

    loop: while (i < remaining) {
        if (!isLowSurrogate(buf[offset + i])) {
            break :loop;
        }
        i += 1;
    }

    return .{ .code_point = INVALID_CODE_POINT, .len = i };
}

/// Validates the given buffer and returns the length and CodePoint from end_index(inclusive).
///
/// @stable-since: v0.1.0
pub fn validateAndDecodeU16CodePointReverse(buf: []const u16, end_index: usize) UTF16ValidationError!DecodedCodePoint {
    const len = try utf16SequenceLenReverse(buf, end_index);

    if (len == 1) {
        return .{ .code_point = @as(CodePoint, buf[end_index]), .len = 1 };
    }

    const start = end_index + 1 - @as(usize, len);
    return decode(buf, start, len);
}

fn decodeCodePointReverse(buf: []const u16, end_index: usize) DecodedCodePoint {
    const len = utf16SequenceLenReverseUnchecked(buf, end_index);

    if (len == 1) {
        @branchHint(.likely);
        return .{ .code_point = @as(CodePoint, buf[end_index]), .len = 1 };
    }

    const start = end_index + 1 - @as(usize, len);
    return decode(buf, start, len);
}

/// Decodes the code point starting at `offset` without validating the units.
/// This is the unchecked forward-decode entry point: callers that hold
/// already-validated UTF-16 (e.g. units that passed `validate`, or the
/// backing units of a `UTF16View`) can decode without paying validation
/// again, and without wrapping the units in a `UTF16View`.
///
/// Contract: `offset < buf.len`, `offset` is a code point boundary (not the
/// low half of a surrogate pair), and `buf` is valid UTF-16 at `offset`.
/// Preconditions are asserted / safety-checked (trap in Debug/ReleaseSafe,
/// undefined in ReleaseFast/ReleaseSmall), never error-returned. Use
/// `validateAndDecodeU16CodePoint` when the units' validity is uncertain.
///
/// @stable-since: v0.4.0
pub fn decodeU16CodePointUnchecked(buf: []const u16, offset: usize) DecodedCodePoint {
    std.debug.assert(offset < buf.len);

    return decode(buf, offset, utf16SequenceLenUnchecked(buf[offset]));
}

fn decodeCodePoint(buf: []const u16, offset: usize) DecodedCodePoint {
    return decodeU16CodePointUnchecked(buf, offset);
}

pub const UTF16SliceError = error{
    IndexOutOfBounds,
    InvalidLowSurrogate,
    InvalidHighSurrogate,
};

/// Bidirectional cursor over the scalars of a `UTF16View`. Assumes the
/// underlying code units are already valid UTF-16 (as produced by
/// `initUTF16View`); decoding is unchecked. Obtain one with `UTF16View.iter`.
///
/// @stable-since: v0.2.0
pub const UTF16ViewIterator = struct {
    index: usize = 0,
    data: []const u16,
    curr: ?CodePoint = null,

    /// Advance to and return the next scalar, or `null` at the end.
    ///
    /// @stable-since: v0.2.0
    pub fn next(self: *UTF16ViewIterator) ?CodePoint {
        if (self.index >= self.data.len) {
            return null;
        }

        const code_point = decodeCodePoint(self.data, self.index);
        self.index += @as(usize, code_point.len);
        self.curr = code_point.code_point;

        return self.curr.?;
    }

    /// Return the next scalar without advancing the cursor, or `null` at the end.
    ///
    /// @stable-since: v0.2.0
    pub fn peek(self: *const UTF16ViewIterator) ?CodePoint {
        if (self.index >= self.data.len) {
            return null;
        }

        return decodeCodePoint(self.data, self.index).code_point;
    }

    /// Step back to and return the previous scalar, or `null` at the start.
    ///
    /// @stable-since: v0.2.0
    pub fn previous(self: *UTF16ViewIterator) ?CodePoint {
        if (self.index == 0) {
            return null;
        }

        const code_point = decodeCodePointReverse(self.data, self.index - 1);
        self.index -= @as(usize, code_point.len);
        self.curr = code_point.code_point;

        return self.curr.?;
    }

    /// Return the previous scalar without moving the cursor, or `null` at the start.
    ///
    /// @stable-since: v0.2.0
    pub fn peekPrevious(self: *const UTF16ViewIterator) ?CodePoint {
        if (self.index == 0) {
            return null;
        }

        return decodeCodePointReverse(self.data, self.index - 1).code_point;
    }
};

/// Zero-copy view over a `[]const u16` of validated UTF-16 code units. Provides
/// scalar counting, boundary tests, scalar-indexed sub-slicing, and a
/// bidirectional iterator (`iter`). Construct with `initUTF16View` (checked) or
/// `initUTF16ViewUnchecked`.
///
/// @stable-since: v0.2.0
pub const UTF16View = struct {
    data: []const u16,

    /// Return the number of scalars in the view by walking the code units.
    ///
    /// @stable-since: v0.2.0
    pub fn countScalar(self: *const UTF16View) usize {
        var count: usize = 0;
        var i: usize = 0;

        while (i < self.data.len) {
            const unit = self.data[i];

            const len = utf16SequenceLenUnchecked(unit);
            i += @as(usize, len);
            count += 1;
        }

        return count;
    }

    /// Report whether unit offset `index` falls on a scalar boundary (the start
    /// of a scalar, or the end of the data). Offsets on a trailing (low)
    /// surrogate return `false`.
    ///
    /// @stable-since: v0.2.0
    pub fn isBoundary(self: *const UTF16View, index: usize) bool {
        if (index > self.data.len) {
            return false;
        }

        if (index == 0 or index == self.data.len) {
            return true;
        }

        return !isLowSurrogate(self.data[index]);
    }

    /// Return a sub-view spanning scalars `[start_scalar, end_scalar)`. Errors
    /// if the range is inverted, runs past the end, or splits a surrogate pair.
    ///
    /// @stable-since: v0.2.0
    pub fn sliceScalars(self: *const UTF16View, start_scalar: usize, end_scalar: usize) UTF16SliceError!UTF16View {
        if (start_scalar > end_scalar) {
            return error.IndexOutOfBounds;
        }

        var scalar_index: usize = 0;
        var unit_index: usize = 0;

        var start_unit: ?usize = null;
        var end_unit: ?usize = null;

        while (unit_index < self.data.len) {
            if (scalar_index == start_scalar) {
                start_unit = unit_index;
            }

            if (scalar_index == end_scalar) {
                end_unit = unit_index;
                break;
            }

            const unit = self.data[unit_index];

            const len: u2 = if (!isHighSurrogate(unit) and !isLowSurrogate(unit))
                1
            else
                utf16SequenceLenUnchecked(unit);

            if (len == 2) {
                if (unit_index + 1 >= self.data.len) {
                    return error.IndexOutOfBounds;
                }

                if (!isLowSurrogate(self.data[unit_index + 1])) {
                    return error.InvalidLowSurrogate;
                }
            }

            unit_index += @as(usize, len);
            scalar_index += 1;
        }

        if (scalar_index == start_scalar and start_unit == null) {
            start_unit = self.data.len;
        }

        if (scalar_index == end_scalar and end_unit == null) {
            end_unit = self.data.len;
        }

        if (start_unit == null or end_unit == null) {
            return error.IndexOutOfBounds;
        }

        return .{
            .data = self.data[start_unit.?..end_unit.?],
        };
    }

    /// Return a bidirectional iterator positioned at the start of the view.
    ///
    /// @stable-since: v0.2.0
    pub fn iter(self: *const UTF16View) UTF16ViewIterator {
        return .{ .data = self.data };
    }
};

/// Forward iterator that decodes raw, unvalidated `[]const u16` leniently,
/// yielding the replacement scalar (U+FFFD) for any malformed sequence (lone or
/// swapped surrogates). Obtain one with `lossyIterator`.
///
/// @stable-since: v0.2.0
pub const UTF16LossyIterator = struct {
    data: []const u16,
    index: usize = 0,
    curr: ?CodePoint = null,

    /// Advance to and return the next scalar (replacement on malformed units),
    /// or `null` at the end.
    ///
    /// @stable-since: v0.2.0
    pub fn next(self: *UTF16LossyIterator) ?CodePoint {
        if (self.index >= self.data.len) {
            return null;
        }

        const decoded = validateAndDecodeU16CodePointLossy(self.data, self.index) catch @panic("invalid decode code point lossy");
        std.debug.assert(decoded.len > 0);
        self.index += decoded.len;
        self.curr = decoded.code_point;
        return decoded.code_point;
    }

    /// Return the next scalar without advancing (replacement on malformed
    /// units), or `null` at the end.
    ///
    /// @stable-since: v0.2.0
    pub fn peek(self: *const UTF16LossyIterator) ?CodePoint {
        if (self.index >= self.data.len) {
            return null;
        }

        return (validateAndDecodeU16CodePointLossy(self.data, self.index) catch @panic("invalid decode code point lossy")).code_point;
    }
};

/// Takes un-validated UTF-16 `units` and returns a lossy forward iterator. Any
/// malformed unit yields the Unicode Replacement Character (U+FFFD). See
/// `UTF16LossyIterator`; use `initUTF16View` for strict decoding.
///
/// @stable-since: v0.1.0
pub fn lossyIterator(units: []const u16) UTF16LossyIterator {
    return .{ .data = units };
}

/// Returns the number of scalars produced by lossily decoding `units`,
/// counting one replacement scalar per malformed unit. Strict counterpart:
/// `countScalars`.
///
/// @stable-since: v0.1.0
pub fn countScalarsLossy(units: []const u16) usize {
    var count: usize = 0;
    var iter = lossyIterator(units);

    while (iter.next()) |_| : (count += 1) {}

    return count;
}

/// Lossily decode `units` into the caller-supplied `buf`, returning the number
/// of scalars written. Malformed units become the replacement scalar (U+FFFD);
/// a `buf` too small to hold every scalar returns `error.BufferTooSmall`.
/// Strict counterpart: `bufToCodePointsBuffer`.
///
/// @stable-since: v0.1.0
pub fn bufToCodePointsLossyBuffer(units: []const u16, buf: []CodePoint) error{BufferTooSmall}!usize {
    var i: usize = 0;
    var iter = lossyIterator(units);

    while (iter.next()) |code_point| {
        if (i >= buf.len) {
            return error.BufferTooSmall;
        }
        buf[i] = code_point;
        i += 1;
    }

    return i;
}

/// Lossily decode `units` into a freshly allocated `[]CodePoint`, substituting
/// the replacement scalar (U+FFFD) for malformed units. The caller owns and
/// must free the result.
///
/// @stable-since: v0.1.0
pub fn bufToCodePointsLossy(allocator: std.mem.Allocator, units: []const u16) error{ OutOfMemory, BufferTooSmall }![]CodePoint {
    const len = countScalarsLossy(units);
    const out = try allocator.alloc(CodePoint, len);
    errdefer allocator.free(out);

    _ = try bufToCodePointsLossyBuffer(units, out);
    return out;
}

/// Returns `true` when `units` is well-formed UTF-16 from start to end (every
/// high surrogate paired with a low surrogate, no lone surrogates), `false`
/// otherwise. Fast path when only a yes/no answer is needed; use `countScalars`
/// or `initUTF16View` when the failure reason or scalar count matters.
///
/// @stable-since: v0.2.0
pub fn validate(units: []const u16) bool {
    var scalar_count: usize = 0;
    _ = initUTF16View(units, &scalar_count) catch return false;
    return true;
}

/// Validates `units` and returns the number of Unicode scalars it encodes.
/// Strict counterpart of `countScalarsLossy`: a malformed unit surfaces the
/// corresponding `UTF16ValidationError` instead of being counted as a
/// replacement scalar.
///
/// @stable-since: v0.2.0
pub fn countScalars(units: []const u16) UTF16ValidationError!usize {
    var scalar_count: usize = 0;
    _ = try initUTF16View(units, &scalar_count);
    return scalar_count;
}

/// Validates `units` and writes the decoded scalars into the caller-supplied
/// `buf`, returning the number written. Strict counterpart of
/// `bufToCodePointsLossyBuffer`: a malformed unit surfaces a
/// `UTF16ValidationError`, and a `buf` too small returns `error.BufferTooSmall`.
/// Allocation-free; pair with `countScalars` to size `buf`, or use
/// `bufToUTF16String` to allocate.
///
/// @stable-since: v0.2.0
pub fn bufToCodePointsBuffer(units: []const u16, buf: []CodePoint) (UTF16ValidationError || error{BufferTooSmall})!usize {
    var i: usize = 0;
    var o: usize = 0;

    while (i < units.len) {
        const decoded = try validateAndDecodeU16CodePoint(units, i);
        if (o >= buf.len) {
            return error.BufferTooSmall;
        }
        buf[o] = decoded.code_point;
        o += 1;
        i += @as(usize, decoded.len);
    }

    return o;
}

/// Validate every code unit of `data` and return a view over it, writing the
/// decoded scalar count to `resultant_unicode_str_len`. Errors on the first
/// malformed sequence. Prefer this over the unchecked variant for untrusted
/// input.
///
/// @stable-since: v0.1.0
pub fn initUTF16View(data: []const u16, resultant_unicode_str_len: *usize) UTF16ValidationError!UTF16View {
    var i: usize = 0;
    var scalar_count: usize = 0;

    while (i < data.len) : (scalar_count += 1) {
        const len = try validateU16Sequence(data, i);
        _ = try validateAndDecodeU16CodePointWithLen(data, i, len);
        i += @as(usize, len);
    }

    resultant_unicode_str_len.* = scalar_count;

    return .{ .data = data };
}

/// Wrap `data` in a view without validating its code units. The caller must
/// guarantee every unit forms valid UTF-16. Use `initUTF16View` for untrusted
/// input.
///
/// @stable-since: v0.1.0
pub fn initUTF16ViewUnchecked(data: []const u16) UTF16View {
    return .{ .data = data };
}

/// Copy the scalars of `view` into `buf`, returning the count written. Errors
/// if `buf` is too small to hold every scalar.
///
/// @stable-since: v0.1.0
pub fn utf16ViewToUTF16String(view: *const UTF16View, buf: []CodePoint) (UTF16ValidationError || error{BufferTooSmall})!usize {
    var i: usize = 0;
    var iter = view.iter();
    while (iter.next()) |code_point| {
        if (i >= buf.len) return error.BufferTooSmall;
        buf[i] = code_point;
        i += 1;
    }

    if (iter.next() != null) {
        return error.BufferTooSmall;
    }

    return i;
}

/// Validate and decode comptime-known `units` into a fixed-size `[N]CodePoint`
/// array sized to the scalar count. Compile error on any malformed unit.
///
/// @stable-since: v0.1.0
pub fn bufToUTF16StringComptime(comptime units: []const u16) (UTF16ValidationError || error{BufferTooSmall})![initUTF16ViewUnchecked(units).countScalar()]CodePoint {
    comptime {
        var unicode_str_len: usize = 0;
        const view = try initUTF16View(units, &unicode_str_len);
        var buf: [unicode_str_len]CodePoint = undefined;
        _ = try utf16ViewToUTF16String(&view, &buf);
        return buf;
    }
}

/// Validate and decode `buf` into a freshly allocated `[]CodePoint`. Errors on
/// the first malformed unit. The caller owns and must free the result.
///
/// @stable-since: v0.1.0
pub fn bufToUTF16String(allocator: std.mem.Allocator, buf: []const u16) (UTF16ValidationError || error{ BufferTooSmall, OutOfMemory })![]CodePoint {
    var unicode_str_len: usize = 0;
    const view = try initUTF16View(buf, &unicode_str_len);
    const out = try allocator.alloc(CodePoint, unicode_str_len);
    errdefer allocator.free(out);

    _ = try utf16ViewToUTF16String(&view, out);

    return out;
}

// --- tests ------------------------------------------------------------------

test "utf16SequenceLen: BMP, surrogates, unpaired" {
    try std.testing.expectEqual(@as(u2, 1), try utf16SequenceLen('A'));
    try std.testing.expectEqual(@as(u2, 1), try utf16SequenceLen(0xFFFF));
    try std.testing.expectEqual(@as(u2, 2), try utf16SequenceLen(high_surrogate_range_start));
    try std.testing.expectError(error.InvalidLowSurrogate, utf16SequenceLen(low_surrogate_range_start));
    try std.testing.expectError(error.InvalidLowSurrogate, utf16SequenceLen(surrogate_range_end));
}

test "utf16EncodeLen: BMP, supplementary, surrogates, overflow" {
    try std.testing.expectEqual(@as(u2, 1), try utf16EncodeLen(0));
    try std.testing.expectEqual(@as(u2, 1), try utf16EncodeLen(0xFFFF));
    try std.testing.expectEqual(@as(u2, 2), try utf16EncodeLen(min_supplementary_code_point));
    try std.testing.expectEqual(@as(u2, 2), try utf16EncodeLen(max_supplementary_code_point));
}

test "validateU16CodePoint: empty, truncated, bad pair" {
    try std.testing.expectError(error.ZeroLengthUnits, validateU16Sequence(&.{}, 0));
    try std.testing.expectError(error.IndexOutOfBounds, validateU16Sequence(&.{high_surrogate_range_start}, 0));
    try std.testing.expectError(error.InvalidLowSurrogate, validateU16Sequence(&.{low_surrogate_range_start}, 0));
    try std.testing.expectError(error.InvalidLowSurrogate, validateU16Sequence(&.{ high_surrogate_range_start, 0x0041 }, 0));
    _ = try validateU16Sequence(&.{ 'a', 'Z' }, 0);
}

test "validateAndDecode: supplementary and scalar range" {
    const grin = [_]u16{ 0xD83D, 0xDE00 };
    const d = try validateAndDecodeU16CodePoint(&grin, 0);
    try std.testing.expectEqual(@as(CodePoint, 0x1F600), d.code_point);
    try std.testing.expectEqual(@as(u2, 2), d.len);

    // Lone high surrogate at end of buffer
    try std.testing.expectError(error.IndexOutOfBounds, validateAndDecodeU16CodePoint(&.{high_surrogate_range_start}, 0));
}

test "utf16SequenceLenReverse and validateU16CodePointReverse" {
    try std.testing.expectError(error.ZeroLengthUnits, utf16SequenceLenReverse(&.{}, 0));

    const one = [_]u16{'x'};
    try std.testing.expectEqual(@as(u2, 1), try utf16SequenceLenReverse(&one, one.len - 1));
    try std.testing.expectEqual(@as(u2, 1), try validateU16CodePointReverse(&one));

    const pair = [_]u16{ 0xD83D, 0xDE00 };
    try std.testing.expectEqual(@as(u2, 2), try utf16SequenceLenReverse(&pair, pair.len - 1));
    try std.testing.expectEqual(@as(u2, 2), try validateU16CodePointReverse(&pair));

    try std.testing.expectError(error.InvalidLowSurrogate, utf16SequenceLenReverse(&.{low_surrogate_range_start}, 0));
    try std.testing.expectError(error.InvalidHighSurrogate, utf16SequenceLenReverse(&.{high_surrogate_range_start}, 0));
    // Reverse peels legal trailing BMP (same heuristic as UTF-8 orphan lead + ASCII tail)
    try std.testing.expectEqual(@as(u2, 1), try utf16SequenceLenReverse(&.{ high_surrogate_range_start, 0x0041 }, 1));
}

test "encode/decode round-trip representative code points" {
    const cases = [_]CodePoint{
        0x0000,
        0x007F,
        0x0080,
        0x07FF,
        0x0800,
        0xD7FF,
        0xE000,
        0xFFFF,
        0x10000,
        0x1F600,
        0x10FFFF,
    };

    var buf: [2]u16 = undefined;

    for (cases) |cp| {
        const len = try encodeCodePoint(cp, &buf);
        const decoded = decode(&buf, 0, len);
        try std.testing.expectEqual(cp, decoded.code_point);
        try std.testing.expectEqual(len, decoded.len);
    }
}

test "encode rejects surrogates; buffer too small" {
    var buf: [1]u16 = undefined;
    try std.testing.expectError(error.BufferTooSmall, encodeCodePoint(0x1F600, &buf));
}

test "checked decode rejects illegal units" {
    try std.testing.expectError(error.InvalidLowSurrogate, validateAndDecodeU16CodePoint(&.{low_surrogate_range_start}, 0));
    try std.testing.expectError(error.IndexOutOfBounds, validateAndDecodeU16CodePoint(&.{high_surrogate_range_start}, 0));
}

test "validateAndDecodeU16CodePoint and ReverseChecked agree on valid scalars" {
    const units = [_]u16{ 'a', 0x03B1, 0xD83D, 0xDE00, 0xD7FF, 0xDBFF, 0xDFFF };
    var i: usize = 0;
    while (i < units.len) {
        const fwd = try validateAndDecodeU16CodePoint(&units, i);
        const prefix = units[0 .. i + fwd.len];
        const rev = try validateAndDecodeU16CodePointReverse(prefix, prefix.len - 1);
        try std.testing.expectEqual(fwd.code_point, rev.code_point);
        try std.testing.expectEqual(fwd.len, rev.len);
        i += @as(usize, fwd.len);
    }
}

test "UTF16View: boundaries and countScalar" {
    const view = initUTF16ViewUnchecked(&[_]u16{ 'e', 0xD83D, 0xDE00 });
    try std.testing.expectEqual(@as(usize, 2), view.countScalar());

    try std.testing.expect(view.isBoundary(0));
    try std.testing.expect(view.isBoundary(1));
    try std.testing.expect(!view.isBoundary(2));
    try std.testing.expect(view.isBoundary(3));
}

test "UTF16View: iterator next, peek, previous, peekPrevious" {
    var view = initUTF16ViewUnchecked(&[_]u16{ 'a', 'b' });
    var it = view.iter();
    try std.testing.expectEqual(@as(?CodePoint, 'a'), it.peek());
    try std.testing.expectEqual(@as(?CodePoint, 'a'), it.next());
    try std.testing.expectEqual(@as(?CodePoint, 'b'), it.peek());
    try std.testing.expectEqual(@as(?CodePoint, 'b'), it.next());
    try std.testing.expectEqual(@as(?CodePoint, null), it.next());

    it.index = 2;
    try std.testing.expectEqual(@as(?CodePoint, 'b'), it.peekPrevious());
    try std.testing.expectEqual(@as(?CodePoint, 'b'), it.previous());
    try std.testing.expectEqual(@as(?CodePoint, 'a'), it.peekPrevious());
    try std.testing.expectEqual(@as(?CodePoint, 'a'), it.previous());
    try std.testing.expectEqual(@as(?CodePoint, null), it.previous());
}

test "initUTF16View validates full buffer" {
    var n: usize = 0;
    _ = try initUTF16View(&[_]u16{ 'x', 0xD83D, 0xDE00 }, &n);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectError(error.InvalidLowSurrogate, initUTF16View(&[_]u16{low_surrogate_range_start}, &n));
}

test "utf16ViewToUTF16String and bufToUTF16String" {
    var n: usize = 0;
    const view = try initUTF16View(&[_]u16{ 0x03B1, 0xD83D, 0xDE00 }, &n);
    var stack: [2]CodePoint = undefined;
    try std.testing.expectEqual(@as(usize, 2), try utf16ViewToUTF16String(&view, &stack));
    try std.testing.expectEqual(@as(CodePoint, 0x03B1), stack[0]);
    try std.testing.expectEqual(@as(CodePoint, 0x1F600), stack[1]);

    const s = try bufToUTF16String(std.testing.allocator, &[_]u16{'z'});
    defer std.testing.allocator.free(s);
    try std.testing.expectEqual(@as(usize, 1), s.len);
    try std.testing.expectEqual(@as(CodePoint, 'z'), s[0]);
}

test "unpaired and swapped surrogates" {
    try std.testing.expectError(error.InvalidLowSurrogate, utf16SequenceLenReverse(&.{low_surrogate_range_start}, 0));
    try std.testing.expectError(error.InvalidHighSurrogate, utf16SequenceLenReverse(&.{high_surrogate_range_start}, 0));
    try std.testing.expectEqual(@as(u2, 1), try validateU16CodePointReverse(&.{ low_surrogate_range_start, 'a' }));
    try std.testing.expectError(error.InvalidHighSurrogate, validateU16CodePointReverse(&.{ 'a', high_surrogate_range_start }));
}

test "reverse peels trailing BMP after invalid lead" {
    const d = try validateAndDecodeU16CodePointReverse(&.{ high_surrogate_range_start, '(' }, 1);
    try std.testing.expectEqual(@as(CodePoint, '('), d.code_point);
    try std.testing.expectEqual(@as(u2, 1), d.len);

    const tail = try validateAndDecodeU16CodePointReverse(&.{ 0xD83D, 0xD83D, '(' }, 2);
    try std.testing.expectEqual(@as(CodePoint, '('), tail.code_point);
    try std.testing.expectEqual(@as(u2, 1), tail.len);
}

test "reverse decode errors on isolated malformed buffers" {
    const Case = struct { units: []const u16, expect_err: UTF16ValidationError };
    const cases = [_]Case{
        .{ .units = &.{low_surrogate_range_start}, .expect_err = error.InvalidLowSurrogate },
        .{ .units = &.{high_surrogate_range_start}, .expect_err = error.InvalidHighSurrogate },
    };

    for (cases) |c| {
        try std.testing.expectError(c.expect_err, validateAndDecodeU16CodePointReverse(c.units, c.units.len - 1));
    }
}

test "supplementary boundary U+10FFFF" {
    const max_pair = [_]u16{ 0xDBFF, 0xDFFF };
    try std.testing.expectEqual(@as(CodePoint, 0x10FFFF), (try validateAndDecodeU16CodePointReverse(&max_pair, max_pair.len - 1)).code_point);

    try std.testing.expectError(error.InvalidLowSurrogate, validateAndDecodeU16CodePoint(&.{ 0xDBFF, 0xE000 }, 0));
}

test "initUTF16View rejects stitched errors" {
    var n: usize = 0;
    try std.testing.expectError(error.InvalidLowSurrogate, initUTF16View(&[_]u16{ 'q', low_surrogate_range_start }, &n));
    try std.testing.expectError(error.InvalidLowSurrogate, initUTF16View(&[_]u16{ high_surrogate_range_start, 'z' }, &n));
}

test "UTF16View iterator roundtrip on surrogate-heavy string" {
    var units: [6]u16 = undefined;
    _ = try encodeCodePoint(0x1F600, units[0..]);
    units[2] = 0x03B1;
    units[3] = 'q';
    var scalar_count: usize = 0;
    const view = try initUTF16View(units[0..4], &scalar_count);
    var it = view.iter();
    var fwd: usize = 0;
    while (it.next()) |cp| {
        _ = cp;
        fwd += 1;
    }
    var rev: usize = 0;
    while (it.previous()) |_| {
        rev += 1;
    }
    try std.testing.expectEqual(fwd, rev);
}

test "string conversion APIs propagate validation" {
    try std.testing.expectError(error.InvalidLowSurrogate, bufToUTF16String(std.testing.allocator, &[_]u16{low_surrogate_range_start}));
    try std.testing.expectError(error.IndexOutOfBounds, bufToUTF16String(std.testing.allocator, &[_]u16{high_surrogate_range_start}));
}

test "BMP encode/decode sweep (stride avoids timeout)" {
    var buf: [2]u16 = undefined;
    var cp: CodePoint = 0;
    while (cp <= 0xFFFF) : (cp += 0x111) {
        if (cp >= surrogate_range_start and cp <= surrogate_range_end) continue;
        const len = try encodeCodePoint(@intCast(cp), &buf);
        const d = try validateAndDecodeU16CodePoint(&buf, 0);
        try std.testing.expectEqual(@as(CodePoint, cp), d.code_point);
        try std.testing.expectEqual(len, d.len);
    }
}

test "supplementary encode/decode sweep" {
    var buf: [2]u16 = undefined;
    var cp: CodePoint = min_supplementary_code_point;
    while (cp <= max_supplementary_code_point) : (cp += 0x11111) {
        const len = try encodeCodePoint(cp, &buf);
        const d = try validateAndDecodeU16CodePoint(&buf, 0);
        try std.testing.expectEqual(cp, d.code_point);
        try std.testing.expectEqual(len, d.len);
    }
}

test "lossy: valid BMP scalar" {
    const d = try validateAndDecodeU16CodePointLossy(&.{0x0041}, 0);

    try std.testing.expectEqual(@as(CodePoint, 'A'), d.code_point);
    try std.testing.expectEqual(@as(usize, 1), d.len);
}

test "lossy: valid surrogate pair" {
    const d = try validateAndDecodeU16CodePointLossy(
        &.{ 0xD83D, 0xDE00 },
        0,
    );

    try std.testing.expectEqual(@as(CodePoint, 0x1F600), d.code_point);
    try std.testing.expectEqual(@as(usize, 2), d.len);
}

test "lossy: lone high surrogate becomes replacement" {
    const d = try validateAndDecodeU16CodePointLossy(
        &.{0xD83D},
        0,
    );

    try std.testing.expectEqual(INVALID_CODE_POINT, d.code_point);
    try std.testing.expectEqual(@as(usize, 1), d.len);
}

test "lossy: high surrogate followed by BMP becomes replacement len1" {
    const d = try validateAndDecodeU16CodePointLossy(
        &.{ 0xD83D, 'A' },
        0,
    );

    try std.testing.expectEqual(INVALID_CODE_POINT, d.code_point);
    try std.testing.expectEqual(@as(usize, 1), d.len);
}

test "lossy: lone low surrogate becomes replacement" {
    const d = try validateAndDecodeU16CodePointLossy(
        &.{0xDE00},
        0,
    );

    try std.testing.expectEqual(INVALID_CODE_POINT, d.code_point);
    try std.testing.expectEqual(@as(usize, 1), d.len);
}

test "lossy: consecutive low surrogates collapse into one replacement" {
    const d = try validateAndDecodeU16CodePointLossy(
        &.{ 0xDE00, 0xDE01, 0xDE02 },
        0,
    );

    try std.testing.expectEqual(INVALID_CODE_POINT, d.code_point);
    try std.testing.expectEqual(@as(usize, 3), d.len);
}

test "lossy: low surrogate run stops before valid BMP" {
    const d = try validateAndDecodeU16CodePointLossy(
        &.{ 0xDE00, 0xDE01, 'A' },
        0,
    );

    try std.testing.expectEqual(INVALID_CODE_POINT, d.code_point);
    try std.testing.expectEqual(@as(usize, 2), d.len);
}

test "lossy: low surrogate followed by valid pair" {
    const buf = [_]u16{
        0xDE00,
        0xD83D,
        0xDE00,
    };

    const first = try validateAndDecodeU16CodePointLossy(&buf, 0);

    try std.testing.expectEqual(INVALID_CODE_POINT, first.code_point);
    try std.testing.expectEqual(@as(usize, 1), first.len);

    const second = try validateAndDecodeU16CodePointLossy(&buf, 1);

    try std.testing.expectEqual(@as(CodePoint, 0x1F600), second.code_point);
    try std.testing.expectEqual(@as(usize, 2), second.len);
}

test "lossy: truncated pair at end of buffer" {
    const buf = [_]u16{
        'A',
        0xD83D,
    };

    const d = try validateAndDecodeU16CodePointLossy(&buf, 1);

    try std.testing.expectEqual(INVALID_CODE_POINT, d.code_point);
    try std.testing.expectEqual(@as(usize, 1), d.len);
}

test "lossy: replacement recovery iteration" {
    const buf = [_]u16{
        'A',
        0xDE00,
        0xD83D,
        0xDE00,
        0xD83D,
        'B',
    };

    var i: usize = 0;

    const expected = [_]CodePoint{
        'A',
        INVALID_CODE_POINT,
        0x1F600,
        INVALID_CODE_POINT,
        'B',
    };

    var idx: usize = 0;

    while (i < buf.len) {
        const d = try validateAndDecodeU16CodePointLossy(buf[0..], i);

        try std.testing.expectEqual(expected[idx], d.code_point);

        i += d.len;
        idx += 1;
    }

    try std.testing.expectEqual(expected.len, idx);
}

test "lossy: iterator and materialization replace malformed spans" {
    const buf = [_]u16{ 'A', 0xDE00, 0xD83D, 0xDE00, 0xD83D, 'B' };

    var iter = lossyIterator(&buf);
    try std.testing.expectEqual(@as(?CodePoint, 'A'), iter.next());
    try std.testing.expectEqual(@as(?CodePoint, INVALID_CODE_POINT), iter.next());
    try std.testing.expectEqual(@as(?CodePoint, 0x1F600), iter.next());
    try std.testing.expectEqual(@as(?CodePoint, INVALID_CODE_POINT), iter.next());
    try std.testing.expectEqual(@as(?CodePoint, 'B'), iter.next());
    try std.testing.expectEqual(@as(?CodePoint, null), iter.next());

    try std.testing.expectEqual(@as(usize, 5), countScalarsLossy(&buf));

    var out: [5]CodePoint = undefined;
    const n = try bufToCodePointsLossyBuffer(&buf, &out);
    try std.testing.expectEqual(@as(usize, 5), n);
    try std.testing.expectEqualSlices(CodePoint, &.{ 'A', INVALID_CODE_POINT, 0x1F600, INVALID_CODE_POINT, 'B' }, out[0..n]);
}

test "lossy: offset out of bounds" {
    try std.testing.expectError(
        error.IndexOutOfBounds,
        validateAndDecodeU16CodePointLossy(&.{'A'}, 1),
    );
}

test "lossy: zero length buffer" {
    try std.testing.expectError(
        error.ZeroLengthUnits,
        validateAndDecodeU16CodePointLossy(&.{}, 0),
    );
}

test "surrogate range forward validation matrix" {
    var high: u16 = high_surrogate_range_start;
    while (high <= high_surrogate_range_end) : (high += 1) {
        try std.testing.expectError(error.IndexOutOfBounds, validateU16Sequence(&.{high}, 0));
        try std.testing.expectError(error.InvalidLowSurrogate, validateU16Sequence(&.{ high, 'A' }, 0));
        try std.testing.expectError(error.InvalidLowSurrogate, validateU16Sequence(&.{ high, high_surrogate_range_start }, 0));

        const low: u16 = low_surrogate_range_start | (high & 0x03FF);
        try std.testing.expectEqual(@as(u2, 2), try validateU16Sequence(&.{ high, low }, 0));
    }

    var low: u16 = low_surrogate_range_start;
    while (low <= low_surrogate_range_end) : (low += 1) {
        try std.testing.expectError(error.InvalidLowSurrogate, validateU16Sequence(&.{low}, 0));
        try std.testing.expectError(error.InvalidLowSurrogate, utf16SequenceLenReverse(&.{low}, 0));
    }
}

test "UTF-16 lossy decoder makes progress over all surrogate code units" {
    var unit: u16 = surrogate_range_start;
    var replacements: usize = 0;

    while (unit <= surrogate_range_end) : (unit += 1) {
        const decoded = try validateAndDecodeU16CodePointLossy(&.{unit}, 0);
        try std.testing.expect(decoded.len > 0);
        try std.testing.expectEqual(INVALID_CODE_POINT, decoded.code_point);
        replacements += 1;
    }

    try std.testing.expectEqual(@as(usize, surrogate_range_end - surrogate_range_start + 1), replacements);
}

test "reverse validation rejects malformed surrogate endings" {
    const cases = [_][]const u16{
        &.{high_surrogate_range_start},
        &.{ 'A', high_surrogate_range_start },
        &.{ high_surrogate_range_start, high_surrogate_range_end },
    };

    for (cases) |units| {
        try std.testing.expectError(error.InvalidHighSurrogate, validateAndDecodeU16CodePointReverse(units, units.len - 1));
    }

    try std.testing.expectError(
        error.InvalidLowSurrogate,
        validateAndDecodeU16CodePointReverse(&.{low_surrogate_range_start}, 0),
    );
    try std.testing.expectError(
        error.InvalidLowSurrogate,
        validateAndDecodeU16CodePointReverse(&.{ low_surrogate_range_start, low_surrogate_range_end }, 1),
    );
}

test "encodeCodePoint rejects undersized UTF-16 output" {
    var empty: [0]u16 = .{};
    var one: [1]u16 = undefined;

    try std.testing.expectError(error.BufferTooSmall, encodeCodePoint('A', &empty));
    try std.testing.expectError(error.BufferTooSmall, encodeCodePoint(0x10000, &one));
}

test "validate: accepts well-formed and rejects malformed UTF-16" {
    try std.testing.expect(validate(&[_]u16{ 'a', 0xD83D, 0xDE00 }));
    try std.testing.expect(validate(&[_]u16{}));
    try std.testing.expect(!validate(&[_]u16{low_surrogate_range_start})); // lone low
    try std.testing.expect(!validate(&[_]u16{high_surrogate_range_start})); // lone high
    try std.testing.expect(!validate(&[_]u16{ high_surrogate_range_start, 'A' })); // unpaired high
}

test "countScalars: strict count and error propagation" {
    try std.testing.expectEqual(@as(usize, 0), try countScalars(&[_]u16{}));
    // 'a' + a surrogate pair (😀) = 2 scalars across 3 code units.
    try std.testing.expectEqual(@as(usize, 2), try countScalars(&[_]u16{ 'a', 0xD83D, 0xDE00 }));
    try std.testing.expectError(error.InvalidLowSurrogate, countScalars(&[_]u16{low_surrogate_range_start}));
}

test "bufToCodePointsBuffer: strict decode, BufferTooSmall, and error propagation" {
    var buf: [2]CodePoint = undefined;
    const n = try bufToCodePointsBuffer(&[_]u16{ 'a', 0xD83D, 0xDE00 }, &buf);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqualSlices(CodePoint, &.{ 'a', 0x1F600 }, buf[0..n]);

    var tiny: [1]CodePoint = undefined;
    try std.testing.expectError(error.BufferTooSmall, bufToCodePointsBuffer(&[_]u16{ 'a', 'b' }, &tiny));
    try std.testing.expectError(error.InvalidLowSurrogate, bufToCodePointsBuffer(&[_]u16{low_surrogate_range_start}, &buf));
}

test "encodeCodePointUnchecked: matches encodeCodePoint for valid scalars" {
    var buf: [2]u16 = undefined;
    const cases = [_]CodePoint{ 'A', 0xFFFF, 0x10000, 0x1F600, 0x10FFFF };
    for (cases) |cp| {
        const len = encodeCodePointUnchecked(cp, &buf);
        const got = try validateAndDecodeU16CodePoint(&buf, 0);
        try std.testing.expectEqual(cp, got.code_point);
        try std.testing.expectEqual(@as(u2, got.len), len);
    }
}

test "encodeCodePointWriter: emits big/little-endian bytes" {
    var backing: [8]u8 = undefined;

    var be = std.Io.Writer.fixed(&backing);
    const be_len = try encodeCodePointWriter('A', .big, &be);
    try std.testing.expectEqual(@as(u2, 1), be_len);
    try std.testing.expectEqualSlices(u8, &.{ 0x00, 0x41 }, be.buffered());

    var le = std.Io.Writer.fixed(&backing);
    _ = try encodeCodePointWriter('A', .little, &le);
    try std.testing.expectEqualSlices(u8, &.{ 0x41, 0x00 }, le.buffered());

    var pair = std.Io.Writer.fixed(&backing);
    const pair_len = try encodeCodePointWriter(0x1F600, .big, &pair);
    try std.testing.expectEqual(@as(u2, 2), pair_len);
    try std.testing.expectEqualSlices(u8, &.{ 0xD8, 0x3D, 0xDE, 0x00 }, pair.buffered());

    var tiny_backing: [1]u8 = undefined;
    var tiny = std.Io.Writer.fixed(&tiny_backing);
    try std.testing.expectError(error.WriteFailed, encodeCodePointWriter('A', .big, &tiny));
}

test "sliceScalars produces a usable sub-view (regression: no endian field)" {
    var n: usize = 0;
    const view = try initUTF16View(&[_]u16{ 'a', 0xD83D, 0xDE00, 'b' }, &n);
    const mid = try view.sliceScalars(1, 3);
    var out: [2]CodePoint = undefined;
    const written = try utf16ViewToUTF16String(&mid, &out);
    try std.testing.expectEqual(@as(usize, 2), written);
    try std.testing.expectEqual(@as(CodePoint, 0x1F600), out[0]);
    try std.testing.expectEqual(@as(CodePoint, 'b'), out[1]);
}

test "bufToUTF16StringComptime (regression: single-arg view ctor)" {
    const arr = comptime try bufToUTF16StringComptime(&[_]u16{ 'h', 'i' });
    try comptime std.testing.expect(arr.len == 2);
    try comptime std.testing.expect(arr[0] == 'h' and arr[1] == 'i');
}

test "public view types are reachable as named types" {
    const view: UTF16View = initUTF16ViewUnchecked(&[_]u16{ 'a', 'b' });
    var it: UTF16ViewIterator = view.iter();
    try std.testing.expectEqual(@as(?CodePoint, 'a'), it.next());
    var lossy: UTF16LossyIterator = lossyIterator(&[_]u16{ 'a', 'b' });
    try std.testing.expectEqual(@as(?CodePoint, 'a'), lossy.next());
}

test "decodeU16CodePointUnchecked: agrees with strict decode over valid UTF-16" {
    const units = [_]u16{ 'a', 0x00E9, 0x20AC, 0xD83D, 0xDE00, 'z' };
    var offset: usize = 0;
    while (offset < units.len) {
        const expected = try validateAndDecodeU16CodePoint(&units, offset);
        const actual = decodeU16CodePointUnchecked(&units, offset);
        try std.testing.expectEqual(expected.code_point, actual.code_point);
        try std.testing.expectEqual(expected.len, actual.len);
        offset += actual.len;
    }
    try std.testing.expectEqual(units.len, offset);
}
