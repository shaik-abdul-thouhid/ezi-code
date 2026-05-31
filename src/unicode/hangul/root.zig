//! The Hangul_Syllable_Type property (UAX #44, HangulSyllableType.txt).
//!
//! `hangulSyllableType(cp)` classifies a codepoint as a conjoining jamo
//! (`l`/`v`/`t` — Leading / Vowel / Trailing) or a precomposed syllable
//! (`lv`/`lvt`), or `not_applicable` for everything else. This is the static
//! property table; the algorithmic jamo<->syllable composition arithmetic of
//! UAX #15 lives in the normalization module, not here.
//!
//! Backed by a deduplicated 2-level page table in `generated/`.

const std = @import("std");
const encoding = @import("encoding");

const CodePoint = encoding.CodePoint;

/// The generated backing module: a deduplicated 2-level page table encoding
/// the Hangul_Syllable_Type property for every codepoint. Prefer the
/// re-exports below; this is exposed for direct access to the raw table.
pub const generated = @import("generated/hangul_syllable_type.zig");

/// The Hangul_Syllable_Type enum (`l`, `v`, `t`, `lv`, `lvt`,
/// `not_applicable`), re-exported from the generated table.
pub const HangulSyllableType = generated.HangulSyllableType;

/// Hangul_Syllable_Type of `cp` (`.l`, `.v`, `.t`, `.lv`, `.lvt`, or
/// `.not_applicable`).
///
/// Total over all `u21` inputs; out-of-range and non-Hangul codepoints map to
/// `.not_applicable`, so no validation of `cp` is required.
/// @stable-since: v0.1.0
pub const hangulSyllableType = generated.hangulSyllableType;

/// True when `cp` is a conjoining jamo (Leading, Vowel, or Trailing).
/// @stable-since: v0.1.0
pub inline fn isConjoiningJamo(cp: CodePoint) bool {
    return switch (hangulSyllableType(cp)) {
        .l, .v, .t => true,
        else => false,
    };
}

/// True when `cp` is a precomposed Hangul syllable (LV or LVT).
/// @stable-since: v0.1.0
pub inline fn isSyllable(cp: CodePoint) bool {
    return switch (hangulSyllableType(cp)) {
        .lv, .lvt => true,
        else => false,
    };
}

// ============================================================================
// Hostile / edge-case tests
// ============================================================================

const testing = std.testing;

test "hangulSyllableType: jamo and syllable representatives" {
    try testing.expectEqual(HangulSyllableType.l, hangulSyllableType(0x1100)); // CHOSEONG KIYEOK
    try testing.expectEqual(HangulSyllableType.l, hangulSyllableType(0x115F)); // CHOSEONG FILLER
    try testing.expectEqual(HangulSyllableType.v, hangulSyllableType(0x1160)); // JUNGSEONG FILLER
    try testing.expectEqual(HangulSyllableType.v, hangulSyllableType(0x11A7)); // JUNGSEONG O-YAE
    try testing.expectEqual(HangulSyllableType.t, hangulSyllableType(0x11A8)); // JONGSEONG KIYEOK
    try testing.expectEqual(HangulSyllableType.t, hangulSyllableType(0x11FF)); // JONGSEONG SSANGNIEUN
    // AC00 GA is LV (no trailing consonant); AC01 GAG is LVT.
    try testing.expectEqual(HangulSyllableType.lv, hangulSyllableType(0xAC00));
    try testing.expectEqual(HangulSyllableType.lvt, hangulSyllableType(0xAC01));
    // Extended jamo (A960 block, D7B0 block).
    try testing.expectEqual(HangulSyllableType.l, hangulSyllableType(0xA960));
    try testing.expectEqual(HangulSyllableType.v, hangulSyllableType(0xD7B0));
    try testing.expectEqual(HangulSyllableType.t, hangulSyllableType(0xD7CB));
}

test "hangulSyllableType: non-Hangul and out-of-range are not_applicable" {
    try testing.expectEqual(HangulSyllableType.not_applicable, hangulSyllableType('A'));
    try testing.expectEqual(HangulSyllableType.not_applicable, hangulSyllableType(0x4E00)); // CJK
    try testing.expectEqual(HangulSyllableType.not_applicable, hangulSyllableType(0xABFF)); // just before AC00
    try testing.expectEqual(HangulSyllableType.not_applicable, hangulSyllableType(0xD7A4)); // gap after last syllable D7A3
    try testing.expectEqual(HangulSyllableType.not_applicable, hangulSyllableType(0x10FFFF));
    try testing.expectEqual(HangulSyllableType.not_applicable, hangulSyllableType(0x110000));
    try testing.expectEqual(HangulSyllableType.not_applicable, hangulSyllableType(0x1FFFFF));
}

test "hangulSyllableType: the AC00..D7A3 syllable block is entirely LV or LVT" {
    // Every precomposed syllable is LV exactly when (cp - AC00) % 28 == 0
    // (no trailing jamo), else LVT. Verify the table matches that arithmetic.
    var cp: CodePoint = 0xAC00;
    while (cp <= 0xD7A3) : (cp += 1) {
        const want: HangulSyllableType = if ((cp - 0xAC00) % 28 == 0) .lv else .lvt;
        try testing.expectEqual(want, hangulSyllableType(cp));
    }
}

test "convenience predicates agree with the property lookup" {
    try testing.expect(isConjoiningJamo(0x1100));
    try testing.expect(isConjoiningJamo(0x1160));
    try testing.expect(isConjoiningJamo(0x11A8));
    try testing.expect(!isConjoiningJamo(0xAC00));
    try testing.expect(isSyllable(0xAC00));
    try testing.expect(isSyllable(0xAC01));
    try testing.expect(!isSyllable(0x1100));
    try testing.expect(!isSyllable('A'));
    try testing.expect(!isConjoiningJamo('A'));
}

test {
    testing.refAllDecls(@This());
}
