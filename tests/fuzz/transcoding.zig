const std = @import("std");
const ezi = @import("ezi_code");
const transcoding = ezi.transcoding;

const print = std.debug.print;

const utf8 = ezi.utf8;
const utf16 = ezi.utf16;
const utf32 = ezi.utf32;

const INVALID_CODE_POINT =
    ezi.encoding.INVALID_CODE_POINT;

const ITERATIONS = 250_000;
const MAX_SCALARS = 128;

fn isValidScalar(cp: u21) bool {
    return cp <= 0x10FFFF and
        !(cp >= 0xD800 and cp <= 0xDFFF);
}

fn randomScalar(
    random: std.Random,
) u21 {
    while (true) {
        const cp =
            random.intRangeAtMost(
                u21,
                0,
                0x10FFFF,
            );

        if (isValidScalar(cp)) {
            return cp;
        }
    }
}

fn mutateUtf8(
    random: std.Random,
    bytes: []u8,
) void {
    if (bytes.len == 0) return;

    const mutations =
        random.intRangeAtMost(
            usize,
            1,
            @min(bytes.len, 64),
        );

    for (0..mutations) |_| {
        const idx =
            random.intRangeLessThan(
                usize,
                0,
                bytes.len,
            );

        switch (random.intRangeAtMost(u8, 0, 11)) {
            // invalid leading bytes
            0 => bytes[idx] = 0xC0,
            1 => bytes[idx] = 0xC1,
            2 => bytes[idx] = 0xF5,
            3 => bytes[idx] = 0xFF,

            // continuation spam
            4 => bytes[idx] = 0x80,
            5 => bytes[idx] = 0xBF,

            // truncate multi-byte lead
            6 => {
                bytes[idx] = 0xE2;

                if (idx + 1 < bytes.len) {
                    bytes[idx + 1] = 0x82;
                }
            },

            // overlong-ish patterns
            7 => {
                bytes[idx] = 0xF0;

                if (idx + 1 < bytes.len)
                    bytes[idx + 1] = 0x80;

                if (idx + 2 < bytes.len)
                    bytes[idx + 2] = 0x80;

                if (idx + 3 < bytes.len)
                    bytes[idx + 3] = 0xAF;
            },

            // random corruption
            else => {
                bytes[idx] =
                    random.int(u8);
            },
        }
    }
}

fn mutateUtf16(
    random: std.Random,
    units: []u16,
) void {
    if (units.len == 0) return;

    const mutations =
        random.intRangeAtMost(
            usize,
            1,
            @min(units.len, 64),
        );

    for (0..mutations) |_| {
        const idx =
            random.intRangeLessThan(
                usize,
                0,
                units.len,
            );

        switch (random.intRangeAtMost(u8, 0, 9)) {
            0 => units[idx] = 0xD800,
            1 => units[idx] = 0xDBFF,
            2 => units[idx] = 0xDC00,
            3 => units[idx] = 0xDFFF,

            // reverse surrogate pair
            4 => {
                if (idx + 1 < units.len) {
                    units[idx] = 0xDC00;
                    units[idx + 1] = 0xD800;
                }
            },

            // repeated high surrogates
            5 => {
                if (idx + 1 < units.len) {
                    units[idx] = 0xD800;
                    units[idx + 1] = 0xDBFF;
                }
            },

            // repeated low surrogates
            6 => {
                if (idx + 1 < units.len) {
                    units[idx] = 0xDC00;
                    units[idx + 1] = 0xDFFF;
                }
            },

            else => {
                units[idx] =
                    random.int(u16);
            },
        }
    }
}

fn mutateUtf32(
    random: std.Random,
    units: []u32,
) void {
    if (units.len == 0) return;

    const mutations =
        random.intRangeAtMost(
            usize,
            1,
            @min(units.len, 64),
        );

    for (0..mutations) |_| {
        const idx =
            random.intRangeLessThan(
                usize,
                0,
                units.len,
            );

        switch (random.intRangeAtMost(u8, 0, 11)) {
            0 => units[idx] = 0x110000,
            1 => units[idx] = 0xFFFFFFFF,
            2 => units[idx] = 0xD800,
            3 => units[idx] = 0xDFFF,
            4 => units[idx] = 0x80000000,
            5 => units[idx] = 0x7FFFFFFF,
            6 => units[idx] = 0x10FFFF,
            7 => units[idx] = 0x10FFFF + 1,

            else => {
                units[idx] =
                    random.int(u32);
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
        "starting iterations (transcoding)...\n",
        .{},
    );

    var iter: usize = 0;

    while (iter < ITERATIONS) : (iter += 1) {
        _ = arena.reset(
            .retain_capacity,
        );

        if ((iter % 10_000) == 0) {
            print(
                "transcoding iter={d}\n",
                .{iter},
            );
        }

        const scalar_len =
            random.intRangeAtMost(
                usize,
                0,
                MAX_SCALARS,
            );

        var utf8_bytes: std.ArrayList(u8) = .empty;

        var utf16_units: std.ArrayList(u16) = .empty;

        var utf32_units: std.ArrayList(u32) = .empty;

        // canonical corpus generation

        for (0..scalar_len) |_| {
            const cp =
                randomScalar(random);

            {
                var tmp: [4]u8 =
                    undefined;

                const len =
                    try utf8.encodeCodePoint(
                        cp,
                        &tmp,
                    );

                try utf8_bytes.appendSlice(
                    allocator,
                    tmp[0..len],
                );
            }

            {
                var tmp: [2]u16 =
                    undefined;

                const len =
                    try utf16.encodeCodePoint(
                        cp,
                        &tmp,
                    );

                try utf16_units.appendSlice(
                    allocator,
                    tmp[0..len],
                );
            }

            {
                var tmp: [1]u32 =
                    undefined;

                const len =
                    try utf32.encodeCodePoint(
                        cp,
                        &tmp,
                    );

                try utf32_units.appendSlice(
                    allocator,
                    tmp[0..len],
                );
            }
        }

        // canonical UTF8 <-> UTF16

        {
            const converted =
                try transcoding.utf8ToUtf16(
                    allocator,
                    utf8_bytes.items,
                );

            std.debug.assert(
                std.mem.eql(
                    u16,
                    converted,
                    utf16_units.items,
                ),
            );

            const roundtrip =
                try transcoding.utf16ToUtf8(
                    allocator,
                    converted,
                );

            std.debug.assert(
                std.mem.eql(
                    u8,
                    roundtrip,
                    utf8_bytes.items,
                ),
            );
        }

        // canonical UTF8 <-> UTF32

        {
            const converted =
                try transcoding.utf8ToUtf32(
                    allocator,
                    utf8_bytes.items,
                );

            std.debug.assert(
                std.mem.eql(
                    u32,
                    converted,
                    utf32_units.items,
                ),
            );

            const roundtrip =
                try transcoding.utf32ToUtf8(
                    allocator,
                    converted,
                );

            std.debug.assert(
                std.mem.eql(
                    u8,
                    roundtrip,
                    utf8_bytes.items,
                ),
            );
        }

        // canonical UTF16 <-> UTF32

        {
            const converted =
                try transcoding.utf16ToUtf32(
                    allocator,
                    utf16_units.items,
                );

            std.debug.assert(
                std.mem.eql(
                    u32,
                    converted,
                    utf32_units.items,
                ),
            );

            const roundtrip =
                try transcoding.utf32ToUtf16(
                    allocator,
                    converted,
                );

            std.debug.assert(
                std.mem.eql(
                    u16,
                    roundtrip,
                    utf16_units.items,
                ),
            );
        }

        // hostile UTF8 mutations

        {
            const corrupted =
                try allocator.dupe(
                    u8,
                    utf8_bytes.items,
                );

            mutateUtf8(
                random,
                corrupted,
            );

            const result16 =
                transcoding.utf8ToUtf16(
                    allocator,
                    corrupted,
                );

            if (result16) |converted| {
                const roundtrip =
                    try transcoding.utf16ToUtf8(
                        allocator,
                        converted,
                    );

                var i: usize = 0;

                while (i < roundtrip.len) {
                    const decoded =
                        try utf8.validateAndDecodeCodePointBytes(
                            roundtrip,
                            i,
                        );

                    std.debug.assert(
                        isValidScalar(
                            decoded.code_point,
                        ),
                    );

                    i += decoded.len;
                }
            } else |_| {}

            const result32 =
                transcoding.utf8ToUtf32(
                    allocator,
                    corrupted,
                );

            if (result32) |converted| {
                for (converted) |cp| {
                    std.debug.assert(
                        isValidScalar(
                            @intCast(cp),
                        ),
                    );
                }
            } else |_| {}
        }

        // hostile UTF16 mutations

        {
            const corrupted =
                try allocator.dupe(
                    u16,
                    utf16_units.items,
                );

            mutateUtf16(
                random,
                corrupted,
            );

            const result8 =
                transcoding.utf16ToUtf8(
                    allocator,
                    corrupted,
                );

            if (result8) |converted| {
                var i: usize = 0;

                while (i < converted.len) {
                    const decoded =
                        try utf8.validateAndDecodeCodePointBytes(
                            converted,
                            i,
                        );

                    std.debug.assert(
                        isValidScalar(
                            decoded.code_point,
                        ),
                    );

                    i += decoded.len;
                }
            } else |_| {}

            const result32 =
                transcoding.utf16ToUtf32(
                    allocator,
                    corrupted,
                );

            if (result32) |converted| {
                for (converted) |cp| {
                    std.debug.assert(
                        isValidScalar(
                            @intCast(cp),
                        ),
                    );
                }
            } else |_| {}
        }

        // hostile UTF32 mutations

        {
            const corrupted =
                try allocator.dupe(
                    u32,
                    utf32_units.items,
                );

            mutateUtf32(
                random,
                corrupted,
            );

            const result8 =
                transcoding.utf32ToUtf8(
                    allocator,
                    corrupted,
                );

            if (result8) |converted| {
                var i: usize = 0;

                while (i < converted.len) {
                    const decoded =
                        try utf8.validateAndDecodeCodePointBytes(
                            converted,
                            i,
                        );

                    std.debug.assert(
                        isValidScalar(
                            decoded.code_point,
                        ),
                    );

                    i += decoded.len;
                }
            } else |_| {}

            const result16 =
                transcoding.utf32ToUtf16(
                    allocator,
                    corrupted,
                );

            if (result16) |converted| {
                var i: usize = 0;

                while (i < converted.len) {
                    const decoded =
                        try utf16.validateAndDecodeU16CodePointLossy(
                            converted,
                            i,
                        );

                    std.debug.assert(
                        isValidScalar(
                            decoded.code_point,
                        ) or
                            decoded.code_point ==
                                INVALID_CODE_POINT,
                    );

                    i += decoded.len;
                }
            } else |_| {}
        }
    }

    print(
        "fuzz complete(transcoding) with {d} iterations....\n",
        .{ITERATIONS},
    );
}
