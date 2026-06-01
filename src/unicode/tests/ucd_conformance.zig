const std = @import("std");
const encoding = @import("encoding");
const utils = @import("utils");

const unicode_data = @import("../generated/unicode_data.zig");
const derived = @import("../properties/generated/derived_core_properties.zig");
const prop_list = @import("../properties/generated/prop_list.zig");
const case_folding = @import("../casing/generated/case_folding.zig");
const special_casing = @import("../casing/generated/special_casing.zig");
const grapheme_break = @import("../segmentation/generated/grapheme_break.zig");
const emoji_data = @import("../segmentation/generated/emoji_data.zig");
const word_break = @import("../segmentation/generated/word_break.zig");
const sentence_break = @import("../segmentation/generated/sentence_break.zig");
const line_break = @import("../segmentation/generated/line_break.zig");
const east_asian_width = @import("../width/generated/east_asian_width.zig");
const dnp = @import("../normalization/generated/derived_normalization_props.zig");
const decomposition = @import("../normalization/generated/decomposition.zig");
const normalization = @import("../normalization/root.zig");
const segmentation = @import("../segmentation/root.zig");
const scripts = @import("../scripts/root.zig");
const bidi_props = @import("../bidi/root.zig");
const numeric_props = @import("../numeric/root.zig");
const blocks_props = @import("../blocks/root.zig");
const hangul_props = @import("../hangul/root.zig");
const age_props = @import("../age/root.zig");
const unicode_types = @import("../types.zig");

const ScriptType = scripts.ScriptType;

const CodePoint = encoding.CodePoint;
const testing = std.testing;

const unicode_data_path = "ucd/UnicodeData.txt";
const derived_core_properties_path = "ucd/DerivedCoreProperties.txt";
const prop_list_path = "ucd/PropList.txt";
const case_folding_path = "ucd/CaseFolding.txt";
const special_casing_path = "ucd/SpecialCasing.txt";
const grapheme_break_property_path = "ucd/GraphemeBreakProperty.txt";
const grapheme_break_test_path = "ucd/GraphemeBreakTest.txt";
const word_break_property_path = "ucd/WordBreakProperty.txt";
const word_break_test_path = "ucd/WordBreakTest.txt";
const sentence_break_property_path = "ucd/SentenceBreakProperty.txt";
const sentence_break_test_path = "ucd/SentenceBreakTest.txt";
const line_break_path = "ucd/LineBreak.txt";
const line_break_test_path = "ucd/LineBreakTest.txt";
const east_asian_width_path = "ucd/EastAsianWidth.txt";
const emoji_data_path = "ucd/emoji-data.txt";
const derived_normalization_props_path = "ucd/DerivedNormalizationProps.txt";
const normalization_test_path = "ucd/NormalizationTest.txt";
const property_value_aliases_path = "ucd/PropertyValueAliases.txt";
const scripts_path = "ucd/Scripts.txt";
const script_extensions_path = "ucd/ScriptExtensions.txt";
const bidi_brackets_path = "ucd/BidiBrackets.txt";
const bidi_mirroring_path = "ucd/BidiMirroring.txt";
const numeric_type_path = "ucd/DerivedNumericType.txt";
const numeric_values_path = "ucd/DerivedNumericValues.txt";
const blocks_path = "ucd/Blocks.txt";
const hangul_syllable_type_path = "ucd/HangulSyllableType.txt";
const derived_age_path = "ucd/DerivedAge.txt";
const bidi_test_path = "ucd/BidiTest.txt";
const bidi_character_test_path = "ucd/BidiCharacterTest.txt";

fn cleanData(line: []const u8) []const u8 {
    var comment_split = std.mem.splitScalar(u8, line, '#');
    return std.mem.trim(u8, comment_split.next().?, " \t\r");
}

fn parseCodePoint(text: []const u8) !CodePoint {
    return try std.fmt.parseInt(CodePoint, std.mem.trim(u8, text, " \t\r"), 16);
}

fn parseRange(text: []const u8) !struct { start: CodePoint, end: CodePoint } {
    var split = std.mem.splitSequence(u8, std.mem.trim(u8, text, " \t\r"), "..");
    const start = try parseCodePoint(split.next() orelse return error.BadRange);
    const end = if (split.next()) |raw| try parseCodePoint(raw) else start;
    return .{ .start = start, .end = end };
}

fn parseCodePointList(text: []const u8, out: *[4]CodePoint) ![]const CodePoint {
    var len: usize = 0;
    var split = std.mem.splitScalar(u8, std.mem.trim(u8, text, " \t\r"), ' ');
    while (split.next()) |token| {
        if (token.len == 0) continue;
        if (len == out.len) return error.MappingTooLong;
        out[len] = try parseCodePoint(token);
        len += 1;
    }
    return out[0..len];
}

fn expectCodePointSlices(expected: []const CodePoint, actual: []const CodePoint) !void {
    try testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |want, got| {
        try testing.expectEqual(want, got);
    }
}

fn categoryFromUcd(raw: []const u8) unicode_data.GeneralCategory {
    if (std.mem.eql(u8, raw, "Lu")) return .uppercase_letter;
    if (std.mem.eql(u8, raw, "Ll")) return .lowercase_letter;
    if (std.mem.eql(u8, raw, "Lt")) return .titlecase_letter;
    if (std.mem.eql(u8, raw, "Lm")) return .modifier_letter;
    if (std.mem.eql(u8, raw, "Lo")) return .other_letter;
    if (std.mem.eql(u8, raw, "Mn")) return .non_spacing_mark;
    if (std.mem.eql(u8, raw, "Mc")) return .spacing_mark;
    if (std.mem.eql(u8, raw, "Me")) return .enclosing_mark;
    if (std.mem.eql(u8, raw, "Nd")) return .decimal_number;
    if (std.mem.eql(u8, raw, "Nl")) return .letter_number;
    if (std.mem.eql(u8, raw, "No")) return .other_number;
    if (std.mem.eql(u8, raw, "Pc")) return .connector_punctuation;
    if (std.mem.eql(u8, raw, "Pd")) return .dash_punctuation;
    if (std.mem.eql(u8, raw, "Ps")) return .open_punctuation;
    if (std.mem.eql(u8, raw, "Pe")) return .close_punctuation;
    if (std.mem.eql(u8, raw, "Pi")) return .initial_punctuation;
    if (std.mem.eql(u8, raw, "Pf")) return .final_punctuation;
    if (std.mem.eql(u8, raw, "Po")) return .other_punctuation;
    if (std.mem.eql(u8, raw, "Sm")) return .math_symbol;
    if (std.mem.eql(u8, raw, "Sc")) return .currency_symbol;
    if (std.mem.eql(u8, raw, "Sk")) return .modifier_symbol;
    if (std.mem.eql(u8, raw, "So")) return .other_symbol;
    if (std.mem.eql(u8, raw, "Zs")) return .space_separator;
    if (std.mem.eql(u8, raw, "Zl")) return .line_separator;
    if (std.mem.eql(u8, raw, "Zp")) return .paragraph_separator;
    if (std.mem.eql(u8, raw, "Cc")) return .control;
    if (std.mem.eql(u8, raw, "Cf")) return .format;
    if (std.mem.eql(u8, raw, "Cs")) return .surrogate;
    if (std.mem.eql(u8, raw, "Co")) return .private_use;
    return .unassigned;
}

fn bidiFromUcd(raw: []const u8) unicode_data.BidiClass {
    if (std.mem.eql(u8, raw, "L")) return .left_to_right;
    if (std.mem.eql(u8, raw, "R")) return .right_to_left;
    if (std.mem.eql(u8, raw, "AL")) return .arabic_letter;
    if (std.mem.eql(u8, raw, "EN")) return .european_number;
    if (std.mem.eql(u8, raw, "ES")) return .european_separator;
    if (std.mem.eql(u8, raw, "ET")) return .european_terminator;
    if (std.mem.eql(u8, raw, "AN")) return .arabic_number;
    if (std.mem.eql(u8, raw, "CS")) return .common_separator;
    if (std.mem.eql(u8, raw, "NSM")) return .non_spacing_mark;
    if (std.mem.eql(u8, raw, "BN")) return .boundary_neutral;
    if (std.mem.eql(u8, raw, "B")) return .paragraph_separator;
    if (std.mem.eql(u8, raw, "S")) return .segment_separator;
    if (std.mem.eql(u8, raw, "WS")) return .whitespace;
    if (std.mem.eql(u8, raw, "ON")) return .other_neutral;
    if (std.mem.eql(u8, raw, "LRE")) return .left_to_right_embedding;
    if (std.mem.eql(u8, raw, "LRO")) return .left_to_right_override;
    if (std.mem.eql(u8, raw, "RLE")) return .right_to_left_embedding;
    if (std.mem.eql(u8, raw, "RLO")) return .right_to_left_override;
    if (std.mem.eql(u8, raw, "PDF")) return .pop_directional_format;
    if (std.mem.eql(u8, raw, "LRI")) return .left_to_right_isolate;
    if (std.mem.eql(u8, raw, "RLI")) return .right_to_left_isolate;
    if (std.mem.eql(u8, raw, "FSI")) return .first_strong_isolate;
    if (std.mem.eql(u8, raw, "PDI")) return .pop_directional_isolate;
    return .left_to_right;
}

fn simpleCaseMap(table: []const unicode_data.CaseMappingRangeEntry, cp: CodePoint) CodePoint {
    const range = utils.searchRange(
        unicode_data.CaseMappingRangeEntry,
        CodePoint,
        "start",
        "end",
        table,
        cp,
    ) orelse return cp;
    return @intCast(@as(i32, @intCast(cp)) + range.delta);
}

fn propertyFromDcpLabel(raw: []const u8) ?derived.Property {
    const label = std.mem.trim(u8, raw, " \t\r");
    if (std.mem.eql(u8, label, "Math")) return .math;
    if (std.mem.eql(u8, label, "Alphabetic")) return .alphabetic;
    if (std.mem.eql(u8, label, "Lowercase")) return .lowercase;
    if (std.mem.eql(u8, label, "Uppercase")) return .uppercase;
    if (std.mem.eql(u8, label, "Cased")) return .cased;
    if (std.mem.eql(u8, label, "Case_Ignorable")) return .case_ignorable;
    if (std.mem.eql(u8, label, "Changes_When_Lowercased")) return .changes_when_lowercased;
    if (std.mem.eql(u8, label, "Changes_When_Uppercased")) return .changes_when_uppercased;
    if (std.mem.eql(u8, label, "Changes_When_Titlecased")) return .changes_when_titlecased;
    if (std.mem.eql(u8, label, "Changes_When_Casefolded")) return .changes_when_casefolded;
    if (std.mem.eql(u8, label, "Changes_When_Casemapped")) return .changes_when_casemapped;
    if (std.mem.eql(u8, label, "ID_Start")) return .id_start;
    if (std.mem.eql(u8, label, "ID_Continue")) return .id_continue;
    if (std.mem.eql(u8, label, "XID_Start")) return .xid_start;
    if (std.mem.eql(u8, label, "XID_Continue")) return .xid_continue;
    if (std.mem.eql(u8, label, "Default_Ignorable_Code_Point")) return .default_ignorable_code_point;
    if (std.mem.eql(u8, label, "Grapheme_Extend")) return .grapheme_extend;
    if (std.mem.eql(u8, label, "Grapheme_Base")) return .grapheme_base;
    if (std.mem.eql(u8, label, "Grapheme_Link")) return .grapheme_link;
    if (std.mem.eql(u8, label, "InCB; Linker")) return .in_cb_linker;
    if (std.mem.eql(u8, label, "InCB; Consonant")) return .in_cb_consonant;
    if (std.mem.eql(u8, label, "InCB; Extend")) return .in_cb_extend;
    return null;
}

fn specialLocale(raw: []const u8) special_casing.Locale {
    if (std.mem.eql(u8, raw, "tr")) return .tr;
    if (std.mem.eql(u8, raw, "az")) return .az;
    if (std.mem.eql(u8, raw, "lt")) return .lt;
    return .none;
}

fn specialCondition(raw: []const u8) special_casing.Condition {
    if (std.mem.eql(u8, raw, "After_I")) return .after_i;
    if (std.mem.eql(u8, raw, "Not_Before_Dot")) return .not_before_dot;
    if (std.mem.eql(u8, raw, "After_Soft_Dotted")) return .after_soft_dotted;
    if (std.mem.eql(u8, raw, "More_Above")) return .more_above;
    if (std.mem.eql(u8, raw, "Final_Sigma")) return .final_sigma;
    return .none;
}

fn specialLookup(locale: special_casing.Locale, condition: special_casing.Condition, cp: CodePoint) ?special_casing.Mapping {
    return switch (locale) {
        .none => switch (condition) {
            .none => special_casing.lookup(.none, .none, cp),
            .after_i => special_casing.lookup(.none, .after_i, cp),
            .not_before_dot => special_casing.lookup(.none, .not_before_dot, cp),
            .after_soft_dotted => special_casing.lookup(.none, .after_soft_dotted, cp),
            .more_above => special_casing.lookup(.none, .more_above, cp),
            .final_sigma => special_casing.lookup(.none, .final_sigma, cp),
            else => null,
        },
        .tr => switch (condition) {
            .none => special_casing.lookup(.tr, .none, cp),
            .after_i => special_casing.lookup(.tr, .after_i, cp),
            .not_before_dot => special_casing.lookup(.tr, .not_before_dot, cp),
            .after_soft_dotted => special_casing.lookup(.tr, .after_soft_dotted, cp),
            .more_above => special_casing.lookup(.tr, .more_above, cp),
            .final_sigma => special_casing.lookup(.tr, .final_sigma, cp),
            else => null,
        },
        .az => switch (condition) {
            .none => special_casing.lookup(.az, .none, cp),
            .after_i => special_casing.lookup(.az, .after_i, cp),
            .not_before_dot => special_casing.lookup(.az, .not_before_dot, cp),
            .after_soft_dotted => special_casing.lookup(.az, .after_soft_dotted, cp),
            .more_above => special_casing.lookup(.az, .more_above, cp),
            .final_sigma => special_casing.lookup(.az, .final_sigma, cp),
            else => null,
        },
        .lt => switch (condition) {
            .none => special_casing.lookup(.lt, .none, cp),
            .after_i => special_casing.lookup(.lt, .after_i, cp),
            .not_before_dot => special_casing.lookup(.lt, .not_before_dot, cp),
            .after_soft_dotted => special_casing.lookup(.lt, .after_soft_dotted, cp),
            .more_above => special_casing.lookup(.lt, .more_above, cp),
            .final_sigma => special_casing.lookup(.lt, .final_sigma, cp),
            else => null,
        },
        else => null,
    };
}

test "ucd hostile: UnicodeData generated categories, bidi classes, combining classes, and simple case maps match every row and range" {
    const unicode_data_txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, unicode_data_path, testing.allocator, .limited(8 * 1024 * 1024));
    defer testing.allocator.free(unicode_data_txt);

    var pending_range_start: ?CodePoint = null;
    var pending_category: unicode_data.GeneralCategory = undefined;
    var pending_bidi: unicode_data.BidiClass = undefined;
    var pending_ccc: unicode_types.CanonicalCombiningClass = undefined;

    var lines = std.mem.splitScalar(u8, unicode_data_txt, '\n');
    while (lines.next()) |raw_line| {
        const line = cleanData(raw_line);
        if (line.len == 0) continue;

        var fields: [15][]const u8 = undefined;
        var field_count: usize = 0;
        var split = std.mem.splitScalar(u8, line, ';');
        while (split.next()) |field| {
            if (field_count == fields.len) break;
            fields[field_count] = std.mem.trim(u8, field, " \t\r");
            field_count += 1;
        }
        try testing.expectEqual(@as(usize, 15), field_count);

        const cp = try parseCodePoint(fields[0]);
        const name = fields[1];
        const category = categoryFromUcd(fields[2]);
        const ccc = unicode_types.CanonicalCombiningClass.fromU8(try std.fmt.parseInt(u8, fields[3], 10));
        const bidi = bidiFromUcd(fields[4]);

        if (std.mem.endsWith(u8, name, ", First>")) {
            pending_range_start = cp;
            pending_category = category;
            pending_bidi = bidi;
            pending_ccc = ccc;
            continue;
        }

        const start = pending_range_start orelse cp;
        const end = cp;
        if (pending_range_start != null) {
            try testing.expect(std.mem.endsWith(u8, name, ", Last>"));
            pending_range_start = null;
        }

        for (@as(usize, start)..@as(usize, end) + 1) |cp_usize| {
            const current: CodePoint = @intCast(cp_usize);
            try testing.expectEqual(if (start == cp) category else pending_category, unicode_data.generalCategory(current));
            try testing.expectEqual(if (start == cp) bidi else pending_bidi, unicode_data.bidiClass(current));
            try testing.expectEqual(if (start == cp) ccc else pending_ccc, lookupCombiningClass(current));
        }

        if (start == cp) {
            const upper = if (fields[12].len == 0) cp else try parseCodePoint(fields[12]);
            const lower = if (fields[13].len == 0) cp else try parseCodePoint(fields[13]);
            const title = if (fields[14].len == 0) cp else try parseCodePoint(fields[14]);
            try testing.expectEqual(upper, simpleCaseMap(&unicode_data.uppercase_range_mapping_table, cp));
            try testing.expectEqual(lower, simpleCaseMap(&unicode_data.lowercase_range_mapping_table, cp));
            try testing.expectEqual(title, simpleCaseMap(&unicode_data.titlecase_range_mapping_table, cp));
        }
    }
}

fn lookupCombiningClass(cp: CodePoint) unicode_types.CanonicalCombiningClass {
    return unicode_data.canonicalCombiningClass(cp);
}

test "ucd hostile: DerivedCoreProperties bitset matches every scalar, not just cute samples" {
    const allocator = testing.allocator;
    const derived_core_properties_txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, derived_core_properties_path, allocator, .limited(8 * 1024 * 1024));
    defer allocator.free(derived_core_properties_txt);

    const expected = try allocator.alloc(u32, 0x110000);
    defer allocator.free(expected);
    @memset(expected, 0);

    var lines = std.mem.splitScalar(u8, derived_core_properties_txt, '\n');
    while (lines.next()) |raw_line| {
        const line = cleanData(raw_line);
        if (line.len == 0) continue;

        var split = std.mem.splitSequence(u8, line, " ; ");
        const range = try parseRange(split.next() orelse return error.BadDerivedCorePropertiesLine);
        const property_label = split.next() orelse return error.BadDerivedCorePropertiesLine;
        const property = propertyFromDcpLabel(property_label) orelse return error.UnknownDerivedCoreProperty;
        const bit = @intFromEnum(property);

        for (@as(usize, range.start)..@as(usize, range.end) + 1) |cp_usize| {
            expected[cp_usize] |= bit;
        }
    }

    for (expected, 0..) |want, cp| {
        try testing.expectEqual(want, derived.propertyMask(@intCast(cp)));
    }
    try testing.expectEqual(@as(u32, 0), derived.propertyMask(0x110000));
}

test "ucd hostile: CaseFolding generated lookup obeys C/F/S/T rows and Turkic fallback is not broken" {
    const case_folding_txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, case_folding_path, testing.allocator, .limited(1024 * 1024));
    defer testing.allocator.free(case_folding_txt);

    var lines = std.mem.splitScalar(u8, case_folding_txt, '\n');
    while (lines.next()) |raw_line| {
        const line = cleanData(raw_line);
        if (line.len == 0) continue;

        var fields: [3][]const u8 = undefined;
        var field_count: usize = 0;
        var split = std.mem.splitScalar(u8, line, ';');
        while (split.next()) |field| {
            if (field_count == fields.len) break;
            fields[field_count] = std.mem.trim(u8, field, " \t\r");
            field_count += 1;
        }
        try testing.expectEqual(@as(usize, 3), field_count);

        const cp = try parseCodePoint(fields[0]);
        const status = fields[1];
        var expected_buf: [4]CodePoint = undefined;
        const expected = try parseCodePointList(fields[2], &expected_buf);

        if (std.mem.eql(u8, status, "C")) {
            try testing.expectEqual(expected[0], case_folding.lookup(.simple, .default, cp).?);
            try expectCodePointSlices(expected, case_folding.lookup(.full, .default, cp).?);
        } else if (std.mem.eql(u8, status, "S")) {
            try testing.expectEqual(expected[0], case_folding.lookup(.simple, .default, cp).?);
        } else if (std.mem.eql(u8, status, "F")) {
            try expectCodePointSlices(expected, case_folding.lookup(.full, .default, cp).?);
        } else if (std.mem.eql(u8, status, "T")) {
            try testing.expectEqual(expected[0], case_folding.lookup(.simple, .turkic, cp).?);
            try expectCodePointSlices(expected, case_folding.lookup(.full, .turkic, cp).?);
        } else {
            return error.UnknownCaseFoldingStatus;
        }
    }

    try testing.expectEqual(@as(CodePoint, 'a'), case_folding.lookup(.simple, .turkic, 'A').?);
    try testing.expectEqual(@as(?CodePoint, null), case_folding.lookup(.simple, .default, 'a'));
}

test "ucd hostile: SpecialCasing generated lookup matches every unconditional and supported conditional row" {
    const special_casing_txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, special_casing_path, testing.allocator, .limited(1024 * 1024));
    defer testing.allocator.free(special_casing_txt);

    var lines = std.mem.splitScalar(u8, special_casing_txt, '\n');
    while (lines.next()) |raw_line| {
        const line = cleanData(raw_line);
        if (line.len == 0) continue;

        var fields: [5][]const u8 = .{ "", "", "", "", "" };
        var field_count: usize = 0;
        var split = std.mem.splitScalar(u8, line, ';');
        while (split.next()) |field| {
            if (field_count == fields.len) break;
            fields[field_count] = std.mem.trim(u8, field, " \t\r");
            field_count += 1;
        }
        try testing.expect(field_count >= 4);

        const cp = try parseCodePoint(fields[0]);
        var lower_buf: [4]CodePoint = undefined;
        var title_buf: [4]CodePoint = undefined;
        var upper_buf: [4]CodePoint = undefined;
        const lower = try parseCodePointList(fields[1], &lower_buf);
        const title = try parseCodePointList(fields[2], &title_buf);
        const upper = try parseCodePointList(fields[3], &upper_buf);

        var locale: special_casing.Locale = .none;
        var condition: special_casing.Condition = .none;
        var condition_tokens = std.mem.splitScalar(u8, fields[4], ' ');
        while (condition_tokens.next()) |token| {
            if (token.len == 0) continue;
            const maybe_locale = specialLocale(token);
            if (maybe_locale != .none) {
                locale = maybe_locale;
            } else {
                condition = specialCondition(token);
            }
        }

        const mapping = specialLookup(locale, condition, cp) orelse return error.SpecialCasingMissingRow;
        try expectCodePointSlices(lower, mapping.lower);
        try expectCodePointSlices(title, mapping.title);
        try expectCodePointSlices(upper, mapping.upper);
    }

    try expectCodePointSlices(&.{0x131}, special_casing.lookup(.tr, .not_before_dot, 'I').?.lower);
    try expectCodePointSlices(&.{ 0x69, 0x307 }, special_casing.lookup(.none, .none, 0x130).?.lower);
    try expectCodePointSlices(&.{0x69}, special_casing.lookup(.tr, .none, 0x130).?.lower);
}

const PropListPredicate = struct {
    label: []const u8,
    predicate: *const fn (CodePoint) bool,
};

/// Bridge `inline fn (CodePoint) bool` predicates into normal function-pointer
/// targets so we can hold them in a table.
fn wrap(comptime f: fn (CodePoint) callconv(.@"inline") bool) *const fn (CodePoint) bool {
    const Wrapper = struct {
        fn call(cp: CodePoint) bool {
            return f(cp);
        }
    };
    return &Wrapper.call;
}

const prop_list_predicates = [_]PropListPredicate{
    .{ .label = "White_Space", .predicate = wrap(prop_list.isWhiteSpace) },
    .{ .label = "Bidi_Control", .predicate = wrap(prop_list.isBidiControl) },
    .{ .label = "Join_Control", .predicate = wrap(prop_list.isJoinControl) },
    .{ .label = "Dash", .predicate = wrap(prop_list.isDash) },
    .{ .label = "Hyphen", .predicate = wrap(prop_list.isHyphen) },
    .{ .label = "Quotation_Mark", .predicate = wrap(prop_list.isQuotationMark) },
    .{ .label = "Terminal_Punctuation", .predicate = wrap(prop_list.isTerminalPunctuation) },
    .{ .label = "Other_Math", .predicate = wrap(prop_list.isOtherMath) },
    .{ .label = "Hex_Digit", .predicate = wrap(prop_list.isHexDigit) },
    .{ .label = "ASCII_Hex_Digit", .predicate = wrap(prop_list.isAsciiHexDigit) },
    .{ .label = "Other_Alphabetic", .predicate = wrap(prop_list.isOtherAlphabetic) },
    .{ .label = "Ideographic", .predicate = wrap(prop_list.isIdeographic) },
    .{ .label = "Diacritic", .predicate = wrap(prop_list.isDiacritic) },
    .{ .label = "Extender", .predicate = wrap(prop_list.isExtender) },
    .{ .label = "Other_Lowercase", .predicate = wrap(prop_list.isOtherLowercase) },
    .{ .label = "Other_Uppercase", .predicate = wrap(prop_list.isOtherUppercase) },
    .{ .label = "Noncharacter_Code_Point", .predicate = wrap(prop_list.isNoncharacterCodePoint) },
    .{ .label = "Other_Grapheme_Extend", .predicate = wrap(prop_list.isOtherGraphemeExtend) },
    .{ .label = "IDS_Binary_Operator", .predicate = wrap(prop_list.isIdsBinaryOperator) },
    .{ .label = "IDS_Trinary_Operator", .predicate = wrap(prop_list.isIdsTrinaryOperator) },
    .{ .label = "IDS_Unary_Operator", .predicate = wrap(prop_list.isIdsUnaryOperator) },
    .{ .label = "Radical", .predicate = wrap(prop_list.isRadical) },
    .{ .label = "Unified_Ideograph", .predicate = wrap(prop_list.isUnifiedIdeograph) },
    .{ .label = "Other_Default_Ignorable_Code_Point", .predicate = wrap(prop_list.isOtherDefaultIgnorableCodePoint) },
    .{ .label = "Deprecated", .predicate = wrap(prop_list.isDeprecated) },
    .{ .label = "Soft_Dotted", .predicate = wrap(prop_list.isSoftDotted) },
    .{ .label = "Logical_Order_Exception", .predicate = wrap(prop_list.isLogicalOrderException) },
    .{ .label = "Other_ID_Start", .predicate = wrap(prop_list.isOtherIdStart) },
    .{ .label = "Other_ID_Continue", .predicate = wrap(prop_list.isOtherIdContinue) },
    .{ .label = "Sentence_Terminal", .predicate = wrap(prop_list.isSentenceTerminal) },
    .{ .label = "Variation_Selector", .predicate = wrap(prop_list.isVariationSelector) },
    .{ .label = "Pattern_White_Space", .predicate = wrap(prop_list.isPatternWhiteSpace) },
    .{ .label = "Pattern_Syntax", .predicate = wrap(prop_list.isPatternSyntax) },
    .{ .label = "Prepended_Concatenation_Mark", .predicate = wrap(prop_list.isPrependedConcatenationMark) },
    .{ .label = "Regional_Indicator", .predicate = wrap(prop_list.isRegionalIndicator) },
    .{ .label = "Modifier_Combining_Mark", .predicate = wrap(prop_list.isModifierCombiningMark) },
    .{ .label = "ID_Compat_Math_Start", .predicate = wrap(prop_list.isIdCompatMathStart) },
    .{ .label = "ID_Compat_Math_Continue", .predicate = wrap(prop_list.isIdCompatMathContinue) },
};

fn predicateForPropListLabel(label: []const u8) ?*const fn (CodePoint) bool {
    for (prop_list_predicates) |entry| {
        if (std.mem.eql(u8, label, entry.label)) return entry.predicate;
    }
    return null;
}

test "ucd hostile: every PropList property predicate matches every codepoint" {
    const allocator = testing.allocator;
    const txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, prop_list_path, allocator, .limited(8 * 1024 * 1024));
    defer allocator.free(txt);

    var groups: std.StringHashMapUnmanaged(std.ArrayListUnmanaged(struct { start: CodePoint, end: CodePoint })) = .empty;
    defer {
        var it_free = groups.iterator();
        while (it_free.next()) |e| {
            e.value_ptr.deinit(allocator);
            allocator.free(e.key_ptr.*);
        }
        groups.deinit(allocator);
    }

    var lines = std.mem.splitScalar(u8, txt, '\n');
    while (lines.next()) |raw_line| {
        const line = cleanData(raw_line);
        if (line.len == 0) continue;

        // PropList.txt is mostly "RANGE    ; LABEL" but at least one line
        // omits the space before the semicolon — split on the scalar to be
        // robust to either layout.
        var parts = std.mem.splitScalar(u8, line, ';');
        const range = try parseRange(parts.next() orelse return error.BadPropListLine);
        const label = std.mem.trim(u8, parts.next() orelse return error.BadPropListLine, " \t\r");

        const gop = try groups.getOrPut(allocator, label);
        if (!gop.found_existing) {
            gop.key_ptr.* = try allocator.dupe(u8, label);
            gop.value_ptr.* = .empty;
        }
        try gop.value_ptr.append(allocator, .{ .start = range.start, .end = range.end });
    }

    const dense = try allocator.alloc(bool, 0x110000);
    defer allocator.free(dense);

    // Track which property labels we've actually exercised so we catch
    // generator-side drops (label in file but no predicate emitted).
    var seen = std.StringHashMapUnmanaged(void).empty;
    defer seen.deinit(allocator);

    var it = groups.iterator();
    while (it.next()) |entry| {
        const label = entry.key_ptr.*;
        const predicate = predicateForPropListLabel(label) orelse {
            std.debug.print("unknown PropList label: '{s}'\n", .{label});
            return error.UnknownPropListLabel;
        };

        @memset(dense, false);
        for (entry.value_ptr.items) |r| {
            for (@as(usize, r.start)..@as(usize, r.end) + 1) |cp| {
                dense[cp] = true;
            }
        }

        for (dense, 0..) |want, cp_usize| {
            const cp: CodePoint = @intCast(cp_usize);
            try testing.expectEqual(want, predicate(cp));
        }

        // Above 0x10FFFF must always be false (predicate's u21 guard).
        try testing.expectEqual(false, predicate(0x10FFFF) and !dense[0x10FFFF]);
        try seen.put(allocator, label, {});
    }

    // Every predicate we emit must correspond to a label present in the
    // file — guards against the table going stale relative to the data.
    for (prop_list_predicates) |entry| {
        if (!seen.contains(entry.label)) {
            std.debug.print("predicate '{s}' has no rows in PropList.txt\n", .{entry.label});
            return error.PredicateMissingFromPropList;
        }
    }
}

fn graphemeBreakFromUcd(raw: []const u8) ?grapheme_break.GraphemeBreakProperty {
    const label = std.mem.trim(u8, raw, " \t\r");
    if (std.mem.eql(u8, label, "CR")) return .cr;
    if (std.mem.eql(u8, label, "LF")) return .lf;
    if (std.mem.eql(u8, label, "Control")) return .control;
    if (std.mem.eql(u8, label, "Extend")) return .extend;
    if (std.mem.eql(u8, label, "ZWJ")) return .zwj;
    if (std.mem.eql(u8, label, "Regional_Indicator")) return .regional_indicator;
    if (std.mem.eql(u8, label, "Prepend")) return .prepend;
    if (std.mem.eql(u8, label, "SpacingMark")) return .spacing_mark;
    if (std.mem.eql(u8, label, "L")) return .l;
    if (std.mem.eql(u8, label, "V")) return .v;
    if (std.mem.eql(u8, label, "T")) return .t;
    if (std.mem.eql(u8, label, "LV")) return .lv;
    if (std.mem.eql(u8, label, "LVT")) return .lvt;
    return null;
}

test "ucd hostile: GraphemeBreakProperty.txt assigns the same property to every codepoint as the generated table" {
    const allocator = testing.allocator;
    const txt = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        grapheme_break_property_path,
        allocator,
        .limited(1024 * 1024),
    );
    defer allocator.free(txt);

    // Default is .none ("Other" / XX) for every codepoint not explicitly listed.
    const expected = try allocator.alloc(grapheme_break.GraphemeBreakProperty, 0x110000);
    defer allocator.free(expected);
    @memset(expected, .none);

    var lines = std.mem.splitScalar(u8, txt, '\n');
    while (lines.next()) |raw_line| {
        const line = cleanData(raw_line);
        if (line.len == 0) continue;

        var parts = std.mem.splitScalar(u8, line, ';');
        const range = try parseRange(parts.next() orelse return error.BadGraphemeBreakLine);
        const label_raw = parts.next() orelse return error.BadGraphemeBreakLine;
        const prop = graphemeBreakFromUcd(label_raw) orelse {
            std.debug.print("unknown GraphemeBreakProperty label: '{s}'\n", .{std.mem.trim(u8, label_raw, " \t\r")});
            return error.UnknownGraphemeBreakLabel;
        };

        for (@as(usize, range.start)..@as(usize, range.end) + 1) |cp_usize| {
            expected[cp_usize] = prop;
        }
    }

    for (expected, 0..) |want, cp| {
        try testing.expectEqual(want, grapheme_break.graphemeBreakProperty(@intCast(cp)));
    }

    // Above 0x10FFFF the generated lookup must still return .none.
    try testing.expectEqual(grapheme_break.GraphemeBreakProperty.none, grapheme_break.graphemeBreakProperty(0x110000));
    try testing.expectEqual(grapheme_break.GraphemeBreakProperty.none, grapheme_break.graphemeBreakProperty(0x1FFFFF));
}

// ÷ U+00F7 — UTF-8 0xC3 0xB7 — break opportunity in GraphemeBreakTest.txt.
const grapheme_break_marker = "\xC3\xB7";
// × U+00D7 — UTF-8 0xC3 0x97 — no break.
const grapheme_no_break_marker = "\xC3\x97";

const ParsedGraphemeLine = struct {
    code_points: []CodePoint,
    boundaries: []bool,

    fn deinit(self: *ParsedGraphemeLine, allocator: std.mem.Allocator) void {
        allocator.free(self.code_points);
        allocator.free(self.boundaries);
    }
};

fn parseGraphemeTestLine(allocator: std.mem.Allocator, data_part: []const u8) !ParsedGraphemeLine {
    var code_points: std.ArrayList(CodePoint) = .empty;
    errdefer code_points.deinit(allocator);
    var boundaries: std.ArrayList(bool) = .empty;
    errdefer boundaries.deinit(allocator);

    var tokens = std.mem.tokenizeAny(u8, data_part, " \t");
    while (tokens.next()) |tok| {
        if (std.mem.eql(u8, tok, grapheme_break_marker)) {
            try boundaries.append(allocator, true);
        } else if (std.mem.eql(u8, tok, grapheme_no_break_marker)) {
            try boundaries.append(allocator, false);
        } else {
            const cp = try std.fmt.parseInt(CodePoint, tok, 16);
            try code_points.append(allocator, cp);
        }
    }

    return .{
        .code_points = try code_points.toOwnedSlice(allocator),
        .boundaries = try boundaries.toOwnedSlice(allocator),
    };
}

fn computeGraphemeBoundaries(allocator: std.mem.Allocator, code_points: []const CodePoint) ![]bool {
    const out = try allocator.alloc(bool, code_points.len + 1);
    errdefer allocator.free(out);

    @memset(out, true); // sot at [0] and eot at [len] are always breaks.
    var state: segmentation.BoundaryState = .{};
    for (code_points, 0..) |cp, i| {
        const decision = segmentation.checkBoundary(state, cp);
        if (i > 0) out[i] = decision.should_break;
        state = decision.new_state;
    }
    return out;
}

test "ucd hostile: GraphemeBreakTest.txt full conformance (including GB11 Extended_Pictographic)" {
    const allocator = testing.allocator;
    const text = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        grapheme_break_test_path,
        allocator,
        .limited(4 * 1024 * 1024),
    );
    defer allocator.free(text);

    var lines = std.mem.splitScalar(u8, text, '\n');
    var line_no: usize = 0;
    var tested: usize = 0;
    while (lines.next()) |raw_line| {
        line_no += 1;
        const trimmed = std.mem.trim(u8, raw_line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        const hash_idx = std.mem.indexOfScalar(u8, trimmed, '#') orelse trimmed.len;
        const data_part = std.mem.trim(u8, trimmed[0..hash_idx], " \t");
        const comment = if (hash_idx < trimmed.len) trimmed[hash_idx + 1 ..] else "";

        var parsed = try parseGraphemeTestLine(allocator, data_part);
        defer parsed.deinit(allocator);

        try testing.expectEqual(parsed.code_points.len + 1, parsed.boundaries.len);

        const actual = try computeGraphemeBoundaries(allocator, parsed.code_points);
        defer allocator.free(actual);

        for (parsed.boundaries, actual, 0..) |want, got, i| {
            if (want != got) {
                std.debug.print(
                    "GraphemeBreakTest.txt line {d}: boundary index {d} expected {} got {}\n  data: {s}\n  comment: {s}\n",
                    .{ line_no, i, want, got, data_part, comment },
                );
                return error.GraphemeBreakBoundaryMismatch;
            }
        }
        tested += 1;
    }

    try testing.expect(tested > 0);
}

test "ucd: parseGraphemeTestLine round-trips a representative line" {
    const allocator = testing.allocator;
    const data = grapheme_break_marker ++ " 000D " ++ grapheme_no_break_marker ++ " 000A " ++ grapheme_break_marker;
    var parsed = try parseGraphemeTestLine(allocator, data);
    defer parsed.deinit(allocator);
    try testing.expectEqual(@as(usize, 2), parsed.code_points.len);
    try testing.expectEqual(@as(CodePoint, 0x000D), parsed.code_points[0]);
    try testing.expectEqual(@as(CodePoint, 0x000A), parsed.code_points[1]);
    try testing.expectEqualSlices(bool, &.{ true, false, true }, parsed.boundaries);
}

test "ucd: computeGraphemeBoundaries on a trivial CR LF sequence" {
    const allocator = testing.allocator;
    const cps = [_]CodePoint{ 0x000D, 0x000A };
    const got = try computeGraphemeBoundaries(allocator, &cps);
    defer allocator.free(got);
    try testing.expectEqualSlices(bool, &.{ true, false, true }, got);
}

// ============================================================================
// Conformance for the Tier 1 generators added in this session.
// Each one walks the UCD source file, builds an expected dense array across
// every scalar, and verifies the generated lookup matches everywhere.
// ============================================================================

fn wordBreakFromUcd(raw: []const u8) ?word_break.WordBreakProperty {
    const label = std.mem.trim(u8, raw, " \t\r");
    if (std.mem.eql(u8, label, "Other")) return .other;
    if (std.mem.eql(u8, label, "ALetter")) return .aletter;
    if (std.mem.eql(u8, label, "CR")) return .cr;
    if (std.mem.eql(u8, label, "Double_Quote")) return .double_quote;
    if (std.mem.eql(u8, label, "Extend")) return .extend;
    if (std.mem.eql(u8, label, "ExtendNumLet")) return .extend_num_let;
    if (std.mem.eql(u8, label, "Format")) return .format;
    if (std.mem.eql(u8, label, "Hebrew_Letter")) return .hebrew_letter;
    if (std.mem.eql(u8, label, "Katakana")) return .katakana;
    if (std.mem.eql(u8, label, "LF")) return .lf;
    if (std.mem.eql(u8, label, "MidLetter")) return .mid_letter;
    if (std.mem.eql(u8, label, "MidNum")) return .mid_num;
    if (std.mem.eql(u8, label, "MidNumLet")) return .mid_num_let;
    if (std.mem.eql(u8, label, "Newline")) return .newline;
    if (std.mem.eql(u8, label, "Numeric")) return .numeric;
    if (std.mem.eql(u8, label, "Regional_Indicator")) return .regional_indicator;
    if (std.mem.eql(u8, label, "Single_Quote")) return .single_quote;
    if (std.mem.eql(u8, label, "WSegSpace")) return .wseg_space;
    if (std.mem.eql(u8, label, "ZWJ")) return .zwj;
    return null;
}

test "ucd hostile: WordBreakProperty.txt assigns the same property to every codepoint" {
    const allocator = testing.allocator;
    const txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, word_break_property_path, allocator, .limited(2 * 1024 * 1024));
    defer allocator.free(txt);

    const expected = try allocator.alloc(word_break.WordBreakProperty, 0x110000);
    defer allocator.free(expected);
    @memset(expected, .other);

    var lines = std.mem.splitScalar(u8, txt, '\n');
    while (lines.next()) |raw_line| {
        const line = cleanData(raw_line);
        if (line.len == 0) continue;
        var parts = std.mem.splitScalar(u8, line, ';');
        const range = try parseRange(parts.next() orelse return error.BadWordBreakLine);
        const label = parts.next() orelse return error.BadWordBreakLine;
        const prop = wordBreakFromUcd(label) orelse {
            std.debug.print("unknown WordBreakProperty label: '{s}'\n", .{std.mem.trim(u8, label, " \t\r")});
            return error.UnknownWordBreakLabel;
        };
        for (@as(usize, range.start)..@as(usize, range.end) + 1) |cp| expected[cp] = prop;
    }

    for (expected, 0..) |want, cp| {
        try testing.expectEqual(want, word_break.wordBreakProperty(@intCast(cp)));
    }
    try testing.expectEqual(word_break.WordBreakProperty.other, word_break.wordBreakProperty(0x110000));
}

fn sentenceBreakFromUcd(raw: []const u8) ?sentence_break.SentenceBreakProperty {
    const label = std.mem.trim(u8, raw, " \t\r");
    if (std.mem.eql(u8, label, "Other")) return .other;
    if (std.mem.eql(u8, label, "ATerm")) return .aterm;
    if (std.mem.eql(u8, label, "Close")) return .close;
    if (std.mem.eql(u8, label, "CR")) return .cr;
    if (std.mem.eql(u8, label, "Extend")) return .extend;
    if (std.mem.eql(u8, label, "Format")) return .format;
    if (std.mem.eql(u8, label, "LF")) return .lf;
    if (std.mem.eql(u8, label, "Lower")) return .lower;
    if (std.mem.eql(u8, label, "Numeric")) return .numeric;
    if (std.mem.eql(u8, label, "OLetter")) return .oletter;
    if (std.mem.eql(u8, label, "SContinue")) return .scontinue;
    if (std.mem.eql(u8, label, "Sep")) return .sep;
    if (std.mem.eql(u8, label, "Sp")) return .sp;
    if (std.mem.eql(u8, label, "STerm")) return .sterm;
    if (std.mem.eql(u8, label, "Upper")) return .upper;
    return null;
}

test "ucd hostile: SentenceBreakProperty.txt assigns the same property to every codepoint" {
    const allocator = testing.allocator;
    const txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, sentence_break_property_path, allocator, .limited(2 * 1024 * 1024));
    defer allocator.free(txt);

    const expected = try allocator.alloc(sentence_break.SentenceBreakProperty, 0x110000);
    defer allocator.free(expected);
    @memset(expected, .other);

    var lines = std.mem.splitScalar(u8, txt, '\n');
    while (lines.next()) |raw_line| {
        const line = cleanData(raw_line);
        if (line.len == 0) continue;
        var parts = std.mem.splitScalar(u8, line, ';');
        const range = try parseRange(parts.next() orelse return error.BadSentenceBreakLine);
        const label = parts.next() orelse return error.BadSentenceBreakLine;
        const prop = sentenceBreakFromUcd(label) orelse {
            std.debug.print("unknown SentenceBreakProperty label: '{s}'\n", .{std.mem.trim(u8, label, " \t\r")});
            return error.UnknownSentenceBreakLabel;
        };
        for (@as(usize, range.start)..@as(usize, range.end) + 1) |cp| expected[cp] = prop;
    }

    for (expected, 0..) |want, cp| {
        try testing.expectEqual(want, sentence_break.sentenceBreakProperty(@intCast(cp)));
    }
    try testing.expectEqual(sentence_break.SentenceBreakProperty.other, sentence_break.sentenceBreakProperty(0x110000));
}

fn lineBreakFromUcd(raw: []const u8) ?line_break.LineBreak {
    const label = std.mem.trim(u8, raw, " \t\r");
    if (std.mem.eql(u8, label, "XX")) return .xx;
    if (std.mem.eql(u8, label, "AI")) return .ai;
    if (std.mem.eql(u8, label, "AK")) return .ak;
    if (std.mem.eql(u8, label, "AL")) return .al;
    if (std.mem.eql(u8, label, "AP")) return .ap;
    if (std.mem.eql(u8, label, "AS")) return .as;
    if (std.mem.eql(u8, label, "B2")) return .b2;
    if (std.mem.eql(u8, label, "BA")) return .ba;
    if (std.mem.eql(u8, label, "BB")) return .bb;
    if (std.mem.eql(u8, label, "BK")) return .bk;
    if (std.mem.eql(u8, label, "CB")) return .cb;
    if (std.mem.eql(u8, label, "CJ")) return .cj;
    if (std.mem.eql(u8, label, "CL")) return .cl;
    if (std.mem.eql(u8, label, "CM")) return .cm;
    if (std.mem.eql(u8, label, "CP")) return .cp;
    if (std.mem.eql(u8, label, "CR")) return .cr;
    if (std.mem.eql(u8, label, "EB")) return .eb;
    if (std.mem.eql(u8, label, "EM")) return .em;
    if (std.mem.eql(u8, label, "EX")) return .ex;
    if (std.mem.eql(u8, label, "GL")) return .gl;
    if (std.mem.eql(u8, label, "H2")) return .h2;
    if (std.mem.eql(u8, label, "H3")) return .h3;
    if (std.mem.eql(u8, label, "HH")) return .hh;
    if (std.mem.eql(u8, label, "HL")) return .hl;
    if (std.mem.eql(u8, label, "HY")) return .hy;
    if (std.mem.eql(u8, label, "ID")) return .id;
    if (std.mem.eql(u8, label, "IN")) return .in;
    if (std.mem.eql(u8, label, "IS")) return .is;
    if (std.mem.eql(u8, label, "JL")) return .jl;
    if (std.mem.eql(u8, label, "JT")) return .jt;
    if (std.mem.eql(u8, label, "JV")) return .jv;
    if (std.mem.eql(u8, label, "LF")) return .lf;
    if (std.mem.eql(u8, label, "NL")) return .nl;
    if (std.mem.eql(u8, label, "NS")) return .ns;
    if (std.mem.eql(u8, label, "NU")) return .nu;
    if (std.mem.eql(u8, label, "OP")) return .op;
    if (std.mem.eql(u8, label, "PO")) return .po;
    if (std.mem.eql(u8, label, "PR")) return .pr;
    if (std.mem.eql(u8, label, "QU")) return .qu;
    if (std.mem.eql(u8, label, "RI")) return .ri;
    if (std.mem.eql(u8, label, "SA")) return .sa;
    if (std.mem.eql(u8, label, "SG")) return .sg;
    if (std.mem.eql(u8, label, "SP")) return .sp;
    if (std.mem.eql(u8, label, "SY")) return .sy;
    if (std.mem.eql(u8, label, "VF")) return .vf;
    if (std.mem.eql(u8, label, "VI")) return .vi;
    if (std.mem.eql(u8, label, "WJ")) return .wj;
    if (std.mem.eql(u8, label, "ZW")) return .zw;
    if (std.mem.eql(u8, label, "ZWJ")) return .zwj;
    return null;
}

test "ucd hostile: LineBreak.txt assigns the same property to every codepoint" {
    const allocator = testing.allocator;
    const txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, line_break_path, allocator, .limited(4 * 1024 * 1024));
    defer allocator.free(txt);

    const expected = try allocator.alloc(line_break.LineBreak, 0x110000);
    defer allocator.free(expected);
    @memset(expected, .xx);

    var lines = std.mem.splitScalar(u8, txt, '\n');
    while (lines.next()) |raw_line| {
        const line = cleanData(raw_line);
        if (line.len == 0) continue;
        var parts = std.mem.splitScalar(u8, line, ';');
        const range = try parseRange(parts.next() orelse return error.BadLineBreakLine);
        const label = parts.next() orelse return error.BadLineBreakLine;
        const prop = lineBreakFromUcd(label) orelse {
            std.debug.print("unknown LineBreak label: '{s}'\n", .{std.mem.trim(u8, label, " \t\r")});
            return error.UnknownLineBreakLabel;
        };
        for (@as(usize, range.start)..@as(usize, range.end) + 1) |cp| expected[cp] = prop;
    }

    for (expected, 0..) |want, cp| {
        try testing.expectEqual(want, line_break.lineBreak(@intCast(cp)));
    }
    try testing.expectEqual(line_break.LineBreak.xx, line_break.lineBreak(0x110000));
}

fn eastAsianWidthFromUcd(raw: []const u8) ?east_asian_width.EastAsianWidth {
    const label = std.mem.trim(u8, raw, " \t\r");
    if (std.mem.eql(u8, label, "N")) return .n;
    if (std.mem.eql(u8, label, "A")) return .a;
    if (std.mem.eql(u8, label, "F")) return .f;
    if (std.mem.eql(u8, label, "H")) return .h;
    if (std.mem.eql(u8, label, "Na")) return .na;
    if (std.mem.eql(u8, label, "W")) return .w;
    return null;
}

test "ucd hostile: EastAsianWidth.txt assigns the same property to every codepoint" {
    const allocator = testing.allocator;
    const txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, east_asian_width_path, allocator, .limited(2 * 1024 * 1024));
    defer allocator.free(txt);

    const expected = try allocator.alloc(east_asian_width.EastAsianWidth, 0x110000);
    defer allocator.free(expected);
    @memset(expected, .n);

    var lines = std.mem.splitScalar(u8, txt, '\n');
    while (lines.next()) |raw_line| {
        const line = cleanData(raw_line);
        if (line.len == 0) continue;
        var parts = std.mem.splitScalar(u8, line, ';');
        const range = try parseRange(parts.next() orelse return error.BadEastAsianWidthLine);
        const label = parts.next() orelse return error.BadEastAsianWidthLine;
        const prop = eastAsianWidthFromUcd(label) orelse {
            std.debug.print("unknown EastAsianWidth label: '{s}'\n", .{std.mem.trim(u8, label, " \t\r")});
            return error.UnknownEastAsianWidthLabel;
        };
        for (@as(usize, range.start)..@as(usize, range.end) + 1) |cp| expected[cp] = prop;
    }

    for (expected, 0..) |want, cp| {
        try testing.expectEqual(want, east_asian_width.eastAsianWidth(@intCast(cp)));
    }
    try testing.expectEqual(east_asian_width.EastAsianWidth.n, east_asian_width.eastAsianWidth(0x110000));
}

const EmojiPredicate = struct {
    label: []const u8,
    predicate: *const fn (CodePoint) bool,
};

fn wrapEmoji(comptime f: fn (CodePoint) callconv(.@"inline") bool) *const fn (CodePoint) bool {
    const Wrapper = struct {
        fn call(cp: CodePoint) bool {
            return f(cp);
        }
    };
    return &Wrapper.call;
}

const emoji_predicates = [_]EmojiPredicate{
    .{ .label = "Emoji", .predicate = wrapEmoji(emoji_data.isEmoji) },
    .{ .label = "Emoji_Presentation", .predicate = wrapEmoji(emoji_data.isEmojiPresentation) },
    .{ .label = "Emoji_Modifier", .predicate = wrapEmoji(emoji_data.isEmojiModifier) },
    .{ .label = "Emoji_Modifier_Base", .predicate = wrapEmoji(emoji_data.isEmojiModifierBase) },
    .{ .label = "Emoji_Component", .predicate = wrapEmoji(emoji_data.isEmojiComponent) },
    .{ .label = "Extended_Pictographic", .predicate = wrapEmoji(emoji_data.isExtendedPictographic) },
};

fn predicateForEmojiLabel(label: []const u8) ?*const fn (CodePoint) bool {
    for (emoji_predicates) |entry| {
        if (std.mem.eql(u8, label, entry.label)) return entry.predicate;
    }
    return null;
}

test "ucd hostile: every emoji-data property predicate matches every codepoint" {
    const allocator = testing.allocator;
    const txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, emoji_data_path, allocator, .limited(1024 * 1024));
    defer allocator.free(txt);

    var groups: std.StringHashMapUnmanaged(std.ArrayListUnmanaged(struct { start: CodePoint, end: CodePoint })) = .empty;
    defer {
        var it_free = groups.iterator();
        while (it_free.next()) |e| {
            e.value_ptr.deinit(allocator);
            allocator.free(e.key_ptr.*);
        }
        groups.deinit(allocator);
    }

    var lines = std.mem.splitScalar(u8, txt, '\n');
    while (lines.next()) |raw_line| {
        const line = cleanData(raw_line);
        if (line.len == 0) continue;

        var parts = std.mem.splitScalar(u8, line, ';');
        const range = try parseRange(parts.next() orelse return error.BadEmojiDataLine);
        const label = std.mem.trim(u8, parts.next() orelse return error.BadEmojiDataLine, " \t\r");

        const gop = try groups.getOrPut(allocator, label);
        if (!gop.found_existing) {
            gop.key_ptr.* = try allocator.dupe(u8, label);
            gop.value_ptr.* = .empty;
        }
        try gop.value_ptr.append(allocator, .{ .start = range.start, .end = range.end });
    }

    const dense = try allocator.alloc(bool, 0x110000);
    defer allocator.free(dense);

    var seen = std.StringHashMapUnmanaged(void).empty;
    defer seen.deinit(allocator);

    var it = groups.iterator();
    while (it.next()) |entry| {
        const label = entry.key_ptr.*;
        const predicate = predicateForEmojiLabel(label) orelse {
            std.debug.print("unknown emoji-data label: '{s}'\n", .{label});
            return error.UnknownEmojiDataLabel;
        };

        @memset(dense, false);
        for (entry.value_ptr.items) |r| {
            for (@as(usize, r.start)..@as(usize, r.end) + 1) |cp| dense[cp] = true;
        }

        for (dense, 0..) |want, cp_usize| {
            const cp: CodePoint = @intCast(cp_usize);
            try testing.expectEqual(want, predicate(cp));
        }

        try seen.put(allocator, label, {});
    }

    // All six predicates we emit must correspond to a label in the file.
    for (emoji_predicates) |entry| {
        if (!seen.contains(entry.label)) {
            std.debug.print("emoji predicate '{s}' has no rows in emoji-data.txt\n", .{entry.label});
            return error.EmojiPredicateMissingFromFile;
        }
    }
}

// ============================================================================
// UAX #29 / UAX #14 segmentation conformance — WordBreakTest, SentenceBreakTest,
// LineBreakTest.
// ============================================================================

// ÷ U+00F7 — UTF-8 0xC3 0xB7 — break opportunity.
const break_marker = "\xC3\xB7";
// × U+00D7 — UTF-8 0xC3 0x97 — no break.
const no_break_marker = "\xC3\x97";

const ParsedSegmentationLine = struct {
    code_points: []CodePoint,
    boundaries: []bool,

    fn deinit(self: *ParsedSegmentationLine, allocator: std.mem.Allocator) void {
        allocator.free(self.code_points);
        allocator.free(self.boundaries);
    }
};

/// Parse one row of a UCD break-test file. The format alternates boundary
/// markers and hexadecimal code points, with whitespace as the only delimiter.
fn parseSegmentationLine(allocator: std.mem.Allocator, data_part: []const u8) !ParsedSegmentationLine {
    var code_points: std.ArrayList(CodePoint) = .empty;
    errdefer code_points.deinit(allocator);
    var boundaries: std.ArrayList(bool) = .empty;
    errdefer boundaries.deinit(allocator);

    var tokens = std.mem.tokenizeAny(u8, data_part, " \t");
    while (tokens.next()) |tok| {
        if (std.mem.eql(u8, tok, break_marker)) {
            try boundaries.append(allocator, true);
        } else if (std.mem.eql(u8, tok, no_break_marker)) {
            try boundaries.append(allocator, false);
        } else {
            const cp = try std.fmt.parseInt(CodePoint, tok, 16);
            try code_points.append(allocator, cp);
        }
    }

    return .{
        .code_points = try code_points.toOwnedSlice(allocator),
        .boundaries = try boundaries.toOwnedSlice(allocator),
    };
}

const SegmentationKind = enum { word, sentence, line };

fn runSegmentationConformance(
    allocator: std.mem.Allocator,
    text: []const u8,
    kind: SegmentationKind,
) !void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    var line_no: usize = 0;
    var tested: usize = 0;
    while (lines.next()) |raw_line| {
        line_no += 1;
        const trimmed = std.mem.trim(u8, raw_line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        const hash_idx = std.mem.indexOfScalar(u8, trimmed, '#') orelse trimmed.len;
        const data_part = std.mem.trim(u8, trimmed[0..hash_idx], " \t");
        const comment = if (hash_idx < trimmed.len) trimmed[hash_idx + 1 ..] else "";

        var parsed = try parseSegmentationLine(allocator, data_part);
        defer parsed.deinit(allocator);

        try testing.expectEqual(parsed.code_points.len + 1, parsed.boundaries.len);

        // LineBreakTest.txt only marks ÷ vs ×; mandatory and opportunity
        // both encode as ÷ (true). Flatten the line-break enum back to a
        // boolean here so the conformance loop stays uniform across kinds.
        const actual: []bool = switch (kind) {
            .word => try segmentation.computeWordBoundaries(allocator, parsed.code_points),
            .sentence => try segmentation.computeSentenceBoundaries(allocator, parsed.code_points),
            .line => blk: {
                const kinds = try segmentation.computeLineBoundaries(allocator, parsed.code_points);
                defer allocator.free(kinds);
                const flattened = try allocator.alloc(bool, kinds.len);
                for (kinds, flattened) |k, *out| out.* = (k != .prohibited);
                break :blk flattened;
            },
        };
        defer allocator.free(actual);

        for (parsed.boundaries, actual, 0..) |want, got, i| {
            if (want != got) {
                const tag = switch (kind) {
                    .word => "WordBreakTest.txt",
                    .sentence => "SentenceBreakTest.txt",
                    .line => "LineBreakTest.txt",
                };
                std.debug.print(
                    "{s} line {d}: boundary index {d} expected {} got {}\n  data: {s}\n  comment: {s}\n",
                    .{ tag, line_no, i, want, got, data_part, comment },
                );
                return switch (kind) {
                    .word => error.WordBreakBoundaryMismatch,
                    .sentence => error.SentenceBreakBoundaryMismatch,
                    .line => error.LineBreakBoundaryMismatch,
                };
            }
        }
        tested += 1;
    }

    try testing.expect(tested > 0);
}

test "ucd hostile: WordBreakTest.txt full conformance (all rules WB1..WB999)" {
    const allocator = testing.allocator;
    const text = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        word_break_test_path,
        allocator,
        .limited(4 * 1024 * 1024),
    );
    defer allocator.free(text);
    try runSegmentationConformance(allocator, text, .word);
}

test "ucd hostile: SentenceBreakTest.txt full conformance (all rules SB1..SB999)" {
    const allocator = testing.allocator;
    const text = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        sentence_break_test_path,
        allocator,
        .limited(4 * 1024 * 1024),
    );
    defer allocator.free(text);
    try runSegmentationConformance(allocator, text, .sentence);
}

test "ucd hostile: LineBreakTest.txt full conformance (UAX #14 LB1..LB31)" {
    const allocator = testing.allocator;
    const text = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        line_break_test_path,
        allocator,
        .limited(8 * 1024 * 1024),
    );
    defer allocator.free(text);
    try runSegmentationConformance(allocator, text, .line);
}

test "ucd: parseSegmentationLine roundtrips a representative line" {
    const allocator = testing.allocator;
    const data = break_marker ++ " 000D " ++ no_break_marker ++ " 000A " ++ break_marker;
    var parsed = try parseSegmentationLine(allocator, data);
    defer parsed.deinit(allocator);
    try testing.expectEqual(@as(usize, 2), parsed.code_points.len);
    try testing.expectEqual(@as(CodePoint, 0x000D), parsed.code_points[0]);
    try testing.expectEqual(@as(CodePoint, 0x000A), parsed.code_points[1]);
    try testing.expectEqualSlices(bool, &.{ true, false, true }, parsed.boundaries);
}

// ============================================================================
// DerivedNormalizationProps.txt + NormalizationTest.txt conformance
// ============================================================================

fn quickCheckFromUcd(raw: []const u8) ?dnp.QuickCheck {
    const t = std.mem.trim(u8, raw, " \t\r");
    if (t.len == 1) switch (t[0]) {
        'Y' => return .yes,
        'N' => return .no,
        'M' => return .maybe,
        else => {},
    };
    return null;
}

// Re-parse DerivedNormalizationProps.txt into dense expected arrays and
// verify every codepoint matches the generated lookup. Combines all 13
// properties into one walk to avoid 13 separate file reads.
test "ucd hostile: DerivedNormalizationProps full conformance — every property at every codepoint" {
    const allocator = testing.allocator;

    var arena_state: std.heap.ArenaAllocator = .init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, derived_normalization_props_path, allocator, .limited(8 * 1024 * 1024));
    defer allocator.free(txt);

    // Boolean expected arrays.
    const expected_fce = try arena.alloc(bool, 0x110000);
    const expected_exp_nfd = try arena.alloc(bool, 0x110000);
    const expected_exp_nfc = try arena.alloc(bool, 0x110000);
    const expected_exp_nfkd = try arena.alloc(bool, 0x110000);
    const expected_exp_nfkc = try arena.alloc(bool, 0x110000);
    const expected_cwkcf = try arena.alloc(bool, 0x110000);
    @memset(expected_fce, false);
    @memset(expected_exp_nfd, false);
    @memset(expected_exp_nfc, false);
    @memset(expected_exp_nfkd, false);
    @memset(expected_exp_nfkc, false);
    @memset(expected_cwkcf, false);

    // Quick_Check expected arrays — default is `.unknown` (matches the
    // generated table's gap-fill, not the UCD `@missing` default of `.yes`).
    const expected_nfc_qc = try arena.alloc(dnp.QuickCheck, 0x110000);
    const expected_nfd_qc = try arena.alloc(dnp.QuickCheck, 0x110000);
    const expected_nfkc_qc = try arena.alloc(dnp.QuickCheck, 0x110000);
    const expected_nfkd_qc = try arena.alloc(dnp.QuickCheck, 0x110000);
    @memset(expected_nfc_qc, .unknown);
    @memset(expected_nfd_qc, .unknown);
    @memset(expected_nfkc_qc, .unknown);
    @memset(expected_nfkd_qc, .unknown);

    // Mapping expected arrays. `null` = no entry; a (possibly empty) slice = explicit mapping (incl. delete).
    const Maybe = ?[]const CodePoint;
    const expected_fc_nfkc = try arena.alloc(Maybe, 0x110000);
    const expected_nfkc_cf = try arena.alloc(Maybe, 0x110000);
    const expected_nfkc_scf = try arena.alloc(Maybe, 0x110000);
    @memset(expected_fc_nfkc, null);
    @memset(expected_nfkc_cf, null);
    @memset(expected_nfkc_scf, null);

    var lines = std.mem.splitScalar(u8, txt, '\n');
    line_loop: while (lines.next()) |raw_line| {
        if (raw_line.len == 0 or raw_line[0] == '#') continue :line_loop;

        var split_hash = std.mem.splitScalar(u8, raw_line, '#');
        const data_part = std.mem.trim(u8, split_hash.next() orelse continue :line_loop, " \t\r");
        if (data_part.len == 0) continue :line_loop;

        var fields: [3][]const u8 = @splat("");
        var field_count: usize = 0;
        var split = std.mem.splitScalar(u8, data_part, ';');
        while (split.next()) |f| : (field_count += 1) {
            if (field_count == fields.len) break;
            fields[field_count] = std.mem.trim(u8, f, " \t");
        }
        if (field_count < 2) continue :line_loop;

        var cp_split = std.mem.splitSequence(u8, fields[0], "..");
        const start = try std.fmt.parseInt(CodePoint, cp_split.next() orelse continue :line_loop, 16);
        const end = if (cp_split.next()) |raw| try std.fmt.parseInt(CodePoint, raw, 16) else start;
        const label = fields[1];

        if (field_count == 2) {
            const arr: ?[]bool = if (std.mem.eql(u8, label, "Full_Composition_Exclusion"))
                expected_fce
            else if (std.mem.eql(u8, label, "Expands_On_NFD"))
                expected_exp_nfd
            else if (std.mem.eql(u8, label, "Expands_On_NFC"))
                expected_exp_nfc
            else if (std.mem.eql(u8, label, "Expands_On_NFKD"))
                expected_exp_nfkd
            else if (std.mem.eql(u8, label, "Expands_On_NFKC"))
                expected_exp_nfkc
            else if (std.mem.eql(u8, label, "Changes_When_NFKC_Casefolded"))
                expected_cwkcf
            else
                null;
            if (arr) |a| {
                for (@as(usize, start)..@as(usize, end) + 1) |cp| a[cp] = true;
            }
            continue :line_loop;
        }

        if (std.mem.endsWith(u8, label, "_QC")) {
            const qc = quickCheckFromUcd(fields[2]) orelse {
                std.debug.print("unknown QC value: '{s}'\n", .{fields[2]});
                return error.UnknownQuickCheckValue;
            };
            const target: ?[]dnp.QuickCheck = if (std.mem.eql(u8, label, "NFC_QC"))
                expected_nfc_qc
            else if (std.mem.eql(u8, label, "NFD_QC"))
                expected_nfd_qc
            else if (std.mem.eql(u8, label, "NFKC_QC"))
                expected_nfkc_qc
            else if (std.mem.eql(u8, label, "NFKD_QC"))
                expected_nfkd_qc
            else
                null;
            if (target) |t| {
                for (@as(usize, start)..@as(usize, end) + 1) |cp| t[cp] = qc;
            }
            continue :line_loop;
        }

        // Mapping. Empty third field => explicit empty mapping.
        var mapping_buf: std.ArrayList(CodePoint) = .empty;
        var tok = std.mem.splitScalar(u8, fields[2], ' ');
        while (tok.next()) |t| {
            const tt = std.mem.trim(u8, t, " \t");
            if (tt.len == 0) continue;
            try mapping_buf.append(arena, try std.fmt.parseInt(CodePoint, tt, 16));
        }
        const mapping: []CodePoint = try mapping_buf.toOwnedSlice(arena);

        const target_map: ?[]Maybe = if (std.mem.eql(u8, label, "FC_NFKC"))
            expected_fc_nfkc
        else if (std.mem.eql(u8, label, "NFKC_CF"))
            expected_nfkc_cf
        else if (std.mem.eql(u8, label, "NFKC_SCF"))
            expected_nfkc_scf
        else
            null;
        if (target_map) |t| {
            for (@as(usize, start)..@as(usize, end) + 1) |cp| t[cp] = mapping;
        }
    }

    // Now sweep every codepoint and assert lookups agree with the expected arrays.
    var cp_iter: usize = 0;
    while (cp_iter < 0x110000) : (cp_iter += 1) {
        const cp: CodePoint = @intCast(cp_iter);

        try testing.expectEqual(expected_fce[cp_iter], dnp.isFullCompositionExclusion(cp));
        try testing.expectEqual(expected_exp_nfd[cp_iter], dnp.isExpandsOnNfd(cp));
        try testing.expectEqual(expected_exp_nfc[cp_iter], dnp.isExpandsOnNfc(cp));
        try testing.expectEqual(expected_exp_nfkd[cp_iter], dnp.isExpandsOnNfkd(cp));
        try testing.expectEqual(expected_exp_nfkc[cp_iter], dnp.isExpandsOnNfkc(cp));
        try testing.expectEqual(expected_cwkcf[cp_iter], dnp.isChangesWhenNfkcCasefolded(cp));

        try testing.expectEqual(expected_nfc_qc[cp_iter], dnp.nfcQuickCheck(cp));
        try testing.expectEqual(expected_nfd_qc[cp_iter], dnp.nfdQuickCheck(cp));
        try testing.expectEqual(expected_nfkc_qc[cp_iter], dnp.nfkcQuickCheck(cp));
        try testing.expectEqual(expected_nfkd_qc[cp_iter], dnp.nfkdQuickCheck(cp));

        try expectOptionalCpSlices(expected_fc_nfkc[cp_iter], dnp.fcNfkcMap(cp));
        try expectOptionalCpSlices(expected_nfkc_cf[cp_iter], dnp.nfkcCaseFoldMap(cp));
        try expectOptionalCpSlices(expected_nfkc_scf[cp_iter], dnp.nfkcSimpleCaseFoldMap(cp));
    }

    // Out-of-range boundary: every lookup must return the safe default.
    try testing.expectEqual(false, dnp.isFullCompositionExclusion(0x110000));
    try testing.expectEqual(false, dnp.isExpandsOnNfd(0x110000));
    try testing.expectEqual(dnp.QuickCheck.unknown, dnp.nfcQuickCheck(0x110000));
    try testing.expectEqual(dnp.QuickCheck.unknown, dnp.nfdQuickCheck(0x110000));
    try testing.expectEqual(@as(?[]const CodePoint, null), dnp.fcNfkcMap(0x110000));
    try testing.expectEqual(@as(?[]const CodePoint, null), dnp.nfkcCaseFoldMap(0x110000));
}

fn expectOptionalCpSlices(want: ?[]const CodePoint, got: ?[]const CodePoint) !void {
    if (want == null and got == null) return;
    if (want == null) {
        std.debug.print("expected null, got slice of len {}\n", .{got.?.len});
        return error.UnexpectedSlice;
    }
    if (got == null) {
        std.debug.print("expected slice of len {}, got null\n", .{want.?.len});
        return error.UnexpectedNull;
    }
    try testing.expectEqualSlices(CodePoint, want.?, got.?);
}

// Spot tests for the three comptime-dispatched generic APIs — confirms the
// switch table compiles down to direct calls and that each arm reaches the
// right per-form lookup.
test "ucd: dnp comptime-dispatched generic API round-trips" {
    // QC: NFD on a precomposed letter must be .no (it decomposes).
    try testing.expectEqual(dnp.nfdQuickCheck(0x00C0), dnp.quickCheck(.nfd, 0x00C0));
    try testing.expectEqual(dnp.nfcQuickCheck(0x0300), dnp.quickCheck(.nfc, 0x0300));
    try testing.expectEqual(dnp.nfkcQuickCheck(0x00B5), dnp.quickCheck(.nfkc, 0x00B5));
    try testing.expectEqual(dnp.nfkdQuickCheck(0x00B5), dnp.quickCheck(.nfkd, 0x00B5));

    // Mapping: NFKC_CF on Latin capital A maps to lowercase a.
    const fold_a = dnp.casefoldMap(.nfkc_cf, 0x0041).?;
    try testing.expectEqualSlices(CodePoint, &.{0x61}, fold_a);
    // SOFT HYPHEN maps to empty (delete) under NFKC_CF.
    const fold_softhyphen = dnp.casefoldMap(.nfkc_cf, 0x00AD).?;
    try testing.expectEqual(@as(usize, 0), fold_softhyphen.len);

    // Boolean: combining grave is Expands_On_NFD? No — it's the decomposition target, not source.
    // 0x00C0 (À) IS Expands_On_NFD though — it decomposes to A + combining grave.
    try testing.expectEqual(dnp.isExpandsOnNfd(0x00C0), dnp.isExpandsOn(.nfd, 0x00C0));
    try testing.expectEqual(dnp.isExpandsOnNfkc(0x00C0), dnp.isExpandsOn(.nfkc, 0x00C0));
}

// Smoke test the new QuickCheck enum and the `unknown` default for unlisted
// codepoints. ASCII letters aren't in any QC table → all four checks return
// `.unknown` (not `.yes`).
test "ucd: dnp Quick_Check returns .unknown for unlisted codepoints" {
    try testing.expectEqual(dnp.QuickCheck.unknown, dnp.nfcQuickCheck(0x0041));
    try testing.expectEqual(dnp.QuickCheck.unknown, dnp.nfdQuickCheck(0x0041));
    try testing.expectEqual(dnp.QuickCheck.unknown, dnp.nfkcQuickCheck(0x0041));
    try testing.expectEqual(dnp.QuickCheck.unknown, dnp.nfkdQuickCheck(0x0041));
}

// ----- NormalizationTest.txt Part 1 cross-check against QC tables -----

const NormTestRow = struct {
    c1: []CodePoint,
    c2: []CodePoint,
    c3: []CodePoint,
    c4: []CodePoint,
    c5: []CodePoint,
};

fn parseHexSeq(arena: std.mem.Allocator, raw: []const u8) ![]CodePoint {
    var out: std.ArrayList(CodePoint) = .empty;
    var tok = std.mem.tokenizeAny(u8, raw, " \t");
    while (tok.next()) |t| {
        try out.append(arena, try std.fmt.parseInt(CodePoint, t, 16));
    }
    return try out.toOwnedSlice(arena);
}

fn parseNormTestRow(arena: std.mem.Allocator, data: []const u8) !NormTestRow {
    var iter = std.mem.splitScalar(u8, data, ';');
    const c1 = try parseHexSeq(arena, std.mem.trim(u8, iter.next() orelse return error.BadRow, " \t"));
    const c2 = try parseHexSeq(arena, std.mem.trim(u8, iter.next() orelse return error.BadRow, " \t"));
    const c3 = try parseHexSeq(arena, std.mem.trim(u8, iter.next() orelse return error.BadRow, " \t"));
    const c4 = try parseHexSeq(arena, std.mem.trim(u8, iter.next() orelse return error.BadRow, " \t"));
    const c5 = try parseHexSeq(arena, std.mem.trim(u8, iter.next() orelse return error.BadRow, " \t"));
    return .{ .c1 = c1, .c2 = c2, .c3 = c3, .c4 = c4, .c5 = c5 };
}

// Cross-check the four Quick_Check tables against NormalizationTest.txt Part 1.
// Part 1 has one row per assigned codepoint; for each row the source column
// c1 is the single codepoint X and the other columns are NFC(X), NFD(X),
// NFKC(X), NFKD(X). We don't normalize anything — we just observe column
// equality and assert it matches the QC table:
//
//   X == NFD(X)  ⇒  nfdQuickCheck(X) in {.yes, .unknown}
//   X != NFD(X)  ⇒  nfdQuickCheck(X) == .no            (NFD has no Maybe)
//   X == NFC(X)  ⇒  nfcQuickCheck(X) != .no
//   X != NFC(X)  ⇒  nfcQuickCheck(X) in {.no, .maybe}  (Maybe means "may differ")
//
// Same shape for NFKC/NFKD. Rows whose c1 has != 1 codepoint are skipped
// (those exist in Part 4/5; Part 1 lines all have single-codepoint sources).
test "ucd hostile: NormalizationTest.txt Part 1 — QC tables consistent with column equality" {
    const allocator = testing.allocator;

    var arena_state: std.heap.ArenaAllocator = .init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, normalization_test_path, allocator, .limited(8 * 1024 * 1024));
    defer allocator.free(txt);

    var in_part1 = false;
    var checked: usize = 0;

    var lines = std.mem.splitScalar(u8, txt, '\n');
    while (lines.next()) |raw_line| {
        const trimmed = std.mem.trim(u8, raw_line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        if (trimmed[0] == '@') {
            in_part1 = std.mem.startsWith(u8, trimmed, "@Part1");
            continue;
        }
        if (!in_part1) continue;

        const hash_idx = std.mem.indexOfScalar(u8, trimmed, '#') orelse trimmed.len;
        const data_part = std.mem.trim(u8, trimmed[0..hash_idx], " \t;");
        if (data_part.len == 0) continue;

        const row = try parseNormTestRow(arena, data_part);
        if (row.c1.len != 1) continue;
        const cp = row.c1[0];

        const eq = struct {
            fn call(a: []const CodePoint, b: []const CodePoint) bool {
                return std.mem.eql(CodePoint, a, b);
            }
        }.call;

        // NFD: column 3. NFD has no Maybe per UAX #15.
        const nfd_eq = eq(row.c1, row.c3);
        const nfd_qc = dnp.nfdQuickCheck(cp);
        if (nfd_eq) {
            if (nfd_qc == .no) {
                std.debug.print("NFD_QC mismatch for U+{X}: expected yes/unknown, got .no\n", .{cp});
                return error.NfdQcMismatch;
            }
        } else {
            if (nfd_qc != .no) {
                std.debug.print("NFD_QC mismatch for U+{X}: expected .no, got {}\n", .{ cp, nfd_qc });
                return error.NfdQcMismatch;
            }
        }

        // NFC: column 2. NFC may have Maybe (codepoint may differ depending on context).
        const nfc_eq = eq(row.c1, row.c2);
        const nfc_qc = dnp.nfcQuickCheck(cp);
        if (nfc_eq) {
            if (nfc_qc == .no) {
                std.debug.print("NFC_QC mismatch for U+{X}: expected non-.no, got .no\n", .{cp});
                return error.NfcQcMismatch;
            }
        } else {
            if (nfc_qc == .yes or nfc_qc == .unknown) {
                std.debug.print("NFC_QC mismatch for U+{X}: expected .no/.maybe, got {}\n", .{ cp, nfc_qc });
                return error.NfcQcMismatch;
            }
        }

        // NFKD: column 5. No Maybe.
        const nfkd_eq = eq(row.c1, row.c5);
        const nfkd_qc = dnp.nfkdQuickCheck(cp);
        if (nfkd_eq) {
            if (nfkd_qc == .no) {
                std.debug.print("NFKD_QC mismatch for U+{X}: expected yes/unknown, got .no\n", .{cp});
                return error.NfkdQcMismatch;
            }
        } else {
            if (nfkd_qc != .no) {
                std.debug.print("NFKD_QC mismatch for U+{X}: expected .no, got {}\n", .{ cp, nfkd_qc });
                return error.NfkdQcMismatch;
            }
        }

        // NFKC: column 4. May have Maybe.
        const nfkc_eq = eq(row.c1, row.c4);
        const nfkc_qc = dnp.nfkcQuickCheck(cp);
        if (nfkc_eq) {
            if (nfkc_qc == .no) {
                std.debug.print("NFKC_QC mismatch for U+{X}: expected non-.no, got .no\n", .{cp});
                return error.NfkcQcMismatch;
            }
        } else {
            if (nfkc_qc == .yes or nfkc_qc == .unknown) {
                std.debug.print("NFKC_QC mismatch for U+{X}: expected .no/.maybe, got {}\n", .{ cp, nfkc_qc });
                return error.NfkcQcMismatch;
            }
        }

        checked += 1;
    }

    try testing.expect(checked > 0);
}

// ============================================================================
// NormalizationTest.txt full conformance (Parts 0..3) for NFC/NFD/NFKC/NFKD.
//
// UAX #15 conformance invariants (per the file's preamble):
//
//   NFC:   c2 == toNFC(c1)  == toNFC(c2)  == toNFC(c3)
//          c4 == toNFC(c4)  == toNFC(c5)
//   NFD:   c3 == toNFD(c1)  == toNFD(c2)  == toNFD(c3)
//          c5 == toNFD(c4)  == toNFD(c5)
//   NFKC:  c4 == toNFKC(c1) == toNFKC(c2) == toNFKC(c3) == toNFKC(c4) == toNFKC(c5)
//   NFKD:  c5 == toNFKD(c1) == toNFKD(c2) == toNFKD(c3) == toNFKD(c4) == toNFKD(c5)
//
// Part 0: specific cases. Part 1: per-codepoint identity tests (single cp in c1
// per row). Parts 2/3: canonical order and PRI tests. We walk every row in
// every Part and assert all invariants. With ~25k rows this is the bedrock
// guarantee that our pipeline is wired up correctly across the table fully.
// ============================================================================

fn invariantsForRow(
    allocator: std.mem.Allocator,
    row: NormTestRow,
    part: u8,
    line_no: usize,
) !void {
    inline for (.{ "c1", "c2", "c3" }) |col_name| {
        const col = @field(row, col_name);
        const got = try normalization.nfc(allocator, col);
        defer allocator.free(got);
        if (!std.mem.eql(CodePoint, row.c2, got)) {
            std.debug.print(
                "NormalizationTest.txt Part {d} line {d}: NFC({s}) != c2\n  in:  {any}\n  got: {any}\n  c2:  {any}\n",
                .{ part, line_no, col_name, col, got, row.c2 },
            );
            return error.NFCMismatch;
        }
    }
    inline for (.{ "c1", "c2", "c3" }) |col_name| {
        const col = @field(row, col_name);
        const got = try normalization.nfd(allocator, col);
        defer allocator.free(got);
        if (!std.mem.eql(CodePoint, row.c3, got)) {
            std.debug.print(
                "NormalizationTest.txt Part {d} line {d}: NFD({s}) != c3\n  in:  {any}\n  got: {any}\n  c3:  {any}\n",
                .{ part, line_no, col_name, col, got, row.c3 },
            );
            return error.NFDMismatch;
        }
    }
    // c4 / c5 NFC/NFD invariants (compatibility decomposition collapses
    // into c4/c5 under NFC/NFD too).
    inline for (.{ "c4", "c5" }) |col_name| {
        const col = @field(row, col_name);
        const got_nfc = try normalization.nfc(allocator, col);
        defer allocator.free(got_nfc);
        if (!std.mem.eql(CodePoint, row.c4, got_nfc)) {
            std.debug.print(
                "NormalizationTest.txt Part {d} line {d}: NFC({s}) != c4\n  in:  {any}\n  got: {any}\n  c4:  {any}\n",
                .{ part, line_no, col_name, col, got_nfc, row.c4 },
            );
            return error.NFCMismatch;
        }
        const got_nfd = try normalization.nfd(allocator, col);
        defer allocator.free(got_nfd);
        if (!std.mem.eql(CodePoint, row.c5, got_nfd)) {
            std.debug.print(
                "NormalizationTest.txt Part {d} line {d}: NFD({s}) != c5\n  in:  {any}\n  got: {any}\n  c5:  {any}\n",
                .{ part, line_no, col_name, col, got_nfd, row.c5 },
            );
            return error.NFDMismatch;
        }
    }

    // NFKC: c4 == NFKC(c1..c5)
    inline for (.{ "c1", "c2", "c3", "c4", "c5" }) |col_name| {
        const col = @field(row, col_name);
        const got = try normalization.nfkc(allocator, col);
        defer allocator.free(got);
        if (!std.mem.eql(CodePoint, row.c4, got)) {
            std.debug.print(
                "NormalizationTest.txt Part {d} line {d}: NFKC({s}) != c4\n  in:  {any}\n  got: {any}\n  c4:  {any}\n",
                .{ part, line_no, col_name, col, got, row.c4 },
            );
            return error.NFKCMismatch;
        }
    }
    // NFKD: c5 == NFKD(c1..c5)
    inline for (.{ "c1", "c2", "c3", "c4", "c5" }) |col_name| {
        const col = @field(row, col_name);
        const got = try normalization.nfkd(allocator, col);
        defer allocator.free(got);
        if (!std.mem.eql(CodePoint, row.c5, got)) {
            std.debug.print(
                "NormalizationTest.txt Part {d} line {d}: NFKD({s}) != c5\n  in:  {any}\n  got: {any}\n  c5:  {any}\n",
                .{ part, line_no, col_name, col, got, row.c5 },
            );
            return error.NFKDMismatch;
        }
    }
}

/// Decode `@PartN` header lines into a `0..5` part index, or null for any
/// other `@…` line. Centralizing this matters because NormalizationTest.txt
/// has 6 parts and we want each test to identify the part precisely (for
/// labelling errors and for the per-part row-count floor).
fn partFromHeader(trimmed: []const u8) ?u8 {
    if (!std.mem.startsWith(u8, trimmed, "@Part")) return null;
    if (trimmed.len < 6) return null;
    return switch (trimmed[5]) {
        '0'...'5' => trimmed[5] - '0',
        else => null,
    };
}

test "ucd hostile: NormalizationTest.txt Parts 0..5 — all four forms match every row (specific, char-by-char, canonical order, PRI #29, canonical closures, chained primary composites)" {
    const allocator = testing.allocator;

    const txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, normalization_test_path, allocator, .limited(8 * 1024 * 1024));
    defer allocator.free(txt);

    var arena_state: std.heap.ArenaAllocator = .init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var part: u8 = 255;
    var per_part: [6]usize = .{ 0, 0, 0, 0, 0, 0 };
    var line_no: usize = 0;
    var lines = std.mem.splitScalar(u8, txt, '\n');

    while (lines.next()) |raw_line| {
        line_no += 1;
        const trimmed = std.mem.trim(u8, raw_line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        if (trimmed[0] == '@') {
            if (partFromHeader(trimmed)) |p| part = p;
            continue;
        }

        const hash_idx = std.mem.indexOfScalar(u8, trimmed, '#') orelse trimmed.len;
        const data_part = std.mem.trim(u8, trimmed[0..hash_idx], " \t;");
        if (data_part.len == 0) continue;

        const row = try parseNormTestRow(arena, data_part);
        try invariantsForRow(allocator, row, part, line_no);
        if (part < per_part.len) per_part[part] += 1;
    }

    // Floors per part — a future UCD release dropping any part is loud.
    // Current counts: 45 / 17086 / 1936 / 194 / 735 / 38.
    try testing.expect(per_part[0] >= 40); // Specific cases
    try testing.expect(per_part[1] >= 15_000); // Character by character
    try testing.expect(per_part[2] >= 1500); // Canonical Order Test
    try testing.expect(per_part[3] >= 150); // PRI #29 Test
    try testing.expect(per_part[4] >= 700); // Canonical closures (excluding Hangul)
    try testing.expect(per_part[5] >= 30); // Chained primary composites
}

// ----- Hostile: idempotency across every NormalizationTest.txt row -----

test "ucd hostile: idempotency — normalize(normalize(x)) == normalize(x) for every row in every Part" {
    const allocator = testing.allocator;

    const txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, normalization_test_path, allocator, .limited(8 * 1024 * 1024));
    defer allocator.free(txt);

    var arena_state: std.heap.ArenaAllocator = .init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var per_part: [6]usize = .{ 0, 0, 0, 0, 0, 0 };
    var part: u8 = 255;
    var lines = std.mem.splitScalar(u8, txt, '\n');
    while (lines.next()) |raw_line| {
        const trimmed = std.mem.trim(u8, raw_line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        if (trimmed[0] == '@') {
            if (partFromHeader(trimmed)) |p| part = p;
            continue;
        }
        if (part >= per_part.len) continue;

        const hash_idx = std.mem.indexOfScalar(u8, trimmed, '#') orelse trimmed.len;
        const data_part = std.mem.trim(u8, trimmed[0..hash_idx], " \t;");
        if (data_part.len == 0) continue;

        const row = try parseNormTestRow(arena, data_part);

        // Run idempotency on every column, not just c1 — every column is a
        // possible "input" the API will see in the wild.
        inline for (.{ "c1", "c2", "c3", "c4", "c5" }) |col_name| {
            const col = @field(row, col_name);
            inline for (.{ normalization.NormalizationForm.nfc, .nfd, .nfkc, .nfkd }) |form| {
                const once = try normalization.normalize(form, allocator, col);
                defer allocator.free(once);
                const twice = try normalization.normalize(form, allocator, once);
                defer allocator.free(twice);
                if (!std.mem.eql(CodePoint, once, twice)) {
                    std.debug.print(
                        "idempotency fail Part {d} form .{s} column {s} (first cp U+{X}): norm(norm(x)) != norm(x)\n  once: {any}\n  twice: {any}\n",
                        .{ part, @tagName(form), col_name, if (col.len == 0) @as(CodePoint, 0) else col[0], once, twice },
                    );
                    return error.IdempotencyViolation;
                }
            }
        }
        per_part[part] += 1;
    }
    try testing.expect(per_part[0] >= 40);
    try testing.expect(per_part[1] >= 15_000);
    try testing.expect(per_part[2] >= 1500);
    try testing.expect(per_part[3] >= 150);
    try testing.expect(per_part[4] >= 700);
    try testing.expect(per_part[5] >= 30);
}

// ----- Hostile: cross-form NFC(NFD(x)) == NFC(x), NFD(NFC(x)) == NFD(x), etc. -----

test "ucd hostile: cross-form invariants — NFC(NFD(x))==NFC(x), NFD(NFC(x))==NFD(x), NFKC/NFKD analogs across every Part" {
    const allocator = testing.allocator;

    const txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, normalization_test_path, allocator, .limited(8 * 1024 * 1024));
    defer allocator.free(txt);

    var arena_state: std.heap.ArenaAllocator = .init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var part: u8 = 255;
    var checked: usize = 0;
    var lines = std.mem.splitScalar(u8, txt, '\n');
    while (lines.next()) |raw_line| {
        const trimmed = std.mem.trim(u8, raw_line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        if (trimmed[0] == '@') {
            if (partFromHeader(trimmed)) |p| part = p;
            continue;
        }
        if (part >= 6) continue;

        const hash_idx = std.mem.indexOfScalar(u8, trimmed, '#') orelse trimmed.len;
        const data_part = std.mem.trim(u8, trimmed[0..hash_idx], " \t;");
        if (data_part.len == 0) continue;

        const row = try parseNormTestRow(arena, data_part);

        const nfc_x = try normalization.nfc(allocator, row.c1);
        defer allocator.free(nfc_x);
        const nfd_x = try normalization.nfd(allocator, row.c1);
        defer allocator.free(nfd_x);

        // NFC(NFD(x)) == NFC(x)
        const nfc_of_nfd = try normalization.nfc(allocator, nfd_x);
        defer allocator.free(nfc_of_nfd);
        try testing.expectEqualSlices(CodePoint, nfc_x, nfc_of_nfd);

        // NFD(NFC(x)) == NFD(x)
        const nfd_of_nfc = try normalization.nfd(allocator, nfc_x);
        defer allocator.free(nfd_of_nfc);
        try testing.expectEqualSlices(CodePoint, nfd_x, nfd_of_nfc);

        // NFKC/NFKD analogues
        const nfkc_x = try normalization.nfkc(allocator, row.c1);
        defer allocator.free(nfkc_x);
        const nfkd_x = try normalization.nfkd(allocator, row.c1);
        defer allocator.free(nfkd_x);

        const nfkc_of_nfkd = try normalization.nfkc(allocator, nfkd_x);
        defer allocator.free(nfkc_of_nfkd);
        try testing.expectEqualSlices(CodePoint, nfkc_x, nfkc_of_nfkd);

        const nfkd_of_nfkc = try normalization.nfkd(allocator, nfkc_x);
        defer allocator.free(nfkd_of_nfkc);
        try testing.expectEqualSlices(CodePoint, nfkd_x, nfkd_of_nfkc);

        checked += 1;
    }
    try testing.expect(checked > 15_000);
}

// ----- Hostile: every Hangul syllable round-trips through NFC and NFD -----

test "ucd hostile: every Hangul syllable in AC00..D7A3 decomposes and recomposes correctly" {
    const allocator = testing.allocator;

    // Pre-compute base constants per UAX #15 / TUS §3.12.
    const S_BASE: CodePoint = 0xAC00;
    const L_BASE: CodePoint = 0x1100;
    const V_BASE: CodePoint = 0x1161;
    const T_BASE: CodePoint = 0x11A7;
    const V_COUNT: CodePoint = 21;
    const T_COUNT: CodePoint = 28;
    const N_COUNT: CodePoint = V_COUNT * T_COUNT; // 588
    const S_COUNT: CodePoint = 11172;

    var s_idx: CodePoint = 0;
    while (s_idx < S_COUNT) : (s_idx += 1) {
        const cp = S_BASE + s_idx;
        const l = L_BASE + s_idx / N_COUNT;
        const v = V_BASE + (s_idx % N_COUNT) / T_COUNT;
        const t_off = s_idx % T_COUNT;

        const decomposed = try normalization.nfd(allocator, &.{cp});
        defer allocator.free(decomposed);

        if (t_off == 0) {
            try testing.expectEqualSlices(CodePoint, &.{ l, v }, decomposed);
        } else {
            try testing.expectEqualSlices(CodePoint, &.{ l, v, T_BASE + t_off }, decomposed);
        }

        const recomposed = try normalization.nfc(allocator, decomposed);
        defer allocator.free(recomposed);
        try testing.expectEqualSlices(CodePoint, &.{cp}, recomposed);
    }
}

// ----- Hostile: streaming Normalizer agrees with the batch API on every Part 1 row -----

test "ucd hostile: streaming Normalizer(form) emits identical output to batch normalize for every row in every Part" {
    const allocator = testing.allocator;

    const txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, normalization_test_path, allocator, .limited(8 * 1024 * 1024));
    defer allocator.free(txt);

    var arena_state: std.heap.ArenaAllocator = .init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var part: u8 = 255;
    var per_part: [6]usize = @splat(0);
    var lines = std.mem.splitScalar(u8, txt, '\n');

    while (lines.next()) |raw_line| {
        const trimmed = std.mem.trim(u8, raw_line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        if (trimmed[0] == '@') {
            if (partFromHeader(trimmed)) |p| part = p;
            continue;
        }
        if (part >= per_part.len) continue;

        const hash_idx = std.mem.indexOfScalar(u8, trimmed, '#') orelse trimmed.len;
        const data_part = std.mem.trim(u8, trimmed[0..hash_idx], " \t;");
        if (data_part.len == 0) continue;

        const row = try parseNormTestRow(arena, data_part);

        // Drive every column through the streaming Normalizer (not just c1) —
        // Parts 4 and 5 exercise multi-codepoint sources that only show up in
        // c1, but c4/c5 are the gnarliest compatibility inputs we test against.
        inline for (.{ "c1", "c2", "c3", "c4", "c5" }) |col_name| {
            const col = @field(row, col_name);
            inline for (.{ normalization.NormalizationForm.nfc, .nfd, .nfkc, .nfkd }) |form| {
                const batch = try normalization.normalize(form, allocator, col);
                defer allocator.free(batch);

                var streamed: std.ArrayList(CodePoint) = .empty;
                defer streamed.deinit(allocator);
                var norm = normalization.Normalizer(form).init();
                var scratch: [normalization.MAX_DECOMP_LEN]CodePoint = undefined;
                for (col) |cp| {
                    const emitted = norm.feed(cp, &scratch);
                    try streamed.appendSlice(allocator, emitted);
                }
                const tail = norm.flush(&scratch);
                try streamed.appendSlice(allocator, tail);

                if (!std.mem.eql(CodePoint, batch, streamed.items)) {
                    std.debug.print(
                        "streaming != batch for Part {d} form .{s} column {s}\n  input:    {any}\n  batch:    {any}\n  streamed: {any}\n",
                        .{ part, @tagName(form), col_name, col, batch, streamed.items },
                    );
                    return error.StreamingDisagreesWithBatch;
                }
            }
        }

        per_part[part] += 1;
    }
    try testing.expect(per_part[0] >= 40);
    try testing.expect(per_part[1] >= 15_000);
    try testing.expect(per_part[2] >= 1500);
    try testing.expect(per_part[3] >= 150);
    try testing.expect(per_part[4] >= 700);
    try testing.expect(per_part[5] >= 30);
}

// ----- Hostile: ASCII fast-path produces the same answer as the full pipeline -----

test "ucd hostile: ASCII fast-path agrees with full pipeline for every length-1..16 ASCII string" {
    const allocator = testing.allocator;

    // Sweep 0x00..0x7F. ASCII codepoints are NFC=NFD=NFKC=NFKD=self per UCD.
    var cp: CodePoint = 0;
    while (cp < 0x80) : (cp += 1) {
        const input: []const CodePoint = &.{cp};
        inline for (.{ normalization.NormalizationForm.nfc, .nfd, .nfkc, .nfkd }) |form| {
            const got = try normalization.normalize(form, allocator, input);
            defer allocator.free(got);
            try testing.expectEqualSlices(CodePoint, input, got);
            try testing.expect(normalization.isNormalized(form, got));
        }
    }
}

// ----- Hostile: isNormalized agrees with normalize for every Part 0 row -----

test "ucd hostile: isNormalized(form, normalize(form, x)) == true for every Part 0 + Part 1 row" {
    const allocator = testing.allocator;

    const txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, normalization_test_path, allocator, .limited(8 * 1024 * 1024));
    defer allocator.free(txt);

    var arena_state: std.heap.ArenaAllocator = .init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var part: u8 = 255;
    var checked: usize = 0;
    var lines = std.mem.splitScalar(u8, txt, '\n');

    while (lines.next()) |raw_line| {
        const trimmed = std.mem.trim(u8, raw_line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        if (trimmed[0] == '@') {
            if (std.mem.startsWith(u8, trimmed, "@Part0")) part = 0;
            if (std.mem.startsWith(u8, trimmed, "@Part1")) part = 1;
            if (std.mem.startsWith(u8, trimmed, "@Part2")) part = 2;
            if (std.mem.startsWith(u8, trimmed, "@Part3")) part = 3;
            continue;
        }
        if (part > 1) continue;

        const hash_idx = std.mem.indexOfScalar(u8, trimmed, '#') orelse trimmed.len;
        const data_part = std.mem.trim(u8, trimmed[0..hash_idx], " \t;");
        if (data_part.len == 0) continue;

        const row = try parseNormTestRow(arena, data_part);

        inline for (.{ normalization.NormalizationForm.nfc, .nfd, .nfkc, .nfkd }) |form| {
            const out = try normalization.normalize(form, allocator, row.c1);
            defer allocator.free(out);
            if (!normalization.isNormalized(form, out)) {
                std.debug.print(
                    "isNormalized(.{s}, normalize(.{s}, {any})) == false (out={any})\n",
                    .{ @tagName(form), @tagName(form), row.c1, out },
                );
                return error.IsNormalizedDisagreesWithNormalize;
            }
        }
        checked += 1;
    }
    try testing.expect(checked > 1000);
}

// ----- Hostile: empty input round-trips and out-of-range guard -----

test "ucd: normalize empty input returns empty slice across every form" {
    const allocator = testing.allocator;
    const empty: []const CodePoint = &.{};
    inline for (.{ normalization.NormalizationForm.nfc, .nfd, .nfkc, .nfkd }) |form| {
        const got = try normalization.normalize(form, allocator, empty);
        defer allocator.free(got);
        try testing.expectEqual(@as(usize, 0), got.len);
    }
}

// ----- Hostile: every assigned starter that is its own NFC also has nfcQuickCheck != .no -----

test "ucd hostile: every codepoint that is its own NFC has nfcQuickCheck != .no" {
    const allocator = testing.allocator;
    var cp: CodePoint = 0;
    while (cp < 0x10000) : (cp += 1) {
        if (cp >= 0xD800 and cp <= 0xDFFF) continue; // skip surrogates
        const got = try normalization.nfc(allocator, &.{cp});
        defer allocator.free(got);
        if (got.len == 1 and got[0] == cp) {
            // x is its own NFC. QC must not say .no.
            const qc = dnp.nfcQuickCheck(cp);
            if (qc == .no) {
                std.debug.print("U+{X}: NFC(x)==x but nfcQuickCheck == .no\n", .{cp});
                return error.QcDisagreesWithNormalize;
            }
        }
    }
}

// ----- Hostile: decomposition table — every entry round-trips through canonical compose -----

test "ucd hostile: every canonical 2-component decomp recomposes (modulo Full_Composition_Exclusion)" {
    var cp: CodePoint = 0;
    while (cp <= 0x10FFFF) : (cp += 1) {
        if (cp >= 0xD800 and cp <= 0xDFFF) continue;
        if (dnp.isFullCompositionExclusion(cp)) continue;
        const raw = decomposition.canonicalDecomposeRaw(cp) orelse continue;
        if (raw.len != 2) continue;
        // Hangul syllables don't appear in the raw table, so we don't have
        // to special-case them here — they're tested in the dedicated sweep.
        const composed = decomposition.canonicalCompose(raw[0], raw[1]) orelse {
            std.debug.print("U+{X}: decomp = U+{X} U+{X} but canonicalCompose returns null\n", .{ cp, raw[0], raw[1] });
            return error.CompositionMissing;
        };
        if (composed != cp) {
            std.debug.print("U+{X}: decomp+compose round-trips to U+{X}, expected U+{X}\n", .{ cp, composed, cp });
            return error.CompositionRoundTripMismatch;
        }
    }
}

// ----- Hostile: decomposition tables match a recursive expansion of UnicodeData.txt -----
//
// `canonicalDecomposeRaw` / `compatibilityDecomposeRaw` are *fully recursively
// expanded and canonically reordered* at generation time, so we can't compare
// them to UnicodeData.txt field 5 one-step mappings directly. This test
// independently reproduces that expansion + reorder from the source data and
// verifies both tables at every codepoint — the same algorithm the generator
// runs, written from scratch here so a bug in one wouldn't hide a bug in the
// other.

const DecompRow = struct { is_compat: bool, components: []const CodePoint };

/// Dense CCC array from UnicodeData.txt field 3. First/Last ranges all carry
/// CCC 0, so per-line assignment is sufficient (the default is already 0).
fn parseDecompCcc(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const ccc = try allocator.alloc(u8, 0x110000);
    @memset(ccc, 0);
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, ';');
        const cp_raw = fields.next() orelse continue;
        const cp = std.fmt.parseInt(CodePoint, std.mem.trim(u8, cp_raw, " \t\r"), 16) catch continue;
        _ = fields.next(); // name
        _ = fields.next(); // category
        const ccc_raw = fields.next() orelse continue;
        ccc[cp] = std.fmt.parseInt(u8, std.mem.trim(u8, ccc_raw, " \t\r"), 10) catch 0;
    }
    return ccc;
}

/// One-step decomposition map from UnicodeData.txt field 5 (`<tag>` ⇒ compat).
fn parseRawDecompMap(allocator: std.mem.Allocator, data: []const u8) !std.AutoHashMapUnmanaged(CodePoint, DecompRow) {
    var raw: std.AutoHashMapUnmanaged(CodePoint, DecompRow) = .empty;
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, ';');
        const cp_raw = fields.next() orelse continue;
        const cp = std.fmt.parseInt(CodePoint, std.mem.trim(u8, cp_raw, " \t\r"), 16) catch continue;
        _ = fields.next(); // name
        _ = fields.next(); // category
        _ = fields.next(); // ccc
        _ = fields.next(); // bidi
        const decomp_raw = fields.next() orelse continue;
        const decomp = std.mem.trim(u8, decomp_raw, " \t\r");
        if (decomp.len == 0) continue;

        var is_compat = false;
        var to_parse = decomp;
        if (decomp[0] == '<') {
            const close = std.mem.indexOfScalar(u8, decomp, '>') orelse continue;
            is_compat = true;
            to_parse = std.mem.trim(u8, decomp[close + 1 ..], " \t");
        }

        var comps: std.ArrayList(CodePoint) = .empty;
        var tok = std.mem.tokenizeAny(u8, to_parse, " \t");
        while (tok.next()) |t| try comps.append(allocator, try std.fmt.parseInt(CodePoint, t, 16));
        try raw.put(allocator, cp, .{ .is_compat = is_compat, .components = try comps.toOwnedSlice(allocator) });
    }
    return raw;
}

/// Recursively expand `cp`. In canonical mode (`compat == false`) a component
/// whose own row is compat-tagged is left as-is. Mirrors the generator's
/// `expandDecomposition`.
fn expandDecomp(
    allocator: std.mem.Allocator,
    raw: *const std.AutoHashMapUnmanaged(CodePoint, DecompRow),
    cache: *std.AutoHashMapUnmanaged(CodePoint, []const CodePoint),
    cp: CodePoint,
    compat: bool,
    depth: u8,
) ![]const CodePoint {
    if (depth > 32) return error.DecompositionCycle;
    if (cache.get(cp)) |cached| return cached;

    const self_singleton = blk: {
        const out = try allocator.alloc(CodePoint, 1);
        out[0] = cp;
        break :blk out;
    };

    const rd = raw.get(cp) orelse {
        try cache.put(allocator, cp, self_singleton);
        return self_singleton;
    };
    if (!compat and rd.is_compat) {
        try cache.put(allocator, cp, self_singleton);
        return self_singleton;
    }

    var buf: std.ArrayList(CodePoint) = .empty;
    for (rd.components) |comp| {
        try buf.appendSlice(allocator, try expandDecomp(allocator, raw, cache, comp, compat, depth + 1));
    }
    const out = try buf.toOwnedSlice(allocator);
    try cache.put(allocator, cp, out);
    return out;
}

/// Stable per-run sort by CCC; CCC-0 codepoints are barriers (UAX #15 D109).
/// Mirrors the generator's `canonicalReorder`.
fn canonicalReorderSeq(ccc: []const u8, seq: []CodePoint) void {
    if (seq.len < 2) return;
    var i: usize = 0;
    while (i < seq.len) {
        if (ccc[seq[i]] == 0) {
            i += 1;
            continue;
        }
        var j = i + 1;
        while (j < seq.len and ccc[seq[j]] != 0) j += 1;
        var k: usize = i + 1;
        while (k < j) : (k += 1) {
            const v = seq[k];
            const vc = ccc[v];
            var m = k;
            while (m > i and ccc[seq[m - 1]] > vc) : (m -= 1) seq[m] = seq[m - 1];
            seq[m] = v;
        }
        i = j;
    }
}

test "ucd hostile: decomposition tables (canonical + compatibility) match a full recursive expansion of UnicodeData.txt" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, unicode_data_path, testing.allocator, .limited(8 * 1024 * 1024));
    defer testing.allocator.free(txt);

    const ccc = try parseDecompCcc(arena, txt);
    var raw = try parseRawDecompMap(arena, txt);

    var canon_cache: std.AutoHashMapUnmanaged(CodePoint, []const CodePoint) = .empty;
    var compat_cache: std.AutoHashMapUnmanaged(CodePoint, []const CodePoint) = .empty;
    var present: std.AutoHashMapUnmanaged(CodePoint, void) = .empty;

    // Phase A: every codepoint that has a one-step decomposition.
    var it = raw.iterator();
    while (it.next()) |e| {
        const cp = e.key_ptr.*;
        const rd = e.value_ptr.*;
        try present.put(arena, cp, {});

        // Canonical: present iff the row is untagged; otherwise null.
        if (!rd.is_compat) {
            const seq = try arena.dupe(CodePoint, try expandDecomp(arena, &raw, &canon_cache, cp, false, 0));
            canonicalReorderSeq(ccc, seq);
            const got = decomposition.canonicalDecomposeRaw(cp) orelse {
                std.debug.print("U+{X}: canonicalDecomposeRaw returned null, expected a mapping\n", .{cp});
                return error.CanonicalDecompMissing;
            };
            try expectCodePointSlices(seq, got);
        } else {
            try testing.expectEqual(@as(?[]const CodePoint, null), decomposition.canonicalDecomposeRaw(cp));
        }

        // Compatibility: present for every row unless the full expansion is a
        // no-op `[cp]` (the generator drops those).
        const cseq = try arena.dupe(CodePoint, try expandDecomp(arena, &raw, &compat_cache, cp, true, 0));
        canonicalReorderSeq(ccc, cseq);
        if (cseq.len == 1 and cseq[0] == cp) {
            try testing.expectEqual(@as(?[]const CodePoint, null), decomposition.compatibilityDecomposeRaw(cp));
        } else {
            const cgot = decomposition.compatibilityDecomposeRaw(cp) orelse {
                std.debug.print("U+{X}: compatibilityDecomposeRaw returned null, expected a mapping\n", .{cp});
                return error.CompatDecompMissing;
            };
            try expectCodePointSlices(cseq, cgot);
        }
    }

    // Phase B: codepoints with no one-step decomposition must return null from
    // both raw tables (Hangul is handled by the wrapper, not these tables).
    var cp: CodePoint = 0;
    while (cp <= 0x10FFFF) : (cp += 1) {
        if (present.contains(cp)) continue;
        try testing.expectEqual(@as(?[]const CodePoint, null), decomposition.canonicalDecomposeRaw(cp));
        try testing.expectEqual(@as(?[]const CodePoint, null), decomposition.compatibilityDecomposeRaw(cp));
    }
}

// ----- Sanity: out-of-range codepoints pass through the API safely -----

test "ucd: normalize handles edge codepoints (0, 0x10FFFF, 0x110000) without UB" {
    const allocator = testing.allocator;
    const input: []const CodePoint = &.{ 0, 0x10FFFF };
    inline for (.{ normalization.NormalizationForm.nfc, .nfd, .nfkc, .nfkd }) |form| {
        const got = try normalization.normalize(form, allocator, input);
        defer allocator.free(got);
        try testing.expect(got.len >= input.len);
    }
}

// ----- UAX #24: Script and Script_Extensions ---------------------------------

/// Build `long name -> ScriptType` from PropertyValueAliases.txt by routing
/// each `sc` row's abbreviation through the generated `fromAbbreviation`.
/// Keys borrow from `pva`, so the map is only valid while `pva` is alive.
fn buildScriptNameMap(allocator: std.mem.Allocator, pva: []const u8) !std.StringHashMap(ScriptType) {
    var map = std.StringHashMap(ScriptType).init(allocator);
    errdefer map.deinit();
    var lines = std.mem.splitScalar(u8, pva, '\n');
    while (lines.next()) |line| {
        if (line.len == 0 or line[0] == '#') continue;
        var comment = std.mem.splitScalar(u8, line, '#');
        const body = comment.next() orelse continue;
        var fields = std.mem.splitScalar(u8, body, ';');
        const prop = std.mem.trim(u8, fields.next() orelse continue, " \t\r");
        if (!std.mem.eql(u8, prop, "sc")) continue;
        const abbrev = std.mem.trim(u8, fields.next() orelse continue, " \t\r");
        const full = std.mem.trim(u8, fields.next() orelse continue, " \t\r");
        const st = scripts.fromAbbreviation(abbrev) orelse {
            std.debug.print("PropertyValueAliases.txt: abbreviation '{s}' missing from ScriptType\n", .{abbrev});
            return error.UnknownScriptAbbreviation;
        };
        try map.put(full, st);
    }
    return map;
}

test "ucd hostile: Scripts.txt assigns the same Script to every codepoint as the generated table" {
    const allocator = testing.allocator;

    const pva = try std.Io.Dir.cwd().readFileAlloc(testing.io, property_value_aliases_path, allocator, .limited(2 * 1024 * 1024));
    defer allocator.free(pva);
    var name_map = try buildScriptNameMap(allocator, pva);
    defer name_map.deinit();

    const txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, scripts_path, allocator, .limited(2 * 1024 * 1024));
    defer allocator.free(txt);

    // Default Unknown for every codepoint not explicitly listed (@missing).
    const expected = try allocator.alloc(ScriptType, 0x110000);
    defer allocator.free(expected);
    @memset(expected, .unknown);

    var lines = std.mem.splitScalar(u8, txt, '\n');
    while (lines.next()) |raw_line| {
        const line = cleanData(raw_line);
        if (line.len == 0) continue;

        var parts = std.mem.splitScalar(u8, line, ';');
        const range = try parseRange(parts.next() orelse return error.BadScriptLine);
        const name = std.mem.trim(u8, parts.next() orelse return error.BadScriptLine, " \t\r");
        const st = name_map.get(name) orelse {
            std.debug.print("Scripts.txt: long name '{s}' missing from PropertyValueAliases.txt\n", .{name});
            return error.UnknownScriptName;
        };
        for (@as(usize, range.start)..@as(usize, range.end) + 1) |cp| expected[cp] = st;
    }

    for (expected, 0..) |want, cp| {
        try testing.expectEqual(want, scripts.scriptType(@intCast(cp)));
    }

    // Out of range stays Unknown, never traps.
    try testing.expectEqual(ScriptType.unknown, scripts.scriptType(0x110000));
    try testing.expectEqual(ScriptType.unknown, scripts.scriptType(0x1FFFFF));
}

test "ucd hostile: ScriptExtensions.txt set matches scriptExtensions for every codepoint, with Script fallback" {
    const allocator = testing.allocator;

    const txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, script_extensions_path, allocator, .limited(2 * 1024 * 1024));
    defer allocator.free(txt);

    // sets[0] is the empty sentinel; every parsed line appends one set and the
    // per-codepoint id points into this list. 0 means "not listed".
    var sets: std.ArrayList([]ScriptType) = .empty;
    defer {
        for (sets.items) |s| allocator.free(s);
        sets.deinit(allocator);
    }
    try sets.append(allocator, try allocator.alloc(ScriptType, 0));

    const cp_set = try allocator.alloc(u32, 0x110000);
    defer allocator.free(cp_set);
    @memset(cp_set, 0);

    var lines = std.mem.splitScalar(u8, txt, '\n');
    while (lines.next()) |raw_line| {
        const line = cleanData(raw_line);
        if (line.len == 0) continue;

        var parts = std.mem.splitScalar(u8, line, ';');
        const range = try parseRange(parts.next() orelse return error.BadScriptExtLine);
        const set_raw = std.mem.trim(u8, parts.next() orelse return error.BadScriptExtLine, " \t\r");

        var list: std.ArrayList(ScriptType) = .empty;
        defer list.deinit(allocator);
        var toks = std.mem.splitScalar(u8, set_raw, ' ');
        while (toks.next()) |tok| {
            const abbr = std.mem.trim(u8, tok, " \t\r");
            if (abbr.len == 0) continue;
            const st = scripts.fromAbbreviation(abbr) orelse {
                std.debug.print("ScriptExtensions.txt: unknown abbreviation '{s}'\n", .{abbr});
                return error.UnknownScriptAbbreviation;
            };
            try list.append(allocator, st);
        }
        // Match the generator's canonical ordering (ascending enum value) so a
        // plain element-wise comparison suffices.
        std.mem.sort(ScriptType, list.items, {}, struct {
            fn lessThan(_: void, a: ScriptType, b: ScriptType) bool {
                return @intFromEnum(a) < @intFromEnum(b);
            }
        }.lessThan);

        const id: u32 = @intCast(sets.items.len);
        try sets.append(allocator, try allocator.dupe(ScriptType, list.items));
        for (@as(usize, range.start)..@as(usize, range.end) + 1) |cp| cp_set[cp] = id;
    }

    for (cp_set, 0..) |id, cp| {
        const actual = scripts.scriptExtensions(@intCast(cp));
        if (id == 0) {
            // No explicit extensions: must be exactly {Script(cp)}.
            try testing.expectEqual(@as(usize, 1), actual.len);
            try testing.expectEqual(scripts.scriptType(@intCast(cp)), actual[0]);
        } else {
            const want = sets.items[id];
            try testing.expectEqual(want.len, actual.len);
            for (want, actual) |w, a| try testing.expectEqual(w, a);
        }
    }

    // Out of range: single-element Unknown set (Script fallback), never empty.
    const oob = scripts.scriptExtensions(0x110000);
    try testing.expectEqual(@as(usize, 1), oob.len);
    try testing.expectEqual(ScriptType.unknown, oob[0]);
}

test "ucd hostile: BidiMirroring.txt maps every codepoint identically to the generated table" {
    const allocator = testing.allocator;

    const txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, bidi_mirroring_path, allocator, .limited(1024 * 1024));
    defer allocator.free(txt);

    // Default <none> (0 sentinel here means null) for every unlisted codepoint.
    const expected = try allocator.alloc(?CodePoint, 0x110000);
    defer allocator.free(expected);
    @memset(expected, null);

    var lines = std.mem.splitScalar(u8, txt, '\n');
    while (lines.next()) |raw_line| {
        const line = cleanData(raw_line);
        if (line.len == 0) continue;

        var parts = std.mem.splitScalar(u8, line, ';');
        const cp = try parseCodePoint(parts.next() orelse return error.BadMirrorLine);
        const mirror = try parseCodePoint(parts.next() orelse return error.BadMirrorLine);
        expected[cp] = mirror;
    }

    for (expected, 0..) |want, cp| {
        try testing.expectEqual(want, bidi_props.bidiMirroringGlyph(@intCast(cp)));
    }

    // Out of range stays null, never traps.
    try testing.expectEqual(@as(?CodePoint, null), bidi_props.bidiMirroringGlyph(0x110000));
    try testing.expectEqual(@as(?CodePoint, null), bidi_props.bidiMirroringGlyph(0x1FFFFF));
}

test "ucd hostile: BidiBrackets.txt assigns the same type and pairing to every codepoint as the generated tables" {
    const allocator = testing.allocator;

    const txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, bidi_brackets_path, allocator, .limited(1024 * 1024));
    defer allocator.free(txt);

    const expected_type = try allocator.alloc(bidi_props.BidiPairedBracketType, 0x110000);
    defer allocator.free(expected_type);
    @memset(expected_type, .none);

    const expected_pair = try allocator.alloc(?CodePoint, 0x110000);
    defer allocator.free(expected_pair);
    @memset(expected_pair, null);

    var lines = std.mem.splitScalar(u8, txt, '\n');
    while (lines.next()) |raw_line| {
        const line = cleanData(raw_line);
        if (line.len == 0) continue;

        var parts = std.mem.splitScalar(u8, line, ';');
        const cp = try parseCodePoint(parts.next() orelse return error.BadBracketLine);
        const pair_raw = std.mem.trim(u8, parts.next() orelse return error.BadBracketLine, " \t\r");
        const type_raw = std.mem.trim(u8, parts.next() orelse return error.BadBracketLine, " \t\r");

        expected_type[cp] = if (std.mem.eql(u8, type_raw, "o"))
            .open
        else if (std.mem.eql(u8, type_raw, "c"))
            .close
        else
            .none;

        if (!std.mem.eql(u8, pair_raw, "<none>")) {
            expected_pair[cp] = try parseCodePoint(pair_raw);
        }
    }

    for (0..0x110000) |cp| {
        try testing.expectEqual(expected_type[cp], bidi_props.bidiPairedBracketType(@intCast(cp)));
        try testing.expectEqual(expected_pair[cp], bidi_props.bidiPairedBracket(@intCast(cp)));
    }

    // Out of range never traps.
    try testing.expectEqual(bidi_props.BidiPairedBracketType.none, bidi_props.bidiPairedBracketType(0x110000));
    try testing.expectEqual(@as(?CodePoint, null), bidi_props.bidiPairedBracket(0x1FFFFF));
}

test "ucd hostile: DerivedNumericType.txt assigns the same Numeric_Type to every codepoint" {
    const allocator = testing.allocator;

    const txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, numeric_type_path, allocator, .limited(2 * 1024 * 1024));
    defer allocator.free(txt);

    const NumericType = numeric_props.NumericType;
    const expected = try allocator.alloc(NumericType, 0x110000);
    defer allocator.free(expected);
    @memset(expected, .none);

    var lines = std.mem.splitScalar(u8, txt, '\n');
    while (lines.next()) |raw_line| {
        const line = cleanData(raw_line);
        if (line.len == 0) continue;

        var parts = std.mem.splitScalar(u8, line, ';');
        const range = try parseRange(parts.next() orelse return error.BadNumericTypeLine);
        const name = std.mem.trim(u8, parts.next() orelse return error.BadNumericTypeLine, " \t\r");
        const nt: NumericType = if (std.mem.eql(u8, name, "Decimal"))
            .decimal
        else if (std.mem.eql(u8, name, "Digit"))
            .digit
        else if (std.mem.eql(u8, name, "Numeric"))
            .numeric
        else
            return error.UnknownNumericType;
        for (@as(usize, range.start)..@as(usize, range.end) + 1) |cp| expected[cp] = nt;
    }

    for (expected, 0..) |want, cp| {
        try testing.expectEqual(want, numeric_props.numericType(@intCast(cp)));
    }
    try testing.expectEqual(NumericType.none, numeric_props.numericType(0x110000));
}

test "ucd hostile: DerivedNumericValues.txt assigns the same Numeric_Value to every codepoint" {
    const allocator = testing.allocator;

    const txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, numeric_values_path, allocator, .limited(4 * 1024 * 1024));
    defer allocator.free(txt);

    const NumericValue = numeric_props.NumericValue;
    const expected = try allocator.alloc(?NumericValue, 0x110000);
    defer allocator.free(expected);
    @memset(expected, null);

    var lines = std.mem.splitScalar(u8, txt, '\n');
    while (lines.next()) |raw_line| {
        const line = cleanData(raw_line);
        if (line.len == 0) continue;

        var parts = std.mem.splitScalar(u8, line, ';');
        const range = try parseRange(parts.next() orelse return error.BadNumericValueLine);
        _ = parts.next(); // decimal field (lossy)
        _ = parts.next(); // empty field
        const rational = std.mem.trim(u8, parts.next() orelse return error.BadNumericValueLine, " \t\r");

        var frac = std.mem.splitScalar(u8, rational, '/');
        const numerator = try std.fmt.parseInt(i64, std.mem.trim(u8, frac.next() orelse return error.BadNumericValueLine, " \t\r"), 10);
        const denominator = if (frac.next()) |d| try std.fmt.parseInt(i64, std.mem.trim(u8, d, " \t\r"), 10) else 1;
        const v: NumericValue = .{ .numerator = numerator, .denominator = denominator };
        for (@as(usize, range.start)..@as(usize, range.end) + 1) |cp| expected[cp] = v;
    }

    for (expected, 0..) |want, cp| {
        try testing.expectEqual(want, numeric_props.numericValue(@intCast(cp)));
    }
    try testing.expectEqual(@as(?NumericValue, null), numeric_props.numericValue(0x110000));
}

test "ucd hostile: Blocks.txt assigns the same Block to every codepoint" {
    const allocator = testing.allocator;

    const txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, blocks_path, allocator, .limited(1024 * 1024));
    defer allocator.free(txt);

    // Expected canonical block name per codepoint; default "No_Block" (@missing).
    const expected_name = try allocator.alloc([]const u8, 0x110000);
    defer allocator.free(expected_name);
    @memset(expected_name, "No_Block");

    var lines = std.mem.splitScalar(u8, txt, '\n');
    while (lines.next()) |raw_line| {
        const line = cleanData(raw_line);
        if (line.len == 0) continue;

        var parts = std.mem.splitScalar(u8, line, ';');
        const range = try parseRange(parts.next() orelse return error.BadBlockLine);
        const name = std.mem.trim(u8, parts.next() orelse return error.BadBlockLine, " \t\r");
        for (@as(usize, range.start)..@as(usize, range.end) + 1) |cp| expected_name[cp] = name;
    }

    for (expected_name, 0..) |want, cp| {
        try testing.expectEqualStrings(want, blocks_props.blockName(blocks_props.block(@intCast(cp))));
    }
    try testing.expectEqual(blocks_props.Block.no_block, blocks_props.block(0x110000));
}

test "ucd hostile: HangulSyllableType.txt assigns the same type to every codepoint" {
    const allocator = testing.allocator;

    const txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, hangul_syllable_type_path, allocator, .limited(1024 * 1024));
    defer allocator.free(txt);

    const HST = hangul_props.HangulSyllableType;
    const expected = try allocator.alloc(HST, 0x110000);
    defer allocator.free(expected);
    @memset(expected, .not_applicable);

    var lines = std.mem.splitScalar(u8, txt, '\n');
    while (lines.next()) |raw_line| {
        const line = cleanData(raw_line);
        if (line.len == 0) continue;

        var parts = std.mem.splitScalar(u8, line, ';');
        const range = try parseRange(parts.next() orelse return error.BadHangulLine);
        const code = std.mem.trim(u8, parts.next() orelse return error.BadHangulLine, " \t\r");
        const hst: HST = if (std.mem.eql(u8, code, "L"))
            .l
        else if (std.mem.eql(u8, code, "V"))
            .v
        else if (std.mem.eql(u8, code, "T"))
            .t
        else if (std.mem.eql(u8, code, "LV"))
            .lv
        else if (std.mem.eql(u8, code, "LVT"))
            .lvt
        else
            return error.UnknownHangulType;
        for (@as(usize, range.start)..@as(usize, range.end) + 1) |cp| expected[cp] = hst;
    }

    for (expected, 0..) |want, cp| {
        try testing.expectEqual(want, hangul_props.hangulSyllableType(@intCast(cp)));
    }
    try testing.expectEqual(HST.not_applicable, hangul_props.hangulSyllableType(0x110000));
}

// Map a UAX #9 Bidi_Class short name to a representative codepoint whose
// bidiClass() returns that class.  Only one representative per class is needed;
// we deliberately avoid bracket codepoints for ON so N0 does not fire.
fn bidiClassCp(name: []const u8) ?CodePoint {
    if (std.mem.eql(u8, name, "L")) return 0x0041; // LATIN CAPITAL LETTER A
    if (std.mem.eql(u8, name, "R")) return 0x05D0; // HEBREW LETTER ALEF
    if (std.mem.eql(u8, name, "AL")) return 0x0627; // ARABIC LETTER ALEF
    if (std.mem.eql(u8, name, "EN")) return 0x0030; // DIGIT ZERO
    if (std.mem.eql(u8, name, "ES")) return 0x002B; // PLUS SIGN
    if (std.mem.eql(u8, name, "ET")) return 0x0024; // DOLLAR SIGN
    if (std.mem.eql(u8, name, "AN")) return 0x0660; // ARABIC-INDIC DIGIT ZERO
    if (std.mem.eql(u8, name, "CS")) return 0x002C; // COMMA
    if (std.mem.eql(u8, name, "NSM")) return 0x0300; // COMBINING GRAVE ACCENT
    if (std.mem.eql(u8, name, "BN")) return 0x200B; // ZERO WIDTH SPACE
    if (std.mem.eql(u8, name, "B")) return 0x2029; // PARAGRAPH SEPARATOR
    if (std.mem.eql(u8, name, "S")) return 0x0009; // CHARACTER TABULATION
    if (std.mem.eql(u8, name, "WS")) return 0x0020; // SPACE
    if (std.mem.eql(u8, name, "ON")) return 0x0021; // EXCLAMATION MARK (not a bracket)
    if (std.mem.eql(u8, name, "LRE")) return 0x202A;
    if (std.mem.eql(u8, name, "LRO")) return 0x202D;
    if (std.mem.eql(u8, name, "RLE")) return 0x202B;
    if (std.mem.eql(u8, name, "RLO")) return 0x202E;
    if (std.mem.eql(u8, name, "PDF")) return 0x202C;
    if (std.mem.eql(u8, name, "LRI")) return 0x2066;
    if (std.mem.eql(u8, name, "RLI")) return 0x2067;
    if (std.mem.eql(u8, name, "FSI")) return 0x2068;
    if (std.mem.eql(u8, name, "PDI")) return 0x2069;
    return null;
}

test "ucd hostile: DerivedAge.txt assigns the same version to every codepoint" {
    const allocator = testing.allocator;

    const txt = try std.Io.Dir.cwd().readFileAlloc(testing.io, derived_age_path, allocator, .limited(2 * 1024 * 1024));
    defer allocator.free(txt);

    const Version = age_props.Version;
    // null == unassigned (@missing) for every codepoint not explicitly listed.
    const expected = try allocator.alloc(?Version, 0x110000);
    defer allocator.free(expected);
    @memset(expected, null);

    var lines = std.mem.splitScalar(u8, txt, '\n');
    while (lines.next()) |raw_line| {
        const line = cleanData(raw_line);
        if (line.len == 0) continue;

        var parts = std.mem.splitScalar(u8, line, ';');
        const range = try parseRange(parts.next() orelse return error.BadAgeLine);
        const ver = std.mem.trim(u8, parts.next() orelse return error.BadAgeLine, " \t\r");
        var vi = std.mem.splitScalar(u8, ver, '.');
        const major = try std.fmt.parseInt(u16, std.mem.trim(u8, vi.next() orelse return error.BadAgeLine, " \t\r"), 10);
        const minor = try std.fmt.parseInt(u16, std.mem.trim(u8, vi.next() orelse "0", " \t\r"), 10);
        const v: Version = .{ .major = major, .minor = minor };
        for (@as(usize, range.start)..@as(usize, range.end) + 1) |cp| expected[cp] = v;
    }

    for (expected, 0..) |want, cp| {
        try testing.expectEqual(want, age_props.assignedIn(@intCast(cp)));
    }
    try testing.expectEqual(age_props.Age.unassigned, age_props.age(0x110000));
    try testing.expectEqual(@as(?Version, null), age_props.assignedIn(0x1FFFFF));
}

// ============================================================================
// UAX #9 Bidirectional Algorithm conformance: BidiTest.txt + BidiCharacterTest.txt
//
// BidiTest.txt format:
//   @Levels: <l0> <l1> ...   — expected resolved levels; 'x' = removed by X9
//   @Reorder: <i0> <i1> ...  — visual order of non-x characters (0-based indices)
//   <types>; <bitset>         — Bidi_Class names + which para-directions to test
//     bitset bit 0 (1) = auto-LTR (P2/P3, first-strong heuristic, default LTR)
//     bitset bit 1 (2) = explicit LTR (force paragraph level 0)
//     bitset bit 2 (4) = explicit RTL (force paragraph level 1)
//
// BidiCharacterTest.txt format (five semicolon-delimited fields per line):
//   <cps>; <para_dir>; <para_level>; <levels>; <reorder>
//     para_dir: 0=LTR, 1=RTL, 2=auto-LTR (P2/P3)
// ============================================================================

test "ucd hostile: BidiTest.txt full conformance (UAX #9 levels and visual order, abstract Bidi_Class sequences)" {
    const allocator = testing.allocator;
    const text = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        bidi_test_path,
        allocator,
        .limited(8 * 1024 * 1024),
    );
    defer allocator.free(text);

    // Context lines: slices into `text`, valid for its lifetime.
    var levels_raw: []const u8 = "";
    var reorder_raw: []const u8 = "";
    var have_context = false;

    var tested: usize = 0;
    var line_no: usize = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        line_no += 1;
        const clean = cleanData(raw_line);
        if (clean.len == 0) continue;

        if (std.mem.startsWith(u8, clean, "@Levels:")) {
            levels_raw = std.mem.trim(u8, clean["@Levels:".len..], " \t");
            have_context = true;
            continue;
        }
        if (std.mem.startsWith(u8, clean, "@Reorder:")) {
            reorder_raw = std.mem.trim(u8, clean["@Reorder:".len..], " \t");
            continue;
        }
        if (!have_context) continue;

        // Data line: <types>; <bitset>
        var split = std.mem.splitScalar(u8, clean, ';');
        const types_raw = std.mem.trim(u8, split.next() orelse continue, " \t");
        const bitset_raw = std.mem.trim(u8, split.next() orelse continue, " \t");
        if (types_raw.len == 0 or bitset_raw.len == 0) continue;
        const bitset = try std.fmt.parseInt(u8, bitset_raw, 10);

        // Parse Bidi_Class sequence → representative codepoints.
        var cps: std.ArrayList(CodePoint) = .empty;
        defer cps.deinit(allocator);
        var type_tok = std.mem.tokenizeAny(u8, types_raw, " \t");
        while (type_tok.next()) |t| {
            const cp = bidiClassCp(t) orelse {
                std.debug.print("BidiTest.txt line {d}: unknown Bidi_Class '{s}'\n", .{ line_no, t });
                return error.UnknownBidiClass;
            };
            try cps.append(allocator, cp);
        }

        // Parse @Levels: context — e.g. "0 x 1 2".
        var exp_levels: std.ArrayList(?bidi_props.Level) = .empty;
        defer exp_levels.deinit(allocator);
        var lev_tok = std.mem.tokenizeAny(u8, levels_raw, " \t");
        while (lev_tok.next()) |t| {
            if (std.mem.eql(u8, t, "x")) {
                try exp_levels.append(allocator, null);
            } else {
                try exp_levels.append(allocator, try std.fmt.parseInt(bidi_props.Level, t, 10));
            }
        }

        // Parse @Reorder: context — e.g. "0 2 1".
        var exp_reorder: std.ArrayList(usize) = .empty;
        defer exp_reorder.deinit(allocator);
        var ro_tok = std.mem.tokenizeAny(u8, reorder_raw, " \t");
        while (ro_tok.next()) |t| {
            try exp_reorder.append(allocator, try std.fmt.parseInt(usize, t, 10));
        }

        if (exp_levels.items.len != cps.items.len) {
            std.debug.print(
                "BidiTest.txt line {d}: @Levels count ({d}) != types count ({d})\n",
                .{ line_no, exp_levels.items.len, cps.items.len },
            );
            return error.BidiTestFormatError;
        }

        // Test each paragraph direction selected by the bitset.
        const dir_table = [_]struct { bit: u8, dir: bidi_props.BaseDirection }{
            .{ .bit = 1, .dir = .auto },
            .{ .bit = 2, .dir = .ltr },
            .{ .bit = 4, .dir = .rtl },
        };

        for (dir_table) |entry| {
            if (bitset & entry.bit == 0) continue;

            var para = try bidi_props.resolveParagraph(allocator, cps.items, entry.dir);
            defer para.deinit();

            // Get L1-applied levels (treating the whole sequence as one line).
            const levels_l1 = try para.lineLevels(allocator, 0, para.levels.len);
            defer allocator.free(levels_l1);

            // Compare levels; skip 'x' positions.
            for (exp_levels.items, 0..) |maybe_lvl, i| {
                const want = maybe_lvl orelse continue;
                if (levels_l1[i] != want) {
                    std.debug.print(
                        "BidiTest.txt line {d} dir=.{s}: level[{d}] expected {d} got {d}\n  types: {s}\n  @Levels: {s}\n",
                        .{ line_no, @tagName(entry.dir), i, want, levels_l1[i], types_raw, levels_raw },
                    );
                    return error.BidiLevelMismatch;
                }
            }

            // Compare visual order; filter out 'x' positions from the output.
            const vis_order = try para.reorderLine(allocator, 0, para.levels.len);
            defer allocator.free(vis_order);

            var actual_reorder: std.ArrayList(usize) = .empty;
            defer actual_reorder.deinit(allocator);
            for (vis_order) |idx| {
                if (exp_levels.items[idx] != null) try actual_reorder.append(allocator, idx);
            }

            if (actual_reorder.items.len != exp_reorder.items.len) {
                std.debug.print(
                    "BidiTest.txt line {d} dir=.{s}: reorder length expected {d} got {d}\n  types: {s}\n  @Reorder: {s}\n",
                    .{ line_no, @tagName(entry.dir), exp_reorder.items.len, actual_reorder.items.len, types_raw, reorder_raw },
                );
                return error.BidiReorderLengthMismatch;
            }

            for (actual_reorder.items, exp_reorder.items, 0..) |got, want, ri| {
                if (got != want) {
                    std.debug.print(
                        "BidiTest.txt line {d} dir=.{s}: reorder[{d}] expected {d} got {d}\n  types: {s}\n  @Reorder: {s}\n",
                        .{ line_no, @tagName(entry.dir), ri, want, got, types_raw, reorder_raw },
                    );
                    return error.BidiReorderMismatch;
                }
            }

            tested += 1;
        }
    }

    try testing.expect(tested > 0);
}

test "ucd hostile: BidiCharacterTest.txt full conformance (UAX #9 levels and visual order, real codepoints)" {
    const allocator = testing.allocator;
    const text = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        bidi_character_test_path,
        allocator,
        .limited(16 * 1024 * 1024),
    );
    defer allocator.free(text);

    var tested: usize = 0;
    var line_no: usize = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        line_no += 1;
        const clean = cleanData(raw_line);
        if (clean.len == 0) continue;

        // Five semicolon-separated fields.
        var fields = std.mem.splitScalar(u8, clean, ';');
        const cps_raw = std.mem.trim(u8, fields.next() orelse continue, " \t");
        const dir_raw = std.mem.trim(u8, fields.next() orelse continue, " \t");
        const para_lvl_raw = std.mem.trim(u8, fields.next() orelse continue, " \t");
        const levels_raw = std.mem.trim(u8, fields.next() orelse continue, " \t");
        const reorder_raw = std.mem.trim(u8, fields.next() orelse continue, " \t");
        if (cps_raw.len == 0) continue;

        // Codepoints.
        var cps: std.ArrayList(CodePoint) = .empty;
        defer cps.deinit(allocator);
        var cp_tok = std.mem.tokenizeAny(u8, cps_raw, " \t");
        while (cp_tok.next()) |t| {
            try cps.append(allocator, try std.fmt.parseInt(CodePoint, t, 16));
        }

        // Paragraph direction: 0=LTR, 1=RTL, 2=auto.
        const dir_int = try std.fmt.parseInt(u8, dir_raw, 10);
        const dir: bidi_props.BaseDirection = switch (dir_int) {
            0 => .ltr,
            1 => .rtl,
            2 => .auto,
            else => {
                std.debug.print("BidiCharacterTest.txt line {d}: unknown para_direction {d}\n", .{ line_no, dir_int });
                return error.UnknownParaDirection;
            },
        };

        // Expected paragraph embedding level.
        const exp_para_level = try std.fmt.parseInt(bidi_props.Level, para_lvl_raw, 10);

        // Expected resolved levels ('x' = removed by X9).
        var exp_levels: std.ArrayList(?bidi_props.Level) = .empty;
        defer exp_levels.deinit(allocator);
        var lev_tok = std.mem.tokenizeAny(u8, levels_raw, " \t");
        while (lev_tok.next()) |t| {
            if (std.mem.eql(u8, t, "x")) {
                try exp_levels.append(allocator, null);
            } else {
                try exp_levels.append(allocator, try std.fmt.parseInt(bidi_props.Level, t, 10));
            }
        }

        // Expected visual order (indices of non-x characters in display order).
        var exp_reorder: std.ArrayList(usize) = .empty;
        defer exp_reorder.deinit(allocator);
        var ro_tok = std.mem.tokenizeAny(u8, reorder_raw, " \t");
        while (ro_tok.next()) |t| {
            if (t.len == 0) continue;
            try exp_reorder.append(allocator, try std.fmt.parseInt(usize, t, 10));
        }

        // Run the full algorithm.
        var para = try bidi_props.resolveParagraph(allocator, cps.items, dir);
        defer para.deinit();

        // Paragraph embedding level.
        if (para.level != exp_para_level) {
            std.debug.print(
                "BidiCharacterTest.txt line {d}: paragraph level expected {d} got {d}\n  codepoints: {s}\n",
                .{ line_no, exp_para_level, para.level, cps_raw },
            );
            return error.BidiParaLevelMismatch;
        }

        // Resolved levels with L1 applied (whole sequence treated as one line).
        const levels_l1 = try para.lineLevels(allocator, 0, para.levels.len);
        defer allocator.free(levels_l1);

        for (exp_levels.items, 0..) |maybe_lvl, i| {
            const want = maybe_lvl orelse continue;
            if (i >= levels_l1.len) break;
            if (levels_l1[i] != want) {
                std.debug.print(
                    "BidiCharacterTest.txt line {d}: level[{d}] expected {d} got {d}\n  codepoints: {s}\n",
                    .{ line_no, i, want, levels_l1[i], cps_raw },
                );
                return error.BidiLevelMismatch;
            }
        }

        // Visual order: filter to non-x positions only.
        const vis_order = try para.reorderLine(allocator, 0, para.levels.len);
        defer allocator.free(vis_order);

        var actual_reorder: std.ArrayList(usize) = .empty;
        defer actual_reorder.deinit(allocator);
        for (vis_order) |idx| {
            if (idx < exp_levels.items.len and exp_levels.items[idx] != null) {
                try actual_reorder.append(allocator, idx);
            }
        }

        if (actual_reorder.items.len != exp_reorder.items.len) {
            std.debug.print(
                "BidiCharacterTest.txt line {d}: reorder length expected {d} got {d}\n  codepoints: {s}\n",
                .{ line_no, exp_reorder.items.len, actual_reorder.items.len, cps_raw },
            );
            return error.BidiReorderLengthMismatch;
        }

        for (actual_reorder.items, exp_reorder.items, 0..) |got, want, ri| {
            if (got != want) {
                std.debug.print(
                    "BidiCharacterTest.txt line {d}: reorder[{d}] expected {d} got {d}\n  codepoints: {s}\n",
                    .{ line_no, ri, want, got, cps_raw },
                );
                return error.BidiReorderMismatch;
            }
        }

        tested += 1;
    }

    try testing.expect(tested > 0);
}
