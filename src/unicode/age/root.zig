//! The Age property (UAX #44, DerivedAge.txt): the Unicode version in which a
//! codepoint was first assigned.
//!
//! `age(cp)` returns an `Age` enum whose variants are `v{major}_{minor}` (plus
//! `unassigned`), ordered by release. `version(a)` unpacks a non-`unassigned`
//! value into a `{ major, minor }` pair for numeric comparison. Backed by a
//! deduplicated 2-level page table in `generated/`.

const std = @import("std");
const encoding = @import("encoding");

const CodePoint = encoding.CodePoint;

/// The generated Age data: the deduplicated 2-level page table plus the `Age`
/// enum and `Version` struct it is built around. Imported for re-export; most
/// callers should use the wrappers below rather than reach in directly.
pub const generated = @import("generated/derived_age.zig");

/// Enumerates every Unicode release that has assigned code points, as
/// `v{major}_{minor}` variants ordered by release, plus `.unassigned`. The
/// value `age(cp)` returns; pair with `version` to recover numeric components.
pub const Age = generated.Age;

/// A decoded `{ major, minor }` Unicode version number, returned by `version`
/// and `assignedIn`.
pub const Version = generated.Version;

/// The Age of `cp`: the Unicode version it was first assigned in, or
/// `.unassigned` if it is not yet assigned (or above U+10FFFF).
/// @stable-since: v0.1.0
pub const age = generated.age;

/// The `{ major, minor }` version a non-`unassigned` `Age` denotes, else null.
/// @stable-since: v0.1.0
pub const version = generated.version;

/// The Unicode version `cp` was first assigned in, or null when unassigned.
/// @stable-since: v0.1.0
pub inline fn assignedIn(cp: CodePoint) ?Version {
    return version(age(cp));
}

/// True when `cp` is assigned in the current Unicode version.
/// @stable-since: v0.1.0
pub inline fn isAssigned(cp: CodePoint) bool {
    return age(cp) != .unassigned;
}

// ============================================================================
// Hostile / edge-case tests
// ============================================================================

const testing = std.testing;

test "age: ASCII and Latin-1 are Unicode 1.1" {
    try testing.expectEqual(Age.v1_1, age('A'));
    try testing.expectEqual(Age.v1_1, age(' '));
    try testing.expectEqual(Age.v1_1, age(0x00A9)); // COPYRIGHT SIGN
}

test "age: later assignments carry their introducing version" {
    try testing.expectEqual(Age.v10_0, age(0x20BF)); // BITCOIN SIGN (Unicode 10.0)

    // At least one codepoint must be tagged with the newest version (17.0);
    // find it by scanning rather than hardcoding a fragile sample.
    var found_v17 = false;
    var cp: CodePoint = 0;
    while (cp <= 0x10FFFF) : (cp += 1) {
        if (age(cp) == .v17_0) {
            found_v17 = true;
            try testing.expectEqual(@as(?Version, .{ .major = 17, .minor = 0 }), assignedIn(cp));
            break;
        }
    }
    try testing.expect(found_v17);
}

test "age: unassigned codepoints and out-of-range are .unassigned" {
    try testing.expectEqual(Age.unassigned, age(0x0378)); // unassigned in Unicode 17
    try testing.expectEqual(Age.unassigned, age(0x110000));
    try testing.expectEqual(Age.unassigned, age(0x1FFFFF));
    try testing.expectEqual(@as(?Version, null), assignedIn(0x0378));
    try testing.expect(!isAssigned(0x0378));
    try testing.expect(!isAssigned(0x110000));
}

test "version: round-trips and unassigned maps to null" {
    try testing.expectEqual(@as(?Version, .{ .major = 1, .minor = 1 }), version(.v1_1));
    try testing.expectEqual(@as(?Version, .{ .major = 10, .minor = 0 }), version(.v10_0));
    try testing.expectEqual(@as(?Version, .{ .major = 17, .minor = 0 }), version(.v17_0));
    try testing.expectEqual(@as(?Version, null), version(.unassigned));
}

test "age: every codepoint maps to a valid enum variant, never traps" {
    const field_count = @typeInfo(Age).@"enum".fields.len;
    var cp: CodePoint = 0;
    while (cp <= 0x10FFFF) : (cp += 1) {
        const a = age(cp);
        try testing.expect(@intFromEnum(a) < field_count);
        // assignedIn agrees with the enum: null exactly when unassigned.
        try testing.expectEqual(a == .unassigned, assignedIn(cp) == null);
    }
}

test "age: enum variants are ordered by ascending version" {
    // The generator emits versions in release order; confirm the parallel
    // version table is monotonically non-decreasing.
    const fields = @typeInfo(Age).@"enum".fields;
    var prev: Version = .{ .major = 0, .minor = 0 };
    inline for (fields) |f| {
        const a: Age = @enumFromInt(f.value);
        if (version(a)) |v| {
            const ge = v.major > prev.major or (v.major == prev.major and v.minor >= prev.minor);
            try testing.expect(ge);
            prev = v;
        }
    }
}

test {
    testing.refAllDecls(@This());
}
