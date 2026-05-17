const std = @import("std");
const ezi = @import("ezi_code");

const print = std.debug.print;

const utf32 = ezi.utf32;
const utf8 = ezi.utf8;

const INVALID_CODE_POINT = ezi.encoding.INVALID_CODE_POINT;

const ITERATIONS = 500_000;
const MAX_INPUT_UNITS = 128;

fn isValidScalar(cp: u21) bool {
    return cp <= 0x10FFFF and !(cp >= 0xD800 and cp <= 0xDFFF);
}

fn weightedUtf32Unit(
    random: std.Random,
) u32 {
    return switch (random.intRangeAtMost(u8, 0, 47)) {
        // legal scalar boundaries
        0 => 0x0000,
        1 => 0x0001,
        2 => 0x007F,
        3 => 0x0080,
        4 => 0x07FF,
        5 => 0x0800,
        6 => 0xD7FF,
        7 => 0xE000,
        8 => 0xFFFD,
        9 => 0xFFFF,
        10 => 0x10000,
        11 => 0x10FFFF,

        // surrogate boundaries
        12 => 0xD800,
        13 => 0xDBFF,
        14 => 0xDC00,
        15 => 0xDFFF,

        // invalid Unicode range edges
        16 => 0x110000,
        17 => 0x110001,
        18 => 0x1FFFFF,
        19 => 0x7FFFFFFF,
        20 => 0x80000000,
        21 => 0xFFFFFFFF,

        // dense surrogate region
        22 => 0xD800 +
            random.intRangeAtMost(
                u32,
                0,
                0x7FF,
            ),

        // near max scalar
        23 => 0x10FF00 +
            random.intRangeAtMost(
                u32,
                0,
                0xFF,
            ),

        // just-above valid range
        24 => 0x110000 +
            random.intRangeAtMost(
                u32,
                0,
                0x1000,
            ),

        // bit-pattern adversarial values
        25 => 0xAAAAAAAA,
        26 => 0x55555555,
        27 => 0x7FFFFFFF,
        28 => 0x80000000,
        29 => 0xFFFFFFFE,

        else => random.int(u32),
    };
}

fn generateHostileUtf32(
    random: std.Random,
    buf: []u32,
) void {
    var i: usize = 0;

    while (i < buf.len) {
        const mode =
            random.intRangeAtMost(
                u8,
                0,
                15,
            );

        switch (mode) {
            // valid scalar storm
            0 => {
                const repeat =
                    @min(
                        random.intRangeAtMost(
                            usize,
                            4,
                            32,
                        ),
                        buf.len - i,
                    );

                for (0..repeat) |j| {
                    while (true) {
                        const cp =
                            random.intRangeAtMost(
                                u21,
                                0,
                                0x10FFFF,
                            );

                        if (isValidScalar(cp)) {
                            buf[i + j] = cp;
                            break;
                        }
                    }
                }

                i += repeat;
            },

            // surrogate storm
            1 => {
                const repeat =
                    @min(
                        random.intRangeAtMost(
                            usize,
                            4,
                            32,
                        ),
                        buf.len - i,
                    );

                for (0..repeat) |j| {
                    buf[i + j] =
                        0xD800 +
                        random.intRangeAtMost(
                            u32,
                            0,
                            0x7FF,
                        );
                }

                i += repeat;
            },

            // invalid-above-max storm
            2 => {
                const repeat =
                    @min(
                        random.intRangeAtMost(
                            usize,
                            4,
                            32,
                        ),
                        buf.len - i,
                    );

                for (0..repeat) |j| {
                    buf[i + j] =
                        0x110000 +
                        random.intRangeAtMost(
                            u32,
                            0,
                            0x100000,
                        );
                }

                i += repeat;
            },

            // alternating valid/invalid
            3 => {
                const repeat =
                    @min(
                        random.intRangeAtMost(
                            usize,
                            4,
                            32,
                        ),
                        buf.len - i,
                    );

                for (0..repeat) |j| {
                    buf[i + j] =
                        if ((j & 1) == 0)
                            0x10FFFF
                        else
                            0xFFFFFFFF;
                }

                i += repeat;
            },

            // edge transition cluster
            4 => {
                const edges = [_]u32{
                    0xD7FF,
                    0xD800,
                    0xDFFF,
                    0xE000,
                    0x10FFFF,
                    0x110000,
                };

                const repeat =
                    @min(
                        random.intRangeAtMost(
                            usize,
                            4,
                            16,
                        ),
                        buf.len - i,
                    );

                for (0..repeat) |j| {
                    buf[i + j] =
                        edges[
                            random.intRangeLessThan(
                                usize,
                                0,
                                edges.len,
                            )
                        ];
                }

                i += repeat;
            },

            // bit corruption cluster
            5 => {
                const base =
                    weightedUtf32Unit(random);

                const repeat =
                    @min(
                        random.intRangeAtMost(
                            usize,
                            4,
                            16,
                        ),
                        buf.len - i,
                    );

                for (0..repeat) |j| {
                    const bit =
                        @as(
                            u5,
                            @intCast(
                                random.intRangeAtMost(
                                    u8,
                                    0,
                                    31,
                                ),
                            ),
                        );

                    buf[i + j] =
                        base ^ (@as(u32, 1) << bit);
                }

                i += repeat;
            },

            else => {
                buf[i] =
                    weightedUtf32Unit(random);

                i += 1;
            },
        }
    }
}

pub fn main(
    init: std.process.Init,
) !void {
    const arena = init.arena;
    const allocator =
        init.arena.allocator();

    const clock: std.Io.Clock = .real;

    const timestamp: std.Io.Timestamp =
        .now(init.io, clock);

    var prng =
        std.Random.DefaultPrng.init(
            @intCast(
                timestamp.toMicroseconds(),
            ),
        );

    const random = prng.random();

    print(
        "starting iterations (utf32)...\n",
        .{},
    );

    var iter: usize = 0;

    while (iter < ITERATIONS) : (iter += 1) {
        _ = arena.reset(
            .retain_capacity,
        );

        if ((iter % 10_000) == 0) {
            print(
                "utf32 iter={d}\n",
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
            try allocator.alloc(
                u32,
                len,
            );

        generateHostileUtf32(
            random,
            buf,
        );

        var i: usize = 0;
        var valid_count: usize = 0;
        var invalid_count: usize = 0;

        while (i < buf.len) {
            const lossy =
                try utf32.validateAndDecodeU32CodePointLossy(
                    buf,
                    i,
                );

            std.debug.assert(
                lossy.len == 1,
            );

            const strict =
                utf32.validateAndDecodeU32CodePoint(
                    buf,
                    i,
                );

            if (strict) |decoded| {
                valid_count += 1;

                std.debug.assert(
                    decoded.code_point ==
                        lossy.code_point,
                );

                std.debug.assert(
                    isValidScalar(
                        decoded.code_point,
                    ),
                );

                var tmp: [1]u32 =
                    undefined;

                const enc_len =
                    try utf32.encodeCodePoint(
                        decoded.code_point,
                        &tmp,
                    );

                std.debug.assert(
                    enc_len == 1,
                );

                std.debug.assert(
                    tmp[0] == buf[i],
                );
            } else |_| {
                invalid_count += 1;

                std.debug.assert(
                    lossy.code_point ==
                        INVALID_CODE_POINT,
                );
            }

            i += 1;
        }

        std.debug.assert(
            valid_count +
                invalid_count ==
                buf.len,
        );

        // UTF32 -> UTF8 hostile transcoding

        var utf8_out: std.ArrayList(u8) = .empty;

        i = 0;

        while (i < buf.len) {
            const decoded =
                try utf32.validateAndDecodeU32CodePointLossy(
                    buf,
                    i,
                );

            var tmp: [4]u8 =
                undefined;

            const enc_len =
                try utf8.encodeCodePoint(
                    decoded.code_point,
                    &tmp,
                );

            try utf8_out.appendSlice(
                allocator,
                tmp[0..enc_len],
            );

            i += 1;
        }

        i = 0;

        while (i < utf8_out.items.len) {
            const decoded =
                try utf8.validateAndDecodeCodePointBytes(
                    utf8_out.items,
                    i,
                );

            std.debug.assert(
                isValidScalar(
                    decoded.code_point,
                ),
            );

            i += decoded.len;
        }
    }

    print(
        "fuzz complete(utf32) with {d} iterations....\n",
        .{ITERATIONS},
    );
}
