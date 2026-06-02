# unicode

Character properties and text algorithms backed by the Unicode Character Database
(UCD). This is the largest part of the library; `root.zig` is a deliberately thin
facade that re-exports the submodules and the handful of most-used types. The real
code, and its tests, live in the submodules next to the data they use.

## How the data gets here

Each submodule has a `generated/` directory holding Zig source produced from the
`ucd/*.txt` files at the repository root. The generator is `src/generate.zig`:

```
zig build generate
```

The generated tables are **deduplicated two-level page tables** — a small index
of 256-entry blocks, with identical blocks shared — so a lookup is two array
indexes and the binary stays small even though it covers the whole code space.
The generated files are committed, so a normal build does not need the `ucd/`
inputs; you only re-run `generate` when bumping the Unicode version.

## What's in here

- **properties** — `generalCategory`, `bidiClass`, `canonicalCombiningClass`, the
  Derived Core Properties (`isAlphabetic`, `isIdStart`, …) and the PropList
  predicates (`isWhiteSpace`, `isDash`, `isNoncharacterCodePoint`, …). The boolean
  predicates that most callers want (`isLetter`, `isUpperCase`, `isHexDigit`, …)
  are here.
- **casing** — simple and full case mappings, `SpecialCasing` (context- and
  locale-sensitive, including Turkic dotted/dotless I), and case folding.
- **normalization** — NFC / NFD / NFKC / NFKD via `decompose` / `compose` /
  `normalize` (and the `nfc`/`nfd`/`nfkc`/`nfkd` wrappers), plus `isNormalized`,
  Quick_Check, and a streaming `Normalizer`.
- **segmentation** — grapheme cluster, word, sentence, and line breaking (UAX #14,
  #29), the emoji properties they depend on, and grapheme iterators over both
  bytes and code points.
- **width** — East Asian Width.
- **scripts** — `Script` and `ScriptExtensions`.
- **bidi** — the Unicode Bidirectional Algorithm (UAX #9): both the character
  properties (mirroring glyphs, paired brackets) and the reordering algorithm
  itself. See `bidi/README` below.
- **numeric** — Numeric_Type and Numeric_Value.
- **blocks** — block membership and names.
- **hangul** — Hangul_Syllable_Type plus the algorithmic Hangul composition rules.
- **age** — Derived Age (the Unicode version a code point was assigned in).

`types.zig` holds the enums shared across submodules
(`CanonicalCombiningClass`, `QuickCheck`, the case-folding mode/locale enums, …).

## String-level operations

The property and mapping functions are per-codepoint. These submodules also offer
whole-string helpers in the project's variant families (`…Buffer` into caller
memory, `…Alloc` owned slice, `…Writer` to a `*std.Io.Writer`, `…Len` exact size):

- **casing** — simple (1:1) mapping over a string: `upperSimpleBuffer/Alloc`,
  `lowerSimpleBuffer/Alloc`, `foldSimpleBuffer/Alloc` over `[]const CodePoint`, and
  `upperSimpleUtf8Alloc/Writer`, `lowerSimpleUtf8Alloc/Writer` over UTF-8 bytes.
  Full case folding (honors expansions like ß → "ss") via `foldFullLen/Buffer/Alloc`
  and `foldFullUtf8Alloc/Writer` — the primitive for caseless matching. Simple
  variants are fast but not locale/context-aware; use the per-codepoint
  `toUpperCaseFull` / `toLowerCaseFull` for conformant cased output.
- **width** — `stringWidth` (validating UTF-8), `stringWidthLossy`, and
  `stringWidthCodePoints` sum `terminalColumnWidth` across a string, allocation-free.
- **normalization** — allocation-free `normalizeBuffer` and `normalizedLen` drive
  the streaming `Normalizer` to normalize into caller memory (the buffer
  counterparts of the allocating `normalize`/`nfc`/`nfd`/`nfkc`/`nfkd`). This layer
  stays code-point-only by design; for UTF-8 output, compose `normalize` with the
  `transcoding` helpers.

## bidi

Beyond the property lookups, `bidi/algorithm.zig` implements the full UAX #9
pipeline. The entry points:

- `resolveParagraph(allocator, code_points, base)` → a `Paragraph` owning the
  resolved embedding `levels` for every input scalar (rules P2/P3 for the
  paragraph level, X1–X10 for explicit levels and isolating run sequences, W1–W7
  for weak types, N0–N2 for brackets and neutrals, I1–I2 for the implicit levels).
- `Paragraph.reorderLine` / `reorderVisual` → the L1/L2 display reordering for a
  line, returned as a permutation of indices.
- `paragraphLevel` → just the base level (P2/P3), allocation-free.
- `mirror(cp, level)` → L4 glyph mirroring.

`base` is `.ltr`, `.rtl`, or `.auto` (first-strong detection). The algorithm is
written so the rule numbering in the code matches the spec, and it is exercised by
an extensive test set including adversarial inputs (nesting past `max_depth`,
bracket-stack overflow, unmatched isolates, NSM at sequence start).

## Conformance tests

`tests/ucd_conformance.zig` runs the official UCD test vectors
(`GraphemeBreakTest.txt`, `WordBreakTest.txt`, `SentenceBreakTest.txt`,
`LineBreakTest.txt`, `NormalizationTest.txt`). They are gated behind a build
option so they don't slow the normal test run; enable them with the `conformance`
selector.

## Running the tests

The unicode tests include exhaustive `0..0x10FFFF` sweeps, which are painfully slow
in Debug — run them optimized:

```
zig build test -Dinclude-test=unicode -Doptimize=ReleaseSafe
zig build test -Dinclude-test=conformance -Doptimize=ReleaseSafe   # UCD vectors
```

`-Dinclude-test` selects which suites the `test` step depends on
(`all`, `encoding`, `transcoding`, `unicode`, `utils`, `conformance`).
