//! This file contains APIs for transcoding text between the UTF-8, UTF-16, and
//! UTF-32 encodings. Each conversion comes in three families:
//!
//! - `xxxLen(...)` computes the exact number of output units required, so the
//!   caller can size a buffer up front.
//! - `xxxBuffer(...)` writes the result into a caller-provided slice and
//!   returns the number of units written.
//! - `xxx(...)` allocates and returns an owned, exactly-sized output slice.
//!
//! The checked variants validate the source encoding and surface the
//! underlying validation/encoding errors; prefer them for untrusted input.
//! The `Lossy` variants instead substitute the Unicode replacement character
//! (U+FFFD) for any malformed sequence and therefore cannot fail validation.

const std = @import("std");
const encoding = @import("encoding");

const CodePoint = encoding.CodePoint;
const utf8 = encoding.utf8;
const utf16 = encoding.utf16;
const utf32 = encoding.utf32;

/// Errors that can arise from transcoding itself, independent of source
/// validation. `Overflow` is returned when the computed output length would
/// exceed `usize`, and is checked before reading the source.
pub const TranscodingError = error{
    Overflow,
};

inline fn ensureMaxExpansion(input_len: usize, comptime max_units_per_input: usize) TranscodingError!void {
    if (input_len > std.math.maxInt(usize) / max_units_per_input) {
        return error.Overflow;
    }
}

/// Returns the number of UTF-16 code units required to transcode the validated
/// UTF-8 `bytes`. Returns a `UTF8ValidationError` when the source is malformed.
///
/// @stable-since: v0.1.0
pub fn utf8ToUtf16Len(bytes: []const u8) utf8.UTF8ValidationError!usize {
    var i: usize = 0;
    var out_len: usize = 0;

    while (i < bytes.len) {
        const decoded = try utf8.validateAndDecodeCodePointBytes(bytes, i);
        out_len += utf16.utf16EncodeLen(decoded.code_point) catch @panic("invalid code point");
        i += decoded.len;
    }

    return out_len;
}

/// Transcodes the validated UTF-8 `bytes` into the caller-provided `out` slice
/// and returns the number of UTF-16 code units written. Returns a
/// `UTF8ValidationError` for malformed source, or a `UTF16EncodeError` (such as
/// `BufferTooSmall`) when `out` cannot hold the result.
///
/// @stable-since: v0.1.0
pub fn utf8ToUtf16Buffer(bytes: []const u8, out: []u16) (utf8.UTF8ValidationError || utf16.UTF16EncodeError)!usize {
    var i: usize = 0;
    var o: usize = 0;

    while (i < bytes.len) {
        const decoded = try utf8.validateAndDecodeCodePointBytes(bytes, i);
        o += try utf16.encodeCodePoint(decoded.code_point, out[o..]);
        i += decoded.len;
    }

    return o;
}

/// Transcodes the validated UTF-8 `bytes` into a freshly allocated,
/// exactly-sized UTF-16 slice owned by the caller. Returns a
/// `UTF8ValidationError` for malformed source, or `error.OutOfMemory` when
/// allocation fails.
///
/// @stable-since: v0.1.0
pub fn utf8ToUtf16(allocator: std.mem.Allocator, bytes: []const u8) (utf8.UTF8ValidationError || utf16.UTF16EncodeError || error{OutOfMemory})![]u16 {
    const out_len = try utf8ToUtf16Len(bytes);
    const out = try allocator.alloc(u16, out_len);
    errdefer allocator.free(out);

    _ = try utf8ToUtf16Buffer(bytes, out);
    return out;
}

/// Returns the number of UTF-8 bytes required to transcode the validated
/// UTF-16 `units`. Returns a `UTF16ValidationError` when the source is
/// malformed, or `error.Overflow` when the result would exceed `usize`.
///
/// @stable-since: v0.1.0
pub fn utf16ToUtf8Len(units: []const u16) (utf16.UTF16ValidationError || utf8.UTF8EncodeError || TranscodingError)!usize {
    try ensureMaxExpansion(units.len, 3);

    var i: usize = 0;
    var out_len: usize = 0;

    while (i < units.len) {
        const decoded = try utf16.validateAndDecodeU16CodePoint(units, i);
        out_len += utf8.utf8EncodeLen(decoded.code_point);
        i += decoded.len;
    }

    return out_len;
}

/// Transcodes the validated UTF-16 `units` into the caller-provided `out` slice
/// and returns the number of UTF-8 bytes written. Returns a
/// `UTF16ValidationError` for malformed source, a `UTF8EncodeError` (such as
/// `BufferTooSmall`) when `out` cannot hold the result, or `error.Overflow`.
///
/// @stable-since: v0.1.0
pub fn utf16ToUtf8Buffer(units: []const u16, out: []u8) (utf16.UTF16ValidationError || utf8.UTF8EncodeError || TranscodingError)!usize {
    try ensureMaxExpansion(units.len, 3);

    var i: usize = 0;
    var o: usize = 0;

    while (i < units.len) {
        const decoded = try utf16.validateAndDecodeU16CodePoint(units, i);
        o += try utf8.encodeCodePoint(decoded.code_point, out[o..]);
        i += decoded.len;
    }

    return o;
}

/// Transcodes the validated UTF-16 `units` into a freshly allocated,
/// exactly-sized UTF-8 slice owned by the caller. Returns a
/// `UTF16ValidationError` for malformed source, `error.Overflow`, or
/// `error.OutOfMemory` when allocation fails.
///
/// @stable-since: v0.1.0
pub fn utf16ToUtf8(allocator: std.mem.Allocator, units: []const u16) (utf16.UTF16ValidationError || utf8.UTF8EncodeError || TranscodingError || error{OutOfMemory})![]u8 {
    const out_len = try utf16ToUtf8Len(units);
    const out = try allocator.alloc(u8, out_len);
    errdefer allocator.free(out);

    _ = try utf16ToUtf8Buffer(units, out);
    return out;
}

/// Returns the number of UTF-32 code units (i.e. scalar values) required to
/// transcode the validated UTF-8 `bytes`. Returns a `UTF8ValidationError` when
/// the source is malformed.
///
/// @stable-since: v0.1.0
pub fn utf8ToUtf32Len(bytes: []const u8) utf8.UTF8ValidationError!usize {
    var i: usize = 0;
    var out_len: usize = 0;

    while (i < bytes.len) {
        const decoded = try utf8.validateAndDecodeCodePointBytes(bytes, i);
        out_len += 1;
        i += decoded.len;
    }

    return out_len;
}

/// Transcodes the validated UTF-8 `bytes` into the caller-provided `out` slice
/// and returns the number of UTF-32 code units written. Returns a
/// `UTF8ValidationError` for malformed source, or a `UTF32EncodeError` (such as
/// `BufferTooSmall`) when `out` cannot hold the result.
///
/// @stable-since: v0.1.0
pub fn utf8ToUtf32Buffer(bytes: []const u8, out: []u32) (utf8.UTF8ValidationError || utf32.UTF32EncodeError)!usize {
    var i: usize = 0;
    var o: usize = 0;

    while (i < bytes.len) {
        const decoded = try utf8.validateAndDecodeCodePointBytes(bytes, i);
        o += try utf32.encodeCodePoint(decoded.code_point, out[o..]);
        i += decoded.len;
    }

    return o;
}

/// Transcodes the validated UTF-8 `bytes` into a freshly allocated,
/// exactly-sized UTF-32 slice owned by the caller. Returns a
/// `UTF8ValidationError` for malformed source, or `error.OutOfMemory` when
/// allocation fails.
///
/// @stable-since: v0.1.0
pub fn utf8ToUtf32(allocator: std.mem.Allocator, bytes: []const u8) (utf8.UTF8ValidationError || utf32.UTF32EncodeError || error{OutOfMemory})![]u32 {
    const out_len = try utf8ToUtf32Len(bytes);
    const out = try allocator.alloc(u32, out_len);
    errdefer allocator.free(out);

    _ = try utf8ToUtf32Buffer(bytes, out);
    return out;
}

/// Returns the number of UTF-8 bytes required to transcode the validated
/// UTF-32 `units`. Returns a `UTF32ValidationError` when the source is
/// malformed, or `error.Overflow` when the result would exceed `usize`.
///
/// @stable-since: v0.1.0
pub fn utf32ToUtf8Len(units: []const u32) (utf32.UTF32ValidationError || utf8.UTF8EncodeError || TranscodingError)!usize {
    try ensureMaxExpansion(units.len, 4);

    var i: usize = 0;
    var out_len: usize = 0;

    while (i < units.len) {
        const decoded = try utf32.validateAndDecodeU32CodePoint(units, i);
        out_len += utf8.utf8EncodeLen(decoded.code_point);
        i += decoded.len;
    }

    return out_len;
}

/// Transcodes the validated UTF-32 `units` into the caller-provided `out` slice
/// and returns the number of UTF-8 bytes written. Returns a
/// `UTF32ValidationError` for malformed source, a `UTF8EncodeError` (such as
/// `BufferTooSmall`) when `out` cannot hold the result, or `error.Overflow`.
///
/// @stable-since: v0.1.0
pub fn utf32ToUtf8Buffer(units: []const u32, out: []u8) (utf32.UTF32ValidationError || utf8.UTF8EncodeError || TranscodingError)!usize {
    try ensureMaxExpansion(units.len, 4);

    var i: usize = 0;
    var o: usize = 0;

    while (i < units.len) {
        const decoded = try utf32.validateAndDecodeU32CodePoint(units, i);
        o += try utf8.encodeCodePoint(decoded.code_point, out[o..]);
        i += decoded.len;
    }

    return o;
}

/// Transcodes the validated UTF-32 `units` into a freshly allocated,
/// exactly-sized UTF-8 slice owned by the caller. Returns a
/// `UTF32ValidationError` for malformed source, `error.Overflow`, or
/// `error.OutOfMemory` when allocation fails.
///
/// @stable-since: v0.1.0
pub fn utf32ToUtf8(allocator: std.mem.Allocator, units: []const u32) (utf32.UTF32ValidationError || utf8.UTF8EncodeError || TranscodingError || error{OutOfMemory})![]u8 {
    const out_len = try utf32ToUtf8Len(units);
    const out = try allocator.alloc(u8, out_len);
    errdefer allocator.free(out);

    _ = try utf32ToUtf8Buffer(units, out);
    return out;
}

/// Returns the number of UTF-32 code units (i.e. scalar values) required to
/// transcode the validated UTF-16 `units`. Returns a `UTF16ValidationError`
/// when the source is malformed.
///
/// @stable-since: v0.1.0
pub fn utf16ToUtf32Len(units: []const u16) utf16.UTF16ValidationError!usize {
    var i: usize = 0;
    var out_len: usize = 0;

    while (i < units.len) {
        const decoded = try utf16.validateAndDecodeU16CodePoint(units, i);
        out_len += 1;
        i += decoded.len;
    }

    return out_len;
}

/// Transcodes the validated UTF-16 `units` into the caller-provided `out` slice
/// and returns the number of UTF-32 code units written. Returns a
/// `UTF16ValidationError` for malformed source, or a `UTF32EncodeError` (such
/// as `BufferTooSmall`) when `out` cannot hold the result.
///
/// @stable-since: v0.1.0
pub fn utf16ToUtf32Buffer(units: []const u16, out: []u32) (utf16.UTF16ValidationError || utf32.UTF32EncodeError)!usize {
    var i: usize = 0;
    var o: usize = 0;

    while (i < units.len) {
        const decoded = try utf16.validateAndDecodeU16CodePoint(units, i);
        o += try utf32.encodeCodePoint(decoded.code_point, out[o..]);
        i += decoded.len;
    }

    return o;
}

/// Transcodes the validated UTF-16 `units` into a freshly allocated,
/// exactly-sized UTF-32 slice owned by the caller. Returns a
/// `UTF16ValidationError` for malformed source, or `error.OutOfMemory` when
/// allocation fails.
///
/// @stable-since: v0.1.0
pub fn utf16ToUtf32(allocator: std.mem.Allocator, units: []const u16) (utf16.UTF16ValidationError || utf32.UTF32EncodeError || error{OutOfMemory})![]u32 {
    const out_len = try utf16ToUtf32Len(units);
    const out = try allocator.alloc(u32, out_len);
    errdefer allocator.free(out);

    _ = try utf16ToUtf32Buffer(units, out);
    return out;
}

/// Returns the number of UTF-16 code units required to transcode the validated
/// UTF-32 `units`. Returns a `UTF32ValidationError` when the source is
/// malformed, or `error.Overflow` when the result would exceed `usize`.
///
/// @stable-since: v0.1.0
pub fn utf32ToUtf16Len(units: []const u32) (utf32.UTF32ValidationError || utf16.UTF16EncodeError || TranscodingError)!usize {
    try ensureMaxExpansion(units.len, 2);

    var i: usize = 0;
    var out_len: usize = 0;

    while (i < units.len) {
        const decoded = try utf32.validateAndDecodeU32CodePoint(units, i);
        out_len += utf16.utf16EncodeLen(decoded.code_point) catch @panic("invalid code point");
        i += decoded.len;
    }

    return out_len;
}

/// Transcodes the validated UTF-32 `units` into the caller-provided `out` slice
/// and returns the number of UTF-16 code units written. Returns a
/// `UTF32ValidationError` for malformed source, a `UTF16EncodeError` (such as
/// `BufferTooSmall`) when `out` cannot hold the result, or `error.Overflow`.
///
/// @stable-since: v0.1.0
pub fn utf32ToUtf16Buffer(units: []const u32, out: []u16) (utf32.UTF32ValidationError || utf16.UTF16EncodeError || TranscodingError)!usize {
    try ensureMaxExpansion(units.len, 2);

    var i: usize = 0;
    var o: usize = 0;

    while (i < units.len) {
        const decoded = try utf32.validateAndDecodeU32CodePoint(units, i);
        o += try utf16.encodeCodePoint(decoded.code_point, out[o..]);
        i += decoded.len;
    }

    return o;
}

/// Transcodes the validated UTF-32 `units` into a freshly allocated,
/// exactly-sized UTF-16 slice owned by the caller. Returns a
/// `UTF32ValidationError` for malformed source, `error.Overflow`, or
/// `error.OutOfMemory` when allocation fails.
///
/// @stable-since: v0.1.0
pub fn utf32ToUtf16(allocator: std.mem.Allocator, units: []const u32) (utf32.UTF32ValidationError || utf16.UTF16EncodeError || TranscodingError || error{OutOfMemory})![]u16 {
    const out_len = try utf32ToUtf16Len(units);
    const out = try allocator.alloc(u16, out_len);
    errdefer allocator.free(out);

    _ = try utf32ToUtf16Buffer(units, out);
    return out;
}

/// Returns the number of UTF-16 code units a lossy transcode of `bytes` would
/// produce, counting one replacement scalar (U+FFFD) per malformed UTF-8
/// sequence. Never fails validation.
///
/// @stable-since: v0.1.0
pub fn utf8ToUtf16LossyLen(bytes: []const u8) usize {
    var out_len: usize = 0;
    var iter = utf8.lossyIterator(bytes);

    while (iter.next()) |code_point| {
        out_len += utf16.utf16EncodeLen(code_point) catch @panic("invalid code point");
    }

    return out_len;
}

/// Lossily transcodes `bytes` into the caller-provided `out` slice, emitting
/// the replacement scalar (U+FFFD) for any malformed UTF-8 sequence, and
/// returns the number of UTF-16 code units written. Only fails with a
/// `UTF16EncodeError` (such as `BufferTooSmall`) when `out` cannot hold the
/// result.
///
/// @stable-since: v0.1.0
pub fn utf8ToUtf16LossyBuffer(bytes: []const u8, out: []u16) utf16.UTF16EncodeError!usize {
    var o: usize = 0;
    var iter = utf8.lossyIterator(bytes);

    while (iter.next()) |code_point| {
        o += try utf16.encodeCodePoint(code_point, out[o..]);
    }

    return o;
}

/// Lossily transcodes `bytes` into a freshly allocated, exactly-sized UTF-16
/// slice owned by the caller, substituting the replacement scalar (U+FFFD) for
/// malformed UTF-8. Only fails with `error.OutOfMemory` when allocation fails.
///
/// @stable-since: v0.1.0
pub fn utf8ToUtf16Lossy(allocator: std.mem.Allocator, bytes: []const u8) (utf16.UTF16EncodeError || error{OutOfMemory})![]u16 {
    const out_len = utf8ToUtf16LossyLen(bytes);
    const out = try allocator.alloc(u16, out_len);
    errdefer allocator.free(out);

    _ = try utf8ToUtf16LossyBuffer(bytes, out);
    return out;
}

/// Returns the number of UTF-8 bytes a lossy transcode of `units` would
/// produce, counting the replacement scalar (U+FFFD) for any malformed UTF-16.
/// Only fails with `error.Overflow` when the result would exceed `usize`.
///
/// @stable-since: v0.1.0
pub fn utf16ToUtf8LossyLen(units: []const u16) TranscodingError!usize {
    try ensureMaxExpansion(units.len, 3);

    var out_len: usize = 0;
    var iter = utf16.lossyIterator(units);

    while (iter.next()) |code_point| {
        out_len += utf8.utf8EncodeLen(code_point);
    }

    return out_len;
}

/// Lossily transcodes `units` into the caller-provided `out` slice, emitting
/// the replacement scalar (U+FFFD) for any malformed UTF-16, and returns the
/// number of UTF-8 bytes written. Fails with a `UTF8EncodeError` (such as
/// `BufferTooSmall`) when `out` cannot hold the result, or `error.Overflow`.
///
/// @stable-since: v0.1.0
pub fn utf16ToUtf8LossyBuffer(units: []const u16, out: []u8) (utf8.UTF8EncodeError || TranscodingError)!usize {
    try ensureMaxExpansion(units.len, 3);

    var o: usize = 0;
    var iter = utf16.lossyIterator(units);

    while (iter.next()) |code_point| {
        o += try utf8.encodeCodePoint(code_point, out[o..]);
    }

    return o;
}

/// Lossily transcodes `units` into a freshly allocated, exactly-sized UTF-8
/// slice owned by the caller, substituting the replacement scalar (U+FFFD) for
/// malformed UTF-16. Fails with `error.Overflow` or `error.OutOfMemory`.
///
/// @stable-since: v0.1.0
pub fn utf16ToUtf8Lossy(allocator: std.mem.Allocator, units: []const u16) (utf8.UTF8EncodeError || TranscodingError || error{OutOfMemory})![]u8 {
    const out_len = try utf16ToUtf8LossyLen(units);
    const out = try allocator.alloc(u8, out_len);
    errdefer allocator.free(out);

    _ = try utf16ToUtf8LossyBuffer(units, out);
    return out;
}

/// Returns the number of UTF-8 bytes a lossy transcode of `units` would
/// produce, counting the replacement scalar (U+FFFD) for any value that is not
/// a valid scalar. Only fails with `error.Overflow` when the result would
/// exceed `usize`.
///
/// @stable-since: v0.1.0
pub fn utf32ToUtf8LossyLen(units: []const u32) TranscodingError!usize {
    try ensureMaxExpansion(units.len, 4);

    var out_len: usize = 0;
    var iter = utf32.lossyIterator(units);

    while (iter.next()) |code_point| {
        out_len += utf8.utf8EncodeLen(code_point);
    }

    return out_len;
}

/// Lossily transcodes `units` into the caller-provided `out` slice, emitting
/// the replacement scalar (U+FFFD) for any value that is not a valid scalar,
/// and returns the number of UTF-8 bytes written. Fails with a `UTF8EncodeError`
/// (such as `BufferTooSmall`) when `out` cannot hold the result, or
/// `error.Overflow`.
///
/// @stable-since: v0.1.0
pub fn utf32ToUtf8LossyBuffer(units: []const u32, out: []u8) (utf8.UTF8EncodeError || TranscodingError)!usize {
    try ensureMaxExpansion(units.len, 4);

    var o: usize = 0;
    var iter = utf32.lossyIterator(units);

    while (iter.next()) |code_point| {
        o += try utf8.encodeCodePoint(code_point, out[o..]);
    }

    return o;
}

/// Lossily transcodes `units` into a freshly allocated, exactly-sized UTF-8
/// slice owned by the caller, substituting the replacement scalar (U+FFFD) for
/// any value that is not a valid scalar. Fails with `error.Overflow` or
/// `error.OutOfMemory`.
///
/// @stable-since: v0.1.0
pub fn utf32ToUtf8Lossy(allocator: std.mem.Allocator, units: []const u32) (utf8.UTF8EncodeError || TranscodingError || error{OutOfMemory})![]u8 {
    const out_len = try utf32ToUtf8LossyLen(units);
    const out = try allocator.alloc(u8, out_len);
    errdefer allocator.free(out);

    _ = try utf32ToUtf8LossyBuffer(units, out);
    return out;
}

test "utf8 to utf16 and back" {
    const input = "a€😀";
    var units: [4]u16 = undefined;

    const units_len = try utf8ToUtf16Buffer(input, &units);
    try std.testing.expectEqual(@as(usize, 4), units_len);
    try std.testing.expectEqualSlices(u16, &.{ 'a', 0x20AC, 0xD83D, 0xDE00 }, units[0..units_len]);

    var bytes: [input.len]u8 = undefined;
    const bytes_len = try utf16ToUtf8Buffer(units[0..units_len], &bytes);
    try std.testing.expectEqualStrings(input, bytes[0..bytes_len]);
}

test "utf8 to utf32 and back" {
    const input = "a€😀";
    var units: [3]u32 = undefined;

    const units_len = try utf8ToUtf32Buffer(input, &units);
    try std.testing.expectEqual(@as(usize, 3), units_len);
    try std.testing.expectEqualSlices(u32, &.{ 'a', 0x20AC, 0x1F600 }, units[0..units_len]);

    var bytes: [input.len]u8 = undefined;
    const bytes_len = try utf32ToUtf8Buffer(units[0..units_len], &bytes);
    try std.testing.expectEqualStrings(input, bytes[0..bytes_len]);
}

test "utf16 and utf32 conversion" {
    const utf16_units = [_]u16{ 'a', 0xD83D, 0xDE00 };
    var utf32_units: [2]u32 = undefined;

    const utf32_len = try utf16ToUtf32Buffer(&utf16_units, &utf32_units);
    try std.testing.expectEqualSlices(u32, &.{ 'a', 0x1F600 }, utf32_units[0..utf32_len]);

    var roundtrip: [3]u16 = undefined;
    const utf16_len = try utf32ToUtf16Buffer(utf32_units[0..utf32_len], &roundtrip);
    try std.testing.expectEqualSlices(u16, &utf16_units, roundtrip[0..utf16_len]);
}

test "checked transcoding rejects malformed source and small output" {
    var small_utf16: [1]u16 = undefined;
    try std.testing.expectError(error.BufferTooSmall, utf8ToUtf16Buffer("😀", &small_utf16));

    var utf16_out: [4]u16 = undefined;
    try std.testing.expectError(error.OverlongEncoding, utf8ToUtf16Buffer(&.{ 0xE0, 0x80, 0x80 }, &utf16_out));

    var utf8_out: [4]u8 = undefined;
    try std.testing.expectError(error.InvalidLowSurrogate, utf16ToUtf8Buffer(&.{0xDE00}, &utf8_out));
    try std.testing.expectError(error.CodePointTooLarge, utf32ToUtf8Buffer(&.{0x110000}, &utf8_out));
}

test "lossy transcoding emits replacement scalar in target encoding" {
    const malformed_utf8 = [_]u8{ 'A', 0xF0, 0x9F, 0x92, '(', 'B' };
    var utf16_out: [4]u16 = undefined;
    const utf16_len = try utf8ToUtf16LossyBuffer(&malformed_utf8, &utf16_out);
    try std.testing.expectEqualSlices(u16, &.{ 'A', encoding.INVALID_CODE_POINT, '(', 'B' }, utf16_out[0..utf16_len]);

    const malformed_utf16 = [_]u16{ 'A', 0xDE00, 'B' };
    var utf8_out: [8]u8 = undefined;
    const utf8_len = try utf16ToUtf8LossyBuffer(&malformed_utf16, &utf8_out);
    try std.testing.expectEqualStrings("A\u{FFFD}B", utf8_out[0..utf8_len]);

    const malformed_utf32 = [_]u32{ 'A', 0xD800, 'B' };
    const utf32_utf8_len = try utf32ToUtf8LossyBuffer(&malformed_utf32, &utf8_out);
    try std.testing.expectEqualStrings("A\u{FFFD}B", utf8_out[0..utf32_utf8_len]);
}

test "scalar boundaries roundtrip through every transcoding path" {
    const scalars = [_]u32{
        0x0000,
        0x007F,
        0x0080,
        0x07FF,
        0x0800,
        0xD7FF,
        0xE000,
        0xFFFF,
        0x10000,
        0x10FFFF,
    };

    var utf8_buf: [scalars.len * 4]u8 = undefined;
    const utf8_len = try utf32ToUtf8Buffer(&scalars, &utf8_buf);

    var back_from_utf8: [scalars.len]u32 = undefined;
    const back_from_utf8_len = try utf8ToUtf32Buffer(utf8_buf[0..utf8_len], &back_from_utf8);
    try std.testing.expectEqualSlices(u32, &scalars, back_from_utf8[0..back_from_utf8_len]);

    var utf16_buf: [scalars.len * 2]u16 = undefined;
    const utf16_len = try utf32ToUtf16Buffer(&scalars, &utf16_buf);

    var back_from_utf16: [scalars.len]u32 = undefined;
    const back_from_utf16_len = try utf16ToUtf32Buffer(utf16_buf[0..utf16_len], &back_from_utf16);
    try std.testing.expectEqualSlices(u32, &scalars, back_from_utf16[0..back_from_utf16_len]);

    var utf8_from_utf16: [scalars.len * 4]u8 = undefined;
    const utf8_from_utf16_len = try utf16ToUtf8Buffer(utf16_buf[0..utf16_len], &utf8_from_utf16);
    try std.testing.expectEqualSlices(u8, utf8_buf[0..utf8_len], utf8_from_utf16[0..utf8_from_utf16_len]);

    var utf16_from_utf8: [scalars.len * 2]u16 = undefined;
    const utf16_from_utf8_len = try utf8ToUtf16Buffer(utf8_buf[0..utf8_len], &utf16_from_utf8);
    try std.testing.expectEqualSlices(u16, utf16_buf[0..utf16_len], utf16_from_utf8[0..utf16_from_utf8_len]);
}

test "checked UTF-8 transcoding rejects malformed matrix" {
    const Case = struct {
        bytes: []const u8,
        expect_err: anyerror,
    };
    const cases = [_]Case{
        .{ .bytes = &.{0x80}, .expect_err = error.InvalidByteSequence },
        .{ .bytes = &.{ 0x80, 0x80, 0x80 }, .expect_err = error.InvalidByteSequence },
        .{ .bytes = &.{ 0xC0, 0x80 }, .expect_err = error.InvalidByteSequence },
        .{ .bytes = &.{ 0xC1, 0xBF }, .expect_err = error.InvalidByteSequence },
        .{ .bytes = &.{ 0xE0, 0x80, 0x80 }, .expect_err = error.OverlongEncoding },
        .{ .bytes = &.{ 0xED, 0xA0, 0x80 }, .expect_err = error.SurrogateCodePoint },
        .{ .bytes = &.{ 0xF0, 0x80, 0x80, 0x80 }, .expect_err = error.OverlongEncoding },
        .{ .bytes = &.{ 0xF4, 0x90, 0x80, 0x80 }, .expect_err = error.CodePointTooLarge },
        .{ .bytes = &.{ 0xF5, 0x80, 0x80, 0x80 }, .expect_err = error.InvalidByteSequence },
        .{ .bytes = &.{ 0xE2, 0x82 }, .expect_err = error.IndexOutOfBounds },
        .{ .bytes = &.{ 0xF0, 0x9F, 0x92 }, .expect_err = error.IndexOutOfBounds },
    };

    var utf16_out: [16]u16 = undefined;
    var utf32_out: [16]u32 = undefined;

    for (cases) |c| {
        try std.testing.expectError(c.expect_err, utf8ToUtf16Buffer(c.bytes, &utf16_out));
        try std.testing.expectError(c.expect_err, utf8ToUtf32Buffer(c.bytes, &utf32_out));
    }
}

test "lossy UTF-8 transcoding over all byte values emits valid UTF-16 and UTF-8" {
    var bytes: [256]u8 = undefined;
    for (&bytes, 0..) |*byte, i| {
        byte.* = @intCast(i);
    }

    var utf16_out: [512]u16 = undefined;
    const utf16_len = try utf8ToUtf16LossyBuffer(&bytes, &utf16_out);

    var scalar_count: usize = 0;
    _ = try utf16.initUTF16View(utf16_out[0..utf16_len], &scalar_count);

    var utf8_out: [1024]u8 = undefined;
    const utf8_len = try utf16ToUtf8Buffer(utf16_out[0..utf16_len], &utf8_out);
    var utf8_scalar_count: usize = 0;
    _ = try utf8.initUTF8View(utf8_out[0..utf8_len], &utf8_scalar_count);
}

test "lossy UTF-16 dense surrogate garbage emits valid UTF-8" {
    const units = [_]u16{
        0xD800,
        0xD801,
        0xDC00,
        'A',
        0xDBFF,
        0xDFFF,
        0xDFFF,
        0xD800,
        'B',
    };

    var utf8_out: [64]u8 = undefined;
    const utf8_len = try utf16ToUtf8LossyBuffer(&units, &utf8_out);

    var scalar_count: usize = 0;
    _ = try utf8.initUTF8View(utf8_out[0..utf8_len], &scalar_count);
    try std.testing.expect(scalar_count > 0);
}

test "lossy UTF-32 huge values emit valid UTF-8" {
    const units = [_]u32{
        0,
        0xD800,
        0xDFFF,
        0x10FFFF,
        0x110000,
        0x7FFF_FFFF,
        0xFFFF_FFFF,
    };

    var utf8_out: [64]u8 = undefined;
    const utf8_len = try utf32ToUtf8LossyBuffer(&units, &utf8_out);

    var scalar_count: usize = 0;
    _ = try utf8.initUTF8View(utf8_out[0..utf8_len], &scalar_count);
    try std.testing.expectEqual(units.len, scalar_count);
}

test "transcoding buffer-too-small checks across target encodings" {
    var empty_u8: [0]u8 = .{};
    var empty_u16: [0]u16 = .{};
    var empty_u32: [0]u32 = .{};
    var one_u16: [1]u16 = undefined;

    try std.testing.expectError(error.BufferTooSmall, utf16ToUtf8Buffer(&.{'A'}, &empty_u8));
    try std.testing.expectError(error.BufferTooSmall, utf32ToUtf8Buffer(&.{'A'}, &empty_u8));
    try std.testing.expectError(error.BufferTooSmall, utf8ToUtf16Buffer("A", &empty_u16));
    try std.testing.expectError(error.BufferTooSmall, utf32ToUtf16Buffer(&.{0x1F600}, &one_u16));
    try std.testing.expectError(error.BufferTooSmall, utf8ToUtf32Buffer("A", &empty_u32));
    try std.testing.expectError(error.BufferTooSmall, utf16ToUtf32Buffer(&.{'A'}, &empty_u32));
}

test "transcoding rejects theoretical output length overflow before reading source" {
    const huge_u16_ptr: [*]const u16 = @ptrFromInt(0x1000);
    const huge_u32_ptr: [*]const u32 = @ptrFromInt(0x1000);

    var huge_utf16_to_utf8_len: usize = std.math.maxInt(usize) / 3 + 1;
    var huge_utf32_to_utf8_len: usize = std.math.maxInt(usize) / 4 + 1;
    var huge_utf32_to_utf16_len: usize = std.math.maxInt(usize) / 2 + 1;
    huge_utf16_to_utf8_len += 0;
    huge_utf32_to_utf8_len += 0;
    huge_utf32_to_utf16_len += 0;

    const huge_utf16_to_utf8 = huge_u16_ptr[0..huge_utf16_to_utf8_len];
    const huge_utf32_to_utf8 = huge_u32_ptr[0..huge_utf32_to_utf8_len];
    const huge_utf32_to_utf16 = huge_u32_ptr[0..huge_utf32_to_utf16_len];

    var empty_u8: [0]u8 = .{};
    var empty_u16: [0]u16 = .{};

    try std.testing.expectError(error.Overflow, utf16ToUtf8Len(huge_utf16_to_utf8));
    try std.testing.expectError(error.Overflow, utf16ToUtf8Buffer(huge_utf16_to_utf8, &empty_u8));
    try std.testing.expectError(error.Overflow, utf16ToUtf8LossyLen(huge_utf16_to_utf8));
    try std.testing.expectError(error.Overflow, utf16ToUtf8LossyBuffer(huge_utf16_to_utf8, &empty_u8));

    try std.testing.expectError(error.Overflow, utf32ToUtf8Len(huge_utf32_to_utf8));
    try std.testing.expectError(error.Overflow, utf32ToUtf8Buffer(huge_utf32_to_utf8, &empty_u8));
    try std.testing.expectError(error.Overflow, utf32ToUtf8LossyLen(huge_utf32_to_utf8));
    try std.testing.expectError(error.Overflow, utf32ToUtf8LossyBuffer(huge_utf32_to_utf8, &empty_u8));

    try std.testing.expectError(error.Overflow, utf32ToUtf16Len(huge_utf32_to_utf16));
    try std.testing.expectError(error.Overflow, utf32ToUtf16Buffer(huge_utf32_to_utf16, &empty_u16));
}
