//! This file contains APIs for encoding and decoding utf8 codepoints from
//! `[]const u8`. Contains functions for validating, Optimistic lengths,
//! traversal, decoding, encoding, and converting to []CodePoint slice.
//!
//! - "Optimistic length" returned by `xxxLen(...)` functions is the
//!   expected number of bytes to consume to decode a valid CodePoint.
//!   It reflects the length claimed by the lead byte; continuation bytes
//!   have not been validated yet.
//! - Lossy `xxxLen(...)` variants return 0 when the byte is invalid or
//!   the expected length cannot be inferred from it.

const std = @import("std");
const encoding = @import("root.zig");

const CodePoint = encoding.CodePoint;
const INVALID_CODE_POINT = encoding.INVALID_CODE_POINT;

const encoding_range_start = 0x0000;
const encoding_range_end = 0x10FFFF;

const MAX_ASCII = encoding.MAX_ASCII;

// Surrogate range
const surrogate_range_start = 0xD800;
const surrogate_range_end = 0xDFFF;

// Continuation byte
const continuation_sequence = 0b1000_0000;
const continuation_sequence_mask = 0b1100_0000;
const continuation_payload_mask = 0b0011_1111;

// 2-byte sequence
const two_byte_start_sequence_range_start = 0xC2;
const two_byte_start_sequence_range_end = 0xDF;
const two_byte_lead_byte_prefix = 0b1100_0000;
const two_byte_payload_mask = 0b0001_1111;

// 3-byte sequence
const three_byte_start_sequence_range_start = 0xE0;
const three_byte_start_sequence_range_end = 0xEF;
const three_byte_payload_mask = 0b0000_1111;

// 4-byte sequence
const four_byte_start_sequence_range_start = 0xF0;
const four_byte_start_sequence_range_end = 0xF4;
const four_byte_payload_mask = 0b0000_0111;

const min_two_byte_code_point = 0x80;
const max_two_byte_code_point = 0x7FF;
const min_three_byte_code_point = 0x800;
const max_three_byte_code_point = 0xFFFF;
const min_four_byte_code_point = 0x10000;
const max_four_byte_code_point = 0x10FFFF;

const UTF8_ACCEPT: u32 = 0;
const UTF8_REJECT: u32 = 1;

const DecodeResult = enum(u2) { accept, reject, incomplete };

const hoehrmann_utf8_decode_table = [_]u8{
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 00..1f
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 20..3f
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 40..5f
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 60..7f
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, // 80..9f
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, // a0..bf
    8, 8, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, // c0..df
    0xa, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x4, 0x3, 0x3, // e0..ef
    0xb, 0x6, 0x6, 0x6, 0x5, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, // f0..ff
    0x0, 0x1, 0x2, 0x3, 0x5, 0x8, 0x7, 0x1, 0x1, 0x1, 0x4, 0x6, 0x1, 0x1, 0x1, 0x1, // s0..s0
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1, 1, // s1..s2
    1, 2, 1, 1, 1, 1, 1, 2, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, // s3..s4
    1, 2, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 3, 1, 3, 1, 1, 1, 1, 1, 1, // s5..s6
    1, 3, 1, 1, 1, 1, 1, 3, 1, 3, 1, 1, 1, 1, 1, 1, 1, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, // s7..s8
};

inline fn decodeByte(state: *u32, code_point: *CodePoint, byte: u8) DecodeResult {
    const t = hoehrmann_utf8_decode_table[byte];

    code_point.* = if (state.* != UTF8_ACCEPT)
        (byte & 0x3f) | (code_point.* << 6)
    else
        (@as(CodePoint, 0xff) >> @intCast(t)) & byte;

    state.* = hoehrmann_utf8_decode_table[256 + state.* * 16 + t];

    return switch (state.*) {
        UTF8_ACCEPT => .accept,
        UTF8_REJECT => .reject,
        else => .incomplete,
    };
}
inline fn countScalars(bytes: []const u8) !usize {
    var state: u32 = UTF8_ACCEPT;
    var code_point: CodePoint = 0;
    var count: usize = 0;

    for (bytes) |b| {
        switch (decodeByte(&state, &code_point, b)) {
            .accept => count += 1,
            .reject => return error.InvalidUTF8,
            .incomplete => {},
        }
    }

    if (state != UTF8_ACCEPT)
        return error.TruncatedUTF8;

    return count;
}

pub const UTF8ValidationError = error{
    ZeroLengthBytes,
    IndexOutOfBounds,
    InvalidByteSequence,
    InvalidContinuationByte,
    OverlongEncoding,
    SurrogateCodePoint,
    CodePointTooLarge,
};

pub const UTF8ValidationLossyError = error{
    ZeroLengthBytes,
    IndexOutOfBounds,
    InvalidByteSequence,
};

pub const UTF8EncodeError = error{
    CodePointTooLarge,
    BufferTooSmall,
    InvalidByteSequence,
    SurrogateCodePoint,
};

inline fn isOverlong(comptime len: u3, bytes: []const u8, offset: usize) bool {
    if (len == 3) {
        return bytes[offset] == 0xE0 and bytes[offset + 1] < 0xA0;
    }

    if (len == 4) {
        return bytes[offset] == 0xF0 and bytes[offset + 1] < 0x90;
    }

    @compileError("invalid length");
}

inline fn isSurrogateSequence(comptime len: u3, bytes: []const u8, offset: usize) bool {
    if (len == 3) {
        return bytes[offset] == 0xED and bytes[offset + 1] >= 0xA0;
    }

    @compileError("invalid length");
}

inline fn isCodePointTooLong(comptime len: u3, bytes: []const u8, offset: usize) bool {
    if (len == 4) {
        return bytes[offset] == 0xF4 and bytes[offset + 1] > 0x8F;
    }

    @compileError("invalid length");
}

inline fn codePointFromLen(comptime len: u3, bytes: []const u8, offset: usize) DecodedCodePoint {
    if (len < 1 or len > 4) {
        @panic("invalid length");
    }

    if (len == 1) {
        return .{ .code_point = @as(CodePoint, bytes[offset]), .len = len };
    }

    const mask = switch (len) {
        2 => two_byte_payload_mask,
        3 => three_byte_payload_mask,
        4 => four_byte_payload_mask,
        else => @compileError("invalid length"),
    };

    var code_point = (@as(CodePoint, bytes[offset] & mask) << (6 * @as(u5, len - 1)));

    inline for (1..len) |i| {
        code_point |= (@as(CodePoint, bytes[offset + i] & continuation_payload_mask) << (6 * (len - i - 1)));
    }

    return .{ .code_point = code_point, .len = len };
}

inline fn codePointFromLenLossy(comptime len: u3, bytes: []const u8, offset: usize) DecodedCodePointLossy {
    return .{ .len = len, .code_point = codePointFromLen(len, bytes, offset).code_point };
}

/// Returns optimistic length for the given byte, or returns error
/// if an invalid byte is passed. The code point decode
/// should be handled by either `validateAndDecodeCodePointBytes`
/// or `validateAndDecodeCodePointBytesLossy`
///
/// @stable-since: v0.1.0
pub fn codePointLen(byte: u8) UTF8ValidationError!u3 {
    return switch (byte) {
        // byte is more likely to be ascii
        0...MAX_ASCII => blk: {
            @branchHint(.likely);
            break :blk 1;
        },
        two_byte_start_sequence_range_start...two_byte_start_sequence_range_end => 2,
        three_byte_start_sequence_range_start...three_byte_start_sequence_range_end => 3,
        four_byte_start_sequence_range_start...four_byte_start_sequence_range_end => 4,
        else => error.InvalidByteSequence,
    };
}

/// The function returns an optimistic length from the given byte, return value
/// is in range 0...4.
/// `0` is for the invalid byte. The code point decode
/// should be handled by either `validateAndDecodeCodePointBytes`
/// or `validateAndDecodeCodePointBytesLossy`
///
/// @stable-since: v0.1.0
pub fn codePointLenLossy(byte: u8) u3 {
    return switch (byte) {
        // byte is more likely to be ascii
        0...MAX_ASCII => blk: {
            @branchHint(.likely);
            break :blk 1;
        },
        two_byte_start_sequence_range_start...two_byte_start_sequence_range_end => 2,
        three_byte_start_sequence_range_start...three_byte_start_sequence_range_end => 3,
        four_byte_start_sequence_range_start...four_byte_start_sequence_range_end => 4,
        else => 0,
    };
}

/// The `code_point` argument is expected to be a valid utf8 codepoint.
/// No checks are done to the codepoint.
/// The caller needs to make sure a valid code point is
/// passed as an argument.
///
/// - code_point > 0x10FFFF -> triggers unreachable (UB in ReleaseFast)
/// - code_point in surrogate range (0xD800-0xDFFF) -> silently returns 3, no unreachable
///
/// @stable-since: v0.1.0
pub fn utf8EncodeLen(code_point: CodePoint) u3 {
    return switch (code_point) {
        0...MAX_ASCII => blk: {
            @branchHint(.likely);
            break :blk 1;
        },
        min_four_byte_code_point...max_four_byte_code_point => 4,
        min_three_byte_code_point...max_three_byte_code_point => 3,
        min_two_byte_code_point...max_two_byte_code_point => 2,
        else => unreachable,
    };
}

/// Returns `true` if the given byte is `10xxxxxx`
///
/// @stable-since: v0.1.0
pub inline fn isContinuationByte(byte: u8) bool {
    return (byte & continuation_sequence_mask) == continuation_sequence;
}

/// Returns `true` if the byte is either `110xxxxx`, or
/// `1110xxxx` or `11110xxx`, else `false` ASCII bytes (0x00-0x7F) or any other byte
///
/// @stable-since: v0.1.0
pub fn isLeaderByte(byte: u8) bool {
    return switch (byte) {
        two_byte_start_sequence_range_start...two_byte_start_sequence_range_end,
        three_byte_start_sequence_range_start...three_byte_start_sequence_range_end,
        four_byte_start_sequence_range_start...four_byte_start_sequence_range_end,
        => true,
        else => false,
    };
}

fn validateAndDecodeNonAscii(bytes: []const u8, offset: usize, len: u3) UTF8ValidationError!DecodedCodePoint {
    if (offset + len > bytes.len) {
        return UTF8ValidationError.IndexOutOfBounds;
    }

    // Validate continuation bytes
    if (!isContinuationByte(bytes[offset + 1]) or
        (len >= 3 and !isContinuationByte(bytes[offset + 2])) or
        (len == 4 and !isContinuationByte(bytes[offset + 3])))
    {
        return UTF8ValidationError.InvalidContinuationByte;
    }

    // Structural UTF-8 legality constraints

    if (len == 2) {
        return codePointFromLen(2, bytes, offset);
    }

    if ((len == 3 and isOverlong(3, bytes, offset)) or
        (len == 4 and isOverlong(4, bytes, offset)))
    {
        return UTF8ValidationError.OverlongEncoding;
    }

    if (len == 3) {
        if (isSurrogateSequence(3, bytes, offset)) {
            return UTF8ValidationError.SurrogateCodePoint;
        }

        return codePointFromLen(3, bytes, offset);
    }

    // the invariant is preserved in this internal api
    if (isCodePointTooLong(4, bytes, offset)) {
        return UTF8ValidationError.CodePointTooLarge;
    }

    return codePointFromLen(4, bytes, offset);
}

inline fn validateAndDecodeCodePointBytesWithLen(bytes: []const u8, offset: usize, len: u3) UTF8ValidationError!DecodedCodePoint {
    if (bytes.len - offset < @as(usize, len)) {
        return UTF8ValidationError.IndexOutOfBounds;
    }

    // ASCII fast path
    if (len == 1) {
        @branchHint(.likely);
        return codePointFromLen(1, bytes, offset);
    }

    return validateAndDecodeNonAscii(bytes, offset, len);
}

/// This function validates and returns a struct containing the validated code point
/// and the length the code point consumed from the buffer passed.
/// It is a strict decoder variant. Use `validateAndDecodeCodePointBytesLossy` if
/// want to recover the buffer.
///
/// @stable-since: v0.1.0
pub fn validateAndDecodeCodePointBytes(bytes: []const u8, offset: usize) UTF8ValidationError!DecodedCodePoint {
    if (bytes.len == 0) {
        return UTF8ValidationError.ZeroLengthBytes;
    } else if (offset >= bytes.len) {
        return UTF8ValidationError.IndexOutOfBounds;
    }

    const b = bytes[offset];

    if (b <= MAX_ASCII) {
        @branchHint(.likely);
        return codePointFromLen(1, bytes, offset);
    }

    const len = try codePointLen(b);

    return validateAndDecodeNonAscii(bytes, offset, len);
}

fn validateAndDecodeCodePointBytesWithLenLossy(bytes: []const u8, offset: usize, len: u3) UTF8ValidationLossyError!DecodedCodePointLossy {
    const remaining = bytes.len - offset;

    if (len > 1 and len <= 4) {
        // validate if the successive byte is an continuation sequence
        if (remaining < 2 or !isContinuationByte(bytes[offset + 1])) {
            return .{ .code_point = INVALID_CODE_POINT, .len = 1 };
        } else if (len == 2) {
            return codePointFromLenLossy(2, bytes, offset);
        }

        if (remaining < 3 or !isContinuationByte(bytes[offset + 2])) {
            return .{ .code_point = INVALID_CODE_POINT, .len = 2 };
        } else if (len == 3) {
            if (isOverlong(3, bytes, offset) or isSurrogateSequence(3, bytes, offset)) {
                return .{ .code_point = INVALID_CODE_POINT, .len = 3 };
            }

            return codePointFromLenLossy(3, bytes, offset);
        }

        if (remaining < 4 or !isContinuationByte(bytes[offset + 3])) {
            return .{ .code_point = INVALID_CODE_POINT, .len = 3 };
        }

        if (isOverlong(4, bytes, offset) or isCodePointTooLong(4, bytes, offset)) {
            return .{ .code_point = INVALID_CODE_POINT, .len = 4 };
        }

        return codePointFromLenLossy(4, bytes, offset);
    }

    // Handle the case where the code_point length
    // is not 0.
    // It could only mean that the byte encountered
    // is an orphaned continuation-byte sequence or an invalid lead byte
    // We don't decode individual orphaned continuation
    // sequence to individual invalid code-point.
    // we crunch all the successive orphaned bytes
    // into a single invalid code-point until we
    // encounter a [2,3,4]leader byte sequence or
    // an ascii

    var i: usize = 0;

    while (i < remaining and !(isLeaderByte(bytes[offset + i]) or bytes[offset + i] <= MAX_ASCII)) : (i += 1) {}

    return .{ .code_point = INVALID_CODE_POINT, .len = i };
}

/// This function validates and returns a struct containing the validated code point
/// and the length the code point consumed from the buffer passed.
/// It is the lossy variant of decoder. The invalid bytes are consumed and replaced
/// with Unicode Replacement Character `0xFFFD`. Also this function returns the consumed length in
/// `usize` unlike it's strict variant which returns `u3`.
///
/// Note: **The orphaned continuation bytes are consumed all at once until some other byte is found and replaced into a single Unicode Replacement Character.**
///
/// @stable-since: v0.1.0
pub fn validateAndDecodeCodePointBytesLossy(bytes: []const u8, offset: usize) UTF8ValidationLossyError!DecodedCodePointLossy {
    if (bytes.len == 0) {
        return UTF8ValidationLossyError.ZeroLengthBytes;
    } else if (offset >= bytes.len) {
        return UTF8ValidationLossyError.IndexOutOfBounds;
    }

    const b = bytes[offset];

    if (b <= MAX_ASCII) {
        return codePointFromLenLossy(1, bytes, offset);
    }

    const len = codePointLenLossy(b);

    return validateAndDecodeCodePointBytesWithLenLossy(bytes, offset, len);
}

/// Returns optimistic length of the codepoint from the end_index(inclusive) of the given buffer. It is a strict
/// variant where all checks are in place. Use unchecked variant `codePointLenReverseUnchecked` if caller
/// is certain about the bytes validity. To decode and get the len of the bytes consumed, use
/// `validateAndDecodeCodePointBytesReverse`
///
/// @stable-since: v0.1.0
pub fn codePointLenReverse(bytes: []const u8, end_index: usize) UTF8ValidationError!u3 {
    if (bytes.len == 0) {
        return UTF8ValidationError.ZeroLengthBytes;
    } else if (end_index >= bytes.len) {
        return UTF8ValidationError.IndexOutOfBounds;
    }

    var start = end_index;
    var continuation_count: usize = 0;

    while (isContinuationByte(bytes[start])) {
        continuation_count += 1;

        if (continuation_count > 3 or start == 0)
            return error.InvalidByteSequence;

        start -= 1;
    }

    const len = try codePointLen(bytes[start]);

    if (end_index - start + 1 != @as(usize, len)) {
        return UTF8ValidationError.InvalidByteSequence;
    }

    return len;
}

/// Returns optimistic length of the codepoint from the end_index(inclusive) of the given buffer. It is a unchecked
/// variant where only the bytes length checks are in place. Use checked variant `codePointLenReverse` if caller
/// is uncertain about the bytes validity. To decode and get the len of the bytes consumed, use
/// `validateAndDecodeCodePointBytesReverse`
///
/// @stable-since: v0.1.0
pub fn codePointLenReverseUnchecked(bytes: []const u8, end_index: usize) UTF8ValidationError!u3 {
    if (bytes.len == 0) {
        @branchHint(.unlikely);
        return UTF8ValidationError.ZeroLengthBytes;
    } else if (end_index >= bytes.len) {
        @branchHint(.unlikely);
        return UTF8ValidationError.IndexOutOfBounds;
    }

    var start = end_index;

    while (start > 0 and isContinuationByte(bytes[start])) {
        start -= 1;
    }

    return @as(u3, @intCast(end_index - start + 1));
}

/// Validates and decodes code point from given buffer from end_index(inclusive). It is
/// strict variant of decode bytes reverse. Use unchecked variant `decodeCodePointReverseUnchecked`
/// if the caller is certain of the code point validity
///
/// @stable-since: v0.1.0
pub fn validateAndDecodeCodePointBytesReverse(bytes: []const u8, end_index: usize) UTF8ValidationError!DecodedCodePoint {
    if (bytes.len == 0) {
        return UTF8ValidationError.ZeroLengthBytes;
    } else if (end_index >= bytes.len) {
        return UTF8ValidationError.IndexOutOfBounds;
    }

    // ASCII fast path
    if (bytes[end_index] <= MAX_ASCII) {
        @branchHint(.likely);
        return codePointFromLen(1, bytes, end_index);
    }

    const len = try codePointLenReverse(bytes, end_index);

    const start = end_index + 1 - @as(usize, len);

    return validateAndDecodeCodePointBytesWithLen(bytes, start, len);
}

pub const DecodedCodePoint = struct {
    code_point: CodePoint,
    len: u3,
};

pub const DecodedCodePointLossy = struct {
    code_point: CodePoint,
    len: usize,
};

fn decode(bytes: []const u8, offset: usize, len: u3) DecodedCodePoint {
    return switch (len) {
        1 => codePointFromLen(1, bytes, offset),
        2 => codePointFromLen(2, bytes, offset),
        3 => codePointFromLen(3, bytes, offset),
        4 => codePointFromLen(4, bytes, offset),
        else => @panic("unknown code point length"),
    };
}

fn encode(code_point: CodePoint, bytes: []u8) UTF8EncodeError!u3 {
    const len = utf8EncodeLen(code_point);

    if (bytes.len < len) {
        return error.BufferTooSmall;
    }

    switch (len) {
        1 => {
            @branchHint(.likely);
            bytes[0] = @as(u8, @truncate(code_point));
        },

        2 => {
            bytes[0] =
                @as(u8, @truncate((code_point >> 6) & two_byte_payload_mask)) |
                two_byte_lead_byte_prefix;

            bytes[1] =
                @as(u8, @truncate(code_point & continuation_payload_mask)) |
                continuation_sequence;
        },

        3 => {
            bytes[0] =
                @as(u8, @truncate((code_point >> 12) & three_byte_payload_mask)) |
                three_byte_start_sequence_range_start;

            bytes[1] =
                @as(u8, @truncate((code_point >> 6) & continuation_payload_mask)) |
                continuation_sequence;

            bytes[2] =
                @as(u8, @truncate(code_point & continuation_payload_mask)) |
                continuation_sequence;
        },

        4 => {
            bytes[0] =
                @as(u8, @truncate((code_point >> 18) & four_byte_payload_mask)) |
                four_byte_start_sequence_range_start;

            bytes[1] =
                @as(u8, @truncate((code_point >> 12) & continuation_payload_mask)) |
                continuation_sequence;

            bytes[2] =
                @as(u8, @truncate((code_point >> 6) & continuation_payload_mask)) |
                continuation_sequence;

            bytes[3] =
                @as(u8, @truncate(code_point & continuation_payload_mask)) |
                continuation_sequence;
        },

        else => unreachable,
    }

    return len;
}

/// The function does not validate the codepoint, caller needs to make sure
/// to pass a valid codepoint. Only the buffer length is validated
///
/// @stable-since: v0.1.0
pub fn encodeCodePoint(code_point: CodePoint, bytes: []u8) UTF8EncodeError!u3 {
    return encode(code_point, bytes);
}

/// This function validates and decodes code point from buffer. This is the unchecked variant
/// of decode reverse, use strict variant `validateAndDecodeCodePointBytesReverse` if caller is uncertain the bytes are valid.
///
/// Note: **this function panics in case the buffer length is zero or end_index > bytes.len**
///
/// @stable-since: v0.1.0
pub fn decodeCodePointReverseUnchecked(bytes: []const u8, end_index: usize) DecodedCodePoint {
    const len = codePointLenReverseUnchecked(bytes, end_index) catch @panic("invalid decode reverse unchecked code point length");
    const start = end_index + 1 - @as(usize, len);

    return decode(bytes, start, len);
}

fn bytesToUTF8CodePoint(bytes: []const u8, offset: usize) DecodedCodePoint {
    const len = codePointLen(bytes[offset]) catch @panic("invalid code point length");

    if (len == 1 and bytes[offset] <= MAX_ASCII) {
        return .{ .code_point = @as(CodePoint, bytes[offset]), .len = 1 };
    }

    return decode(bytes, offset, len);
}

pub const UTF8SliceError = error{
    IndexOutOfBounds,
    InvalidBoundary,
};

const UTF8ViewIterator = struct {
    index: usize = 0,
    view: *const UTF8View,

    pub fn next(self: *UTF8ViewIterator) ?CodePoint {
        if (self.index >= self.view.data.len) {
            return null;
        }

        const code_point = bytesToUTF8CodePoint(self.view.data, self.index);

        self.index += @as(usize, code_point.len);

        return code_point.code_point;
    }

    pub fn reset(self: *UTF8ViewIterator) void {
        self.index = 0;
    }

    pub fn peek(self: *const UTF8ViewIterator) ?CodePoint {
        if (self.index >= self.view.data.len) {
            return null;
        }

        return bytesToUTF8CodePoint(self.view.data, self.index).code_point;
    }

    pub fn previous(self: *UTF8ViewIterator) ?CodePoint {
        if (self.index == 0) {
            return null;
        }

        const code_point = decodeCodePointReverseUnchecked(self.view.data, self.index - 1);

        self.index -= @as(usize, code_point.len);
        return code_point.code_point;
    }

    pub fn peekPrevious(self: *const UTF8ViewIterator) ?CodePoint {
        if (self.index == 0) {
            return null;
        }

        return decodeCodePointReverseUnchecked(self.view.data, self.index - 1).code_point;
    }
};

const UTF8View = struct {
    data: []const u8,

    pub fn countScalar(self: *const UTF8View) usize {
        var count: usize = 0;
        var i: usize = 0;

        while (i < self.data.len) {
            const byte = self.data[i];

            if (byte <= MAX_ASCII) {
                i += 1;
                count += 1;
                continue;
            }

            const len = codePointLen(byte) catch @panic("invalid code point length");

            i += @as(usize, len);
            count += 1;
        }

        return count;
    }

    pub fn isBoundary(self: *const UTF8View, index: usize) bool {
        if (index > self.data.len) {
            return false;
        }

        if (index == 0 or index == self.data.len) {
            return true;
        }

        return !isContinuationByte(self.data[index]);
    }

    pub fn sliceScalars(self: *const UTF8View, start_scalar: usize, end_scalar: usize) UTF8SliceError!UTF8View {
        if (start_scalar > end_scalar) {
            return error.IndexOutOfBounds;
        }

        var scalar_index: usize = 0;
        var byte_index: usize = 0;

        var start_byte: ?usize = null;
        var end_byte: ?usize = null;

        while (byte_index < self.data.len) {
            if (scalar_index == start_scalar) {
                start_byte = byte_index;
            }

            if (scalar_index == end_scalar) {
                end_byte = byte_index;
                break;
            }

            const byte = self.data[byte_index];

            if (byte <= MAX_ASCII) {
                byte_index += 1;
            } else {
                const len = codePointLen(byte) catch @panic("invalid code point length");
                byte_index += len;
            }

            scalar_index += 1;
        }

        if (scalar_index == start_scalar and start_byte == null) {
            start_byte = self.data.len;
        }

        if (scalar_index == end_scalar and end_byte == null) {
            end_byte = self.data.len;
        }

        if (start_byte == null or end_byte == null) {
            return error.IndexOutOfBounds;
        }

        return .{
            .data = self.data[start_byte.?..end_byte.?],
        };
    }

    pub fn iter(self: *const UTF8View) UTF8ViewIterator {
        return .{ .view = self };
    }
};

const UTF8LossyIterator = struct {
    data: []const u8,
    index: usize = 0,

    pub fn next(self: *UTF8LossyIterator) ?CodePoint {
        if (self.index >= self.data.len) {
            return null;
        }

        const decoded = validateAndDecodeCodePointBytesLossy(self.data, self.index) catch unreachable;
        std.debug.assert(decoded.len > 0);
        self.index += decoded.len;
        return decoded.code_point;
    }

    pub fn peek(self: *const UTF8LossyIterator) ?CodePoint {
        if (self.index >= self.data.len) {
            return null;
        }

        return (validateAndDecodeCodePointBytesLossy(self.data, self.index) catch unreachable).code_point;
    }
};

/// Takes un-validated bytes and returns an iterator primitive. Any invalid bytes are
/// consumed and replaced with Unicode Replacement Character.
///
/// Note: **The invalid consecutive orphaned continuation bytes are consumed and a single Unicode Replacement Character is returned.**
///
/// This is lossy variant to decode bytes to valid CodePoints, for script decoding, see `initUTF8View`
///
/// ## Usage
///
/// ```zig
/// var iter = encoding.lossyIterator(bytes_to_decode);
///
/// while (iter.next()) |code_point| {
///     ...
/// }
/// ```
///
/// @stable-since: v0.1.0
pub fn lossyIterator(bytes: []const u8) UTF8LossyIterator {
    return .{ .data = bytes };
}

/// This function returns back the number of code point in the bytes. Invalid bytes
/// are replaced with Unicode Replacement Character. This is the lossy variant. See `initUTF8View`
/// for strict variant.
///
/// Note: **The invalid consecutive orphaned continuation bytes are consumed and a single Unicode Replacement Character is returned.**
///
/// @stable-since: v0.1.0
pub fn countScalarsLossy(bytes: []const u8) usize {
    var count: usize = 0;
    var iter = lossyIterator(bytes);

    while (iter.next()) |_| : (count += 1) {}
    return count;
}

/// This function writes the valid code points to the mutable CodePoint slice passed as argument.
/// All the invalid code points are converted to Unicode Replacement Character.
/// Returns error if mutable CodePoint buffer is small.
///
/// Note: **The invalid consecutive orphaned continuation bytes are consumed and a single Unicode Replacement Character is returned.**
///
/// @stable-since: v0.1.0
pub fn bytesToCodePointsLossyBuffer(bytes: []const u8, buf: []CodePoint) error{BufferTooSmall}!usize {
    var i: usize = 0;
    var iter = lossyIterator(bytes);

    while (iter.next()) |code_point| {
        if (i >= buf.len) {
            return error.BufferTooSmall;
        }
        buf[i] = code_point;
        i += 1;
    }

    return i;
}

/// This function allocates and writes the valid CodePoints to the allocated CodePoint slice.
/// All the invalid code points are converted to Unicode Replacement Character. Caller needs to free
/// the returned slice.
///
/// Note: **The invalid consecutive orphaned continuation bytes are consumed and a single Unicode Replacement Character is returned.**
///
/// @stable-since: v0.1.0
pub fn bytesToCodePointsLossy(allocator: std.mem.Allocator, bytes: []const u8) error{OutOfMemory}![]CodePoint {
    const len = countScalarsLossy(bytes);
    const out = try allocator.alloc(CodePoint, len);
    errdefer allocator.free(out);

    _ = bytesToCodePointsLossyBuffer(bytes, out) catch unreachable;
    return out;
}

/// This function validates and stores valid buffer and can be used for iterating, counting, peeking,
/// traversing forward and backward. Expects a mutable usize argument which writes the scalar count
/// of the validated bytes.
///
/// @stable-since: v0.1.0
pub fn initUTF8View(data: []const u8, resultant_unicode_str_len: *usize) UTF8ValidationError!UTF8View {
    var i: usize = 0;
    var scalar_count: usize = 0;

    while (i < data.len) : (scalar_count += 1) {
        const cp = try validateAndDecodeCodePointBytes(data, i);
        i += cp.len;
    }

    resultant_unicode_str_len.* = scalar_count;

    return .{ .data = data };
}

/// This function assumes the bytes passed as argument are valid utf8 codepoints. The bytes
/// are not validated.
///
/// @stable-since: v0.1.0
pub fn initUTF8ViewUnchecked(data: []const u8) UTF8View {
    return .{ .data = data };
}

/// Writes the valid CodePoints to a mutable CodePoint slice passed by from arguments
/// Returns error if the writable buffer is small.
///
/// @stable-since: v0.1.0
pub fn utf8ViewToUTF8String(view: *const UTF8View, buf: []CodePoint) error{BufferTooSmall}!usize {
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

/// Generates a validated comptime CodePoint Slice from given bytes.
///
/// @stable-since: v0.1.0
pub fn bytesToUTF8StringComptime(comptime bytes: []const u8) (UTF8ValidationError || error{BufferTooSmall})![countScalars(bytes) catch {}]CodePoint {
    comptime {
        var unicode_str_len: usize = 0;

        const utf8_view = try initUTF8View(bytes, &unicode_str_len);
        var buf: [unicode_str_len]CodePoint = undefined;

        _ = try utf8ViewToUTF8String(&utf8_view, &buf);

        return buf;
    }
}

/// validates and writes valid codepoints to an allocated CodePoint slice. The caller needs to
/// free the returned slice
///
/// @stable-since: v0.1.0
pub fn bytesToUTF8String(allocator: std.mem.Allocator, bytes: []const u8) (UTF8ValidationError || error{ BufferTooSmall, OutOfMemory })![]CodePoint {
    var unicode_str_len: usize = 0;
    const utf8_view = try initUTF8View(bytes, &unicode_str_len);
    const buf = try allocator.alloc(CodePoint, unicode_str_len);
    errdefer allocator.free(buf);

    _ = try utf8ViewToUTF8String(&utf8_view, buf);

    return buf;
}

// --- tests ------------------------------------------------------------------

test "decodeByte: ascii accept" {
    var state: u32 = UTF8_ACCEPT;
    var cp: CodePoint = 0;

    const r = decodeByte(&state, &cp, 'A');

    try std.testing.expectEqual(DecodeResult.accept, r);
    try std.testing.expectEqual(UTF8_ACCEPT, state);
    try std.testing.expectEqual(@as(CodePoint, 'A'), cp);
}

test "decodeByte: valid two byte sequence" {
    var state: u32 = UTF8_ACCEPT;
    var cp: CodePoint = 0;

    try std.testing.expectEqual(
        DecodeResult.incomplete,
        decodeByte(&state, &cp, 0xC2),
    );

    try std.testing.expect(state != UTF8_ACCEPT);

    try std.testing.expectEqual(
        DecodeResult.accept,
        decodeByte(&state, &cp, 0xA2),
    );

    try std.testing.expectEqual(
        @as(CodePoint, 0xA2),
        cp,
    );
}

test "decodeByte: valid four byte sequence 😀" {
    var state: u32 = UTF8_ACCEPT;
    var cp: CodePoint = 0;

    const bytes = [_]u8{
        0xF0,
        0x9F,
        0x98,
        0x80,
    };

    try std.testing.expectEqual(
        DecodeResult.incomplete,
        decodeByte(&state, &cp, bytes[0]),
    );

    try std.testing.expectEqual(
        DecodeResult.incomplete,
        decodeByte(&state, &cp, bytes[1]),
    );

    try std.testing.expectEqual(
        DecodeResult.incomplete,
        decodeByte(&state, &cp, bytes[2]),
    );

    try std.testing.expectEqual(
        DecodeResult.accept,
        decodeByte(&state, &cp, bytes[3]),
    );

    try std.testing.expectEqual(
        @as(CodePoint, 0x1F600),
        cp,
    );
}

test "decodeByte: reject malformed sequence" {
    var state: u32 = UTF8_ACCEPT;
    var cp: CodePoint = 0;

    _ = decodeByte(&state, &cp, 0xF0);

    const r = decodeByte(&state, &cp, 0x28);

    try std.testing.expectEqual(DecodeResult.reject, r);

    try std.testing.expectEqual(
        UTF8_REJECT,
        state,
    );
}

test "decodeByte: orphan continuation byte rejects" {
    var state: u32 = UTF8_ACCEPT;
    var cp: CodePoint = 0;

    const r = decodeByte(&state, &cp, 0x80);

    try std.testing.expectEqual(DecodeResult.reject, r);
}

test "codePointLen: ASCII and classification edge bytes" {
    try std.testing.expectEqual(@as(u3, 1), try codePointLen(0));
    try std.testing.expectEqual(@as(u3, 1), try codePointLen(MAX_ASCII));
    // Continuation-shaped byte is not a lead
    try std.testing.expectError(error.InvalidByteSequence, codePointLen(0x80));
    try std.testing.expectError(error.InvalidByteSequence, codePointLen(0xBF));
    // Invalid / overlong lead ranges excluded from two-byte window
    try std.testing.expectError(error.InvalidByteSequence, codePointLen(0xC0));
    try std.testing.expectError(error.InvalidByteSequence, codePointLen(0xC1));
    // First legal two-byte lead
    try std.testing.expectEqual(@as(u3, 2), try codePointLen(two_byte_start_sequence_range_start));
    try std.testing.expectEqual(@as(u3, 2), try codePointLen(two_byte_start_sequence_range_end));
    try std.testing.expectEqual(@as(u3, 3), try codePointLen(three_byte_start_sequence_range_start));
    try std.testing.expectEqual(@as(u3, 3), try codePointLen(three_byte_start_sequence_range_end));
    try std.testing.expectEqual(@as(u3, 4), try codePointLen(four_byte_start_sequence_range_start));
    try std.testing.expectEqual(@as(u3, 4), try codePointLen(four_byte_start_sequence_range_end));
    try std.testing.expectError(error.InvalidByteSequence, codePointLen(0xF5));
    try std.testing.expectError(error.InvalidByteSequence, codePointLen(0xFF));
}

test "utf8EncodeLen: boundaries, BMP vs supplementary, surrogates, overflow" {
    try std.testing.expectEqual(@as(u3, 1), utf8EncodeLen(0));
    try std.testing.expectEqual(@as(u3, 1), utf8EncodeLen(MAX_ASCII));
    try std.testing.expectEqual(@as(u3, 2), utf8EncodeLen(min_two_byte_code_point));
    try std.testing.expectEqual(@as(u3, 2), utf8EncodeLen(max_two_byte_code_point));
    try std.testing.expectEqual(@as(u3, 3), utf8EncodeLen(min_three_byte_code_point));
    try std.testing.expectEqual(@as(u3, 3), utf8EncodeLen(max_three_byte_code_point));
    try std.testing.expectEqual(@as(u3, 4), utf8EncodeLen(min_four_byte_code_point));
    try std.testing.expectEqual(@as(u3, 4), utf8EncodeLen(max_four_byte_code_point));
}

test "isContinuationByte" {
    try std.testing.expect(isContinuationByte(0x80));
    try std.testing.expect(isContinuationByte(0xBF));
    try std.testing.expect(!isContinuationByte(0x7F));
    try std.testing.expect(!isContinuationByte(0xC0));
}

test "validateCodePointBytes: empty, truncated, bad continuation" {
    try std.testing.expectError(UTF8ValidationError.ZeroLengthBytes, validateAndDecodeCodePointBytes(&.{}, 0));

    try std.testing.expectError(UTF8ValidationError.IndexOutOfBounds, validateAndDecodeCodePointBytes(&.{0xF0}, 0));
    try std.testing.expectError(UTF8ValidationError.IndexOutOfBounds, validateAndDecodeCodePointBytes(&.{ 0xF0, 0x90 }, 0));
    try std.testing.expectError(UTF8ValidationError.IndexOutOfBounds, validateAndDecodeCodePointBytes(&.{ 0xF0, 0x90, 0x80 }, 0));

    // Lead claims 2 bytes but second is not a continuation
    try std.testing.expectError(UTF8ValidationError.InvalidContinuationByte, validateAndDecodeCodePointBytes(&.{ 0xC2, 0x40 }, 0));

    // Extra bytes in slice are ignored (validate prefix only)
    _ = try validateAndDecodeCodePointBytes("aZ", 0);
}

test "validateAndDecodeCodePointBytes: overlong sequences" {
    // 2-byte overlong (would decode < 0x80)
    try std.testing.expectError(UTF8ValidationError.InvalidByteSequence, validateAndDecodeCodePointBytes(&.{ 0xC0, 0x80 }, 0));
    try std.testing.expectError(UTF8ValidationError.InvalidByteSequence, validateAndDecodeCodePointBytes(&.{ 0xC1, 0xBF }, 0));

    // 3-byte overlong minimum block (E0 80-9F)
    try std.testing.expectError(UTF8ValidationError.OverlongEncoding, validateAndDecodeCodePointBytes(&.{ 0xE0, 0x80, 0x80 }, 0));
    try std.testing.expectError(UTF8ValidationError.OverlongEncoding, validateAndDecodeCodePointBytes(&.{ 0xE0, 0x9F, 0xBF }, 0));

    // 3-byte: smallest legal after overlong boundary (E0 A0 80 = U+0800)
    try std.testing.expectEqual(@as(u3, 3), (try validateAndDecodeCodePointBytes(&.{ 0xE0, 0xA0, 0x80 }, 0)).len);

    // 4-byte overlong (F0 80-8F ...)
    try std.testing.expectError(UTF8ValidationError.OverlongEncoding, validateAndDecodeCodePointBytes(&.{ 0xF0, 0x80, 0x80, 0x80 }, 0));
    try std.testing.expectError(UTF8ValidationError.OverlongEncoding, validateAndDecodeCodePointBytes(&.{ 0xF0, 0x8F, 0xBF, 0xBF }, 0));

    // 4-byte: smallest legal supplementary (U+10000)
    try std.testing.expectEqual(@as(u3, 4), (try validateAndDecodeCodePointBytes(&.{ 0xF0, 0x90, 0x80, 0x80 }, 0)).len);
}

test "validateCodePointBytes: UTF-16 surrogate encodings and above U+10FFFF" {
    try std.testing.expectError(UTF8ValidationError.SurrogateCodePoint, validateAndDecodeCodePointBytes(&.{ 0xED, 0xA0, 0x80 }, 0));
    try std.testing.expectError(UTF8ValidationError.SurrogateCodePoint, validateAndDecodeCodePointBytes(&.{ 0xED, 0xBF, 0xBF }, 0));

    // ED 9F BF is just below surrogate block (legal)
    try std.testing.expectEqual(@as(u3, 3), (try validateAndDecodeCodePointBytes(&.{ 0xED, 0x9F, 0xBF }, 0)).len);

    // Beyond Unicode (F4 90 ...)
    try std.testing.expectError(UTF8ValidationError.CodePointTooLarge, validateAndDecodeCodePointBytes(&.{ 0xF4, 0x90, 0x80, 0x80 }, 0));
    // Max legal plane-16 encoding
    try std.testing.expectEqual(@as(u3, 4), (try validateAndDecodeCodePointBytes(&.{ 0xF4, 0x8F, 0xBF, 0xBF }, 0)).len);
}

test "codePointLenReverse and validateAndDecodeCodePointBytesReverse" {
    try std.testing.expectError(UTF8ValidationError.ZeroLengthBytes, codePointLenReverse(&.{}, 0));

    const one = "x";
    try std.testing.expectEqual(@as(u3, 1), try codePointLenReverse(one, one.len - 1));
    try std.testing.expectEqual(@as(u3, 1), (try validateAndDecodeCodePointBytesReverse(one, one.len - 1)).len);

    const four = [_]u8{ 0xF0, 0x90, 0x80, 0x80 };
    try std.testing.expectEqual(@as(u3, 4), try codePointLenReverse(&four, four.len - 1));
    try std.testing.expectEqual(@as(u3, 4), (try validateAndDecodeCodePointBytesReverse(&four, four.len - 1)).len);

    // Too many continuation bytes before lead
    try std.testing.expectError(error.InvalidByteSequence, codePointLenReverse(&.{ 0x80, 0x80, 0x80, 0x80, 0x80 }, 4));
    // Lead does not cover all trailing bytes
    try std.testing.expectError(error.InvalidByteSequence, codePointLenReverse(&.{ 0xE0, 0xA0 }, 1));
}

test "encode/decode round-trip representative code points" {
    const cases = [_]CodePoint{
        0x0000,
        0x007F,
        0x0080,
        0x07FF,
        0x0800,
        0xFFFF,
        0x10000,
        0x10FFFF,
        '한',
        0x1F600, // 😀
    };
    var buf: [4]u8 = undefined;
    for (cases) |cp| {
        const len = try encode(cp, &buf);
        try std.testing.expectEqual(utf8EncodeLen(cp), len);
        const got = decode(&buf, 0, len);
        try std.testing.expectEqual(cp, got.code_point);
    }
}

test "encode buffer too small" {
    var buf: [4]u8 = undefined;

    try std.testing.expectError(error.BufferTooSmall, encode(0x80, buf[0..0]));
    try std.testing.expectError(error.BufferTooSmall, encode(0x0800, buf[0..1]));
}

test "checked decode rejects overlong and out-of-range encodings" {
    try std.testing.expectError(error.InvalidByteSequence, validateAndDecodeCodePointBytes(&.{ 0xC0, 0x80 }, 0));
    try std.testing.expectError(error.OverlongEncoding, validateAndDecodeCodePointBytes(&.{ 0xE0, 0x80, 0x80 }, 0));
    try std.testing.expectError(error.CodePointTooLarge, validateAndDecodeCodePointBytes(&.{ 0xF4, 0x90, 0x80, 0x80 }, 0));
}

test "validateAndDecodeCodePointBytes and ReverseChecked agree on valid scalars" {
    const s = "a€𝄞\u{10FFFF}"; // mixed ASCII, 3-byte, 4-byte, max scalar
    var i: usize = 0;
    while (i < s.len) {
        const rest = s[i..];
        const fwd = try validateAndDecodeCodePointBytes(rest, 0);
        const prefix = s[0 .. i + fwd.len];
        const rev = try validateAndDecodeCodePointBytesReverse(prefix, prefix.len - 1);
        try std.testing.expectEqual(fwd.code_point, rev.code_point);
        try std.testing.expectEqual(fwd.len, rev.len);
        i += fwd.len;
    }
}

test "validateAndDecodeCodePointBytes rejects illegal sequences" {
    try std.testing.expectError(error.InvalidContinuationByte, validateAndDecodeCodePointBytes(&.{ 0xE0, 0xA0, 0x40 }, 0));
    try std.testing.expectError(error.OverlongEncoding, validateAndDecodeCodePointBytes(&.{ 0xF0, 0x80, 0x80, 0x80 }, 0));
}

test "UTF8View: boundaries and countScalar" {
    // U+00E9 (é) = 2 UTF-8 bytes; U+1D11E (𝄞) = 4 bytes → 6 bytes, 2 scalars.
    const view = initUTF8ViewUnchecked("é𝄞");
    try std.testing.expectEqual(@as(usize, 2), view.countScalar());

    try std.testing.expect(view.isBoundary(0));
    try std.testing.expect(!view.isBoundary(1));
    try std.testing.expect(view.isBoundary(2));
    try std.testing.expect(!view.isBoundary(3));
    try std.testing.expect(!view.isBoundary(4));
    try std.testing.expect(!view.isBoundary(5));
    try std.testing.expect(view.isBoundary(6));
    try std.testing.expect(!view.isBoundary(7));

    try std.testing.expectEqual(@as(usize, 0), initUTF8ViewUnchecked("").countScalar());
}

test "UTF8View: iterator next, peek, previous, peekPrevious" {
    var view = initUTF8ViewUnchecked("ab");
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

test "UTF8View: sliceScalars edge indices" {
    const view = initUTF8ViewUnchecked("hello");
    // empty range at each boundary
    const empty0 = try view.sliceScalars(0, 0);
    try std.testing.expectEqualStrings("", empty0.data);
    const empty5 = try view.sliceScalars(5, 5);
    try std.testing.expectEqualStrings("", empty5.data);
    // full string
    const all = try view.sliceScalars(0, 5);
    try std.testing.expectEqualStrings("hello", all.data);
    // middle "ell"
    const mid = try view.sliceScalars(1, 4);
    try std.testing.expectEqualStrings("ell", mid.data);

    try std.testing.expectError(error.IndexOutOfBounds, view.sliceScalars(3, 2));
    try std.testing.expectError(error.IndexOutOfBounds, view.sliceScalars(0, 6));
}

test "initUTF8View validates full buffer" {
    var size: usize = 0;
    _ = try initUTF8View("ok", &size);
    try std.testing.expectError(error.OverlongEncoding, initUTF8View(&.{ 0xE0, 0x80, 0x80 }, &size));
}

test "utf8ViewToUTF8String and bytesToUTF8String" {
    var size: usize = 0;
    const view = try initUTF8View("αβγ", &size);
    var buf: [3]CodePoint = undefined;
    const n = try utf8ViewToUTF8String(&view, &buf);
    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqual(@as(CodePoint, 0x03B1), buf[0]);
    try std.testing.expectEqual(@as(CodePoint, 0x03B2), buf[1]);
    try std.testing.expectEqual(@as(CodePoint, 0x03B3), buf[2]);

    const alloc_buf = try bytesToUTF8String(std.testing.allocator, "αβ");
    defer std.testing.allocator.free(alloc_buf);
    try std.testing.expectEqual(@as(usize, 2), alloc_buf.len);
    try std.testing.expectEqual(@as(CodePoint, 0x03B1), alloc_buf[0]);
    try std.testing.expectEqual(@as(CodePoint, 0x03B2), alloc_buf[1]);
}

test "bytesToUTF8StringComptime" {
    const arr = comptime try bytesToUTF8StringComptime("π");
    try comptime std.testing.expect(arr.len == 1);
    try comptime std.testing.expect(arr[0] == 0x03C0);
}

test "bytesToUTF8CodePoint and validateAndDecodeCodePointBytesReverse match expectations" {
    const s = [_]u8{ 0xF0, 0x9F, 0x98, 0x80 }; // 😀
    const d = bytesToUTF8CodePoint(&s, 0);
    try std.testing.expectEqual(@as(CodePoint, 0x1F600), d.code_point);
    const r = try validateAndDecodeCodePointBytesReverse(&s, 3);
    try std.testing.expectEqual(d.code_point, r.code_point);
}

test "hostile: single-byte lead 0x00-0xFF classification smoke" {
    var b: u8 = 0;
    while (true) : (b +%= 1) {
        const r = codePointLen(b);
        if (b <= MAX_ASCII) {
            try std.testing.expectEqual(@as(u3, 1), r);
        } else if (b >= two_byte_start_sequence_range_start and b <= two_byte_start_sequence_range_end) {
            try std.testing.expectEqual(@as(u3, 2), r);
        } else if (b >= three_byte_start_sequence_range_start and b <= three_byte_start_sequence_range_end) {
            try std.testing.expectEqual(@as(u3, 3), r);
        } else if (b >= four_byte_start_sequence_range_start and b <= four_byte_start_sequence_range_end) {
            try std.testing.expectEqual(@as(u3, 4), r);
        } else {
            try std.testing.expectError(error.InvalidByteSequence, r);
        }
        if (b == 0xFF) break;
    }
}

test "hostile: validate every lead with wrong continuation shapes" {
    // 2-byte leads: bad second (not cont), truncated (solo lead)
    var lead: u8 = two_byte_start_sequence_range_start;
    while (lead <= two_byte_start_sequence_range_end) : (lead += 1) {
        try std.testing.expectError(UTF8ValidationError.InvalidContinuationByte, validateAndDecodeCodePointBytes(&.{ lead, 0x40 }, 0));
        try std.testing.expectError(UTF8ValidationError.IndexOutOfBounds, validateAndDecodeCodePointBytes(&.{lead}, 0));
    }
    // 3-byte: bad at [1] or [2], length 2
    const t3 = [_]u8{ 0xE1, 0x80, 0x40 };
    try std.testing.expectError(UTF8ValidationError.InvalidContinuationByte, validateAndDecodeCodePointBytes(&t3, 0));
    try std.testing.expectError(UTF8ValidationError.IndexOutOfBounds, validateAndDecodeCodePointBytes(&.{ 0xE1, 0x80 }, 0));
    // 4-byte
    try std.testing.expectError(UTF8ValidationError.InvalidContinuationByte, validateAndDecodeCodePointBytes(&.{ 0xF4, 0x8F, 0x40, 0x80 }, 0));
    try std.testing.expectError(UTF8ValidationError.IndexOutOfBounds, validateAndDecodeCodePointBytes(&.{ 0xF4, 0x8F, 0xBF }, 0));
}

test "hostile: reverse path on garbage tails" {
    try std.testing.expectError(UTF8ValidationError.InvalidByteSequence, codePointLenReverse(&.{0xC2}, 0));
    try std.testing.expectError(UTF8ValidationError.InvalidByteSequence, validateAndDecodeCodePointBytesReverse(&.{ 0xE0, 0xA0 }, 1));
    try std.testing.expectError(UTF8ValidationError.InvalidByteSequence, validateAndDecodeCodePointBytesReverse(&.{0x80}, 0));
    // orphan continuation only
    try std.testing.expectError(UTF8ValidationError.InvalidByteSequence, codePointLenReverse(&.{0x80}, 0));
}

test "hostile: initUTF8View rejects stitched error bytes" {
    var size: usize = 0;
    try std.testing.expectError(UTF8ValidationError.OverlongEncoding, initUTF8View(&.{ 0xE0, 0x80, 0x80 }, &size));
    try std.testing.expectError(UTF8ValidationError.InvalidByteSequence, initUTF8View("ok\xFFtrailing", &size));
    try std.testing.expectError(UTF8ValidationError.InvalidContinuationByte, initUTF8View("\xC3\x28", &size));
    try std.testing.expectError(UTF8ValidationError.OverlongEncoding, initUTF8View(&.{ 0xF0, 0x80, 0x80, 0x80 }, &size));
    try std.testing.expectError(UTF8ValidationError.SurrogateCodePoint, initUTF8View(&.{ 0xED, 0xA0, 0x80 }, &size));
}

test "hostile: BMP encode/decode sweep (stride avoids timeout)" {
    var buf: [4]u8 = undefined;
    var cp: u32 = 0;
    while (cp <= 0xFFFF) : (cp += 37) {
        if (cp >= surrogate_range_start and cp <= surrogate_range_end) continue;
        const cp21: CodePoint = @truncate(cp);
        _ = try encode(cp21, &buf);
        _ = try validateAndDecodeCodePointBytes(&buf, 0);
        const got = try validateAndDecodeCodePointBytes(&buf, 0);
        try std.testing.expectEqual(cp21, got.code_point);
    }
}

test "hostile: supplementary encode/decode sweep" {
    var buf: [4]u8 = undefined;
    var cp: u32 = 0x10000;
    while (cp <= max_four_byte_code_point) : (cp += 7919) {
        const cp21: CodePoint = @truncate(cp);
        _ = try encode(cp21, &buf);
        const got = try validateAndDecodeCodePointBytes(&buf, 0);
        try std.testing.expectEqual(cp21, got.code_point);
    }
}

test "hostile: UTF8View iterator roundtrip on punisher string" {
    const s = "a\u{0080}\u{0800}\u{10000}\u{10FFFF}👨\u{200D}👩\u{200D}👧\u{3030}";
    var size: usize = 0;
    const view = try initUTF8View(s, &size);
    var it = view.iter();
    var forward: usize = 0;
    while (it.next()) |_| {
        forward += 1;
    }
    var backward: usize = 0;
    while (it.previous()) |_| {
        backward += 1;
    }
    try std.testing.expectEqual(forward, backward);
    try std.testing.expectEqual(@as(usize, 0), it.index);
}

test "hostile: sliceScalars on emoji-heavy string" {
    const s = "x\u{1F9FF}\u{200D}\u{2642}\u{FE0F}z";
    var size: usize = 0;
    const v = try initUTF8View(s, &size);
    const mid = try v.sliceScalars(1, v.countScalar() - 1);
    try std.testing.expect(mid.data.len > 0);
    const full = try v.sliceScalars(0, v.countScalar());
    try std.testing.expectEqualStrings(s, full.data);
}

test "hostile: utf8ViewToUTF8String buffer too small path" {
    var size: usize = 0;
    const view = try initUTF8View("αβ", &size);
    var tiny: [1]CodePoint = undefined;
    try std.testing.expectError(error.BufferTooSmall, utf8ViewToUTF8String(&view, &tiny));
}

// --- error matrix: wrong inputs → exact expected errors ----------------

test "matrix: validateAndDecodeCodePointBytes length contract" {
    // Empty buffer
    try std.testing.expectError(
        error.ZeroLengthBytes,
        validateAndDecodeCodePointBytes(&.{}, 0),
    );
    try std.testing.expectError(
        error.IndexOutOfBounds,
        validateAndDecodeCodePointBytes("a", 1),
    );
    try std.testing.expectError(
        error.IndexOutOfBounds,
        validateAndDecodeCodePointBytes(&.{ 0xC3, 0xA9 }, 2),
    );
    // Wrong continuation for claimed 2-byte decode
    try std.testing.expectError(
        error.InvalidContinuationByte,
        validateAndDecodeCodePointBytes(&.{ 0xC2, 0x28 }, 0),
    );
    //  does not consult codePointLen(bytes[0]); high bit + len 1 is accepted (caller obligation)
    const hi = validateAndDecodeCodePointBytes(&.{0x80}, 0);
    try std.testing.expectError(UTF8ValidationError.InvalidByteSequence, hi);

    const pi = try validateAndDecodeCodePointBytes("π", 0);
    try std.testing.expectEqual(@as(CodePoint, 0x03C0), pi.code_point);
}

test "matrix: validateAndDecode forwards match bytesToUTF8CodePointChecked" {
    const Case = struct { bytes: []const u8, expect_err: UTF8ValidationError };
    const cases = [_]Case{
        .{ .bytes = &.{ 0xF5, 0x80, 0x80, 0x80 }, .expect_err = error.InvalidByteSequence },
        .{ .bytes = &.{ 0xC0, 0x80 }, .expect_err = error.InvalidByteSequence },
        .{ .bytes = &.{ 0xC1, 0xBF }, .expect_err = error.InvalidByteSequence },
        .{ .bytes = &.{ 0xE0, 0x80, 0x80 }, .expect_err = error.OverlongEncoding },
        .{ .bytes = &.{ 0xF0, 0x80, 0x80, 0x80 }, .expect_err = error.OverlongEncoding },
        .{ .bytes = &.{ 0xED, 0xA0, 0x80 }, .expect_err = error.SurrogateCodePoint },
        .{ .bytes = &.{ 0xED, 0xBF, 0xBF }, .expect_err = error.SurrogateCodePoint },
        .{ .bytes = &.{ 0xF4, 0x90, 0x80, 0x80 }, .expect_err = error.CodePointTooLarge },
        .{ .bytes = &.{ 0xC2, 0x40 }, .expect_err = error.InvalidContinuationByte },
        .{ .bytes = &.{0xE1}, .expect_err = error.IndexOutOfBounds },
        .{ .bytes = &.{ 0xE1, 0x80 }, .expect_err = error.IndexOutOfBounds },
        .{ .bytes = &.{ 0xE1, 0x80, 0x28 }, .expect_err = error.InvalidContinuationByte },
        .{ .bytes = &.{ 0xF0, 0x9F }, .expect_err = error.IndexOutOfBounds },
        .{ .bytes = &.{0x80}, .expect_err = error.InvalidByteSequence },
    };

    for (cases) |c| {
        try std.testing.expectError(c.expect_err, validateAndDecodeCodePointBytes(c.bytes, 0));
    }

    // Where codePointLen(lead) exists, validateAndDecodeCodePointBytesWithLen uses the same body
    try std.testing.expectError(
        error.OverlongEncoding,
        validateAndDecodeCodePointBytes(&.{ 0xE0, 0x80, 0x80 }, 0),
    );
    try std.testing.expectError(
        error.IndexOutOfBounds,
        validateAndDecodeCodePointBytes(&.{0xC2}, 0),
    );
}

test "matrix: reverse-checked singles — codePointLenReverse vs validateAndDecodeCodePointBytesReverse" {
    // Truncated 3-byte lead: both reverse paths reject structural length mismatch
    try std.testing.expectError(
        error.InvalidByteSequence,
        codePointLenReverse(&.{ 0xE1, 0x80 }, 1),
    );
    try std.testing.expectError(
        error.InvalidByteSequence,
        validateAndDecodeCodePointBytesReverse(&.{ 0xE1, 0x80 }, 1),
    );

    try std.testing.expectError(
        error.InvalidByteSequence,
        codePointLenReverse(&.{0xE1}, 0),
    );
    try std.testing.expectError(
        error.InvalidByteSequence,
        validateAndDecodeCodePointBytesReverse(&.{0xE1}, 0),
    );
}

test "matrix: reverse decode API matches forward errors on isolated sequences" {
    // Notes: Reverse APIs decode the final scalar only. A buffer ending in legal ASCII peels that
    // byte first (e.g. F0…'(' yields '('), so isomorphism with forward-scan errors requires the
    // slice to encode exactly one malformed or illegal unit end-to-end.
    const Case = struct { bytes: []const u8, expect_err: UTF8ValidationError };
    const cases = [_]Case{
        .{ .bytes = &.{ 0xC0, 0x80 }, .expect_err = error.InvalidByteSequence },
        .{ .bytes = &.{ 0xE0, 0x80, 0x80 }, .expect_err = error.OverlongEncoding },
        .{ .bytes = &.{ 0xF0, 0x80, 0x80, 0x80 }, .expect_err = error.OverlongEncoding },
        .{ .bytes = &.{ 0xED, 0xA0, 0x80 }, .expect_err = error.SurrogateCodePoint },
        .{ .bytes = &.{ 0xF4, 0x90, 0x80, 0x80 }, .expect_err = error.CodePointTooLarge },
    };

    for (cases) |c| {
        try std.testing.expectError(c.expect_err, validateAndDecodeCodePointBytesReverse(c.bytes, c.bytes.len - 1));
    }

    try std.testing.expectError(error.ZeroLengthBytes, validateAndDecodeCodePointBytesReverse("", 0));

    try std.testing.expectError(
        error.InvalidByteSequence,
        validateAndDecodeCodePointBytesReverse(&.{ 0xE1, 0x80 }, 1),
    );
}

test "matrix: reverse last-byte heuristic — orphan lead + ASCII tail" {
    try std.testing.expectError(
        error.InvalidContinuationByte,
        validateAndDecodeCodePointBytes(&.{ 0xC2, 0x28 }, 0),
    );

    const d = try validateAndDecodeCodePointBytesReverse(&.{ 0xC2, 0x28 }, 1);
    try std.testing.expectEqual(@as(CodePoint, '('), d.code_point);
    try std.testing.expectEqual(@as(u3, 1), d.len);

    try std.testing.expectError(
        error.InvalidContinuationByte,
        validateAndDecodeCodePointBytes(&.{ 0xF0, 0x9F, 0x92, 0x28 }, 0),
    );
    const tail = try validateAndDecodeCodePointBytesReverse(&.{ 0xF0, 0x9F, 0x92, 0x28 }, 3);
    try std.testing.expectEqual(@as(CodePoint, '('), tail.code_point);
    try std.testing.expectEqual(@as(u3, 1), tail.len);
}

test "matrix: initUTF8View error position and resultant length on success" {
    var size: usize = undefined;

    var z: usize = 0;
    _ = try initUTF8View("", &z);
    try std.testing.expectEqual(@as(usize, 0), z);

    _ = try initUTF8View("αβγ", &size);
    try std.testing.expectEqual(@as(usize, 3), size);

    // First rejection wins after valid prefix
    try std.testing.expectError(error.InvalidByteSequence, initUTF8View("pq\xFE", &size));
    try std.testing.expectError(error.OverlongEncoding, initUTF8View("SAFE\xE0\x80\x80TAIL", &size));

    try std.testing.expectError(error.CodePointTooLarge, initUTF8View(&.{ 'z', 0xF4, 0x90, 0x80, 0x80 }, &size));
}

test "matrix: string conversion APIs propagate validation" {
    var size: usize = 0;

    const view_delta = try initUTF8View("Δ", &size);
    try std.testing.expectError(error.BufferTooSmall, utf8ViewToUTF8String(&view_delta, &[_]CodePoint{}));
    // Buffer exactly sized succeeds
    var buf_two: [2]CodePoint = undefined;
    const view_two = try initUTF8View("αβ", &size);
    try std.testing.expectEqual(@as(usize, 2), try utf8ViewToUTF8String(&view_two, buf_two[0..]));

    try std.testing.expectError(error.SurrogateCodePoint, bytesToUTF8String(std.testing.allocator, &.{ 0xED, 0xAD, 0xBF }));

    try std.testing.expectError(
        error.InvalidByteSequence,
        bytesToUTF8String(std.testing.allocator, &.{ 'q', 0xF5, 0x80, 0x80, 0x80 }),
    );

    try std.testing.expectError(
        error.InvalidContinuationByte,
        bytesToUTF8String(std.testing.allocator, "\xCF\xCF"),
    );
}

test "matrix: bytesToUTF8String OutOfMemory propagates from alloc path" {
    var failing_allocator_state = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = 0,
    });
    const failing = failing_allocator_state.allocator();
    try std.testing.expectError(
        error.OutOfMemory,
        bytesToUTF8String(failing, "ab"),
    );
}

test "matrix: compile-time initUTF8View rejects illegal bytes" {
    const invalid_lead = comptime blk: {
        var scalar_count: usize = 0;
        break :blk initUTF8View("\xff", &scalar_count);
    };
    try std.testing.expectError(error.InvalidByteSequence, invalid_lead);

    const surrogate_seq = comptime blk: {
        var scalar_count: usize = 0;
        break :blk initUTF8View(&.{ 0xED, 0xA0, 0x80 }, &scalar_count);
    };
    try std.testing.expectError(error.SurrogateCodePoint, surrogate_seq);

    _ = try comptime blk: {
        var scalar_count: usize = 0;
        break :blk initUTF8View("Σ", &scalar_count);
    };
}

test "matrix: surrogate boundary around ED xx (forward + reverse APIs)" {
    const low = [_]u8{ 0xED, 0x9F, 0xBF };
    try std.testing.expectEqual(@as(u3, 3), (try validateAndDecodeCodePointBytes(&low, 0)).len);
    try std.testing.expectEqual(@as(CodePoint, 0xD7FF), (try validateAndDecodeCodePointBytes(&low, 0)).code_point);
    try std.testing.expectEqual(@as(CodePoint, 0xD7FF), (try validateAndDecodeCodePointBytesReverse(&low, low.len - 1)).code_point);

    // Third byte is not a UTF-8 continuation → structural error precedes surrogate check
    try std.testing.expectError(
        error.InvalidContinuationByte,
        validateAndDecodeCodePointBytes(&.{ 0xED, 0xA0, 0x7F }, 0),
    );
    try std.testing.expectError(
        error.InvalidContinuationByte,
        validateAndDecodeCodePointBytes(&.{ 0xED, 0x90, 0x28 }, 0),
    );
}

test "matrix: F4 second-byte boundary CodePointTooLarge vs legal max" {
    try std.testing.expectError(
        error.CodePointTooLarge,
        validateAndDecodeCodePointBytes(&.{ 0xF4, 0x90, 0x80, 0x80 }, 0),
    );
    try std.testing.expectError(
        error.InvalidContinuationByte,
        validateAndDecodeCodePointBytes(&.{ 0xF4, 0xCF, 0xBF, 0xBF }, 0),
    );
    const max_enc = [_]u8{ 0xF4, 0x8F, 0xBF, 0xBF };
    try std.testing.expectEqual(@as(CodePoint, 0x10FFFF), (try validateAndDecodeCodePointBytes(&max_enc, 0)).code_point);
    try std.testing.expectEqual(@as(CodePoint, 0x10FFFF), (try validateAndDecodeCodePointBytesReverse(&max_enc, max_enc.len - 1)).code_point);
}

test "matrix: four trailing continuation bytes before lead is illegal" {
    const tail = [_]u8{ 0x80, 0x80, 0x80, 0x80, 0xC2 };
    try std.testing.expectError(
        error.InvalidByteSequence,
        codePointLenReverse(&tail, tail.len - 1),
    );
    try std.testing.expectError(
        error.InvalidByteSequence,
        validateAndDecodeCodePointBytesReverse(&tail, tail.len - 1),
    );
}

test "lossy: orphan continuation collapse" {
    const d = try validateAndDecodeCodePointBytesLossy(
        &.{ 0x80, 0x80, 0x80, 'a' },

        0,
    );
    try std.testing.expectEqual(INVALID_CODE_POINT, d.code_point);
    try std.testing.expectEqual(@as(usize, 3), d.len);

    const next = try validateAndDecodeCodePointBytesLossy(
        &.{ 0x80, 0x80, 0x80, 'a' },
        d.len,
    );
    try std.testing.expectEqual(@as(CodePoint, 'a'), next.code_point);
}

test "lossy: malformed lead preserves trailing ascii" {
    const d = try validateAndDecodeCodePointBytesLossy(
        &.{ 0xF0, 0x9F, 0x92, '(' },
        0,
    );
    try std.testing.expectEqual(INVALID_CODE_POINT, d.code_point);
    try std.testing.expectEqual(@as(usize, 3), d.len);

    const next = try validateAndDecodeCodePointBytesLossy(
        &.{ 0xF0, 0x9F, 0x92, '(' },
        3,
    );
    try std.testing.expectEqual(@as(CodePoint, '('), next.code_point);
}

test "lossy: over-longs collapse correctly" {
    const d = try validateAndDecodeCodePointBytesLossy(
        &.{ 0xF0, 0x80, 0x80, 0x80 },
        0,
    );
    try std.testing.expectEqual(INVALID_CODE_POINT, d.code_point);
    try std.testing.expectEqual(@as(usize, 4), d.len);
}

test "lossy: surrogate sequence replaced" {
    const d = try validateAndDecodeCodePointBytesLossy(
        &.{ 0xED, 0xA0, 0x80 },
        0,
    );
    try std.testing.expectEqual(INVALID_CODE_POINT, d.code_point);
    try std.testing.expectEqual(@as(usize, 3), d.len);
}

test "lossy: iterator and materialization replace malformed spans" {
    const input = [_]u8{ 'A', 0xF0, 0x9F, 0x92, '(', 0x80, 0x80, 'B' };
    var iter = lossyIterator(&input);

    try std.testing.expectEqual(@as(?CodePoint, 'A'), iter.next());
    try std.testing.expectEqual(@as(?CodePoint, INVALID_CODE_POINT), iter.next());
    try std.testing.expectEqual(@as(?CodePoint, '('), iter.next());
    try std.testing.expectEqual(@as(?CodePoint, INVALID_CODE_POINT), iter.next());
    try std.testing.expectEqual(@as(?CodePoint, 'B'), iter.next());
    try std.testing.expectEqual(@as(?CodePoint, null), iter.next());

    try std.testing.expectEqual(@as(usize, 5), countScalarsLossy(&input));

    var out: [5]CodePoint = undefined;
    const n = try bytesToCodePointsLossyBuffer(&input, &out);
    try std.testing.expectEqual(@as(usize, 5), n);
    try std.testing.expectEqualSlices(CodePoint, &.{ 'A', INVALID_CODE_POINT, '(', INVALID_CODE_POINT, 'B' }, out[0..n]);
}

test "encodeCodePoint public wrapper" {
    var buf: [4]u8 = undefined;
    const len = try encodeCodePoint(0x20AC, &buf);
    try std.testing.expectEqual(@as(u3, 3), len);
    try std.testing.expectEqualSlices(u8, &.{ 0xE2, 0x82, 0xAC }, buf[0..len]);
}

test "iterator: next then previous returns same scalar" {
    var view = initUTF8ViewUnchecked("a€😀");
    var it = view.iter();
    const a = it.next().?;
    try std.testing.expectEqual(a, it.previous().?);
    const again = it.next().?;
    try std.testing.expectEqual(a, again);
}

test "sliceScalars: multi-byte exact boundaries" {
    const view = initUTF8ViewUnchecked("a€😀z");
    const s1 = try view.sliceScalars(1, 2);
    try std.testing.expectEqualStrings("€", s1.data);
    const s2 = try view.sliceScalars(2, 3);
    try std.testing.expectEqualStrings("😀", s2.data);
}

test "sliceScalars: all scalar windows" {
    const view = initUTF8ViewUnchecked("a€😀b");

    var start: usize = 0;

    while (start <= view.countScalar()) : (start += 1) {
        var end = start;
        while (end <= view.countScalar()) : (end += 1) {
            const s = try view.sliceScalars(start, end);
            var size: usize = 0;
            _ = try initUTF8View(s.data, &size);
        }
    }
}

test "encode exact vectors" {
    var buf: [4]u8 = undefined;
    _ = try encode(0x24, &buf);
    try std.testing.expectEqualSlices(u8, &.{0x24}, buf[0..1]);
    _ = try encode(0xA2, &buf);
    try std.testing.expectEqualSlices(u8, &.{ 0xC2, 0xA2 }, buf[0..2]);
    _ = try encode(0x20AC, &buf);
    try std.testing.expectEqualSlices(u8, &.{ 0xE2, 0x82, 0xAC }, buf[0..3]);
    _ = try encode(0x1F600, &buf);
    try std.testing.expectEqualSlices(u8, &.{ 0xF0, 0x9F, 0x98, 0x80 }, buf[0..4]);
}

test "checked and unchecked decode agree on valid utf8" {
    const s = "a€😀";
    var i: usize = 0;

    while (i < s.len) {
        const checked = try validateAndDecodeCodePointBytes(s, i);
        const unchecked = bytesToUTF8CodePoint(s, i);
        try std.testing.expectEqual(
            checked.code_point,
            unchecked.code_point,
        );
        try std.testing.expectEqual(
            checked.len,
            unchecked.len,
        );
        i += checked.len;
    }
}

test "hostile: every possible byte in lossy decoder makes progress" {
    var bytes: [256]u8 = undefined;
    for (&bytes, 0..) |*byte, i| {
        byte.* = @intCast(i);
    }

    var i: usize = 0;
    var replacements: usize = 0;
    while (i < bytes.len) {
        const decoded = try validateAndDecodeCodePointBytesLossy(&bytes, i);
        try std.testing.expect(decoded.len > 0);
        try std.testing.expect(i + decoded.len <= bytes.len);
        if (decoded.code_point == INVALID_CODE_POINT) {
            replacements += 1;
        }
        i += decoded.len;
    }

    try std.testing.expect(replacements > 0);
}

test "hostile: invalid continuation matrix for legal UTF-8 leads" {
    var lead_u16: u16 = two_byte_start_sequence_range_start;
    while (lead_u16 <= two_byte_start_sequence_range_end) : (lead_u16 += 1) {
        var byte_u16: u16 = 0;
        while (byte_u16 <= 0xFF) : (byte_u16 += 1) {
            const second: u8 = @intCast(byte_u16);
            if (isContinuationByte(second)) continue;

            try std.testing.expectError(
                error.InvalidContinuationByte,
                validateAndDecodeCodePointBytes(&.{ @intCast(lead_u16), second }, 0),
            );
        }
    }

    const bad_three = [_][]const u8{
        &.{ 0xE0, 0x7F, 0x80 },
        &.{ 0xE1, 0x80, 0x7F },
        &.{ 0xEF, 0xC0, 0x80 },
    };
    for (bad_three) |bytes| {
        try std.testing.expectError(error.InvalidContinuationByte, validateAndDecodeCodePointBytes(bytes, 0));
    }

    const bad_four = [_][]const u8{
        &.{ 0xF0, 0x7F, 0x80, 0x80 },
        &.{ 0xF1, 0x80, 0x7F, 0x80 },
        &.{ 0xF4, 0x8F, 0x80, 0x7F },
    };
    for (bad_four) |bytes| {
        try std.testing.expectError(error.InvalidContinuationByte, validateAndDecodeCodePointBytes(bytes, 0));
    }
}

test "hostile: every truncated UTF-8 prefix rejects without decoding" {
    const cases = [_][]const u8{
        &.{0xC2},
        &.{0xDF},
        &.{0xE0},
        &.{ 0xE0, 0xA0 },
        &.{0xEF},
        &.{ 0xEF, 0xBF },
        &.{0xF0},
        &.{ 0xF0, 0x90 },
        &.{ 0xF0, 0x90, 0x80 },
        &.{0xF4},
        &.{ 0xF4, 0x8F },
        &.{ 0xF4, 0x8F, 0xBF },
    };

    for (cases) |bytes| {
        try std.testing.expectError(error.IndexOutOfBounds, validateAndDecodeCodePointBytes(bytes, 0));
    }
}

test "hostile: continuation-only reverse tails always reject" {
    const tail = [_]u8{ 0x80, 0x81, 0x82, 0x83, 0x84, 0xBF, 0x80, 0xBF };

    var len: usize = 1;
    while (len <= tail.len) : (len += 1) {
        try std.testing.expectError(error.InvalidByteSequence, codePointLenReverse(tail[0..len], len - 1));
        try std.testing.expectError(error.InvalidByteSequence, validateAndDecodeCodePointBytesReverse(tail[0..len], len - 1));
    }
}

test "hostile: encodeCodePoint rejects every undersized output buffer" {
    const cases = [_]CodePoint{ 0x80, 0x800, 0x10000, 0x10FFFF };
    var backing: [4]u8 = undefined;

    for (cases) |code_point| {
        const len = utf8EncodeLen(code_point);
        var out_len: usize = 0;
        while (out_len < len) : (out_len += 1) {
            try std.testing.expectError(error.BufferTooSmall, encodeCodePoint(code_point, backing[0..out_len]));
        }
    }
}
