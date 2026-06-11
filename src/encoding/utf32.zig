//! UTF-32 encoding and decoding over `[]const u32` code units.
//!
//! Every Unicode scalar occupies exactly one `u32` code unit, so the
//! sequence length is always 1. The work here is therefore validation:
//! rejecting surrogate code points (U+D800..U+DFFF) and units above the
//! Unicode range (> U+10FFFF). Provides validation, forward and reverse
//! decoding, encoding, lossy decoding with the replacement scalar,
//! zero-copy views, and conversion to `[]CodePoint`.
//!
//! Prefer the checked `validateAndDecode…` entry points for untrusted
//! input; the `…Unchecked` and `…Lossy` variants assume or tolerate
//! malformed units respectively.

const std = @import("std");
const utils = @import("utils");
const encoding = @import("root.zig");

const CodePoint = encoding.CodePoint;
const INVALID_CODE_POINT = encoding.INVALID_CODE_POINT;

const encoding_range_end: CodePoint = 0x10FFFF;

/// Byte order used when interpreting stored UTF-32 code units.
pub const Endian = utils.Endian;

/// First code point of the surrogate range (U+D800); surrogates are not
/// valid UTF-32 scalars.
pub const surrogate_range_start: u32 = 0xD800;
/// Last code point of the surrogate range (U+DFFF), inclusive.
pub const surrogate_range_end: u32 = 0xDFFF;

/// Smallest representable Unicode scalar (U+0000).
pub const min_scalar: CodePoint = 0x0000;
/// Largest representable Unicode scalar (U+10FFFF).
pub const max_scalar: CodePoint = 0x10FFFF;

/// A decoded scalar paired with the number of code units it consumed,
/// produced by the checked decode paths. In UTF-32 `len` is always 1.
pub const DecodedCodePoint = struct {
    code_point: CodePoint,
    len: u1,
};

/// A decoded scalar paired with the number of code units consumed,
/// produced by the lossy decode paths. Invalid units yield the
/// replacement scalar with `len` still advancing past them.
pub const DecodedCodePointLossy = struct {
    code_point: CodePoint,
    len: usize,
};

/// Errors reported by the checked validation and decode paths: empty or
/// out-of-bounds access, surrogate units, and units above U+10FFFF.
pub const UTF32ValidationError = error{
    ZeroLengthUnits,
    IndexOutOfBounds,
    SurrogateCodePoint,
    CodePointTooLarge,
};

/// Errors reported by the lossy decode paths. Malformed scalar values
/// are replaced rather than raised, so only structural errors (empty or
/// out-of-bounds access) remain.
pub const UTF32ValidationLossyError = error{
    ZeroLengthUnits,
    IndexOutOfBounds,
};

/// Errors reported when encoding a code point into a `[]u32` buffer:
/// surrogate or out-of-range scalars, and an undersized output buffer.
pub const UTF32EncodeError = error{
    CodePointTooLarge,
    BufferTooSmall,
    SurrogateCodePoint,
};

fn validateScalarValue(code_point: CodePoint) UTF32ValidationError!void {
    if (code_point > encoding_range_end) {
        return error.CodePointTooLarge;
    }

    if (code_point >= surrogate_range_start and code_point <= surrogate_range_end) {
        return error.SurrogateCodePoint;
    }
}

fn validateStoredUnit(unit: u32) UTF32ValidationError!CodePoint {
    if (unit > encoding_range_end) {
        return error.CodePointTooLarge;
    }

    const code_point: CodePoint = @intCast(unit);
    try validateScalarValue(code_point);
    return code_point;
}

/// Validate `c32` as a stored UTF-32 unit and return its sequence length
/// (always 1). Errors on surrogate or out-of-range units.
///
/// @stable-since: v0.1.0
pub fn utf32SequenceLen(c32: u32) UTF32ValidationError!u1 {
    _ = try validateStoredUnit(c32);
    return 1;
}

/// Buffer must end at the last code unit of the scalar (`buf.len - 1`).
/// Validates that trailing unit and returns its sequence length (always 1).
///
/// @stable-since: v0.1.0
pub fn utf32SequenceLenReverse(buf: []const u32) UTF32ValidationError!u1 {
    if (buf.len == 0) {
        return error.ZeroLengthUnits;
    }
    _ = try validateStoredUnit(buf[buf.len - 1]);
    return 1;
}

/// Return the number of code units `code_point` would occupy when encoded
/// (always 1). Errors on surrogate or out-of-range scalars.
///
/// @stable-since: v0.1.0
pub fn utf32EncodeLen(code_point: CodePoint) UTF32EncodeError!u1 {
    if (code_point > encoding_range_end) {
        return error.CodePointTooLarge;
    }

    if (code_point >= surrogate_range_start and code_point <= surrogate_range_end) {
        return error.SurrogateCodePoint;
    }

    return 1;
}

/// Encode `code_point` into `buf` and return the units written (always 1).
/// Errors on surrogate or out-of-range scalars, or if `buf` is too small.
///
/// @stable-since: v0.1.0
pub fn encodeCodePoint(code_point: CodePoint, buf: []u32) UTF32EncodeError!u1 {
    const len = try utf32EncodeLen(code_point);

    if (buf.len < len) {
        return error.BufferTooSmall;
    }

    buf[0] = @intCast(code_point);
    return len;
}

/// Encode a valid `code_point` into `buf` and return the units written (always
/// 1). Neither the code point nor the buffer length is validated — the caller
/// must guarantee a valid scalar and `buf.len >= 1`. Use `encodeCodePoint` when
/// either invariant is uncertain.
///
/// Note: **an empty buffer or a surrogate / out-of-range scalar triggers
/// `unreachable` (checked illegal behavior in safe builds, UB in `ReleaseFast`).**
///
/// @stable-since: v0.2.0
pub fn encodeCodePointUnchecked(code_point: CodePoint, buf: []u32) u1 {
    return encodeCodePoint(code_point, buf) catch unreachable;
}

/// Encode a valid `code_point` as a single UTF-32 unit and write it to `writer`
/// as 4 bytes in the given `endian` order, returning the units written (always
/// 1). The code point is not validated — same contract as `encodeCodePoint`.
/// The only error returned is the writer's own (`error.WriteFailed`).
///
/// @stable-since: v0.2.0
pub fn encodeCodePointWriter(code_point: CodePoint, endian: Endian, writer: *std.Io.Writer) std.Io.Writer.Error!u1 {
    var units: [1]u32 = undefined;
    _ = encodeCodePointUnchecked(code_point, &units);

    var bytes: [4]u8 = undefined;
    const byte_len = utils.slices.u32SliceToBytesBuffer(units[0..1], &bytes, endian) catch unreachable;

    try writer.writeAll(bytes[0..byte_len]);
    return 1;
}

/// Returns the number of `u32` code units `code_points` occupies when encoded
/// as UTF-32 — always `code_points.len`. Provided for symmetry with the UTF-8
/// and UTF-16 bulk encoders so generic code can treat the three uniformly.
///
/// @stable-since: v0.4.0
pub fn encodeCodePointsLen(code_points: []const CodePoint) usize {
    return code_points.len;
}

/// Encodes `code_points` as UTF-32 into `buf` (native unit order), returning
/// the units written (always `code_points.len`). Returns
/// `error.BufferTooSmall` when `buf` is shorter than the input.
/// Allocation-free; use `encodeCodePointsAlloc` for an owned slice.
///
/// Contract: every element is a valid Unicode scalar (`CodePoint` contract);
/// the scalars are not validated.
///
/// @stable-since: v0.4.0
pub fn encodeCodePointsBuffer(code_points: []const CodePoint, buf: []u32) error{BufferTooSmall}!usize {
    if (buf.len < code_points.len) {
        return error.BufferTooSmall;
    }
    for (code_points, buf[0..code_points.len]) |code_point, *unit| {
        unit.* = code_point;
    }
    return code_points.len;
}

/// Encodes `code_points` as UTF-32 (native unit order) into a
/// freshly-allocated, exactly-sized unit slice. Caller owns (and frees) the
/// result. The encode-direction inverse of `bufToUTF32String`.
///
/// Contract: every element is a valid Unicode scalar (`CodePoint` contract);
/// the scalars are not validated.
///
/// @stable-since: v0.4.0
pub fn encodeCodePointsAlloc(allocator: std.mem.Allocator, code_points: []const CodePoint) error{OutOfMemory}![]u32 {
    const out = try allocator.alloc(u32, code_points.len);
    errdefer allocator.free(out);

    _ = encodeCodePointsBuffer(code_points, out) catch unreachable;
    return out;
}

/// Validate the unit at `buf[offset]` and return its sequence length
/// (always 1). Errors on empty input, out-of-bounds offset, or an
/// illegal unit.
///
/// @stable-since: v0.1.0
pub fn validateU32CodePoint(buf: []const u32, offset: usize) UTF32ValidationError!u1 {
    if (buf.len == 0) {
        return error.ZeroLengthUnits;
    } else if (offset >= buf.len) {
        return error.IndexOutOfBounds;
    }

    _ = try validateStoredUnit(buf[offset]);
    return 1;
}

/// Validate the trailing unit of `buf` and return its sequence length
/// (always 1). Reverse counterpart of `validateU32CodePoint`.
///
/// @stable-since: v0.1.0
pub fn validateU32CodePointReverse(buf: []const u32) UTF32ValidationError!u1 {
    return try utf32SequenceLenReverse(buf);
}

/// Pass entire buffer with offset to avoid reconstructing slice struct in hot paths.
fn validateAndDecodeU32CodePointWithLen(buf: []const u32, offset: usize, len: u1) UTF32ValidationError!DecodedCodePoint {
    if (buf.len == 0) {
        return error.ZeroLengthUnits;
    } else if (offset >= buf.len) {
        return error.IndexOutOfBounds;
    }

    if (buf.len - offset < @as(usize, len)) {
        return error.IndexOutOfBounds;
    }

    if (len != 1) {
        return error.IndexOutOfBounds;
    }

    const code_point = try validateStoredUnit(buf[offset]);
    return .{ .code_point = code_point, .len = 1 };
}

/// Validate and decode the scalar at `buf[offset]`. Prefer this checked
/// entry point for untrusted input; it rejects surrogate and out-of-range
/// units rather than producing them.
///
/// @stable-since: v0.1.0
pub fn validateAndDecodeU32CodePoint(buf: []const u32, offset: usize) UTF32ValidationError!DecodedCodePoint {
    const len = try validateU32CodePoint(buf, offset);
    return validateAndDecodeU32CodePointWithLen(buf, offset, len);
}

/// Decode the scalar at `buf[offset]`, substituting the replacement scalar
/// for any surrogate or out-of-range unit. Only structural errors (empty
/// input, out-of-bounds offset) are raised.
///
/// @stable-since: v0.1.0
pub fn validateAndDecodeU32CodePointLossy(buf: []const u32, offset: usize) UTF32ValidationLossyError!DecodedCodePointLossy {
    if (buf.len == 0) {
        return error.ZeroLengthUnits;
    } else if (offset >= buf.len) {
        return error.IndexOutOfBounds;
    }

    const code_point = validateStoredUnit(buf[offset]) catch INVALID_CODE_POINT;
    return .{ .code_point = code_point, .len = 1 };
}

/// Validate and decode the scalar ending at the last unit of `buf`.
/// Reverse counterpart of `validateAndDecodeU32CodePoint`, for backward
/// traversal.
///
/// @stable-since: v0.1.0
pub fn validateAndDecodeU32CodePointReverse(buf: []const u32) UTF32ValidationError!DecodedCodePoint {
    const len = try utf32SequenceLenReverse(buf);
    const start = buf.len - @as(usize, len);
    return validateAndDecodeU32CodePointWithLen(buf, start, len);
}

fn decodeCodePointReverse(buf: []const u32) DecodedCodePoint {
    const len = utf32SequenceLenReverse(buf) catch @panic("invalid point reverse unchecked len");
    const start = buf.len - @as(usize, len);
    return .{
        .code_point = @intCast(buf[start]),
        .len = len,
    };
}

/// Decodes the code point at `offset` without validating the unit. This is
/// the unchecked forward-decode entry point: callers that hold
/// already-validated UTF-32 can read scalars without paying validation again.
///
/// Contract: `offset < buf.len` and `buf[offset]` is a valid Unicode scalar
/// value (<= U+10FFFF, not a surrogate). Preconditions are asserted /
/// safety-checked (trap in Debug/ReleaseSafe, undefined in
/// ReleaseFast/ReleaseSmall), never error-returned. Use
/// `validateAndDecodeU32CodePoint` when the units' validity is uncertain.
///
/// @stable-since: v0.4.0
pub fn decodeU32CodePointUnchecked(buf: []const u32, offset: usize) DecodedCodePoint {
    std.debug.assert(offset < buf.len);

    return .{
        .code_point = @intCast(buf[offset]),
        .len = 1,
    };
}

fn bufToUTF32CodePoint(buf: []const u32, offset: usize) DecodedCodePoint {
    return decodeU32CodePointUnchecked(buf, offset);
}

/// Error returned when a scalar-index slice request falls outside the view.
pub const UTF32SliceError = error{
    IndexOutOfBounds,
};

/// Bidirectional cursor over the scalars of a `UTF32View`. Assumes the
/// underlying units are already valid (as produced by `initUTF32View`).
pub const UTF32ViewIterator = struct {
    index: usize = 0,
    view: *const UTF32View,
    curr: ?CodePoint = null,

    /// Advance to and return the next scalar, or `null` at the end.
    /// @stable-since: v0.1.0
    pub fn next(self: *UTF32ViewIterator) ?CodePoint {
        if (self.index >= self.view.data.len) {
            return null;
        }

        const code_point = bufToUTF32CodePoint(self.view.data, self.index);
        self.index += @as(usize, code_point.len);
        self.curr = code_point.code_point;

        return self.curr.?;
    }

    /// Return the next scalar without advancing the cursor, or `null` at
    /// the end.
    /// @stable-since: v0.1.0
    pub fn peek(self: *const UTF32ViewIterator) ?CodePoint {
        if (self.index >= self.view.data.len) {
            return null;
        }

        return bufToUTF32CodePoint(self.view.data, self.index).code_point;
    }

    /// Step back to and return the previous scalar, or `null` at the start.
    /// @stable-since: v0.1.0
    pub fn previous(self: *UTF32ViewIterator) ?CodePoint {
        if (self.index == 0) {
            return null;
        }

        const code_point = decodeCodePointReverse(self.view.data[0..self.index]);
        self.index -= @as(usize, code_point.len);
        self.curr = code_point.code_point;

        return self.curr.?;
    }

    /// Return the previous scalar without moving the cursor, or `null` at
    /// the start.
    /// @stable-since: v0.1.0
    pub fn peekPrevious(self: *const UTF32ViewIterator) ?CodePoint {
        if (self.index == 0) {
            return null;
        }

        return decodeCodePointReverse(self.view.data[0..self.index]).code_point;
    }
};

/// Zero-copy view over a `[]const u32` of UTF-32 code units together with
/// its byte order. Since each scalar is one unit, scalar indices and unit
/// indices coincide.
pub const UTF32View = struct {
    data: []const u32,
    endian: Endian,

    /// Return the number of scalars in the view (equal to the unit count).
    ///
    /// @stable-since: v0.1.0
    pub fn countScalar(self: *const UTF32View) usize {
        return self.data.len;
    }

    /// Report whether `index` is a valid scalar boundary, i.e. any offset
    /// from 0 through the unit count inclusive.
    ///
    /// @stable-since: v0.1.0
    pub fn isBoundary(self: *const UTF32View, index: usize) bool {
        return index <= self.data.len;
    }

    /// Return a sub-view spanning scalars `[start_scalar, end_scalar)`.
    /// Errors if the range is inverted or runs past the end.
    ///
    /// @stable-since: v0.1.0
    pub fn sliceScalars(self: *const UTF32View, start_scalar: usize, end_scalar: usize) UTF32SliceError!UTF32View {
        if (start_scalar > end_scalar or end_scalar > self.data.len) {
            return error.IndexOutOfBounds;
        }

        return .{
            .data = self.data[start_scalar..end_scalar],
            .endian = self.endian,
        };
    }

    /// Return a bidirectional iterator positioned at the start of the view.
    ///
    /// @stable-since: v0.1.0
    pub fn iter(self: *const UTF32View) UTF32ViewIterator {
        return .{ .view = self };
    }
};

/// Forward iterator that decodes raw `[]const u32` units leniently,
/// yielding the replacement scalar for any surrogate or out-of-range unit.
pub const UTF32LossyIterator = struct {
    data: []const u32,
    index: usize = 0,
    curr: ?CodePoint = null,

    /// Advance to and return the next scalar (replacement on invalid
    /// units), or `null` at the end.
    ///
    /// @stable-since: v0.1.0
    pub fn next(self: *UTF32LossyIterator) ?CodePoint {
        if (self.index >= self.data.len) {
            return null;
        }

        const decoded = validateAndDecodeU32CodePointLossy(self.data, self.index) catch @panic("invalid decode code point lossy");
        std.debug.assert(decoded.len > 0);
        self.index += decoded.len;
        self.curr = decoded.code_point;
        return decoded.code_point;
    }

    /// Return the next scalar without advancing (replacement on invalid
    /// units), or `null` at the end.
    ///
    /// @stable-since: v0.1.0
    pub fn peek(self: *const UTF32LossyIterator) ?CodePoint {
        if (self.index >= self.data.len) {
            return null;
        }

        return (validateAndDecodeU32CodePointLossy(self.data, self.index) catch @panic("invalid decode code point lossy")).code_point;
    }
};

/// Create a lossy forward iterator over `units` (see `UTF32LossyIterator`).
///
/// @stable-since: v0.1.0
pub fn lossyIterator(units: []const u32) UTF32LossyIterator {
    return .{ .data = units };
}

/// Count the scalars produced by lossy decoding `units`, including
/// replacement scalars for invalid units.
///
/// @stable-since: v0.1.0
pub fn countScalarsLossy(units: []const u32) usize {
    var count: usize = 0;
    var iter = lossyIterator(units);

    while (iter.next()) |_| {
        count += 1;
    }

    return count;
}

/// Returns `true` when every unit of `units` is a valid UTF-32 scalar (no
/// surrogates, none above U+10FFFF), `false` otherwise. Fast path when only a
/// yes/no answer is needed; use `countScalars` or `initUTF32View` when the
/// failure reason matters.
///
/// @stable-since: v0.2.0
pub fn validate(units: []const u32) bool {
    for (units) |unit| {
        _ = validateStoredUnit(unit) catch return false;
    }
    return true;
}

/// Returns the unit offset of the first invalid unit (a surrogate, or a value
/// above U+10FFFF), or `null` when `units` is valid UTF-32. The
/// position-reporting counterpart of `validate`.
///
/// To recover the precise failure kind, decode at the reported offset:
/// `validateAndDecodeU32CodePoint(units, invalidIndex(units).?)` returns the
/// fine-grained `UTF32ValidationError` for that unit.
///
/// @stable-since: v0.4.0
pub fn invalidIndex(units: []const u32) ?usize {
    for (units, 0..) |unit, i| {
        _ = validateStoredUnit(unit) catch return i;
    }
    return null;
}

/// Validates `units` and returns the number of Unicode scalars it encodes (one
/// per unit). Strict counterpart of `countScalarsLossy`: a surrogate or
/// out-of-range unit surfaces the corresponding `UTF32ValidationError` instead
/// of being counted as a replacement scalar.
///
/// @stable-since: v0.2.0
pub fn countScalars(units: []const u32) UTF32ValidationError!usize {
    for (units) |unit| {
        _ = try validateStoredUnit(unit);
    }
    return units.len;
}

/// Validates `units` and writes the decoded scalars into the caller-supplied
/// `buf`, returning the number written. Strict counterpart of
/// `bufToCodePointsLossyBuffer`: a surrogate or out-of-range unit surfaces a
/// `UTF32ValidationError`, and a `buf` too small returns `error.BufferTooSmall`.
/// Allocation-free; use `bufToUTF32String` to allocate.
///
/// @stable-since: v0.2.0
pub fn bufToCodePointsBuffer(units: []const u32, buf: []CodePoint) (UTF32ValidationError || error{BufferTooSmall})!usize {
    var o: usize = 0;

    for (units) |unit| {
        const code_point = try validateStoredUnit(unit);
        if (o >= buf.len) {
            return error.BufferTooSmall;
        }
        buf[o] = code_point;
        o += 1;
    }

    return o;
}

/// Lossily decode `units` into the caller-supplied `buf`, returning the
/// number of scalars written. Errors if `buf` cannot hold them all.
///
/// @stable-since: v0.1.0
pub fn bufToCodePointsLossyBuffer(units: []const u32, buf: []CodePoint) error{BufferTooSmall}!usize {
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

/// Lossily decode `units` into a freshly allocated `[]CodePoint`. The
/// caller owns and must free the result.
///
/// @stable-since: v0.1.0
pub fn bufToCodePointsLossy(allocator: std.mem.Allocator, units: []const u32) error{ OutOfMemory, BufferTooSmall }![]CodePoint {
    const len = countScalarsLossy(units);
    const out = try allocator.alloc(CodePoint, len);
    errdefer allocator.free(out);

    _ = try bufToCodePointsLossyBuffer(units, out);
    return out;
}

/// Validate every unit of `data` and return a view over it. Writes the
/// decoded scalar count to `resultant_unicode_str_len`. Errors on the first
/// surrogate or out-of-range unit. Prefer this over the unchecked variant
/// for untrusted input.
///
/// @stable-since: v0.1.0
pub fn initUTF32View(data: []const u32, endian: Endian, resultant_unicode_str_len: *usize) UTF32ValidationError!UTF32View {
    var i: usize = 0;
    var scalar_count: usize = 0;

    while (i < data.len) : (scalar_count += 1) {
        const len = try validateU32CodePoint(data, i);
        _ = try validateAndDecodeU32CodePointWithLen(data, i, len);
        i += @as(usize, len);
    }

    resultant_unicode_str_len.* = scalar_count;

    return .{ .data = data, .endian = endian };
}

/// Wrap `data` in a view without validating its units. The caller must
/// guarantee every unit is a valid UTF-32 scalar.
///
/// @stable-since: v0.1.0
pub fn initUTF32ViewUnchecked(data: []const u32, endian: Endian) UTF32View {
    return .{ .data = data, .endian = endian };
}

/// Copy the scalars of `view` into `buf`, returning the count written.
/// Errors if `buf` is too small to hold every scalar.
///
/// @stable-since: v0.1.0
pub fn utf32ViewToUTF32String(view: *const UTF32View, buf: []CodePoint) (UTF32ValidationError || error{BufferTooSmall})!usize {
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

/// Validate and decode comptime-known `units` into a fixed-size
/// `[N]CodePoint` array sized to the scalar count. Compile error on any
/// invalid unit.
///
/// @stable-since: v0.1.0
pub fn bufToUTF32StringComptime(comptime units: []const u32) (UTF32ValidationError || error{BufferTooSmall})![initUTF32ViewUnchecked(units, .little).countScalar()]CodePoint {
    comptime {
        var unicode_str_len: usize = 0;
        const view = try initUTF32View(units, .little, &unicode_str_len);
        var buf: [unicode_str_len]CodePoint = undefined;
        _ = try utf32ViewToUTF32String(&view, &buf);
        return buf;
    }
}

/// Validate and decode `buf` into a freshly allocated `[]CodePoint`. Errors
/// on the first invalid unit. The caller owns and must free the result.
///
/// @stable-since: v0.1.0
pub fn bufToUTF32String(allocator: std.mem.Allocator, buf: []const u32, endian: Endian) (UTF32ValidationError || error{ BufferTooSmall, OutOfMemory })![]CodePoint {
    var unicode_str_len: usize = 0;
    const view = try initUTF32View(buf, endian, &unicode_str_len);
    const out = try allocator.alloc(CodePoint, unicode_str_len);
    errdefer allocator.free(out);

    _ = try utf32ViewToUTF32String(&view, out);

    return out;
}

// --- tests ------------------------------------------------------------------

test "utf32SequenceLen: BMP, supplementary, surrogates, overflow" {
    try std.testing.expectEqual(@as(u1, 1), try utf32SequenceLen('A'));
    try std.testing.expectEqual(@as(u1, 1), try utf32SequenceLen(0x10FFFF));
    try std.testing.expectError(error.SurrogateCodePoint, utf32SequenceLen(surrogate_range_start));
    try std.testing.expectError(error.SurrogateCodePoint, utf32SequenceLen(surrogate_range_end));
    try std.testing.expectError(error.CodePointTooLarge, utf32SequenceLen(encoding_range_end + 1));
    try std.testing.expectError(error.CodePointTooLarge, utf32SequenceLen(0xFFFFFFFF));
}

test "utf32EncodeLen: boundaries, surrogates, overflow" {
    try std.testing.expectEqual(@as(u1, 1), try utf32EncodeLen(0));
    try std.testing.expectEqual(@as(u1, 1), try utf32EncodeLen(max_scalar));
    try std.testing.expectError(error.SurrogateCodePoint, utf32EncodeLen(surrogate_range_start));
    try std.testing.expectError(error.SurrogateCodePoint, utf32EncodeLen(surrogate_range_end));
    try std.testing.expectError(error.CodePointTooLarge, utf32EncodeLen(encoding_range_end + 1));
}

test "validateU32CodePoint: empty, out of bounds" {
    try std.testing.expectError(error.ZeroLengthUnits, validateU32CodePoint(&.{}, 0));
    try std.testing.expectError(error.IndexOutOfBounds, validateU32CodePoint(&.{'a'}, 1));
    try std.testing.expectError(error.SurrogateCodePoint, validateU32CodePoint(&.{surrogate_range_start}, 0));
    _ = try validateU32CodePoint(&.{ 'a', 'Z' }, 0);
}

test "validateAndDecode: representative scalars" {
    const grin = [_]u32{0x1F600};
    const d = try validateAndDecodeU32CodePoint(&grin, 0);
    try std.testing.expectEqual(@as(CodePoint, 0x1F600), d.code_point);
    try std.testing.expectEqual(@as(u1, 1), d.len);

    try std.testing.expectError(error.SurrogateCodePoint, validateAndDecodeU32CodePoint(&.{0xD800}, 0));
    try std.testing.expectError(error.CodePointTooLarge, validateAndDecodeU32CodePoint(&.{0x110000}, 0));
}

test "utf32SequenceLenReverse and validateU32CodePointReverse" {
    try std.testing.expectError(error.ZeroLengthUnits, utf32SequenceLenReverse(&.{}));

    const one = [_]u32{'x'};
    try std.testing.expectEqual(@as(u1, 1), try utf32SequenceLenReverse(&one));
    try std.testing.expectEqual(@as(u1, 1), try validateU32CodePointReverse(&one));

    try std.testing.expectError(error.SurrogateCodePoint, utf32SequenceLenReverse(&.{surrogate_range_start}));
    try std.testing.expectError(error.CodePointTooLarge, utf32SequenceLenReverse(&.{0xFFFFFFFF}));
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

    var buf: [1]u32 = undefined;

    for (cases) |cp| {
        const len = try encodeCodePoint(cp, &buf);
        const decoded = try validateAndDecodeU32CodePoint(&buf, 0);
        try std.testing.expectEqual(cp, decoded.code_point);
        try std.testing.expectEqual(len, decoded.len);
    }
}

test "encode rejects surrogates; buffer too small" {
    var buf: [0]u32 = undefined;
    try std.testing.expectError(error.SurrogateCodePoint, encodeCodePoint(0xD800, &buf));
    try std.testing.expectError(error.BufferTooSmall, encodeCodePoint('A', &buf));
}

test "checked decode rejects illegal units" {
    try std.testing.expectError(error.SurrogateCodePoint, validateAndDecodeU32CodePoint(&.{surrogate_range_start}, 0));
    try std.testing.expectError(error.CodePointTooLarge, validateAndDecodeU32CodePoint(&.{0x110000}, 0));
}

test "validateAndDecodeU32CodePoint and reverse agree on valid scalars" {
    const units = [_]u32{ 'a', 0x03B1, 0x1F600, 0xD7FF, 0xE000, 0x10FFFF };
    var i: usize = 0;
    while (i < units.len) {
        const fwd = try validateAndDecodeU32CodePoint(&units, i);
        const prefix = units[0 .. i + fwd.len];
        const rev = try validateAndDecodeU32CodePointReverse(prefix);
        try std.testing.expectEqual(fwd.code_point, rev.code_point);
        try std.testing.expectEqual(fwd.len, rev.len);
        i += @as(usize, fwd.len);
    }
}

test "UTF32View: boundaries and countScalar" {
    const view = initUTF32ViewUnchecked(&[_]u32{ 'e', 0x1F600 }, .little);
    try std.testing.expectEqual(@as(usize, 2), view.countScalar());

    try std.testing.expect(view.isBoundary(0));
    try std.testing.expect(view.isBoundary(1));
    try std.testing.expect(view.isBoundary(2));
    try std.testing.expect(!view.isBoundary(3));
}

test "UTF32View: iterator next, peek, previous, peekPrevious" {
    var view = initUTF32ViewUnchecked(&[_]u32{ 'a', 'b' }, .little);
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

test "UTF32View: sliceScalars" {
    const view = initUTF32ViewUnchecked(&[_]u32{ 'a', 'b', 'c' }, .little);
    const mid = try view.sliceScalars(1, 2);
    try std.testing.expectEqual(@as(usize, 1), mid.data.len);
    try std.testing.expectEqual(@as(u32, 'b'), mid.data[0]);
    try std.testing.expectError(error.IndexOutOfBounds, view.sliceScalars(2, 1));
    try std.testing.expectError(error.IndexOutOfBounds, view.sliceScalars(0, 4));
}

test "initUTF32View validates full buffer" {
    var n: usize = 0;
    _ = try initUTF32View(&[_]u32{ 'x', 0x1F600 }, .little, &n);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectError(error.SurrogateCodePoint, initUTF32View(&[_]u32{surrogate_range_start}, .little, &n));
}

test "utf32ViewToUTF32String and bufToUTF32String" {
    var n: usize = 0;
    const view = try initUTF32View(&[_]u32{ 0x03B1, 0x1F600 }, .little, &n);
    var stack: [2]CodePoint = undefined;
    try std.testing.expectEqual(@as(usize, 2), try utf32ViewToUTF32String(&view, &stack));
    try std.testing.expectEqual(@as(CodePoint, 0x03B1), stack[0]);
    try std.testing.expectEqual(@as(CodePoint, 0x1F600), stack[1]);

    const s = try bufToUTF32String(std.testing.allocator, &[_]u32{'z'}, .little);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqual(@as(usize, 1), s.len);
    try std.testing.expectEqual(@as(CodePoint, 'z'), s[0]);
}

test "high-bit garbage scalars in buffer" {
    const garbage = [_]u32{ 0x80000000, 0x00110000, 0x00FFFFFF, 0xFFFFFFFF };
    for (garbage) |unit| {
        try std.testing.expectError(error.CodePointTooLarge, utf32SequenceLen(unit));
        try std.testing.expectError(error.CodePointTooLarge, validateAndDecodeU32CodePoint(&.{unit}, 0));
    }
}

test "surrogate scalars stored as UTF-32 code units" {
    var cp: u32 = surrogate_range_start;
    while (cp <= surrogate_range_end) : (cp += 0x111) {
        try std.testing.expectError(error.SurrogateCodePoint, utf32SequenceLen(cp));
        try std.testing.expectError(error.SurrogateCodePoint, validateAndDecodeU32CodePointReverse(&.{cp}));
    }
}

test "reverse decode errors on isolated malformed buffers" {
    const Case = struct { units: []const u32, expect_err: UTF32ValidationError };
    const cases = [_]Case{
        .{ .units = &.{surrogate_range_start}, .expect_err = error.SurrogateCodePoint },
        .{ .units = &.{0x110000}, .expect_err = error.CodePointTooLarge },
        .{ .units = &.{}, .expect_err = error.ZeroLengthUnits },
    };

    for (cases) |c| {
        try std.testing.expectError(c.expect_err, validateAndDecodeU32CodePointReverse(c.units));
    }
}

test "supplementary boundary U+10FFFF" {
    const max_unit = [_]u32{0x10FFFF};
    try std.testing.expectEqual(@as(CodePoint, 0x10FFFF), (try validateAndDecodeU32CodePointReverse(&max_unit)).code_point);

    try std.testing.expectError(error.CodePointTooLarge, validateAndDecodeU32CodePoint(&.{0x110000}, 0));
}

test "initUTF32View rejects stitched errors" {
    var n: usize = 0;
    try std.testing.expectError(error.SurrogateCodePoint, initUTF32View(&[_]u32{ 'q', surrogate_range_start }, .little, &n));
    try std.testing.expectError(error.CodePointTooLarge, initUTF32View(&[_]u32{ 'z', 0x110000 }, .little, &n));
}

test "UTF32View iterator roundtrip on mixed string" {
    const units = [_]u32{ 0x1F600, 0x03B1, 'q' };
    var scalar_count: usize = 0;
    const view = try initUTF32View(&units, .little, &scalar_count);
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
    try std.testing.expectError(error.SurrogateCodePoint, bufToUTF32String(std.testing.allocator, &[_]u32{surrogate_range_start}, .little));
    try std.testing.expectError(error.CodePointTooLarge, bufToUTF32String(std.testing.allocator, &[_]u32{0x110000}, .little));
}

test "lossy: invalid UTF-32 units become replacement scalars" {
    const units = [_]u32{ 'A', 0xD800, 0x110000, 0x10FFFF };

    var iter = lossyIterator(&units);
    try std.testing.expectEqual(@as(?CodePoint, 'A'), iter.next());
    try std.testing.expectEqual(@as(?CodePoint, INVALID_CODE_POINT), iter.next());
    try std.testing.expectEqual(@as(?CodePoint, INVALID_CODE_POINT), iter.next());
    try std.testing.expectEqual(@as(?CodePoint, 0x10FFFF), iter.next());
    try std.testing.expectEqual(@as(?CodePoint, null), iter.next());

    try std.testing.expectEqual(@as(usize, 4), countScalarsLossy(&units));

    var out: [4]CodePoint = undefined;
    const n = try bufToCodePointsLossyBuffer(&units, &out);
    try std.testing.expectEqual(@as(usize, 4), n);
    try std.testing.expectEqualSlices(CodePoint, &.{ 'A', INVALID_CODE_POINT, INVALID_CODE_POINT, 0x10FFFF }, out[0..n]);
}

test "lossy: UTF-32 offset and zero-length errors" {
    try std.testing.expectError(error.IndexOutOfBounds, validateAndDecodeU32CodePointLossy(&.{'A'}, 1));
    try std.testing.expectError(error.ZeroLengthUnits, validateAndDecodeU32CodePointLossy(&.{}, 0));
}

test "utf32ViewToUTF32String buffer too small path" {
    var n: usize = 0;
    const view = try initUTF32View(&[_]u32{ 'a', 'b' }, .little, &n);
    var tiny: [1]CodePoint = undefined;
    try std.testing.expectError(error.BufferTooSmall, utf32ViewToUTF32String(&view, &tiny));
}

test "validateAndDecodeU32CodePointWithLen length contract" {
    const unit = [_]u32{'x'};
    try std.testing.expectError(error.IndexOutOfBounds, validateAndDecodeU32CodePointWithLen(&unit, 0, 0));
    _ = try validateAndDecodeU32CodePointWithLen(&unit, 0, 1);

    try std.testing.expectError(error.IndexOutOfBounds, validateAndDecodeU32CodePointWithLen(&unit, 1, 1));
}

test "forward APIs agree on prefix walks" {
    const units = [_]u32{ 'Z', 0x20AC, 0x10348 };
    var i: usize = 0;
    while (i < units.len) {
        const a = try validateAndDecodeU32CodePoint(&units, i);
        const b = try validateAndDecodeU32CodePoint(&units, i);
        try std.testing.expectEqual(a.code_point, b.code_point);
        try std.testing.expectEqual(a.len, b.len);
        i += @as(usize, a.len);
    }
}

test "BMP encode/decode sweep (stride avoids timeout)" {
    var buf: [1]u32 = undefined;
    var cp: CodePoint = 0;
    while (cp <= 0xFFFF) : (cp += 0x111) {
        if (cp >= surrogate_range_start and cp <= surrogate_range_end) continue;
        const len = try encodeCodePoint(@intCast(cp), &buf);
        const d = try validateAndDecodeU32CodePoint(&buf, 0);
        try std.testing.expectEqual(@as(CodePoint, cp), d.code_point);
        try std.testing.expectEqual(len, d.len);
    }
}

test "supplementary encode/decode sweep" {
    var buf: [1]u32 = undefined;
    var cp: CodePoint = 0x10000;
    while (cp <= max_scalar) : (cp += 0x11111) {
        const len = try encodeCodePoint(cp, &buf);
        const d = try validateAndDecodeU32CodePoint(&buf, 0);
        try std.testing.expectEqual(cp, d.code_point);
        try std.testing.expectEqual(len, d.len);
    }
}

test "compile-time initUTF32View rejects illegal units" {
    const surrogate_unit = comptime blk: {
        var scalar_count: usize = 0;
        break :blk initUTF32View(&[_]u32{0xD800}, .little, &scalar_count);
    };
    try std.testing.expectError(error.SurrogateCodePoint, surrogate_unit);

    const too_large = comptime blk: {
        var scalar_count: usize = 0;
        break :blk initUTF32View(&[_]u32{0x110000}, .little, &scalar_count);
    };
    try std.testing.expectError(error.CodePointTooLarge, too_large);

    _ = try comptime blk: {
        var scalar_count: usize = 0;
        break :blk initUTF32View(&[_]u32{'Σ'}, .little, &scalar_count);
    };
}

test "reverse always peels exactly one code unit on valid tail" {
    const units = [_]u32{ 0xD7FF, 0xE000, 0x10FFFF };
    var off = units.len;
    while (off > 0) {
        const d = try validateAndDecodeU32CodePointReverse(units[0..off]);
        try std.testing.expectEqual(@as(u1, 1), d.len);
        off -= 1;
    }
}

test "sliceScalars + utf32ViewToUTF32String on emoji-heavy string" {
    const units = [_]u32{ 0x1F600, 0x03B1, 'q', 0x10FFFF };
    var n: usize = 0;
    const view = try initUTF32View(&units, .little, &n);
    const slice = try view.sliceScalars(1, 3);
    var out: [2]CodePoint = undefined;
    try std.testing.expectEqual(@as(usize, 2), try utf32ViewToUTF32String(&slice, &out));
    try std.testing.expectEqual(@as(CodePoint, 0x03B1), out[0]);
    try std.testing.expectEqual(@as(CodePoint, 'q'), out[1]);
}

test "UTF-32 rejects every surrogate scalar value" {
    var unit: u32 = surrogate_range_start;
    var rejected: usize = 0;

    while (unit <= surrogate_range_end) : (unit += 1) {
        try std.testing.expectError(error.SurrogateCodePoint, utf32SequenceLen(unit));
        try std.testing.expectError(error.SurrogateCodePoint, validateAndDecodeU32CodePoint(&.{unit}, 0));
        rejected += 1;
    }

    try std.testing.expectEqual(@as(usize, surrogate_range_end - surrogate_range_start + 1), rejected);
}

test "UTF-32 lossy decoder replaces huge and surrogate units" {
    const units = [_]u32{
        0,
        surrogate_range_start,
        surrogate_range_end,
        max_scalar,
        max_scalar + 1,
        0x7FFF_FFFF,
        0xFFFF_FFFF,
    };

    var iter = lossyIterator(&units);
    var seen: usize = 0;
    while (iter.next()) |code_point| {
        if (seen == 1 or seen == 2 or seen >= 4) {
            try std.testing.expectEqual(INVALID_CODE_POINT, code_point);
        }
        seen += 1;
    }

    try std.testing.expectEqual(units.len, seen);
}

test "encodeCodePoint rejects undersized UTF-32 output" {
    var empty: [0]u32 = .{};
    try std.testing.expectError(error.BufferTooSmall, encodeCodePoint('A', &empty));
    try std.testing.expectError(error.SurrogateCodePoint, encodeCodePoint(surrogate_range_start, &empty));
    try std.testing.expectError(error.CodePointTooLarge, encodeCodePoint(max_scalar + 1, &empty));
}

test "validate: accepts scalars and rejects surrogate / out-of-range units" {
    try std.testing.expect(validate(&[_]u32{ 'a', 0x1F600, 0x10FFFF }));
    try std.testing.expect(validate(&[_]u32{}));
    try std.testing.expect(!validate(&[_]u32{surrogate_range_start}));
    try std.testing.expect(!validate(&[_]u32{0x110000}));
}

test "countScalars: strict count and error propagation" {
    try std.testing.expectEqual(@as(usize, 0), try countScalars(&[_]u32{}));
    try std.testing.expectEqual(@as(usize, 3), try countScalars(&[_]u32{ 'a', 0x1F600, 0x10FFFF }));
    try std.testing.expectError(error.SurrogateCodePoint, countScalars(&[_]u32{0xD800}));
    try std.testing.expectError(error.CodePointTooLarge, countScalars(&[_]u32{0x110000}));
}

test "bufToCodePointsBuffer: strict decode, BufferTooSmall, and error propagation" {
    var buf: [3]CodePoint = undefined;
    const n = try bufToCodePointsBuffer(&[_]u32{ 'a', 0x1F600, 0x10FFFF }, &buf);
    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqualSlices(CodePoint, &.{ 'a', 0x1F600, 0x10FFFF }, buf[0..n]);

    var tiny: [1]CodePoint = undefined;
    try std.testing.expectError(error.BufferTooSmall, bufToCodePointsBuffer(&[_]u32{ 'a', 'b' }, &tiny));
    try std.testing.expectError(error.SurrogateCodePoint, bufToCodePointsBuffer(&[_]u32{0xD800}, &buf));
}

test "encodeCodePointUnchecked: matches encodeCodePoint for valid scalars" {
    var buf: [1]u32 = undefined;
    const cases = [_]CodePoint{ 'A', 0x03B1, 0x1F600, 0x10FFFF };
    for (cases) |cp| {
        const len = encodeCodePointUnchecked(cp, &buf);
        try std.testing.expectEqual(@as(u1, 1), len);
        const got = try validateAndDecodeU32CodePoint(&buf, 0);
        try std.testing.expectEqual(cp, got.code_point);
    }
}

test "encodeCodePointWriter: emits big/little-endian bytes" {
    var backing: [4]u8 = undefined;

    var be = std.Io.Writer.fixed(&backing);
    const be_len = try encodeCodePointWriter('A', .big, &be);
    try std.testing.expectEqual(@as(u1, 1), be_len);
    try std.testing.expectEqualSlices(u8, &.{ 0x00, 0x00, 0x00, 0x41 }, be.buffered());

    var le = std.Io.Writer.fixed(&backing);
    _ = try encodeCodePointWriter('A', .little, &le);
    try std.testing.expectEqualSlices(u8, &.{ 0x41, 0x00, 0x00, 0x00 }, le.buffered());

    var tiny_backing: [2]u8 = undefined;
    var tiny = std.Io.Writer.fixed(&tiny_backing);
    try std.testing.expectError(error.WriteFailed, encodeCodePointWriter('A', .big, &tiny));
}

test "decodeU32CodePointUnchecked: agrees with strict decode over valid UTF-32" {
    const units = [_]u32{ 'a', 0x00E9, 0x20AC, 0x1F600, 'z' };
    var offset: usize = 0;
    while (offset < units.len) : (offset += 1) {
        const expected = try validateAndDecodeU32CodePoint(&units, offset);
        const actual = decodeU32CodePointUnchecked(&units, offset);
        try std.testing.expectEqual(expected.code_point, actual.code_point);
        try std.testing.expectEqual(expected.len, actual.len);
    }
}

test "invalidIndex: null on valid input, exact offset on bad units" {
    try std.testing.expectEqual(@as(?usize, null), invalidIndex(&[_]u32{}));
    try std.testing.expectEqual(@as(?usize, null), invalidIndex(&[_]u32{ 'a', 0x1F600 }));

    try std.testing.expectEqual(@as(?usize, 0), invalidIndex(&[_]u32{0xD800}));
    try std.testing.expectEqual(@as(?usize, 2), invalidIndex(&[_]u32{ 'o', 'k', 0x110000 }));
}

test "encodeCodePoints: round-trips through bufToUTF32String" {
    const cps = [_]CodePoint{ 'a', 0x00E9, 0x1F600 };

    try std.testing.expectEqual(cps.len, encodeCodePointsLen(&cps));

    var buf: [4]u32 = undefined;
    const written = try encodeCodePointsBuffer(&cps, &buf);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 'a', 0x00E9, 0x1F600 }, buf[0..written]);

    var small: [2]u32 = undefined;
    try std.testing.expectError(error.BufferTooSmall, encodeCodePointsBuffer(&cps, &small));

    const owned = try encodeCodePointsAlloc(std.testing.allocator, &cps);
    defer std.testing.allocator.free(owned);
    const back = try bufToUTF32String(std.testing.allocator, owned, .little);
    defer std.testing.allocator.free(back);
    try std.testing.expectEqualSlices(CodePoint, &cps, back);
}
