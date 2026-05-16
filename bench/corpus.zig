//! Deterministic UTF-8 corpora tiled into backing buffers.

/// Deterministic 4 KiB ASCII block.
pub const ascii_stress_4k: [4096]u8 = blk: {
    @setEvalBranchQuota(20_000);
    var b: [4096]u8 = undefined;
    for (0..4096) |i| {
        b[i] = @truncate(0x20 + @mod(i, 95));
    }
    break :blk b;
};

pub const normal_chunks = [_][]const u8{
    "Line0\t\r\n !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~\x7f",
    "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs.",
    "τὸ γὰρ αὐτὸ νοεῖν ἐστίν τε καὶ εἶναι· Heraclitus fragment.",
    "В чащах юга жил бы цитрус? Да, но фальшивый экземпляр!",
    "한글키보드 ㄱㅏㅁㅅㅏㅎㅏ 타자연습에 좋은 문장입니다.",
    "口內漢字簡繁體區分與通用規範在文件與網頁上都很重要。",
    "क़ु॒त्रि और देवनागरी में विभिन्न जोड़। தமிழ் மொழி அழகு.",
    "العُرُoobِيّة مع أرقام ١٢٣ والنصوص المختلطة.",
    "דָּבָר מִתּוֹךְ כָּרָךְ — עברית עם ניקוד.",
    "ภาษาไทยสำหรับข้อความทั่วไปและสระต่างๆ",
    "မြန်မာဘာသာဖြင့် နေ့စဉ်သတင်းစာဖတ်ခြင်း။",
    "Minimal emoji for realism: 🙂 Hallo 👋 thanks 🙏",
};

pub const pathological_chunks = [_][]const u8{
    "\u{007F}\u{0080}\u{07FF}\u{0800}\u{FFFF}\u{10000}\u{1F600}\u{10FFFF}",
    "👩🏿\u{FE0F}\u{200D}❤\u{FE0F}\u{200D}💋\u{200D}👨🏽\u{200D}🦰",
    "👨\u{200D}👩\u{200D}👧\u{200D}👦\u{200D}\u{200D}🏳️\u{FE0F}\u{200D}🌈",
    "🇺🇸🏴\u{FE0F}+\u{1F3FB}\u{1F3FC}\u{1F3FF}",
    "𝐇𝐞𝐥𝑙𝑜 𝒞𝒶𝕝𝔩𝕚𝕘𝕣𝕒𝕡𝕙𝕪 𝄞\u{1D11E}\u{1D165}",
    "ꍐꍑꍒ𐂀𐃏\u{E0020}\u{E0066}\u{E007F}",
    "abc\u{202B}בקש\u{202C}def\u{2066}numeric\u{2069}",
    "🯰🯱🯲🯳🯴🯵🯶🯷🯸🯹🯸🯷🯶🯵🯴🯳🯲🯱🯰",
    "က္ခမြနှင့် ខ្មែរ\u{103A}\u{1039}សញ្ញាខ្មែរ",
    "क़ु॒त्रि\u{0951}\u{0952}ధీర్ఘంௐ",
};

/// Tile `chunks` into `buffer` without splitting chunks; tail padded with ASCII '@'.
pub fn fillFromChunks(buffer: []u8, chunks: []const []const u8) []const u8 {
    var off: usize = 0;
    var i: usize = 0;
    while (off < buffer.len) {
        const chunk = chunks[i % chunks.len];
        i += 1;
        if (chunk.len > buffer.len - off) {
            while (off < buffer.len) {
                buffer[off] = '@';
                off += 1;
            }
            break;
        }
        @memcpy(buffer[off..][0..chunk.len], chunk);
        off += chunk.len;
    }
    return buffer;
}

pub fn fillAsciiOnly(buffer: []u8) []const u8 {
    var off: usize = 0;
    while (off < buffer.len) {
        const rem = buffer.len - off;
        const n = @min(ascii_stress_4k.len, rem);
        @memcpy(buffer[off..][0..n], ascii_stress_4k[0..n]);
        off += n;
    }
    return buffer;
}
