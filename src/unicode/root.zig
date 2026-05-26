//! Top-level Unicode facade. Re-exports submodule namespaces and the most
//! widely-used types. Predicates and casing functions are accessed through
//! their submodule (`unicode.properties.isAlphabetic`, `unicode.casing.toUpperCase`,
//! `unicode.segmentation.graphemeBreakProperty`, etc.) rather than via thin
//! delegate wrappers at this level. Tests live in the submodule files
//! alongside the code they exercise.

const std = @import("std");
const encoding = @import("encoding");

pub const types = @import("types.zig");
pub const properties = @import("properties/root.zig");
pub const casing = @import("casing/root.zig");
pub const segmentation = @import("segmentation/root.zig");
pub const width = @import("width/root.zig");

// Generated data table re-exports — useful for callers that want raw
// table-level access rather than the consumer module's higher-level API.
pub const unicode_data = properties.unicode_data;
pub const derived_core_properties = properties.derived_core_properties;
pub const prop_list = properties.prop_list;
pub const case_folding = casing.case_folding;
pub const special_casing = casing.special_casing;
pub const grapheme_break = segmentation.generated;
pub const emoji_data = segmentation.emoji_data;
pub const word_break = segmentation.word_break;
pub const sentence_break = segmentation.sentence_break;
pub const line_break = segmentation.line_break;
pub const east_asian_width = width.generated;

// Widely-used type aliases. Anything more specific belongs in the submodule.
pub const GeneralCategory = properties.GeneralCategory;
pub const BidiClass = properties.BidiClass;
pub const CanonicalCombiningClass = types.CanonicalCombiningClass;
pub const DerivedProperty = properties.DerivedProperty;
pub const CaseFoldingMode = types.CaseFoldingMode;
pub const CaseFoldingLocale = types.CaseFoldingLocale;
pub const SpecialCaseLocale = casing.SpecialCaseLocale;
pub const SpecialCaseCondition = casing.SpecialCaseCondition;
pub const SpecialCaseMapping = casing.SpecialCaseMapping;
pub const GraphemeBreakProperty = segmentation.GraphemeBreakProperty;
pub const WordBreakProperty = segmentation.WordBreakProperty;
pub const SentenceBreakProperty = segmentation.SentenceBreakProperty;
pub const LineBreak = segmentation.LineBreak;
pub const EastAsianWidth = width.EastAsianWidth;
pub const GraphemeIterator = segmentation.GraphemeIterator;
pub const CodePointGraphemeIterator = segmentation.CodePointGraphemeIterator;
pub const InCB = segmentation.InCB;

// Pull in submodule tests via refAllDecls — the test binary built for this
// module otherwise wouldn't see them because each submodule lives behind a
// `pub const`.
const ucd_conformance_tests = @import("tests/ucd_conformance.zig");

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(ucd_conformance_tests);
}
