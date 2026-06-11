//! Byte Order Mark (BOM) detection, stripping, and emission for the three
//! UTF encoding forms. A BOM is the encoded form of U+FEFF at the start of a
//! byte stream; it identifies the encoding form and (for UTF-16/32) the byte
//! order. The codecs themselves never consume or produce BOMs — this module
//! is the explicit seam: detect/strip on ingest, write the constants on
//! output.
//!
//! Detection is longest-match: `FF FE 00 00` is reported as the UTF-32 LE
//! mark, not as a UTF-16 LE mark followed by U+0000. Callers that know their
//! input is UTF-16 should check `Bom.utf16_le.match(bytes)` directly instead
//! of `detect`.

const std = @import("std");
const utils = @import("utils");

/// Byte order used when interpreting stored UTF-16/UTF-32 code units.
pub const Endian = utils.Endian;

/// The encoded BOM for UTF-8 (`EF BB BF`). UTF-8 has no byte order; this
/// mark only signals "this is UTF-8".
pub const UTF8_BOM = "\xEF\xBB\xBF";
/// The encoded BOM for little-endian UTF-16 (`FF FE`).
pub const UTF16_LE_BOM = "\xFF\xFE";
/// The encoded BOM for big-endian UTF-16 (`FE FF`).
pub const UTF16_BE_BOM = "\xFE\xFF";
/// The encoded BOM for little-endian UTF-32 (`FF FE 00 00`).
pub const UTF32_LE_BOM = "\xFF\xFE\x00\x00";
/// The encoded BOM for big-endian UTF-32 (`00 00 FE FF`).
pub const UTF32_BE_BOM = "\x00\x00\xFE\xFF";

/// The five encoding-form marks a byte stream can open with.
///
/// @stable-since: v0.4.0
pub const Bom = enum {
    utf8,
    utf16_le,
    utf16_be,
    utf32_le,
    utf32_be,

    /// The encoded bytes of this mark, suitable for writing at the start of
    /// an output stream.
    ///
    /// @stable-since: v0.4.0
    pub fn bytes(self: Bom) []const u8 {
        return switch (self) {
            .utf8 => UTF8_BOM,
            .utf16_le => UTF16_LE_BOM,
            .utf16_be => UTF16_BE_BOM,
            .utf32_le => UTF32_LE_BOM,
            .utf32_be => UTF32_BE_BOM,
        };
    }

    /// Byte length of this mark (3 for UTF-8, 2 for UTF-16, 4 for UTF-32).
    ///
    /// @stable-since: v0.4.0
    pub fn len(self: Bom) usize {
        return self.bytes().len;
    }

    /// The byte order this mark declares, or `null` for UTF-8 (which has
    /// none). Feed the result to the UTF-16/32 views and transcoders.
    ///
    /// @stable-since: v0.4.0
    pub fn endian(self: Bom) ?Endian {
        return switch (self) {
            .utf8 => null,
            .utf16_le, .utf32_le => .little,
            .utf16_be, .utf32_be => .big,
        };
    }

    /// True when `data` starts with exactly this mark. Unlike `detect`, no
    /// longest-match policy applies: `Bom.utf16_le.match("\xFF\xFE\x00\x00")`
    /// is `true`.
    ///
    /// @stable-since: v0.4.0
    pub fn match(self: Bom, data: []const u8) bool {
        return std.mem.startsWith(u8, data, self.bytes());
    }
};

/// Detects a leading BOM, or returns `null` when `data` opens with none.
/// Longest match wins: `FF FE 00 00` reports `.utf32_le`, not `.utf16_le`.
/// A `null` result does NOT mean the data is unencoded or invalid — most
/// UTF-8 text carries no BOM.
///
/// @stable-since: v0.4.0
pub fn detect(data: []const u8) ?Bom {
    // UTF-32 marks first: each contains (LE) or could be shadowed by (BE
    // vs. none) a shorter mark.
    if (Bom.utf32_le.match(data)) return .utf32_le;
    if (Bom.utf32_be.match(data)) return .utf32_be;
    if (Bom.utf8.match(data)) return .utf8;
    if (Bom.utf16_le.match(data)) return .utf16_le;
    if (Bom.utf16_be.match(data)) return .utf16_be;
    return null;
}

/// Returns `data` with its leading BOM removed, or `data` unchanged when no
/// BOM is present. Zero-copy: the result is a sub-slice of `data`. Uses the
/// same longest-match policy as `detect`.
///
/// @stable-since: v0.4.0
pub fn strip(data: []const u8) []const u8 {
    const mark = detect(data) orelse return data;
    return data[mark.len()..];
}

test "detect: each mark, longest-match ambiguity, and clean inputs" {
    try std.testing.expectEqual(@as(?Bom, .utf8), detect("\xEF\xBB\xBFhello"));
    try std.testing.expectEqual(@as(?Bom, .utf16_le), detect("\xFF\xFEh\x00"));
    try std.testing.expectEqual(@as(?Bom, .utf16_be), detect("\xFE\xFF\x00h"));
    try std.testing.expectEqual(@as(?Bom, .utf32_be), detect("\x00\x00\xFE\xFFrest"));

    // The ambiguous prefix: UTF-32 LE wins over UTF-16 LE + U+0000.
    try std.testing.expectEqual(@as(?Bom, .utf32_le), detect("\xFF\xFE\x00\x00"));
    // ...but a direct match query ignores the policy.
    try std.testing.expect(Bom.utf16_le.match("\xFF\xFE\x00\x00"));

    try std.testing.expectEqual(@as(?Bom, null), detect("plain text"));
    try std.testing.expectEqual(@as(?Bom, null), detect(""));
    try std.testing.expectEqual(@as(?Bom, null), detect("\xEF\xBB")); // truncated mark
}

test "strip: removes exactly the detected mark, zero-copy" {
    try std.testing.expectEqualStrings("hello", strip("\xEF\xBB\xBFhello"));
    try std.testing.expectEqualStrings("plain", strip("plain"));
    try std.testing.expectEqualStrings("", strip("\xFF\xFE\x00\x00"));

    const data = "\xEF\xBB\xBFbody";
    const stripped = strip(data);
    try std.testing.expectEqual(@intFromPtr(data.ptr) + 3, @intFromPtr(stripped.ptr));
}

test "Bom: bytes/len/endian are consistent" {
    inline for (@typeInfo(Bom).@"enum".field_values) |fv| {
        const mark: Bom = @enumFromInt(fv);
        try std.testing.expectEqual(mark.bytes().len, mark.len());
        try std.testing.expect(mark.match(mark.bytes()));
        try std.testing.expectEqual(@as(?Bom, mark), detect(mark.bytes()));
    }

    try std.testing.expectEqual(@as(?Endian, null), Bom.utf8.endian());
    try std.testing.expectEqual(@as(?Endian, .little), Bom.utf16_le.endian());
    try std.testing.expectEqual(@as(?Endian, .big), Bom.utf32_be.endian());
}
