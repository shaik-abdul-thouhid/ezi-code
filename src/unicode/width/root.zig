const std = @import("std");
const encoding = @import("encoding");

const CodePoint = encoding.CodePoint;

pub const generated = @import("generated/east_asian_width.zig");
pub const EastAsianWidth = generated.EastAsianWidth;
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

test {
    testing.refAllDecls(@This());
}
