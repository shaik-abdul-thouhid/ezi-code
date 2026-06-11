//! This file contains APIs for estimating the display width of Unicode
//! scalar values. It exposes the East Asian Width property (per Unicode
//! Standard Annex #11) and a terminal-oriented column-width estimator for
//! laying text out on a monospace cell grid.
//!
//! - All public functions accept any `u32` and never trap: out-of-range
//!   values (above U+10FFFF) and surrogates fall back to a safe default
//!   rather than erroring.
//! - The East Asian Width tables are auto-generated from the Unicode
//!   Character Database; see `generated/east_asian_width.zig`.

const std = @import("std");
const encoding = @import("encoding");
const segmentation = @import("../segmentation/root.zig");

const CodePoint = encoding.CodePoint;

/// Auto-generated East Asian Width tables and lookup, derived from the
/// Unicode Character Database. Re-exported so callers can reach the raw
/// generated declarations; prefer the aliases below for everyday use.
pub const generated = @import("generated/east_asian_width.zig");
/// The East Asian Width property values from Unicode Standard Annex #11:
/// `n` (Neutral), `a` (Ambiguous), `f` (Fullwidth), `h` (Halfwidth),
/// `na` (Narrow), and `w` (Wide). This enum is exhaustive.
pub const EastAsianWidth = generated.EastAsianWidth;
/// Returns the East Asian Width property of `cp`. Accepts any `u32` and
/// never traps: code points above U+10FFFF resolve to `.n` (Neutral).
///
/// @stable-since: v0.1.0
pub const eastAsianWidth = generated.eastAsianWidth;

const unicode_data = @import("../generated/unicode_data.zig");

/// Estimated number of terminal columns occupied by `cp` when rendered in a
/// monospace cell grid:
///   0 — combining marks, format controls, ASCII/C0 controls (no advance)
///   2 — East Asian Wide (W) and Fullwidth (F)
///   1 — everything else (Narrow / Halfwidth / Ambiguous / Neutral letters)
///
/// Ambiguous (A) is treated as 1 because it is the safer default in
/// non-CJK contexts; callers that need East Asian context can switch on
/// `eastAsianWidth(cp) == .a` directly.
///
/// @stable-since: v0.1.0
pub fn terminalColumnWidth(cp: CodePoint) u2 {
    if (cp > 0x10FFFF) return 1;
    const cat = unicode_data.generalCategory(cp);
    switch (cat) {
        .non_spacing_mark, .enclosing_mark, .format, .control, .surrogate => return 0,
        else => {},
    }
    return switch (eastAsianWidth(cp)) {
        .w, .f => 2,
        .n, .na, .a, .h => 1,
    };
}

/// Sum of `terminalColumnWidth` over a slice of already-decoded scalars — the
/// estimated number of monospace columns `code_points` occupies. Combining marks
/// and controls contribute 0, East Asian Wide/Fullwidth contribute 2, everything
/// else 1. Allocation-free and never traps.
///
/// @stable-since: v0.2.0
pub fn stringWidthCodePoints(code_points: []const CodePoint) usize {
    var total: usize = 0;
    for (code_points) |cp| total += terminalColumnWidth(cp);
    return total;
}

/// Estimated monospace column width of the UTF-8 `bytes`, summing
/// `terminalColumnWidth` over each decoded scalar. Validates the input and
/// surfaces a `UTF8ValidationError` on malformed sequences; use
/// `stringWidthLossy` to measure possibly-malformed input instead.
///
/// @stable-since: v0.2.0
pub fn stringWidth(bytes: []const u8) encoding.utf8.UTF8ValidationError!usize {
    var i: usize = 0;
    var total: usize = 0;
    while (i < bytes.len) {
        const decoded = try encoding.utf8.validateAndDecodeCodePointBytes(bytes, i);
        total += terminalColumnWidth(decoded.code_point);
        i += decoded.len;
    }
    return total;
}

/// Estimated monospace column width of the UTF-8 `bytes`, decoding leniently:
/// each malformed sequence is treated as one replacement scalar (U+FFFD, width
/// 1) rather than raising an error. Never fails. Strict counterpart:
/// `stringWidth`.
///
/// @stable-since: v0.2.0
pub fn stringWidthLossy(bytes: []const u8) usize {
    var total: usize = 0;
    var iter = encoding.utf8.lossyIterator(bytes);
    while (iter.next()) |cp| total += terminalColumnWidth(cp);
    return total;
}

// ============================================================================
// Grapheme-cluster-aware width
//
// The `stringWidth*` functions above sum `terminalColumnWidth` over every
// scalar, so a single user-perceived character spread across several scalars is
// over-counted: a ZWJ emoji such as 👨‍👩‍👧 (U+1F468 U+200D U+1F469 U+200D
// U+1F467) sums 2+0+2+0+2 = 6 columns but renders in 2. The functions in this
// section first group scalars into extended grapheme clusters (UAX #29, via the
// `segmentation` module) and charge each cluster a single cell-run, so the same
// emoji counts as 2. They remain estimates: the true on-screen advance of an
// exotic emoji sequence is ultimately terminal- and font-dependent.
// ============================================================================

/// The emoji variation selector, U+FE0F (VS16). When it follows an otherwise
/// text-presentation base, the base is rendered as a (wide) emoji.
const VARIATION_SELECTOR_16: CodePoint = 0xFE0F;
/// Inclusive bounds of the Regional_Indicator block (U+1F1E6..U+1F1FF). A pair
/// of these forms a flag, which renders in 2 columns.
const REGIONAL_INDICATOR_FIRST: CodePoint = 0x1F1E6;
const REGIONAL_INDICATOR_LAST: CodePoint = 0x1F1FF;

/// Folds one scalar of a grapheme cluster into the running width signals shared
/// by `graphemeClusterWidth` and `graphemeClusterWidthBytes`: the maximum
/// per-scalar `terminalColumnWidth`, whether an emoji variation selector
/// (U+FE0F) was seen, and the count of Regional_Indicator scalars.
const ClusterWidthAccum = struct {
    max_w: u2 = 0,
    has_vs16: bool = false,
    ri: usize = 0,

    inline fn add(self: *ClusterWidthAccum, cp: CodePoint) void {
        const w = terminalColumnWidth(cp);
        if (w > self.max_w) self.max_w = w;
        if (cp == VARIATION_SELECTOR_16) self.has_vs16 = true;
        if (cp >= REGIONAL_INDICATOR_FIRST and cp <= REGIONAL_INDICATOR_LAST) self.ri += 1;
    }

    /// Resolves the accumulated signals to the cluster's column width.
    inline fn resolve(self: ClusterWidthAccum) u2 {
        // An emoji-presentation sequence (base + VS16, e.g. ❤️ = U+2764 U+FE0F)
        // renders wide regardless of the base's text-presentation width.
        if (self.has_vs16) return 2;
        // A flag is a pair of Regional_Indicators and renders in 2 columns.
        if (self.ri >= 2) return 2;
        // Otherwise the base (or the emoji the sequence forms) governs the
        // width; combining marks, ZWJ, and variation selectors are zero-width
        // and so never lift `max_w` above the base.
        return self.max_w;
    }
};

/// Estimated monospace column width of a single grapheme cluster (a slice of
/// already-decoded scalars belonging to one cluster, e.g. as produced by
/// `segmentation.codePointIterator`). A cluster renders in one cell-run:
/// combining marks, ZWJ, and variation selectors are zero-width, so the base —
/// or the emoji the whole sequence forms — governs the width. Concretely:
///   - a base + emoji variation selector (U+FE0F) sequence renders wide (2);
///   - a pair of Regional_Indicators (a flag) renders wide (2);
///   - otherwise the width is the maximum `terminalColumnWidth` of the
///     cluster's scalars.
/// An empty cluster is 0 columns. Allocation-free and never traps. This is the
/// per-cluster primitive behind the `stringWidthGraphemes*` functions; unlike
/// summing `terminalColumnWidth` per scalar it counts a multi-scalar emoji such
/// as 👨‍👩‍👧 (U+1F468 U+200D U+1F469 U+200D U+1F467) once (2, not 6). The
/// result is an estimate — exotic emoji are ultimately terminal-dependent.
///
/// @stable-since: v0.4.1
pub fn graphemeClusterWidth(cluster: []const CodePoint) u2 {
    if (cluster.len == 0) return 0;
    var accum: ClusterWidthAccum = .{};
    for (cluster) |cp| accum.add(cp);
    return accum.resolve();
}

/// Width of a grapheme cluster supplied as the UTF-8 `cluster` bytes (one
/// cluster, e.g. as produced by `segmentation.iterator`). Decodes the cluster's
/// scalars leniently (U+FFFD for malformed sequences) and applies the same
/// max / VS16 / Regional_Indicator logic as `graphemeClusterWidth`. An empty
/// cluster is 0 columns.
fn graphemeClusterWidthBytes(cluster: []const u8) u2 {
    if (cluster.len == 0) return 0;
    var accum: ClusterWidthAccum = .{};
    var i: usize = 0;
    while (i < cluster.len) {
        const decoded = encoding.utf8.decodeCodePointLossy(cluster, i);
        accum.add(decoded.code_point);
        i += decoded.len;
    }
    return accum.resolve();
}

/// Estimated monospace column width of `code_points`, grouping the scalars into
/// extended grapheme clusters (via `segmentation.codePointIterator`) and
/// charging each cluster one cell-run with `graphemeClusterWidth`. Unlike the
/// per-scalar `stringWidthCodePoints`, a multi-scalar emoji such as 👨‍👩‍👧
/// (U+1F468 U+200D U+1F469 U+200D U+1F467) is counted once (2, not 6).
/// Allocation-free and never traps. The result is an estimate — the on-screen
/// advance of exotic emoji is ultimately terminal-dependent.
///
/// @stable-since: v0.4.1
pub fn stringWidthGraphemesCodePoints(code_points: []const CodePoint) usize {
    var total: usize = 0;
    var iter = segmentation.codePointIterator(code_points);
    while (iter.next()) |cluster| total += graphemeClusterWidth(cluster);
    return total;
}

/// Estimated monospace column width of the UTF-8 `bytes`, grouping the decoded
/// scalars into extended grapheme clusters (via `segmentation.iterator`) and
/// charging each cluster one cell-run. Decodes leniently: malformed sequences
/// are treated as one replacement scalar (U+FFFD, width 1) rather than raising
/// an error, so it never fails. Unlike the per-scalar `stringWidthLossy`, a
/// multi-scalar emoji such as 👨‍👩‍👧 (U+1F468 U+200D U+1F469 U+200D U+1F467)
/// is counted once (2, not 6). Strict counterpart: `stringWidthGraphemes`. The
/// result is an estimate — exotic emoji are ultimately terminal-dependent.
///
/// @stable-since: v0.4.1
pub fn stringWidthGraphemesLossy(bytes: []const u8) usize {
    var total: usize = 0;
    var iter = segmentation.iterator(bytes);
    while (iter.next()) |cluster| total += graphemeClusterWidthBytes(cluster);
    return total;
}

/// Estimated monospace column width of the UTF-8 `bytes`, grouping the decoded
/// scalars into extended grapheme clusters and charging each cluster one
/// cell-run — the grapheme-aware counterpart of `stringWidth`. Validates the
/// input and surfaces a `UTF8ValidationError` on malformed sequences; use
/// `stringWidthGraphemesLossy` to measure possibly-malformed input instead.
/// Unlike the per-scalar `stringWidth`, a multi-scalar emoji such as 👨‍👩‍👧
/// (U+1F468 U+200D U+1F469 U+200D U+1F467) is counted once (2, not 6). The
/// result is an estimate — exotic emoji are ultimately terminal-dependent.
///
/// @stable-since: v0.4.1
pub fn stringWidthGraphemes(bytes: []const u8) encoding.utf8.UTF8ValidationError!usize {
    // Validate up front: on valid input the lossy clustering below is identical,
    // so a single strict decode pass is enough to gate the lenient measurement.
    var i: usize = 0;
    while (i < bytes.len) {
        const decoded = try encoding.utf8.validateAndDecodeCodePointBytes(bytes, i);
        i += decoded.len;
    }
    return stringWidthGraphemesLossy(bytes);
}

// ============================================================================
// Hostile / edge-case tests
// ============================================================================

const testing = std.testing;

test "east asian width: known boundary codepoints across every variant" {
    // Wide and Fullwidth — CJK ideograph, ideographic space.
    try testing.expectEqual(EastAsianWidth.w, eastAsianWidth(0x4E00)); // CJK UNIFIED IDEOGRAPH-4E00
    try testing.expectEqual(EastAsianWidth.f, eastAsianWidth(0x3000)); // IDEOGRAPHIC SPACE
    try testing.expectEqual(EastAsianWidth.f, eastAsianWidth(0xFF01)); // FULLWIDTH EXCLAMATION MARK
    // Halfwidth katakana.
    try testing.expectEqual(EastAsianWidth.h, eastAsianWidth(0xFF61)); // HALFWIDTH IDEOGRAPHIC FULL STOP
    // Narrow ASCII.
    try testing.expectEqual(EastAsianWidth.na, eastAsianWidth('A'));
    try testing.expectEqual(EastAsianWidth.na, eastAsianWidth('0'));
    // Ambiguous — Greek alpha, inverted exclamation, combining diaeresis
    // (the whole 0300..036F combining-marks block is Ambiguous in EAW).
    try testing.expectEqual(EastAsianWidth.a, eastAsianWidth(0x03B1)); // GREEK SMALL LETTER ALPHA
    try testing.expectEqual(EastAsianWidth.a, eastAsianWidth(0x00A1)); // INVERTED EXCLAMATION MARK
    try testing.expectEqual(EastAsianWidth.a, eastAsianWidth(0x0308)); // COMBINING DIAERESIS
    // Neutral — copyright sign, Greek capital letter heta.
    try testing.expectEqual(EastAsianWidth.n, eastAsianWidth(0x00A9));
    try testing.expectEqual(EastAsianWidth.n, eastAsianWidth(0x0370));
}

test "east asian width: out-of-range returns default neutral, never traps" {
    try testing.expectEqual(EastAsianWidth.n, eastAsianWidth(0x110000));
    try testing.expectEqual(EastAsianWidth.n, eastAsianWidth(0x1FFFFF));
}

test "east asian width: every codepoint resolves to an exhaustive enum variant" {
    var cp: CodePoint = 0;
    while (cp <= 0x10FFFF) : (cp += 1) {
        switch (eastAsianWidth(cp)) {
            .n, .a, .f, .h, .na, .w => {},
        }
    }
}

test "terminalColumnWidth: 2 for W and F, 1 for ASCII letters, 0 for combining marks" {
    try testing.expectEqual(@as(u2, 2), terminalColumnWidth(0x4E00));
    try testing.expectEqual(@as(u2, 2), terminalColumnWidth(0x3000));
    try testing.expectEqual(@as(u2, 2), terminalColumnWidth(0xFF01));
    try testing.expectEqual(@as(u2, 1), terminalColumnWidth('A'));
    try testing.expectEqual(@as(u2, 1), terminalColumnWidth(0x03B1)); // Ambiguous → 1
    try testing.expectEqual(@as(u2, 1), terminalColumnWidth(0xFF61)); // Halfwidth → 1
    try testing.expectEqual(@as(u2, 0), terminalColumnWidth(0x0308)); // combining diaeresis
    try testing.expectEqual(@as(u2, 0), terminalColumnWidth(0x0300)); // combining grave
    try testing.expectEqual(@as(u2, 0), terminalColumnWidth(0x200D)); // ZWJ (Cf)
    try testing.expectEqual(@as(u2, 0), terminalColumnWidth(0x0000)); // NUL (Cc)
    try testing.expectEqual(@as(u2, 0), terminalColumnWidth(0x0007)); // BEL (Cc)
    try testing.expectEqual(@as(u2, 0), terminalColumnWidth(0x007F)); // DEL (Cc)
}

test "terminalColumnWidth: enclosing mark counts as 0" {
    // U+20DD COMBINING ENCLOSING CIRCLE — Me category.
    try testing.expectEqual(@as(u2, 0), terminalColumnWidth(0x20DD));
}

test "terminalColumnWidth: surrogate range returns 0 (cannot render)" {
    try testing.expectEqual(@as(u2, 0), terminalColumnWidth(0xD800));
    try testing.expectEqual(@as(u2, 0), terminalColumnWidth(0xDFFF));
}

test "terminalColumnWidth: out-of-range falls back to 1 (treated as default Neutral)" {
    try testing.expectEqual(@as(u2, 1), terminalColumnWidth(0x110000));
}

test "terminalColumnWidth: never reports more than 2 columns for any scalar" {
    var cp: CodePoint = 0;
    while (cp <= 0x10FFFF) : (cp += 1) {
        try testing.expect(terminalColumnWidth(cp) <= 2);
    }
}

// ============================================================================
// Zalgo (combining-mark-saturated) text. Combining marks are nonspacing and
// occupy zero terminal columns, so a base buried under any number of marks is
// still just the width of the base. With ASCII bases (1 column each) the summed
// width equals the base count. Driven by the shared corpus.
// ============================================================================

const zalgo_corpus = @import("../tests/zalgo_corpus.zig");

test "terminalColumnWidth zalgo: combining marks add zero columns" {
    for (zalgo_corpus.samples) |s| {
        const cps = try zalgo_corpus.decode(testing.allocator, s.text);
        defer testing.allocator.free(cps);

        var total: usize = 0;
        for (cps) |cp| total += terminalColumnWidth(cp);

        // Each base is a 1-column ASCII scalar; each mark is 0 columns.
        try testing.expectEqual(s.base_count, total);
    }
}

test "stringWidth / stringWidthCodePoints: sums column widths" {
    // "Aあ" = 1 (A) + 2 (Wide HIRAGANA A) = 3 columns.
    try testing.expectEqual(@as(usize, 3), try stringWidth("Aあ"));

    const cps = [_]CodePoint{ 'A', 0x3042, 0x0308 }; // A, あ (wide), combining diaeresis (0)
    try testing.expectEqual(@as(usize, 3), stringWidthCodePoints(&cps));

    try testing.expectEqual(@as(usize, 0), try stringWidth(""));
    // Combining mark over a base adds no columns.
    try testing.expectEqual(@as(usize, 1), try stringWidth("e\u{0301}"));

    try testing.expectError(error.InvalidByteSequence, stringWidth("\xFF"));
}

test "stringWidthLossy: malformed bytes count as one replacement column" {
    // 'A' + invalid byte (→ U+FFFD, width 1) + 'B' = 3.
    try testing.expectEqual(@as(usize, 3), stringWidthLossy("A\xFFB"));
    try testing.expectEqual(@as(usize, 3), stringWidthLossy("Aあ"));
}

// ============================================================================
// Grapheme-cluster-aware width tests
// ============================================================================

test "stringWidthGraphemes: ASCII + wide parity with per-scalar stringWidth" {
    // "Aあ" = 1 (A) + 2 (Wide HIRAGANA A) = 3 columns, matching the per-scalar
    // case above — no clustering changes anything when every cluster is one
    // scalar.
    try testing.expectEqual(@as(usize, 3), try stringWidthGraphemes("Aあ"));
}

test "stringWidthGraphemes: ZWJ family counts once (the C1 fix)" {
    // 👨‍👩‍👧 = U+1F468 U+200D U+1F469 U+200D U+1F467. It renders in 2 columns,
    // but the per-scalar estimator sums 2+0+2+0+2 = 6. The grapheme-aware
    // functions charge the single cluster once.
    const family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}";

    try testing.expectEqual(@as(usize, 2), try stringWidthGraphemes(family));

    const cps = try encoding.utf8.bytesToUTF8String(testing.allocator, family);
    defer testing.allocator.free(cps);
    try testing.expectEqual(@as(usize, 2), stringWidthGraphemesCodePoints(cps));

    // Document the divergence from the old per-scalar API explicitly: the same
    // bytes still measure 6 columns under `stringWidth`, which the new API fixes.
    try testing.expectEqual(@as(usize, 6), try stringWidth(family));
    try testing.expect((try stringWidth(family)) != (try stringWidthGraphemes(family)));
}

test "stringWidthGraphemes: emoji presentation, flags, and modifiers are 2" {
    // ❤️ = U+2764 U+FE0F — text-presentation heart promoted to emoji by VS16.
    try testing.expectEqual(@as(usize, 2), try stringWidthGraphemes("\u{2764}\u{FE0F}"));
    // 🇺🇸 = U+1F1FA U+1F1F8 — a flag is a Regional_Indicator pair.
    try testing.expectEqual(@as(usize, 2), try stringWidthGraphemes("\u{1F1FA}\u{1F1F8}"));
    // 👍🏽 = U+1F44D U+1F3FD — emoji base + skin-tone modifier, one cluster.
    try testing.expectEqual(@as(usize, 2), try stringWidthGraphemes("\u{1F44D}\u{1F3FD}"));
}

test "stringWidthGraphemes: combining-mark clusters count as the base" {
    // "é" as e + COMBINING ACUTE ACCENT (U+0065 U+0301) → 1 column.
    try testing.expectEqual(@as(usize, 1), try stringWidthGraphemes("e\u{0301}"));
    // "café" with a decomposed é (cafe + combining acute) → 4 columns.
    try testing.expectEqual(@as(usize, 4), try stringWidthGraphemes("cafe\u{0301}"));
}

test "stringWidthGraphemesLossy: invalid bytes do not trap, yield a sane width" {
    // 'a' + lone 0xFF (→ U+FFFD, width 1) + 'b' = 3 columns, and no trap.
    try testing.expectEqual(@as(usize, 3), stringWidthGraphemesLossy(&.{ 'a', 0xFF, 'b' }));
}

test "stringWidthGraphemes*: empty input is zero columns" {
    try testing.expectEqual(@as(usize, 0), try stringWidthGraphemes(""));
    try testing.expectEqual(@as(usize, 0), stringWidthGraphemesLossy(""));
    try testing.expectEqual(@as(usize, 0), stringWidthGraphemesCodePoints(&[_]CodePoint{}));
    try testing.expectEqual(@as(u2, 0), graphemeClusterWidth(&[_]CodePoint{}));
}

test {
    testing.refAllDecls(@This());
}
