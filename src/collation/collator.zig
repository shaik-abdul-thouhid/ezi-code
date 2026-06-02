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

/// A reusable Unicode collation sort key. `Collator.buildKey` populates it from
/// a string: the four per-level weight arrays (`primary`..`quaternary`) plus the
/// `nfd` code points used as the identical-strength tiebreaker. `work` is
/// internal scratch for the discontiguous-match step.
///
/// Initialize with `.{}`, reuse across many strings via `clearRetainingCapacity`
/// (keeps the backing allocations), and release with `deinit`. Compare two keys
/// with `Collator.compareKeys`, or serialize to bytes with `serializeInto` /
/// `serializeAlloc` for allocation-free comparison and storage.
///
/// @stable-since: v0.2.0
pub const Key = struct {
    primary: std.ArrayListUnmanaged(u16) = .empty,
    secondary: std.ArrayListUnmanaged(u16) = .empty,
    tertiary: std.ArrayListUnmanaged(u16) = .empty,
    quaternary: std.ArrayListUnmanaged(u16) = .empty,
    nfd: std.ArrayListUnmanaged(CodePoint) = .empty,
    work: std.ArrayListUnmanaged(CodePoint) = .empty,

    /// Reset the key for reuse, clearing all weight levels and scratch while
    /// retaining their backing allocations. Pass the same `Key` to repeated
    /// `Collator.buildKey` calls when sorting many strings.
    ///
    /// @stable-since: v0.2.0
    pub fn clearRetainingCapacity(self: *Key) void {
        self.primary.clearRetainingCapacity();
        self.secondary.clearRetainingCapacity();
        self.tertiary.clearRetainingCapacity();
        self.quaternary.clearRetainingCapacity();
        self.nfd.clearRetainingCapacity();
        self.work.clearRetainingCapacity();
    }

    /// Free all backing allocations and invalidate the key. `allocator` must be
    /// the same one passed to `Collator.buildKey`.
    ///
    /// @stable-since: v0.2.0
    pub fn deinit(self: *Key, allocator: Allocator) void {
        self.primary.deinit(allocator);
        self.secondary.deinit(allocator);
        self.tertiary.deinit(allocator);
        self.quaternary.deinit(allocator);
        self.nfd.deinit(allocator);
        self.work.deinit(allocator);
        self.* = undefined;
    }

    /// Read-only view of the primary (base-letter) weights, in order. Valid
    /// until the next `buildKey` / `clearRetainingCapacity` / `deinit`.
    ///
    /// @stable-since: v0.2.0
    pub fn primaryWeights(self: *const Key) []const u16 {
        return self.primary.items;
    }

    /// Read-only view of the secondary (accent / diacritic) weights, in order.
    /// Valid until the next mutation of the key.
    ///
    /// @stable-since: v0.2.0
    pub fn secondaryWeights(self: *const Key) []const u16 {
        return self.secondary.items;
    }

    /// Read-only view of the tertiary (case) weights, in order. Valid until the
    /// next mutation of the key.
    ///
    /// @stable-since: v0.2.0
    pub fn tertiaryWeights(self: *const Key) []const u16 {
        return self.tertiary.items;
    }

    /// Read-only view of the quaternary weights (populated only under SHIFTED
    /// variable weighting), in order. Valid until the next mutation of the key.
    ///
    /// @stable-since: v0.2.0
    pub fn quaternaryWeights(self: *const Key) []const u16 {
        return self.quaternary.items;
    }

    /// Read-only view of the NFD code points used as the identical-strength
    /// tiebreaker, in order. Valid until the next mutation of the key.
    ///
    /// @stable-since: v0.2.0
    pub fn nfdCodePoints(self: *const Key) []const CodePoint {
        return self.nfd.items;
    }

    /// Returns the byte length of the serialized sort key for the given options.
    /// The result is exactly how many bytes `serializeInto` will write.
    ///
    /// @stable-since: v0.2.0
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
    ///
    /// @stable-since: v0.2.0
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
    ///
    /// @stable-since: v0.2.0
    pub fn serializeAlloc(self: *const Key, allocator: Allocator, options: Options) ![]u8 {
        const len = self.serializedLen(options);
        const buf = try allocator.alloc(u8, len);
        _ = self.serializeInto(options, buf);
        return buf;
    }

    /// Streams the serialized sort key to `writer` (same byte format as
    /// `serializeInto`) and returns the number of bytes written. Avoids sizing or
    /// allocating an intermediate buffer — useful for writing keys straight to a
    /// file, socket, or hasher. Only the writer's own `error.WriteFailed` is
    /// returned.
    ///
    /// @stable-since: v0.2.0
    pub fn serializeIntoWriter(self: *const Key, options: Options, writer: *std.Io.Writer) std.Io.Writer.Error!usize {
        var n: usize = 0;

        for (self.primary.items) |w| {
            try writer.writeByte(@intCast(w >> 8));
            try writer.writeByte(@intCast(w & 0xFF));
            n += 2;
        }
        if (options.strength == .primary) return n;

        try writer.writeByte(0);
        try writer.writeByte(0);
        n += 2;
        for (self.secondary.items) |w| {
            try writer.writeByte(@intCast(w >> 8));
            try writer.writeByte(@intCast(w & 0xFF));
            n += 2;
        }
        if (options.strength == .secondary) return n;

        try writer.writeByte(0);
        try writer.writeByte(0);
        n += 2;
        for (self.tertiary.items) |w| {
            try writer.writeByte(@intCast(w >> 8));
            try writer.writeByte(@intCast(w & 0xFF));
            n += 2;
        }
        if (options.strength == .tertiary) return n;

        if (options.variable_weighting == .shifted) {
            try writer.writeByte(0);
            try writer.writeByte(0);
            n += 2;
            for (self.quaternary.items) |w| {
                try writer.writeByte(@intCast(w >> 8));
                try writer.writeByte(@intCast(w & 0xFF));
                n += 2;
            }
        }
        if (options.strength == .quaternary) return n;

        try writer.writeByte(0);
        try writer.writeByte(0);
        n += 2;
        for (self.nfd.items) |cp| {
            try writer.writeByte(@intCast(cp >> 16));
            try writer.writeByte(@intCast((cp >> 8) & 0xFF));
            try writer.writeByte(@intCast(cp & 0xFF));
            n += 3;
        }
        return n;
    }
};

/// A Unicode Collation Algorithm collator. Stateless apart from its `options`
/// (cheap to copy by value); construct with `init`. Compare strings directly
/// with `compareUtf8` / `compareCodePoints` (which allocate scratch keys), or
/// build reusable `Key` values with `buildKey` and compare them with
/// `compareKeys` / serialize them for storage.
///
/// @stable-since: v0.2.0
pub const Collator = struct {
    options: Options,

    /// Create a collator with the given `options` (variable weighting, strength,
    /// normalization). No allocation; the collator is a value type.
    ///
    /// @stable-since: v0.2.0
    pub fn init(options: Options) Collator {
        return .{ .options = options };
    }

    /// Compares two UTF-8 strings under this collator's options, returning their
    /// relative `Order`. Decodes both inputs and builds temporary sort keys, so
    /// it allocates and frees internally. Surfaces a `UTF8ValidationError` for
    /// malformed input or `error.OutOfMemory`. For repeated comparisons of the
    /// same strings, build `Key` values once and use `compareKeys`.
    ///
    /// @stable-since: v0.2.0
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

    /// Convenience predicate: `true` iff `a` sorts strictly before `b` under this
    /// collator. Same semantics and error set as `compareUtf8`.
    ///
    /// @stable-since: v0.2.0
    pub fn lessThanUtf8(
        self: Collator,
        allocator: Allocator,
        a: []const u8,
        b: []const u8,
    ) (encoding.utf8.UTF8ValidationError || error{ BufferTooSmall, OutOfMemory })!bool {
        return (try self.compareUtf8(allocator, a, b)) == .lt;
    }

    /// Convenience predicate: `true` iff `a` and `b` are equal under this
    /// collator (equal at every compared level). Same error set as `compareUtf8`.
    ///
    /// @stable-since: v0.2.0
    pub fn equalUtf8(
        self: Collator,
        allocator: Allocator,
        a: []const u8,
        b: []const u8,
    ) (encoding.utf8.UTF8ValidationError || error{ BufferTooSmall, OutOfMemory })!bool {
        return (try self.compareUtf8(allocator, a, b)) == .eq;
    }

    /// Compares two decoded code-point slices under this collator's options.
    /// Builds and frees temporary sort keys internally, so it allocates. For
    /// allocation-free repeated comparisons, reuse keys via
    /// `compareCodePointsReusing` or build them once and call `compareKeys`.
    ///
    /// @stable-since: v0.2.0
    pub fn compareCodePoints(self: Collator, allocator: Allocator, a: []const CodePoint, b: []const CodePoint) error{OutOfMemory}!Order {
        var a_key: Key = .{};
        defer a_key.deinit(allocator);
        var b_key: Key = .{};
        defer b_key.deinit(allocator);

        try self.buildKey(allocator, a, &a_key);
        try self.buildKey(allocator, b, &b_key);
        return self.compareKeys(&a_key, &b_key);
    }

    /// Compares two code-point slices reusing the caller-provided `a_key` and
    /// `b_key` as scratch, returning their `Order`. Identical result to
    /// `compareCodePoints` but lets a hot loop keep the key allocations alive
    /// across calls (`clearRetainingCapacity` is applied by `buildKey`). The keys
    /// are left holding `a`/`b`'s weights on return; the caller still owns and
    /// must `deinit` them.
    ///
    /// @stable-since: v0.2.0
    pub fn compareCodePointsReusing(
        self: Collator,
        allocator: Allocator,
        a: []const CodePoint,
        b: []const CodePoint,
        a_key: *Key,
        b_key: *Key,
    ) error{OutOfMemory}!Order {
        try self.buildKey(allocator, a, a_key);
        try self.buildKey(allocator, b, b_key);
        return self.compareKeys(a_key, b_key);
    }

    /// Convenience predicate: `true` iff `a` sorts strictly before `b`. Allocates
    /// like `compareCodePoints`.
    ///
    /// @stable-since: v0.2.0
    pub fn lessThanCodePoints(self: Collator, allocator: Allocator, a: []const CodePoint, b: []const CodePoint) error{OutOfMemory}!bool {
        return (try self.compareCodePoints(allocator, a, b)) == .lt;
    }

    /// Convenience predicate: `true` iff `a` and `b` are equal under this
    /// collator. Allocates like `compareCodePoints`.
    ///
    /// @stable-since: v0.2.0
    pub fn equalCodePoints(self: Collator, allocator: Allocator, a: []const CodePoint, b: []const CodePoint) error{OutOfMemory}!bool {
        return (try self.compareCodePoints(allocator, a, b)) == .eq;
    }

    /// Builds the sort key for `input` into `out`, applying the full UCA
    /// pipeline: optional NFD normalization, discontiguous-match extension, DUCET
    /// collation-element lookup, and variable-weighting handling. `out` is
    /// cleared first (retaining its allocations), so the same `Key` can be reused
    /// across many strings. The caller owns and must `deinit` `out`.
    ///
    /// @stable-since: v0.2.0
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

    /// Compares two already-built sort keys level by level (primary → secondary →
    /// tertiary → quaternary → identical), stopping at this collator's `strength`.
    /// Allocation-free. The keys must have been built with the same options for
    /// the result to be meaningful.
    ///
    /// @stable-since: v0.2.0
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

    /// One-shot helper: builds the sort key for `input` and serializes it to an
    /// owned byte slice under this collator's options. Equivalent to `buildKey`
    /// followed by `Key.serializeAlloc`, but manages the scratch `Key` for you.
    /// The caller owns and must free the returned slice. Compare results with
    /// `compareSerializedKeys`.
    ///
    /// @stable-since: v0.2.0
    pub fn sortKeyAlloc(self: Collator, allocator: Allocator, input: []const CodePoint) error{OutOfMemory}![]u8 {
        var key: Key = .{};
        defer key.deinit(allocator);
        try self.buildKey(allocator, input, &key);
        return key.serializeAlloc(allocator, self.options);
    }

    /// Sorts `items` (a slice of UTF-8 strings) in place into collation order
    /// under this collator's options. Builds one serialized sort key per item,
    /// sorts by raw byte comparison, then rewrites `items`. Allocates `O(total
    /// key bytes)` transiently and frees it before returning. Surfaces a
    /// `UTF8ValidationError` for malformed input or `error.OutOfMemory`.
    ///
    /// @stable-since: v0.2.0
    pub fn sortUtf8InPlace(
        self: Collator,
        allocator: Allocator,
        items: [][]const u8,
    ) (encoding.utf8.UTF8ValidationError || error{ BufferTooSmall, OutOfMemory })!void {
        const Entry = struct { key: []u8, str: []const u8 };

        const entries = try allocator.alloc(Entry, items.len);
        defer allocator.free(entries);

        var built: usize = 0;
        errdefer for (entries[0..built]) |e| allocator.free(e.key);

        var key: Key = .{};
        defer key.deinit(allocator);

        for (items, 0..) |item, i| {
            const cps = try encoding.utf8.bytesToUTF8String(allocator, item);
            defer allocator.free(cps);
            try self.buildKey(allocator, cps, &key);
            entries[i] = .{ .key = try key.serializeAlloc(allocator, self.options), .str = item };
            built += 1;
        }

        std.mem.sort(Entry, entries, {}, struct {
            fn lessThan(_: void, x: Entry, y: Entry) bool {
                return std.mem.lessThan(u8, x.key, y.key);
            }
        }.lessThan);

        for (entries, 0..) |e, i| items[i] = e.str;
        for (entries) |e| allocator.free(e.key);
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
///
/// @stable-since: v0.2.0
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

test "Key weight accessors expose the per-level arrays" {
    const allocator = std.testing.allocator;
    var collator = Collator.init(.{});
    const cps = try encoding.utf8.bytesToUTF8String(allocator, "Ábc");
    defer allocator.free(cps);

    var key: Key = .{};
    defer key.deinit(allocator);
    try collator.buildKey(allocator, cps, &key);

    try std.testing.expectEqualSlices(u16, key.primary.items, key.primaryWeights());
    try std.testing.expectEqualSlices(u16, key.secondary.items, key.secondaryWeights());
    try std.testing.expectEqualSlices(u16, key.tertiary.items, key.tertiaryWeights());
    try std.testing.expectEqualSlices(u16, key.quaternary.items, key.quaternaryWeights());
    try std.testing.expectEqualSlices(CodePoint, key.nfd.items, key.nfdCodePoints());
    try std.testing.expect(key.primaryWeights().len > 0);
}

test "serializeIntoWriter matches serializeAlloc byte-for-byte" {
    const allocator = std.testing.allocator;
    var collator = Collator.init(.{ .strength = .identical });
    const cps = try encoding.utf8.bytesToUTF8String(allocator, "Résumé!");
    defer allocator.free(cps);

    var key: Key = .{};
    defer key.deinit(allocator);
    try collator.buildKey(allocator, cps, &key);

    const expected = try key.serializeAlloc(allocator, collator.options);
    defer allocator.free(expected);

    const buf = try allocator.alloc(u8, key.serializedLen(collator.options));
    defer allocator.free(buf);
    var w = std.Io.Writer.fixed(buf);
    const n = try key.serializeIntoWriter(collator.options, &w);

    try std.testing.expectEqual(expected.len, n);
    try std.testing.expectEqualSlices(u8, expected, w.buffered());
}

test "sortKeyAlloc agrees with compareCodePoints via compareSerializedKeys" {
    const allocator = std.testing.allocator;
    var collator = Collator.init(.{});

    const a = try encoding.utf8.bytesToUTF8String(allocator, "café");
    defer allocator.free(a);
    const b = try encoding.utf8.bytesToUTF8String(allocator, "cafe");
    defer allocator.free(b);

    const ka = try collator.sortKeyAlloc(allocator, a);
    defer allocator.free(ka);
    const kb = try collator.sortKeyAlloc(allocator, b);
    defer allocator.free(kb);

    try std.testing.expectEqual(
        try collator.compareCodePoints(allocator, a, b),
        compareSerializedKeys(ka, kb),
    );
}

test "compareCodePointsReusing matches compareCodePoints" {
    const allocator = std.testing.allocator;
    var collator = Collator.init(.{});

    const a = try encoding.utf8.bytesToUTF8String(allocator, "apple");
    defer allocator.free(a);
    const b = try encoding.utf8.bytesToUTF8String(allocator, "Apple");
    defer allocator.free(b);

    var ka: Key = .{};
    defer ka.deinit(allocator);
    var kb: Key = .{};
    defer kb.deinit(allocator);

    const reused = try collator.compareCodePointsReusing(allocator, a, b, &ka, &kb);
    const direct = try collator.compareCodePoints(allocator, a, b);
    try std.testing.expectEqual(direct, reused);
}

test "lessThan / equal convenience predicates" {
    const allocator = std.testing.allocator;
    var collator = Collator.init(.{});

    try std.testing.expect(try collator.lessThanUtf8(allocator, "apple", "banana"));
    try std.testing.expect(!try collator.lessThanUtf8(allocator, "banana", "apple"));
    try std.testing.expect(try collator.equalUtf8(allocator, "abc", "abc"));

    const a = try encoding.utf8.bytesToUTF8String(allocator, "a");
    defer allocator.free(a);
    const z = try encoding.utf8.bytesToUTF8String(allocator, "z");
    defer allocator.free(z);
    try std.testing.expect(try collator.lessThanCodePoints(allocator, a, z));
    try std.testing.expect(try collator.equalCodePoints(allocator, a, a));
}

test "sortUtf8InPlace orders a word list by collation" {
    const allocator = std.testing.allocator;
    var collator = Collator.init(.{});

    var items = [_][]const u8{ "banana", "Apple", "cherry", "apple" };
    try collator.sortUtf8InPlace(allocator, &items);

    // Primary order is a < c; "Apple"/"apple" differ only at the tertiary
    // (case) level, so they sit adjacent ahead of "banana" and "cherry".
    try std.testing.expectEqualStrings("banana", items[2]);
    try std.testing.expectEqualStrings("cherry", items[3]);
    try std.testing.expect(std.mem.eql(u8, items[0], "apple") or std.mem.eql(u8, items[0], "Apple"));
    try std.testing.expect(std.mem.eql(u8, items[1], "apple") or std.mem.eql(u8, items[1], "Apple"));
}
