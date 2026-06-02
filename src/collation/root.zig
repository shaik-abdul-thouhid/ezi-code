//! Default Unicode Collation Algorithm (UCA) using the DUCET.
//!
//! This module is DUCET-only (no locale tailorings). It supports the two UCA
//! conformance configurations shipped by Unicode: NON_IGNORABLE and SHIFTED.

const std = @import("std");
const build_options = @import("build_options");

/// Collation configuration types (`Options`, `Strength`, `VariableWeighting`, `Order`).
pub const types = @import("types.zig");
/// The UCA collator: builds sort keys and compares strings. See `collator.zig`.
pub const Collator = @import("collator.zig").Collator;
/// A reusable sort key holding per-level weights plus the NFD form. See `collator.zig`.
pub const Key = @import("collator.zig").Key;
/// Compare two serialized sort keys without allocating. See `Key.serializeInto`.
pub const compareSerializedKeys = @import("collator.zig").compareSerializedKeys;
/// Collation configuration. See `types.Options`.
pub const Options = types.Options;
/// Deepest weight level compared. See `types.Strength`.
pub const Strength = types.Strength;
/// Variable-element handling. See `types.VariableWeighting`.
pub const VariableWeighting = types.VariableWeighting;
/// Comparison result alias for `std.math.Order`.
pub const Order = types.Order;

/// Auto-generated DUCET collation element tables and lookup helpers.
pub const generated = @import("generated/ducet.zig");

const conformance_tests = @import("tests/uca_conformance.zig");
const sort_key_tests = @import("tests/sort_key.zig");

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(sort_key_tests);
    if (build_options.include_conformance) {
        std.testing.refAllDecls(conformance_tests);
    }
}
