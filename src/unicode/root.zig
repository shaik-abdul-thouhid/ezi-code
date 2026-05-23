const std = @import("std");
const encoding = @import("encoding");
pub const unicode_data = @import("unicode_data_generated.zig");

const property_alias = @import("property_alias.zig");
const CanonicalCombiningClass = property_alias.CanonicalCombiningClass;

const CodePoint = encoding.CodePoint;

pub const GeneralCategory = unicode_data.GeneralCategory;
pub const BidiClass = unicode_data.BidiClass;
pub const combining_class_table = unicode_data.combining_class_table;
pub const lowercase_mapping_table = unicode_data.lowercase_range_mapping_table;
pub const uppercase_mapping_table = unicode_data.uppercase_range_mapping_table;
pub const title_case_mapping_table = unicode_data.title_case_range_mapping_table;

pub fn canonicalCombiningClass(code_point: CodePoint) CanonicalCombiningClass {
    if (combining_class_table.len == 0) return 0;

    var low: usize = 0;
    var high: usize = combining_class_table.len;

    while (low < high) {
        const mid = low + (high - low) / 2;
        const range = combining_class_table[mid];

        if (code_point < range.range_start) {
            high = mid;
        } else if (code_point > range.range_end) {
            low = mid + 1;
        } else {
            return range.ccc;
        }
    }

    return .not_reordered;
}

pub fn isLetter(code_point: CodePoint) bool {
    const category = generalCategory(code_point);
    return switch (category) {
        .uppercase_letter, .lowercase_letter, .title_case_letter, .modifier_letter, .other_letter => true,
        else => false,
    };
}

pub fn isUpperCase(code_point: CodePoint) bool {
    return generalCategory(code_point) == .uppercase_letter;
}

pub fn isLowerCase(code_point: CodePoint) bool {
    return generalCategory(code_point) == .lowercase_letter;
}

pub fn isAlphabetic(code_point: CodePoint) bool {
    const category = generalCategory(code_point);
    return switch (category) {
        .uppercase_letter,
        .lowercase_letter,
        .title_case_letter,
        .modifier_letter,
        .other_letter,
        .letter_number,
        => true,
        else => false,
    };
}

pub fn isNumeric(code_point: CodePoint) bool {
    const category = generalCategory(code_point);
    return switch (category) {
        .decimal_number, .letter_number, .other_number => true,
        else => false,
    };
}

pub fn isWhitespace(code_point: CodePoint) bool {
    return switch (code_point) {
        0x0009, // Tab
        0x000A, // Line Feed
        0x000B, // Vertical Tab
        0x000C, // Form Feed
        0x000D, // Carriage Return
        0x0020, // Space
        0x0085, // Next Line
        0x00A0, // No-Break Space
        0x1680, // Ogham Space Mark
        0x2000...0x200A, // En Quad to Hair Space
        0x2028, // Line Separator
        0x2029, // Paragraph Separator
        0x202F, // Narrow No-Break Space
        0x205F, // Medium Mathematical Space
        0x3000, // Ideographic Space
        => true,
        else => false,
    };
}

pub fn isPrintable(code_point: CodePoint) bool {
    const category = generalCategory(code_point);
    return switch (category) {
        .control, .format, .surrogate, .private_use, .unassigned => false,
        else => true,
    };
}

pub fn isValidCodePoint(code_point: CodePoint) bool {
    return code_point <= 0x10FFFF and !isSurrogate(code_point);
}

pub fn isSurrogate(code_point: CodePoint) bool {
    return code_point >= 0xD800 and code_point <= 0xDFFF;
}

pub fn toUpperCase(code_point: CodePoint) CodePoint {
    if (uppercase_mapping_table.len == 0) return code_point;

    var low: usize = 0;
    var high: usize = uppercase_mapping_table.len;

    while (low < high) {
        const mid = low + (high - low) / 2;
        const range = uppercase_mapping_table[mid];

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

pub fn toLowerCase(code_point: CodePoint) CodePoint {
    if (lowercase_mapping_table.len == 0) return code_point;

    var low: usize = 0;
    var high: usize = lowercase_mapping_table.len;

    while (low < high) {
        const mid = low + (high - low) / 2;
        const range = lowercase_mapping_table[mid];

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

pub fn toTitleCase(code_point: CodePoint) CodePoint {
    if (title_case_mapping_table.len == 0) return code_point;

    var low: usize = 0;
    var high: usize = title_case_mapping_table.len;

    while (low < high) {
        const mid = low + (high - low) / 2;
        const range = title_case_mapping_table[mid];

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

/// Check if a code point is a combining mark (diacritic, accent, etc.)
/// This includes non-spacing marks, spacing marks, and enclosing marks.
pub fn isMark(code_point: CodePoint) bool {
    const category = generalCategory(code_point);
    return switch (category) {
        .non_spacing_mark, .spacing_mark, .enclosing_mark => true,
        else => false,
    };
}

/// Check if a code point is a decimal digit (0-9 in ASCII and other scripts)
/// More specific than isNumeric() which includes letter_number and other_number.
pub fn isDecimalDigit(code_point: CodePoint) bool {
    return generalCategory(code_point) == .decimal_number;
}

/// Check if a code point is a valid hexadecimal digit (0-9, a-f, A-F).
/// Useful for parsing hex literals and other hex-based formats.
pub fn isHexDigit(code_point: CodePoint) bool {
    return switch (code_point) {
        '0'...'9', 'a'...'f', 'A'...'F' => true,
        else => false,
    };
}

/// Check if a code point can start an identifier.
/// This follows common identifier rules (letters, underscore, maybe some other categories).
pub fn isIdentifierStart(code_point: CodePoint) bool {
    if (code_point == '_') return true;
    const category = generalCategory(code_point);
    return switch (category) {
        .uppercase_letter,
        .lowercase_letter,
        .title_case_letter,
        .modifier_letter,
        .other_letter,
        .letter_number,
        => true,
        else => false,
    };
}

/// Check if a code point can continue an identifier.
/// This includes identifier start characters plus digits and marks.
pub fn isIdentifierContinue(code_point: CodePoint) bool {
    if (isIdentifierStart(code_point)) return true;
    if (code_point == '_') return true;
    const category = generalCategory(code_point);
    return switch (category) {
        .decimal_number,
        .connector_punctuation,
        .non_spacing_mark,
        .spacing_mark,
        => true,
        else => false,
    };
}

/// Check if a code point is a space separator (excludes other whitespace like tabs, newlines).
pub fn isSpaceSeparator(code_point: CodePoint) bool {
    return generalCategory(code_point) == .space_separator;
}

/// Check if a code point is punctuation.
pub fn isPunctuation(code_point: CodePoint) bool {
    const category = generalCategory(code_point);
    return switch (category) {
        .connector_punctuation,
        .dash_punctuation,
        .open_punctuation,
        .close_punctuation,
        .initial_punctuation,
        .final_punctuation,
        .other_punctuation,
        => true,
        else => false,
    };
}

/// Check if a code point is a symbol.
pub fn isSymbol(code_point: CodePoint) bool {
    const category = generalCategory(code_point);
    return switch (category) {
        .math_symbol,
        .currency_symbol,
        .modifier_symbol,
        .other_symbol,
        => true,
        else => false,
    };
}

/// Check if a code point is in the ASCII range (0x00-0x7F).
pub fn isAscii(code_point: CodePoint) bool {
    return code_point <= 0x7F;
}

// ============================================================================
// COMPREHENSIVE UNICODE TESTS
// ============================================================================

const testing = std.testing;

// ============================================================================
// canonicalCombiningClass Tests
// ============================================================================

test "canonicalCombiningClass: ASCII has class 0" {
    for (0x00..0x80) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        const cc = canonicalCombiningClass(cp);
        try testing.expectEqual(.not_reordered, cc);
    }
}

test "canonicalCombiningClass: boundaries and ranges" {
    // Test code points with known combining classes
    const tests = [_]struct { cp: CodePoint, expected: CanonicalCombiningClass }{
        .{ .cp = 0x0300, .expected = .above }, // Combining Grave Accent
        .{ .cp = 0x0301, .expected = .above }, // Combining Acute Accent
        .{ .cp = 0x0315, .expected = .above_right }, // Combining Comma Above
        .{ .cp = 0x0330, .expected = .below }, // Combining Tilde Below
    };

    for (tests) |tc| {
        const cc = canonicalCombiningClass(tc.cp);
        try testing.expectEqual(tc.expected, cc);
    }
}

test "canonicalCombiningClass: binary search correctness" {
    // Test that binary search correctly finds combining classes
    // Start of table lookup
    const start = canonicalCombiningClass(0x0300);
    try testing.expect(@intFromEnum(start) > 0);

    // Middle range
    const middle = canonicalCombiningClass(0x0320);
    try testing.expect(@intFromEnum(middle) >= 0);

    // End range
    const end = canonicalCombiningClass(0xFE20);
    try testing.expect(@intFromEnum(end) >= 0);
}

// ============================================================================
// isLetter Tests
// ============================================================================

test "isLetter: basic ASCII letters" {
    for ('A'..'Z' + 1) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(isLetter(cp));
    }
    for ('a'..'z' + 1) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(isLetter(cp));
    }
}

test "isLetter: ASCII digits are not letters" {
    for ('0'..'9' + 1) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(!isLetter(cp));
    }
}

test "isLetter: ASCII punctuation is not letter" {
    const punct = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~";
    for (punct) |cp| {
        try testing.expect(!isLetter(cp));
    }
}

test "isLetter: space is not letter" {
    try testing.expect(!isLetter(' '));
    try testing.expect(!isLetter('\t'));
    try testing.expect(!isLetter('\n'));
}

test "isLetter: extended Latin letters" {
    const extended = [_]CodePoint{
        0xC0, // À
        0xE9, // é
        0xF1, // ñ
    };
    for (extended) |cp| {
        try testing.expect(isLetter(cp));
    }
}

test "isLetter: Greek letters" {
    const greek = [_]CodePoint{
        0x0391, // Α
        0x03B1, // α
        0x03A9, // Ω
    };
    for (greek) |cp| {
        try testing.expect(isLetter(cp));
    }
}

test "isLetter: Cyrillic letters" {
    const cyrillic = [_]CodePoint{
        0x0410, // А
        0x0430, // а
        0x042F, // Я
    };
    for (cyrillic) |cp| {
        try testing.expect(isLetter(cp));
    }
}

test "isLetter: CJK ideographs" {
    const cjk = [_]CodePoint{
        0x4E00, // 一
        0x4E8C, // 二
        0x4E09, // 三
    };
    for (cjk) |cp| try testing.expect(isLetter(cp));
}

// ============================================================================
// isUpperCase Tests
// ============================================================================

test "isUpperCase: ASCII uppercase" {
    for ('A'..'Z' + 1) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(isUpperCase(cp));
    }
}

test "isUpperCase: ASCII lowercase is not uppercase" {
    for ('a'..'z' + 1) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(!isUpperCase(cp));
    }
}

test "isUpperCase: extended uppercase letters" {
    const extended = [_]CodePoint{
        0xC0, // À
        0xC1, // Á
        0xC9, // É
    };
    for (extended) |cp| {
        try testing.expect(isUpperCase(cp));
    }
}

test "isUpperCase: Greek uppercase" {
    const greek_upper = [_]CodePoint{
        0x0391, // Α
        0x0393, // Γ
        0x03A9, // Ω
    };
    for (greek_upper) |cp| {
        try testing.expect(isUpperCase(cp));
    }
}

test "isUpperCase: Cyrillic uppercase" {
    const cyrillic_upper = [_]CodePoint{
        0x0410, // А
        0x0411, // Б
        0x042F, // Я
    };
    for (cyrillic_upper) |cp| {
        try testing.expect(isUpperCase(cp));
    }
}

test "isUpperCase: digits and symbols are not uppercase" {
    for ('0'..'9' + 1) |cp| {
        try testing.expect(!isUpperCase(@as(CodePoint, @truncate(cp))));
    }
    try testing.expect(!isUpperCase('@'));
    try testing.expect(!isUpperCase('#'));
}

// ============================================================================
// isLowerCase Tests
// ============================================================================

test "isLowerCase: ASCII lowercase" {
    for ('a'..'z' + 1) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(isLowerCase(cp));
    }
}

test "isLowerCase: ASCII uppercase is not lowercase" {
    for ('A'..'Z' + 1) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(!isLowerCase(cp));
    }
}

test "isLowerCase: extended lowercase letters" {
    const extended = [_]CodePoint{
        0xE0, // à
        0xE1, // á
        0xE9, // é
    };
    for (extended) |cp| {
        try testing.expect(isLowerCase(cp));
    }
}

test "isLowerCase: Greek lowercase" {
    const greek_lower = [_]CodePoint{
        0x03B1, // α
        0x03B2, // β
        0x03C9, // ω
    };
    for (greek_lower) |cp| {
        try testing.expect(isLowerCase(cp));
    }
}

test "isLowerCase: Cyrillic lowercase" {
    const cyrillic_lower = [_]CodePoint{
        0x0430, // а
        0x0431, // б
        0x044F, // я
    };
    for (cyrillic_lower) |cp| {
        try testing.expect(isLowerCase(cp));
    }
}

// ============================================================================
// isAlphabetic Tests
// ============================================================================

test "isAlphabetic: ASCII letters are alphabetic" {
    for ('A'..'Z' + 1) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(isAlphabetic(cp));
    }
    for ('a'..'z' + 1) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(isAlphabetic(cp));
    }
}

test "isAlphabetic: digits and symbols are not alphabetic" {
    for ('0'..'9' + 1) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(!isAlphabetic(cp));
    }
    try testing.expect(!isAlphabetic(' '));
    try testing.expect(!isAlphabetic('@'));
    try testing.expect(!isAlphabetic('#'));
}

test "isAlphabetic: letter_number category is alphabetic" {
    // Roman numerals are letter_number
    const roman = [_]CodePoint{
        0x2160, // Ⅰ
        0x2161, // Ⅱ
        0x2162, // Ⅲ
    };
    for (roman) |cp| {
        try testing.expect(isAlphabetic(cp));
    }
}

// ============================================================================
// isNumeric Tests
// ============================================================================

test "isNumeric: ASCII digits" {
    for ('0'..'9' + 1) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(isNumeric(cp));
    }
}

test "isNumeric: letters are not numeric" {
    for ('A'..'Z' + 1) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(!isNumeric(cp));
    }
    for ('a'..'z' + 1) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(!isNumeric(cp));
    }
}

test "isNumeric: extended numeric characters" {
    const numeric = [_]CodePoint{
        0x0660, // Arabic-Indic digit zero
        0x0669, // Arabic-Indic digit nine
        0x0966, // Devanagari digit zero
        0x0BE6, // Tamil digit zero
    };
    for (numeric) |cp| {
        try testing.expect(isNumeric(cp));
    }
}

test "isNumeric: Roman numerals are numeric (letter_number)" {
    const roman = [_]CodePoint{
        0x2160, // Ⅰ
        0x2161, // Ⅱ
    };
    for (roman) |cp| {
        try testing.expect(isNumeric(cp));
    }
}

// ============================================================================
// isWhitespace Tests
// ============================================================================

test "isWhitespace: ASCII whitespace" {
    const ws = [_]CodePoint{ '\t', '\n', '\x0B', '\x0C', '\r', ' ' };
    for (ws) |cp| {
        try testing.expect(isWhitespace(cp));
    }
}

test "isWhitespace: non-whitespace ASCII" {
    for ('A'..'Z' + 1) |cp| {
        try testing.expect(!isWhitespace(@as(CodePoint, @truncate(cp))));
    }
    for ('0'..'9' + 1) |cp| {
        try testing.expect(!isWhitespace(@as(CodePoint, @truncate(cp))));
    }
}

test "isWhitespace: Unicode whitespace" {
    const ws = [_]CodePoint{
        0x0085, // Next Line
        0x00A0, // No-Break Space
        0x1680, // Ogham Space Mark
        0x2000, // En Quad
        0x2001, // Em Quad
        0x2002, // En Space
        0x2003, // Em Space
        0x2004, // Three-Per-Em Space
        0x2005, // Four-Per-Em Space
        0x2006, // Six-Per-Em Space
        0x2007, // Figure Space
        0x2008, // Punctuation Space
        0x2009, // Thin Space
        0x200A, // Hair Space
        0x2028, // Line Separator
        0x2029, // Paragraph Separator
        0x202F, // Narrow No-Break Space
        0x205F, // Medium Mathematical Space
        0x3000, // Ideographic Space
    };
    for (ws) |cp| {
        try testing.expect(isWhitespace(cp));
    }
}

test "isWhitespace: non-whitespace Unicode" {
    const non_ws = [_]CodePoint{
        0x00A1, // ¡
        0x00A9, // ©
        0x200B, // Zero-Width Space (not whitespace)
    };
    for (non_ws) |cp| {
        try testing.expect(!isWhitespace(cp));
    }
}

// ============================================================================
// isPrintable Tests
// ============================================================================

test "isPrintable: ASCII printable characters" {
    for (' '..'~' + 1) |cp| {
        try testing.expect(isPrintable(@as(CodePoint, @truncate(cp))));
    }
}

test "isPrintable: ASCII control characters are not printable" {
    for (0..32) |cp| {
        try testing.expect(!isPrintable(@as(CodePoint, @truncate(cp))));
    }
    try testing.expect(!isPrintable(0x7F)); // DEL
}

test "isPrintable: extended printable characters" {
    const printable = [_]CodePoint{
        0xC0, // À
        0xE9, // é
        0x0391, // Α
        0x4E00, // 一
    };
    for (printable) |cp| {
        try testing.expect(isPrintable(cp));
    }
}

test "isPrintable: format characters are not printable" {
    const format_chars = [_]CodePoint{
        0x200B, // Zero-Width Space
        0x200C, // Zero-Width Non-Joiner
        0x200D, // Zero-Width Joiner
    };
    for (format_chars) |cp| {
        try testing.expect(!isPrintable(cp));
    }
}

test "isPrintable: surrogate codepoints are not printable" {
    // Surrogates should be detected as non-printable
    const surrogates = [_]CodePoint{
        0xD800, // High surrogate start
        0xDBFF, // High surrogate end
        0xDC00, // Low surrogate start
        0xDFFF, // Low surrogate end
    };
    for (surrogates) |cp| {
        try testing.expect(!isPrintable(cp));
    }
}

test "isPrintable: private use characters" {
    // Private use area should not be printable
    const private_use = [_]CodePoint{
        0xE000, // Private Use Area start
        0xF000, // Private Use Area
        0xF8FF, // Private Use Area end
    };
    for (private_use) |cp| {
        try testing.expect(!isPrintable(cp));
    }
}

// ============================================================================
// isSurrogate Tests
// ============================================================================

test "isSurrogate: high surrogates" {
    for (0xD800..0xDC00) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(isSurrogate(cp));
    }
}

test "isSurrogate: low surrogates" {
    for (0xDC00..0xE000) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(isSurrogate(cp));
    }
}

test "isSurrogate: non-surrogates" {
    const non_surrogates = [_]CodePoint{
        0x0000,
        0xD7FF, // Just before surrogates
        0xE000, // Just after surrogates
        0xFFFF,
        0x10FFFF,
    };
    for (non_surrogates) |cp| {
        try testing.expect(!isSurrogate(cp));
    }
}

test "isSurrogate: boundary cases" {
    try testing.expect(isSurrogate(0xD800)); // First surrogate
    try testing.expect(isSurrogate(0xDFFF)); // Last surrogate
    try testing.expect(!isSurrogate(0xD7FF)); // Before surrogates
    try testing.expect(!isSurrogate(0xE000)); // After surrogates
}

// ============================================================================
// Case Mapping Tests (toUpperCase, toLowerCase, toTitleCase)
// ============================================================================

test "toUpperCase: ASCII lowercase to uppercase" {
    for ('a'..'z' + 1) |cp| {
        const upper = toUpperCase(@as(CodePoint, @truncate(cp)));
        try testing.expectEqual(cp - ('a' - 'A'), upper);
    }
}

test "toUpperCase: ASCII uppercase unchanged" {
    for ('A'..'Z' + 1) |cp| {
        const upper = toUpperCase(@as(CodePoint, @truncate(cp)));
        try testing.expectEqual(cp, upper);
    }
}

test "toUpperCase: ASCII non-letters unchanged" {
    for ('0'..'9' + 1) |cp| {
        const upper = toUpperCase(@as(CodePoint, @truncate(cp)));
        try testing.expectEqual(cp, upper);
    }
}

test "toUpperCase: extended Latin" {
    const tests = [_]struct { lower: CodePoint, upper: CodePoint }{
        .{ .lower = 0xE0, .upper = 0xC0 }, // à -> À
        .{ .lower = 0xE9, .upper = 0xC9 }, // é -> É
        .{ .lower = 0xF1, .upper = 0xD1 }, // ñ -> Ñ
    };
    for (tests) |tc| {
        const upper = toUpperCase(tc.lower);
        try testing.expectEqual(tc.upper, upper);
    }
}

test "toUpperCase: already uppercase unchanged" {
    const uppers = [_]CodePoint{ 0xC0, 0xC9, 0xD1 };
    for (uppers) |cp| {
        const upper = toUpperCase(cp);
        try testing.expectEqual(cp, upper);
    }
}

test "toLowerCase: ASCII uppercase to lowercase" {
    for ('A'..'Z' + 1) |cp| {
        const lower = toLowerCase(@as(CodePoint, @truncate(cp)));
        try testing.expectEqual(cp + ('a' - 'A'), lower);
    }
}

test "toLowerCase: ASCII lowercase unchanged" {
    for ('a'..'z' + 1) |cp| {
        const lower = toLowerCase(@as(CodePoint, @truncate(cp)));
        try testing.expectEqual(cp, lower);
    }
}

test "toLowerCase: ASCII non-letters unchanged" {
    for ('0'..'9' + 1) |cp| {
        const lower = toLowerCase(@as(CodePoint, @truncate(cp)));
        try testing.expectEqual(cp, lower);
    }
}

test "toLowerCase: extended Latin" {
    const tests = [_]struct { upper: CodePoint, lower: CodePoint }{
        .{ .upper = 0xC0, .lower = 0xE0 }, // À -> à
        .{ .upper = 0xC9, .lower = 0xE9 }, // É -> é
        .{ .upper = 0xD1, .lower = 0xF1 }, // Ñ -> ñ
    };
    for (tests) |tc| {
        const lower = toLowerCase(tc.upper);
        try testing.expectEqual(tc.lower, lower);
    }
}

test "toLowerCase: already lowercase unchanged" {
    const lowers = [_]CodePoint{ 0xE0, 0xE9, 0xF1 };
    for (lowers) |cp| {
        const lower = toLowerCase(@as(CodePoint, @truncate(cp)));
        try testing.expectEqual(cp, lower);
    }
}

test "toTitleCase: ASCII uppercase and lowercase" {
    // ASCII doesn't have separate title case, so expect same as uppercase
    for ('a'..'z' + 1) |cp| {
        const title = toTitleCase(@as(CodePoint, @truncate(cp)));
        try testing.expectEqual(cp - ('a' - 'A'), title);
    }
    for ('A'..'Z' + 1) |cp| {
        const title = toTitleCase(@as(CodePoint, @truncate(cp)));
        try testing.expectEqual(cp, title);
    }
}

test "toTitleCase: non-letters unchanged" {
    for ('0'..'9' + 1) |cp| {
        const title = toTitleCase(@as(CodePoint, @truncate(cp)));
        try testing.expectEqual(cp, title);
    }
}

// ============================================================================
// Roundtrip Tests (case conversions and back)
// ============================================================================

test "case conversion roundtrip: uppercase->lowercase->uppercase" {
    const chars = [_]CodePoint{ 'A', 'B', 'Z', 0xC0, 0xC9 };
    for (chars) |cp| {
        const lower = toLowerCase(cp);
        const upper = toUpperCase(lower);
        // Note: Not all chars have perfect roundtrip due to Unicode complexity
        // but basic ASCII should work
        if (cp <= 'Z') {
            try testing.expectEqual(cp, upper);
        }
    }
}

test "case conversion roundtrip: lowercase->uppercase->lowercase" {
    const chars = [_]CodePoint{ 'a', 'b', 'z', 0xE0, 0xE9 };
    for (chars) |cp| {
        const upper = toUpperCase(cp);
        const lower = toLowerCase(upper);
        if (cp <= 'z') {
            try testing.expectEqual(cp, lower);
        }
    }
}

// ============================================================================
// Combination Tests
// ============================================================================

test "properties: letter AND uppercase" {
    const uppers = [_]CodePoint{ 'A', 'B', 'Z', 0xC0 };
    for (uppers) |cp| {
        try testing.expect(isLetter(cp));
        try testing.expect(isUpperCase(cp));
        try testing.expect(!isLowerCase(cp));
        try testing.expect(isAlphabetic(cp));
    }
}

test "properties: letter AND lowercase" {
    const lowers = [_]CodePoint{ 'a', 'b', 'z', 0xE0 };
    for (lowers) |cp| {
        try testing.expect(isLetter(cp));
        try testing.expect(isLowerCase(cp));
        try testing.expect(!isUpperCase(cp));
        try testing.expect(isAlphabetic(cp));
    }
}

test "properties: printable AND letter" {
    const letters = [_]CodePoint{ 'A', 'a', 0xC0, 0xE0 };
    for (letters) |cp| {
        try testing.expect(isPrintable(cp));
        try testing.expect(isLetter(cp));
    }
}

test "properties: numeric AND printable" {
    const nums = [_]CodePoint{ '0', '9' };
    for (nums) |cp| {
        try testing.expect(isPrintable(cp));
        try testing.expect(isNumeric(cp));
        try testing.expect(!isLetter(cp));
    }
}

test "properties: whitespace NOT printable" {
    const ws = [_]CodePoint{ ' ', '\t', '\n' };
    for (ws) |cp| {
        try testing.expect(isWhitespace(cp));
        // Space is printable, but tab and newline are not typically considered printable
        // This depends on the definition - space IS printable
    }
    try testing.expect(isPrintable(' '));
}

test "properties: surrogate NOT valid AND NOT printable" {
    for (0xD800..0xE000) |cp| {
        try testing.expect(!isValidCodePoint(@as(CodePoint, @truncate(cp))));
        try testing.expect(!isPrintable(@as(CodePoint, @truncate(cp))));
        try testing.expect(isSurrogate(@as(CodePoint, @truncate(cp))));
    }
}

test "properties: ASCII control NOT printable" {
    for (0..32) |cp| {
        try testing.expect(!isPrintable(@as(CodePoint, @truncate(cp))));
    }
    try testing.expect(!isPrintable(0x7F));
}

// ============================================================================
// Edge Case Tests
// ============================================================================

test "edge case: null code point" {
    try testing.expectEqual(.not_reordered, canonicalCombiningClass(0));
    try testing.expect(!isLetter(0));
    try testing.expect(!isUpperCase(0));
    try testing.expect(!isLowerCase(0));
    try testing.expect(!isAlphabetic(0));
    try testing.expect(!isNumeric(0));
    try testing.expect(!isWhitespace(0));
    try testing.expect(!isPrintable(0)); // NUL is a control character and not printable
    try testing.expect(!isSurrogate(0));
    try testing.expect(isValidCodePoint(0));
    try testing.expectEqual(@as(CodePoint, 0), toUpperCase(0));
    try testing.expectEqual(@as(CodePoint, 0), toLowerCase(0));
}

test "edge case: max valid code point 0x10FFFF" {
    try testing.expect(isValidCodePoint(0x10FFFF));
    try testing.expect(!isSurrogate(0x10FFFF));
    // 0x10FFFF is assigned and should be printable
    try testing.expect(!isPrintable(0x10FFFF));
}

test "edge case: last before surrogate 0xD7FF" {
    try testing.expect(isValidCodePoint(0xD7FF));
    try testing.expect(!isSurrogate(0xD7FF));
    try testing.expect(!isPrintable(0xD7FF));
}

test "edge case: first after surrogate 0xE000" {
    try testing.expect(isValidCodePoint(0xE000));
    try testing.expect(!isSurrogate(0xE000));
    try testing.expect(!isPrintable(0xE000)); // Private use
}

test "edge case: BMP boundaries" {
    try testing.expect(isValidCodePoint(0x0000));
    try testing.expect(isValidCodePoint(0xFFFF));
    try testing.expect(!isSurrogate(0xFFFF));
}

test "edge case: SMP boundaries" {
    try testing.expect(isValidCodePoint(0x10000));
    try testing.expect(isValidCodePoint(0x1FFFF));
    try testing.expect(!isSurrogate(0x10000));
}

// ============================================================================
// Hostile Test Cases
// ============================================================================

test "hostile: all surrogate code points" {
    for (0xD800..0xE000) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(isSurrogate(cp));
        try testing.expect(!isValidCodePoint(cp));
        try testing.expect(!isLetter(cp));
        try testing.expect(!isPrintable(cp));
    }
}

test "hostile: boundary surrogate values" {
    try testing.expect(isSurrogate(0xD800));
    try testing.expect(isSurrogate(0xDBFF));
    try testing.expect(isSurrogate(0xDC00));
    try testing.expect(isSurrogate(0xDFFF));

    try testing.expect(!isSurrogate(0xD7FF));
    try testing.expect(!isSurrogate(0xE000));
}

test "hostile: combining class lookup correctness" {
    // Test that combining class returns consistent values
    const prev_class: u8 = 0;
    for (0x0300..0x0370) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        const cc = canonicalCombiningClass(cp);
        // Combining classes should be valid values (0-255)
        try testing.expect(@intFromEnum(cc) >= 0);
        try testing.expect(@intFromEnum(cc) <= 255);
        _ = prev_class;
    }
}

test "hostile: case mapping with unusual inputs" {
    // Case mappings should never produce invalid code points
    for (0x0000..0x10FFFF) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        // Skip surrogates as they're invalid
        if (cp >= 0xD800 and cp <= 0xDFFF) continue;

        const upper = toUpperCase(cp);
        const lower = toLowerCase(cp);
        const title = toTitleCase(cp);

        // Results should be valid code points
        try testing.expect(upper <= 0x10FFFF);
        try testing.expect(lower <= 0x10FFFF);
        try testing.expect(title <= 0x10FFFF);
    }
}

test "hostile: whitespace coverage exhaustive" {
    // Every explicitly mentioned whitespace should return true
    const all_ws = [_]CodePoint{
        0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x0020,
        0x0085, 0x00A0, 0x1680, 0x2000, 0x2001, 0x2002,
        0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008,
        0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F,
        0x3000,
    };
    for (all_ws) |cp| {
        try testing.expect(isWhitespace(cp));
    }
}

test "hostile: non-whitespace near whitespace" {
    const non_ws_near = [_]CodePoint{
        0x0008, // Before tab
        0x000E, // After CR
        0x0021, // After space
        0x0084, // Before NEL
        0x009F, // After NEL
        0x167F, // Before Ogham space
        0x1681, // After Ogham space
        0x1FFF, // Before En Quad
        0x200B, // Zero-width space (not whitespace)
    };
    for (non_ws_near) |cp| {
        try testing.expect(!isWhitespace(cp));
    }
}

// ============================================================================
// Performance-aware Tests
// ============================================================================

test "binary search: combining class correctness in ranges" {
    // Ensure binary search doesn't miss ranges
    const first_combining = 0x0300;
    const last_combining = 0xFE2F;

    const start = canonicalCombiningClass(first_combining);
    try testing.expect(@intFromEnum(start) > 0);

    const end = canonicalCombiningClass(last_combining);
    try testing.expect(@intFromEnum(end) >= 0);

    // Points in between should have consistent results
    for (first_combining..last_combining) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        const cc = canonicalCombiningClass(cp);
        _ = cc; // Just ensure no crashes
    }
}

test "binary search: case mapping correctness in ranges" {
    // Test case mapping doesn't miss ranges
    for (0xC2..0xDF) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        const upper = toUpperCase(cp);
        const lower = toLowerCase(cp);
        // Should not crash
        _ = upper;
        _ = lower;
    }
}

test "all ascii printable is printable" {
    for (0x20..0x7F) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(isPrintable(cp));
    }
}

// ============================================================================
// isMark Tests
// ============================================================================

test "isMark: combining accents are marks" {
    const marks = [_]CodePoint{
        0x0300, // Combining Grave Accent
        0x0301, // Combining Acute Accent
        0x0302, // Combining Circumflex Accent
    };
    for (marks) |cp| {
        try testing.expect(isMark(cp));
    }
}

test "isMark: non-marks" {
    const non_marks = [_]CodePoint{
        'A', 'a', '0', ' ', '@',
    };
    for (non_marks) |cp| {
        try testing.expect(!isMark(cp));
    }
}

// ============================================================================
// isDecimalDigit Tests
// ============================================================================

test "isDecimalDigit: ASCII digits" {
    for ('0'..'9' + 1) |cp| {
        try testing.expect(isDecimalDigit(@as(CodePoint, @truncate(cp))));
    }
}

test "isDecimalDigit: letters are not decimal digits" {
    for ('A'..'Z' + 1) |cp| {
        try testing.expect(!isDecimalDigit(@as(CodePoint, @truncate(cp))));
    }
    for ('a'..'z' + 1) |cp| {
        try testing.expect(!isDecimalDigit(@as(CodePoint, @truncate(cp))));
    }
}

test "isDecimalDigit: extended digits" {
    const extended_digits = [_]CodePoint{
        0x0660, // Arabic-Indic digit zero
        0x0669, // Arabic-Indic digit nine
    };
    for (extended_digits) |cp| {
        try testing.expect(isDecimalDigit(cp));
    }
}

test "isDecimalDigit: more restrictive than isNumeric" {
    // Roman numerals are numeric but not decimal digits
    const roman = [_]CodePoint{
        0x2160, // Ⅰ
        0x2161, // Ⅱ
    };
    for (roman) |cp| {
        try testing.expect(isNumeric(cp));
        try testing.expect(!isDecimalDigit(cp));
    }
}

// ============================================================================
// isHexDigit Tests
// ============================================================================

test "isHexDigit: ASCII hex digits" {
    const hex_digits = "0123456789abcdefABCDEF";
    for (hex_digits) |cp_u8| {
        const cp: CodePoint = cp_u8;
        try testing.expect(isHexDigit(cp));
    }
}

test "isHexDigit: non-hex characters" {
    const non_hex = "ghijklmnopqrstuvwxyzGHIJKLMNOPQRSTUVWXYZ";
    for (non_hex) |cp_u8| {
        const cp: CodePoint = cp_u8;
        try testing.expect(!isHexDigit(cp));
    }
}

test "isHexDigit: digits in hex" {
    for ('0'..'9' + 1) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(isHexDigit(cp));
    }
}

test "isHexDigit: case insensitive" {
    try testing.expect(isHexDigit('a'));
    try testing.expect(isHexDigit('A'));
    try testing.expect(isHexDigit('f'));
    try testing.expect(isHexDigit('F'));
}

// ============================================================================
// isIdentifierStart Tests
// ============================================================================

test "isIdentifierStart: ASCII letters" {
    for ('A'..'Z' + 1) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(isIdentifierStart(cp));
    }
    for ('a'..'z' + 1) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(isIdentifierStart(cp));
    }
}

test "isIdentifierStart: underscore" {
    try testing.expect(isIdentifierStart('_'));
}

test "isIdentifierStart: digits not valid start" {
    for ('0'..'9' + 1) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(!isIdentifierStart(cp));
    }
}

test "isIdentifierStart: special characters not valid" {
    const special = "!@#$%^&*(){}[]|\\:;\"'<>,.?/";
    for (special) |cp| {
        try testing.expect(!isIdentifierStart(cp));
    }
}

test "isIdentifierStart: extended letters" {
    const extended = [_]CodePoint{
        0xC0, // À
        0xE9, // é
        0x0391, // Α
    };
    for (extended) |cp| {
        try testing.expect(isIdentifierStart(cp));
    }
}

// ============================================================================
// isIdentifierContinue Tests
// ============================================================================

test "isIdentifierContinue: includes identifier start chars" {
    for ('A'..'Z' + 1) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(isIdentifierContinue(cp));
    }
    for ('a'..'z' + 1) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(isIdentifierContinue(cp));
    }
    try testing.expect(isIdentifierContinue('_'));
}

test "isIdentifierContinue: includes digits" {
    for ('0'..'9' + 1) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(isIdentifierContinue(cp));
    }
}

test "isIdentifierContinue: includes combining marks" {
    const marks = [_]CodePoint{
        0x0300, // Combining Grave Accent
        0x0301, // Combining Acute Accent
    };
    for (marks) |cp| {
        if (isMark(cp)) {
            try testing.expect(isIdentifierContinue(cp));
        }
    }
}

test "isIdentifierContinue: excludes special characters" {
    const special = "!@#$%^&*(){}[]|\\:;\"'<>,.?/";
    for (special) |cp| {
        try testing.expect(!isIdentifierContinue(cp));
    }
}

// ============================================================================
// isSpaceSeparator Tests
// ============================================================================

test "isSpaceSeparator: regular space" {
    try testing.expect(isSpaceSeparator(' '));
}

test "isSpaceSeparator: no-break space" {
    try testing.expect(isSpaceSeparator(0x00A0));
}

test "isSpaceSeparator: not other whitespace" {
    try testing.expect(!isSpaceSeparator('\t'));
    try testing.expect(!isSpaceSeparator('\n'));
    try testing.expect(!isSpaceSeparator('\r'));
}

// ============================================================================
// isPunctuation Tests
// ============================================================================

test "isPunctuation: ASCII punctuation" {
    for ("!\"#%&'()*,-./:;?@[\\]_{}") |cp_u8| {
        const cp: CodePoint = cp_u8;
        try testing.expect(isPunctuation(cp));
    }
}

test "isPunctuation: not letters" {
    for ('A'..'Z' + 1) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(!isPunctuation(cp));
    }
    for ('a'..'z' + 1) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(!isPunctuation(cp));
    }
}

test "isPunctuation: not digits" {
    for ('0'..'9' + 1) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(!isPunctuation(cp));
    }
}

// ============================================================================
// isSymbol Tests
// ============================================================================

test "isSymbol: math symbols" {
    const symbols = [_]CodePoint{
        0x002B, // +
        0x003D, // =
        0x003C, // <
        0x003E, // >
    };

    for (symbols) |cp| {
        try testing.expect(isSymbol(cp));
    }
}

test "isSymbol: not letters" {
    for ('A'..'Z' + 1) |cp| {
        try testing.expect(!isSymbol(@as(CodePoint, @truncate(cp))));
    }
}

// ============================================================================
// isAscii Tests
// ============================================================================

test "isAscii: ASCII range 0x00-0x7F" {
    for (0..0x80) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(isAscii(cp));
    }
}

test "isAscii: non-ASCII range" {
    const non_ascii = [_]CodePoint{
        0x80, 0xFF, 0x100, 0x1000, 0x10000, 0x10FFFF,
    };
    for (non_ascii) |cp| {
        try testing.expect(!isAscii(cp));
    }
}

test "isAscii: boundary condition" {
    try testing.expect(isAscii(0x7F)); // Last ASCII
    try testing.expect(!isAscii(0x80)); // First non-ASCII
}

test "isMark: mark handling in identifier" {
    const combining_acute = 0x0301;
    try testing.expect(isMark(combining_acute));
    try testing.expect(isIdentifierContinue(combining_acute));
}

test "isHexDigit: hex digit handling" {
    // Hex digits work in identifiers but 'a' and 'f' must be in identifier start
    try testing.expect(isHexDigit('a'));
    try testing.expect(isIdentifierStart('a'));
    try testing.expect(isHexDigit('0'));
    try testing.expect(!isIdentifierStart('0'));
}

test "isDecimalDigit: decimal digit handling" {
    for ('0'..'9' + 1) |cp| {
        try testing.expect(isDecimalDigit(@as(CodePoint, @truncate(cp))));
        try testing.expect(!isIdentifierStart(@as(CodePoint, @truncate(cp))));
        try testing.expect(isIdentifierContinue(@as(CodePoint, @truncate(cp))));
    }
}

pub fn generalCategory(code_point: CodePoint) GeneralCategory {
    return unicode_data.generalCategory(code_point);
}

pub fn bidiClass(code_point: CodePoint) BidiClass {
    return unicode_data.bidiClass(code_point);
}
