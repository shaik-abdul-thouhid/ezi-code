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

test {
    testing.refAllDecls(@This());
}
