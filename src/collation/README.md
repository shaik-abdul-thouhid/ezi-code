# collation

Default Unicode Collation Algorithm (UCA) support using the DUCET
(`allkeys.txt`). This module is intentionally **not** under `unicode/` — it is
its own top-level layer.

Status: DUCET-only (no locale tailorings). Implements the two UCA conformance
settings shipped by Unicode:

- **Non-ignorable** (`CollationTest_NON_IGNORABLE*.txt`)
- **Shifted** (`CollationTest_SHIFTED*.txt`)

Generated data lives in `src/collation/generated/` and is produced by
`zig build generate`.

## Quick look

```zig
const ezi = @import("ezi_code");

var collator = ezi.collation.Collator.init(.{});
const order = try collator.compareUtf8(std.testing.allocator, "cafe", "café");
_ = order;
```

## Regenerating

`zig build generate` downloads:

- `https://www.unicode.org/Public/17.0.0/uca/allkeys.txt`
- `https://www.unicode.org/Public/17.0.0/uca/CollationTest.zip`

and regenerates the DUCET tables.

Run conformance tests with:

```sh
zig build test -Dinclude-test=conformance -Doptimize=ReleaseSafe
```

