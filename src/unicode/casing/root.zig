const std = @import("std");
const encoding = @import("encoding");
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
pub const max_case_mapping_len = 3;

fn simpleCaseMap(table: []const unicode_data.CaseMappingRangeEntry, code_point: CodePoint) CodePoint {
    if (table.len == 0) return code_point;

    var low: usize = 0;
    var high: usize = table.len;

    while (low < high) {
        const mid = low + (high - low) / 2;
        const range = table[mid];

        if (code_point < range.start) {
            high = mid;
        } else if (code_point > range.end) {
            low = mid + 1;
        } else {
            return @intCast(@as(i32, @intCast(code_point)) + range.delta);
        }
    }

    return code_point;
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

pub fn caseFoldFull(code_point: CodePoint, fallback: *[max_case_mapping_len]CodePoint) []const CodePoint {
    if (case_folding.lookup(.full, .default, code_point)) |mapped| return mapped;
    fallback[0] = code_point;
    return fallback[0..1];
}

pub fn caseFoldFullTurkic(code_point: CodePoint, fallback: *[max_case_mapping_len]CodePoint) []const CodePoint {
    if (case_folding.lookup(.full, .turkic, code_point)) |mapped| return mapped;
    fallback[0] = code_point;
    return fallback[0..1];
}

pub fn specialCaseMapping(
    locale: SpecialCaseLocale,
    condition: SpecialCaseCondition,
    code_point: CodePoint,
) ?SpecialCaseMapping {
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
    locale: SpecialCaseLocale,
    condition: SpecialCaseCondition,
    fallback: *[max_case_mapping_len]CodePoint,
) []const CodePoint {
    if (specialCaseMapping(locale, condition, code_point)) |mapping| {
        if (mapping.lower.len != 0) return mapping.lower;
    }
    fallback[0] = toLowerCase(code_point);
    return fallback[0..1];
}

pub fn toUpperCaseFull(
    code_point: CodePoint,
    locale: SpecialCaseLocale,
    condition: SpecialCaseCondition,
    fallback: *[max_case_mapping_len]CodePoint,
) []const CodePoint {
    if (specialCaseMapping(locale, condition, code_point)) |mapping| {
        if (mapping.upper.len != 0) return mapping.upper;
    }
    fallback[0] = toUpperCase(code_point);
    return fallback[0..1];
}

pub fn toTitleCaseFull(
    code_point: CodePoint,
    locale: SpecialCaseLocale,
    condition: SpecialCaseCondition,
    fallback: *[max_case_mapping_len]CodePoint,
) []const CodePoint {
    if (specialCaseMapping(locale, condition, code_point)) |mapping| {
        if (mapping.title.len != 0) return mapping.title;
    }
    fallback[0] = toTitleCase(code_point);
    return fallback[0..1];
}

test {
    std.testing.refAllDecls(@This());
}
