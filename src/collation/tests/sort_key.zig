const std = @import("std");
const collation = @import("../root.zig");
const encoding = @import("encoding");

const testing = std.testing;
const Allocator = std.mem.Allocator;
const CodePoint = encoding.CodePoint;
const Collator = collation.Collator;
const Options = collation.Options;
const Strength = collation.Strength;
const VariableWeighting = collation.VariableWeighting;
const Order = collation.Order;

fn buildKeyUtf8(allocator: Allocator, collator: Collator, utf8: []const u8, key: *collation.Key) !void {
    const cps = try encoding.utf8.bytesToUTF8String(allocator, utf8);
    defer allocator.free(cps);
    try collator.buildKey(allocator, cps, key);
}

fn serializedFor(allocator: Allocator, collator: Collator, utf8: []const u8) ![]u8 {
    const cps = try encoding.utf8.bytesToUTF8String(allocator, utf8);
    defer allocator.free(cps);
    var key: collation.Key = .{};
    defer key.deinit(allocator);
    try collator.buildKey(allocator, cps, &key);
    return key.serializeAlloc(allocator, collator.options);
}

// ============================================================================
// serializedLen / serializeInto / serializeAlloc round-trips
// ============================================================================

test "sort key: serializedLen matches serializeInto for all strength levels" {
    const allocator = testing.allocator;

    const strings = [_][]const u8{ "", "a", "hello", "café", "안녕하세요", "𠀀𠀁𠀂", "A b C 1 2 3!" };
    const options_list = [_]Options{
        .{ .strength = .primary },
        .{ .strength = .secondary },
        .{ .strength = .tertiary },
        .{ .strength = .quaternary },
        .{ .strength = .identical },
        .{ .variable_weighting = .shifted, .strength = .quaternary },
        .{ .variable_weighting = .shifted, .strength = .identical },
    };

    for (strings) |str| {
        const cps = try encoding.utf8.bytesToUTF8String(allocator, str);
        defer allocator.free(cps);

        for (options_list) |opts| {
            var collator = Collator.init(opts);
            var key: collation.Key = .{};
            defer key.deinit(allocator);
            try collator.buildKey(allocator, cps, &key);

            const expected_len = key.serializedLen(opts);
            const buf = try allocator.alloc(u8, expected_len);
            defer allocator.free(buf);
            const slice = key.serializeInto(opts, buf);

            try testing.expectEqual(expected_len, slice.len);
        }
    }
}

test "sort key: serializeInto and serializeAlloc produce identical bytes" {
    const allocator = testing.allocator;
    const collator = Collator.init(.{});
    const strings = [_][]const u8{ "", "hello", "café", "UNICODE", "中文テスト" };

    for (strings) |str| {
        const cps = try encoding.utf8.bytesToUTF8String(allocator, str);
        defer allocator.free(cps);

        var key: collation.Key = .{};
        defer key.deinit(allocator);
        try collator.buildKey(allocator, cps, &key);

        const len = key.serializedLen(collator.options);
        const buf = try allocator.alloc(u8, len);
        defer allocator.free(buf);
        const from_into = key.serializeInto(collator.options, buf);

        const from_alloc = try key.serializeAlloc(allocator, collator.options);
        defer allocator.free(from_alloc);

        try testing.expectEqualSlices(u8, from_alloc, from_into);
    }
}

test "sort key: clearRetainingCapacity then rebuild produces same bytes" {
    const allocator = testing.allocator;
    const collator = Collator.init(.{});

    const cps = try encoding.utf8.bytesToUTF8String(allocator, "hello world");
    defer allocator.free(cps);

    var key: collation.Key = .{};
    defer key.deinit(allocator);

    try collator.buildKey(allocator, cps, &key);
    const first = try key.serializeAlloc(allocator, collator.options);
    defer allocator.free(first);

    key.clearRetainingCapacity();
    try collator.buildKey(allocator, cps, &key);
    const second = try key.serializeAlloc(allocator, collator.options);
    defer allocator.free(second);

    try testing.expectEqualSlices(u8, first, second);
}

// ============================================================================
// compareSerializedKeys agrees with compareKeys
// ============================================================================

test "sort key: compareSerializedKeys agrees with compareKeys for default options" {
    const allocator = testing.allocator;
    const collator = Collator.init(.{});

    const pairs = [_][2][]const u8{
        .{ "", "" },
        .{ "a", "a" },
        .{ "a", "b" },
        .{ "b", "a" },
        .{ "cafe", "café" },
        .{ "café", "cafe" },
        .{ "A", "a" },
        .{ "a", "A" },
        .{ "", "a" },
        .{ "a", "" },
        .{ "hello world", "hello" },
        .{ "hello", "hello world" },
        .{ "Ångström", "angstrom" },
        .{ "中文", "abc" },
        .{ "abc", "中文" },
        .{ "résumé", "resume" },
        .{ "HELLO", "hello" },
    };

    for (pairs) |pair| {
        var a_key: collation.Key = .{};
        defer a_key.deinit(allocator);
        var b_key: collation.Key = .{};
        defer b_key.deinit(allocator);

        try buildKeyUtf8(allocator, collator, pair[0], &a_key);
        try buildKeyUtf8(allocator, collator, pair[1], &b_key);

        const expected = collator.compareKeys(&a_key, &b_key);

        const a_bytes = try a_key.serializeAlloc(allocator, collator.options);
        defer allocator.free(a_bytes);
        const b_bytes = try b_key.serializeAlloc(allocator, collator.options);
        defer allocator.free(b_bytes);

        try testing.expectEqual(expected, collation.compareSerializedKeys(a_bytes, b_bytes));
    }
}

test "sort key: compareSerializedKeys agrees with compareKeys across all strength levels" {
    const allocator = testing.allocator;

    const strings = [_][]const u8{ "a", "A", "café", "cafe", "CAFE", "b", "B", "", "hello", "résumé" };

    const options_list = [_]Options{
        .{ .strength = .primary },
        .{ .strength = .secondary },
        .{ .strength = .tertiary },
        .{ .strength = .identical },
        .{ .variable_weighting = .shifted, .strength = .quaternary },
        .{ .variable_weighting = .shifted, .strength = .identical },
    };

    for (options_list) |opts| {
        const collator = Collator.init(opts);
        for (strings) |s| {
            for (strings) |t| {
                var s_key: collation.Key = .{};
                defer s_key.deinit(allocator);
                var t_key: collation.Key = .{};
                defer t_key.deinit(allocator);

                try buildKeyUtf8(allocator, collator, s, &s_key);
                try buildKeyUtf8(allocator, collator, t, &t_key);

                const expected = collator.compareKeys(&s_key, &t_key);

                const s_bytes = try s_key.serializeAlloc(allocator, opts);
                defer allocator.free(s_bytes);
                const t_bytes = try t_key.serializeAlloc(allocator, opts);
                defer allocator.free(t_bytes);

                try testing.expectEqual(expected, collation.compareSerializedKeys(s_bytes, t_bytes));
            }
        }
    }
}

// ============================================================================
// Strength gates: which levels appear in the serialized bytes
// ============================================================================

test "sort key: primary strength strips secondary and tertiary differences" {
    const allocator = testing.allocator;
    const collator_primary = Collator.init(.{ .strength = .primary });
    const collator_tertiary = Collator.init(.{ .strength = .tertiary });

    // "A" and "a" have the same primary weight but differ at tertiary (case).
    {
        const a = try serializedFor(allocator, collator_primary, "A");
        defer allocator.free(a);
        const b = try serializedFor(allocator, collator_primary, "a");
        defer allocator.free(b);
        try testing.expectEqual(Order.eq, collation.compareSerializedKeys(a, b));
    }
    // With tertiary strength they must differ.
    {
        const a = try serializedFor(allocator, collator_tertiary, "A");
        defer allocator.free(a);
        const b = try serializedFor(allocator, collator_tertiary, "a");
        defer allocator.free(b);
        try testing.expect(collation.compareSerializedKeys(a, b) != .eq);
    }
}

test "sort key: secondary strength strips tertiary differences" {
    const allocator = testing.allocator;
    const collator_secondary = Collator.init(.{ .strength = .secondary });

    // "cafe" and "CAFE" differ only at tertiary (case) — equal at secondary.
    {
        const a = try serializedFor(allocator, collator_secondary, "cafe");
        defer allocator.free(a);
        const b = try serializedFor(allocator, collator_secondary, "CAFE");
        defer allocator.free(b);
        try testing.expectEqual(Order.eq, collation.compareSerializedKeys(a, b));
    }
    // "cafe" and "café" differ at secondary (accent) — must differ at secondary.
    {
        const a = try serializedFor(allocator, collator_secondary, "cafe");
        defer allocator.free(a);
        const b = try serializedFor(allocator, collator_secondary, "café");
        defer allocator.free(b);
        try testing.expect(collation.compareSerializedKeys(a, b) != .eq);
    }
}

test "sort key: identical strength key is longer than tertiary key" {
    const allocator = testing.allocator;
    const collator_ident = Collator.init(.{ .strength = .identical });
    const collator_tert = Collator.init(.{ .strength = .tertiary });

    // "hello" = 5 codepoints, each stored as 3 bytes in the NFD section.
    // identical key length = tertiary key length + 2 (separator) + 5 * 3 (NFD).
    const ident = try serializedFor(allocator, collator_ident, "hello");
    defer allocator.free(ident);
    const tert = try serializedFor(allocator, collator_tert, "hello");
    defer allocator.free(tert);

    try testing.expectEqual(tert.len + 2 + 5 * 3, ident.len);
}

// ============================================================================
// Variable weighting: quaternary level
// ============================================================================

test "sort key: shifted weighting populates quaternary and includes it in the sort key" {
    const allocator = testing.allocator;
    const opts_shifted = Options{ .variable_weighting = .shifted, .strength = .quaternary };
    const collator_shifted = Collator.init(opts_shifted);

    // "a!" with SHIFTED: "!" is a variable CE, its primary weight goes to
    // quaternary. "a" alone has no quaternary contribution.
    var a_key: collation.Key = .{};
    defer a_key.deinit(allocator);
    var ab_key: collation.Key = .{};
    defer ab_key.deinit(allocator);

    try buildKeyUtf8(allocator, collator_shifted, "a", &a_key);
    try buildKeyUtf8(allocator, collator_shifted, "a!", &ab_key);

    // "a!" must contribute non-empty quaternary weights.
    try testing.expect(ab_key.quaternary.items.len > 0);

    // Serialized "a" < "a!" because the latter adds quaternary weight.
    const sa = try a_key.serializeAlloc(allocator, opts_shifted);
    defer allocator.free(sa);
    const sab = try ab_key.serializeAlloc(allocator, opts_shifted);
    defer allocator.free(sab);
    try testing.expectEqual(Order.lt, collation.compareSerializedKeys(sa, sab));
}

test "sort key: non-ignorable quaternary key equals tertiary key length" {
    const allocator = testing.allocator;
    // NON_IGNORABLE never writes to key.quaternary, so the quaternary level
    // contributes no bytes even when strength = .quaternary.
    const opts_quat_ni = Options{ .variable_weighting = .non_ignorable, .strength = .quaternary };
    const opts_tert_ni = Options{ .variable_weighting = .non_ignorable, .strength = .tertiary };

    const collator_quat = Collator.init(opts_quat_ni);
    const collator_tert = Collator.init(opts_tert_ni);

    const a = try serializedFor(allocator, collator_quat, "hello!");
    defer allocator.free(a);
    const b = try serializedFor(allocator, collator_tert, "hello!");
    defer allocator.free(b);

    try testing.expectEqual(b.len, a.len);
}

// ============================================================================
// Format invariants: 0x0000 only at level boundaries (aligned-pair check)
// ============================================================================

test "sort key: weight sequences contain no zero values" {
    const allocator = testing.allocator;
    const collator = Collator.init(.{ .strength = .tertiary });

    const cps = try encoding.utf8.bytesToUTF8String(allocator, "Hello World 123!");
    defer allocator.free(cps);

    var key: collation.Key = .{};
    defer key.deinit(allocator);
    try collator.buildKey(allocator, cps, &key);

    for (key.primary.items) |w| try testing.expect(w != 0);
    for (key.secondary.items) |w| try testing.expect(w != 0);
    for (key.tertiary.items) |w| try testing.expect(w != 0);
}

test "sort key: separators land on aligned 2-byte boundaries" {
    // The separator 0x0000 is a 2-byte value. Valid weights are also 2-byte
    // big-endian and never zero, so scanning aligned pairs must find 0x0000
    // exactly at the level boundaries and nowhere else.
    const allocator = testing.allocator;
    const collator = Collator.init(.{ .strength = .tertiary });

    const cps = try encoding.utf8.bytesToUTF8String(allocator, "Hello");
    defer allocator.free(cps);

    var key: collation.Key = .{};
    defer key.deinit(allocator);
    try collator.buildKey(allocator, cps, &key);

    const bytes = try key.serializeAlloc(allocator, collator.options);
    defer allocator.free(bytes);

    // For tertiary strength the format is:
    //   [primary weights] 0x0000 [secondary weights] 0x0000 [tertiary weights]
    const sep1_pos = key.primary.items.len * 2;
    const sep2_pos = sep1_pos + 2 + key.secondary.items.len * 2;

    // Separators are at the expected positions.
    try testing.expectEqual(@as(u8, 0), bytes[sep1_pos]);
    try testing.expectEqual(@as(u8, 0), bytes[sep1_pos + 1]);
    try testing.expectEqual(@as(u8, 0), bytes[sep2_pos]);
    try testing.expectEqual(@as(u8, 0), bytes[sep2_pos + 1]);

    // No 0x0000 aligned pair anywhere except the two separators.
    var i: usize = 0;
    while (i + 1 < bytes.len) : (i += 2) {
        const is_sep = (bytes[i] == 0 and bytes[i + 1] == 0);
        const at_sep1 = (i == sep1_pos);
        const at_sep2 = (i == sep2_pos);
        try testing.expect(!is_sep or at_sep1 or at_sep2);
    }
}

// ============================================================================
// Empty string
// ============================================================================

test "sort key: empty string produces separator-only key with tertiary strength" {
    const allocator = testing.allocator;
    const collator = Collator.init(.{ .strength = .tertiary });

    const bytes = try serializedFor(allocator, collator, "");
    defer allocator.free(bytes);

    // No CEs → empty primary/secondary/tertiary arrays.
    // serializedLen = 0 + 2 + 0 + 2 + 0 = 4.
    try testing.expectEqual(@as(usize, 4), bytes.len);
    try testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, bytes);
}

test "sort key: two empty strings compare as equal" {
    const allocator = testing.allocator;
    const collator = Collator.init(.{});

    const a = try serializedFor(allocator, collator, "");
    defer allocator.free(a);
    const b = try serializedFor(allocator, collator, "");
    defer allocator.free(b);

    try testing.expectEqual(Order.eq, collation.compareSerializedKeys(a, b));
}

test "sort key: empty string sorts before any non-empty string" {
    const allocator = testing.allocator;
    const collator = Collator.init(.{});

    const empty = try serializedFor(allocator, collator, "");
    defer allocator.free(empty);

    const non_empty_strings = [_][]const u8{ "a", "A", "1", " ", "!", "中" };
    for (non_empty_strings) |str| {
        const other = try serializedFor(allocator, collator, str);
        defer allocator.free(other);
        try testing.expectEqual(Order.lt, collation.compareSerializedKeys(empty, other));
    }
}

// ============================================================================
// Sort consistency: serialized-key sort equals pairwise Collator order
// ============================================================================

test "sort key: sorting by serialized bytes produces the same order as Collator" {
    const allocator = testing.allocator;
    const collator = Collator.init(.{});

    const words = [_][]const u8{
        "Ångström", "angle", "Angle", "ANGLE",
        "cafe",     "café",  "Cafe",  "Café",
        "résumé",   "resume", "RESUME",
        "hello",    "Hello",  "HELLO",
        "z",        "Z",      "a",    "A",
        "",         "   ",    "123",
    };

    // Serialize all keys.
    var serial = try allocator.alloc([]u8, words.len);
    defer allocator.free(serial);
    for (words, 0..) |word, i| {
        serial[i] = try serializedFor(allocator, collator, word);
    }
    defer for (serial) |sk| allocator.free(sk);

    // Sort an index array by serialized key.
    var indices = try allocator.alloc(usize, words.len);
    defer allocator.free(indices);
    for (0..words.len) |i| indices[i] = i;

    const Ctx = struct {
        keys: []const []u8,
        fn lt(ctx: @This(), a: usize, b: usize) bool {
            return std.mem.lessThan(u8, ctx.keys[a], ctx.keys[b]);
        }
    };
    std.mem.sort(usize, indices, Ctx{ .keys = serial }, Ctx.lt);

    // Consecutive pairs in the sorted result must satisfy a <= b via the Collator.
    for (0..indices.len - 1) |i| {
        const a_str = words[indices[i]];
        const b_str = words[indices[i + 1]];
        const order = try collator.compareUtf8(allocator, a_str, b_str);
        try testing.expect(order != .gt);
    }
}

test "sort key: shifted sort order matches Collator for punctuated strings" {
    const allocator = testing.allocator;
    const collator = Collator.init(.{ .variable_weighting = .shifted, .strength = .identical });

    const words = [_][]const u8{
        "ab",   "a b", "a-b", "a!b",
        "hello world", "helloworld", "hello-world",
        "cafe", "café",
        "",     "a",   "z",
    };

    var serial = try allocator.alloc([]u8, words.len);
    defer allocator.free(serial);
    for (words, 0..) |word, i| {
        serial[i] = try serializedFor(allocator, collator, word);
    }
    defer for (serial) |sk| allocator.free(sk);

    var indices = try allocator.alloc(usize, words.len);
    defer allocator.free(indices);
    for (0..words.len) |i| indices[i] = i;

    const Ctx = struct {
        keys: []const []u8,
        fn lt(ctx: @This(), a: usize, b: usize) bool {
            return std.mem.lessThan(u8, ctx.keys[a], ctx.keys[b]);
        }
    };
    std.mem.sort(usize, indices, Ctx{ .keys = serial }, Ctx.lt);

    for (0..indices.len - 1) |i| {
        const a_str = words[indices[i]];
        const b_str = words[indices[i + 1]];
        const order = try collator.compareUtf8(allocator, a_str, b_str);
        try testing.expect(order != .gt);
    }
}

// ============================================================================
// Transitivity: if A <= B and B <= C then A <= C via serialized keys
// ============================================================================

test "sort key: serialized key ordering is transitive" {
    const allocator = testing.allocator;
    const collator = Collator.init(.{});

    const words = [_][]const u8{ "apple", "APPLE", "banana", "Banana", "cherry", "", "中文", "abc" };

    var serial = try allocator.alloc([]u8, words.len);
    defer allocator.free(serial);
    for (words, 0..) |word, i| {
        serial[i] = try serializedFor(allocator, collator, word);
    }
    defer for (serial) |sk| allocator.free(sk);

    // Check transitivity: for every triple (i, j, k), if serial[i] <= serial[j]
    // and serial[j] <= serial[k] then serial[i] <= serial[k].
    for (0..words.len) |i| {
        for (0..words.len) |j| {
            for (0..words.len) |k| {
                const ij = collation.compareSerializedKeys(serial[i], serial[j]);
                const jk = collation.compareSerializedKeys(serial[j], serial[k]);
                const ik = collation.compareSerializedKeys(serial[i], serial[k]);
                if (ij != .gt and jk != .gt) {
                    try testing.expect(ik != .gt);
                }
            }
        }
    }
}

// ============================================================================
// Supplementary characters and multi-script
// ============================================================================

test "sort key: supplementary plane codepoints produce valid keys" {
    const allocator = testing.allocator;
    const collator = Collator.init(.{ .strength = .identical });

    // Han extension B (supplementary), emoji, Deseret script.
    const strings = [_][]const u8{
        "𠀀",  // CJK Ext B U+20000
        "𝄞",  // Musical symbol G-clef U+1D11E
        "🙂",  // Slightly smiling face U+1F642
        "𐐷",  // Deseret small letter OW U+10437
    };

    for (strings) |str| {
        const bytes = try serializedFor(allocator, collator, str);
        defer allocator.free(bytes);
        // Key must be non-empty (has at least the level separators).
        try testing.expect(bytes.len > 0);
    }

    // Ordering of supplementary strings via serialized keys matches the Collator.
    for (strings) |s| {
        for (strings) |t| {
            const s_bytes = try serializedFor(allocator, collator, s);
            defer allocator.free(s_bytes);
            const t_bytes = try serializedFor(allocator, collator, t);
            defer allocator.free(t_bytes);

            var s_key: collation.Key = .{};
            defer s_key.deinit(allocator);
            var t_key: collation.Key = .{};
            defer t_key.deinit(allocator);
            try buildKeyUtf8(allocator, collator, s, &s_key);
            try buildKeyUtf8(allocator, collator, t, &t_key);

            try testing.expectEqual(
                collator.compareKeys(&s_key, &t_key),
                collation.compareSerializedKeys(s_bytes, t_bytes),
            );
        }
    }
}
