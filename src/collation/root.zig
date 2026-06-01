//! Default Unicode Collation Algorithm (UCA) using the DUCET.
//!
//! This module is DUCET-only (no locale tailorings). It supports the two UCA
//! conformance configurations shipped by Unicode: NON_IGNORABLE and SHIFTED.

const std = @import("std");
const build_options = @import("build_options");

pub const types = @import("types.zig");
pub const Collator = @import("collator.zig").Collator;
pub const Key = @import("collator.zig").Key;
pub const Options = types.Options;
pub const Strength = types.Strength;
pub const VariableWeighting = types.VariableWeighting;
pub const Order = types.Order;

pub const generated = @import("generated/ducet.zig");

const conformance_tests = @import("tests/uca_conformance.zig");

test {
    std.testing.refAllDecls(@This());
    if (build_options.include_conformance) {
        std.testing.refAllDecls(conformance_tests);
    }
}
