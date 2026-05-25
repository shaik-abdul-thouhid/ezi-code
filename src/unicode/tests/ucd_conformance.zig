const std = @import("std");
const encoding = @import("encoding");

const unicode_data = @import("../generated/unicode_data.zig");
const derived = @import("../properties/generated/derived_core_properties.zig");
const prop_list = @import("../properties/generated/prop_list.zig");
const case_folding = @import("../casing/generated/case_folding.zig");
const special_casing = @import("../casing/generated/special_casing.zig");
const unicode_types = @import("../types.zig");

const CodePoint = encoding.CodePoint;
const testing = std.testing;

const unicode_data_path = "ucd/UnicodeData.txt";
const derived_core_properties_path = "ucd/DerivedCoreProperties.txt";
const prop_list_path = "ucd/PropList.txt";
const case_folding_path = "ucd/CaseFolding.txt";
const special_casing_path = "ucd/SpecialCasing.txt";

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
    var low: usize = 0;
    var high: usize = table.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const range = table[mid];
        if (cp < range.start) {
            high = mid;
        } else if (cp > range.end) {
            low = mid + 1;
        } else {
            return @intCast(@as(i32, @intCast(cp)) + range.delta);
        }
    }
    return cp;
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
    var low: usize = 0;
    var high: usize = unicode_data.combining_class_table.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const range = unicode_data.combining_class_table[mid];
        if (cp < range.range_start) {
            high = mid;
        } else if (cp > range.range_end) {
            low = mid + 1;
        } else {
            return range.ccc;
        }
    }
    return .not_reordered;
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
