const std = @import("std");

const ezi_code = @import("ezi_code");

const print = std.debug.print;

const utf8 = ezi_code.utf8;
const transcoding = ezi_code.transcoding;

const MAX_INPUT = 128;
const ITERATIONS = 500_000;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const clock: std.Io.Clock = .real;
    const timestamp: std.Io.Timestamp = .now(init.io, clock);

    var prng = std.Random.DefaultPrng.init(
        @intCast(timestamp.toMicroseconds()),
    );

    const random = prng.random();

    const backing = try allocator.alloc(u8, MAX_INPUT);
    defer allocator.free(backing);

    print("starting iterations (utf8)...\n", .{});

    for (0..ITERATIONS) |iter| {
        const len = generateMostlyValidUtf8(random, backing);

        structuredMutate(random, backing[0..len]);

        if (iter % 10000 == 0) {
            print("iter={}\n", .{iter});
        }

        try fuzzOne(allocator, backing[0..len]);
    }

    print("fuzz complete(utf8) with {d} iterations....\n", .{ITERATIONS});
}

fn fuzzOne(allocator: std.mem.Allocator, bytes: []u8) !void {

    // =========================================================
    // STRICT VALIDATION
    // =========================================================

    var scalar_count: usize = 0;

    const valid = blk: {
        _ = utf8.initUTF8View(bytes, &scalar_count) catch break :blk false;
        break :blk true;
    };

    // =========================================================
    // STRICT FORWARD DECODE
    // =========================================================

    {
        var i: usize = 0;

        while (i < bytes.len) {
            const decoded =
                utf8.validateAndDecodeCodePointBytes(
                    bytes,
                    i,
                ) catch {
                    i += 1;
                    continue;
                };

            if (decoded.len == 0)
                crash(bytes, "strict zero progress");

            if (decoded.len > 4)
                crash(bytes, "strict >4 len");

            if (decoded.code_point > 0x10FFFF)
                crash(bytes, "strict invalid scalar");

            if (decoded.len > bytes.len - i)
                crash(bytes, "strict overflow");

            i += decoded.len;
        }
    }

    // =========================================================
    // LOSSY ITERATOR
    // =========================================================

    {
        var iter = utf8.lossyIterator(bytes);

        var consumed: usize = 0;
        var count: usize = 0;

        while (iter.next()) |cp| {
            _ = cp;

            if (iter.index <= consumed)
                crash(bytes, "lossy no progress");

            consumed = iter.index;

            count += 1;

            if (count > bytes.len)
                crash(bytes, "lossy runaway");
        }

        if (iter.index != bytes.len)
            crash(bytes, "lossy incomplete");
    }

    // =========================================================
    // REVERSE VALIDATION
    // =========================================================

    {
        if (bytes.len > 0) {
            var i = bytes.len;

            while (i > 0) {
                i -= 1;

                _ =
                    utf8.validateAndDecodeCodePointBytesReverse(
                        bytes,
                        i,
                    ) catch {};
            }
        }
    }

    // =========================================================
    // UTF8 VIEW
    // =========================================================

    if (valid) {
        var counted: usize = 0;

        const view = try utf8.initUTF8View(bytes, &counted);

        if (view.countScalar() != counted)
            crash(bytes, "scalar mismatch");

        var iter = view.iter();

        var iterated: usize = 0;

        while (iter.next()) |cp| {
            _ = cp;
            iterated += 1;
            if (iter.index > bytes.len) crash(bytes, "iterator overflow");
        }

        if (iterated != counted)
            crash(bytes, "iterator count mismatch");

        while (iter.previous()) |_| {}

        if (iter.index != 0)
            crash(bytes, "reverse iterator mismatch");

        var seen = try allocator.alloc(bool, bytes.len + 1);
        defer allocator.free(seen);

        @memset(seen, false);
        var boundary_iter = view.iter();

        seen[0] = true;
        while (boundary_iter.next()) |_| {
            if (boundary_iter.index > bytes.len) crash(bytes, "iterator overflow");
            seen[boundary_iter.index] = true;
        }

        for (0..bytes.len + 1) |idx| {
            const expected = seen[idx];
            const actual = view.isBoundary(idx);
            if (expected != actual) {
                crash(bytes, "boundary mismatch");
            }
        }
    }

    // =========================================================
    // UTF8 -> UTF16 -> UTF8
    // =========================================================

    {
        const out = try transcoding.utf8ToUtf16Lossy(allocator, bytes);
        defer allocator.free(out);

        const round = try transcoding.utf16ToUtf8Lossy(allocator, out);
        defer allocator.free(round);

        if (valid) {
            var tmp: usize = 0;

            _ = utf8.initUTF8View(round, &tmp) catch {
                crash(
                    bytes,
                    "roundtrip corruption",
                );
            };
        }
    }

    // =========================================================
    // COUNTING APIs
    // =========================================================

    {
        const lossy_count =
            utf8.countScalarsLossy(bytes);

        var iter =
            utf8.lossyIterator(bytes);

        var manual: usize = 0;

        while (iter.next()) |_| {
            manual += 1;
        }

        if (lossy_count != manual)
            crash(bytes, "lossy count mismatch");
    }

    // =========================================================
    // BUFFER API
    // =========================================================

    {
        const count =
            utf8.countScalarsLossy(bytes);

        const buf =
            try allocator.alloc(
                ezi_code.encoding.CodePoint,
                count,
            );

        defer allocator.free(buf);

        const written =
            try utf8.bytesToCodePointsLossyBuffer(
                bytes,
                buf,
            );

        if (written != count)
            crash(bytes, "buffer mismatch");
    }
}

fn generateMostlyValidUtf8(random: std.Random, bytes: []u8) usize {
    var i: usize = 0;

    while (i < bytes.len) {
        switch (random.uintLessThan(u8, 10)) {
            0 => {
                bytes[i] =
                    random.uintLessThan(u8, 0x80);
                i += 1;
            },

            1 => {
                if (i + 2 > bytes.len) break;

                const cp: u21 = 0x80 + random.uintLessThan(u21, 0x7FF - 0x80);

                var enc: [4]u8 = undefined;

                _ = utf8.encodeCodePoint(cp, &enc) catch unreachable;

                @memcpy(bytes[i..][0..2], enc[0..2]);

                i += 2;
            },

            2 => {
                if (i + 3 > bytes.len) break;

                const cp: u21 =
                    0x800 +
                    random.uintLessThan(u21, 0xFFFF - 0x800);

                if (cp >= 0xD800 and cp <= 0xDFFF)
                    continue;

                var enc: [4]u8 = undefined;

                _ = utf8.encodeCodePoint(cp, &enc) catch unreachable;

                @memcpy(bytes[i..][0..3], enc[0..3]);

                i += 3;
            },

            else => {
                if (i + 4 > bytes.len) break;

                const cp: u21 = 0x10000 + random.uintLessThan(u21, 0x10FFFF - 0x10000);

                var enc: [4]u8 = undefined;

                _ = utf8.encodeCodePoint(cp, &enc) catch unreachable;

                @memcpy(bytes[i..][0..4], enc[0..4]);

                i += 4;
            },
        }
    }

    return i;
}

fn biasedLength(
    random: std.Random,
) usize {
    return switch (random.uintLessThan(u8, 8)) {
        0 => random.uintLessThan(usize, 8),
        1 => random.uintLessThan(usize, 16),
        2 => random.uintLessThan(usize, 32),
        3 => random.uintLessThan(usize, 64),
        4 => random.uintLessThan(usize, 256),
        5 => random.uintLessThan(usize, 1024),
        6 => random.uintLessThan(usize, 4096),
        else => random.uintLessThan(
            usize,
            MAX_INPUT,
        ),
    };
}

fn structuredMutate(random: std.Random, bytes: []u8) void {
    if (bytes.len == 0)
        return;

    const mutation_count = 1 + random.uintLessThan(u8, 4);

    for (0..mutation_count) |_| {
        switch (random.uintLessThan(u8, 19)) {
            0 => injectOverlong2(random, bytes),
            1 => injectOverlong3(random, bytes),
            2 => injectOverlong4(random, bytes),
            3 => injectSurrogate(random, bytes),
            4 => injectTooLarge(random, bytes),
            5 => truncateTail(random, bytes),
            6 => randomFlip(random, bytes),
            7 => randomLead(random, bytes),
            8 => randomContinuation(random, bytes),
            9 => deleteRandomByte(random, bytes),
            10 => insertContinuationInsideScalar(random, bytes),
            11 => injectEdgeSequence(random, bytes),
            12 => splice(bytes),
            13 => incomplete2(random, bytes),
            14 => incomplete3(random, bytes),
            15 => incomplete4(random, bytes),
            16 => illegalLead(random, bytes),
            17 => mixedValidInvalid(bytes),
            18 => maxScalar(random, bytes),
            else => unreachable,
        }
    }

    if (random.uintLessThan(u8, 100) < 5) {
        switch (random.uintLessThan(u8, 4)) {
            0 => injectContinuationStorm(bytes),
            1 => asciiFlood(bytes),
            2 => nullFlood(bytes),
            3 => replacementFlood(bytes),
            else => unreachable,
        }
    }
}

fn injectEdgeSequence(
    r: std.Random,
    b: []u8,
) void {
    const corpus = [_][]const u8{
        &.{ 0xC0, 0x80 },
        &.{ 0xE0, 0x80, 0x80 },
        &.{ 0xED, 0xA0, 0x80 },
        &.{ 0xF4, 0x90, 0x80, 0x80 },
        &.{ 0xF4, 0x8F, 0xBF, 0xBF },
        &.{ 0xE2, 0x82, 0xAC },
        &.{ 0xF0, 0x9F, 0x98, 0x80 },
    };

    const seq =
        corpus[
            r.uintLessThan(
                usize,
                corpus.len,
            )
        ];

    write(
        b,
        r.uintLessThan(usize, b.len),
        seq,
    );
}

fn write(bytes: []u8, idx: usize, seq: []const u8) void {
    if (idx + seq.len > bytes.len)
        return;

    @memcpy(bytes[idx .. idx + seq.len], seq);
}

fn injectOverlong2(
    r: std.Random,
    b: []u8,
) void {
    write(
        b,
        r.uintLessThan(usize, b.len),
        &.{ 0xC0, 0x80 },
    );
}

fn injectOverlong3(
    r: std.Random,
    b: []u8,
) void {
    write(
        b,
        r.uintLessThan(usize, b.len),
        &.{ 0xE0, 0x80, 0x80 },
    );
}

fn injectOverlong4(
    r: std.Random,
    b: []u8,
) void {
    write(
        b,
        r.uintLessThan(usize, b.len),
        &.{ 0xF0, 0x80, 0x80, 0x80 },
    );
}

fn injectSurrogate(
    r: std.Random,
    b: []u8,
) void {
    write(
        b,
        r.uintLessThan(usize, b.len),
        &.{ 0xED, 0xA0, 0x80 },
    );
}

fn injectTooLarge(
    r: std.Random,
    b: []u8,
) void {
    write(
        b,
        r.uintLessThan(usize, b.len),
        &.{ 0xF4, 0x90, 0x80, 0x80 },
    );
}

fn incomplete2(
    r: std.Random,
    b: []u8,
) void {
    const idx =
        r.uintLessThan(usize, b.len);

    b[idx] = 0xC2;

    if (idx + 1 < b.len)
        b[idx + 1] = 0x41;
}

fn incomplete3(
    r: std.Random,
    b: []u8,
) void {
    const idx =
        r.uintLessThan(usize, b.len);

    b[idx] = 0xE2;

    if (idx + 1 < b.len)
        b[idx + 1] = 0x41;

    if (idx + 2 < b.len)
        b[idx + 2] = 0x41;
}

fn incomplete4(
    r: std.Random,
    b: []u8,
) void {
    const idx =
        r.uintLessThan(usize, b.len);

    b[idx] = 0xF0;

    if (idx + 1 < b.len)
        b[idx + 1] = 0x41;

    if (idx + 2 < b.len)
        b[idx + 2] = 0x41;

    if (idx + 3 < b.len)
        b[idx + 3] = 0x41;
}

fn illegalLead(
    r: std.Random,
    b: []u8,
) void {
    b[
        r.uintLessThan(usize, b.len)
    ] = 0xFF;
}

fn randomFlip(
    r: std.Random,
    b: []u8,
) void {
    const idx =
        r.uintLessThan(usize, b.len);

    const shift: u3 =
        @intCast(
            r.uintLessThan(u8, 8),
        );

    b[idx] ^= (@as(u8, 1) << shift);
}

fn randomLead(
    r: std.Random,
    b: []u8,
) void {
    b[
        r.uintLessThan(usize, b.len)
    ] =
        0xC0 +
        r.uintLessThan(u8, 0x40);
}

fn randomContinuation(
    r: std.Random,
    b: []u8,
) void {
    b[r.uintLessThan(usize, b.len)] = 0x80 + r.uintLessThan(u8, 0x40);
}

fn asciiFlood(b: []u8) void {
    @memset(b, 'A');
}

fn nullFlood(b: []u8) void {
    @memset(b, 0);
}

fn replacementFlood(b: []u8) void {
    var i: usize = 0;

    while (i + 3 <= b.len) : (i += 3) {
        b[i] = 0xEF;
        b[i + 1] = 0xBF;
        b[i + 2] = 0xBD;
    }
}

fn injectContinuationStorm(
    b: []u8,
) void {
    @memset(b, 0x80);
}

fn truncateTail(r: std.Random, b: []u8) void {
    if (b.len < 2) return;
    const idx = r.uintLessThan(usize, b.len - 1);
    const chop = 1 + r.uintLessThan(u8, 3);
    const end = @min(idx + chop, b.len);

    for (idx..end) |i| {
        b[i] = 0xFF;
    }
}

fn splice(b: []u8) void {
    if (b.len < 2)
        return;

    const mid = b.len / 2;
    std.mem.reverse(u8, b[0..mid]);
    std.mem.reverse(u8, b[mid..]);
}

fn deleteRandomByte(r: std.Random, b: []u8) void {
    if (b.len < 2) return;
    const idx = r.uintLessThan(usize, b.len - 1);
    std.mem.copyForwards(u8, b[idx .. b.len - 1], b[idx + 1 .. b.len]);

    b[b.len - 1] = 0x00;
}

fn insertContinuationInsideScalar(r: std.Random, b: []u8) void {
    if (b.len < 2) return;
    const idx = r.uintLessThan(usize, b.len);
    b[idx] = 0x80 + r.uintLessThan(u8, 0x40);
}

fn mixedValidInvalid(b: []u8) void {
    const seq = [_]u8{ 0x61, 0xF0, 0x9F, 0x98, 0x80, 0xFF, 0x80, 0xC0 };
    var i: usize = 0;
    while (i + seq.len <= b.len) : (i += seq.len) {
        @memcpy(b[i .. i + seq.len], &seq);
    }
}

fn maxScalar(r: std.Random, b: []u8) void {
    write(b, r.uintLessThan(usize, b.len), &.{ 0xF4, 0x8F, 0xBF, 0xBF });
}

fn crash(
    bytes: []const u8,
    comptime msg: []const u8,
) noreturn {
    print(
        "\nFUZZ FAILURE: {s}\n",
        .{msg},
    );

    print(
        "len={d}\n",
        .{bytes.len},
    );

    for (bytes, 0..) |b, i| {
        print(
            "{X:0>2} ",
            .{b},
        );

        if ((i + 1) % 32 == 0)
            print(
                "\n",
                .{},
            );
    }

    print(
        "\n",
        .{},
    );

    @panic(msg);
}
