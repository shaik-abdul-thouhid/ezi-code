//! UAX #15 Unicode normalization (NFC / NFD / NFKC / NFKD).
//!
//! Pipeline:
//!   decompose(form ∈ {.nfd, .nfkd})  → canonical_reorder
//!   compose(form ∈ {.nfc, .nfkc})    → decompose then canonical-compose
//!
//! Hot-path tactics:
//!   - QC fast-path. Scan inputs with the relevant `*_QC` table first; if every
//!     codepoint is `.yes` (or `.unknown`, which UCD treats as `.yes`), return
//!     a borrow/dupe of the input. ASCII never appears in any QC table, so
//!     ASCII strings hit this in O(n) with no allocations beyond the output.
//!   - Pre-expanded decomposition. The generator transitively closes every
//!     decomposition at build time. Runtime decomp is one 2-level page table
//!     lookup per codepoint.
//!   - Algorithmic Hangul. Syllables in AC00..D7A3 (11172 codepoints) bypass
//!     all tables for both decompose and compose.
//!   - Comptime form. `decompose(comptime form, ...)` and
//!     `compose(comptime form, ...)` specialize at the call site — the form
//!     switch evaporates and the canonical vs compatibility decomposition
//!     selector becomes a direct call.
//!
//! Surface:
//!   types.DecompositionForm  { nfd, nfkd }
//!   types.CompositionForm    { nfc, nfkc }
//!   types.NormalizationForm  { nfc, nfd, nfkc, nfkd }
//!
//!   decompose(form, allocator, input) ![]CodePoint
//!   compose(form, allocator, input)   ![]CodePoint
//!   normalize(form, allocator, input) ![]CodePoint           // four-way
//!   nfd / nfc / nfkd / nfkc                                  // thin wrappers
//!   isNormalized(form, input) bool                           // QC sweep
//!   Normalizer(form)                                         // streaming
//!
//! All accept `[]const CodePoint`. UTF-8 in/out is left to transcoding helpers
//! the caller composes (avoids dragging the UTF-8 module into this layer's
//! dependency graph).

const std = @import("std");
const encoding = @import("encoding");
const types = @import("../types.zig");
const unicode_data = @import("../generated/unicode_data.zig");

pub const derived_normalization_props = @import("generated/derived_normalization_props.zig");
pub const decomposition = @import("generated/decomposition.zig");

const CodePoint = encoding.CodePoint;
const Allocator = std.mem.Allocator;

pub const QuickCheck = types.QuickCheck;
pub const QuickCheckForm = types.QuickCheckForm;
pub const ExpandsForm = types.ExpandsForm;
pub const CasefoldKind = types.CasefoldKind;

/// Forms that produce a decomposed sequence. NFD walks canonical mappings;
/// NFKD walks compatibility mappings (which subsume canonical).
pub const DecompositionForm = enum { nfd, nfkd };

/// Forms that produce a (re-)composed sequence. NFC composes after NFD;
/// NFKC composes after NFKD.
pub const CompositionForm = enum { nfc, nfkc };

/// The four UAX #15 normalization forms.
pub const NormalizationForm = enum {
    nfd,
    nfc,
    nfkd,
    nfkc,

    pub fn quickCheckForm(comptime self: NormalizationForm) QuickCheckForm {
        return switch (self) {
            .nfd => .nfd,
            .nfc => .nfc,
            .nfkd => .nfkd,
            .nfkc => .nfkc,
        };
    }

    /// Underlying decomposition flavor — NFC/NFKC need it as their first
    /// pipeline stage; NFD/NFKD ARE that stage.
    pub fn decompositionForm(comptime self: NormalizationForm) DecompositionForm {
        return switch (self) {
            .nfd, .nfc => .nfd,
            .nfkd, .nfkc => .nfkd,
        };
    }

    pub fn isComposing(comptime self: NormalizationForm) bool {
        return self == .nfc or self == .nfkc;
    }
};

// ----------------------------------------------------------------------------
// Per-codepoint helpers
// ----------------------------------------------------------------------------

/// CCC byte for `cp`. Returns 0 (Not_Reordered) for cp > 0x10FFFF — caller
/// shouldn't be feeding us those, but the table guard makes this safe.
pub inline fn ccc(cp: CodePoint) u8 {
    return @intFromEnum(unicode_data.canonicalCombiningClass(cp));
}

pub inline fn isStarter(cp: CodePoint) bool {
    return ccc(cp) == 0;
}

/// Choose canonical vs compatibility decomposition by comptime form. The
/// `hangul_buf` is a scratch slot the lookup writes into when `cp` is a
/// Hangul syllable; the returned slice references it in that case.
pub inline fn decomposeOne(
    comptime form: DecompositionForm,
    cp: CodePoint,
    hangul_buf: *[3]CodePoint,
) ?[]const CodePoint {
    return switch (form) {
        .nfd => decomposition.canonicalDecompose(cp, hangul_buf),
        .nfkd => decomposition.compatibilityDecompose(cp, hangul_buf),
    };
}

pub inline fn canonicalCompose(starter: CodePoint, combiner: CodePoint) ?CodePoint {
    return decomposition.canonicalCompose(starter, combiner);
}

// ----------------------------------------------------------------------------
// QC fast-path / isNormalized
// ----------------------------------------------------------------------------

/// Three-state QC result for `input`. Implements the UAX #15 §11.6
/// "Detecting Normalization Forms" algorithm verbatim. `.yes` means
/// definitively normalized; `.no` means definitively not; `.maybe` means a
/// codepoint with a context-sensitive QC value is present and a full
/// normalize + compare is required for a strict answer.
pub fn quickCheckString(comptime form: NormalizationForm, input: []const CodePoint) QuickCheck {
    const qcf = comptime form.quickCheckForm();
    var last_ccc: u8 = 0;
    var result: QuickCheck = .yes;
    for (input) |cp| {
        const c = ccc(cp);
        if (c != 0 and last_ccc > c) return .no;
        const qc = derived_normalization_props.quickCheck(qcf, cp);
        switch (qc) {
            .yes, .unknown => {},
            .no => return .no,
            .maybe => result = .maybe,
        }
        last_ccc = c;
    }
    return result;
}

/// Returns true iff `input` is identical to `normalize(form, input)`.
///
/// Fast path: a QC sweep that returns `.yes` decides immediately. On `.maybe`
/// the strict definition forces us to run the full pipeline — we do it
/// allocation-free using the streaming Normalizer, comparing emitted
/// codepoints to `input` position-by-position and bailing on the first
/// mismatch.
pub fn isNormalized(comptime form: NormalizationForm, input: []const CodePoint) bool {
    switch (quickCheckString(form, input)) {
        .yes => return true,
        .no => return false,
        .maybe, .unknown => {},
    }
    // .maybe → verify by streaming + compare.
    var norm = Normalizer(form).init();
    var scratch: [MAX_DECOMP_LEN]CodePoint = undefined;
    var idx: usize = 0;
    for (input) |cp| {
        const emitted = norm.feed(cp, &scratch);
        for (emitted) |e| {
            if (idx >= input.len or input[idx] != e) return false;
            idx += 1;
        }
    }
    const tail = norm.flush(&scratch);
    for (tail) |e| {
        if (idx >= input.len or input[idx] != e) return false;
        idx += 1;
    }
    return idx == input.len;
}

// ----------------------------------------------------------------------------
// Canonical reordering
// ----------------------------------------------------------------------------

/// Stable sort marks within each combining run by CCC. UAX #15 D109.
fn canonicalReorder(seq: []CodePoint) void {
    if (seq.len < 2) return;
    var i: usize = 0;
    while (i < seq.len) {
        if (ccc(seq[i]) == 0) {
            i += 1;
            continue;
        }
        var j = i + 1;
        while (j < seq.len and ccc(seq[j]) != 0) j += 1;

        // Insertion sort over [i, j). Stable: equal-CCC marks retain order.
        var k: usize = i + 1;
        while (k < j) : (k += 1) {
            const v = seq[k];
            const vc = ccc(v);
            var m = k;
            while (m > i and ccc(seq[m - 1]) > vc) : (m -= 1) seq[m] = seq[m - 1];
            seq[m] = v;
        }
        i = j;
    }
}

// ----------------------------------------------------------------------------
// decompose
// ----------------------------------------------------------------------------

/// Decompose `input` to its NFD or NFKD form. The result is allocated; caller
/// frees with `allocator.free`. Comptime-specialized on `form` — the
/// canonical vs compatibility selector becomes a direct call.
pub fn decompose(
    comptime form: DecompositionForm,
    allocator: Allocator,
    input: []const CodePoint,
) Allocator.Error![]CodePoint {
    var out: std.ArrayList(CodePoint) = .empty;
    errdefer out.deinit(allocator);
    try out.ensureTotalCapacity(allocator, input.len);

    var hangul_buf: [3]CodePoint = undefined;
    for (input) |cp| {
        if (decomposeOne(form, cp, &hangul_buf)) |decomp| {
            try out.appendSlice(allocator, decomp);
        } else {
            try out.append(allocator, cp);
        }
    }

    canonicalReorder(out.items);
    return out.toOwnedSlice(allocator);
}

// ----------------------------------------------------------------------------
// compose (NFC / NFKC)
// ----------------------------------------------------------------------------

/// Compose `input` to its NFC or NFKC form. The pipeline is: decompose to
/// NFD/NFKD → canonical reorder → canonical-compose adjacent starters.
///
/// Comptime-specialized on `form`. The inner decomposition stage uses the
/// matched canonical/compat selector.
pub fn compose(
    comptime form: CompositionForm,
    allocator: Allocator,
    input: []const CodePoint,
) Allocator.Error![]CodePoint {
    const decomp_form: DecompositionForm = comptime switch (form) {
        .nfc => .nfd,
        .nfkc => .nfkd,
    };

    var decomposed = try decompose(decomp_form, allocator, input);
    const out_len = composeInPlace(decomposed);
    if (allocator.resize(decomposed, out_len)) {
        return decomposed[0..out_len];
    }
    // Resize failed — fall back to copy. Rare; mostly happens with custom
    // allocators that don't implement resize.
    defer allocator.free(decomposed);
    return allocator.dupe(CodePoint, decomposed[0..out_len]);
}

/// Canonical-compose a *decomposed and canonically-reordered* sequence in
/// place. Returns the new length of `buf`. UAX #15 D117 / D118.
///
/// Algorithm:
///   - Walk the sequence with two cursors: `starter_pos` (the most recent
///     starter eligible to absorb a combiner) and `i` (the cursor we're
///     consuming).
///   - On each cp, if canonicalCompose(buf[starter_pos], cp) yields a
///     composite C and cp is not blocked (D115), replace the starter with C
///     and drop cp.
///   - Else emit cp.
fn composeInPlace(buf: []CodePoint) usize {
    if (buf.len < 2) return buf.len;

    var out_len: usize = 0;
    var starter_pos: ?usize = null;
    var last_ccc: u8 = 0;

    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        const cp = buf[i];
        const c = ccc(cp);

        if (starter_pos) |sp| {
            // D115: cp is blocked from the starter at sp if last_ccc != 0
            // and last_ccc >= c. (Equivalent: an intervening mark dominates.)
            const blocked = (last_ccc >= c) and last_ccc != 0;
            if (!blocked) {
                if (canonicalCompose(buf[sp], cp)) |composed| {
                    buf[sp] = composed;
                    continue;
                }
            }
        }

        buf[out_len] = cp;
        if (c == 0) starter_pos = out_len;
        last_ccc = c;
        out_len += 1;
    }

    return out_len;
}

// ----------------------------------------------------------------------------
// Four-way normalize + thin wrappers
// ----------------------------------------------------------------------------

/// One entry point parameterized on form. Routes to `decompose` for NFD/NFKD
/// or `compose` for NFC/NFKC.
pub fn normalize(
    comptime form: NormalizationForm,
    allocator: Allocator,
    input: []const CodePoint,
) Allocator.Error![]CodePoint {
    // QC fast-path: only the definitively-YES case lets us skip the
    // pipeline. `.maybe` requires the full work (codepoints like U+1E0A
    // followed by U+0323 re-decompose and re-compose to a different result).
    if (quickCheckString(form, input) == .yes) {
        return allocator.dupe(CodePoint, input);
    }

    return switch (form) {
        .nfd => decompose(.nfd, allocator, input),
        .nfkd => decompose(.nfkd, allocator, input),
        .nfc => compose(.nfc, allocator, input),
        .nfkc => compose(.nfkc, allocator, input),
    };
}

pub inline fn nfd(allocator: Allocator, input: []const CodePoint) Allocator.Error![]CodePoint {
    return normalize(.nfd, allocator, input);
}
pub inline fn nfkd(allocator: Allocator, input: []const CodePoint) Allocator.Error![]CodePoint {
    return normalize(.nfkd, allocator, input);
}
pub inline fn nfc(allocator: Allocator, input: []const CodePoint) Allocator.Error![]CodePoint {
    return normalize(.nfc, allocator, input);
}
pub inline fn nfkc(allocator: Allocator, input: []const CodePoint) Allocator.Error![]CodePoint {
    return normalize(.nfkc, allocator, input);
}

// ----------------------------------------------------------------------------
// Streaming Normalizer
// ----------------------------------------------------------------------------

/// Largest pending region the streaming Normalizer keeps internally.
///
/// Sized for the UAX #15 Stream-Safe Text Format guarantee: at most 30
/// non-starters between starters, +1 starter, +1 slack = 32. Inputs that
/// violate Stream-Safe (>30 marks in a row) trigger an internal flush and
/// keep producing correct output — the buffer just splits the over-long run
/// into multiple emitted chunks.
pub const MAX_INTERNAL_BUF: usize = 32;

/// Largest number of codepoints a single `feed()` call can emit into the
/// caller's scratch buffer.
///
/// Worst case analysis: on entry the internal buffer can hold up to
/// MAX_INTERNAL_BUF cps (1 starter + 31 marks, hostile input). The input cp
/// may compatibility-decompose into up to **18 cps** (U+FDFA, the lone
/// outlier in the UCD — `ARABIC LIGATURE SALLALLAHOU ALAYHE WASALLAM`,
/// decomposing to 18 standalone Arabic letters). If every component is a
/// starter that fails to compose with the preceding one, we emit
///   - 32 cps (the prior region) for the first decomposed starter, plus
///   - 1 cp per remaining 17 starters
/// = 49 cps. Rounded up to 64 for cache alignment / future-proofing.
///
/// Callers MUST pass a `*[MAX_FEED_OUTPUT]CodePoint` to `feed()` / `flush()`.
pub const MAX_FEED_OUTPUT: usize = 64;

/// Deprecated alias kept for the in-tree benchmark/tests written before the
/// split between `MAX_INTERNAL_BUF` and `MAX_FEED_OUTPUT`. New code should
/// pick the constant that matches its role.
pub const MAX_DECOMP_LEN: usize = MAX_FEED_OUTPUT;

/// Streaming, allocation-free normalizer.
///
/// Comptime-specialized on `form`. Caller drives it with `feed(cp, out)`
/// returning 0..N output codepoints, then `flush(out)` to drain the trailing
/// region at end-of-input. `out` is a caller-owned scratch buffer; the
/// returned slice points into it and is valid only until the next call.
///
/// Active region model:
///   buf[0..len] always holds a "pending region" — at index 0 a starter (or
///   nothing if len==0), then 0..N non-starter marks in canonical order. When
///   a new starter arrives we attempt to compose it with the pending starter
///   (NFC/NFKC only); if that fails we finalize the region (compose marks
///   into starter, emit) and seed a fresh region from the new starter.
///
/// For starter+starter composition (e.g. Bengali U+09C7 + U+09BE → U+09CB),
/// the composition is attempted only when no marks intervene — D115 blocks
/// would catch the case anyway because any intervening mark has CCC >= 0.
pub fn Normalizer(comptime form: NormalizationForm) type {
    return struct {
        const Self = @This();
        const decomp_form: DecompositionForm = form.decompositionForm();
        const composing: bool = form.isComposing();

        buf: [MAX_INTERNAL_BUF]CodePoint = undefined,
        len: usize = 0,

        pub fn init() Self {
            return .{};
        }

        pub fn feed(self: *Self, cp: CodePoint, out: *[MAX_FEED_OUTPUT]CodePoint) []const CodePoint {
            var hangul_buf: [3]CodePoint = undefined;
            const decomp = decomposeOne(decomp_form, cp, &hangul_buf) orelse blk: {
                hangul_buf[0] = cp;
                break :blk hangul_buf[0..1];
            };

            var emitted: usize = 0;
            for (decomp) |d| {
                const dc = ccc(d);
                if (dc == 0 and self.len > 0) {
                    // New starter — close the pending region.
                    self.finalize();
                    // If finalize collapsed everything into a single starter
                    // (no leftover marks), the new starter may itself fuse
                    // with it (D117 starter-starter composition).
                    if (composing and self.len == 1) {
                        if (canonicalCompose(self.buf[0], d)) |composed| {
                            self.buf[0] = composed;
                            continue;
                        }
                    }
                    // Otherwise emit the finalized region and seed anew.
                    @memcpy(out[emitted..][0..self.len], self.buf[0..self.len]);
                    emitted += self.len;
                    self.buf[0] = d;
                    self.len = 1;
                } else if (self.len < self.buf.len) {
                    self.buf[self.len] = d;
                    self.len += 1;
                } else {
                    // Overflow guard: adversarial input with >MAX_DECOMP_LEN
                    // codepoints between starters. Finalize and start fresh.
                    self.finalize();
                    @memcpy(out[emitted..][0..self.len], self.buf[0..self.len]);
                    emitted += self.len;
                    self.buf[0] = d;
                    self.len = 1;
                }
            }
            return out[0..emitted];
        }

        pub fn flush(self: *Self, out: *[MAX_FEED_OUTPUT]CodePoint) []const CodePoint {
            self.finalize();
            const n = self.len;
            @memcpy(out[0..n], self.buf[0..n]);
            self.len = 0;
            return out[0..n];
        }

        /// Canonical-order trailing marks then (for composing forms) absorb
        /// them into the starter. Operates in-place on `buf[0..len]`.
        fn finalize(self: *Self) void {
            if (self.len < 2) return;
            const start_idx: usize = if (ccc(self.buf[0]) == 0) 1 else 0;

            // Stable insertion sort of marks by CCC, in [start_idx, len).
            var k: usize = start_idx + 1;
            while (k < self.len) : (k += 1) {
                const v = self.buf[k];
                const vc = ccc(v);
                var m = k;
                while (m > start_idx and ccc(self.buf[m - 1]) > vc) : (m -= 1) {
                    self.buf[m] = self.buf[m - 1];
                }
                self.buf[m] = v;
            }

            if (composing and start_idx == 1) {
                var write: usize = 1;
                var last_ccc: u8 = 0;
                var i: usize = 1;
                while (i < self.len) : (i += 1) {
                    const m_cp = self.buf[i];
                    const c = ccc(m_cp);
                    const blocked = last_ccc != 0 and last_ccc >= c;
                    if (!blocked) {
                        if (canonicalCompose(self.buf[0], m_cp)) |composed| {
                            self.buf[0] = composed;
                            continue;
                        }
                    }
                    self.buf[write] = m_cp;
                    write += 1;
                    last_ccc = c;
                }
                self.len = write;
            }
        }
    };
}

// ----------------------------------------------------------------------------
// Re-exports of the raw DerivedNormalizationProps API (kept for callers that
// want set-membership / Quick_Check lookups without going through the full
// pipeline).
// ----------------------------------------------------------------------------

pub const quickCheck = derived_normalization_props.quickCheck;
pub const isExpandsOn = derived_normalization_props.isExpandsOn;
pub const casefoldMap = derived_normalization_props.casefoldMap;

pub const nfcQuickCheck = derived_normalization_props.nfcQuickCheck;
pub const nfdQuickCheck = derived_normalization_props.nfdQuickCheck;
pub const nfkcQuickCheck = derived_normalization_props.nfkcQuickCheck;
pub const nfkdQuickCheck = derived_normalization_props.nfkdQuickCheck;

pub const fcNfkcMap = derived_normalization_props.fcNfkcMap;
pub const nfkcCaseFoldMap = derived_normalization_props.nfkcCaseFoldMap;
pub const nfkcSimpleCaseFoldMap = derived_normalization_props.nfkcSimpleCaseFoldMap;

pub const isFullCompositionExclusion = derived_normalization_props.isFullCompositionExclusion;
pub const isChangesWhenNfkcCasefolded = derived_normalization_props.isChangesWhenNfkcCasefolded;
pub const isExpandsOnNfd = derived_normalization_props.isExpandsOnNfd;
pub const isExpandsOnNfc = derived_normalization_props.isExpandsOnNfc;
pub const isExpandsOnNfkd = derived_normalization_props.isExpandsOnNfkd;
pub const isExpandsOnNfkc = derived_normalization_props.isExpandsOnNfkc;

// ============================================================================
// Sanity tests (full conformance lives in src/unicode/tests/ucd_conformance.zig)
// ============================================================================

const testing = std.testing;

test "nfd: ASCII passes through unchanged" {
    const out = try nfd(testing.allocator, &.{ 'h', 'e', 'l', 'l', 'o' });
    defer testing.allocator.free(out);
    try testing.expectEqualSlices(CodePoint, &.{ 'h', 'e', 'l', 'l', 'o' }, out);
}

test "nfd: A-with-grave decomposes to A + combining grave" {
    const out = try nfd(testing.allocator, &.{0x00C0});
    defer testing.allocator.free(out);
    try testing.expectEqualSlices(CodePoint, &.{ 0x0041, 0x0300 }, out);
}

test "nfc: A + combining grave composes to U+00C0" {
    const out = try nfc(testing.allocator, &.{ 0x0041, 0x0300 });
    defer testing.allocator.free(out);
    try testing.expectEqualSlices(CodePoint, &.{0x00C0}, out);
}

test "nfd → nfc: roundtrip on precomposed cp" {
    const original = &[_]CodePoint{0x00C0};
    const d = try nfd(testing.allocator, original);
    defer testing.allocator.free(d);
    const c = try nfc(testing.allocator, d);
    defer testing.allocator.free(c);
    try testing.expectEqualSlices(CodePoint, original, c);
}

test "nfkd: superscript 2 decomposes to plain 2" {
    const out = try nfkd(testing.allocator, &.{0x00B2});
    defer testing.allocator.free(out);
    try testing.expectEqualSlices(CodePoint, &.{'2'}, out);
}

test "nfkc: superscript 2 normalizes to plain 2 (compat composition)" {
    const out = try nfkc(testing.allocator, &.{0x00B2});
    defer testing.allocator.free(out);
    try testing.expectEqualSlices(CodePoint, &.{'2'}, out);
}

test "hangul: AC00 decomposes algorithmically to L + V" {
    const out = try nfd(testing.allocator, &.{0xAC00});
    defer testing.allocator.free(out);
    try testing.expectEqualSlices(CodePoint, &.{ 0x1100, 0x1161 }, out);
}

test "hangul: L + V composes to AC00" {
    const out = try nfc(testing.allocator, &.{ 0x1100, 0x1161 });
    defer testing.allocator.free(out);
    try testing.expectEqualSlices(CodePoint, &.{0xAC00}, out);
}

test "hangul: LVT syllable decomposes to L V T" {
    // 0xAC01 = first L + V + T (T=1) syllable in the block.
    const out = try nfd(testing.allocator, &.{0xAC01});
    defer testing.allocator.free(out);
    try testing.expectEqualSlices(CodePoint, &.{ 0x1100, 0x1161, 0x11A8 }, out);
}

test "canonical reorder: marks out of CCC order get sorted" {
    // 0x0301 (acute, ccc=230) before 0x0316 (grave below, ccc=220) should swap.
    const out = try nfd(testing.allocator, &.{ 'a', 0x0301, 0x0316 });
    defer testing.allocator.free(out);
    try testing.expectEqualSlices(CodePoint, &.{ 'a', 0x0316, 0x0301 }, out);
}

test "isNormalized: ASCII is normalized under every form" {
    const ascii = "hello world";
    var cps: [11]CodePoint = undefined;
    for (ascii, 0..) |b, i| cps[i] = b;
    try testing.expect(isNormalized(.nfd, &cps));
    try testing.expect(isNormalized(.nfc, &cps));
    try testing.expect(isNormalized(.nfkd, &cps));
    try testing.expect(isNormalized(.nfkc, &cps));
}

test "isNormalized: precomposed cp fails NFD quick-check" {
    try testing.expect(!isNormalized(.nfd, &.{0x00C0}));
    try testing.expect(isNormalized(.nfc, &.{0x00C0}));
}

test "Normalizer: streaming NFC matches batch NFC" {
    const input: []const CodePoint = &.{ 'a', 0x0301, 'b', 0x0301, 'c' };
    const batch = try nfc(testing.allocator, input);
    defer testing.allocator.free(batch);

    var norm = Normalizer(.nfc).init();
    var out_buf: [MAX_DECOMP_LEN]CodePoint = undefined;
    var collected: std.ArrayList(CodePoint) = .empty;
    defer collected.deinit(testing.allocator);
    for (input) |cp| {
        const emitted = norm.feed(cp, &out_buf);
        try collected.appendSlice(testing.allocator, emitted);
    }
    const tail = norm.flush(&out_buf);
    try collected.appendSlice(testing.allocator, tail);

    try testing.expectEqualSlices(CodePoint, batch, collected.items);
}

test "idempotency: NFC(NFC(x)) == NFC(x)" {
    const input: []const CodePoint = &.{ 0x00C0, 0x0041, 0x0301, 0xAC00, 0x1100, 0x1161, 0x11A8 };
    const once = try nfc(testing.allocator, input);
    defer testing.allocator.free(once);
    const twice = try nfc(testing.allocator, once);
    defer testing.allocator.free(twice);
    try testing.expectEqualSlices(CodePoint, once, twice);
}

// Constructs the streaming Normalizer's documented worst case: a hostile input
// that fills the internal buffer (1 starter + 31 marks, exceeding UAX #15
// Stream-Safe), followed by U+FDFA whose compatibility decomposition is 18
// standalone Arabic letter starters. The first decomposed starter triggers a
// 32-cp flush; each of the remaining 17 starters emits 1 cp → 49 cps in a
// single feed(). Verifies the output buffer (sized to MAX_FEED_OUTPUT = 64)
// holds them all and the result matches the batch pipeline.
test "Normalizer: worst-case feed (full internal buf + U+FDFA decomp) does not overflow MAX_FEED_OUTPUT and matches batch" {
    var input: std.ArrayList(CodePoint) = .empty;
    defer input.deinit(testing.allocator);

    // Starter + 31 same-CCC combining marks. 0x0301 (COMBINING ACUTE, CCC=230)
    // never composes with itself, so the marks survive into the buffer.
    try input.append(testing.allocator, 'a');
    var i: usize = 0;
    while (i < 31) : (i += 1) try input.append(testing.allocator, 0x0301);
    try input.append(testing.allocator, 0xFDFA); // 18-cp compat decomposition

    inline for (.{ NormalizationForm.nfkc, .nfkd, .nfc, .nfd }) |form| {
        const batch = try normalize(form, testing.allocator, input.items);
        defer testing.allocator.free(batch);

        var collected: std.ArrayList(CodePoint) = .empty;
        defer collected.deinit(testing.allocator);

        var norm = Normalizer(form).init();
        var scratch: [MAX_FEED_OUTPUT]CodePoint = undefined;
        for (input.items) |cp| {
            const emitted = norm.feed(cp, &scratch);
            try collected.appendSlice(testing.allocator, emitted);
        }
        const tail = norm.flush(&scratch);
        try collected.appendSlice(testing.allocator, tail);

        try testing.expectEqualSlices(CodePoint, batch, collected.items);
    }
}

// Mixed-CCC marks (acute=CCC230 / grave-below=CCC220) interleaved at the
// largest count that stays within UAX #15 Stream-Safe (≤30 marks between
// starters → at most 30 / 2 = 15 pairs). Confirms canonical reordering
// across the streaming pipeline matches the batch pipeline within the
// Stream-Safe envelope.
//
// Note: at ≥16 pairs the input is no longer Stream-Safe; the streaming
// algorithm flushes mid-run and CANNOT recover full canonical ordering
// across the flush boundary — that's a documented UAX #15 limitation, not a
// bug. Callers feeding non-Stream-Safe input get well-formed output but it
// may differ from the batch pipeline on the over-long run.
test "Normalizer: Stream-Safe mixed-CCC marks reorder identically to batch (NFC)" {
    var input: std.ArrayList(CodePoint) = .empty;
    defer input.deinit(testing.allocator);

    try input.append(testing.allocator, 'a');
    var i: usize = 0;
    while (i < 15) : (i += 1) {
        try input.append(testing.allocator, 0x0301); // CCC=230, above
        try input.append(testing.allocator, 0x0316); // CCC=220, below
    }
    try input.append(testing.allocator, 'b');

    const batch = try nfc(testing.allocator, input.items);
    defer testing.allocator.free(batch);

    var collected: std.ArrayList(CodePoint) = .empty;
    defer collected.deinit(testing.allocator);

    var norm = Normalizer(.nfc).init();
    var scratch: [MAX_FEED_OUTPUT]CodePoint = undefined;
    for (input.items) |cp| {
        const emitted = norm.feed(cp, &scratch);
        try collected.appendSlice(testing.allocator, emitted);
    }
    const tail = norm.flush(&scratch);
    try collected.appendSlice(testing.allocator, tail);

    try testing.expectEqualSlices(CodePoint, batch, collected.items);
}

// Adversarial non-Stream-Safe input (>30 marks between starters). The
// streaming Normalizer must STILL terminate, produce well-formed (correctly
// ordered within each emitted region) output, and not overflow the
// caller-provided scratch buffer. We don't assert equality with batch — see
// the test above for why.
test "Normalizer: non-Stream-Safe input (50 marks in a row) terminates and emits well-formed output" {
    var input: std.ArrayList(CodePoint) = .empty;
    defer input.deinit(testing.allocator);

    try input.append(testing.allocator, 'a');
    var i: usize = 0;
    while (i < 50) : (i += 1) try input.append(testing.allocator, 0x0301);
    try input.append(testing.allocator, 'b');

    var collected: std.ArrayList(CodePoint) = .empty;
    defer collected.deinit(testing.allocator);

    var norm = Normalizer(.nfc).init();
    var scratch: [MAX_FEED_OUTPUT]CodePoint = undefined;
    for (input.items) |cp| {
        const emitted = norm.feed(cp, &scratch);
        try testing.expect(emitted.len <= MAX_FEED_OUTPUT);
        try collected.appendSlice(testing.allocator, emitted);
    }
    const tail = norm.flush(&scratch);
    try collected.appendSlice(testing.allocator, tail);

    // Output is well-formed: starts with a starter, ends with a starter,
    // and within each combining run CCC is non-decreasing.
    try testing.expect(collected.items.len >= 2);
    var last_ccc: u8 = 0;
    for (collected.items) |cp| {
        const c = ccc(cp);
        if (c != 0) try testing.expect(c >= last_ccc);
        last_ccc = c;
    }
}

// ============================================================================
// Zalgo (combining-mark-saturated) text. Heavy combining-mark stacks are the
// stress case for canonical ordering and the streaming/batch buffers. For any
// input, all four forms must be idempotent, must self-report as normalized, and
// must emit marks in non-decreasing CCC order within each non-starter run.
// Driven by the shared corpus, so a new torture case is just another input.
// ============================================================================

const zalgo_corpus = @import("../tests/zalgo_corpus.zig");

test "normalization zalgo: every form is idempotent, self-normalized, and canonically ordered" {
    for (zalgo_corpus.samples) |s| {
        const cps = try zalgo_corpus.decode(testing.allocator, s.text);
        defer testing.allocator.free(cps);

        inline for (.{ NormalizationForm.nfd, .nfc, .nfkd, .nfkc }) |form| {
            const once = try normalize(form, testing.allocator, cps);
            defer testing.allocator.free(once);

            // Re-normalizing the normal form changes nothing.
            const twice = try normalize(form, testing.allocator, once);
            defer testing.allocator.free(twice);
            try testing.expectEqualSlices(CodePoint, once, twice);

            // ...and the quick-check sweep agrees it is already normalized.
            try testing.expect(isNormalized(form, once));

            // Within each maximal run of non-starters, CCC is non-decreasing.
            var last_ccc: u8 = 0;
            for (once) |cp| {
                const c = ccc(cp);
                if (c != 0) try testing.expect(c >= last_ccc);
                last_ccc = c;
            }
        }
    }
}

test {
    testing.refAllDecls(@This());
}
