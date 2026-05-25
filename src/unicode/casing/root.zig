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

test {
    std.testing.refAllDecls(@This());
}
