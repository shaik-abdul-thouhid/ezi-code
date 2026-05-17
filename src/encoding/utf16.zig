const std = @import("std");
const utils = @import("utils");
const encoding = @import("root.zig");

const CodePoint = encoding.CodePoint;
const INVALID_CODE_POINT = encoding.INVALID_CODE_POINT;

const encoding_range_end = 0x10FFFF;
const supplementary_offset: CodePoint = 0x10000;

pub const Endian = utils.Endian;

pub const surrogate_range_start: u16 = 0xD800;
pub const surrogate_range_end: u16 = 0xDFFF;

const surrogate_mask = 0b111111_0000000000;

pub const high_surrogate_range_start = 0b110110_0000000000;
pub const high_surrogate_range_end = 0b110110_1111111111;

pub const low_surrogate_range_start = 0b110111_0000000000;
pub const low_surrogate_range_end = 0b110111_1111111111;

pub const min_supplementary_code_point: CodePoint = 0x10000;
pub const max_supplementary_code_point: CodePoint = 0x10FFFF;

const DecodedCodePoint = struct {
    code_point: CodePoint,
    len: u2,
};

const DecodedCodePointLossy = struct {
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

const UTF16ValidationLossyError = error{
    ZeroLengthBytes,
    IndexOutOfBounds,
};

pub const UTF16EncodeError = error{
    CodePointTooLarge,
    BufferTooSmall,
    SurrogateCodePoint,
};

pub fn isHighSurrogate(c16: u16) bool {
    return (c16 & surrogate_mask) == high_surrogate_range_start;
}

pub fn isLowSurrogate(c16: u16) bool {
    return (c16 & surrogate_mask) == low_surrogate_range_start;
}

fn validateDecodedScalar(code_point: CodePoint) UTF16ValidationError!void {
    if (code_point > encoding_range_end) {
        return error.CodePointTooLarge;
    }

    if (code_point >= surrogate_range_start and code_point <= surrogate_range_end) {
        return error.SurrogateCodePoint;
    }
}

pub fn utf16SequenceLen(c16: u16) UTF16ValidationError!u2 {
    if (isHighSurrogate(c16)) {
        return 2;
    }

    if (isLowSurrogate(c16)) {
        return error.InvalidLowSurrogate;
    }

    return 1;
}

/// Returns `0` for any invalid optimistic sequence
pub fn utf16SequenceLenLossy(c16: u16) u2 {
    if (isHighSurrogate(c16)) {
        return 2;
    }

    if (isLowSurrogate(c16)) {
        return 0;
    }
    return 1;
}

pub fn utf16SequenceLenUnchecked(c16: u16) u2 {
    if (isHighSurrogate(c16)) {
        return 2;
    }

    return 1;
}

/// Buffer must end at the last code unit of the scalar (`buf.len - 1`).
pub fn utf16SequenceLenReverse(buf: []const u16, end_index: usize) UTF16ValidationError!u2 {
    if (buf.len == 0) {
        return error.ZeroLengthUnits;
    } else if (buf.len <= end_index) {
        return error.IndexOutOfBounds;
    }

    const last = end_index;

    if (isLowSurrogate(buf[last])) {
        if (end_index < 2 or !isHighSurrogate(buf[end_index - 1])) {
            return error.InvalidLowSurrogate;
        }
        return 2;
    }

    if (isHighSurrogate(buf[last])) {
        return error.InvalidHighSurrogate;
    }

    return 1;
}

pub fn utf16SequenceLenReverseUnChecked(buf: []const u16, end_index: usize) UTF16ValidationError!u2 {
    if (buf.len == 0) {
        return error.ZeroLengthUnits;
    }

    const last = end_index;

    if (isLowSurrogate(buf[last])) {
        return 2;
    }

    return 1;
}

pub fn utf16EncodeLen(code_point: CodePoint) UTF16EncodeError!u2 {
    if (code_point > encoding_range_end) {
        return error.CodePointTooLarge;
    }

    if (code_point >= surrogate_range_start and code_point <= surrogate_range_end) {
        return error.SurrogateCodePoint;
    }

    if (code_point < supplementary_offset) {
        return 1;
    }

    return 2;
}

pub fn encodeCodePoint(code_point: CodePoint, buf: []u16) UTF16EncodeError!u2 {
    if (code_point >= surrogate_range_start and code_point <= surrogate_range_end) {
        return error.SurrogateCodePoint;
    }

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

fn decode(buf: []const u16, offset: usize, len: u2) DecodedCodePoint {
    return switch (len) {
        1 => .{
            .code_point = @as(CodePoint, buf[offset]),
            .len = 1,
        },
        2 => .{
            .code_point = supplementary_offset +
                (@as(CodePoint, buf[offset] - high_surrogate_range_start) << 10) |
                @as(CodePoint, buf[offset + 1] - low_surrogate_range_start),
            .len = 2,
        },
        else => unreachable,
    };
}

pub fn validateU16CodePoint(buf: []const u16, offset: usize) UTF16ValidationError!u2 {
    if (buf.len == 0) {
        return error.ZeroLengthUnits;
    } else if (offset >= buf.len) {
        return error.IndexOutOfBounds;
    }

    const len = try utf16SequenceLen(buf[offset]);

    if (offset + @as(usize, len) > buf.len) {
        return error.IndexOutOfBounds;
    }

    if (len == 2 and !isLowSurrogate(buf[offset + 1])) {
        return error.InvalidLowSurrogate;
    }

    return len;
}

pub fn validateU16CodePointReverse(buf: []const u16) UTF16ValidationError!u2 {
    const len = try utf16SequenceLenReverse(buf, buf.len - 1);
    const start = buf.len - @as(usize, len);
    return try validateU16CodePoint(buf, start);
}

/// Pass entire buffer with offset to avoid reconstructing slice struct in hot paths.
fn validateAndDecodeU16CodePointWithLen(buf: []const u16, offset: usize, len: u2) UTF16ValidationError!DecodedCodePoint {
    if (buf.len == 0) {
        return error.ZeroLengthUnits;
    } else if (offset >= buf.len) {
        return error.IndexOutOfBounds;
    }

    if (offset + @as(usize, len) > buf.len) {
        return error.IndexOutOfBounds;
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
    try validateDecodedScalar(decoded.code_point);
    return decoded;
}

pub fn validateAndDecodeU16CodePoint(buf: []const u16, offset: usize) UTF16ValidationError!DecodedCodePoint {
    const len = try validateU16CodePoint(buf, offset);
    return decode(buf, offset, len);
}

pub fn validateAndDecodeU16CodePointLossy(buf: []const u16, offset: usize) UTF16ValidationLossyError!DecodedCodePointLossy {
    if (buf.len == 0) {
        return UTF16ValidationLossyError.ZeroLengthBytes;
    } else if (offset >= buf.len) {
        return UTF16ValidationLossyError.IndexOutOfBounds;
    }

    const optimistic_len = utf16SequenceLenLossy(buf[offset]);

    if (offset + @as(usize, optimistic_len) > buf.len) {
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
        validateDecodedScalar(decoded.code_point) catch {
            return .{ .code_point = INVALID_CODE_POINT, .len = 2 };
        };

        return .{ .code_point = decoded.code_point, .len = decoded.len };
    }

    // crunch all low surrogates
    if (optimistic_len == 0) {
        var i: usize = 0;

        loop: while (offset + i < buf.len) {
            if (!isLowSurrogate(buf[offset + i])) {
                break :loop;
            }
            i += 1;
        }

        return .{ .code_point = INVALID_CODE_POINT, .len = i };
    }

    unreachable;
}

pub fn validateAndDecodeU16CodePointReverse(buf: []const u16, end_index: usize) UTF16ValidationError!DecodedCodePoint {
    const len = try utf16SequenceLenReverse(buf, end_index);
    const start = end_index + 1 - @as(usize, len);
    return decode(buf, start, len);
}

pub fn decodeCodePointReverse(buf: []const u16, end_index: usize) DecodedCodePoint {
    const len = utf16SequenceLenReverseUnChecked(buf, end_index) catch unreachable;
    const start = end_index + 1 - @as(usize, len);
    return decode(buf, start, len);
}

pub fn decodeCodePoint(buf: []const u16, offset: usize) DecodedCodePoint {
    const len = utf16SequenceLen(buf[offset]) catch unreachable;
    return decode(buf, offset, len);
}

pub const UTF16SliceError = error{
    IndexOutOfBounds,
    InvalidLowSurrogate,
    InvalidHighSurrogate,
};

pub const UTF16ViewIterator = struct {
    index: usize = 0,
    view: *const UTF16View,
    curr: ?CodePoint = null,

    pub fn next(self: *UTF16ViewIterator) ?CodePoint {
        if (self.index >= self.view.data.len) {
            return null;
        }

        const code_point = decodeCodePoint(self.view.data, self.index);
        self.index += @as(usize, code_point.len);
        self.curr = code_point.code_point;

        return self.curr.?;
    }

    pub fn peek(self: *const UTF16ViewIterator) ?CodePoint {
        if (self.index >= self.view.data.len) {
            return null;
        }

        return decodeCodePoint(self.view.data, self.index).code_point;
    }

    pub fn previous(self: *UTF16ViewIterator) ?CodePoint {
        if (self.index == 0) {
            return null;
        }

        const code_point = decodeCodePointReverse(self.view.data, self.index);
        self.index -= @as(usize, code_point.len);
        self.curr = code_point.code_point;

        return self.curr.?;
    }

    pub fn peekPrevious(self: *const UTF16ViewIterator) ?CodePoint {
        if (self.index == 0) {
            return null;
        }

        return decodeCodePointReverse(self.view.data, self.index).code_point;
    }
};

pub const UTF16View = struct {
    data: []const u16,
    endian: Endian,

    pub fn countScalar(self: *const UTF16View) usize {
        var count: usize = 0;
        var i: usize = 0;

        while (i < self.data.len) {
            const unit = self.data[i];

            if (!isHighSurrogate(unit) and !isLowSurrogate(unit)) {
                i += 1;
                count += 1;
                continue;
            }

            const len = utf16SequenceLen(unit) catch unreachable;
            i += @as(usize, len);
            count += 1;
        }

        return count;
    }

    pub fn isBoundary(self: *const UTF16View, index: usize) bool {
        if (index > self.data.len) {
            return false;
        }

        if (index == 0 or index == self.data.len) {
            return true;
        }

        return !isLowSurrogate(self.data[index]);
    }

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
            .endian = self.endian,
        };
    }

    pub fn iter(self: *const UTF16View) UTF16ViewIterator {
        return .{ .view = self };
    }
};

pub fn initUTF16View(data: []const u16, endian: Endian, resultant_unicode_str_len: *usize) UTF16ValidationError!UTF16View {
    var i: usize = 0;
    var scalar_count: usize = 0;

    while (i < data.len) : (scalar_count += 1) {
        const len = try validateU16CodePoint(data, i);
        _ = try validateAndDecodeU16CodePointWithLen(data, i, len);
        i += @as(usize, len);
    }

    resultant_unicode_str_len.* = scalar_count;

    return .{ .data = data, .endian = endian };
}

pub fn initUTF16ViewUnchecked(data: []const u16, endian: Endian) UTF16View {
    return .{ .data = data, .endian = endian };
}

pub fn utf16ViewToUTF16String(view: *const UTF16View, buf: []u21) (UTF16ValidationError || error{BufferTooSmall})!usize {
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

pub fn bufToUTF16StringComptime(comptime units: []const u16) (UTF16ValidationError || error{BufferTooSmall})![initUTF16ViewUnchecked(units, .little).countScalar()]u21 {
    comptime {
        var unicode_str_len: usize = 0;
        const view = try initUTF16View(units, .little, &unicode_str_len);
        var buf: [unicode_str_len]u21 = undefined;
        _ = try utf16ViewToUTF16String(&view, &buf);
        return buf;
    }
}

pub fn bufToUTF16String(allocator: std.mem.Allocator, buf: []const u16, endian: Endian) (UTF16ValidationError || error{ BufferTooSmall, OutOfMemory })![]u21 {
    var unicode_str_len: usize = 0;
    const view = try initUTF16View(buf, endian, &unicode_str_len);
    const out = try allocator.alloc(u21, unicode_str_len);
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
    try std.testing.expectError(error.SurrogateCodePoint, utf16EncodeLen(surrogate_range_start));
    try std.testing.expectError(error.SurrogateCodePoint, utf16EncodeLen(surrogate_range_end));
    try std.testing.expectError(error.CodePointTooLarge, utf16EncodeLen(encoding_range_end + 1));
}

test "validateU16CodePoint: empty, truncated, bad pair" {
    try std.testing.expectError(error.ZeroLengthUnits, validateU16CodePoint(&.{}, 0));
    try std.testing.expectError(error.IndexOutOfBounds, validateU16CodePoint(&.{high_surrogate_range_start}, 0));
    try std.testing.expectError(error.InvalidLowSurrogate, validateU16CodePoint(&.{low_surrogate_range_start}, 0));
    try std.testing.expectError(error.InvalidLowSurrogate, validateU16CodePoint(&.{ high_surrogate_range_start, 0x0041 }, 0));
    _ = try validateU16CodePoint(&.{ 'a', 'Z' }, 0);
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
    try std.testing.expectError(error.SurrogateCodePoint, encodeCodePoint(0xD800, &buf));
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
    const view = initUTF16ViewUnchecked(&[_]u16{ 'e', 0xD83D, 0xDE00 }, .little);
    try std.testing.expectEqual(@as(usize, 2), view.countScalar());

    try std.testing.expect(view.isBoundary(0));
    try std.testing.expect(view.isBoundary(1));
    try std.testing.expect(!view.isBoundary(2));
    try std.testing.expect(view.isBoundary(3));
}

test "UTF16View: iterator next, peek, previous, peekPrevious" {
    var view = initUTF16ViewUnchecked(&[_]u16{ 'a', 'b' }, .little);
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
    _ = try initUTF16View(&[_]u16{ 'x', 0xD83D, 0xDE00 }, .little, &n);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectError(error.InvalidLowSurrogate, initUTF16View(&[_]u16{low_surrogate_range_start}, .little, &n));
}

test "utf16ViewToUTF16String and bufToUTF16String" {
    var n: usize = 0;
    const view = try initUTF16View(&[_]u16{ 0x03B1, 0xD83D, 0xDE00 }, .little, &n);
    var stack: [2]u21 = undefined;
    try std.testing.expectEqual(@as(usize, 2), try utf16ViewToUTF16String(&view, &stack));
    try std.testing.expectEqual(@as(u21, 0x03B1), stack[0]);
    try std.testing.expectEqual(@as(u21, 0x1F600), stack[1]);

    const s = try bufToUTF16String(std.testing.allocator, &[_]u16{'z'}, .little);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqual(@as(usize, 1), s.len);
    try std.testing.expectEqual(@as(u21, 'z'), s[0]);
}

test "hostile: unpaired and swapped surrogates" {
    try std.testing.expectError(error.InvalidLowSurrogate, utf16SequenceLenReverse(&.{low_surrogate_range_start}, 1));
    try std.testing.expectError(error.InvalidHighSurrogate, utf16SequenceLenReverse(&.{high_surrogate_range_start}, 1));
    try std.testing.expectEqual(@as(u2, 1), try validateU16CodePointReverse(&.{ low_surrogate_range_start, 'a' }));
    try std.testing.expectError(error.InvalidHighSurrogate, validateU16CodePointReverse(&.{ 'a', high_surrogate_range_start }));
}

test "hostile: reverse peels trailing BMP after invalid lead" {
    const d = try validateAndDecodeU16CodePointReverse(&.{ high_surrogate_range_start, '(' }, 1);
    try std.testing.expectEqual(@as(CodePoint, '('), d.code_point);
    try std.testing.expectEqual(@as(u2, 1), d.len);

    const tail = try validateAndDecodeU16CodePointReverse(&.{ 0xD83D, 0xD83D, '(' }, 2);
    try std.testing.expectEqual(@as(CodePoint, '('), tail.code_point);
    try std.testing.expectEqual(@as(u2, 1), tail.len);
}

test "hostile matrix: reverse decode errors on isolated malformed buffers" {
    const Case = struct { units: []const u16, expect_err: UTF16ValidationError };
    const cases = [_]Case{
        .{ .units = &.{low_surrogate_range_start}, .expect_err = error.InvalidLowSurrogate },
        .{ .units = &.{high_surrogate_range_start}, .expect_err = error.InvalidHighSurrogate },
        .{ .units = &.{}, .expect_err = error.ZeroLengthUnits },
    };

    for (cases) |c| {
        try std.testing.expectError(c.expect_err, validateAndDecodeU16CodePointReverse(c.units, c.units.len - 1));
    }
}

test "hostile matrix: supplementary boundary U+10FFFF" {
    const max_pair = [_]u16{ 0xDBFF, 0xDFFF };
    try std.testing.expectEqual(@as(CodePoint, 0x10FFFF), (try validateAndDecodeU16CodePointReverse(&max_pair, max_pair.len - 1)).code_point);

    try std.testing.expectError(error.InvalidLowSurrogate, validateAndDecodeU16CodePoint(&.{ 0xDBFF, 0xE000 }, 0));
}

test "hostile matrix: initUTF16View rejects stitched errors" {
    var n: usize = 0;
    try std.testing.expectError(error.InvalidLowSurrogate, initUTF16View(&[_]u16{ 'q', low_surrogate_range_start }, .little, &n));
    try std.testing.expectError(error.InvalidLowSurrogate, initUTF16View(&[_]u16{ high_surrogate_range_start, 'z' }, .little, &n));
}

test "hostile: UTF16View iterator roundtrip on surrogate-heavy string" {
    var units: [6]u16 = undefined;
    _ = try encodeCodePoint(0x1F600, units[0..]);
    units[2] = 0x03B1;
    units[3] = 'q';
    var scalar_count: usize = 0;
    const view = try initUTF16View(units[0..4], .little, &scalar_count);
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

test "hostile matrix: string conversion APIs propagate validation" {
    try std.testing.expectError(error.InvalidLowSurrogate, bufToUTF16String(std.testing.allocator, &[_]u16{low_surrogate_range_start}, .little));
    try std.testing.expectError(error.IndexOutOfBounds, bufToUTF16String(std.testing.allocator, &[_]u16{high_surrogate_range_start}, .little));
}

test "hostile: BMP encode/decode sweep (stride avoids timeout)" {
    var buf: [2]u16 = undefined;
    var cp: u21 = 0;
    while (cp <= 0xFFFF) : (cp += 0x111) {
        if (cp >= surrogate_range_start and cp <= surrogate_range_end) continue;
        const len = try encodeCodePoint(@intCast(cp), &buf);
        const d = try validateAndDecodeU16CodePoint(&buf, 0);
        try std.testing.expectEqual(@as(CodePoint, cp), d.code_point);
        try std.testing.expectEqual(len, d.len);
    }
}

test "hostile: supplementary encode/decode sweep" {
    var buf: [2]u16 = undefined;
    var cp: u21 = min_supplementary_code_point;
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

test "lossy: offset out of bounds" {
    try std.testing.expectError(
        error.IndexOutOfBounds,
        validateAndDecodeU16CodePointLossy(&.{'A'}, 1),
    );
}

test "lossy: zero length buffer" {
    try std.testing.expectError(
        error.ZeroLengthBytes,
        validateAndDecodeU16CodePointLossy(&.{}, 0),
    );
}
