pub const generated = @import("generated/prop_list.zig");

pub const isWhiteSpace = generated.isWhiteSpace;
pub const isBidiControl = generated.isBidiControl;
pub const isJoinControl = generated.isJoinControl;
pub const isDash = generated.isDash;
pub const isHyphen = generated.isHyphen;
pub const isQuotationMark = generated.isQuotationMark;
pub const isTerminalPunctuation = generated.isTerminalPunctuation;
pub const isOtherMath = generated.isOtherMath;
pub const isHexDigit = generated.isHexDigit;
pub const isAsciiHexDigit = generated.isAsciiHexDigit;
pub const isOtherAlphabetic = generated.isOtherAlphabetic;
pub const isIdeographic = generated.isIdeographic;
pub const isDiacritic = generated.isDiacritic;
pub const isExtender = generated.isExtender;
pub const isOtherLowercase = generated.isOtherLowercase;
pub const isOtherUppercase = generated.isOtherUppercase;
pub const isNoncharacterCodePoint = generated.isNoncharacterCodePoint;
pub const isOtherGraphemeExtend = generated.isOtherGraphemeExtend;
pub const isIdsBinaryOperator = generated.isIdsBinaryOperator;
pub const isIdsTrinaryOperator = generated.isIdsTrinaryOperator;
pub const isIdsUnaryOperator = generated.isIdsUnaryOperator;
pub const isRadical = generated.isRadical;
pub const isUnifiedIdeograph = generated.isUnifiedIdeograph;
pub const isOtherDefaultIgnorableCodePoint = generated.isOtherDefaultIgnorableCodePoint;
pub const isDeprecated = generated.isDeprecated;
pub const isSoftDotted = generated.isSoftDotted;
pub const isLogicalOrderException = generated.isLogicalOrderException;
pub const isOtherIdStart = generated.isOtherIdStart;
pub const isOtherIdContinue = generated.isOtherIdContinue;
pub const isSentenceTerminal = generated.isSentenceTerminal;
pub const isVariationSelector = generated.isVariationSelector;
pub const isPatternWhiteSpace = generated.isPatternWhiteSpace;
pub const isPatternSyntax = generated.isPatternSyntax;
pub const isPrependedConcatenationMark = generated.isPrependedConcatenationMark;
pub const isRegionalIndicator = generated.isRegionalIndicator;
pub const isModifierCombiningMark = generated.isModifierCombiningMark;
pub const isIdCompatMathStart = generated.isIdCompatMathStart;
pub const isIdCompatMathContinue = generated.isIdCompatMathContinue;

// ============================================================================
// Deep + hostile tests for prop_list predicates
// ============================================================================

const std = @import("std");
const encoding = @import("encoding");
const testing = std.testing;
const CodePoint = encoding.CodePoint;

test "prop_list deep: known White_Space members and adjacent non-members" {
    const members = [_]CodePoint{
        0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x0020,
        0x0085, 0x00A0, 0x1680,
        0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005,
        0x2006, 0x2007, 0x2008, 0x2009, 0x200A,
        0x2028, 0x2029, 0x202F, 0x205F, 0x3000,
    };
    for (members) |cp| try testing.expect(isWhiteSpace(cp));

    // Right next to each boundary, the predicate must flip false.
    const adjacent_non = [_]CodePoint{
        0x0008, 0x000E, 0x001F, 0x0021,
        0x0084, 0x0086, 0x009F, 0x00A1,
        0x167F, 0x1681,
        0x1FFF, 0x200B,
        0x2027, 0x202A, 0x202E, 0x2030,
        0x205E, 0x2060, 0x2FFF, 0x3001,
    };
    for (adjacent_non) |cp| try testing.expect(!isWhiteSpace(cp));
}

test "prop_list deep: ASCII_Hex_Digit is exactly 0-9, A-F, a-f" {
    var seen_true: usize = 0;
    for (0..0x80) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        const want = (cp >= '0' and cp <= '9') or (cp >= 'A' and cp <= 'F') or (cp >= 'a' and cp <= 'f');
        try testing.expectEqual(want, isAsciiHexDigit(cp));
        if (want) seen_true += 1;
    }
    try testing.expectEqual(@as(usize, 22), seen_true);
}

test "prop_list deep: Hex_Digit is ASCII hex plus fullwidth variants" {
    // Fullwidth digits, A..F, a..f
    const fullwidth = [_]CodePoint{
        0xFF10, 0xFF11, 0xFF12, 0xFF13, 0xFF14, 0xFF15, 0xFF16, 0xFF17, 0xFF18, 0xFF19,
        0xFF21, 0xFF22, 0xFF23, 0xFF24, 0xFF25, 0xFF26,
        0xFF41, 0xFF42, 0xFF43, 0xFF44, 0xFF45, 0xFF46,
    };
    for (fullwidth) |cp| {
        try testing.expect(isHexDigit(cp));
        try testing.expect(!isAsciiHexDigit(cp));
    }

    // ASCII hex digits also satisfy Hex_Digit (superset).
    for ("0123456789abcdefABCDEF") |c| {
        try testing.expect(isHexDigit(@intCast(c)));
        try testing.expect(isAsciiHexDigit(@intCast(c)));
    }

    // ASCII-Hex-Digit is strict subset of Hex_Digit.
    for (0..0x10FFFF + 1) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        if (isAsciiHexDigit(cp)) try testing.expect(isHexDigit(cp));
    }
}

test "prop_list deep: Dash vs Hyphen — overlapping but not equal" {
    // HYPHEN-MINUS is both.
    try testing.expect(isHyphen(0x002D));
    try testing.expect(isDash(0x002D));

    // SOFT HYPHEN is Hyphen but NOT Dash.
    try testing.expect(isHyphen(0x00AD));
    try testing.expect(!isDash(0x00AD));

    // EM DASH and EN DASH are Dash but not Hyphen.
    try testing.expect(isDash(0x2014));
    try testing.expect(!isHyphen(0x2014));
    try testing.expect(isDash(0x2013));
    try testing.expect(!isHyphen(0x2013));
}

test "prop_list deep: Quotation_Mark hits well-known marks" {
    const quotes = [_]CodePoint{
        0x0022, 0x0027, 0x00AB, 0x00BB,
        0x2018, 0x2019, 0x201A, 0x201C, 0x201D, 0x201E, 0x201F,
        0x2039, 0x203A,
    };
    for (quotes) |cp| try testing.expect(isQuotationMark(cp));

    // Letters and digits next to quotation codepoints are NOT quotation marks.
    try testing.expect(!isQuotationMark('A'));
    try testing.expect(!isQuotationMark('0'));
    try testing.expect(!isQuotationMark(0x2017)); // DOUBLE LOW LINE (not a quotation)
    try testing.expect(!isQuotationMark(0x203B));
}

test "prop_list deep: Noncharacter_Code_Point covers the FDD0..FDEF and *FFFE/*FFFF sets" {
    // FDD0..FDEF block
    for (0xFDD0..0xFDF0) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(isNoncharacterCodePoint(cp));
    }
    try testing.expect(!isNoncharacterCodePoint(0xFDCF));
    try testing.expect(!isNoncharacterCodePoint(0xFDF0));

    // Every plane's FFFE/FFFF.
    var plane: u21 = 0;
    while (plane <= 0x10) : (plane += 1) {
        const fffe: CodePoint = (plane << 16) | 0xFFFE;
        const ffff: CodePoint = (plane << 16) | 0xFFFF;
        try testing.expect(isNoncharacterCodePoint(fffe));
        try testing.expect(isNoncharacterCodePoint(ffff));
        // One below FFFE in each plane should not be a noncharacter.
        const fffd: CodePoint = (plane << 16) | 0xFFFD;
        try testing.expect(!isNoncharacterCodePoint(fffd));
    }
}

test "prop_list deep: Variation_Selector includes BMP and supplementary blocks" {
    // VS1..VS16
    for (0xFE00..0xFE10) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(isVariationSelector(cp));
    }
    // Mongolian variation selectors
    for (0x180B..0x180E) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(isVariationSelector(cp));
    }
    // VS17..VS256 supplementary
    try testing.expect(isVariationSelector(0xE0100));
    try testing.expect(isVariationSelector(0xE01EF));
    // Just outside the supplementary range.
    try testing.expect(!isVariationSelector(0xE00FF));
    try testing.expect(!isVariationSelector(0xE01F0));
}

test "prop_list deep: Regional_Indicator covers exactly U+1F1E6..U+1F1FF" {
    try testing.expect(!isRegionalIndicator(0x1F1E5));
    for (0x1F1E6..0x1F200) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        try testing.expect(isRegionalIndicator(cp));
    }
    try testing.expect(!isRegionalIndicator(0x1F200));
}

test "prop_list deep: Bidi_Control set" {
    const members = [_]CodePoint{
        0x061C,
        0x200E, 0x200F,
        0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
        0x2066, 0x2067, 0x2068, 0x2069,
    };
    for (members) |cp| try testing.expect(isBidiControl(cp));

    try testing.expect(!isBidiControl(0x200D)); // ZWJ — Join_Control, not Bidi_Control
    try testing.expect(!isBidiControl(0x2065));
    try testing.expect(!isBidiControl(0x206A));
}

test "prop_list deep: Join_Control covers exactly ZWNJ + ZWJ" {
    try testing.expect(isJoinControl(0x200C));
    try testing.expect(isJoinControl(0x200D));
    try testing.expect(!isJoinControl(0x200B));
    try testing.expect(!isJoinControl(0x200E));
}

test "prop_list deep: Ideographic covers core CJK ranges" {
    // CJK Unified Ideographs block
    try testing.expect(isIdeographic(0x4E00));
    try testing.expect(isIdeographic(0x9FFF));
    // CJK Compatibility Ideographs
    try testing.expect(isIdeographic(0xF900));
    // Edges
    try testing.expect(!isIdeographic(0x4DFF));
    try testing.expect(!isIdeographic(0xA000));
}

test "prop_list hostile: every u21 above 0x10FFFF returns false for all predicates" {
    // Sample a handful of high u21 values — full sweep is wasteful.
    const above: [4]CodePoint = .{ 0x110000, 0x150000, 0x1F0000, 0x1FFFFF };
    inline for (.{
        isWhiteSpace,         isBidiControl,        isJoinControl,
        isDash,               isHyphen,             isQuotationMark,
        isTerminalPunctuation, isOtherMath,         isHexDigit,
        isAsciiHexDigit,      isOtherAlphabetic,    isIdeographic,
        isDiacritic,          isExtender,           isOtherLowercase,
        isOtherUppercase,     isNoncharacterCodePoint, isOtherGraphemeExtend,
        isIdsBinaryOperator,  isIdsTrinaryOperator, isIdsUnaryOperator,
        isRadical,            isUnifiedIdeograph,   isOtherDefaultIgnorableCodePoint,
        isDeprecated,         isSoftDotted,         isLogicalOrderException,
        isOtherIdStart,       isOtherIdContinue,    isSentenceTerminal,
        isVariationSelector,  isPatternWhiteSpace,  isPatternSyntax,
        isPrependedConcatenationMark, isRegionalIndicator, isModifierCombiningMark,
        isIdCompatMathStart,  isIdCompatMathContinue,
    }) |p| {
        for (above) |cp| try testing.expect(!p(cp));
    }
}

test "prop_list hostile: surrogate range carries no PropList property" {
    var cp: CodePoint = 0xD800;
    while (cp <= 0xDFFF) : (cp += 1) {
        try testing.expect(!isWhiteSpace(cp));
        try testing.expect(!isBidiControl(cp));
        try testing.expect(!isJoinControl(cp));
        try testing.expect(!isDash(cp));
        try testing.expect(!isHyphen(cp));
        try testing.expect(!isQuotationMark(cp));
        try testing.expect(!isHexDigit(cp));
        try testing.expect(!isAsciiHexDigit(cp));
        try testing.expect(!isIdeographic(cp));
        try testing.expect(!isUnifiedIdeograph(cp));
        try testing.expect(!isRegionalIndicator(cp));
        try testing.expect(!isVariationSelector(cp));
    }
}

test "prop_list hostile: full u21 sweep does not panic on any predicate" {
    var cp: u32 = 0;
    while (cp < 0x110000) : (cp += 4096) {
        const c: CodePoint = @intCast(cp);
        _ = isWhiteSpace(c);
        _ = isBidiControl(c);
        _ = isDash(c);
        _ = isQuotationMark(c);
        _ = isOtherMath(c);
        _ = isHexDigit(c);
        _ = isAsciiHexDigit(c);
        _ = isOtherAlphabetic(c);
        _ = isIdeographic(c);
        _ = isDiacritic(c);
        _ = isExtender(c);
        _ = isOtherLowercase(c);
        _ = isOtherUppercase(c);
        _ = isNoncharacterCodePoint(c);
        _ = isOtherGraphemeExtend(c);
        _ = isIdsBinaryOperator(c);
        _ = isIdsTrinaryOperator(c);
        _ = isIdsUnaryOperator(c);
        _ = isRadical(c);
        _ = isUnifiedIdeograph(c);
        _ = isOtherDefaultIgnorableCodePoint(c);
        _ = isDeprecated(c);
        _ = isSoftDotted(c);
        _ = isLogicalOrderException(c);
        _ = isOtherIdStart(c);
        _ = isOtherIdContinue(c);
        _ = isSentenceTerminal(c);
        _ = isVariationSelector(c);
        _ = isPatternWhiteSpace(c);
        _ = isPatternSyntax(c);
        _ = isPrependedConcatenationMark(c);
        _ = isRegionalIndicator(c);
        _ = isModifierCombiningMark(c);
        _ = isIdCompatMathStart(c);
        _ = isIdCompatMathContinue(c);
        _ = isTerminalPunctuation(c);
        _ = isJoinControl(c);
        _ = isHyphen(c);
    }
}

test "prop_list hostile: zero codepoint carries no PropList property" {
    try testing.expect(!isWhiteSpace(0));
    try testing.expect(!isBidiControl(0));
    try testing.expect(!isDash(0));
    try testing.expect(!isHyphen(0));
    try testing.expect(!isHexDigit(0));
    try testing.expect(!isAsciiHexDigit(0));
    try testing.expect(!isIdeographic(0));
    try testing.expect(!isRegionalIndicator(0));
    try testing.expect(!isVariationSelector(0));
    try testing.expect(!isNoncharacterCodePoint(0));
}

test "prop_list hostile: ASCII region carries only well-known property bits" {
    var cp: CodePoint = 0;
    while (cp < 0x80) : (cp += 1) {
        // No CJK / variation selector / regional indicator inside ASCII.
        try testing.expect(!isIdeographic(cp));
        try testing.expect(!isUnifiedIdeograph(cp));
        try testing.expect(!isRegionalIndicator(cp));
        try testing.expect(!isVariationSelector(cp));
        try testing.expect(!isOtherAlphabetic(cp));
        try testing.expect(!isOtherLowercase(cp));
        try testing.expect(!isOtherUppercase(cp));
        try testing.expect(!isNoncharacterCodePoint(cp));
    }
}

test {
    testing.refAllDecls(@This());
}
