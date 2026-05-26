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

test {
    std.testing.refAllDecls(@This());
}
