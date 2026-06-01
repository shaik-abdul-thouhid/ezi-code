const std = @import("std");

const encoding = @import("encoding");
const unicode = @import("unicode");

const types = @import("types.zig");
pub const Options = types.Options;
pub const Strength = types.Strength;
pub const VariableWeighting = types.VariableWeighting;
pub const Order = types.Order;

const ducet = @import("generated/ducet.zig");

const Allocator = std.mem.Allocator;
const CodePoint = encoding.CodePoint;

pub const Key = struct {
    primary: std.ArrayListUnmanaged(u16) = .empty,
    secondary: std.ArrayListUnmanaged(u16) = .empty,
    tertiary: std.ArrayListUnmanaged(u16) = .empty,
    quaternary: std.ArrayListUnmanaged(u16) = .empty,
    nfd: std.ArrayListUnmanaged(CodePoint) = .empty,
    work: std.ArrayListUnmanaged(CodePoint) = .empty,

    pub fn clearRetainingCapacity(self: *Key) void {
        self.primary.clearRetainingCapacity();
        self.secondary.clearRetainingCapacity();
        self.tertiary.clearRetainingCapacity();
        self.quaternary.clearRetainingCapacity();
        self.nfd.clearRetainingCapacity();
        self.work.clearRetainingCapacity();
    }

    pub fn deinit(self: *Key, allocator: Allocator) void {
        self.primary.deinit(allocator);
        self.secondary.deinit(allocator);
        self.tertiary.deinit(allocator);
        self.quaternary.deinit(allocator);
        self.nfd.deinit(allocator);
        self.work.deinit(allocator);
        self.* = undefined;
    }

    /// Returns the byte length of the serialized sort key for the given options.
    /// The result is exactly how many bytes `serializeInto` will write.
    pub fn serializedLen(self: *const Key, options: Options) usize {
        var len: usize = self.primary.items.len * 2;
        if (options.strength == .primary) return len;
        len += 2 + self.secondary.items.len * 2;
        if (options.strength == .secondary) return len;
        len += 2 + self.tertiary.items.len * 2;
        if (options.strength == .tertiary) return len;
        if (options.variable_weighting == .shifted) len += 2 + self.quaternary.items.len * 2;
        if (options.strength == .quaternary) return len;
        // identical: 2-byte separator + NFD codepoints encoded as 3-byte big-endian each
        len += 2 + self.nfd.items.len * 3;
        return len;
    }

    /// Writes the sort key into `buf` and returns the written slice.
    /// `buf` must be at least `serializedLen(options)` bytes long.
    ///
    /// Format: big-endian u16 weight sequences separated by 0x0000 level markers,
    /// one per strength level included by `options`. The identical level appends
    /// NFD codepoints as 3-byte big-endian values after the final separator.
    /// Two sort keys produced with the same options compare with `std.mem.order`
    /// exactly as `Collator.compareKeys` would compare the originating `Key` values.
    pub fn serializeInto(self: *const Key, options: Options, buf: []u8) []u8 {
        std.debug.assert(buf.len >= self.serializedLen(options));
        var pos: usize = 0;

        for (self.primary.items) |w| {
            buf[pos] = @intCast(w >> 8);
            buf[pos + 1] = @intCast(w & 0xFF);
            pos += 2;
        }
        if (options.strength == .primary) return buf[0..pos];

        buf[pos] = 0;
        buf[pos + 1] = 0;
        pos += 2;
        for (self.secondary.items) |w| {
            buf[pos] = @intCast(w >> 8);
            buf[pos + 1] = @intCast(w & 0xFF);
            pos += 2;
        }
        if (options.strength == .secondary) return buf[0..pos];

        buf[pos] = 0;
        buf[pos + 1] = 0;
        pos += 2;
        for (self.tertiary.items) |w| {
            buf[pos] = @intCast(w >> 8);
            buf[pos + 1] = @intCast(w & 0xFF);
            pos += 2;
        }
        if (options.strength == .tertiary) return buf[0..pos];

        if (options.variable_weighting == .shifted) {
            buf[pos] = 0;
            buf[pos + 1] = 0;
            pos += 2;
            for (self.quaternary.items) |w| {
                buf[pos] = @intCast(w >> 8);
                buf[pos + 1] = @intCast(w & 0xFF);
                pos += 2;
            }
        }
        if (options.strength == .quaternary) return buf[0..pos];

        buf[pos] = 0;
        buf[pos + 1] = 0;
        pos += 2;
        for (self.nfd.items) |cp| {
            buf[pos] = @intCast(cp >> 16);
            buf[pos + 1] = @intCast((cp >> 8) & 0xFF);
            buf[pos + 2] = @intCast(cp & 0xFF);
            pos += 3;
        }
        return buf[0..pos];
    }

    /// Allocates and returns the serialized sort key bytes for the given options.
    /// The caller owns the returned slice; free with the same allocator.
    pub fn serializeAlloc(self: *const Key, allocator: Allocator, options: Options) ![]u8 {
        const len = self.serializedLen(options);
        const buf = try allocator.alloc(u8, len);
        _ = self.serializeInto(options, buf);
        return buf;
    }
};

pub const Collator = struct {
    options: Options,

    pub fn init(options: Options) Collator {
        return .{ .options = options };
    }

    pub fn compareUtf8(
        self: Collator,
        allocator: Allocator,
        a: []const u8,
        b: []const u8,
    ) (encoding.utf8.UTF8ValidationError || error{ BufferTooSmall, OutOfMemory })!Order {
        const a_cps = try encoding.utf8.bytesToUTF8String(allocator, a);
        defer allocator.free(a_cps);
        const b_cps = try encoding.utf8.bytesToUTF8String(allocator, b);
        defer allocator.free(b_cps);

        return try self.compareCodePoints(allocator, a_cps, b_cps);
    }

    pub fn compareCodePoints(self: Collator, allocator: Allocator, a: []const CodePoint, b: []const CodePoint) error{OutOfMemory}!Order {
        var a_key: Key = .{};
        defer a_key.deinit(allocator);
        var b_key: Key = .{};
        defer b_key.deinit(allocator);

        try self.buildKey(allocator, a, &a_key);
        try self.buildKey(allocator, b, &b_key);
        return self.compareKeys(&a_key, &b_key);
    }

    pub fn buildKey(self: Collator, allocator: Allocator, input: []const CodePoint, out: *Key) error{OutOfMemory}!void {
        out.clearRetainingCapacity();

        if (self.options.normalization) {
            var norm = unicode.normalization.Normalizer(.nfd).init();
            var buf: [unicode.normalization.MAX_FEED_OUTPUT]CodePoint = undefined;
            for (input) |cp| {
                const emitted = norm.feed(cp, &buf);
                try out.nfd.appendSlice(allocator, emitted);
            }
            const tail = norm.flush(&buf);
            try out.nfd.appendSlice(allocator, tail);
        } else {
            try out.nfd.appendSlice(allocator, input);
        }

        // Working buffer used for collation element lookup. This starts as NFD
        // but is mutated by the UCA discontiguous-match step (S2.1.1–S2.1.3).
        try out.work.appendSlice(allocator, out.nfd.items);

        var i: usize = 0;
        var after_variable = false;
        while (i < out.work.items.len) {
            var record: u32 = 0;
            var s_len: usize = 1;

            if (i + 2 < out.work.items.len) {
                if (ducet.lookupTriple(out.work.items[i], out.work.items[i + 1], out.work.items[i + 2])) |rec| {
                    record = rec;
                    s_len = 3;
                }
            }
            if (record == 0 and i + 1 < out.work.items.len) {
                if (ducet.lookupDouble(out.work.items[i], out.work.items[i + 1])) |rec| {
                    record = rec;
                    s_len = 2;
                }
            }
            if (record == 0) {
                record = ducet.mappingRecord(out.work.items[i]);
                s_len = 1;
            }

            if (record != 0 and self.options.normalization) {
                try self.extendDiscontiguous(allocator, out, i, &s_len, &record);
            }

            if (record != 0) {
                for (ducet.ceSlice(record)) |ce| {
                    try self.appendCE(allocator, out, ce, &after_variable);
                }
            } else {
                try self.appendImplicit(allocator, out, out.work.items[i], &after_variable);
            }

            i += s_len;
        }
    }

    pub fn compareKeys(self: Collator, a: *const Key, b: *const Key) Order {
        const strength = self.options.strength;

        const p = orderU16Slices(a.primary.items, b.primary.items);
        if (p != .eq) return p;
        if (strength == .primary) return .eq;

        const s = orderU16Slices(a.secondary.items, b.secondary.items);
        if (s != .eq) return s;
        if (strength == .secondary) return .eq;

        const t = orderU16Slices(a.tertiary.items, b.tertiary.items);
        if (t != .eq) return t;
        if (strength == .tertiary) return .eq;

        if (self.options.variable_weighting == .shifted) {
            const q = orderU16Slices(a.quaternary.items, b.quaternary.items);
            if (q != .eq) return q;
        }
        if (strength == .quaternary) return .eq;

        // identical
        return orderCodePointSlices(a.nfd.items, b.nfd.items);
    }

    fn appendCE(self: Collator, allocator: Allocator, out: *Key, ce: ducet.CE, after_variable: *bool) error{OutOfMemory}!void {
        var primary: u16 = ce.primary;
        var secondary: u16 = ce.secondary;
        var tertiary: u16 = ce.tertiary;
        var quaternary: u16 = 0;

        if (primary == 0 and secondary == 0 and tertiary == 0) return;

        switch (self.options.variable_weighting) {
            .non_ignorable => {},
            .shifted => {
                if (primary != 0) {
                    if (ce.variable != 0) {
                        quaternary = primary;
                        primary = 0;
                        secondary = 0;
                        tertiary = 0;
                        after_variable.* = true;
                    } else {
                        quaternary = 0xFFFF;
                        after_variable.* = false;
                    }
                } else {
                    // primary == 0 (ignorable)
                    if (after_variable.*) {
                        primary = 0;
                        secondary = 0;
                        tertiary = 0;
                        quaternary = 0;
                    } else {
                        quaternary = 0xFFFF;
                    }
                }
            },
        }

        if (primary != 0) try out.primary.append(allocator, primary);
        if (secondary != 0) try out.secondary.append(allocator, secondary);
        if (tertiary != 0) try out.tertiary.append(allocator, tertiary);
        if (quaternary != 0) try out.quaternary.append(allocator, quaternary);
    }

    fn appendImplicit(self: Collator, allocator: Allocator, out: *Key, cp: CodePoint, after_variable: *bool) error{OutOfMemory}!void {
        const weights = implicitWeights(cp);

        const ce1: ducet.CE = .{
            .primary = weights.aaaa,
            .secondary = 0x0020,
            .tertiary = 0x0002,
            .variable = 0,
            ._ = 0,
        };
        const ce2: ducet.CE = .{
            .primary = weights.bbbb,
            .secondary = 0x0000,
            .tertiary = 0x0000,
            .variable = 0,
            ._ = 0,
        };

        try self.appendCE(allocator, out, ce1, after_variable);
        try self.appendCE(allocator, out, ce2, after_variable);
    }

    fn extendDiscontiguous(
        self: Collator,
        allocator: Allocator,
        out: *Key,
        start: usize,
        s_len: *usize,
        record: *u32,
    ) error{OutOfMemory}!void {
        _ = self;

        while (s_len.* < 3) {
            var extended = false;
            var k: usize = start + s_len.*;
            while (k < out.work.items.len) : (k += 1) {
                const c = out.work.items[k];
                const ccc_c = ccc(c);
                if (ccc_c == 0) break; // reached next starter

                const base = start + s_len.* - 1;
                if (!isUnblocked(out.work.items, base, k, ccc_c)) continue;

                switch (s_len.*) {
                    1 => if (ducet.lookupDouble(out.work.items[start], c)) |rec| {
                        record.* = rec;
                        const moved = out.work.orderedRemove(k);
                        try out.work.insert(allocator, start + 1, moved);
                        s_len.* = 2;
                        extended = true;
                        break;
                    },
                    2 => if (ducet.lookupTriple(out.work.items[start], out.work.items[start + 1], c)) |rec| {
                        record.* = rec;
                        const moved = out.work.orderedRemove(k);
                        try out.work.insert(allocator, start + 2, moved);
                        s_len.* = 3;
                        extended = true;
                        break;
                    },
                    else => {},
                }
            }
            if (!extended) return;
        }
    }
};

fn orderU16Slices(a: []const u16, b: []const u16) Order {
    const n = @min(a.len, b.len);
    for (a[0..n], b[0..n]) |x, y| {
        if (x < y) return .lt;
        if (x > y) return .gt;
    }
    return std.math.order(a.len, b.len);
}

fn orderCodePointSlices(a: []const CodePoint, b: []const CodePoint) Order {
    const n = @min(a.len, b.len);
    for (a[0..n], b[0..n]) |x, y| {
        if (x < y) return .lt;
        if (x > y) return .gt;
    }
    return std.math.order(a.len, b.len);
}

fn implicitWeights(cp: CodePoint) struct { aaaa: u16, bbbb: u16 } {
    // Siniform ideographic scripts (Tangut, Nushu, Khitan Small Script).
    for (ducet.implicit_ranges) |range| {
        if (cp >= range.start and cp <= range.end) {
            const offset: u16 = @intCast(cp - range.origin);
            return .{ .aaaa = range.base, .bbbb = offset | 0x8000 };
        }
    }

    // Han Unified Ideographs.
    if (unicode.properties.prop_list.isUnifiedIdeograph(cp)) {
        const bbbb: u16 = @intCast((cp & 0x7FFF) | 0x8000);
        const shift: u16 = @intCast(cp >> 15);
        const core = (cp >= 0x4E00 and cp <= 0x9FFF) or (cp >= 0xF900 and cp <= 0xFAFF);
        const base: u16 = if (core) 0xFB40 else 0xFB80;
        return .{ .aaaa = base + shift, .bbbb = bbbb };
    }

    // Unassigned and everything else.
    const bbbb: u16 = @intCast((cp & 0x7FFF) | 0x8000);
    const shift: u16 = @intCast(cp >> 15);
    return .{ .aaaa = 0xFBC0 + shift, .bbbb = bbbb };
}

fn ccc(cp: CodePoint) u8 {
    return @intFromEnum(unicode.properties.canonicalCombiningClass(cp));
}

fn isUnblocked(text: []const CodePoint, base: usize, candidate: usize, ccc_candidate: u8) bool {
    var i: usize = base + 1;
    while (i < candidate) : (i += 1) {
        const b_ccc = ccc(text[i]);
        if (b_ccc == 0) return false;
        if (b_ccc >= ccc_candidate) return false;
    }
    return true;
}

/// Compares two serialized sort keys produced by `Key.serializeInto` or
/// `Key.serializeAlloc` with the same options. Equivalent to calling
/// `Collator.compareKeys` on the source keys — no allocation required.
pub fn compareSerializedKeys(a: []const u8, b: []const u8) Order {
    return std.mem.order(u8, a, b);
}

test "collation: shifted quaternary differentiates trailing variables" {
    const allocator = std.testing.allocator;
    var collator = Collator.init(.{ .variable_weighting = .shifted, .strength = .identical });

    const a = try encoding.utf8.bytesToUTF8String(allocator, "a");
    defer allocator.free(a);
    const b = try encoding.utf8.bytesToUTF8String(allocator, "a!");
    defer allocator.free(b);

    const order = try collator.compareCodePoints(allocator, a, b);
    try std.testing.expectEqual(Order.lt, order);
}
