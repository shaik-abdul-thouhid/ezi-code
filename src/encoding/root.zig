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
/// This type is a contract that the given value is valid.
/// Any functions taking this as input, assume that the code point is
/// valid unless specified.
pub const CodePoint = u21;

/// Upper bound of the ASCII range (U+007F). Exposed for fast-path checks.
pub const MAX_ASCII = 0x7F;

/// Unicode Replacement Character (U+FFFD). Lossy decoders return this
/// for malformed sequences.
pub const INVALID_CODE_POINT: CodePoint = 0xFFFD;

const ENCODING_RANGE_END = 0x10FFFF;

const SURROGATE_RANGE_START: u16 = 0xD800;
const SURROGATE_RANGE_END: u16 = 0xDFFF;

/// Validates a given CodePoint. Returns error set if the codePoint
/// is invalid. Doesn't fail for reserved CodePoints.
///
/// @stable-since: v0.1.0
pub fn validateCodePoint(code_point: CodePoint) error{ CodePointTooLarge, SurrogateCodePoint }!void {
    if (code_point > ENCODING_RANGE_END) {
        return error.CodePointTooLarge;
    }

    if (code_point >= SURROGATE_RANGE_START and code_point <= SURROGATE_RANGE_END) {
        return error.SurrogateCodePoint;
    }
}

test {
    std.testing.refAllDecls(utf8);
    std.testing.refAllDecls(utf16);
    std.testing.refAllDecls(utf32);
}
