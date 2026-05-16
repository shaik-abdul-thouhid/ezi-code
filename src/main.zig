const std = @import("std");

const decoder_state = enum { accept, reject };

pub const UTF8_ACCEPT: u32 = 0;
pub const UTF8_REJECT: u32 = 12;

const utf8_decoder = [_]u8{
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

pub const DecodeResult = enum {
    accept,
    reject,
    incomplete,
};

/// Feed ONE byte into DFA.
///
/// state:
///     mutable DFA state
///
/// codepoint:
///     mutable codepoint accumulator
///
/// returns:
///     accept     -> full valid scalar completed
///     reject     -> invalid UTF-8
///     incomplete -> waiting for continuation bytes
pub inline fn decode(state: *u32, codepoint: *u32, byte: u8) DecodeResult {
    const t = utf8_decoder[byte];

    codepoint.* = if (state.* != UTF8_ACCEPT)
        (byte & 0b0011_1111) | (codepoint.* << 6)
    else
        (@as(u32, 0xFF) >> @intCast(t)) & byte;

    state.* = utf8_decoder[256 + state.* * 16 + t];

    return switch (state.*) {
        UTF8_ACCEPT => .accept,
        UTF8_REJECT => .reject,
        else => .incomplete,
    };
}

/// Validate full UTF-8 buffer.
pub fn validate(bytes: []const u8) bool {
    var state: u32 = UTF8_ACCEPT;
    var codepoint: u32 = 0;

    for (bytes) |b| {
        if (decode(&state, &codepoint, b) == .reject)
            return false;
    }

    return state == UTF8_ACCEPT;
}

/// Count Unicode scalars.
pub fn countScalars(bytes: []const u8) !usize {
    var state: u32 = UTF8_ACCEPT;
    var codepoint: u32 = 0;
    var count: usize = 0;

    for (bytes) |b| {
        switch (decode(&state, &codepoint, b)) {
            .accept => count += 1,
            .reject => return error.InvalidUTF8,
            .incomplete => {},
        }
    }

    if (state != UTF8_ACCEPT)
        return error.TruncatedUTF8;

    return count;
}

/// Decode full string and print scalars.
/// purely demo/debug.
pub fn dumpCodepoints(bytes: []const u8) !void {
    var state: u32 = UTF8_ACCEPT;
    var codepoint: u32 = 0;

    for (bytes) |b| {
        switch (decode(&state, &codepoint, b)) {
            .accept => {
                std.debug.print(
                    "U+{X:0>4}\n",
                    .{codepoint},
                );
            },
            .reject => return error.InvalidUTF8,
            .incomplete => {},
        }
    }

    if (state != UTF8_ACCEPT)
        return error.TruncatedUTF8;
}

pub fn main() !void {
    try dumpCodepoints("こんにちは");
}
