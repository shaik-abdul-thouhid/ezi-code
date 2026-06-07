# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

### Changed

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
