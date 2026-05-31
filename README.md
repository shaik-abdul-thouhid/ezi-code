# ezicode

A Unicode library for Zig. Three layers, stacked:

- **`encoding`** — UTF-8, UTF-16, and UTF-32 codecs.
- **`transcoding`** — conversion between the three encoding forms, plus a
  chunked UTF-8 stream decoder.
- **`unicode`** — character properties and text algorithms backed by the
  Unicode Character Database: normalization, casing, segmentation
  (grapheme / word / sentence / line), width, scripts, bidi, numeric, blocks,
  hangul, age.

It has no dependencies. The UCD tables are generated into Zig source and
committed, so a normal build doesn't touch the network or the `ucd/` inputs.

## Status

Version `0.1.0`. Pre-1.0 in the literal sense: the API is allowed to change.
Tracks a recent Zig dev build (`0.17.0-dev.607+456b2ec07` minimum); it does
not build against stable 0.16. If your toolchain isn't on a current `master`,
this will not compile, and that is the intended trade-off until Zig 0.17 lands.

What works is well-tested. The unicode submodule includes exhaustive
`0..=0x10FFFF` sweeps and runs against the official UCD conformance vectors
(`GraphemeBreakTest.txt`, `WordBreakTest.txt`, `SentenceBreakTest.txt`,
`LineBreakTest.txt`, `NormalizationTest.txt`) under a build flag. The bidi algorithm went in with the rule-numbered
adversarial test set you'd expect for UAX #9.

## Installing

Via git ref (resolves the tag at fetch time):

```
zig fetch --save git+https://github.com/shaik-abdul-thouhid/ezi-code.git#v0.1.0
```

Or via plain HTTP tarball (pins the content hash in `build.zig.zon`):

```
zig fetch --save https://github.com/shaik-abdul-thouhid/ezi-code/archive/refs/tags/v0.1.0.tar.gz
```

Then in `build.zig`:

```zig
const ezi_code = b.dependency("ezi_code", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("ezi_code", ezi_code.module("ezi_code"));
```

Individual modules (`encoding`, `transcoding`, `unicode`, `utils`) are also
exported, so you can depend on just the layer you need.

## Quick look

```zig
const ezi = @import("ezi_code");

// Decode and iterate UTF-8 scalars.
const view = try ezi.utf8.initUTF8View("héllo, мир");
var it = view.iterator();
while (it.next()) |cp| {
    // cp: u21
    _ = cp;
}

// Convert between encoding forms.
const utf16 = try ezi.transcoding.utf8ToUtf16(allocator, "Καλημέρα");
defer allocator.free(utf16);

// Normalize.
const nfc = try ezi.unicode.nfc(allocator, "café");
defer allocator.free(nfc);

// Bidi: resolve embedding levels and get the visual order of a line.
var paragraph = try ezi.unicode.bidi.resolveParagraph(allocator, code_points, .auto);
defer paragraph.deinit();
const visual_order = try paragraph.reorderVisual(allocator);
defer allocator.free(visual_order);
```

The per-module READMEs in `src/encoding/`, `src/transcoding/`, and
`src/unicode/` document the full surface. Read them before reaching for the
top-level types — the interesting design is at that level, not in the facade.

## What's in the unicode module

| Submodule       | What it does                                                              |
| --------------- | ------------------------------------------------------------------------- |
| `properties`    | General Category, Bidi Class, CCC, Derived Core Properties, PropList      |
| `casing`        | Simple / full / special casing (Turkic etc.), case folding                |
| `normalization` | NFC, NFD, NFKC, NFKD, Quick_Check, streaming `Normalizer`                 |
| `segmentation`  | Grapheme / word / sentence / line breaking (UAX #14, UAX #29) + iterators |
| `width`         | East Asian Width                                                          |
| `scripts`       | Script and Script_Extensions                                              |
| `bidi`          | UAX #9: mirroring, paired brackets, **and the full reordering algorithm** |
| `numeric`       | Numeric_Type and Numeric_Value                                            |
| `blocks`        | Block membership and names                                                |
| `hangul`        | Hangul_Syllable_Type plus algorithmic Hangul composition                  |
| `age`           | Derived_Age (Unicode version a code point was assigned in)                |

All lookups are deduplicated two-level page tables — two array indexes per
query — so the table cost stays small even though every submodule covers the
whole code space.

### About the bidi algorithm

`unicode.bidi` started as property lookups (`bidiMirroringGlyph`,
`bidiPairedBracketType`) and now ships with the full UAX #9 pipeline in
`bidi/algorithm.zig`:

- `resolveParagraph(allocator, code_points, base)` — runs P2/P3 to pick the
  paragraph level, then X1–X10 (explicit levels, isolating run sequences), then
  W1–W7 (weak types), then N0–N2 (paired brackets and neutrals), then I1–I2
  (back to levels). Returns a `Paragraph` that owns the per-character levels.
- `Paragraph.reorderLine` / `reorderVisual` — L1/L2 display reordering for a
  line, returned as a permutation of indices. Line breaking is left to you;
  L1/L2 are defined per visual line, not per paragraph.
- `paragraphLevel` — just the base level (allocation-free) if that's all you
  need.
- `mirror(cp, level)` — L4 glyph mirroring.

The code mirrors the rule numbering in the spec so it can be read next to the
text. `base` is `.ltr`, `.rtl`, or `.auto` (Unicode's first-strong heuristic).
Explicit nesting is capped at the spec's `max_depth = 125`; deeper input is
counted as overflow and ignored, as required.

## Unicode version and regenerating the tables

The committed tables track the UCD files in `ucd/` (`UnicodeData.txt`,
`DerivedCoreProperties.txt`, `BidiMirroring.txt`, `BidiBrackets.txt`, the
break-property and -test files, etc.). To bump the Unicode version:

1. Replace the relevant files under `ucd/`.
2. Run `zig build generate`. This rebuilds the deduplicated tables under each
   submodule's `generated/` directory.
3. Re-run the conformance suite (below).

For day-to-day work, you don't need this — the generated files are checked in.

## Building, testing, benchmarking

```sh
# Build the placeholder executable.
zig build

# Run all tests (Debug). Note: the unicode sweeps are slow in Debug.
zig build test

# Run a specific suite. Selectors: all, encoding, transcoding, unicode, utils, conformance.
zig build test -Dinclude-test=unicode -Doptimize=ReleaseSafe

# Run the UCD conformance vectors.
zig build test -Dinclude-test=conformance -Doptimize=ReleaseSafe

# Regenerate Unicode tables from ucd/.
zig build generate

# Run benchmarks. Defaults to ReleaseFast for the library and the driver.
zig build bench
zig build bench -- --list                 # list registered modules
zig build bench -- encoding/utf8          # run one
zig build bench -- --size=524288 unicode  # custom corpus size
```

The bench driver reports mean of 7 runs ± stddev with throughput and tracked
allocator memory, over three corpora (ASCII, multilingual, pathological).
Module list is in `bench/main.zig`.

## Layout

```
src/
  encoding/        UTF-8, UTF-16, UTF-32 codecs + per-module README
  transcoding/     Cross-encoding converters and UTF8Stream + per-module README
  unicode/         All UCD-backed properties and algorithms + per-module README
    age/  bidi/  blocks/  casing/  hangul/  normalization/
    numeric/  properties/  scripts/  segmentation/  width/
    tests/         UCD conformance test runners
  utils/           Internal helpers (search, slices). Not part of the public API.
bench/             Benchmark driver, framework, corpora, per-module suites
ucd/               Raw UCD inputs (only needed for `zig build generate`)
licences/          Upstream licenses for bundled third-party code and data
```

## Design notes worth knowing before reading the code

- Decode paths come in three flavours everywhere they exist: **strict** (full
  validation, fine-grained errors), **unchecked** (assume valid, skip checks),
  and **lossy** (replace malformed runs with U+FFFD, never error). Error sets
  are per-codec; "overlong", "surrogate", and "too large" are different
  failures because callers want to treat them differently.
- The codec layer doesn't allocate. Where you need owned output, there is an
  explicit allocating variant or a buffer variant that writes into your memory.
- Backward UTF-8 traversal is a first-class operation (`codePointLenReverse`,
  `decodeCodePointReverseUnchecked`, etc.) — necessary for cursor-style editing
  without scanning from the start.
- The transcoders check the maximum possible expansion against `usize` overflow
  *before* any allocation. A hostile length is rejected before a single source
  unit is read.
- The bidi algorithm follows the spec's rule numbering literally. If you're
  reading the code, keep UAX #9 open next to it.
- `utils/` is internal. It's exported by `build.zig` so submodules can share
  it, not because it's part of the API.

## License

MIT for the source. See `LICENSE`.

Two third-party components ship with their own terms in `licences/`:

- Björn Höhrmann's "Flexible and Economical UTF-8 Decoder" (MIT) — the DFA
  used by the UTF-8 codec.
- Unicode Character Database data files (Unicode License V3) — the inputs in
  `ucd/` and, transitively, the generated tables derived from them.