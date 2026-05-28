//! Top-level Unicode facade. Re-exports submodule namespaces and the most
//! widely-used types. Predicates and casing functions are accessed through
//! their submodule (`unicode.properties.isAlphabetic`, `unicode.casing.toUpperCase`,
//! `unicode.segmentation.graphemeBreakProperty`, etc.) rather than via thin
//! delegate wrappers at this level. Tests live in the submodule files
//! alongside the code they exercise.

const std = @import("std");
const build_options = @import("build_options");

const encoding = @import("encoding");

pub const types = @import("types.zig");
pub const properties = @import("properties/root.zig");
pub const casing = @import("casing/root.zig");
pub const segmentation = @import("segmentation/root.zig");
pub const width = @import("width/root.zig");
pub const normalization = @import("normalization/root.zig");
pub const scripts = @import("scripts/root.zig");

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
pub const derived_normalization_props = normalization.derived_normalization_props;
pub const scripts_data = scripts.generated;
pub const script_extensions_data = scripts.generated_extensions;

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
pub const ScriptType = scripts.ScriptType;
pub const scriptType = scripts.scriptType;
pub const scriptExtensions = scripts.scriptExtensions;
pub const hasScriptExtension = scripts.hasScriptExtension;
pub const GraphemeIterator = segmentation.GraphemeIterator;
pub const CodePointGraphemeIterator = segmentation.CodePointGraphemeIterator;
pub const InCB = segmentation.InCB;
pub const QuickCheck = types.QuickCheck;
pub const QuickCheckForm = types.QuickCheckForm;
pub const ExpandsForm = types.ExpandsForm;
pub const CasefoldKind = types.CasefoldKind;
pub const NormalizationForm = normalization.NormalizationForm;
pub const DecompositionForm = normalization.DecompositionForm;
pub const CompositionForm = normalization.CompositionForm;
pub const Normalizer = normalization.Normalizer;

// Normalization entry points. The two primary primitives are
// comptime-specialized on form; the four-way `normalize` plus the named
// wrappers (nfc/nfd/nfkc/nfkd) thread through them.
pub const decompose = normalization.decompose;
pub const compose = normalization.compose;
pub const normalize = normalization.normalize;
pub const nfc = normalization.nfc;
pub const nfd = normalization.nfd;
pub const nfkc = normalization.nfkc;
pub const nfkd = normalization.nfkd;
pub const isNormalized = normalization.isNormalized;

// Pull in submodule tests via refAllDecls — the test binary built for this
// module otherwise wouldn't see them because each submodule lives behind a
// `pub const`.
const ucd_conformance_tests = @import("tests/ucd_conformance.zig");

test {
    std.testing.refAllDecls(@This());
    if (build_options.include_conformance) {
        std.testing.refAllDecls(ucd_conformance_tests);
    }
}
