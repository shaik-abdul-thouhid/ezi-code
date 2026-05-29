const std = @import("std");
const encoding = @import("encoding");
const utils = @import("utils");
const types = @import("../types.zig");
const unicode_data = @import("../generated/unicode_data.zig");

pub const case_folding = @import("case_folding.zig");
pub const special_casing = @import("special_casing.zig");

const CodePoint = encoding.CodePoint;

pub const CaseFoldingMode = types.CaseFoldingMode;
pub const CaseFoldingLocale = types.CaseFoldingLocale;
pub const SpecialCaseLocale = special_casing.Locale;
pub const SpecialCaseCondition = special_casing.Condition;
pub const SpecialCaseMapping = special_casing.Mapping;

const CaseSlot = enum { lower, upper, title };

fn maxFoldLen(comptime entries: []const case_folding.FoldEntry) usize {
    return comptime blk: {
        @setEvalBranchQuota(200000);
        var m: usize = 1;
        for (entries) |e| {
            if (e.to.len > m) m = e.to.len;
        }
        break :blk m;
    };
}

fn maxSpecialLen(
    comptime selector: CaseSlot,
    comptime locale: special_casing.Locale,
    comptime condition: special_casing.Condition,
) usize {
    return comptime blk: {
        @setEvalBranchQuota(200000);
        var m: usize = 1;
        for (special_casing.mappings_table) |entry| {
            for (entry.mappings) |mapping| {
                if (mapping.locale != locale) continue;
                if (mapping.condition != condition) continue;
                const arr = switch (selector) {
                    .lower => mapping.lower,
                    .upper => mapping.upper,
                    .title => mapping.title,
                };
                if (arr.len > m) m = arr.len;
            }
        }
        break :blk m;
    };
}

pub fn caseFoldFullCap(comptime locale: CaseFoldingLocale) usize {
    return switch (locale) {
        .default => maxFoldLen(&case_folding.common_full_table),
        .turkic => @max(maxFoldLen(&case_folding.turkic_full_table), maxFoldLen(&case_folding.common_full_table)),
    };
}

pub fn fullCaseMapCap(
    comptime selector: CaseSlot,
    comptime locale: special_casing.Locale,
    comptime condition: special_casing.Condition,
) usize {
    const simple_minimum: usize = 1;
    return @max(simple_minimum, maxSpecialLen(selector, locale, condition));
}

/// Owned buffer holding a case-mapping result. `cap` is computed at comptime
/// from the largest entry in the source table, so the struct is exactly large
/// enough — no over-allocation, no fallback pointers.
pub fn CaseMappingResult(comptime cap: usize) type {
    return struct {
        const Self = @This();

        buf: [cap]CodePoint,
        len: u8,

        pub fn slice(self: *const Self) []const CodePoint {
            return self.buf[0..self.len];
        }
    };
}

fn writeResult(comptime cap: usize, mapped: []const CodePoint) CaseMappingResult(cap) {
    var result: CaseMappingResult(cap) = .{ .buf = undefined, .len = @intCast(mapped.len) };
    for (mapped, 0..) |cp, i| result.buf[i] = cp;
    return result;
}

fn singletonResult(comptime cap: usize, code_point: CodePoint) CaseMappingResult(cap) {
    var result: CaseMappingResult(cap) = .{ .buf = undefined, .len = 1 };
    result.buf[0] = code_point;
    return result;
}

fn simpleCaseMap(table: []const unicode_data.CaseMappingRangeEntry, code_point: CodePoint) CodePoint {
    const range = utils.searchRange(
        unicode_data.CaseMappingRangeEntry,
        CodePoint,
        "start",
        "end",
        table,
        code_point,
    ) orelse return code_point;
    return @intCast(@as(i32, @intCast(code_point)) + range.delta);
}

pub fn toUpperCase(code_point: CodePoint) CodePoint {
    return simpleCaseMap(&unicode_data.uppercase_range_mapping_table, code_point);
}

pub fn toLowerCase(code_point: CodePoint) CodePoint {
    return simpleCaseMap(&unicode_data.lowercase_range_mapping_table, code_point);
}

pub fn toTitleCase(code_point: CodePoint) CodePoint {
    return simpleCaseMap(&unicode_data.titlecase_range_mapping_table, code_point);
}

pub fn caseFoldSimple(code_point: CodePoint) CodePoint {
    return case_folding.lookup(.simple, .default, code_point) orelse code_point;
}

pub fn caseFoldSimpleTurkic(code_point: CodePoint) CodePoint {
    return case_folding.lookup(.simple, .turkic, code_point) orelse code_point;
}

pub fn caseFoldFull(code_point: CodePoint) CaseMappingResult(caseFoldFullCap(.default)) {
    const cap = comptime caseFoldFullCap(.default);
    if (case_folding.lookup(.full, .default, code_point)) |mapped| return writeResult(cap, mapped);
    return singletonResult(cap, code_point);
}

pub fn caseFoldFullTurkic(code_point: CodePoint) CaseMappingResult(caseFoldFullCap(.turkic)) {
    const cap = comptime caseFoldFullCap(.turkic);
    if (case_folding.lookup(.full, .turkic, code_point)) |mapped| return writeResult(cap, mapped);
    return singletonResult(cap, code_point);
}

pub fn specialCaseMapping(comptime locale: SpecialCaseLocale, comptime condition: SpecialCaseCondition, code_point: CodePoint) ?SpecialCaseMapping {
    return switch (locale) {
        .none => switch (condition) {
            .none => special_casing.lookup(.none, .none, code_point),
            .after_i => special_casing.lookup(.none, .after_i, code_point),
            .not_before_dot => special_casing.lookup(.none, .not_before_dot, code_point),
            .after_soft_dotted => special_casing.lookup(.none, .after_soft_dotted, code_point),
            .more_above => special_casing.lookup(.none, .more_above, code_point),
            .final_sigma => special_casing.lookup(.none, .final_sigma, code_point),
            else => null,
        },
        .tr => switch (condition) {
            .none => special_casing.lookup(.tr, .none, code_point),
            .after_i => special_casing.lookup(.tr, .after_i, code_point),
            .not_before_dot => special_casing.lookup(.tr, .not_before_dot, code_point),
            .after_soft_dotted => special_casing.lookup(.tr, .after_soft_dotted, code_point),
            .more_above => special_casing.lookup(.tr, .more_above, code_point),
            .final_sigma => special_casing.lookup(.tr, .final_sigma, code_point),
            else => null,
        },
        .az => switch (condition) {
            .none => special_casing.lookup(.az, .none, code_point),
            .after_i => special_casing.lookup(.az, .after_i, code_point),
            .not_before_dot => special_casing.lookup(.az, .not_before_dot, code_point),
            .after_soft_dotted => special_casing.lookup(.az, .after_soft_dotted, code_point),
            .more_above => special_casing.lookup(.az, .more_above, code_point),
            .final_sigma => special_casing.lookup(.az, .final_sigma, code_point),
            else => null,
        },
        .lt => switch (condition) {
            .none => special_casing.lookup(.lt, .none, code_point),
            .after_i => special_casing.lookup(.lt, .after_i, code_point),
            .not_before_dot => special_casing.lookup(.lt, .not_before_dot, code_point),
            .after_soft_dotted => special_casing.lookup(.lt, .after_soft_dotted, code_point),
            .more_above => special_casing.lookup(.lt, .more_above, code_point),
            .final_sigma => special_casing.lookup(.lt, .final_sigma, code_point),
            else => null,
        },
        else => null,
    };
}

pub fn toLowerCaseFull(
    code_point: CodePoint,
    comptime locale: SpecialCaseLocale,
    comptime condition: SpecialCaseCondition,
) CaseMappingResult(fullCaseMapCap(.lower, locale, condition)) {
    const cap = comptime fullCaseMapCap(.lower, locale, condition);
    if (specialCaseMapping(locale, condition, code_point)) |mapping| {
        if (mapping.lower.len != 0) return writeResult(cap, mapping.lower);
    }
    return singletonResult(cap, toLowerCase(code_point));
}

pub fn toUpperCaseFull(
    code_point: CodePoint,
    comptime locale: SpecialCaseLocale,
    comptime condition: SpecialCaseCondition,
) CaseMappingResult(fullCaseMapCap(.upper, locale, condition)) {
    const cap = comptime fullCaseMapCap(.upper, locale, condition);
    if (specialCaseMapping(locale, condition, code_point)) |mapping| {
        if (mapping.upper.len != 0) return writeResult(cap, mapping.upper);
    }
    return singletonResult(cap, toUpperCase(code_point));
}

pub fn toTitleCaseFull(
    code_point: CodePoint,
    comptime locale: SpecialCaseLocale,
    comptime condition: SpecialCaseCondition,
) CaseMappingResult(fullCaseMapCap(.title, locale, condition)) {
    const cap = comptime fullCaseMapCap(.title, locale, condition);
    if (specialCaseMapping(locale, condition, code_point)) |mapping| {
        if (mapping.title.len != 0) return writeResult(cap, mapping.title);
    }
    return singletonResult(cap, toTitleCase(code_point));
}

pub const EqualFoldMode = enum { simple, full };

inline fn asciiFoldLower(byte: u8) u8 {
    return if ('A' <= byte and byte <= 'Z') byte + ('a' - 'A') else byte;
}

pub inline fn asciiFoldEqual(a: u8, b: u8) bool {
    return asciiFoldLower(a) == asciiFoldLower(b);
}

pub fn equalFoldBytes(comptime mode: EqualFoldMode, s1: []const u8, s2: []const u8) !bool {
    if (mode == .simple) {
        var s1_i: usize = 0;
        var s2_i: usize = 0;

        while (s1_i < s1.len and s2_i < s2.len) {
            // ASCII fast path: both bytes are ASCII => one codepoint each on this step.
            if (s1[s1_i] <= encoding.MAX_ASCII and s2[s2_i] <= encoding.MAX_ASCII) {
                if (!asciiFoldEqual(s1[s1_i], s2[s2_i])) return false;
                s1_i += 1;
                s2_i += 1;
                continue;
            }

            const s1_decoded = try encoding.utf8.validateAndDecodeCodePointBytes(s1, s1_i);
            const s2_decoded = try encoding.utf8.validateAndDecodeCodePointBytes(s2, s2_i);
            s1_i += s1_decoded.len;
            s2_i += s2_decoded.len;

            if (caseFoldSimple(s1_decoded.code_point) != caseFoldSimple(s2_decoded.code_point)) {
                return false;
            }
        }

        return s1_i == s1.len and s2_i == s2.len;
    }

    // Full mode: a single codepoint can fold to multiple codepoints (e.g. U+00DF -> "ss",
    // U+0149 -> U+02BC U+006E, U+0130 -> U+0069 U+0307). Compare the folded streams
    // codepoint-by-codepoint using a small refill buffer per side.
    const cap = comptime caseFoldFullCap(.default);

    var s1_i: usize = 0;
    var s2_i: usize = 0;
    var buf1: [cap]CodePoint = undefined;
    var buf2: [cap]CodePoint = undefined;
    var buf1_len: usize = 0;
    var buf2_len: usize = 0;
    var buf1_pos: usize = 0;
    var buf2_pos: usize = 0;

    while (true) {
        if (buf1_pos >= buf1_len) {
            if (s1_i >= s1.len) break;
            if (s1[s1_i] <= encoding.MAX_ASCII) {
                buf1[0] = asciiFoldLower(s1[s1_i]);
                buf1_len = 1;
                s1_i += 1;
            } else {
                const decoded = try encoding.utf8.validateAndDecodeCodePointBytes(s1, s1_i);
                s1_i += decoded.len;
                const folded = caseFoldFull(decoded.code_point);
                const sl = folded.slice();
                for (sl, 0..) |cp, i| buf1[i] = cp;
                buf1_len = sl.len;
            }
            buf1_pos = 0;
        }

        if (buf2_pos >= buf2_len) {
            if (s2_i >= s2.len) break;
            if (s2[s2_i] <= encoding.MAX_ASCII) {
                buf2[0] = asciiFoldLower(s2[s2_i]);
                buf2_len = 1;
                s2_i += 1;
            } else {
                const decoded = try encoding.utf8.validateAndDecodeCodePointBytes(s2, s2_i);
                s2_i += decoded.len;
                const folded = caseFoldFull(decoded.code_point);
                const sl = folded.slice();
                for (sl, 0..) |cp, i| buf2[i] = cp;
                buf2_len = sl.len;
            }
            buf2_pos = 0;
        }

        if (buf1[buf1_pos] != buf2[buf2_pos]) return false;
        buf1_pos += 1;
        buf2_pos += 1;
    }

    return s1_i == s1.len and s2_i == s2.len and buf1_pos == buf1_len and buf2_pos == buf2_len;
}

pub fn equalFoldBytesLossy(comptime mode: EqualFoldMode, s1: []const u8, s2: []const u8) encoding.utf8.UTF8ValidationLossyError!bool {
    if (mode == .simple) {
        var s1_i: usize = 0;
        var s2_i: usize = 0;

        while (s1_i < s1.len and s2_i < s2.len) {
            if (s1[s1_i] <= encoding.MAX_ASCII and s2[s2_i] <= encoding.MAX_ASCII) {
                if (!asciiFoldEqual(s1[s1_i], s2[s2_i])) return false;
                s1_i += 1;
                s2_i += 1;
                continue;
            }

            const s1_decoded = try encoding.utf8.validateAndDecodeCodePointBytesLossy(s1, s1_i);
            const s2_decoded = try encoding.utf8.validateAndDecodeCodePointBytesLossy(s2, s2_i);
            s1_i += s1_decoded.len;
            s2_i += s2_decoded.len;

            if (caseFoldSimple(s1_decoded.code_point) != caseFoldSimple(s2_decoded.code_point)) {
                return false;
            }
        }

        return s1_i == s1.len and s2_i == s2.len;
    }

    const cap = comptime caseFoldFullCap(.default);

    var s1_i: usize = 0;
    var s2_i: usize = 0;
    var buf1: [cap]CodePoint = undefined;
    var buf2: [cap]CodePoint = undefined;
    var buf1_len: usize = 0;
    var buf2_len: usize = 0;
    var buf1_pos: usize = 0;
    var buf2_pos: usize = 0;

    while (true) {
        if (buf1_pos >= buf1_len) {
            if (s1_i >= s1.len) break;
            if (s1[s1_i] <= encoding.MAX_ASCII) {
                buf1[0] = asciiFoldLower(s1[s1_i]);
                buf1_len = 1;
                s1_i += 1;
            } else {
                const decoded = try encoding.utf8.validateAndDecodeCodePointBytesLossy(s1, s1_i);
                s1_i += decoded.len;
                const folded = caseFoldFull(decoded.code_point);
                const sl = folded.slice();
                for (sl, 0..) |cp, i| buf1[i] = cp;
                buf1_len = sl.len;
            }
            buf1_pos = 0;
        }

        if (buf2_pos >= buf2_len) {
            if (s2_i >= s2.len) break;
            if (s2[s2_i] <= encoding.MAX_ASCII) {
                buf2[0] = asciiFoldLower(s2[s2_i]);
                buf2_len = 1;
                s2_i += 1;
            } else {
                const decoded = try encoding.utf8.validateAndDecodeCodePointBytesLossy(s2, s2_i);
                s2_i += decoded.len;
                const folded = caseFoldFull(decoded.code_point);
                const sl = folded.slice();
                for (sl, 0..) |cp, i| buf2[i] = cp;
                buf2_len = sl.len;
            }
            buf2_pos = 0;
        }

        if (buf1[buf1_pos] != buf2[buf2_pos]) return false;
        buf1_pos += 1;
        buf2_pos += 1;
    }

    return s1_i == s1.len and s2_i == s2.len and buf1_pos == buf1_len and buf2_pos == buf2_len;
}

pub fn equalFoldCodePoints(comptime mode: EqualFoldMode, s1: []const CodePoint, s2: []const CodePoint) bool {
    if (mode == .simple) {
        if (s1.len != s2.len) return false;
        for (s1, s2) |a, b| {
            if (caseFoldSimple(a) != caseFoldSimple(b)) return false;
        }
        return true;
    }

    const cap = comptime caseFoldFullCap(.default);

    var s1_i: usize = 0;
    var s2_i: usize = 0;
    var buf1: [cap]CodePoint = undefined;
    var buf2: [cap]CodePoint = undefined;
    var buf1_len: usize = 0;
    var buf2_len: usize = 0;
    var buf1_pos: usize = 0;
    var buf2_pos: usize = 0;

    while (true) {
        if (buf1_pos >= buf1_len) {
            if (s1_i >= s1.len) break;
            const folded = caseFoldFull(s1[s1_i]);
            s1_i += 1;
            const sl = folded.slice();
            for (sl, 0..) |cp, j| buf1[j] = cp;
            buf1_len = sl.len;
            buf1_pos = 0;
        }

        if (buf2_pos >= buf2_len) {
            if (s2_i >= s2.len) break;
            const folded = caseFoldFull(s2[s2_i]);
            s2_i += 1;
            const sl = folded.slice();
            for (sl, 0..) |cp, j| buf2[j] = cp;
            buf2_len = sl.len;
            buf2_pos = 0;
        }

        if (buf1[buf1_pos] != buf2[buf2_pos]) return false;
        buf1_pos += 1;
        buf2_pos += 1;
    }

    return s1_i == s1.len and s2_i == s2.len and buf1_pos == buf1_len and buf2_pos == buf2_len;
}

// ============================================================================
// Tests (relocated from unicode/root.zig during the slim-facade refactor)
// ============================================================================

const properties = @import("../properties/root.zig");
const testing = std.testing;

test "unicode api: derived properties, case folding, and full special casing are not decorative wrappers" {
    try testing.expect(properties.isAlphabetic('A'));
    try testing.expect(properties.isUpperCase('A'));
    try testing.expect(properties.isLowerCase('a'));
    try testing.expect(properties.isMath('+'));
    try testing.expect(properties.isIdStart('A'));
    try testing.expect(!properties.isIdStart('_'));
    try testing.expect(properties.isIdentifierStart('_'));
    try testing.expect(properties.isXidContinue(0x0301));

    try testing.expectEqual(@as(CodePoint, 'a'), caseFoldSimple('A'));
    try testing.expectEqual(@as(CodePoint, 0x0131), caseFoldSimpleTurkic('I'));
    try testing.expectEqual(@as(CodePoint, 'a'), caseFoldSimpleTurkic('A'));

    {
        const r = caseFoldFull(0x00DF);
        try testing.expectEqualSlices(CodePoint, &.{ 's', 's' }, r.slice());
    }
    {
        const r = caseFoldFull(0x10FFFF);
        try testing.expectEqualSlices(CodePoint, &.{0x10FFFF}, r.slice());
    }

    {
        const r = toLowerCaseFull(0x0130, .none, .none);
        try testing.expectEqualSlices(CodePoint, &.{ 0x69, 0x307 }, r.slice());
    }
    {
        const r = toLowerCaseFull(0x0130, .tr, .none);
        try testing.expectEqualSlices(CodePoint, &.{0x69}, r.slice());
    }
    {
        const r = toLowerCaseFull(0x03A3, .none, .final_sigma);
        try testing.expectEqualSlices(CodePoint, &.{0x03C2}, r.slice());
    }
}

test "toUpperCase: ASCII lowercase to uppercase" {
    for ('a'..'z' + 1) |cp| {
        const upper = toUpperCase(@as(CodePoint, @intCast(cp)));
        try testing.expectEqual(cp - ('a' - 'A'), upper);
    }
}

test "toUpperCase: ASCII uppercase unchanged" {
    for ('A'..'Z' + 1) |cp| {
        const upper = toUpperCase(@as(CodePoint, @intCast(cp)));
        try testing.expectEqual(cp, upper);
    }
}

test "toUpperCase: ASCII non-letters unchanged" {
    for ('0'..'9' + 1) |cp| {
        const upper = toUpperCase(@as(CodePoint, @intCast(cp)));
        try testing.expectEqual(cp, upper);
    }
}

test "toUpperCase: extended Latin" {
    const cases = [_]struct { lower: CodePoint, upper: CodePoint }{
        .{ .lower = 0xE0, .upper = 0xC0 },
        .{ .lower = 0xE9, .upper = 0xC9 },
        .{ .lower = 0xF1, .upper = 0xD1 },
    };
    for (cases) |tc| try testing.expectEqual(tc.upper, toUpperCase(tc.lower));
}

test "toUpperCase: already uppercase unchanged" {
    for ([_]CodePoint{ 0xC0, 0xC9, 0xD1 }) |cp| try testing.expectEqual(cp, toUpperCase(cp));
}

test "toLowerCase: ASCII uppercase to lowercase" {
    for ('A'..'Z' + 1) |cp| {
        const lower = toLowerCase(@as(CodePoint, @intCast(cp)));
        try testing.expectEqual(cp + ('a' - 'A'), lower);
    }
}

test "toLowerCase: ASCII lowercase unchanged" {
    for ('a'..'z' + 1) |cp| {
        const lower = toLowerCase(@as(CodePoint, @intCast(cp)));
        try testing.expectEqual(cp, lower);
    }
}

test "toLowerCase: ASCII non-letters unchanged" {
    for ('0'..'9' + 1) |cp| {
        const lower = toLowerCase(@as(CodePoint, @intCast(cp)));
        try testing.expectEqual(cp, lower);
    }
}

test "toLowerCase: extended Latin" {
    const cases = [_]struct { upper: CodePoint, lower: CodePoint }{
        .{ .upper = 0xC0, .lower = 0xE0 },
        .{ .upper = 0xC9, .lower = 0xE9 },
        .{ .upper = 0xD1, .lower = 0xF1 },
    };
    for (cases) |tc| try testing.expectEqual(tc.lower, toLowerCase(tc.upper));
}

test "toLowerCase: already lowercase unchanged" {
    for ([_]CodePoint{ 0xE0, 0xE9, 0xF1 }) |cp| try testing.expectEqual(cp, toLowerCase(cp));
}

test "toTitleCase: ASCII uppercase and lowercase" {
    for ('a'..'z' + 1) |cp| {
        try testing.expectEqual(cp - ('a' - 'A'), toTitleCase(@as(CodePoint, @intCast(cp))));
    }
    for ('A'..'Z' + 1) |cp| {
        try testing.expectEqual(cp, toTitleCase(@as(CodePoint, @intCast(cp))));
    }
}

test "toTitleCase: non-letters unchanged" {
    for ('0'..'9' + 1) |cp| {
        try testing.expectEqual(cp, toTitleCase(@as(CodePoint, @intCast(cp))));
    }
}

test "case conversion roundtrip: uppercase->lowercase->uppercase" {
    for ([_]CodePoint{ 'A', 'B', 'Z', 0xC0, 0xC9 }) |cp| {
        const lower = toLowerCase(cp);
        const upper = toUpperCase(lower);
        if (cp <= 'Z') try testing.expectEqual(cp, upper);
    }
}

test "case conversion roundtrip: lowercase->uppercase->lowercase" {
    for ([_]CodePoint{ 'a', 'b', 'z', 0xE0, 0xE9 }) |cp| {
        const upper = toUpperCase(cp);
        const lower = toLowerCase(upper);
        if (cp <= 'z') try testing.expectEqual(cp, lower);
    }
}

test "edge case: null code point maps to itself under every casing operation" {
    try testing.expectEqual(@as(CodePoint, 0), toUpperCase(0));
    try testing.expectEqual(@as(CodePoint, 0), toLowerCase(0));
    try testing.expectEqual(@as(CodePoint, 0), toTitleCase(0));
}

test "hostile: case mapping with unusual inputs never produces invalid code points" {
    for (0x0000..0x10FFFF) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        if (cp >= 0xD800 and cp <= 0xDFFF) continue; // skip surrogates
        try testing.expect(toUpperCase(cp) <= 0x10FFFF);
        try testing.expect(toLowerCase(cp) <= 0x10FFFF);
        try testing.expect(toTitleCase(cp) <= 0x10FFFF);
    }
}

test "binary search: case mapping correctness in ranges" {
    for (0xC2..0xDF) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        _ = toUpperCase(cp);
        _ = toLowerCase(cp);
    }
}

// ============================================================================
// equalFoldBytes tests
// ============================================================================

test "equalFoldBytes simple: empty strings are equal" {
    try testing.expect(try equalFoldBytes(.simple, "", ""));
}

test "equalFoldBytes simple: empty vs non-empty" {
    try testing.expect(!try equalFoldBytes(.simple, "", "a"));
    try testing.expect(!try equalFoldBytes(.simple, "a", ""));
    try testing.expect(!try equalFoldBytes(.simple, "", "abc"));
    try testing.expect(!try equalFoldBytes(.simple, "abc", ""));
}

test "equalFoldBytes simple: identical ASCII" {
    try testing.expect(try equalFoldBytes(.simple, "hello", "hello"));
    try testing.expect(try equalFoldBytes(.simple, "Hello, World!", "Hello, World!"));
    try testing.expect(try equalFoldBytes(.simple, "a", "a"));
}

test "equalFoldBytes simple: ASCII case-insensitive" {
    try testing.expect(try equalFoldBytes(.simple, "hello", "HELLO"));
    try testing.expect(try equalFoldBytes(.simple, "Hello", "hELLO"));
    try testing.expect(try equalFoldBytes(.simple, "hElLo", "HeLlO"));
    try testing.expect(try equalFoldBytes(.simple, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz"));
}

test "equalFoldBytes simple: ASCII full alphabet roundtrip" {
    for ('A'..'Z' + 1) |c| {
        const upper = [_]u8{@intCast(c)};
        const lower = [_]u8{@intCast(c + ('a' - 'A'))};
        try testing.expect(try equalFoldBytes(.simple, &upper, &lower));
        try testing.expect(try equalFoldBytes(.simple, &lower, &upper));
    }
}

test "equalFoldBytes simple: ASCII digits and punctuation not folded" {
    try testing.expect(try equalFoldBytes(.simple, "123", "123"));
    try testing.expect(try equalFoldBytes(.simple, "!@#$%", "!@#$%"));
    try testing.expect(!try equalFoldBytes(.simple, "1", "2"));
    try testing.expect(!try equalFoldBytes(.simple, "!", "?"));
}

test "equalFoldBytes simple: ASCII non-letter byte close to A-Z is not folded" {
    // '@' (0x40) is just below 'A' (0x41); '[' (0x5B) is just above 'Z' (0x5A).
    // These must not be confused with case-folding neighbours.
    try testing.expect(!try equalFoldBytes(.simple, "@", "`"));
    try testing.expect(!try equalFoldBytes(.simple, "[", "{"));
    try testing.expect(!try equalFoldBytes(.simple, "A", "@"));
    try testing.expect(!try equalFoldBytes(.simple, "Z", "["));
}

test "equalFoldBytes simple: different ASCII lengths" {
    try testing.expect(!try equalFoldBytes(.simple, "hello", "hellos"));
    try testing.expect(!try equalFoldBytes(.simple, "hellos", "hello"));
    try testing.expect(!try equalFoldBytes(.simple, "a", "ab"));
}

test "equalFoldBytes simple: non-ASCII identity" {
    // U+00E9 (é) == U+00E9
    try testing.expect(try equalFoldBytes(.simple, "café", "café"));
    // U+1F600 (😀) == U+1F600
    try testing.expect(try equalFoldBytes(.simple, "\u{1F600}", "\u{1F600}"));
}

test "equalFoldBytes simple: Latin-1 case fold" {
    // U+00C9 (É) folds to U+00E9 (é)
    try testing.expect(try equalFoldBytes(.simple, "café", "CAFÉ"));
    // U+00DC (Ü) <-> U+00FC (ü)
    try testing.expect(try equalFoldBytes(.simple, "Ü", "ü"));
    // U+00D1 (Ñ) <-> U+00F1 (ñ)
    try testing.expect(try equalFoldBytes(.simple, "ÑOÑO", "ñoño"));
}

test "equalFoldBytes simple: Greek case fold" {
    // U+0391 (Α) <-> U+03B1 (α)
    try testing.expect(try equalFoldBytes(.simple, "Α", "α"));
    // U+0395 (Ε) <-> U+03B5 (ε)
    try testing.expect(try equalFoldBytes(.simple, "Ε", "ε"));
}

test "equalFoldBytes simple: Cyrillic case fold" {
    // U+0410 (А Cyrillic) <-> U+0430 (а Cyrillic)
    try testing.expect(try equalFoldBytes(.simple, "ПРИВЕТ", "привет"));
}

test "equalFoldBytes simple: KELVIN SIGN folds to k" {
    // U+212A (KELVIN SIGN) folds to U+006B (k)
    try testing.expect(try equalFoldBytes(.simple, "\u{212A}", "k"));
    try testing.expect(try equalFoldBytes(.simple, "k", "\u{212A}"));
    try testing.expect(try equalFoldBytes(.simple, "\u{212A}", "K"));
}

test "equalFoldBytes simple: ß does NOT fold to ss in simple mode" {
    // In simple mode, U+00DF stays as U+00DF (no expansion). "ss" != "ß".
    try testing.expect(!try equalFoldBytes(.simple, "ß", "ss"));
    try testing.expect(!try equalFoldBytes(.simple, "ss", "ß"));
    // But "ß" == "ß" trivially.
    try testing.expect(try equalFoldBytes(.simple, "ß", "ß"));
}

test "equalFoldBytes simple: latin mixed with non-ASCII" {
    try testing.expect(try equalFoldBytes(.simple, "Hello Café", "hello café"));
    try testing.expect(try equalFoldBytes(.simple, "Hello Café", "HELLO CAFÉ"));
    try testing.expect(!try equalFoldBytes(.simple, "Hello Café", "Hello Cafe"));
}

test "equalFoldBytes simple: differing non-ASCII codepoints" {
    try testing.expect(!try equalFoldBytes(.simple, "é", "è"));
    try testing.expect(!try equalFoldBytes(.simple, "α", "β"));
}

test "equalFoldBytes simple: mismatched lengths with non-ASCII" {
    try testing.expect(!try equalFoldBytes(.simple, "café", "caféé"));
    try testing.expect(!try equalFoldBytes(.simple, "café", "caf"));
}

test "equalFoldBytes simple: invalid UTF-8 surfaces as error" {
    // 0xC0 0x80 is overlong NUL, 0xFF is invalid.
    try testing.expectError(error.InvalidByteSequence, equalFoldBytes(.simple, "\xFF", "?"));
    try testing.expectError(error.InvalidByteSequence, equalFoldBytes(.simple, "a", "\xFF"));
    // truncated 2-byte sequence
    try testing.expectError(error.IndexOutOfBounds, equalFoldBytes(.simple, "\xC3", "a"));
}

test "equalFoldBytes full: empty strings are equal" {
    try testing.expect(try equalFoldBytes(.full, "", ""));
}

test "equalFoldBytes full: empty vs non-empty" {
    try testing.expect(!try equalFoldBytes(.full, "", "a"));
    try testing.expect(!try equalFoldBytes(.full, "a", ""));
}

test "equalFoldBytes full: identical ASCII" {
    try testing.expect(try equalFoldBytes(.full, "hello", "hello"));
    try testing.expect(try equalFoldBytes(.full, "Hello, World!", "Hello, World!"));
}

test "equalFoldBytes full: ASCII case-insensitive" {
    try testing.expect(try equalFoldBytes(.full, "hello", "HELLO"));
    try testing.expect(try equalFoldBytes(.full, "Hello, World!", "hELLO, wORLD!"));
    try testing.expect(try equalFoldBytes(.full, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz"));
}

test "equalFoldBytes full: ß folds to ss" {
    // The canonical full-mode test: U+00DF expands to "ss" in case folding.
    try testing.expect(try equalFoldBytes(.full, "ß", "ss"));
    try testing.expect(try equalFoldBytes(.full, "ss", "ß"));
    try testing.expect(try equalFoldBytes(.full, "ß", "SS"));
    try testing.expect(try equalFoldBytes(.full, "SS", "ß"));
    try testing.expect(try equalFoldBytes(.full, "ß", "Ss"));
    try testing.expect(try equalFoldBytes(.full, "ß", "sS"));
}

test "equalFoldBytes full: ß in the middle of a word" {
    try testing.expect(try equalFoldBytes(.full, "Straße", "strasse"));
    try testing.expect(try equalFoldBytes(.full, "Straße", "STRASSE"));
    try testing.expect(try equalFoldBytes(.full, "Maßstab", "massstab"));
}

test "equalFoldBytes full: ß does not match a single s" {
    try testing.expect(!try equalFoldBytes(.full, "ß", "s"));
    try testing.expect(!try equalFoldBytes(.full, "s", "ß"));
}

test "equalFoldBytes full: ligature ff folds to ff" {
    // U+FB00 (ﬀ) folds to "ff" under full mode.
    try testing.expect(try equalFoldBytes(.full, "\u{FB00}", "ff"));
    try testing.expect(try equalFoldBytes(.full, "\u{FB00}", "FF"));
    try testing.expect(try equalFoldBytes(.full, "a\u{FB00}b", "affb"));
}

test "equalFoldBytes full: ligature fi folds to fi" {
    // U+FB01 (ﬁ) folds to "fi" under full mode.
    try testing.expect(try equalFoldBytes(.full, "\u{FB01}", "fi"));
    try testing.expect(try equalFoldBytes(.full, "\u{FB01}", "FI"));
}

test "equalFoldBytes full: ŉ folds to two codepoints" {
    // U+0149 (ŉ) folds to U+02BC U+006E.
    try testing.expect(try equalFoldBytes(.full, "\u{0149}", "\u{02BC}n"));
    try testing.expect(try equalFoldBytes(.full, "\u{02BC}n", "\u{0149}"));
}

test "equalFoldBytes full: İ folds to i + combining dot" {
    // U+0130 (İ) folds to U+0069 U+0307 under full default folding.
    try testing.expect(try equalFoldBytes(.full, "\u{0130}", "i\u{0307}"));
    try testing.expect(try equalFoldBytes(.full, "i\u{0307}", "\u{0130}"));
}

test "equalFoldBytes full: KELVIN SIGN folds to k" {
    try testing.expect(try equalFoldBytes(.full, "\u{212A}", "k"));
    try testing.expect(try equalFoldBytes(.full, "K\u{212A}lvin", "KKlvin"));
}

test "equalFoldBytes full: expansion + suffix mismatch" {
    // s1 expands to more codepoints than s2 has -> not equal.
    try testing.expect(!try equalFoldBytes(.full, "ß", "s"));
    try testing.expect(!try equalFoldBytes(.full, "ßx", "ssy"));
    try testing.expect(!try equalFoldBytes(.full, "ßx", "ss"));
    try testing.expect(!try equalFoldBytes(.full, "ss", "ßx"));
}

test "equalFoldBytes full: multiple expansions in a row" {
    try testing.expect(try equalFoldBytes(.full, "ßß", "ssss"));
    try testing.expect(try equalFoldBytes(.full, "ßß", "SSSS"));
    try testing.expect(try equalFoldBytes(.full, "ssss", "ßß"));
    try testing.expect(!try equalFoldBytes(.full, "ßß", "sss"));
    try testing.expect(!try equalFoldBytes(.full, "ßß", "sssss"));
}

test "equalFoldBytes full: expansion at boundary between strings" {
    // ß at end of s1 must consume two s's at end of s2.
    try testing.expect(try equalFoldBytes(.full, "aß", "ass"));
    try testing.expect(try equalFoldBytes(.full, "ass", "aß"));
    // ß at start.
    try testing.expect(try equalFoldBytes(.full, "ßa", "ssa"));
    try testing.expect(try equalFoldBytes(.full, "ssa", "ßa"));
}

test "equalFoldBytes full: differing non-ASCII codepoints" {
    try testing.expect(!try equalFoldBytes(.full, "é", "è"));
    try testing.expect(!try equalFoldBytes(.full, "α", "β"));
}

test "equalFoldBytes full: Greek and Cyrillic case fold" {
    try testing.expect(try equalFoldBytes(.full, "ΑΒΓ", "αβγ"));
    try testing.expect(try equalFoldBytes(.full, "ПРИВЕТ", "привет"));
}

test "equalFoldBytes full: invalid UTF-8 surfaces as error" {
    try testing.expectError(error.InvalidByteSequence, equalFoldBytes(.full, "\xFF", "?"));
    try testing.expectError(error.InvalidByteSequence, equalFoldBytes(.full, "a", "\xFF"));
    try testing.expectError(error.IndexOutOfBounds, equalFoldBytes(.full, "\xC3", "a"));
}

test "equalFoldBytes full: identity for high-plane codepoints" {
    try testing.expect(try equalFoldBytes(.full, "\u{1F600}", "\u{1F600}"));
    try testing.expect(!try equalFoldBytes(.full, "\u{1F600}", "\u{1F601}"));
}

// ============================================================================
// equalFoldBytesLossy tests
// ============================================================================

test "equalFoldBytesLossy simple: matches strict on valid input" {
    try testing.expect(try equalFoldBytesLossy(.simple, "", ""));
    try testing.expect(try equalFoldBytesLossy(.simple, "hello", "HELLO"));
    try testing.expect(try equalFoldBytesLossy(.simple, "café", "CAFÉ"));
    try testing.expect(!try equalFoldBytesLossy(.simple, "hello", "world"));
    try testing.expect(!try equalFoldBytesLossy(.simple, "ß", "ss"));
}

test "equalFoldBytesLossy full: matches strict on valid input" {
    try testing.expect(try equalFoldBytesLossy(.full, "ß", "ss"));
    try testing.expect(try equalFoldBytesLossy(.full, "Straße", "STRASSE"));
    try testing.expect(try equalFoldBytesLossy(.full, "\u{FB00}", "ff"));
    try testing.expect(!try equalFoldBytesLossy(.full, "ß", "s"));
}

test "equalFoldBytesLossy: invalid bytes do not surface as errors" {
    // Strict would error here; lossy replaces with U+FFFD and continues.
    try testing.expect(try equalFoldBytesLossy(.simple, "\xFF", "\xFF"));
    try testing.expect(try equalFoldBytesLossy(.full, "\xFF", "\xFF"));
}

test "equalFoldBytesLossy: invalid byte vs valid byte not equal" {
    // Invalid byte folds to U+FFFD; not equal to '?'.
    try testing.expect(!try equalFoldBytesLossy(.simple, "\xFF", "?"));
    try testing.expect(!try equalFoldBytesLossy(.full, "\xFF", "?"));
}

test "equalFoldBytesLossy: replacement char matches replacement char" {
    // Both sides produce U+FFFD: explicit replacement vs invalid byte.
    try testing.expect(try equalFoldBytesLossy(.simple, "\u{FFFD}", "\xFF"));
    try testing.expect(try equalFoldBytesLossy(.full, "\u{FFFD}", "\xFF"));
}

test "equalFoldBytesLossy: invalid bytes embedded in valid text" {
    try testing.expect(try equalFoldBytesLossy(.simple, "a\xFFb", "A\xFFB"));
    try testing.expect(try equalFoldBytesLossy(.full, "a\xFFß", "A\xFFss"));
}

// ============================================================================
// equalFoldCodePoints tests
// ============================================================================

test "equalFoldCodePoints simple: empty inputs" {
    try testing.expect(equalFoldCodePoints(.simple, &.{}, &.{}));
    try testing.expect(!equalFoldCodePoints(.simple, &.{}, &.{'a'}));
    try testing.expect(!equalFoldCodePoints(.simple, &.{'a'}, &.{}));
}

test "equalFoldCodePoints simple: ASCII case-insensitive" {
    try testing.expect(equalFoldCodePoints(.simple, &.{ 'H', 'I' }, &.{ 'h', 'i' }));
    try testing.expect(equalFoldCodePoints(.simple, &.{ 'a', 'B', 'c' }, &.{ 'A', 'b', 'C' }));
    try testing.expect(!equalFoldCodePoints(.simple, &.{ 'a', 'b' }, &.{ 'a', 'c' }));
}

test "equalFoldCodePoints simple: length mismatch" {
    try testing.expect(!equalFoldCodePoints(.simple, &.{ 'a', 'b', 'c' }, &.{ 'a', 'b' }));
    try testing.expect(!equalFoldCodePoints(.simple, &.{ 'a', 'b' }, &.{ 'a', 'b', 'c' }));
}

test "equalFoldCodePoints simple: non-ASCII case fold" {
    // É (U+00C9) == é (U+00E9) under simple fold.
    try testing.expect(equalFoldCodePoints(.simple, &.{0x00C9}, &.{0x00E9}));
    // KELVIN SIGN (U+212A) == k (U+006B)
    try testing.expect(equalFoldCodePoints(.simple, &.{0x212A}, &.{'k'}));
    // Greek Α (U+0391) == α (U+03B1)
    try testing.expect(equalFoldCodePoints(.simple, &.{0x0391}, &.{0x03B1}));
}

test "equalFoldCodePoints simple: ß does NOT fold to ss in simple mode" {
    try testing.expect(!equalFoldCodePoints(.simple, &.{0x00DF}, &.{ 's', 's' }));
}

test "equalFoldCodePoints full: ß folds to ss" {
    try testing.expect(equalFoldCodePoints(.full, &.{0x00DF}, &.{ 's', 's' }));
    try testing.expect(equalFoldCodePoints(.full, &.{ 's', 's' }, &.{0x00DF}));
    try testing.expect(equalFoldCodePoints(.full, &.{0x00DF}, &.{ 'S', 'S' }));
}

test "equalFoldCodePoints full: ligatures" {
    // U+FB00 (ﬀ) -> "ff"
    try testing.expect(equalFoldCodePoints(.full, &.{0xFB00}, &.{ 'f', 'f' }));
    // U+FB01 (ﬁ) -> "fi"
    try testing.expect(equalFoldCodePoints(.full, &.{0xFB01}, &.{ 'F', 'I' }));
}

test "equalFoldCodePoints full: İ folds to i + combining dot" {
    try testing.expect(equalFoldCodePoints(.full, &.{0x0130}, &.{ 0x0069, 0x0307 }));
}

test "equalFoldCodePoints full: ŉ folds to two codepoints" {
    try testing.expect(equalFoldCodePoints(.full, &.{0x0149}, &.{ 0x02BC, 0x006E }));
}

test "equalFoldCodePoints full: expansion at boundaries" {
    try testing.expect(equalFoldCodePoints(.full, &.{ 'a', 0x00DF }, &.{ 'A', 's', 's' }));
    try testing.expect(equalFoldCodePoints(.full, &.{ 0x00DF, 'a' }, &.{ 's', 's', 'A' }));
    try testing.expect(!equalFoldCodePoints(.full, &.{ 0x00DF, 'a' }, &.{ 's', 's' }));
    try testing.expect(!equalFoldCodePoints(.full, &.{ 0x00DF, 'a' }, &.{ 's', 's', 's' }));
}

test "equalFoldCodePoints full: multiple expansions" {
    try testing.expect(equalFoldCodePoints(.full, &.{ 0x00DF, 0x00DF }, &.{ 's', 's', 's', 's' }));
    try testing.expect(!equalFoldCodePoints(.full, &.{ 0x00DF, 0x00DF }, &.{ 's', 's', 's' }));
}

test "equalFoldCodePoints full: high-plane identity" {
    try testing.expect(equalFoldCodePoints(.full, &.{0x1F600}, &.{0x1F600}));
    try testing.expect(!equalFoldCodePoints(.full, &.{0x1F600}, &.{0x1F601}));
}

test {
    std.testing.refAllDecls(@This());
}
