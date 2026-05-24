const std = @import("std");
const encoding = @import("encoding");
const types = @import("../types.zig");

pub const unicode_data = @import("../generated/unicode_data.zig");
pub const derived_core_properties = @import("derived_core_properties.zig");

pub const GeneralCategory = unicode_data.GeneralCategory;
pub const BidiClass = unicode_data.BidiClass;
pub const DerivedProperty = derived_core_properties.Property;
pub const CanonicalCombiningClass = types.CanonicalCombiningClass;

const CodePoint = encoding.CodePoint;

pub const combining_class_table = unicode_data.combining_class_table;
pub const lowercase_mapping_table = unicode_data.lowercase_range_mapping_table;
pub const uppercase_mapping_table = unicode_data.uppercase_range_mapping_table;
pub const titlecase_mapping_table = unicode_data.titlecase_range_mapping_table;

pub fn derivedPropertyMask(code_point: CodePoint) u32 {
    return derived_core_properties.propertyMask(code_point);
}

pub fn hasDerivedProperty(code_point: CodePoint, property: DerivedProperty) bool {
    return derived_core_properties.codePointProperty(code_point, property);
}

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

pub fn generalCategory(code_point: CodePoint) GeneralCategory {
    return unicode_data.generalCategory(code_point);
}

pub fn bidiClass(code_point: CodePoint) BidiClass {
    return unicode_data.bidiClass(code_point);
}

pub fn isLetter(code_point: CodePoint) bool {
    const category = generalCategory(code_point);
    return switch (category) {
        .uppercase_letter, .lowercase_letter, .titlecase_letter, .modifier_letter, .other_letter => true,
        else => false,
    };
}

pub fn isUpperCase(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .uppercase);
}

pub fn isLowerCase(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .lowercase);
}

pub fn isAlphabetic(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .alphabetic);
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
        0x0009,
        0x000A,
        0x000B,
        0x000C,
        0x000D,
        0x0020,
        0x0085,
        0x00A0,
        0x1680,
        0x2000...0x200A,
        0x2028,
        0x2029,
        0x202F,
        0x205F,
        0x3000,
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

pub fn isMark(code_point: CodePoint) bool {
    const category = generalCategory(code_point);
    return switch (category) {
        .non_spacing_mark, .spacing_mark, .enclosing_mark => true,
        else => false,
    };
}

pub fn isMath(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .math);
}

pub fn isCased(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .cased);
}

pub fn isCaseIgnorable(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .case_ignorable);
}

pub fn changesWhenLowercased(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .changes_when_lowercased);
}

pub fn changesWhenUppercased(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .changes_when_uppercased);
}

pub fn changesWhenTitlecased(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .changes_when_titlecased);
}

pub fn changesWhenCasefolded(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .changes_when_casefolded);
}

pub fn changesWhenCasemapped(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .changes_when_casemapped);
}

pub fn isDecimalDigit(code_point: CodePoint) bool {
    return generalCategory(code_point) == .decimal_number;
}

pub fn isHexDigit(code_point: CodePoint) bool {
    return switch (code_point) {
        '0'...'9', 'a'...'f', 'A'...'F' => true,
        else => false,
    };
}

pub fn isIdentifierStart(code_point: CodePoint) bool {
    if (code_point == '_') return true;
    return isIdStart(code_point);
}

pub fn isIdentifierContinue(code_point: CodePoint) bool {
    if (code_point == '_') return true;
    return isIdContinue(code_point);
}

pub fn isIdStart(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .id_start);
}

pub fn isIdContinue(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .id_continue);
}

pub fn isXidStart(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .xid_start);
}

pub fn isXidContinue(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .xid_continue);
}

pub fn isDefaultIgnorableCodePoint(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .default_ignorable_code_point);
}

pub fn isGraphemeExtend(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .grapheme_extend);
}

pub fn isGraphemeBase(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .grapheme_base);
}

pub fn isGraphemeLink(code_point: CodePoint) bool {
    return hasDerivedProperty(code_point, .grapheme_link);
}

pub fn isSpaceSeparator(code_point: CodePoint) bool {
    return generalCategory(code_point) == .space_separator;
}

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

pub fn isAscii(code_point: CodePoint) bool {
    return code_point <= 0x7F;
}

test {
    std.testing.refAllDecls(@This());
}
