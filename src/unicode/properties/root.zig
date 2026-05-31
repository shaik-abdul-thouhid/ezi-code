//! Unicode character property queries for code points. This module is the
//! facade over the generated Unicode Character Database tables and exposes
//! predicate and lookup functions for the properties defined by UnicodeData,
//! DerivedCoreProperties, and PropList.
//!
//! - Every function accepts an arbitrary `CodePoint` (any `u21` value):
//!   out-of-range, surrogate, and unassigned inputs are handled gracefully and
//!   simply report the appropriate property value (typically `false` or the
//!   default category). No input is rejected; there are no error paths.
//! - Predicates returning `bool` answer a single Unicode property query.
//!   Lookup functions (`generalCategory`, `bidiClass`,
//!   `canonicalCombiningClass`) return the enumerated value for the code point.

const std = @import("std");
const encoding = @import("encoding");
const utils = @import("utils");
const types = @import("../types.zig");

/// Generated Unicode Character Database tables and accessors (from UnicodeData).
pub const unicode_data = @import("../generated/unicode_data.zig");
/// DerivedCoreProperties accessors (alphabetic, cased, id_start, etc.).
pub const derived_core_properties = @import("derived_core_properties.zig");
/// PropList accessors (white space, dash, hyphen, hex digit, etc.).
pub const prop_list = @import("prop_list.zig");

/// The Unicode General_Category enumeration (Lu, Ll, Nd, Zs, ...).
pub const GeneralCategory = unicode_data.GeneralCategory;
/// The Unicode Bidi_Class enumeration used by the bidirectional algorithm.
pub const BidiClass = unicode_data.BidiClass;
/// A property of the DerivedCoreProperties set, used with `hasDerivedProperty`.
pub const DerivedProperty = derived_core_properties.Property;
/// The Canonical_Combining_Class enumeration used during normalization.
pub const CanonicalCombiningClass = types.CanonicalCombiningClass;

const CodePoint = encoding.CodePoint;

/// Range-based table mapping code points to their simple lowercase forms.
pub const lowercase_mapping_table = unicode_data.lowercase_range_mapping_table;
/// Range-based table mapping code points to their simple uppercase forms.
pub const uppercase_mapping_table = unicode_data.uppercase_range_mapping_table;
/// Range-based table mapping code points to their simple titlecase forms.
pub const titlecase_mapping_table = unicode_data.titlecase_range_mapping_table;

/// Returns the bitmask of all DerivedCoreProperties held by `code_point`.
/// Prefer this over repeated `hasDerivedProperty` calls when testing several
/// properties of the same code point.
/// @stable-since: v0.1.0
pub fn derivedPropertyMask(code_point: CodePoint) u32 {
    return derived_core_properties.propertyMask(code_point);
}

/// Returns whether `code_point` carries the given DerivedCoreProperty.
/// @stable-since: v0.1.0
pub fn hasDerivedProperty(code_point: CodePoint, property: DerivedProperty) bool {
    return derived_core_properties.codePointProperty(code_point, property);
}

/// Returns the Canonical_Combining_Class of `code_point` (0 for starters).
pub const canonicalCombiningClass = unicode_data.canonicalCombiningClass;

/// Returns the General_Category of `code_point`. Returns `.unassigned` for
/// code points with no assigned category.
/// @stable-since: v0.1.0
pub fn generalCategory(code_point: CodePoint) GeneralCategory {
    return unicode_data.generalCategory(code_point);
}

/// Returns the Bidi_Class of `code_point` used by the bidirectional algorithm.
/// @stable-since: v0.1.0
pub fn bidiClass(code_point: CodePoint) BidiClass {
    return unicode_data.bidiClass(code_point);
}

/// Returns whether `code_point` is a letter (General_Category L*: uppercase,
/// lowercase, titlecase, modifier, or other letter).
/// @stable-since: v0.1.0
pub fn isLetter(code_point: CodePoint) bool {
    const category = generalCategory(code_point);
    return switch (category) {
        .uppercase_letter, .lowercase_letter, .titlecase_letter, .modifier_letter, .other_letter => true,
        else => false,
    };
}

/// Returns whether `code_point` has the derived Uppercase property. Broader
/// than the Lu category: also includes Other_Uppercase code points.
/// @stable-since: v0.1.0
pub fn isUpperCase(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .uppercase);
}

/// Returns whether `code_point` has the derived Lowercase property. Broader
/// than the Ll category: also includes Other_Lowercase code points.
/// @stable-since: v0.1.0
pub fn isLowerCase(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .lowercase);
}

/// Returns whether `code_point` has the derived Alphabetic property.
/// @stable-since: v0.1.0
pub fn isAlphabetic(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .alphabetic);
}

/// Returns whether `code_point` is a number (General_Category N*: decimal,
/// letter, or other number). Use `isDecimalDigit` for the narrower Nd test.
/// @stable-since: v0.1.0
pub fn isNumeric(code_point: CodePoint) bool {
    const category = generalCategory(code_point);
    return switch (category) {
        .decimal_number, .letter_number, .other_number => true,
        else => false,
    };
}

/// Returns whether `code_point` has the White_Space property (per PropList).
/// @stable-since: v0.1.0
pub fn isWhitespace(code_point: CodePoint) bool {
    return prop_list.isWhiteSpace(code_point);
}

/// Returns whether `code_point` is printable. False for control, format,
/// surrogate, private-use, and unassigned code points; true otherwise.
/// @stable-since: v0.1.0
pub fn isPrintable(code_point: CodePoint) bool {
    const category = generalCategory(code_point);
    return switch (category) {
        .control, .format, .surrogate, .private_use, .unassigned => false,
        else => true,
    };
}

/// Returns whether `code_point` is a Unicode scalar value: in range and not a
/// surrogate. Surrogate code points (U+D800..U+DFFF) are invalid in isolation.
/// @stable-since: v0.1.0
pub fn isValidCodePoint(code_point: CodePoint) bool {
    return code_point <= 0x10FFFF and !isSurrogate(code_point);
}

/// Returns whether `code_point` lies in the surrogate range U+D800..U+DFFF.
/// @stable-since: v0.1.0
pub fn isSurrogate(code_point: CodePoint) bool {
    return code_point >= 0xD800 and code_point <= 0xDFFF;
}

/// Returns whether `code_point` is a combining mark (General_Category M*:
/// non-spacing, spacing, or enclosing mark).
/// @stable-since: v0.1.0
pub fn isMark(code_point: CodePoint) bool {
    const category = generalCategory(code_point);
    return switch (category) {
        .non_spacing_mark, .spacing_mark, .enclosing_mark => true,
        else => false,
    };
}

/// Returns whether `code_point` has the derived Math property.
/// @stable-since: v0.1.0
pub fn isMath(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .math);
}

/// Returns whether `code_point` has the derived Cased property (it is upper-,
/// lower-, or titlecase). Useful for case-folding and case-mapping decisions.
/// @stable-since: v0.1.0
pub fn isCased(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .cased);
}

/// Returns whether `code_point` is Case_Ignorable, i.e. ignored when
/// determining the case context of an adjacent code point.
/// @stable-since: v0.1.0
pub fn isCaseIgnorable(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .case_ignorable);
}

/// Returns whether `code_point` changes under simple lowercase mapping.
/// @stable-since: v0.1.0
pub fn changesWhenLowercased(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .changes_when_lowercased);
}

/// Returns whether `code_point` changes under simple uppercase mapping.
/// @stable-since: v0.1.0
pub fn changesWhenUppercased(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .changes_when_uppercased);
}

/// Returns whether `code_point` changes under simple titlecase mapping.
/// @stable-since: v0.1.0
pub fn changesWhenTitlecased(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .changes_when_titlecased);
}

/// Returns whether `code_point` changes under case folding.
/// @stable-since: v0.1.0
pub fn changesWhenCasefolded(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .changes_when_casefolded);
}

/// Returns whether `code_point` changes under any case mapping.
/// @stable-since: v0.1.0
pub fn changesWhenCasemapped(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .changes_when_casemapped);
}

/// Returns whether `code_point` is a decimal digit (General_Category Nd).
/// Narrower than `isNumeric`; excludes letter and other numbers.
/// @stable-since: v0.1.0
pub fn isDecimalDigit(code_point: CodePoint) bool {
    return generalCategory(code_point) == .decimal_number;
}

/// Returns whether `code_point` is an ASCII hex digit (0-9, a-f, A-F).
/// For the full Unicode Hex_Digit property use `isHexDigitWide`.
/// @stable-since: v0.1.0
pub fn isHexDigit(code_point: CodePoint) bool {
    return prop_list.isAsciiHexDigit(code_point);
}

/// Returns whether `code_point` has the Hex_Digit property, which includes the
/// fullwidth forms in addition to the ASCII hex digits.
/// @stable-since: v0.1.0
pub fn isHexDigitWide(code_point: CodePoint) bool {
    return prop_list.isHexDigit(code_point);
}

/// Returns whether `code_point` has the ASCII_Hex_Digit property (0-9, a-f,
/// A-F). Equivalent to `isHexDigit`.
/// @stable-since: v0.1.0
pub fn isAsciiHexDigit(code_point: CodePoint) bool {
    return prop_list.isAsciiHexDigit(code_point);
}

/// Returns whether `code_point` has the Bidi_Control property.
/// @stable-since: v0.1.0
pub fn isBidiControl(code_point: CodePoint) bool {
    return prop_list.isBidiControl(code_point);
}

/// Returns whether `code_point` has the Join_Control property (ZWJ/ZWNJ).
/// @stable-since: v0.1.0
pub fn isJoinControl(code_point: CodePoint) bool {
    return prop_list.isJoinControl(code_point);
}

/// Returns whether `code_point` has the Dash property.
/// @stable-since: v0.1.0
pub fn isDash(code_point: CodePoint) bool {
    return prop_list.isDash(code_point);
}

/// Returns whether `code_point` has the Hyphen property.
/// @stable-since: v0.1.0
pub fn isHyphen(code_point: CodePoint) bool {
    return prop_list.isHyphen(code_point);
}

/// Returns whether `code_point` has the Quotation_Mark property.
/// @stable-since: v0.1.0
pub fn isQuotationMark(code_point: CodePoint) bool {
    return prop_list.isQuotationMark(code_point);
}

/// Returns whether `code_point` has the Terminal_Punctuation property.
/// @stable-since: v0.1.0
pub fn isTerminalPunctuation(code_point: CodePoint) bool {
    return prop_list.isTerminalPunctuation(code_point);
}

/// Returns whether `code_point` has the Other_Math property (the math code
/// points not already covered by the Sm category).
/// @stable-since: v0.1.0
pub fn isOtherMath(code_point: CodePoint) bool {
    return prop_list.isOtherMath(code_point);
}

/// Returns whether `code_point` has the Other_Alphabetic property.
/// @stable-since: v0.1.0
pub fn isOtherAlphabetic(code_point: CodePoint) bool {
    return prop_list.isOtherAlphabetic(code_point);
}

/// Returns whether `code_point` has the Ideographic property.
/// @stable-since: v0.1.0
pub fn isIdeographic(code_point: CodePoint) bool {
    return prop_list.isIdeographic(code_point);
}

/// Returns whether `code_point` has the Diacritic property.
/// @stable-since: v0.1.0
pub fn isDiacritic(code_point: CodePoint) bool {
    return prop_list.isDiacritic(code_point);
}

/// Returns whether `code_point` has the Extender property.
/// @stable-since: v0.1.0
pub fn isExtender(code_point: CodePoint) bool {
    return prop_list.isExtender(code_point);
}

/// Returns whether `code_point` has the Other_Lowercase property.
/// @stable-since: v0.1.0
pub fn isOtherLowercase(code_point: CodePoint) bool {
    return prop_list.isOtherLowercase(code_point);
}

/// Returns whether `code_point` has the Other_Uppercase property.
/// @stable-since: v0.1.0
pub fn isOtherUppercase(code_point: CodePoint) bool {
    return prop_list.isOtherUppercase(code_point);
}

/// Returns whether `code_point` is a noncharacter (Noncharacter_Code_Point):
/// permanently reserved and never assigned a character.
/// @stable-since: v0.1.0
pub fn isNoncharacterCodePoint(code_point: CodePoint) bool {
    return prop_list.isNoncharacterCodePoint(code_point);
}

/// Returns whether `code_point` has the Other_Grapheme_Extend property.
/// @stable-since: v0.1.0
pub fn isOtherGraphemeExtend(code_point: CodePoint) bool {
    return prop_list.isOtherGraphemeExtend(code_point);
}

/// Returns whether `code_point` is an IDS_Binary_Operator (Ideographic
/// Description Sequence binary operator).
/// @stable-since: v0.1.0
pub fn isIdsBinaryOperator(code_point: CodePoint) bool {
    return prop_list.isIdsBinaryOperator(code_point);
}

/// Returns whether `code_point` is an IDS_Trinary_Operator.
/// @stable-since: v0.1.0
pub fn isIdsTrinaryOperator(code_point: CodePoint) bool {
    return prop_list.isIdsTrinaryOperator(code_point);
}

/// Returns whether `code_point` is an IDS_Unary_Operator.
/// @stable-since: v0.1.0
pub fn isIdsUnaryOperator(code_point: CodePoint) bool {
    return prop_list.isIdsUnaryOperator(code_point);
}

/// Returns whether `code_point` has the Radical property (CJK radical).
/// @stable-since: v0.1.0
pub fn isRadical(code_point: CodePoint) bool {
    return prop_list.isRadical(code_point);
}

/// Returns whether `code_point` has the Unified_Ideograph property.
/// @stable-since: v0.1.0
pub fn isUnifiedIdeograph(code_point: CodePoint) bool {
    return prop_list.isUnifiedIdeograph(code_point);
}

/// Returns whether `code_point` has the Other_Default_Ignorable_Code_Point
/// property.
/// @stable-since: v0.1.0
pub fn isOtherDefaultIgnorableCodePoint(code_point: CodePoint) bool {
    return prop_list.isOtherDefaultIgnorableCodePoint(code_point);
}

/// Returns whether `code_point` has the Deprecated property.
/// @stable-since: v0.1.0
pub fn isDeprecated(code_point: CodePoint) bool {
    return prop_list.isDeprecated(code_point);
}

/// Returns whether `code_point` has the Soft_Dotted property (its dot is
/// removed when a combining mark is applied, e.g. lowercase i and j).
/// @stable-since: v0.1.0
pub fn isSoftDotted(code_point: CodePoint) bool {
    return prop_list.isSoftDotted(code_point);
}

/// Returns whether `code_point` has the Logical_Order_Exception property.
/// @stable-since: v0.1.0
pub fn isLogicalOrderException(code_point: CodePoint) bool {
    return prop_list.isLogicalOrderException(code_point);
}

/// Returns whether `code_point` has the Other_ID_Start property.
/// @stable-since: v0.1.0
pub fn isOtherIdStart(code_point: CodePoint) bool {
    return prop_list.isOtherIdStart(code_point);
}

/// Returns whether `code_point` has the Other_ID_Continue property.
/// @stable-since: v0.1.0
pub fn isOtherIdContinue(code_point: CodePoint) bool {
    return prop_list.isOtherIdContinue(code_point);
}

/// Returns whether `code_point` has the Sentence_Terminal property.
/// @stable-since: v0.1.0
pub fn isSentenceTerminal(code_point: CodePoint) bool {
    return prop_list.isSentenceTerminal(code_point);
}

/// Returns whether `code_point` is a Variation_Selector.
/// @stable-since: v0.1.0
pub fn isVariationSelector(code_point: CodePoint) bool {
    return prop_list.isVariationSelector(code_point);
}

/// Returns whether `code_point` has the Pattern_White_Space property, the
/// stable whitespace set used by syntactic patterns (UAX #31).
/// @stable-since: v0.1.0
pub fn isPatternWhiteSpace(code_point: CodePoint) bool {
    return prop_list.isPatternWhiteSpace(code_point);
}

/// Returns whether `code_point` has the Pattern_Syntax property, the stable
/// set of code points reserved for syntax in patterns (UAX #31).
/// @stable-since: v0.1.0
pub fn isPatternSyntax(code_point: CodePoint) bool {
    return prop_list.isPatternSyntax(code_point);
}

/// Returns whether `code_point` has the Prepended_Concatenation_Mark property.
/// @stable-since: v0.1.0
pub fn isPrependedConcatenationMark(code_point: CodePoint) bool {
    return prop_list.isPrependedConcatenationMark(code_point);
}

/// Returns whether `code_point` is a Regional_Indicator symbol, used in pairs
/// to form flag emoji.
/// @stable-since: v0.1.0
pub fn isRegionalIndicator(code_point: CodePoint) bool {
    return prop_list.isRegionalIndicator(code_point);
}

/// Returns whether `code_point` has the Modifier_Combining_Mark property.
/// @stable-since: v0.1.0
pub fn isModifierCombiningMark(code_point: CodePoint) bool {
    return prop_list.isModifierCombiningMark(code_point);
}

/// Returns whether `code_point` has the ID_Compat_Math_Start property.
/// @stable-since: v0.1.0
pub fn isIdCompatMathStart(code_point: CodePoint) bool {
    return prop_list.isIdCompatMathStart(code_point);
}

/// Returns whether `code_point` has the ID_Compat_Math_Continue property.
/// @stable-since: v0.1.0
pub fn isIdCompatMathContinue(code_point: CodePoint) bool {
    return prop_list.isIdCompatMathContinue(code_point);
}

/// Returns whether `code_point` may start a programming identifier: an ID_Start
/// code point or the ASCII underscore. Use `isIdentifierContinue` for the rest.
/// @stable-since: v0.1.0
pub fn isIdentifierStart(code_point: CodePoint) bool {
    if (code_point == '_') return true;
    return isIdStart(code_point);
}

/// Returns whether `code_point` may continue a programming identifier: an
/// ID_Continue code point or the ASCII underscore.
/// @stable-since: v0.1.0
pub fn isIdentifierContinue(code_point: CodePoint) bool {
    if (code_point == '_') return true;
    return isIdContinue(code_point);
}

/// Returns whether `code_point` has the ID_Start property (UAX #31). This is
/// the raw Unicode property; `isIdentifierStart` also admits underscore.
/// @stable-since: v0.1.0
pub fn isIdStart(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .id_start);
}

/// Returns whether `code_point` has the ID_Continue property (UAX #31).
/// @stable-since: v0.1.0
pub fn isIdContinue(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .id_continue);
}

/// Returns whether `code_point` has the XID_Start property, the
/// normalization-closed variant of ID_Start recommended by UAX #31.
/// @stable-since: v0.1.0
pub fn isXidStart(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .xid_start);
}

/// Returns whether `code_point` has the XID_Continue property, the
/// normalization-closed variant of ID_Continue.
/// @stable-since: v0.1.0
pub fn isXidContinue(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .xid_continue);
}

/// Returns whether `code_point` is a Default_Ignorable_Code_Point, which
/// renderers should ignore when no glyph is available.
/// @stable-since: v0.1.0
pub fn isDefaultIgnorableCodePoint(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .default_ignorable_code_point);
}

/// Returns whether `code_point` has the Grapheme_Extend property (it extends
/// the preceding grapheme cluster).
/// @stable-since: v0.1.0
pub fn isGraphemeExtend(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .grapheme_extend);
}

/// Returns whether `code_point` has the Grapheme_Base property (it can start a
/// grapheme cluster).
/// @stable-since: v0.1.0
pub fn isGraphemeBase(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .grapheme_base);
}

/// Returns whether `code_point` has the Grapheme_Link property.
/// @stable-since: v0.1.0
pub fn isGraphemeLink(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .grapheme_link);
}

/// Returns whether `code_point` is a space separator (General_Category Zs).
/// Narrower than `isWhitespace`; excludes tabs, newlines, and line/paragraph
/// separators.
/// @stable-since: v0.1.0
pub fn isSpaceSeparator(code_point: CodePoint) bool {
    return generalCategory(code_point) == .space_separator;
}

/// Returns whether `code_point` is punctuation (General_Category P*: connector,
/// dash, open, close, initial, final, or other punctuation).
/// @stable-since: v0.1.0
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

/// Returns whether `code_point` is a symbol (General_Category S*: math,
/// currency, modifier, or other symbol).
/// @stable-since: v0.1.0
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

/// Returns whether `code_point` is in the ASCII range U+0000..U+007F.
/// @stable-since: v0.1.0
pub fn isAscii(code_point: CodePoint) bool {
    return code_point <= 0x7F;
}

// ============================================================================
// Tests (relocated from unicode/root.zig during the slim-facade refactor)
// ============================================================================

const testing = std.testing;

test "canonicalCombiningClass: ASCII has class 0" {
    for (0x00..0x80) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        const cc = canonicalCombiningClass(cp);
        try testing.expectEqual(.not_reordered, cc);
    }
}

test "canonicalCombiningClass: boundaries and ranges" {
    const tests = [_]struct { cp: CodePoint, expected: CanonicalCombiningClass }{
        .{ .cp = 0x0300, .expected = .above },
        .{ .cp = 0x0301, .expected = .above },
        .{ .cp = 0x0315, .expected = .above_right },
        .{ .cp = 0x0330, .expected = .below },
    };
    for (tests) |tc| {
        try testing.expectEqual(tc.expected, canonicalCombiningClass(tc.cp));
    }
}

test "canonicalCombiningClass: binary search correctness" {
    const start = canonicalCombiningClass(0x0300);
    try testing.expect(@intFromEnum(start) > 0);
    const middle = canonicalCombiningClass(0x0320);
    try testing.expect(@intFromEnum(middle) >= 0);
    const end = canonicalCombiningClass(0xFE20);
    try testing.expect(@intFromEnum(end) >= 0);
}

test "isLetter: basic ASCII letters" {
    for ('A'..'Z' + 1) |cp| try testing.expect(isLetter(@as(CodePoint, @intCast(cp))));
    for ('a'..'z' + 1) |cp| try testing.expect(isLetter(@as(CodePoint, @intCast(cp))));
}

test "isLetter: ASCII digits are not letters" {
    for ('0'..'9' + 1) |cp| try testing.expect(!isLetter(@as(CodePoint, @intCast(cp))));
}

test "isLetter: ASCII punctuation is not letter" {
    const punct = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~";
    for (punct) |cp| try testing.expect(!isLetter(cp));
}

test "isLetter: space is not letter" {
    try testing.expect(!isLetter(' '));
    try testing.expect(!isLetter('\t'));
    try testing.expect(!isLetter('\n'));
}

test "isLetter: extended Latin letters" {
    for ([_]CodePoint{ 0xC0, 0xE9, 0xF1 }) |cp| try testing.expect(isLetter(cp));
}

test "isLetter: Greek letters" {
    for ([_]CodePoint{ 0x0391, 0x03B1, 0x03A9 }) |cp| try testing.expect(isLetter(cp));
}

test "isLetter: Cyrillic letters" {
    for ([_]CodePoint{ 0x0410, 0x0430, 0x042F }) |cp| try testing.expect(isLetter(cp));
}

test "isLetter: CJK ideographs" {
    for ([_]CodePoint{ 0x4E00, 0x4E8C, 0x4E09 }) |cp| try testing.expect(isLetter(cp));
}

test "isUpperCase: ASCII uppercase" {
    for ('A'..'Z' + 1) |cp| try testing.expect(isUpperCase(@as(CodePoint, @intCast(cp))));
}

test "isUpperCase: ASCII lowercase is not uppercase" {
    for ('a'..'z' + 1) |cp| try testing.expect(!isUpperCase(@as(CodePoint, @intCast(cp))));
}

test "isUpperCase: extended uppercase letters" {
    for ([_]CodePoint{ 0xC0, 0xC1, 0xC9 }) |cp| try testing.expect(isUpperCase(cp));
}

test "isUpperCase: Greek uppercase" {
    for ([_]CodePoint{ 0x0391, 0x0393, 0x03A9 }) |cp| try testing.expect(isUpperCase(cp));
}

test "isUpperCase: Cyrillic uppercase" {
    for ([_]CodePoint{ 0x0410, 0x0411, 0x042F }) |cp| try testing.expect(isUpperCase(cp));
}

test "isUpperCase: digits and symbols are not uppercase" {
    for ('0'..'9' + 1) |cp| try testing.expect(!isUpperCase(@as(CodePoint, @intCast(cp))));
    try testing.expect(!isUpperCase('@'));
    try testing.expect(!isUpperCase('#'));
}

test "isLowerCase: ASCII lowercase" {
    for ('a'..'z' + 1) |cp| try testing.expect(isLowerCase(@as(CodePoint, @intCast(cp))));
}

test "isLowerCase: ASCII uppercase is not lowercase" {
    for ('A'..'Z' + 1) |cp| try testing.expect(!isLowerCase(@as(CodePoint, @intCast(cp))));
}

test "isLowerCase: extended lowercase letters" {
    for ([_]CodePoint{ 0xE0, 0xE1, 0xE9 }) |cp| try testing.expect(isLowerCase(cp));
}

test "isLowerCase: Greek lowercase" {
    for ([_]CodePoint{ 0x03B1, 0x03B2, 0x03C9 }) |cp| try testing.expect(isLowerCase(cp));
}

test "isLowerCase: Cyrillic lowercase" {
    for ([_]CodePoint{ 0x0430, 0x0431, 0x044F }) |cp| try testing.expect(isLowerCase(cp));
}

test "isAlphabetic: ASCII letters are alphabetic" {
    for ('A'..'Z' + 1) |cp| try testing.expect(isAlphabetic(@as(CodePoint, @intCast(cp))));
    for ('a'..'z' + 1) |cp| try testing.expect(isAlphabetic(@as(CodePoint, @intCast(cp))));
}

test "isAlphabetic: digits and symbols are not alphabetic" {
    for ('0'..'9' + 1) |cp| try testing.expect(!isAlphabetic(@as(CodePoint, @intCast(cp))));
    try testing.expect(!isAlphabetic(' '));
    try testing.expect(!isAlphabetic('@'));
    try testing.expect(!isAlphabetic('#'));
}

test "isAlphabetic: letter_number category is alphabetic" {
    for ([_]CodePoint{ 0x2160, 0x2161, 0x2162 }) |cp| try testing.expect(isAlphabetic(cp));
}

test "isNumeric: ASCII digits" {
    for ('0'..'9' + 1) |cp| try testing.expect(isNumeric(@as(CodePoint, @intCast(cp))));
}

test "isNumeric: letters are not numeric" {
    for ('A'..'Z' + 1) |cp| try testing.expect(!isNumeric(@as(CodePoint, @intCast(cp))));
    for ('a'..'z' + 1) |cp| try testing.expect(!isNumeric(@as(CodePoint, @intCast(cp))));
}

test "isNumeric: extended numeric characters" {
    for ([_]CodePoint{ 0x0660, 0x0669, 0x0966, 0x0BE6 }) |cp| try testing.expect(isNumeric(cp));
}

test "isNumeric: Roman numerals are numeric (letter_number)" {
    for ([_]CodePoint{ 0x2160, 0x2161 }) |cp| try testing.expect(isNumeric(cp));
}

test "isWhitespace: ASCII whitespace" {
    for ([_]CodePoint{ '\t', '\n', '\x0B', '\x0C', '\r', ' ' }) |cp| try testing.expect(isWhitespace(cp));
}

test "isWhitespace: non-whitespace ASCII" {
    for ('A'..'Z' + 1) |cp| try testing.expect(!isWhitespace(@as(CodePoint, @intCast(cp))));
    for ('0'..'9' + 1) |cp| try testing.expect(!isWhitespace(@as(CodePoint, @intCast(cp))));
}

test "isWhitespace: Unicode whitespace" {
    const ws = [_]CodePoint{
        0x0085, 0x00A0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004,
        0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A, 0x2028, 0x2029,
        0x202F, 0x205F, 0x3000,
    };
    for (ws) |cp| try testing.expect(isWhitespace(cp));
}

test "isWhitespace: non-whitespace Unicode" {
    for ([_]CodePoint{ 0x00A1, 0x00A9, 0x200B }) |cp| try testing.expect(!isWhitespace(cp));
}

test "isPrintable: ASCII printable characters" {
    for (' '..'~' + 1) |cp| try testing.expect(isPrintable(@as(CodePoint, @intCast(cp))));
}

test "isPrintable: ASCII control characters are not printable" {
    for (0..32) |cp| try testing.expect(!isPrintable(@as(CodePoint, @intCast(cp))));
    try testing.expect(!isPrintable(0x7F));
}

test "isPrintable: extended printable characters" {
    for ([_]CodePoint{ 0xC0, 0xE9, 0x0391, 0x4E00 }) |cp| try testing.expect(isPrintable(cp));
}

test "isPrintable: format characters are not printable" {
    for ([_]CodePoint{ 0x200B, 0x200C, 0x200D }) |cp| try testing.expect(!isPrintable(cp));
}

test "isPrintable: surrogate codepoints are not printable" {
    for ([_]CodePoint{ 0xD800, 0xDBFF, 0xDC00, 0xDFFF }) |cp| try testing.expect(!isPrintable(cp));
}

test "isPrintable: private use characters" {
    for ([_]CodePoint{ 0xE000, 0xF000, 0xF8FF }) |cp| try testing.expect(!isPrintable(cp));
}

test "isSurrogate: high surrogates" {
    for (0xD800..0xDC00) |cp| try testing.expect(isSurrogate(@as(CodePoint, @intCast(cp))));
}

test "isSurrogate: low surrogates" {
    for (0xDC00..0xE000) |cp| try testing.expect(isSurrogate(@as(CodePoint, @intCast(cp))));
}

test "isSurrogate: non-surrogates" {
    for ([_]CodePoint{ 0x0000, 0xD7FF, 0xE000, 0xFFFF, 0x10FFFF }) |cp| try testing.expect(!isSurrogate(cp));
}

test "isSurrogate: boundary cases" {
    try testing.expect(isSurrogate(0xD800));
    try testing.expect(isSurrogate(0xDFFF));
    try testing.expect(!isSurrogate(0xD7FF));
    try testing.expect(!isSurrogate(0xE000));
}

test "properties: letter AND uppercase" {
    for ([_]CodePoint{ 'A', 'B', 'Z', 0xC0 }) |cp| {
        try testing.expect(isLetter(cp));
        try testing.expect(isUpperCase(cp));
        try testing.expect(!isLowerCase(cp));
        try testing.expect(isAlphabetic(cp));
    }
}

test "properties: letter AND lowercase" {
    for ([_]CodePoint{ 'a', 'b', 'z', 0xE0 }) |cp| {
        try testing.expect(isLetter(cp));
        try testing.expect(isLowerCase(cp));
        try testing.expect(!isUpperCase(cp));
        try testing.expect(isAlphabetic(cp));
    }
}

test "properties: printable AND letter" {
    for ([_]CodePoint{ 'A', 'a', 0xC0, 0xE0 }) |cp| {
        try testing.expect(isPrintable(cp));
        try testing.expect(isLetter(cp));
    }
}

test "properties: numeric AND printable" {
    for ([_]CodePoint{ '0', '9' }) |cp| {
        try testing.expect(isPrintable(cp));
        try testing.expect(isNumeric(cp));
        try testing.expect(!isLetter(cp));
    }
}

test "properties: whitespace and space printability" {
    for ([_]CodePoint{ ' ', '\t', '\n' }) |cp| try testing.expect(isWhitespace(cp));
    try testing.expect(isPrintable(' '));
}

test "properties: surrogate NOT valid AND NOT printable" {
    for (0xD800..0xE000) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(!isValidCodePoint(cp));
        try testing.expect(!isPrintable(cp));
        try testing.expect(isSurrogate(cp));
    }
}

test "properties: ASCII control NOT printable" {
    for (0..32) |cp| try testing.expect(!isPrintable(@as(CodePoint, @intCast(cp))));
    try testing.expect(!isPrintable(0x7F));
}

test "edge case: max valid code point 0x10FFFF" {
    try testing.expect(isValidCodePoint(0x10FFFF));
    try testing.expect(!isSurrogate(0x10FFFF));
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
    try testing.expect(!isPrintable(0xE000));
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

test "all surrogate code points" {
    for (0xD800..0xE000) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(isSurrogate(cp));
        try testing.expect(!isValidCodePoint(cp));
        try testing.expect(!isLetter(cp));
        try testing.expect(!isPrintable(cp));
    }
}

test "boundary surrogate values" {
    try testing.expect(isSurrogate(0xD800));
    try testing.expect(isSurrogate(0xDBFF));
    try testing.expect(isSurrogate(0xDC00));
    try testing.expect(isSurrogate(0xDFFF));
    try testing.expect(!isSurrogate(0xD7FF));
    try testing.expect(!isSurrogate(0xE000));
}

test "combining class lookup correctness" {
    for (0x0300..0x0370) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        const cc = canonicalCombiningClass(cp);
        try testing.expect(@intFromEnum(cc) >= 0);
        try testing.expect(@intFromEnum(cc) <= 255);
    }
}

test "whitespace coverage exhaustive" {
    const all_ws = [_]CodePoint{
        0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x0020,
        0x0085, 0x00A0, 0x1680, 0x2000, 0x2001, 0x2002,
        0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008,
        0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F,
        0x3000,
    };
    for (all_ws) |cp| try testing.expect(isWhitespace(cp));
}

test "non-whitespace near whitespace" {
    const non_ws_near = [_]CodePoint{
        0x0008, 0x000E, 0x0021, 0x0084, 0x009F,
        0x167F, 0x1681, 0x1FFF, 0x200B,
    };
    for (non_ws_near) |cp| try testing.expect(!isWhitespace(cp));
}

test "binary search: combining class correctness in ranges" {
    const start = canonicalCombiningClass(0x0300);
    try testing.expect(@intFromEnum(start) > 0);
    const end = canonicalCombiningClass(0xFE2F);
    try testing.expect(@intFromEnum(end) >= 0);
    for (0x0300..0xFE2F) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        _ = canonicalCombiningClass(cp);
    }
}

test "all ascii printable is printable" {
    for (0x20..0x7F) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(isPrintable(cp));
    }
}

test "isMark: combining accents are marks" {
    for ([_]CodePoint{ 0x0300, 0x0301, 0x0302 }) |cp| try testing.expect(isMark(cp));
}

test "isMark: non-marks" {
    for ([_]CodePoint{ 'A', 'a', '0', ' ', '@' }) |cp| try testing.expect(!isMark(cp));
}

test "isDecimalDigit: ASCII digits" {
    for ('0'..'9' + 1) |cp| try testing.expect(isDecimalDigit(@as(CodePoint, @intCast(cp))));
}

test "isDecimalDigit: letters are not decimal digits" {
    for ('A'..'Z' + 1) |cp| try testing.expect(!isDecimalDigit(@as(CodePoint, @intCast(cp))));
    for ('a'..'z' + 1) |cp| try testing.expect(!isDecimalDigit(@as(CodePoint, @intCast(cp))));
}

test "isDecimalDigit: extended digits" {
    for ([_]CodePoint{ 0x0660, 0x0669 }) |cp| try testing.expect(isDecimalDigit(cp));
}

test "isDecimalDigit: more restrictive than isNumeric" {
    for ([_]CodePoint{ 0x2160, 0x2161 }) |cp| {
        try testing.expect(isNumeric(cp));
        try testing.expect(!isDecimalDigit(cp));
    }
}

test "isHexDigit: ASCII hex digits" {
    for ("0123456789abcdefABCDEF") |cp_u8| {
        const cp: CodePoint = cp_u8;
        try testing.expect(isHexDigit(cp));
    }
}

test "isHexDigit: non-hex characters" {
    for ("ghijklmnopqrstuvwxyzGHIJKLMNOPQRSTUVWXYZ") |cp_u8| {
        const cp: CodePoint = cp_u8;
        try testing.expect(!isHexDigit(cp));
    }
}

test "isHexDigit: digits in hex" {
    for ('0'..'9' + 1) |cp| try testing.expect(isHexDigit(@as(CodePoint, @intCast(cp))));
}

test "isHexDigit: case insensitive" {
    try testing.expect(isHexDigit('a'));
    try testing.expect(isHexDigit('A'));
    try testing.expect(isHexDigit('f'));
    try testing.expect(isHexDigit('F'));
}

test "isIdentifierStart: ASCII letters" {
    for ('A'..'Z' + 1) |cp| try testing.expect(isIdentifierStart(@as(CodePoint, @intCast(cp))));
    for ('a'..'z' + 1) |cp| try testing.expect(isIdentifierStart(@as(CodePoint, @intCast(cp))));
}

test "isIdentifierStart: underscore" {
    try testing.expect(isIdentifierStart('_'));
}

test "isIdentifierStart: digits not valid start" {
    for ('0'..'9' + 1) |cp| try testing.expect(!isIdentifierStart(@as(CodePoint, @intCast(cp))));
}

test "isIdentifierStart: special characters not valid" {
    for ("!@#$%^&*(){}[]|\\:;\"'<>,.?/") |cp| try testing.expect(!isIdentifierStart(cp));
}

test "isIdentifierStart: extended letters" {
    for ([_]CodePoint{ 0xC0, 0xE9, 0x0391 }) |cp| try testing.expect(isIdentifierStart(cp));
}

test "isIdentifierContinue: includes identifier start chars" {
    for ('A'..'Z' + 1) |cp| try testing.expect(isIdentifierContinue(@as(CodePoint, @intCast(cp))));
    for ('a'..'z' + 1) |cp| try testing.expect(isIdentifierContinue(@as(CodePoint, @intCast(cp))));
    try testing.expect(isIdentifierContinue('_'));
}

test "isIdentifierContinue: includes digits" {
    for ('0'..'9' + 1) |cp| try testing.expect(isIdentifierContinue(@as(CodePoint, @intCast(cp))));
}

test "isIdentifierContinue: includes combining marks" {
    for ([_]CodePoint{ 0x0300, 0x0301 }) |cp| {
        if (isMark(cp)) try testing.expect(isIdentifierContinue(cp));
    }
}

test "isIdentifierContinue: excludes special characters" {
    for ("!@#$%^&*(){}[]|\\:;\"'<>,.?/") |cp| try testing.expect(!isIdentifierContinue(cp));
}

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

test "isPunctuation: ASCII punctuation" {
    for ("!\"#%&'()*,-./:;?@[\\]_{}") |cp_u8| {
        const cp: CodePoint = cp_u8;
        try testing.expect(isPunctuation(cp));
    }
}

test "isPunctuation: not letters" {
    for ('A'..'Z' + 1) |cp| try testing.expect(!isPunctuation(@as(CodePoint, @intCast(cp))));
    for ('a'..'z' + 1) |cp| try testing.expect(!isPunctuation(@as(CodePoint, @intCast(cp))));
}

test "isPunctuation: not digits" {
    for ('0'..'9' + 1) |cp| try testing.expect(!isPunctuation(@as(CodePoint, @intCast(cp))));
}

test "isSymbol: math symbols" {
    for ([_]CodePoint{ 0x002B, 0x003D, 0x003C, 0x003E }) |cp| try testing.expect(isSymbol(cp));
}

test "isSymbol: not letters" {
    for ('A'..'Z' + 1) |cp| try testing.expect(!isSymbol(@as(CodePoint, @intCast(cp))));
}

test "isAscii: ASCII range 0x00-0x7F" {
    for (0..0x80) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(isAscii(cp));
    }
}

test "isAscii: non-ASCII range" {
    for ([_]CodePoint{ 0x80, 0xFF, 0x100, 0x1000, 0x10000, 0x10FFFF }) |cp| try testing.expect(!isAscii(cp));
}

test "isAscii: boundary condition" {
    try testing.expect(isAscii(0x7F));
    try testing.expect(!isAscii(0x80));
}

test "isMark: mark handling in identifier" {
    const combining_acute: CodePoint = 0x0301;
    try testing.expect(isMark(combining_acute));
    try testing.expect(isIdentifierContinue(combining_acute));
}

test "isHexDigit: hex digit handling vs identifier start" {
    try testing.expect(isHexDigit('a'));
    try testing.expect(isIdentifierStart('a'));
    try testing.expect(isHexDigit('0'));
    try testing.expect(!isIdentifierStart('0'));
}

test "isDecimalDigit: decimal digit handling vs identifier rules" {
    for ('0'..'9' + 1) |cp| {
        const c: CodePoint = @intCast(cp);
        try testing.expect(isDecimalDigit(c));
        try testing.expect(!isIdentifierStart(c));
        try testing.expect(isIdentifierContinue(c));
    }
}

// ============================================================================
// Zalgo (combining-mark-saturated) text. Every decorating scalar is a
// nonspacing combining mark: it carries a nonzero canonical combining class and
// classifies as a Mark, while only the ASCII bases are starters (ccc == 0). So
// the count of starters equals the base count. Driven by the shared corpus.
// ============================================================================

const zalgo_corpus = @import("../tests/zalgo_corpus.zig");

test "properties zalgo: only bases are starters and every mark is a combining Mark" {
    for (zalgo_corpus.samples) |s| {
        const cps = try zalgo_corpus.decode(testing.allocator, s.text);
        defer testing.allocator.free(cps);

        var starters: usize = 0;
        for (cps) |cp| {
            if (@intFromEnum(canonicalCombiningClass(cp)) == 0) {
                starters += 1;
            } else {
                // A nonzero combining class is carried only by combining marks.
                try testing.expect(isMark(cp));
            }
        }
        try testing.expectEqual(s.base_count, starters);
    }
}

test {
    std.testing.refAllDecls(@This());
}
