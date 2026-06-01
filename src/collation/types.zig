const std = @import("std");

pub const VariableWeighting = enum {
    non_ignorable,
    shifted,
};

pub const Strength = enum {
    primary,
    secondary,
    tertiary,
    quaternary,
    identical,
};

pub const Options = struct {
    variable_weighting: VariableWeighting = .non_ignorable,
    strength: Strength = .tertiary,
    normalization: bool = true,
};

pub const Order = std.math.Order;
