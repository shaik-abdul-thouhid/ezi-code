# transcoding

Conversion between the three Unicode encoding forms — UTF-8, UTF-16, UTF-32 —
plus a chunked, pull-based UTF-8 stream decoder. This module sits directly on
top of `encoding`: it never re-implements validation or codec logic, it threads
scalars through the codec modules and only adds the plumbing for moving between
representations.

There are two files:

- `transcoding.zig` — the batch converters (`utf8ToUtf16`, `utf16ToUtf32`, …).
- `stream.zig` — `UTF8Stream`, for decoding UTF-8 that arrives in pieces.

## Batch converters

Every ordered pair of encodings has a family of functions following one naming
convention:

```
utf8ToUtf16        // allocates the output, returns []u16
utf8ToUtf16Len     // just the exact output length, no allocation
utf8ToUtf16Buffer  // writes into a caller-provided buffer, returns bytes written
utf8ToUtf16Lossy        // allocating, replacement-substituting
utf8ToUtf16LossyLen
utf8ToUtf16LossyBuffer
```

…and the same six for `utf8ToUtf32`, `utf16ToUtf8`, `utf16ToUtf32`,
`utf32ToUtf8`, `utf32ToUtf16`.

The split exists so callers can pick their allocation strategy:

- `…Len` then `…Buffer` lets you size once and write into your own memory. The
  `Len` result is exact, so the `Buffer` and allocating forms never re-scan or
  grow.
- The allocating form is the convenience path: it calls `…Len`, allocates, fills,
  and hands back the slice (which the caller frees).

### Strict vs. lossy

The plain functions are **strict**: they decode through the source codec's
validating decoder, so any malformed input surfaces as that codec's error
(`OverlongEncoding`, `SurrogateCodePoint`, `CodePointTooLarge`,
`InvalidLowSurrogate`, …). Nothing is written past the point of failure.

The `Lossy` functions never fail on bad input. Each malformed sequence becomes
one U+FFFD (the replacement character) in the output, and decoding resynchronises
— a run of orphaned UTF-8 continuation bytes collapses into a single U+FFFD
rather than one per byte.

### Overflow is checked before allocation

UTF-16→UTF-8 can triple the unit count; UTF-32→UTF-8 can quadruple it. Before
any of that arithmetic runs, `ensureMaxExpansion` verifies that
`input_len * max_units_per_input` cannot overflow `usize`, returning
`error.Overflow` if it could. This is checked up front, so a hostile length is
rejected before a single source unit is read — see the overflow tests in
`transcoding.zig`.

## UTF8Stream

`stream.zig` is for the case the batch API can't handle: bytes that arrive
incrementally (a socket, a file read loop) where a multi-byte scalar may be
split across two reads.

You `push` borrowed byte slices (the stream does **not** copy or own them) and
pull scalars with `nextCodePoint` / `nextCodePointLossy`. The interesting parts:

- A scalar straddling a slice boundary is buffered in a 4-byte `partial_buffer`
  and completed when the next slice arrives.
- When more input is needed, you get `error.NeedMoreBytes`; once you've called
  `finish()`, the same situation returns `error.EOFReached` (strict) or a final
  U+FFFD for the dangling bytes (lossy).
- On any error the read position is rolled back, so the call is retryable after
  you push more data.
- The optional output buffer receives the raw bytes of the decoded scalar;
  passing `null` decodes without copying them out.
- After the stream drains it resets and can be reused with fresh `push`es.

## Running the tests

```
zig build test -Dinclude-test=transcoding                      # Debug
zig build test -Dinclude-test=transcoding -Doptimize=ReleaseSafe
```
