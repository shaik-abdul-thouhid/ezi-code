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