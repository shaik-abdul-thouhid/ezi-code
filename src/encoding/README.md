# encoding

The bottom layer of the library: turning bytes (or 16-/32-bit units) into Unicode
scalar values and back. Everything above this — `transcoding`, all of `unicode` —
speaks the type defined here, `CodePoint`.

Files:

- `root.zig` — the shared vocabulary and `validateCodePoint`.
- `utf8.zig` — the UTF-8 codec (the largest and most exercised of the three).
- `utf16.zig` — the UTF-16 codec, surrogate-pair aware.
- `utf32.zig` — the UTF-32 codec.

## The shared types (`root.zig`)

- `CodePoint = u21` — the canonical scalar type. A value of this type is a
  *contract*: APIs that take a `CodePoint` assume it is a valid scalar unless they
  say otherwise.
- `MAX_ASCII = 0x7F` — exposed so decoders can take an ASCII fast path.
- `INVALID_CODE_POINT = 0xFFFD` — the replacement character that lossy decoders
  emit for malformed input.
- `validateCodePoint` — range + surrogate check (it does *not* reject reserved or
  noncharacter code points; those are still valid scalars).
- Boolean classifiers (v0.2.0): `isValidCodePoint` (the bool form of
  `validateCodePoint`), `isSurrogateCodePoint`, `isAscii`, and `isSupplementary`
  (≥ U+10000).

## Three variants of everything

Each codec offers the same three flavours of decode, and you choose based on what
you know about the input:

- **strict** (`validateAndDecodeCodePointBytes`, `validateAndDecodeU16CodePoint`,
  `validateAndDecodeU32CodePoint`) — fully validates and returns a precise error.
  The error sets distinguish the failure: `OverlongEncoding`,
  `SurrogateCodePoint`, `CodePointTooLarge`, `InvalidContinuationByte`,
  `IndexOutOfBounds`, and so on. Use this on untrusted input.
- **unchecked** (the `…Unchecked` functions) — assumes the input is already valid
  and skips the structural checks. Faster, and meant for data you have already
  validated (e.g. iterating a `UTF8View`). Passing malformed input is a
  programming error.
- **lossy** (`…Lossy`, `lossyIterator`) — never errors. Malformed sequences become
  U+FFFD and decoding resynchronises. A run of orphaned UTF-8 continuation bytes
  is consumed as a *single* replacement, not one per byte.

### "Optimistic length"

The `…Len` functions (`codePointLen`, `utf8EncodeLen`, `utf16EncodeLen`, …) return
the length implied by the *lead* unit before the continuation units have been
validated — hence "optimistic". The lossy `…LenLossy` variants return `0` when the
lead unit is itself invalid, so the caller can detect that without an error union.

## UTF-8 (`utf8.zig`)

The most complete of the three:

- Scalar counting uses Björn Höhrmann's DFA decoder (`hoehrmann_utf8_decode_table`)
  — a branch-light state machine that validates while it counts.
- Forward decode in strict / unchecked / lossy forms, plus **reverse** decode
  (`codePointLenReverse`, `validateAndDecodeCodePointBytesReverse`,
  `decodeCodePointReverseUnchecked`) so you can walk a buffer backwards without
  re-scanning from the start.
- Whole-buffer validation (v0.2.0): `validate` returns a fast `bool` via the
  Höhrmann DFA; `countScalars` validates and returns the scalar count with the
  fine-grained `UTF8ValidationError` (the strict counterpart of `countScalarsLossy`).
- Encoding: `encodeCodePoint` (buffer-checked only — the scalar is assumed valid)
  and `utf8EncodeLen`. v0.2.0 adds `encodeCodePointUnchecked` (no buffer check) and
  `encodeCodePointWriter` (encode straight to a `*std.Io.Writer`).
- Classification helpers: `isContinuationByte`, `isLeaderByte`, `codePointLen`.
- `UTF8View` (now a `pub` named type, as are `UTF8ViewIterator` and
  `UTF8LossyIterator`) — a validated (or assumed-valid) view over bytes with
  `countScalar`, `isBoundary`, `sliceScalars` (slice by scalar index, not byte
  index), and an iterator (`next`, `peek`, `previous`, `peekPrevious`, `reset`).
- `lossyIterator` for the same traversal over un-validated bytes.
- Bulk conversions to `[]CodePoint`: `bytesToCodePointsBuffer` (strict, v0.2.0) and
  `bytesToCodePointsLossy(Buffer)`, `bytesToUTF8String` (allocating, strict), and
  `bytesToUTF8StringComptime` for building scalar arrays at compile time.
- SIMD chunked scanners (v0.3.0) — see below.

## SIMD chunked scanners (v0.3.0)

These are **additive** data-parallel fast paths in `utf8.zig`; every pre-existing
API keeps its exact signature and behaviour. They share one observation: ASCII
bytes (`<= 0x7F`) are exactly the one-byte UTF-8 scalars, so a run of them can be
located, counted, or widened to code points with no per-byte classification — and
a `simd_block`-wide vector (`std.simd.suggestVectorLength(u8)`, e.g. 16/32/64)
locates such runs many bytes at a time. All are portable `@Vector` compares and
reductions with a scalar tail: no target intrinsics, no dynamic shuffles, nothing
reads past the slice.

- `asciiRunLength(bytes) usize` — length of the leading ASCII run (the shared
  primitive; also useful directly for callers wanting their own ASCII fast path).
- `countScalarsSimd(bytes) usize` — **unchecked** scalar count via the
  non-continuation-byte rule (`(b & 0xC0) != 0x80`). Equals `countScalars` on
  valid input; performs no validation, so use the validating counterparts when
  validity is unknown.
- `simdLossyIterator` / `UTF8SimdLossyIterator` — a buffered lossy decode iterator
  with output identical to `lossyIterator` (malformed → U+FFFD, orphan
  continuation runs collapse to one replacement) that widens ASCII runs in bulk.
  Prefer it over `lossyIterator` for large, mostly-ASCII input.
- `validate` is unchanged in signature and result but, since v0.3.0, skips ASCII
  runs in bulk while the Höhrmann DFA is on a scalar boundary (ASCII bytes always
  keep the DFA in accept, so skipping them cannot change the verdict).

### Which paths can be SIMD — validation vs. unchecked

A common misconception is that "only the unchecked variant can be SIMD". In fact
*validation* is what the well-known SIMD UTF-8 work (Lemire & Keiser; simdjson /
simdutf) accelerates. Both can be SIMD; the real constraint is **error
granularity**, not validation-vs-unchecked:

- **Counting and boolean `validate`** are fully data-parallel — a vector yields a
  single "this block is clean" answer, which is all they need. Largest, simplest
  wins (`countScalarsSimd`, the `validate` fast path).
- **Fine-grained strict decoders** must name *which* error (`OverlongEncoding` vs
  `SurrogateCodePoint` vs `CodePointTooLarge`) at a *specific* offset — a vector
  cannot produce that attribution, so SIMD only fast-forwards the ASCII/clean
  runs and the existing scalar path still attributes the error. SIMD *bypasses*
  the scalar path on the common case; it does not *replace* it.
- **Decoding to code points** is intrinsically variable-length (output count ≠
  input count); only the ASCII sub-case widens 1:1 (`u8` → `u21`), which is what
  the chunk iterator exploits. Reverse decode and single-scalar random-access
  decode stay scalar.

## UTF-16 (`utf16.zig`) and UTF-32 (`utf32.zig`)

Both mirror the UTF-8 structure — strict / unchecked / lossy decode, `encodeCodePoint`,
an encode-length helper, a view type, and a `lossyIterator` — so once you know one
codec you know all three. Each also gained the v0.2.0 additions: `validate`,
strict `countScalars`, a strict `bufToCodePointsBuffer`, `encodeCodePointUnchecked`,
and `encodeCodePointWriter`. Because a writer is a byte sink, the UTF-16/UTF-32
`encodeCodePointWriter` takes an `endian` (`utils.Endian`) and emits each code unit
as bytes in that order; the UTF-8 one needs no endianness. The `UTF16View` /
`UTF32View` types and their iterators are `pub` named types.

- UTF-16 (`validateAndDecodeU16CodePoint`, `utf16EncodeLen`, `initUTF16View`, …) is
  surrogate-pair aware: its errors call out lone high surrogates and missing/invalid
  low surrogates.
- UTF-32 (`validateAndDecodeU32CodePoint`, …) is one unit per scalar, so its
  validation is essentially the range-and-surrogate check applied per unit.

The error sets are named per codec (`UTF8ValidationError`, `UTF16ValidationError`,
`UTF32ValidationError`, and the matching `…EncodeError`s) so error handling stays
specific to the encoding you're working with.

## Design notes

- The core decode/encode paths don't allocate. Where you need owned output there
  is an explicit allocating variant (takes an `std.mem.Allocator`) or a buffer
  variant that writes into your memory; the comptime helpers cover compile-time
  needs.
- Errors are deliberately fine-grained — "overlong" and "surrogate" and
  "too large" are different failures with different causes, and callers often want
  to treat them differently.
- Backward traversal is a first-class operation, not an afterthought, which is what
  makes cursor-style editing over UTF-8 practical.

## Running the tests

```
zig build test -Dinclude-test=encoding                      # Debug
zig build test -Dinclude-test=encoding -Dinclude-test=unicode -Doptimize=ReleaseSafe
```