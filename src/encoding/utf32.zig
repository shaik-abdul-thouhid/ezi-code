const std = @import("std");
const utils = @import("utils");
const encoding = @import("root.zig");

const CodePoint = encoding.CodePoint;

const encoding_range_end: CodePoint = 0x10FFFF;

pub const Endian = utils.Endian;

pub const surrogate_range_start: u32 = 0xD800;
pub const surrogate_range_end: u32 = 0xDFFF;

pub const min_scalar: CodePoint = 0x0000;
pub const max_scalar: CodePoint = 0x10FFFF;

const DecodedCodePoint = struct {
    code_point: CodePoint,
    len: u1,
};

pub const UTF32ValidationError = error{
    ZeroLengthUnits,
    IndexOutOfBounds,
    SurrogateCodePoint,
    CodePointTooLarge,
};

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

pub fn utf32SequenceLen(c32: u32) UTF32ValidationError!u1 {
    _ = try validateStoredUnit(c32);
    return 1;
}

/// Buffer must end at the last code unit of the scalar (`buf.len - 1`).
pub fn utf32SequenceLenReverse(buf: []const u32) UTF32ValidationError!u1 {
    if (buf.len == 0) {
        return error.ZeroLengthUnits;
    }
    _ = try validateStoredUnit(buf[buf.len - 1]);
    return 1;
}

pub fn utf32EncodeLen(code_point: CodePoint) UTF32EncodeError!u1 {
    if (code_point > encoding_range_end) {
        return error.CodePointTooLarge;
    }

    if (code_point >= surrogate_range_start and code_point <= surrogate_range_end) {
        return error.SurrogateCodePoint;
    }

    return 1;
}

pub fn encodeCodePoint(code_point: CodePoint, buf: []u32) UTF32EncodeError!u1 {
    const len = try utf32EncodeLen(code_point);

    if (buf.len < len) {
        return error.BufferTooSmall;
    }

    buf[0] = @intCast(code_point);
    return len;
}

pub fn validateU32CodePoint(buf: []const u32, offset: usize) UTF32ValidationError!u1 {
    if (buf.len == 0) {
        return error.ZeroLengthUnits;
    } else if (offset >= buf.len) {
        return error.IndexOutOfBounds;
    }

    _ = try validateStoredUnit(buf[offset]);
    return 1;
}

pub fn validateU32CodePointReverse(buf: []const u32) UTF32ValidationError!u1 {
    return try utf32SequenceLenReverse(buf);
}

/// Pass entire buffer with offset to avoid reconstructing slice struct in hot paths.
pub fn validateAndDecodeU32CodePointWithLen(buf: []const u32, offset: usize, len: u1) UTF32ValidationError!DecodedCodePoint {
    if (buf.len == 0) {
        return error.ZeroLengthUnits;
    } else if (offset >= buf.len) {
        return error.IndexOutOfBounds;
    }

    if (offset + @as(usize, len) > buf.len) {
        return error.IndexOutOfBounds;
    }

    if (len != 1) {
        return error.IndexOutOfBounds;
    }

    const code_point = try validateStoredUnit(buf[offset]);
    return .{ .code_point = code_point, .len = 1 };
}

pub fn validateAndDecodeU32CodePoint(buf: []const u32, offset: usize) UTF32ValidationError!DecodedCodePoint {
    const len = try validateU32CodePoint(buf, offset);
    return validateAndDecodeU32CodePointWithLen(buf, offset, len);
}

pub fn validateAndDecodeU32CodePointReverse(buf: []const u32) UTF32ValidationError!DecodedCodePoint {
    const len = try utf32SequenceLenReverse(buf);
    const start = buf.len - @as(usize, len);
    return validateAndDecodeU32CodePointWithLen(buf, start, len);
}

pub fn decodeCodePointReverse(buf: []const u32) DecodedCodePoint {
    const len = utf32SequenceLenReverse(buf) catch unreachable;
    const start = buf.len - @as(usize, len);
    return .{
        .code_point = @intCast(buf[start]),
        .len = len,
    };
}

pub fn bufToUTF32CodePoint(buf: []const u32, offset: usize) DecodedCodePoint {
    return .{
        .code_point = @intCast(buf[offset]),
        .len = 1,
    };
}

pub fn bufToUTF32CodePointChecked(buf: []const u32, offset: usize) UTF32ValidationError!DecodedCodePoint {
    return validateAndDecodeU32CodePoint(buf, offset);
}

pub fn bufToUTF32CodePointReverseChecked(buf: []const u32) UTF32ValidationError!DecodedCodePoint {
    return validateAndDecodeU32CodePointReverse(buf);
}

pub const UTF32SliceError = error{
    IndexOutOfBounds,
};

pub const UTF32ViewIterator = struct {
    index: usize = 0,
    view: *const UTF32View,
    curr: ?CodePoint = null,

    pub fn next(self: *UTF32ViewIterator) ?CodePoint {
        if (self.index >= self.view.data.len) {
            return null;
        }

        const code_point = bufToUTF32CodePoint(self.view.data, self.index);
        self.index += @as(usize, code_point.len);
        self.curr = code_point.code_point;

        return self.curr.?;
    }

    pub fn peek(self: *const UTF32ViewIterator) ?CodePoint {
        if (self.index >= self.view.data.len) {
            return null;
        }

        return bufToUTF32CodePoint(self.view.data, self.index).code_point;
    }

    pub fn previous(self: *UTF32ViewIterator) ?CodePoint {
        if (self.index == 0) {
            return null;
        }

        const code_point = decodeCodePointReverse(self.view.data[0..self.index]);
        self.index -= @as(usize, code_point.len);
        self.curr = code_point.code_point;

        return self.curr.?;
    }

    pub fn peekPrevious(self: *const UTF32ViewIterator) ?CodePoint {
        if (self.index == 0) {
            return null;
        }

        return decodeCodePointReverse(self.view.data[0..self.index]).code_point;
    }
};

pub const UTF32View = struct {
    data: []const u32,
    endian: Endian,

    pub fn countScalar(self: *const UTF32View) usize {
        return self.data.len;
    }

    pub fn isBoundary(self: *const UTF32View, index: usize) bool {
        return index <= self.data.len;
    }

    pub fn sliceScalars(self: *const UTF32View, start_scalar: usize, end_scalar: usize) UTF32SliceError!UTF32View {
        if (start_scalar > end_scalar or end_scalar > self.data.len) {
            return error.IndexOutOfBounds;
        }

        return .{
            .data = self.data[start_scalar..end_scalar],
            .endian = self.endian,
        };
    }

    pub fn iter(self: *const UTF32View) UTF32ViewIterator {
        return .{ .view = self };
    }
};

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

pub fn initUTF32ViewUnchecked(data: []const u32, endian: Endian) UTF32View {
    return .{ .data = data, .endian = endian };
}

pub fn utf32ViewToUTF32String(view: *const UTF32View, buf: []u21) (UTF32ValidationError || error{BufferTooSmall})!usize {
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

pub fn bufToUTF32StringComptime(comptime units: []const u32) (UTF32ValidationError || error{BufferTooSmall})![initUTF32ViewUnchecked(units, .little).countScalar()]u21 {
    comptime {
        var unicode_str_len: usize = 0;
        const view = try initUTF32View(units, .little, &unicode_str_len);
        var buf: [unicode_str_len]u21 = undefined;
        _ = try utf32ViewToUTF32String(&view, &buf);
        return buf;
    }
}

pub fn bufToUTF32String(allocator: std.mem.Allocator, buf: []const u32, endian: Endian) (UTF32ValidationError || error{ BufferTooSmall, OutOfMemory })![]u21 {
    var unicode_str_len: usize = 0;
    const view = try initUTF32View(buf, endian, &unicode_str_len);
    const out = try allocator.alloc(u21, unicode_str_len);
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
    try std.testing.expectError(error.SurrogateCodePoint, bufToUTF32CodePointChecked(&.{surrogate_range_start}, 0));
    try std.testing.expectError(error.CodePointTooLarge, bufToUTF32CodePointChecked(&.{0x110000}, 0));
}

test "bufToUTF32CodePointChecked and ReverseChecked agree on valid scalars" {
    const units = [_]u32{ 'a', 0x03B1, 0x1F600, 0xD7FF, 0xE000, 0x10FFFF };
    var i: usize = 0;
    while (i < units.len) {
        const fwd = try bufToUTF32CodePointChecked(&units, i);
        const prefix = units[0 .. i + fwd.len];
        const rev = try bufToUTF32CodePointReverseChecked(prefix);
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
    var stack: [2]u21 = undefined;
    try std.testing.expectEqual(@as(usize, 2), try utf32ViewToUTF32String(&view, &stack));
    try std.testing.expectEqual(@as(u21, 0x03B1), stack[0]);
    try std.testing.expectEqual(@as(u21, 0x1F600), stack[1]);

    const s = try bufToUTF32String(std.testing.allocator, &[_]u32{'z'}, .little);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqual(@as(usize, 1), s.len);
    try std.testing.expectEqual(@as(u21, 'z'), s[0]);
}

test "hostile: high-bit garbage scalars in buffer" {
    const garbage = [_]u32{ 0x80000000, 0x00110000, 0x00FFFFFF, 0xFFFFFFFF };
    for (garbage) |unit| {
        try std.testing.expectError(error.CodePointTooLarge, utf32SequenceLen(unit));
        try std.testing.expectError(error.CodePointTooLarge, validateAndDecodeU32CodePoint(&.{unit}, 0));
    }
}

test "hostile: surrogate scalars stored as UTF-32 code units" {
    var cp: u32 = surrogate_range_start;
    while (cp <= surrogate_range_end) : (cp += 0x111) {
        try std.testing.expectError(error.SurrogateCodePoint, utf32SequenceLen(cp));
        try std.testing.expectError(error.SurrogateCodePoint, validateAndDecodeU32CodePointReverse(&.{cp}));
    }
}

test "hostile matrix: reverse decode errors on isolated malformed buffers" {
    const Case = struct { units: []const u32, expect_err: UTF32ValidationError };
    const cases = [_]Case{
        .{ .units = &.{surrogate_range_start}, .expect_err = error.SurrogateCodePoint },
        .{ .units = &.{0x110000}, .expect_err = error.CodePointTooLarge },
        .{ .units = &.{}, .expect_err = error.ZeroLengthUnits },
    };

    for (cases) |c| {
        try std.testing.expectError(c.expect_err, validateAndDecodeU32CodePointReverse(c.units));
        try std.testing.expectError(c.expect_err, bufToUTF32CodePointReverseChecked(c.units));
    }
}

test "hostile matrix: supplementary boundary U+10FFFF" {
    const max_unit = [_]u32{0x10FFFF};
    try std.testing.expectEqual(@as(CodePoint, 0x10FFFF), (try validateAndDecodeU32CodePointReverse(&max_unit)).code_point);

    try std.testing.expectError(error.CodePointTooLarge, validateAndDecodeU32CodePoint(&.{0x110000}, 0));
}

test "hostile matrix: initUTF32View rejects stitched errors" {
    var n: usize = 0;
    try std.testing.expectError(error.SurrogateCodePoint, initUTF32View(&[_]u32{ 'q', surrogate_range_start }, .little, &n));
    try std.testing.expectError(error.CodePointTooLarge, initUTF32View(&[_]u32{ 'z', 0x110000 }, .little, &n));
}

test "hostile: UTF32View iterator roundtrip on mixed string" {
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

test "hostile matrix: string conversion APIs propagate validation" {
    try std.testing.expectError(error.SurrogateCodePoint, bufToUTF32String(std.testing.allocator, &[_]u32{surrogate_range_start}, .little));
    try std.testing.expectError(error.CodePointTooLarge, bufToUTF32String(std.testing.allocator, &[_]u32{0x110000}, .little));
}

test "hostile: utf32ViewToUTF32String buffer too small path" {
    var n: usize = 0;
    const view = try initUTF32View(&[_]u32{ 'a', 'b' }, .little, &n);
    var tiny: [1]u21 = undefined;
    try std.testing.expectError(error.BufferTooSmall, utf32ViewToUTF32String(&view, &tiny));
}

test "hostile matrix: validateAndDecodeU32CodePointWithLen length contract" {
    const unit = [_]u32{'x'};
    try std.testing.expectError(error.IndexOutOfBounds, validateAndDecodeU32CodePointWithLen(&unit, 0, 0));
    _ = try validateAndDecodeU32CodePointWithLen(&unit, 0, 1);

    try std.testing.expectError(error.IndexOutOfBounds, validateAndDecodeU32CodePointWithLen(&unit, 1, 1));
}

test "hostile matrix: forward APIs agree on prefix walks" {
    const units = [_]u32{ 'Z', 0x20AC, 0x10348 };
    var i: usize = 0;
    while (i < units.len) {
        const a = try validateAndDecodeU32CodePoint(&units, i);
        const b = try bufToUTF32CodePointChecked(&units, i);
        try std.testing.expectEqual(a.code_point, b.code_point);
        try std.testing.expectEqual(a.len, b.len);
        i += @as(usize, a.len);
    }
}

test "hostile: BMP encode/decode sweep (stride avoids timeout)" {
    var buf: [1]u32 = undefined;
    var cp: u21 = 0;
    while (cp <= 0xFFFF) : (cp += 0x111) {
        if (cp >= surrogate_range_start and cp <= surrogate_range_end) continue;
        const len = try encodeCodePoint(@intCast(cp), &buf);
        const d = try validateAndDecodeU32CodePoint(&buf, 0);
        try std.testing.expectEqual(@as(CodePoint, cp), d.code_point);
        try std.testing.expectEqual(len, d.len);
    }
}

test "hostile: supplementary encode/decode sweep" {
    var buf: [1]u32 = undefined;
    var cp: u21 = 0x10000;
    while (cp <= max_scalar) : (cp += 0x11111) {
        const len = try encodeCodePoint(cp, &buf);
        const d = try validateAndDecodeU32CodePoint(&buf, 0);
        try std.testing.expectEqual(cp, d.code_point);
        try std.testing.expectEqual(len, d.len);
    }
}

test "hostile matrix: compile-time initUTF32View rejects illegal units" {
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

test "hostile: reverse always peels exactly one code unit on valid tail" {
    const units = [_]u32{ 0xD7FF, 0xE000, 0x10FFFF };
    var off = units.len;
    while (off > 0) {
        const d = try bufToUTF32CodePointReverseChecked(units[0..off]);
        try std.testing.expectEqual(@as(u1, 1), d.len);
        off -= 1;
    }
}

test "hostile matrix: sliceScalars + utf32ViewToUTF32String on emoji-heavy string" {
    const units = [_]u32{ 0x1F600, 0x03B1, 'q', 0x10FFFF };
    var n: usize = 0;
    const view = try initUTF32View(&units, .little, &n);
    const slice = try view.sliceScalars(1, 3);
    var out: [2]u21 = undefined;
    try std.testing.expectEqual(@as(usize, 2), try utf32ViewToUTF32String(&slice, &out));
    try std.testing.expectEqual(@as(u21, 0x03B1), out[0]);
    try std.testing.expectEqual(@as(u21, 'q'), out[1]);
}
