//! Numeric properties (UAX #44): Numeric_Type and Numeric_Value.
//!
//!   * `numericType(cp)` — Decimal / Digit / Numeric / None. (DerivedNumericType.txt)
//!   * `numericValue(cp)` — the exact rational value of `cp`, or null when it
//!     has no numeric value. (DerivedNumericValues.txt)
//!
//! Both are backed by deduplicated 2-level page tables in `generated/`. The
//! value table stores one entry per *distinct* rational and the page table
//! maps each codepoint to an index, so the millions of value-less codepoints
//! cost nothing beyond a shared zero page.

const std = @import("std");
const encoding = @import("encoding");

const CodePoint = encoding.CodePoint;

/// Generated Numeric_Type page tables and lookup (DerivedNumericType.txt).
/// Exposed for advanced callers; prefer `numericType` for normal use.
pub const generated_type = @import("generated/numeric_type.zig");
/// Generated Numeric_Value tables and lookup (DerivedNumericValues.txt).
/// Exposed for advanced callers; prefer `numericValue` for normal use.
pub const generated_values = @import("generated/numeric_values.zig");

/// Numeric_Type enum: `.none`, `.decimal`, `.digit`, or `.numeric`.
pub const NumericType = generated_type.NumericType;
/// An exact numeric value as a rational `{ numerator: i64, denominator: i64 }`.
/// The denominator is always positive.
pub const NumericValue = generated_values.NumericValue;

/// Numeric_Type of `cp` (`.none`, `.decimal`, `.digit`, or `.numeric`).
pub const numericType = generated_type.numericType;

/// Numeric_Value of `cp` as an exact rational, or null when `cp` has no
/// numeric value. Note a value of *zero* (e.g. DIGIT ZERO) is `.{ .numerator
/// = 0, .denominator = 1 }`, distinct from null.
///
/// @stable-since: v0.1.0
pub inline fn numericValue(cp: CodePoint) ?NumericValue {
    const idx = generated_values.numericValueIndex(cp);
    if (idx == 0) return null;
    return generated_values.numeric_values[idx];
}

/// True when `cp` carries a Numeric_Value (equivalently, Numeric_Type != none).
///
/// @stable-since: v0.1.0
pub inline fn hasNumericValue(cp: CodePoint) bool {
    return generated_values.numericValueIndex(cp) != 0;
}

/// The numeric value of `cp` as an `f64`, or null when it has none. Convenience
/// for callers that don't need exact rationals; precision is limited by `f64`.
///
/// @stable-since: v0.1.0
pub inline fn numericValueAsFloat(cp: CodePoint) ?f64 {
    const v = numericValue(cp) orelse return null;
    return @as(f64, @floatFromInt(v.numerator)) / @as(f64, @floatFromInt(v.denominator));
}

// ============================================================================
// Hostile / edge-case tests
// ============================================================================

const testing = std.testing;

test "numericType: decimal digits, fractions, roman numerals, and non-numerics" {
    try testing.expectEqual(NumericType.decimal, numericType('0'));
    try testing.expectEqual(NumericType.decimal, numericType('5'));
    try testing.expectEqual(NumericType.decimal, numericType('9'));
    // SUPERSCRIPT TWO: a Digit (field 7), not Decimal.
    try testing.expectEqual(NumericType.digit, numericType(0x00B2));
    // VULGAR FRACTION ONE QUARTER and ROMAN NUMERAL ONE: Numeric.
    try testing.expectEqual(NumericType.numeric, numericType(0x00BC));
    try testing.expectEqual(NumericType.numeric, numericType(0x2160));
    // Letters and punctuation are None.
    try testing.expectEqual(NumericType.none, numericType('A'));
    try testing.expectEqual(NumericType.none, numericType('+'));
    try testing.expectEqual(NumericType.none, numericType(' '));
}

test "numericType: out-of-range never traps" {
    try testing.expectEqual(NumericType.none, numericType(0x10FFFF));
    try testing.expectEqual(NumericType.none, numericType(0x110000));
    try testing.expectEqual(NumericType.none, numericType(0x1FFFFF));
}

test "numericValue: integers, zero, fractions, negatives" {
    try testing.expectEqual(@as(?NumericValue, .{ .numerator = 0, .denominator = 1 }), numericValue('0'));
    try testing.expectEqual(@as(?NumericValue, .{ .numerator = 9, .denominator = 1 }), numericValue('9'));
    try testing.expectEqual(@as(?NumericValue, .{ .numerator = 1, .denominator = 2 }), numericValue(0x00BD)); // ONE HALF
    try testing.expectEqual(@as(?NumericValue, .{ .numerator = 3, .denominator = 4 }), numericValue(0x00BE)); // THREE QUARTERS
    try testing.expectEqual(@as(?NumericValue, .{ .numerator = 1, .denominator = 6 }), numericValue(0x2159)); // ONE SIXTH
    try testing.expectEqual(@as(?NumericValue, .{ .numerator = -1, .denominator = 2 }), numericValue(0x0F33)); // TIBETAN DIGIT HALF ZERO
    // VULGAR FRACTION ZERO THIRDS — the file records this as the integer 0.
    try testing.expectEqual(@as(?NumericValue, .{ .numerator = 0, .denominator = 1 }), numericValue(0x2189));
    try testing.expectEqual(@as(?NumericValue, .{ .numerator = 1, .denominator = 1 }), numericValue(0x2160)); // ROMAN NUMERAL ONE
}

test "numericValue: a value of zero is distinct from no value" {
    // DIGIT ZERO has a numeric value (0), so it is non-null...
    const z = numericValue('0');
    try testing.expect(z != null);
    try testing.expectEqual(@as(i64, 0), z.?.numerator);
    try testing.expect(hasNumericValue('0'));
    // ...while a letter has none.
    try testing.expectEqual(@as(?NumericValue, null), numericValue('A'));
    try testing.expect(!hasNumericValue('A'));
}

test "numericValue: out-of-range and value-less codepoints yield null" {
    try testing.expectEqual(@as(?NumericValue, null), numericValue(' '));
    try testing.expectEqual(@as(?NumericValue, null), numericValue(0x10FFFF));
    try testing.expectEqual(@as(?NumericValue, null), numericValue(0x110000));
    try testing.expectEqual(@as(?NumericValue, null), numericValue(0x1FFFFF));
}

test "numericValue: denominator is always positive and lookups never trap" {
    var cp: CodePoint = 0;
    while (cp <= 0x10FFFF) : (cp += 1) {
        if (numericValue(cp)) |v| {
            try testing.expect(v.denominator > 0);
        }
    }
}

test "numericType and numericValue agree: type==none iff no value" {
    // Per the derivation, a codepoint has a Numeric_Value exactly when its
    // Numeric_Type is not None.
    var cp: CodePoint = 0;
    while (cp <= 0x10FFFF) : (cp += 1) {
        const has = hasNumericValue(cp);
        const typed = numericType(cp) != .none;
        try testing.expectEqual(typed, has);
    }
}

test "numericValueAsFloat: matches the rational for representative values" {
    try testing.expectEqual(@as(?f64, 0.5), numericValueAsFloat(0x00BD));
    try testing.expectEqual(@as(?f64, 9.0), numericValueAsFloat('9'));
    try testing.expectEqual(@as(?f64, -0.5), numericValueAsFloat(0x0F33));
    try testing.expectEqual(@as(?f64, null), numericValueAsFloat('A'));
}

test {
    testing.refAllDecls(@This());
}
