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
const segmentation = @import("../segmentation/root.zig");
const unicode_types = @import("../types.zig");

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
const sentence_break_property_path = "ucd/SentenceBreakProperty.txt";
const line_break_path = "ucd/LineBreak.txt";
const east_asian_width_path = "ucd/EastAsianWidth.txt";
const emoji_data_path = "ucd/emoji-data.txt";

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
    const entry = utils.searchRange(
        @TypeOf(unicode_data.combining_class_table[0]),
        CodePoint,
        "range_start",
        "range_end",
        &unicode_data.combining_class_table,
        cp,
    ) orelse return .not_reordered;
    return entry.ccc;
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
