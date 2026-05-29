//! Encoding sub-package. Re-exports the three UTF codec modules and
//! defines the shared types used across the library:
//!
//! - `CodePoint` (u21): the canonical scalar type. All decoder/encoder
//!   APIs in `utf8`, `utf16`, `utf32` produce and consume this type.
//! - `INVALID_CODE_POINT` (U+FFFD): the Unicode Replacement Character.
//!   Lossy decoders substitute this for malformed sequences instead of
//!   returning an error.
//! - `MAX_ASCII` (0x7F): upper bound of the ASCII range, exposed for
//!   fast-path checks in decoders.
//!
//! See `utf8`, `utf16`, `utf32` for the codec APIs (strict / unchecked /
//! lossy variants of validation, decoding, encoding, and traversal).

const std = @import("std");

pub const utf8 = @import("utf8.zig");
pub const utf16 = @import("utf16.zig");
pub const utf32 = @import("utf32.zig");

/// The canonical scalar type. All decoder/encoder
/// APIs in `utf8`, `utf16`, `utf32` produce and consume this type.
pub const CodePoint = u21;

/// Upper bound of the ASCII range (U+007F). Exposed for fast-path checks.
pub const MAX_ASCII = 0x7F;

/// Unicode Replacement Character (U+FFFD). Lossy decoders return this
/// for malformed sequences.
pub const INVALID_CODE_POINT: CodePoint = 0xFFFD;

test {
    std.testing.refAllDecls(utf8);
    std.testing.refAllDecls(utf16);
    std.testing.refAllDecls(utf32);
}
