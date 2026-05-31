//! Bidirectional (UAX #9) character properties.
//!
//! Two normative/informative property mappings are exposed here, each backed
//! by a deduplicated 2-level page table in `generated/`:
//!
//!   * `bidiMirroringGlyph(cp)` — Bidi_Mirroring_Glyph: the codepoint whose
//!     glyph mirrors `cp`'s, or null. (BidiMirroring.txt)
//!   * `bidiPairedBracketType(cp)` + `bidiPairedBracket(cp)` —
//!     Bidi_Paired_Bracket_Type and Bidi_Paired_Bracket: whether `cp` is an
//!     opening/closing bracket and, if so, the opposite member of the pair.
//!     (BidiBrackets.txt)
//!
//! Every lookup is two array indexes plus a branch on the sentinel; all
//! functions are total over `CodePoint` (out-of-range inputs resolve to the
//! default rather than trapping).
//!
//! Note: `hasMirroringGlyph` is *not* the Bidi_Mirrored (Bidi_M) property —
//! several Bidi_Mirrored characters have no mirror-image codepoint and so map
//! to null here. The Bidi_Mirrored boolean is not part of this module.

const std = @import("std");
const encoding = @import("encoding");

const CodePoint = encoding.CodePoint;

pub const generated_mirroring = @import("generated/bidi_mirroring.zig");
pub const generated_brackets = @import("generated/bidi_brackets.zig");

pub const BidiPairedBracketType = generated_brackets.BidiPairedBracketType;

/// Bidi_Mirroring_Glyph of `cp`, or null when no mirror codepoint exists.
/// Involutive over its domain: `bidiMirroringGlyph(bidiMirroringGlyph(cp).?).? == cp`.
pub const bidiMirroringGlyph = generated_mirroring.bidiMirroringGlyph;

/// Bidi_Paired_Bracket_Type of `cp` (`.none`, `.open`, or `.close`).
pub const bidiPairedBracketType = generated_brackets.bidiPairedBracketType;

/// Bidi_Paired_Bracket of `cp`: the opposite member of its bracket pair, or
/// null when `cp` is not a paired bracket.
pub const bidiPairedBracket = generated_brackets.bidiPairedBracket;

/// True when `cp` has a Bidi_Mirroring_Glyph. This is strictly narrower than
/// the Bidi_Mirrored (Bidi_M) property: a character may be Bidi_Mirrored yet
/// have no mirror-image codepoint, in which case this returns false.
pub inline fn hasMirroringGlyph(cp: CodePoint) bool {
    return bidiMirroringGlyph(cp) != null;
}

/// True when `cp` is either half of a bracket pair (Bidi_Paired_Bracket_Type
/// is `open` or `close`).
pub inline fn isPairedBracket(cp: CodePoint) bool {
    return bidiPairedBracketType(cp) != .none;
}

/// True when `cp` is an opening paired bracket (bpt = Open).
pub inline fn isOpeningBracket(cp: CodePoint) bool {
    return bidiPairedBracketType(cp) == .open;
}

/// True when `cp` is a closing paired bracket (bpt = Close).
pub inline fn isClosingBracket(cp: CodePoint) bool {
    return bidiPairedBracketType(cp) == .close;
}

// ============================================================================
// Bidirectional Algorithm (UAX #9)
// ============================================================================
// The reordering algorithm proper lives in `algorithm.zig`; its public surface
// is re-exported here so callers reach it as `unicode.bidi.resolveParagraph`,
// `unicode.bidi.reorderVisual`, and so on, alongside the property lookups above.

pub const algorithm = @import("algorithm.zig");

pub const Level = algorithm.Level;
pub const max_depth = algorithm.max_depth;
pub const BaseDirection = algorithm.BaseDirection;
pub const Paragraph = algorithm.Paragraph;

/// Resolve the embedding levels of one paragraph (UAX #9 rules P–I).
pub const resolveParagraph = algorithm.resolveParagraph;
/// Paragraph embedding level for the given base direction (P2/P3).
pub const paragraphLevel = algorithm.paragraphLevel;
/// Visual (display) order of a line from its resolved levels (L2).
pub const reorderVisual = algorithm.reorderVisual;
/// One-shot: resolve `cps` as a paragraph and return its visual order (L1+L2).
pub const reorderParagraph = algorithm.reorderParagraph;
/// L4 glyph mirroring: the glyph to paint for `cp` at a resolved level.
pub const mirror = algorithm.mirror;

pub const isIsolateInitiator = algorithm.isIsolateInitiator;
pub const isRemovedByX9 = algorithm.isRemovedByX9;
pub const isNeutralOrIsolate = algorithm.isNeutralOrIsolate;
pub const isStrong = algorithm.isStrong;

// ============================================================================
// Property-lookup tests (edge cases and exhaustive sweeps)
// ============================================================================

const testing = std.testing;

test "bidiMirroringGlyph: representative ASCII and BMP mirror pairs" {
    try testing.expectEqual(@as(?CodePoint, ')'), bidiMirroringGlyph('('));
    try testing.expectEqual(@as(?CodePoint, '('), bidiMirroringGlyph(')'));
    try testing.expectEqual(@as(?CodePoint, '>'), bidiMirroringGlyph('<'));
    try testing.expectEqual(@as(?CodePoint, '<'), bidiMirroringGlyph('>'));
    try testing.expectEqual(@as(?CodePoint, ']'), bidiMirroringGlyph('['));
    try testing.expectEqual(@as(?CodePoint, '}'), bidiMirroringGlyph('{'));
    // U+00AB / U+00BB guillemets.
    try testing.expectEqual(@as(?CodePoint, 0x00BB), bidiMirroringGlyph(0x00AB));
    try testing.expectEqual(@as(?CodePoint, 0x00AB), bidiMirroringGlyph(0x00BB));
    // A "best fit" pair and a far-apart, asymmetric-looking pair.
    try testing.expectEqual(@as(?CodePoint, 0x220B), bidiMirroringGlyph(0x2208)); // ELEMENT OF
    try testing.expectEqual(@as(?CodePoint, 0x29F5), bidiMirroringGlyph(0x2215)); // DIVISION SLASH -> REVERSE SOLIDUS OPERATOR
    try testing.expectEqual(@as(?CodePoint, 0x2BFE), bidiMirroringGlyph(0x221F)); // RIGHT ANGLE
    // Highest source codepoint listed in the file.
    try testing.expectEqual(@as(?CodePoint, 0xFF62), bidiMirroringGlyph(0xFF63));
}

test "bidiMirroringGlyph: non-mirrored codepoints and out-of-range yield null" {
    try testing.expectEqual(@as(?CodePoint, null), bidiMirroringGlyph('A'));
    try testing.expectEqual(@as(?CodePoint, null), bidiMirroringGlyph('0'));
    try testing.expectEqual(@as(?CodePoint, null), bidiMirroringGlyph(' '));
    try testing.expectEqual(@as(?CodePoint, null), bidiMirroringGlyph(0)); // U+0000 must never be a mirror result
    try testing.expectEqual(@as(?CodePoint, null), bidiMirroringGlyph(0x4E00)); // CJK
    // Bidi_Mirrored=Y but no mirror glyph (listed only in the file's comments).
    try testing.expectEqual(@as(?CodePoint, null), bidiMirroringGlyph(0x221A)); // SQUARE ROOT
    try testing.expectEqual(@as(?CodePoint, null), bidiMirroringGlyph(0x222B)); // INTEGRAL
    // Boundaries.
    try testing.expectEqual(@as(?CodePoint, null), bidiMirroringGlyph(0x10FFFF));
    try testing.expectEqual(@as(?CodePoint, null), bidiMirroringGlyph(0x110000));
    try testing.expectEqual(@as(?CodePoint, null), bidiMirroringGlyph(0x1FFFFF));
}

test "bidiMirroringGlyph: involution over the entire codepoint space" {
    // For every codepoint with a mirror, mirroring twice returns the original,
    // and the mirror target is itself in range. Never traps.
    var cp: CodePoint = 0;
    while (cp <= 0x10FFFF) : (cp += 1) {
        if (bidiMirroringGlyph(cp)) |m| {
            try testing.expect(m != 0);
            try testing.expect(m <= 0x10FFFF);
            const back = bidiMirroringGlyph(m);
            try testing.expectEqual(@as(?CodePoint, cp), back);
        }
    }
}

test "bidiMirroringGlyph: U+0000 is never produced as a mirror result" {
    // The 0 sentinel is only safe because nothing maps *to* U+0000.
    var cp: CodePoint = 0;
    while (cp <= 0x10FFFF) : (cp += 1) {
        if (bidiMirroringGlyph(cp)) |m| try testing.expect(m != 0);
    }
}

test "bidiPairedBracketType: opens, closes, and non-brackets" {
    try testing.expectEqual(BidiPairedBracketType.open, bidiPairedBracketType('('));
    try testing.expectEqual(BidiPairedBracketType.close, bidiPairedBracketType(')'));
    try testing.expectEqual(BidiPairedBracketType.open, bidiPairedBracketType('['));
    try testing.expectEqual(BidiPairedBracketType.close, bidiPairedBracketType(']'));
    try testing.expectEqual(BidiPairedBracketType.open, bidiPairedBracketType('{'));
    try testing.expectEqual(BidiPairedBracketType.close, bidiPairedBracketType('}'));
    // Brackets are mirrored characters but NOT all mirrored chars are brackets.
    try testing.expectEqual(BidiPairedBracketType.none, bidiPairedBracketType('<'));
    try testing.expectEqual(BidiPairedBracketType.none, bidiPairedBracketType('>'));
    try testing.expectEqual(BidiPairedBracketType.none, bidiPairedBracketType('A'));
    try testing.expectEqual(BidiPairedBracketType.none, bidiPairedBracketType(0x00AB)); // guillemet: mirrored, not a bracket
    // Last bracket rows in the file (halfwidth corner brackets).
    try testing.expectEqual(BidiPairedBracketType.open, bidiPairedBracketType(0xFF62));
    try testing.expectEqual(BidiPairedBracketType.close, bidiPairedBracketType(0xFF63));
}

test "bidiPairedBracketType: out-of-range never traps" {
    try testing.expectEqual(BidiPairedBracketType.none, bidiPairedBracketType(0x10FFFF));
    try testing.expectEqual(BidiPairedBracketType.none, bidiPairedBracketType(0x110000));
    try testing.expectEqual(BidiPairedBracketType.none, bidiPairedBracketType(0x1FFFFF));
}

test "bidiPairedBracket: pairs are symmetric and opposite-typed" {
    try testing.expectEqual(@as(?CodePoint, ')'), bidiPairedBracket('('));
    try testing.expectEqual(@as(?CodePoint, '('), bidiPairedBracket(')'));
    try testing.expectEqual(@as(?CodePoint, ']'), bidiPairedBracket('['));
    try testing.expectEqual(@as(?CodePoint, '}'), bidiPairedBracket('{'));
    // Non-brackets have no pairing.
    try testing.expectEqual(@as(?CodePoint, null), bidiPairedBracket('<'));
    try testing.expectEqual(@as(?CodePoint, null), bidiPairedBracket('A'));
    try testing.expectEqual(@as(?CodePoint, null), bidiPairedBracket(0));
    try testing.expectEqual(@as(?CodePoint, null), bidiPairedBracket(0x10FFFF));
    try testing.expectEqual(@as(?CodePoint, null), bidiPairedBracket(0x110000));
}

test "bidiPairedBracket: the tick-corner brackets pair by glyph, not code order" {
    // U+298D..U+2990 are the documented non-obvious pairings: 298D<->2990 and
    // 298E<->298F, rather than the naive 298D<->298E / 298F<->2990.
    try testing.expectEqual(@as(?CodePoint, 0x2990), bidiPairedBracket(0x298D));
    try testing.expectEqual(@as(?CodePoint, 0x298D), bidiPairedBracket(0x2990));
    try testing.expectEqual(@as(?CodePoint, 0x298F), bidiPairedBracket(0x298E));
    try testing.expectEqual(@as(?CodePoint, 0x298E), bidiPairedBracket(0x298F));
    try testing.expectEqual(BidiPairedBracketType.open, bidiPairedBracketType(0x298D));
    try testing.expectEqual(BidiPairedBracketType.close, bidiPairedBracketType(0x298E));
    try testing.expectEqual(BidiPairedBracketType.open, bidiPairedBracketType(0x298F));
    try testing.expectEqual(BidiPairedBracketType.close, bidiPairedBracketType(0x2990));
}

test "bidiPairedBracket: ORNATE PARENTHESES are excluded for legacy reasons" {
    // U+FD3E / U+FD3F do not mirror in bidi and must not be paired brackets.
    try testing.expectEqual(BidiPairedBracketType.none, bidiPairedBracketType(0xFD3E));
    try testing.expectEqual(BidiPairedBracketType.none, bidiPairedBracketType(0xFD3F));
    try testing.expectEqual(@as(?CodePoint, null), bidiPairedBracket(0xFD3E));
    try testing.expectEqual(@as(?CodePoint, null), bidiPairedBracket(0xFD3F));
}

test "bidiPairedBracket: type/pair invariants hold for every codepoint" {
    var cp: CodePoint = 0;
    while (cp <= 0x10FFFF) : (cp += 1) {
        const bpt = bidiPairedBracketType(cp);
        const pair = bidiPairedBracket(cp);
        switch (bpt) {
            .none => {
                // A non-bracket never carries a pairing.
                try testing.expectEqual(@as(?CodePoint, null), pair);
            },
            .open, .close => {
                // Every bracket has a pairing, and the pairing is the opposite
                // type whose own pairing comes back to `cp` (symmetry).
                const p = pair orelse return error.MissingPairing;
                try testing.expect(p != 0);
                try testing.expect(p <= 0x10FFFF);
                const other = bidiPairedBracketType(p);
                if (bpt == .open) {
                    try testing.expectEqual(BidiPairedBracketType.close, other);
                } else {
                    try testing.expectEqual(BidiPairedBracketType.open, other);
                }
                try testing.expectEqual(@as(?CodePoint, cp), bidiPairedBracket(p));
            },
        }
    }
}

test "bidiPairedBracket: every paired bracket also has a mirroring glyph that agrees" {
    // Per UAX #9 a paired bracket has Bidi_M=Y and bmg == bpb. Verify the two
    // independent tables agree wherever a bracket exists.
    var cp: CodePoint = 0;
    while (cp <= 0x10FFFF) : (cp += 1) {
        if (bidiPairedBracketType(cp) != .none) {
            try testing.expectEqual(bidiPairedBracket(cp), bidiMirroringGlyph(cp));
        }
    }
}

test "convenience predicates agree with the underlying property lookups" {
    const samples = [_]CodePoint{ '(', ')', '[', ']', '{', '}', '<', '>', 'A', 0x00AB, 0x298D, 0xFD3E, 0x4E00, 0x10FFFF, 0x110000 };
    for (samples) |cp| {
        try testing.expectEqual(bidiMirroringGlyph(cp) != null, hasMirroringGlyph(cp));
        try testing.expectEqual(bidiPairedBracketType(cp) != .none, isPairedBracket(cp));
        try testing.expectEqual(bidiPairedBracketType(cp) == .open, isOpeningBracket(cp));
        try testing.expectEqual(bidiPairedBracketType(cp) == .close, isClosingBracket(cp));
    }
    try testing.expect(isOpeningBracket('('));
    try testing.expect(isClosingBracket(')'));
    try testing.expect(!isOpeningBracket(')'));
    try testing.expect(isPairedBracket('['));
    try testing.expect(!isPairedBracket('<'));
    try testing.expect(hasMirroringGlyph('<')); // mirrored, even though not a bracket
}

test {
    testing.refAllDecls(@This());
}
