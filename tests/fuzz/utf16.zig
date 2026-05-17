const std = @import("std");
const ezi = @import("ezi_code");

const print = std.debug.print;

const utf16 = ezi.utf16;
const utf8 = ezi.utf8;

const INVALID_CODE_POINT = ezi.encoding.INVALID_CODE_POINT;

const ITERATIONS = 500_000;
const MAX_INPUT_UNITS = 128;

fn isValidScalar(cp: u21) bool {
    return cp <= 0x10FFFF and !(cp >= 0xD800 and cp <= 0xDFFF);
}

fn weightedUtf16Unit(random: std.Random) u16 {
    return switch (random.intRangeAtMost(u8, 0, 31)) {
        // hostile surrogate edges
        0 => 0xD800,
        1 => 0xDBFF,
        2 => 0xDC00,
        3 => 0xDFFF,

        // scalar boundaries
        4 => 0x0000,
        5 => 0x0001,
        6 => 0x007F,
        7 => 0x0080,
        8 => 0x07FF,
        9 => 0x0800,
        10 => 0xD7FF,
        11 => 0xE000,
        12 => 0xFFFD,
        13 => 0xFFFF,

        // repeated dangerous patterns
        14 => 0xD800 + random.intRangeAtMost(u16, 0, 0x3FF),
        15 => 0xDC00 + random.intRangeAtMost(u16, 0, 0x3FF),

        else => random.int(u16),
    };
}

fn generateHostileUtf16(
    random: std.Random,
    buf: []u16,
) void {
    var i: usize = 0;

    while (i < buf.len) {
        const mode = random.intRangeAtMost(u8, 0, 15);

        switch (mode) {
            // valid surrogate pair
            0 => {
                if (i + 1 >= buf.len) {
                    buf[i] = 0xD800;
                    i += 1;
                    continue;
                }

                buf[i] =
                    0xD800 +
                    random.intRangeAtMost(u16, 0, 0x3FF);

                buf[i + 1] =
                    0xDC00 +
                    random.intRangeAtMost(u16, 0, 0x3FF);

                i += 2;
            },

            // lone high surrogate
            1 => {
                buf[i] =
                    0xD800 +
                    random.intRangeAtMost(u16, 0, 0x3FF);

                i += 1;
            },

            // lone low surrogate
            2 => {
                buf[i] =
                    0xDC00 +
                    random.intRangeAtMost(u16, 0, 0x3FF);

                i += 1;
            },

            // high-high
            3 => {
                if (i + 1 >= buf.len) {
                    buf[i] = 0xD800;
                    i += 1;
                    continue;
                }

                buf[i] = 0xD800;
                buf[i + 1] = 0xDBFF;

                i += 2;
            },

            // low-low
            4 => {
                if (i + 1 >= buf.len) {
                    buf[i] = 0xDC00;
                    i += 1;
                    continue;
                }

                buf[i] = 0xDC00;
                buf[i + 1] = 0xDFFF;

                i += 2;
            },

            // reversed pair
            5 => {
                if (i + 1 >= buf.len) {
                    buf[i] = 0xDC00;
                    i += 1;
                    continue;
                }

                buf[i] = 0xDC00;
                buf[i + 1] = 0xD800;

                i += 2;
            },

            // repeated surrogate storm
            6 => {
                const repeat =
                    @min(
                        random.intRangeAtMost(
                            usize,
                            2,
                            16,
                        ),
                        buf.len - i,
                    );

                for (0..repeat) |j| {
                    buf[i + j] = 0xD800;
                }

                i += repeat;
            },

            // alternating malformed pairs
            7 => {
                const repeat =
                    @min(
                        random.intRangeAtMost(
                            usize,
                            2,
                            16,
                        ),
                        buf.len - i,
                    );

                for (0..repeat) |j| {
                    buf[i + j] =
                        if ((j & 1) == 0)
                            0xD800
                        else
                            0xDC00;
                }

                i += repeat;
            },

            // edge scalar transitions
            8 => {
                const edges = [_]u16{
                    0xD7FF,
                    0xE000,
                    0xFFFD,
                    0xFFFF,
                };

                buf[i] =
                    edges[
                        random.intRangeLessThan(
                            usize,
                            0,
                            edges.len,
                        )
                    ];

                i += 1;
            },

            // mostly-valid corpus
            9 => {
                const cp =
                    random.intRangeAtMost(
                        u21,
                        0,
                        0x10FFFF,
                    );

                if (isValidScalar(cp)) {
                    var tmp: [2]u16 = undefined;

                    const written =
                        utf16.encodeCodePoint(
                            cp,
                            &tmp,
                        ) catch {
                            buf[i] =
                                weightedUtf16Unit(random);

                            i += 1;
                            continue;
                        };

                    if (i + written > buf.len) {
                        buf[i] =
                            weightedUtf16Unit(random);

                        i += 1;
                        continue;
                    }

                    @memcpy(
                        buf[i .. i + written],
                        tmp[0..written],
                    );

                    i += written;
                } else {
                    buf[i] =
                        weightedUtf16Unit(random);

                    i += 1;
                }
            },

            else => {
                buf[i] =
                    weightedUtf16Unit(random);

                i += 1;
            },
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena;
    const allocator = init.arena.allocator();

    const clock: std.Io.Clock = .real;

    const timestamp: std.Io.Timestamp =
        .now(init.io, clock);

    var prng = std.Random.DefaultPrng.init(
        @intCast(timestamp.toMicroseconds()),
    );

    const random = prng.random();

    print(
        "starting iterations (utf16)...\n",
        .{},
    );

    var iter: usize = 0;

    while (iter < ITERATIONS) : (iter += 1) {
        _ = arena.reset(.retain_capacity);

        if ((iter % 10_000) == 0) {
            print(
                "utf16 iter={d}\n",
                .{iter},
            );
        }

        const len =
            random.intRangeAtMost(
                usize,
                0,
                MAX_INPUT_UNITS,
            );

        const buf =
            try allocator.alloc(u16, len);

        generateHostileUtf16(
            random,
            buf,
        );

        var i: usize = 0;
        var scalar_count: usize = 0;

        while (i < buf.len) {
            const lossy = try utf16.validateAndDecodeU16CodePointLossy(buf, i);

            std.debug.assert(if (lossy.len <= 2) true else lossy.code_point == INVALID_CODE_POINT);

            const strict = utf16.validateAndDecodeU16CodePoint(buf, i);

            if (strict) |decoded| {
                std.debug.assert(decoded.code_point == lossy.code_point);

                std.debug.assert(decoded.len == lossy.len);

                std.debug.assert(isValidScalar(decoded.code_point));

                var tmp: [2]u16 = undefined;

                const enc_len =
                    try utf16.encodeCodePoint(
                        decoded.code_point,
                        &tmp,
                    );

                std.debug.assert(
                    enc_len ==
                        decoded.len,
                );

                std.debug.assert(
                    std.mem.eql(
                        u16,
                        tmp[0..enc_len],
                        buf[i .. i + enc_len],
                    ),
                );
            } else |_| {
                std.debug.assert(
                    lossy.code_point ==
                        INVALID_CODE_POINT,
                );
            }

            scalar_count += 1;
            i += @max(lossy.len, 1);
        }

        // reverse hostile traversal

        var reverse_index =
            buf.len;

        var reverse_count: usize = 0;

        while (reverse_index > 0) {
            const decoded =
                try utf16.validateAndDecodeU16CodePointLossy(buf, reverse_index - 1);

            std.debug.assert(
                if (decoded.len <= 2)
                    true
                else
                    decoded.code_point == INVALID_CODE_POINT,
            );

            reverse_index -= @min(@max(decoded.len, 1), reverse_index);

            reverse_count += 1;
        }

        // UTF16 -> UTF8 hostile transcoding

        const utf8_len =
            utf16ToUtf8LenLossy(
                buf,
            );

        const utf8_buf =
            try allocator.alloc(
                u8,
                utf8_len,
            );

        const written =
            try utf16ToUtf8BufferLossy(
                buf,
                utf8_buf,
            );

        std.debug.assert(
            written == utf8_len,
        );

        i = 0;

        while (i < utf8_buf.len) {
            const decoded =
                try utf8.validateAndDecodeCodePointBytes(
                    utf8_buf,
                    i,
                );

            std.debug.assert(
                isValidScalar(
                    decoded.code_point,
                ),
            );

            i += @max(decoded.len, 1);
        }
    }

    print(
        "fuzz complete(utf16) with {d} iterations....\n",
        .{ITERATIONS},
    );
}

fn utf16ToUtf8LenLossy(
    units: []const u16,
) usize {
    var i: usize = 0;
    var out_len: usize = 0;

    while (i < units.len) {
        const decoded =
            utf16.validateAndDecodeU16CodePointLossy(
                units,
                i,
            ) catch unreachable;

        out_len +=
            utf8.utf8EncodeLen(
                decoded.code_point,
            ) catch unreachable;

        i += @max(decoded.len, 1);
    }

    return out_len;
}

fn utf16ToUtf8BufferLossy(
    units: []const u16,
    out: []u8,
) !usize {
    var i: usize = 0;
    var o: usize = 0;

    while (i < units.len) {
        const decoded =
            try utf16.validateAndDecodeU16CodePointLossy(
                units,
                i,
            );

        o +=
            try utf8.encodeCodePoint(
                decoded.code_point,
                out[o..],
            );

        i += @max(decoded.len, 1);
    }

    return o;
}
