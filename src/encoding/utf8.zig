const std = @import("std");
const encoding = @import("root.zig");

const CodePoint = encoding.CodePoint;
const INVALID_CODE_POINT = encoding.INVALID_CODE_POINT;

const encoding_range_start = 0x0000;
const encoding_range_end = 0x10FFFF;

const max_ascii = encoding.max_ascii;

// Surrogate range
const surrogate_range_start = 0xD800;
const surrogate_range_end = 0xDFFF;

// Continuation byte
const continuation_sequence = 0b1000_0000;
const continuation_sequence_mask = 0b1100_0000;
const continuation_payload_mask = 0b0011_1111;
const continuation_mask_inverse = 0b0011_1111;

// 2-byte sequence
const two_byte_start_sequence_range_start = 0xC2;
const two_byte_start_sequence_range_end = 0xDF;
const two_byte_lead_byte_prefix = 0b1100_0000;
const two_byte_payload_mask = 0b0001_1111;
const two_byte_mask_inverse = 0b0001_1111;

// 3-byte sequence
const three_byte_start_sequence_range_start = 0xE0;
const three_byte_start_sequence_range_end = 0xEF;
const three_byte_payload_mask = 0b0000_1111;
const three_byte_mask_inverse = 0b0000_1111;

// 4-byte sequence
const four_byte_start_sequence_range_start = 0xF0;
const four_byte_start_sequence_range_end = 0xF4;
const four_byte_payload_mask = 0b0000_0111;
const four_byte_mask_inverse = 0b0000_0111;
const four_byte_range_start = 0x10000;
const four_byte_range_end = 0x10FFFF;

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
        (@as(u21, 0xff) >> @intCast(t)) & byte;

    state.* = hoehrmann_utf8_decode_table[256 + state.* * 16 + t];

    return switch (state.*) {
        UTF8_ACCEPT => .accept,
        UTF8_REJECT => .reject,
        else => .incomplete,
    };
}

inline fn validateCodePoint(bytes: []const u8, offset: usize) !DecodedCodePoint {
    if (bytes.len <= offset) {
        return UTF8ValidationError.IndexOutOfBounds;
    }

    var i: usize = 0;

    var state: u32 = UTF8_ACCEPT;
    var code_point: CodePoint = 0;

    for (bytes[offset..]) |b| {
        const decoded = decodeByte(&state, &code_point, b);
        i += 1;

        if (decoded == .accept) {
            return .{ .code_point = @as(u21, code_point), .len = @as(u3, @intCast(i)) };
        } else if (decoded == .reject) {
            return UTF8ValidationError.InvalidByteSequence;
        }
    }

    return UTF8ValidationError.InvalidByteSequence;
}

inline fn countScalars(bytes: []const u8) !usize {
    var state: u32 = UTF8_ACCEPT;
    var code_point: u21 = 0;
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

pub fn codePointLen(byte: u8) UTF8ValidationError!u3 {
    if (byte <= max_ascii) {
        @branchHint(.likely);
        return 1;
    } else if (byte >= two_byte_start_sequence_range_start and
        byte <= two_byte_start_sequence_range_end)
    {
        return 2;
    } else if (byte >= three_byte_start_sequence_range_start and
        byte <= three_byte_start_sequence_range_end)
    {
        return 3;
    } else if (byte >= four_byte_start_sequence_range_start and
        byte <= four_byte_start_sequence_range_end)
    {
        return 4;
    } else return error.InvalidByteSequence;
}

/// Returns `0` for any incompatible sequence including the
/// continuation byte sequence.
fn codePointLenLossy(byte: u8) u3 {
    if (byte <= max_ascii) {
        @branchHint(.likely);
        return 1;
    } else if (byte >= two_byte_start_sequence_range_start and
        byte <= two_byte_start_sequence_range_end)
    {
        return 2;
    } else if (byte >= three_byte_start_sequence_range_start and
        byte <= three_byte_start_sequence_range_end)
    {
        return 3;
    } else if (byte >= four_byte_start_sequence_range_start and
        byte <= four_byte_start_sequence_range_end)
    {
        return 4;
    } else return 0;
}

pub fn utf8EncodeLen(code_point: CodePoint) UTF8EncodeError!u3 {
    if (code_point > encoding_range_end) {
        return error.CodePointTooLarge;
    }

    if (code_point >= surrogate_range_start and code_point <= surrogate_range_end) {
        return error.SurrogateCodePoint;
    }

    if (code_point <= max_ascii) {
        @branchHint(.likely);
        return 1;
    }

    return switch (code_point) {
        min_four_byte_code_point...max_four_byte_code_point => 4,
        min_three_byte_code_point...max_three_byte_code_point => 3,
        min_two_byte_code_point...max_two_byte_code_point => 2,
        else => unreachable,
    };
}

inline fn isContinuationByte(byte: u8) bool {
    return (byte & continuation_sequence_mask) == continuation_sequence;
}

// Any sequence that is not leader
// like `11111101` `11111000`
fn isLeaderByte(byte: u8) bool {
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
    if (!isContinuationByte(bytes[offset + 1])) {
        return UTF8ValidationError.InvalidContinuationByte;
    }

    if (len >= 3 and !isContinuationByte(bytes[offset + 2])) {
        return UTF8ValidationError.InvalidContinuationByte;
    }

    if (len == 4 and !isContinuationByte(bytes[offset + 3])) {
        return UTF8ValidationError.InvalidContinuationByte;
    }

    // Structural UTF-8 legality constraints

    var code_point: CodePoint = undefined;

    if (len == 2) {
        code_point = (@as(CodePoint, bytes[offset] & two_byte_payload_mask) << 6) |
            (@as(CodePoint, bytes[offset + 1] & continuation_payload_mask));

        return .{ .code_point = code_point, .len = 2 };
    }

    if (len == 3) {
        if (bytes[offset] == 0xE0 and bytes[offset + 1] < 0xA0) {
            return UTF8ValidationError.OverlongEncoding;
        } else if (bytes[offset] == 0xED and bytes[offset + 1] >= 0xA0) {
            return UTF8ValidationError.SurrogateCodePoint;
        }

        code_point = (@as(CodePoint, bytes[offset] & three_byte_payload_mask) << 12) |
            (@as(CodePoint, bytes[offset + 1] & continuation_payload_mask) << 6) |
            (@as(CodePoint, bytes[offset + 2] & continuation_payload_mask));

        return .{ .code_point = code_point, .len = 3 };
    }

    if (len == 4) {
        if (bytes[offset] == 0xF0 and bytes[offset + 1] < 0x90) {
            return UTF8ValidationError.OverlongEncoding;
        } else if (bytes[offset] == 0xF4 and bytes[offset + 1] > 0x8F) {
            return UTF8ValidationError.CodePointTooLarge;
        }

        code_point = (@as(CodePoint, bytes[offset] & four_byte_payload_mask) << 18) |
            (@as(CodePoint, bytes[offset + 1] & continuation_payload_mask) << 12) |
            (@as(CodePoint, bytes[offset + 2] & continuation_payload_mask) << 6) |
            (@as(CodePoint, bytes[offset + 3] & continuation_payload_mask));

        return .{ .code_point = code_point, .len = 4 };
    }

    unreachable;
}

/// Pass entire string with offset to avoid reconstructing slice struct in hot paths.
inline fn validateAndDecodeCodePointBytesWithLen(bytes: []const u8, offset: usize, len: u3) UTF8ValidationError!DecodedCodePoint {
    if (bytes.len - offset < @as(usize, len)) {
        return UTF8ValidationError.IndexOutOfBounds;
    }

    // ASCII fast path
    if (len == 1) {
        @branchHint(.likely);
        return .{ .code_point = bytes[offset], .len = 1 };
    }

    return validateAndDecodeNonAscii(bytes, offset, len);
}

pub inline fn validateAndDecodeCodePointBytes(bytes: []const u8, offset: usize) UTF8ValidationError!DecodedCodePoint {
    if (bytes.len == 0) {
        return UTF8ValidationError.ZeroLengthBytes;
    } else if (offset >= bytes.len) {
        return UTF8ValidationError.IndexOutOfBounds;
    }

    const b = bytes[offset];

    if (b <= max_ascii) {
        @branchHint(.likely);
        return .{ .code_point = @as(CodePoint, b), .len = 1 };
    }

    const len = try codePointLen(bytes[offset]);

    return validateAndDecodeNonAscii(bytes, offset, len);
}

/// the len argument expects an optimistic len of the code point
fn validateAndDecodeCodePointBytesWithLenLossy(bytes: []const u8, offset: usize, len: u3) UTF8ValidationLossyError!DecodedCodePointLossy {
    const remaining = bytes.len - offset;

    if (len > 1 and len <= 4) {
        // validate if the successive byte is an continuation sequence
        if (remaining < 2 or !isContinuationByte(bytes[offset + 1])) {
            return .{ .code_point = INVALID_CODE_POINT, .len = 1 };
        } else if (len == 2) {
            const code_point = (@as(CodePoint, bytes[offset] & two_byte_payload_mask) << 6) |
                (@as(CodePoint, bytes[offset + 1] & continuation_payload_mask));

            return .{ .code_point = code_point, .len = 2 };
        }

        if (remaining < 3 or !isContinuationByte(bytes[offset + 2])) {
            return .{ .code_point = INVALID_CODE_POINT, .len = 2 };
        } else if (len == 3) {
            if (bytes[offset] == 0xE0 and bytes[offset + 1] < 0xA0) {
                // overlong character
                return .{ .code_point = INVALID_CODE_POINT, .len = 3 };
            } else if (bytes[offset] == 0xED and bytes[offset + 1] >= 0xA0) {
                // surrogate code point
                return .{ .code_point = INVALID_CODE_POINT, .len = 3 };
            }

            const code_point = (@as(CodePoint, bytes[offset] & three_byte_payload_mask) << 12) |
                (@as(CodePoint, bytes[offset + 1] & continuation_payload_mask) << 6) |
                (@as(CodePoint, bytes[offset + 2] & continuation_payload_mask));

            return .{ .code_point = code_point, .len = 3 };
        }

        if (remaining < 4 or !isContinuationByte(bytes[offset + 3])) {
            return .{ .code_point = INVALID_CODE_POINT, .len = 3 };
        } else {
            if (bytes[offset] == 0xF0 and bytes[offset + 1] < 0x90) {
                // overlong character
                return .{ .code_point = INVALID_CODE_POINT, .len = 4 };
            } else if (bytes[offset] == 0xF4 and bytes[offset + 1] > 0x8F) {
                // too large code point
                return .{ .code_point = INVALID_CODE_POINT, .len = 4 };
            }

            const code_point = (@as(CodePoint, bytes[offset] & four_byte_payload_mask) << 18) |
                (@as(CodePoint, bytes[offset + 1] & continuation_payload_mask) << 12) |
                (@as(CodePoint, bytes[offset + 2] & continuation_payload_mask) << 6) |
                (@as(CodePoint, bytes[offset + 3] & continuation_payload_mask));

            return .{ .code_point = code_point, .len = 4 };
        }
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
    if (len == 0) {
        var i: usize = 0;

        while (i < remaining) {
            const byte = bytes[offset + i];
            if (isLeaderByte(byte) or byte <= max_ascii) {
                break;
            }
            i += 1;
        }

        return .{ .code_point = INVALID_CODE_POINT, .len = i };
    }

    unreachable;
}

pub fn validateAndDecodeCodePointBytesLossy(bytes: []const u8, offset: usize) UTF8ValidationLossyError!DecodedCodePointLossy {
    if (bytes.len == 0) {
        return UTF8ValidationLossyError.ZeroLengthBytes;
    } else if (offset >= bytes.len) {
        return UTF8ValidationLossyError.IndexOutOfBounds;
    }

    const b = bytes[offset];

    if (b <= max_ascii) {
        return .{ .code_point = @as(CodePoint, b), .len = 1 };
    }

    const len = codePointLenLossy(bytes[offset]);

    return validateAndDecodeCodePointBytesWithLenLossy(bytes, offset, len);
}

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

pub fn validateAndDecodeCodePointBytesReverse(bytes: []const u8, end_index: usize) UTF8ValidationError!DecodedCodePoint {
    if (bytes.len == 0) {
        return UTF8ValidationError.ZeroLengthBytes;
    } else if (end_index >= bytes.len) {
        return UTF8ValidationError.IndexOutOfBounds;
    }

    // ASCII fast path
    if (bytes[end_index] <= max_ascii) {
        @branchHint(.likely);
        return .{ .code_point = bytes[end_index], .len = 1 };
    }

    const len = try codePointLenReverse(bytes, end_index);

    const start = end_index + 1 - @as(usize, len);

    return validateAndDecodeCodePointBytesWithLen(bytes, start, len);
}

fn validateCodePointBytesReverse(bytes: []const u8, end_index: usize) UTF8ValidationError!u3 {
    if (bytes.len == 0) {
        return UTF8ValidationError.ZeroLengthBytes;
    } else if (end_index >= bytes.len) {
        return UTF8ValidationError.IndexOutOfBounds;
    }

    if (bytes[end_index] <= max_ascii) {
        return 1;
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

    const validated = try validateAndDecodeCodePointBytes(bytes, start);
    return validated.len;
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
        1 => .{
            .code_point = bytes[offset],
            .len = 1,
        },

        2 => .{
            .code_point = (@as(CodePoint, bytes[offset] & two_byte_payload_mask) << 6) |
                (@as(CodePoint, bytes[offset + 1] & continuation_payload_mask)),
            .len = 2,
        },

        3 => .{
            .code_point = (@as(CodePoint, bytes[offset] & three_byte_payload_mask) << 12) |
                (@as(CodePoint, bytes[offset + 1] & continuation_payload_mask) << 6) |
                (@as(CodePoint, bytes[offset + 2] & continuation_payload_mask)),
            .len = 3,
        },

        4 => .{
            .code_point = (@as(CodePoint, bytes[offset] & four_byte_payload_mask) << 18) |
                (@as(CodePoint, bytes[offset + 1] & continuation_payload_mask) << 12) |
                (@as(CodePoint, bytes[offset + 2] & continuation_payload_mask) << 6) |
                (@as(CodePoint, bytes[offset + 3] & continuation_payload_mask)),
            .len = 4,
        },

        else => unreachable,
    };
}

fn encode(code_point: CodePoint, bytes: []u8) UTF8EncodeError!u3 {
    if (code_point >= surrogate_range_start and code_point <= surrogate_range_end) {
        return error.SurrogateCodePoint;
    }

    const len = try utf8EncodeLen(code_point);

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

        else => return error.InvalidByteSequence,
    }

    return len;
}

pub fn encodeCodePoint(code_point: CodePoint, bytes: []u8) UTF8EncodeError!u3 {
    return encode(code_point, bytes);
}

fn decodeCodePointReverse(bytes: []const u8, end_index: usize) DecodedCodePoint {
    const len = codePointLenReverse(bytes, end_index) catch unreachable;
    const start = end_index + 1 - @as(usize, len);

    return decode(bytes, start, len);
}

fn decodeCodePointReverseUnchecked(bytes: []const u8, end_index: usize) DecodedCodePoint {
    const len = codePointLenReverseUnchecked(bytes, end_index) catch unreachable;
    const start = end_index + 1 - @as(usize, len);

    return decode(bytes, start, len);
}

fn bytesToUTF8CodePoint(bytes: []const u8, offset: usize) DecodedCodePoint {
    const len = codePointLen(bytes[offset]) catch unreachable;

    if (len == 1 and bytes[offset] <= max_ascii) {
        return .{ .code_point = @as(CodePoint, bytes[offset]), .len = 1 };
    }

    return decode(bytes, offset, len);
}

pub const UTF8SliceError = error{
    IndexOutOfBounds,
    InvalidBoundary,
};

pub const UTF8ViewIterator = struct {
    index: usize = 0,
    view: *const UTF8View,
    /// A cache for the current code point
    curr: ?CodePoint = null,

    pub fn next(self: *UTF8ViewIterator) ?CodePoint {
        if (self.index >= self.view.data.len) {
            return null;
        }

        const code_point = bytesToUTF8CodePoint(self.view.data, self.index);

        self.index += @as(usize, code_point.len);
        self.curr = code_point.code_point;

        return self.curr orelse unreachable;
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
        self.curr = code_point.code_point;

        return self.curr.?;
    }

    pub fn peekPrevious(self: *const UTF8ViewIterator) ?CodePoint {
        if (self.index == 0) {
            return null;
        }

        return decodeCodePointReverseUnchecked(self.view.data, self.index - 1).code_point;
    }
};

pub const UTF8View = struct {
    data: []const u8,

    pub fn countScalar(self: *const UTF8View) usize {
        var count: usize = 0;
        var i: usize = 0;

        while (i < self.data.len) {
            const byte = self.data[i];

            if (byte <= max_ascii) {
                i += 1;
                count += 1;
                continue;
            }

            const len = codePointLen(byte) catch unreachable;

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

            if (byte <= max_ascii) {
                byte_index += 1;
            } else {
                const len = codePointLen(byte) catch unreachable;
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

pub const UTF8LossyIterator = struct {
    data: []const u8,
    index: usize = 0,
    curr: ?CodePoint = null,

    pub fn next(self: *UTF8LossyIterator) ?CodePoint {
        if (self.index >= self.data.len) {
            return null;
        }

        const decoded = validateAndDecodeCodePointBytesLossy(self.data, self.index) catch unreachable;
        std.debug.assert(decoded.len > 0);
        self.index += decoded.len;
        self.curr = decoded.code_point;
        return decoded.code_point;
    }

    pub fn peek(self: *const UTF8LossyIterator) ?CodePoint {
        if (self.index >= self.data.len) {
            return null;
        }

        return (validateAndDecodeCodePointBytesLossy(self.data, self.index) catch unreachable).code_point;
    }
};

pub fn lossyIterator(bytes: []const u8) UTF8LossyIterator {
    return .{ .data = bytes };
}

pub fn countScalarsLossy(bytes: []const u8) usize {
    var count: usize = 0;
    var iter = lossyIterator(bytes);

    while (iter.next()) |_| {
        count += 1;
    }

    return count;
}

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

pub fn bytesToCodePointsLossy(allocator: std.mem.Allocator, bytes: []const u8) error{ OutOfMemory, BufferTooSmall }![]CodePoint {
    const len = countScalarsLossy(bytes);
    const out = try allocator.alloc(CodePoint, len);
    errdefer allocator.free(out);

    _ = try bytesToCodePointsLossyBuffer(bytes, out);
    return out;
}

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

pub fn initUTF8ViewUnchecked(data: []const u8) UTF8View {
    return .{ .data = data };
}

pub fn utf8ViewToUTF8String(view: *const UTF8View, buf: []u21) (UTF8ValidationError || error{BufferTooSmall})!usize {
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

pub fn bytesToUTF8StringComptime(comptime bytes: []const u8) (UTF8ValidationError || error{BufferTooSmall})![countScalars(bytes) catch {}]u21 {
    comptime {
        var unicode_str_len: usize = 0;

        const utf8_view = try initUTF8View(bytes, &unicode_str_len);
        var buf: [unicode_str_len]u21 = undefined;

        _ = try utf8ViewToUTF8String(&utf8_view, &buf);

        return buf;
    }
}

pub fn bytesToUTF8String(allocator: std.mem.Allocator, bytes: []const u8) (UTF8ValidationError || error{ BufferTooSmall, OutOfMemory })![]u21 {
    var unicode_str_len: usize = 0;
    const utf8_view = try initUTF8View(bytes, &unicode_str_len);
    const buf = try allocator.alloc(u21, unicode_str_len);
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

test "validateCodePoint: ascii" {
    const d = try validateCodePoint("A", 0);

    try std.testing.expectEqual(
        @as(CodePoint, 'A'),
        d.code_point,
    );

    try std.testing.expectEqual(
        @as(u3, 1),
        d.len,
    );
}

test "validateCodePoint: multibyte scalar" {
    const d = try validateCodePoint("€", 0);

    try std.testing.expectEqual(
        @as(CodePoint, 0x20AC),
        d.code_point,
    );

    try std.testing.expectEqual(
        @as(u3, 3),
        d.len,
    );
}

test "validateCodePoint: emoji" {
    const d = try validateCodePoint("😀", 0);

    try std.testing.expectEqual(
        @as(CodePoint, 0x1F600),
        d.code_point,
    );

    try std.testing.expectEqual(
        @as(u3, 4),
        d.len,
    );
}

test "validateCodePoint: malformed rejects" {
    try std.testing.expectError(
        UTF8ValidationError.InvalidByteSequence,
        validateCodePoint(
            &.{ 0xF0, 0x28, 0x8C, 0x28 },
            0,
        ),
    );
}

test "validateCodePoint: truncated sequence rejects" {
    try std.testing.expectError(
        UTF8ValidationError.InvalidByteSequence,
        validateCodePoint(
            &.{ 0xE2, 0x82 },
            0,
        ),
    );
}

test "validateCodePoint: offset works correctly" {
    const s = "a😀b";

    const d = try validateCodePoint(s, 1);

    try std.testing.expectEqual(
        @as(CodePoint, 0x1F600),
        d.code_point,
    );

    try std.testing.expectEqual(
        @as(u3, 4),
        d.len,
    );
}

test "codePointLen: ASCII and classification edge bytes" {
    try std.testing.expectEqual(@as(u3, 1), try codePointLen(0));
    try std.testing.expectEqual(@as(u3, 1), try codePointLen(max_ascii));
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
    try std.testing.expectEqual(@as(u3, 1), try utf8EncodeLen(0));
    try std.testing.expectEqual(@as(u3, 1), try utf8EncodeLen(max_ascii));
    try std.testing.expectEqual(@as(u3, 2), try utf8EncodeLen(min_two_byte_code_point));
    try std.testing.expectEqual(@as(u3, 2), try utf8EncodeLen(max_two_byte_code_point));
    try std.testing.expectEqual(@as(u3, 3), try utf8EncodeLen(min_three_byte_code_point));
    try std.testing.expectEqual(@as(u3, 3), try utf8EncodeLen(max_three_byte_code_point));
    try std.testing.expectEqual(@as(u3, 4), try utf8EncodeLen(min_four_byte_code_point));
    try std.testing.expectEqual(@as(u3, 4), try utf8EncodeLen(max_four_byte_code_point));
    try std.testing.expectError(error.SurrogateCodePoint, utf8EncodeLen(surrogate_range_start));
    try std.testing.expectError(error.SurrogateCodePoint, utf8EncodeLen(surrogate_range_end));
    try std.testing.expectError(error.SurrogateCodePoint, utf8EncodeLen(0xD800));
    try std.testing.expectError(error.CodePointTooLarge, utf8EncodeLen(encoding_range_end + 1));
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

test "codePointLenReverse and validateCodePointBytesReverse" {
    try std.testing.expectError(UTF8ValidationError.ZeroLengthBytes, codePointLenReverse(&.{}, 0));

    const one = "x";
    try std.testing.expectEqual(@as(u3, 1), try codePointLenReverse(one, one.len - 1));
    try std.testing.expectEqual(@as(u3, 1), try validateCodePointBytesReverse(one, one.len - 1));

    const four = [_]u8{ 0xF0, 0x90, 0x80, 0x80 };
    try std.testing.expectEqual(@as(u3, 4), try codePointLenReverse(&four, four.len - 1));
    try std.testing.expectEqual(@as(u3, 4), try validateCodePointBytesReverse(&four, four.len - 1));

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
        try std.testing.expectEqual(try utf8EncodeLen(cp), len);
        const got = decode(&buf, 0, len);
        try std.testing.expectEqual(cp, got.code_point);
    }
}

test "encode rejects surrogates; buffer too small" {
    var buf: [4]u8 = undefined;
    try std.testing.expectError(error.SurrogateCodePoint, encode(surrogate_range_start, &buf));
    try std.testing.expectError(error.SurrogateCodePoint, encode(surrogate_range_end, &buf));

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
    var buf: [3]u21 = undefined;
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

test "bytesToUTF8CodePoint and decodeCodePointReverse (unchecked) match expectations" {
    const s = [_]u8{ 0xF0, 0x9F, 0x98, 0x80 }; // 😀
    const d = bytesToUTF8CodePoint(&s, 0);
    try std.testing.expectEqual(@as(CodePoint, 0x1F600), d.code_point);
    const r = decodeCodePointReverse(&s, 3);
    try std.testing.expectEqual(d.code_point, r.code_point);
}

test "hostile: single-byte lead 0x00-0xFF classification smoke" {
    var b: u8 = 0;
    while (true) : (b +%= 1) {
        const r = codePointLen(b);
        if (b <= max_ascii) {
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
    try std.testing.expectError(UTF8ValidationError.InvalidByteSequence, validateCodePointBytesReverse(&.{ 0xE0, 0xA0 }, 1));
    try std.testing.expectError(UTF8ValidationError.InvalidByteSequence, validateCodePointBytesReverse(&.{0x80}, 0));
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
    var tiny: [1]u21 = undefined;
    try std.testing.expectError(error.BufferTooSmall, utf8ViewToUTF8String(&view, &tiny));
}

// --- Hostile error matrix: wrong inputs → exact expected errors ----------------

test "hostile matrix: validateAndDecodeCodePointBytes length contract" {
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

test "hostile matrix: validateAndDecode forwards match bytesToUTF8CodePointChecked" {
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

test "hostile matrix: reverse-checked singles — codePointLenReverse vs validateCodePointBytesReverse" {
    // Truncated 3-byte lead: both reverse paths reject structural length mismatch
    try std.testing.expectError(
        error.InvalidByteSequence,
        codePointLenReverse(&.{ 0xE1, 0x80 }, 1),
    );
    try std.testing.expectError(
        error.InvalidByteSequence,
        validateCodePointBytesReverse(&.{ 0xE1, 0x80 }, 1),
    );

    try std.testing.expectError(
        error.InvalidByteSequence,
        codePointLenReverse(&.{0xE1}, 0),
    );
    try std.testing.expectError(
        error.InvalidByteSequence,
        validateCodePointBytesReverse(&.{0xE1}, 0),
    );
}

test "hostile matrix: reverse decode API matches forward errors on isolated sequences" {
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

test "hostile matrix: reverse last-byte heuristic — orphan lead + ASCII tail" {
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

test "hostile matrix: initUTF8View error position and resultant length on success" {
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

test "hostile matrix: string conversion APIs propagate validation" {
    var size: usize = 0;

    const view_delta = try initUTF8View("Δ", &size);
    try std.testing.expectError(error.BufferTooSmall, utf8ViewToUTF8String(&view_delta, &[_]u21{}));
    // Buffer exactly sized succeeds
    var buf_two: [2]u21 = undefined;
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

test "hostile matrix: bytesToUTF8String OutOfMemory propagates from alloc path" {
    var failing_allocator_state = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = 0,
    });
    const failing = failing_allocator_state.allocator();
    try std.testing.expectError(
        error.OutOfMemory,
        bytesToUTF8String(failing, "ab"),
    );
}

test "hostile matrix: compile-time initUTF8View rejects illegal bytes" {
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

test "hostile matrix: surrogate boundary around ED xx (forward + reverse APIs)" {
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

test "hostile matrix: F4 second-byte boundary CodePointTooLarge vs legal max" {
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

test "hostile matrix: four trailing continuation bytes before lead is illegal" {
    const tail = [_]u8{ 0x80, 0x80, 0x80, 0x80, 0xC2 };
    try std.testing.expectError(
        error.InvalidByteSequence,
        codePointLenReverse(&tail, tail.len - 1),
    );
    try std.testing.expectError(
        error.InvalidByteSequence,
        validateCodePointBytesReverse(&tail, tail.len - 1),
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
        const len = try utf8EncodeLen(code_point);
        var out_len: usize = 0;
        while (out_len < len) : (out_len += 1) {
            try std.testing.expectError(error.BufferTooSmall, encodeCodePoint(code_point, backing[0..out_len]));
        }
    }
}
