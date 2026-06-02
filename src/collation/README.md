# collation

Default Unicode Collation Algorithm (UCA) using the DUCET (`allkeys.txt`). This
module is its own top-level layer, separate from `unicode/` — it builds on
normalization and character properties but has a distinct public API.

Status: DUCET-only (no locale tailorings). Implements both UCA conformance
configurations shipped by Unicode:

- **Non-ignorable** — every character's weights are taken as-is; punctuation
  sorts by its collation element weights (default).
- **Shifted** — variable characters (punctuation, symbols) have their primary
  weight moved to a fourth, quaternary level so they sort after letters but
  before the end of a string.

Generated data lives in `src/collation/generated/` and is produced by
`zig build generate`.

## Files

| File | Contents |
| ---- | -------- |
| `root.zig` | Public re-exports |
| `collator.zig` | `Collator`, `Key`, `compareSerializedKeys` |
| `types.zig` | `Options`, `Strength`, `VariableWeighting`, `Order` |
| `generated/ducet.zig` | Auto-generated DUCET collation element tables |
| `tests/uca_conformance.zig` | UCA conformance test runner |
| `tests/sort_key.zig` | Sort key serialization tests |

## Core types

**`Options`** — configuration for a collation run:

| Field | Type | Default | Meaning |
| ----- | ---- | ------- | ------- |
| `variable_weighting` | `VariableWeighting` | `.non_ignorable` | How variable CEs are handled |
| `strength` | `Strength` | `.tertiary` | How many weight levels to compare |
| `normalization` | `bool` | `true` | Apply NFD before building weights |

**`Strength`** — controls which weight levels are compared and how many levels
appear in a serialized sort key:

| Value | Compared levels | Typical use |
| ----- | --------------- | ----------- |
| `.primary` | letters only | Language-level equality |
| `.secondary` | + accents / diacritics | Accent-sensitive sort |
| `.tertiary` | + case (default) | Standard dictionary sort |
| `.quaternary` | + punctuation position (SHIFTED only) | SHIFTED conformance |
| `.identical` | + NFD tiebreaker | Byte-level uniqueness |

**`VariableWeighting`** — `.non_ignorable` (default) or `.shifted`.

**`Order`** — `std.math.Order` (`.lt`, `.eq`, `.gt`).

## Collator

```zig
const ezi = @import("ezi_code");

// Default options: NON_IGNORABLE, tertiary strength, normalization enabled.
var collator = ezi.collation.Collator.init(.{});

// Compare two UTF-8 strings directly.
const order = try collator.compareUtf8(allocator, "café", "cafe");
// → .gt  (accented e sorts after plain e at secondary strength)

// Compare pre-decoded code-point slices.
const order2 = try collator.compareCodePoints(allocator, a_cps, b_cps);

// Build a reusable Key, then compare. Useful when sorting large lists.
var key: ezi.collation.Key = .{};
defer key.deinit(allocator);
try collator.buildKey(allocator, code_points, &key);
// Call clearRetainingCapacity() to reuse allocations between strings.
```

### Convenience helpers

- **Boolean predicates** — `lessThanUtf8` / `equalUtf8` and `lessThanCodePoints` /
  `equalCodePoints` wrap the `compare*` calls when you only need a bool.
- **Key reuse** — `compareCodePointsReusing(allocator, a, b, &key_a, &key_b)`
  compares two strings using caller-owned scratch keys, so a hot loop keeps the
  key allocations alive across calls (no per-comparison allocation).
- **Weight inspection** — `Key.primaryWeights()`, `secondaryWeights()`,
  `tertiaryWeights()`, `quaternaryWeights()`, and `nfdCodePoints()` expose the
  per-level arrays as read-only slices (valid until the next mutation of the key).
- **One-shot sort key** — `collator.sortKeyAlloc(allocator, code_points)` builds
  and serializes a key in one call, managing the scratch `Key` for you.
- **Streaming serialization** — `Key.serializeIntoWriter(options, writer)` writes
  the same byte format as `serializeInto` to a `*std.Io.Writer` (file, socket,
  hasher) without sizing an intermediate buffer.
- **Batch sort** — `collator.sortUtf8InPlace(allocator, items)` sorts a
  `[][]const u8` of UTF-8 strings into collation order (the manual sort-key recipe
  below, packaged).

## Sort key serialization

A sort key is a compact byte sequence where a raw `memcmp` of two sort keys
gives the same ordering as `Collator.compareKeys`. This makes them suitable for
storing in a database index, sorting with `std.mem.sort`, or transmitting to
another process without re-running the UCA algorithm.

### API

```zig
// Serialize a Key to an owned byte slice.
const bytes: []u8 = try key.serializeAlloc(allocator, collator.options);
defer allocator.free(bytes);

// Or serialize into a caller-supplied buffer (no allocation).
const len = key.serializedLen(collator.options);
var buf: [4096]u8 = undefined;   // or heap-allocated
const slice = key.serializeInto(collator.options, buf[0..len]);

// Compare two serialized sort keys — no allocation, equivalent to compareKeys.
const order = ezi.collation.compareSerializedKeys(bytes_a, bytes_b);
```

### Binary format

The format follows UTS #10 §4.3. Each strength level contributes a sequence of
big-endian `u16` weight values, with a two-byte null separator (`0x00 0x00`)
between levels. Levels are included only up to `options.strength`.

```text
[ primary weights: u16 BE... ]
0x00 0x00                          ← level separator (only if strength > primary)
[ secondary weights: u16 BE... ]
0x00 0x00                          ← separator (only if strength > secondary)
[ tertiary weights: u16 BE... ]
0x00 0x00                          ← separator (only if SHIFTED ∧ strength ≥ quaternary)
[ quaternary weights: u16 BE... ]  ← only if variable_weighting = .shifted
0x00 0x00                          ← separator (only if strength = identical)
[ NFD codepoints: 3-byte BE... ]   ← only if strength = identical
```

Key invariants that make raw byte comparison safe:

- No collation element weight stored in the key is ever zero — zero-weight CEs
  are silently dropped during `buildKey`. Therefore the `0x00 0x00` separator
  can only appear at level boundaries.
- Weights are written at 2-byte aligned offsets. Scanning in 2-byte steps
  unambiguously finds separators without false positives.
- NFD codepoints are 3-byte big-endian (fits `u21`). Their encoding preserves
  numeric order, so `memcmp` on the NFD section gives the same result as
  comparing the `u21` values directly.

Two sort keys serialized with **the same `Options`** compare via
`std.mem.order(u8, a, b)` exactly as `Collator.compareKeys` would compare the
originating `Key` values.

### Example: sorting a list

```zig
const words = [_][]const u8{ "résumé", "resume", "Résumé", "RESUME" };

var serial = try allocator.alloc([]u8, words.len);
defer { for (serial) |sk| allocator.free(sk); allocator.free(serial); }

var collator = Collator.init(.{});
for (words, 0..) |word, i| {
    const cps = try encoding.utf8.bytesToUTF8String(allocator, word);
    defer allocator.free(cps);
    var key: Key = .{};
    defer key.deinit(allocator);
    try collator.buildKey(allocator, cps, &key);
    serial[i] = try key.serializeAlloc(allocator, collator.options);
}

// Sort indices by serialized key — no Collator involvement at sort time.
var indices = [_]usize{ 0, 1, 2, 3 };
std.mem.sort(usize, &indices, serial, struct {
    fn lt(keys: []const []u8, a: usize, b: usize) bool {
        return std.mem.lessThan(u8, keys[a], keys[b]);
    }
}.lt);
```

## Conformance tests

`tests/uca_conformance.zig` parses the Unicode `CollationTest.zip` vectors and
verifies that each line in the file sorts no higher than the previous one under
both NON_IGNORABLE and SHIFTED configurations. Two scales are provided: SHORT
(fast, used in the normal test run) and full (slow, Release only).

`tests/sort_key.zig` verifies the serialization layer: `serializedLen` matches
actual output, `compareSerializedKeys` agrees with `compareKeys` across all
strength levels and both variable-weighting modes, structural invariants (no
in-sequence zero weights, separators at correct aligned positions), transitivity,
and sort-order preservation on a word list.

Run the conformance tests with:

```sh
zig build test -Dinclude-test=conformance -Doptimize=ReleaseSafe
```

Run only the collation unit and serialization tests:

```sh
zig build test -Dinclude-test=collation
```

## Regenerating the DUCET tables

```sh
zig build generate
```

Downloads `allkeys.txt` and `CollationTest.zip` from
`https://www.unicode.org/Public/17.0.0/uca/` and regenerates
`src/collation/generated/ducet.zig`.

## Design notes

- **DUCET only.** Locale tailorings (e.g. Swedish `v/w` equivalence, German
  phonebook sort) are not implemented. The standard DUCET gives a stable,
  deterministic ordering suitable for most applications and all conformance tests.
- **Normalization is on by default.** Setting `normalization = false` in
  `Options` disables the NFD pass inside `buildKey`. This is faster but only
  correct if the input is already NFD-normalized.
- **Key reuse.** `Key.clearRetainingCapacity()` resets the weight arrays without
  freeing their backing memory. Pass the same `Key` to repeated `buildKey` calls
  when sorting many strings; the allocator will only grow the buffers when a
  string produces more elements than any previous one.
- **Serialized key size.** With default options (tertiary, non-ignorable), the
  serialized key for a typical short string is roughly `3 × codepoint_count × 2`
  bytes plus two 2-byte separators (one between each level). A 10-character
  string produces approximately 60–80 bytes.
- **Implicit weights.** Codepoints not assigned in the DUCET get implicit
  weights computed from their block: Tangut, Nushu, and Khitan use a siniform
  formula; CJK Unified Ideographs use a Han-specific formula; everything else
  uses the unassigned formula (UTS #10 §11.1).
