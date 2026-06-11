# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-06-11

### Changed

- The **`CodePoint` contract** is now documented as such, on the type itself
  (`encoding.CodePoint`) and in the README: values of this type are presumed
  valid Unicode scalars; producers uphold the contract, consumers rely on it
  and skip decoding/validation (which is what makes the `[]const CodePoint`
  API variants the cheap path for already-decoded text). The README quick-look
  examples were also brought back in sync with the real signatures
  (`initUTF8View` out-param, `view.iter()`, `nfc` over code points).
- **Breaking:** "unchecked" now means one thing everywhere — *the caller
  guarantees the documented preconditions; violations are asserted /
  safety-checked (trap in Debug/ReleaseSafe, undefined in
  ReleaseFast/ReleaseSmall); unchecked functions never return errors or
  panic.* Accordingly:
  - `encoding.utf8.codePointLenReverseUnchecked` returns plain `u3`
    (was `UTF8ValidationError!u3`).
  - `encoding.utf16.utf16SequenceLenReverseUnchecked` returns plain `u2`
    (was `UTF16ValidationError!u2`) and asserts `end_index < buf.len`
    instead of returning `ZeroLengthUnits`.
  - `encoding.utf8.decodeCodePointReverseUnchecked` no longer documents (or
    contains) a panic path; its preconditions are asserted.

### Removed

- **Breaking:** the `Undefined` member is gone from all six UTF-16/UTF-32
  error sets (`UTF16ValidationError`, `UTF16ValidationLossyError`,
  `UTF16EncodeError`, `UTF32ValidationError`, `UTF32ValidationLossyError`,
  `UTF32EncodeError`). It was never returned by any code path; exhaustive
  `switch`es over these error sets can drop their dead `error.Undefined` arm.

### Fixed

- `unicode.segmentation` byte-level iterators (grapheme / word / sentence /
  line) and step helpers no longer contain `catch @panic` shims around lossy
  decoding. They decode through `encoding.utf8.decodeCodePointLossy`, so the
  "lossy never errors" promise now holds structurally: malformed UTF-8 yields
  U+FFFD segments and can never trap. `lineStepBytes` documents its
  `byte_pos < bytes.len` contract (asserted, safety-checked).

### Added

- **Early-exit collation compare** (`@stable-since: v0.4.0`):
  `Collator.compareCodePointsIncremental` / `compareUtf8Incremental` generate
  collation elements lazily and stop at the first differing weight of the
  shallowest differing level — no sort keys are materialized. Identical
  results to `compareCodePoints` / `compareUtf8` for every input and option
  set (verified across the strength × variable-weighting matrix). Strings that
  differ early at the primary level — the common case — pay for only a few
  collation elements; the weighting logic is shared with `buildKey` via an
  internal `resolveCE` so the two paths cannot diverge.
- **BOM utilities** — new `encoding.bom` module (`@stable-since: v0.4.0`):
  `Bom` enum (utf8 / utf16_le / utf16_be / utf32_le / utf32_be) with
  `bytes` / `len` / `endian` / `match`, plus `detect` (longest-match: the
  ambiguous `FF FE 00 00` reports UTF-32 LE) and zero-copy `strip`. The
  codecs themselves still never consume or produce BOMs; this is the
  explicit seam, re-exported at the package root as `bom`.
- `unicode.normalization.nfkcCaseFold` — sequence-level **NFKC_Casefold**
  (`@stable-since: v0.4.0`), per the UCD definition
  `NFKC_CF(X) = NFC(toNFKC_Casefold(X))`, built on the already-shipped
  per-scalar `nfkcCaseFoldMap` table. The identifier-caseless form used by
  UAX #31 and security profiles: fullwidth compatibility variants fold
  (`ＡＢＣ` → `abc`), Default_Ignorables map away, and the result is
  idempotent (verified by a BMP-wide sweep).
- String-level **titlecase** in `unicode.casing`
  (`@stable-since: v0.4.0`): `titlecaseAlloc` (`[]const CodePoint`) and
  `titlecaseUtf8Alloc` (UTF-8), implementing the Unicode default algorithm
  (R3) — UAX #29 word segmentation, full titlecase mapping on each word's
  first cased scalar, full lowercase on the rest, with Final_Sigma context
  for U+03A3 (`"ΜΕΓΑΣ"` → `"Μεγας"`). Default root-locale mappings; no
  Turkic/Lithuanian tailoring.
- **Case-insensitive search** in `unicode.casing`
  (`@stable-since: v0.4.0`): `indexOfFold` / `containsFold` over UTF-8 bytes
  and `indexOfFoldCodePoints` / `containsFoldCodePoints` over scalar slices.
  Both sides fold lazily during the scan — no allocation — honoring expanding
  folds in `.full` mode (`"STRASSE"` matches `"Straße"`), with a whole-scalar
  boundary rule (needle `"s"` never matches inside `"ß"`'s expansion). The
  CodePoint variants skip decoding/validation entirely per the `CodePoint`
  contract.
- SIMD chunked scanners for **UTF-16**, mirroring the v0.3.0 UTF-8 set
  (`@stable-since: v0.4.0`, portable `@Vector` compares with scalar tails, no
  target intrinsics): `utf16.nonSurrogateRunLength` (length of the leading
  run of standalone scalars — the UTF-16 analogue of `asciiRunLength`) and
  `utf16.countScalarsSimd` (unchecked scalar count via the high-surrogate
  rule). `utf16.validate` now skips surrogate-free runs in SIMD strides and
  falls back to scalar pair checks only at actual surrogates.
- Bulk **encode-direction** APIs taking `[]const CodePoint`
  (`@stable-since: v0.4.0`): `encodeCodePoints{Len,Buffer,Alloc}` on all three
  codecs, the inverse of `bytesToUTF8String` / `bufToUTF16String` /
  `bufToUTF32String`. Callers holding already-decoded scalars encode without
  any decoding or validation, per the `CodePoint` contract.
- `encoding.utf8.StreamingValidator` — incremental, resumable validation over
  arbitrarily-chunked input (`@stable-since: v0.4.0`). The Höhrmann DFA state
  carries across chunk boundaries (no buffering, no copies); `update` reports
  the absolute offset of the first malformed sequence, `finish` distinguishes
  a truncated trailing scalar from valid end-of-input, and ASCII runs are
  skipped in SIMD strides.
- Error **position** reporting (`@stable-since: v0.4.0`): `invalidIndex` on
  all three codecs returns the unit/byte offset where the first malformed
  sequence starts (`null` when valid), so diagnostics no longer require a
  re-scan. Decoding strictly at the reported offset recovers the fine-grained
  error. The UTF-8 variant skips ASCII runs in SIMD strides.
- Unchecked **forward** decode entry points, completing the strict / unchecked
  / lossy matrix in the forward direction (`@stable-since: v0.4.0`): callers
  holding already-validated text can decode without re-validating and without
  wrapping the input in a View.
  - `encoding.utf8.decodeCodePointUnchecked`
  - `encoding.utf16.decodeU16CodePointUnchecked`
  - `encoding.utf32.decodeU32CodePointUnchecked`
- `encoding.utf8.decodeCodePointLossy` — infallible lossy decode primitive
  (`@stable-since: v0.4.0`). Malformed sequences yield U+FFFD and are never
  reported as errors; the only precondition (`offset < bytes.len`) is asserted
  (safety-checked), not error-returned, and the returned `len` is always >= 1
  so forward scans are guaranteed to make progress. `UTF8LossyIterator` and
  `UTF8SimdLossyIterator` now decode through it, removing their internal
  `catch unreachable`/`catch break` shims.

## [0.3.0] - 2026-06-09

### Added

- SIMD chunked scanners in `encoding.utf8` (additive — every pre-existing API
  keeps its exact signature and behaviour). All are portable `@Vector` compares
  and reductions with a scalar tail (no target intrinsics, no dynamic shuffles),
  striding `std.simd.suggestVectorLength(u8)` bytes at a time. `@stable-since:
  v0.3.0`:
  - `asciiRunLength` — length of the leading ASCII run (`<= 0x7F`), the shared
    primitive behind the others and usable directly for an ASCII fast path.
  - `countScalarsSimd` — **unchecked** scalar count via the non-continuation-byte
    rule (`(b & 0xC0) != 0x80`); equals `countScalars` on valid input.
  - `simdLossyIterator` / `UTF8SimdLossyIterator` — a buffered lossy decode
    iterator that widens ASCII runs in bulk; output is identical to
    `lossyIterator` (malformed → U+FFFD, orphaned continuation runs collapse to a
    single replacement).
- Enumerable code-point **range tables** for Unicode properties, so consumers
  can resolve property classes into sorted ranges at comptime (the per-code-point
  page tables cannot be enumerated without walking all 1.1M code points). New
  `zig build generate-ranges` step (no network; reuses the committed page tables)
  emits:
  - `properties.category_runs` (`CategoryRun{ start, end, category }`) — a full
    partition of 0..=0x10FFFF by `General_Category`, including unassigned runs.
  - `properties.derived_runs` (`DerivedRun{ start, end, mask }`) —
    DerivedCoreProperties runs keyed by the same bitmask as `derivedPropertyMask`.
  - `properties.white_space_ranges` and `properties.join_control_ranges`
    (`CodePointRange{ start, end }`) — PropList bases for `\s` and `\w`.
  - `scripts.script_runs` (`ScriptRun{ start, end, script }`) — Script runs for
    assigned code points.
- `properties.isWord` — Perl `\w` / word-boundary predicate
  (`Alphabetic ∪ Mark ∪ Decimal_Number ∪ Connector_Punctuation ∪ Join_Control`).
  Resolved from the enumerable range tables (with an ASCII fast path), not the
  per-code-point page tries, so a consumer that needs only `isWord` never links
  the page tables. `@stable-since: v0.3.0`.
- **Range-table-backed per-code-point queries** — equivalent to the page-table
  predicates but linking only the enumerable range tables (no two-level page
  tries), so a size-sensitive consumer can drop the tries entirely. Each is
  proven equal to its page-table twin for every code point. `@stable-since:
  v0.3.0`:
  - `properties.categoryFromRuns` — `General_Category` via binary search over
    `category_runs` (twin of `generalCategory`).
  - `properties.derivedMaskFromRuns` — DerivedCoreProperties bitmask via binary
    search over `derived_runs` (twin of `derivedPropertyMask`).
  - `properties.isIdentifierStartByRanges` / `isIdentifierContinueByRanges` —
    twins of `isIdentifierStart` / `isIdentifierContinue`.
- A dedicated **`unicode.emoji`** module for the UTS #51 emoji character
  properties (`emoji-data.txt`), promoting the six emoji predicates out of
  `unicode.segmentation` into a first-class property module alongside `scripts`,
  `blocks`, etc. The generated page/range tables (`emoji.generated`, regenerated
  by `zig build generate`) now live under `unicode/emoji/generated/`. All
  `@stable-since: v0.3.0`:
  - Per-code-point predicates `emoji.isEmoji`, `isEmojiPresentation`,
    `isEmojiModifier`, `isEmojiModifierBase`, `isEmojiComponent`, and
    `isExtendedPictographic` (also surfaced as `unicode.isEmoji`, … ).
  - `emoji.EmojiProperty` (enum of the six properties), `emoji.EmojiProperties`
    (a `packed struct` of all six bools with `.any()`), `emoji.emojiProperties`
    (resolve all six at once), `emoji.hasEmojiProperty` (runtime-selected
    dispatch), and `emoji.hasAnyEmojiProperty`.
  - Enumerable code-point **range tables** so consumers can resolve `\p{Emoji}`,
    `\p{Extended_Pictographic}`, etc. into sorted ranges at comptime without
    walking all 1.1M code points (same rationale as `scripts.script_runs`).
    Emitted by an extended `zig build generate-ranges` into
    `unicode/emoji/generated/emoji_ranges.zig` and re-exported as
    `emoji.emoji_ranges`, `emoji.emoji_presentation_ranges`,
    `emoji.emoji_modifier_ranges`, `emoji.emoji_modifier_base_ranges`,
    `emoji.emoji_component_ranges`, and `emoji.extended_pictographic_ranges`
    (`EmojiRange{ start, end }`), with `emoji.rangesFor(property)` for
    runtime selection. Each table is proven (test) to enumerate exactly its
    predicate over the whole code space.

### Changed

- The emoji predicates moved from `unicode.segmentation` to the new
  `unicode.emoji` module (see Added). `segmentation.isEmoji`,
  `isEmojiPresentation`, `isEmojiModifier`, `isEmojiModifierBase`,
  `isEmojiComponent`, and `isExtendedPictographic` remain as deprecated
  re-export aliases (so `segmentation` keeps compiling and UAX #29 grapheme
  clustering still resolves `Extended_Pictographic`); prefer `unicode.emoji.*`.
  `unicode.emoji_data` now points at `emoji.generated` rather than
  `segmentation.emoji_data`. All still v0.3.0-unreleased.
- The Unicode range-table re-exports (`properties.category_runs`,
  `properties.derived_runs`, `properties.white_space_ranges`,
  `properties.join_control_ranges`, `scripts.script_runs`,
  `casing.case_folding.common_simple_table`) are now `[]const T` slices over a
  single backing array instead of by-value array re-exports. Iteration,
  indexing, slicing and `.len` are unchanged; this removes a duplicate copy of
  each table that the by-value alias materialized in consumer binaries (and the
  extra comptime-materialized copy). Still all v0.3.0-unreleased.

- Performance: `encoding.utf8.validate` now skips ASCII runs in bulk via SIMD
  (`asciiRunLength`) while the Höhrmann DFA is on a scalar boundary, instead of
  feeding every byte through the DFA. ASCII bytes always keep the DFA in accept,
  so the verdict is identical; only the dominant ASCII case is faster. Signature
  and result are unchanged.
- Performance: the UAX #14 line-break steppers (`lineStep`, `lineStepBytes`,
  and the `LineBreakIterator` / `CodePointLineBoundaryIterator` they drive) now
  compute the forward look-ahead only when a look-ahead-dependent rule
  (LB15b, LB15c, LB19a, LB25, LB28a) can actually fire, instead of on every
  code point. Roughly 25–37% faster line iteration on the benchmark corpora.
- Performance: the streaming sentence iterators (`SentenceIterator`,
  `CodePointSentenceIterator`) memoise the SB8 look-ahead across an
  `ATerm Close* Sp*` window, eliminating repeated forward rescans (~10–15%
  faster `CodePointSentenceIterator`) and bounding a previously quadratic
  worst case for long ATerm runs.
- Performance: deduplicated the `General_Category` lookup shared by LB15b and
  LB19 within the line-break rule scan.
- The Regional_Indicator run trackers `BoundaryState.ri_run` and
  `WordStepState.ri_count` are now a single parity bit (`u1`) rather than a
  full `usize`; only the run parity was ever consulted, so the per-step state
  structs are smaller. No behavioural change.

## [0.2.0] - 2026-06-02

### Added

- Collation module with DUCET (Default Unicode Collation Element Table) support
- Serialization and comparison for collation keys
- Bidi conformance test files

### Changed

- Refactored code structure for improved readability and maintainability
- Updated generated Unicode tables and documentation
- Added `sources.tar` containing documentation sources
- Cleaned up `build.zig.zon`

## [0.1.0] - 2026-05-31

### Added

- Transcoding module with UTF-8 and UTF-16 encoding/decoding
  - UTF-8 scalar counting, strict and lossy validation
  - UTF-16 surrogate pair handling, reverse decoding
- Bidi (Unicode Bidirectional Algorithm) implementation with full conformance coverage
- Unicode normalization (NFC, NFD, NFKC, NFKD) with conformance tests
- Unicode segmentation: line break, word, and sentence iterators (streaming mode)
- Unicode properties lookup (derived core properties, combining class, numeric values, blocks)
- Unicode script identification with conformance tests
- Case folding with strict, lossy, and codepoint variants; case-folded equality checks
- Hangul syllable, Bidi brackets/mirroring generation
- Benchmark infrastructure
- UCD 17.0.0 data frozen and code-generated tables

[Unreleased]: https://github.com/shaik-abdul-thouhid/ezi-code/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/shaik-abdul-thouhid/ezi-code/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/shaik-abdul-thouhid/ezi-code/releases/tag/v0.1.0
