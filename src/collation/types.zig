const std = @import("std");

/// How variable collation elements (punctuation, symbols, and other
/// variable-weighted characters) are handled, per UTS #10:
///
/// - `non_ignorable` — variable elements keep their primary weights and sort
///   like any other character (the default).
/// - `shifted` — variable elements have their primary weight moved to the
///   quaternary level, so they sort after letters but are ignored at the
///   primary/secondary/tertiary levels.
///
/// @stable-since: v0.2.0
pub const VariableWeighting = enum {
    non_ignorable,
    shifted,
};

/// Collation strength: the deepest weight level compared, and therefore which
/// distinctions are significant. Each level subsumes the ones above it.
///
/// - `primary` — base characters only (letters); ignores accents and case.
/// - `secondary` — adds accents / diacritics.
/// - `tertiary` — adds case (the default).
/// - `quaternary` — adds punctuation position (meaningful under `shifted`).
/// - `identical` — adds an NFD code-point tiebreaker for byte-level uniqueness.
///
/// @stable-since: v0.2.0
pub const Strength = enum {
    primary,
    secondary,
    tertiary,
    quaternary,
    identical,
};

/// Configuration for a collation run. The defaults give a standard
/// dictionary-style sort: non-ignorable variables, tertiary strength, and NFD
/// normalization applied before weighting.
///
/// @stable-since: v0.2.0
pub const Options = struct {
    /// How variable collation elements are weighted. See `VariableWeighting`.
    variable_weighting: VariableWeighting = .non_ignorable,
    /// Deepest weight level compared. See `Strength`.
    strength: Strength = .tertiary,
    /// Apply NFD normalization before building weights. Disable only when the
    /// input is already NFD-normalized (faster, but otherwise incorrect).
    normalization: bool = true,
};

/// Result of a comparison: `.lt`, `.eq`, or `.gt`. Alias for `std.math.Order`.
///
/// @stable-since: v0.2.0
pub const Order = std.math.Order;
