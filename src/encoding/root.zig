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

/// Boolean form of `validateCodePoint`: returns `true` when `code_point` is a
/// Unicode scalar value (in `0..=0x10FFFF` and not a surrogate), `false`
/// otherwise. Convenient where the failure reason is not needed.
///
/// @stable-since: v0.2.0
pub fn isValidCodePoint(code_point: CodePoint) bool {
    validateCodePoint(code_point) catch return false;
    return true;
}

/// Returns `true` when `code_point` lies in the UTF-16 surrogate range
/// (U+D800..U+DFFF). Surrogates are never valid scalar values; this is the
/// code-point-level counterpart of `utf16.isHighSurrogate` / `utf16.isLowSurrogate`.
///
/// @stable-since: v0.2.0
pub fn isSurrogateCodePoint(code_point: CodePoint) bool {
    return code_point >= SURROGATE_RANGE_START and code_point <= SURROGATE_RANGE_END;
}

/// Returns `true` when `code_point` is in the ASCII range (U+0000..U+007F).
/// Exposed alongside `MAX_ASCII` for fast-path classification.
///
/// @stable-since: v0.2.0
pub fn isAscii(code_point: CodePoint) bool {
    return code_point <= MAX_ASCII;
}

/// Returns `true` when `code_point` is a supplementary-plane scalar
/// (U+10000..U+10FFFF), i.e. anything outside the Basic Multilingual Plane.
/// No validity check is performed; pair with `isValidCodePoint` for untrusted
/// input.
///
/// @stable-since: v0.2.0
pub fn isSupplementary(code_point: CodePoint) bool {
    return code_point >= 0x10000;
}

test {
    std.testing.refAllDecls(utf8);
    std.testing.refAllDecls(utf16);
    std.testing.refAllDecls(utf32);
}
