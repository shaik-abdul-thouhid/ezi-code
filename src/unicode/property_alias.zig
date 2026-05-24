const CodePoint = @import("encoding").CodePoint;

pub const CanonicalCombiningClass = enum(u8) {
    not_reordered = 0,
    overlay = 1,
    han_reading = 6,
    nukta = 7,
    kana_voicing = 8,
    virama = 9,
    ccc10 = 10,
    ccc11 = 11,
    ccc12 = 12,
    ccc13 = 13,
    ccc14 = 14,
    ccc15 = 15,
    ccc16 = 16,
    ccc17 = 17,
    ccc18 = 18,
    ccc19 = 19,
    ccc20 = 20,
    ccc21 = 21,
    ccc22 = 22,
    ccc23 = 23,
    ccc24 = 24,
    ccc25 = 25,
    ccc26 = 26,
    ccc27 = 27,
    ccc28 = 28,
    ccc29 = 29,
    ccc30 = 30,
    ccc31 = 31,
    ccc32 = 32,
    ccc33 = 33,
    ccc34 = 34,
    ccc35 = 35,
    ccc36 = 36,
    ccc84 = 84,
    ccc91 = 91,
    ccc103 = 103,
    ccc107 = 107,
    ccc118 = 118,
    ccc122 = 122,
    ccc129 = 129,
    ccc130 = 130,
    ccc132 = 132,
    ccc133 = 133,
    attached_below_left = 200,
    attached_below = 202,
    attached_above = 214,
    attached_above_right = 216,
    below_left = 218,
    below = 220,
    below_right = 222,
    left = 224,
    right = 226,
    above_left = 228,
    above = 230,
    above_right = 232,
    double_below = 233,
    double_above = 234,
    iota_subscript = 240,

    _,

    pub fn fromU8(c: u8) CanonicalCombiningClass {
        return @enumFromInt(c);
    }
};

pub const CaseFoldingMode = enum { simple, full };

pub const CaseFoldingLocale = enum { default, turkic };

pub fn FoldResult(comptime mode: CaseFoldingMode) type {
    return switch (mode) {
        .simple => CodePoint,
        .full => []const CodePoint,
    };
}
