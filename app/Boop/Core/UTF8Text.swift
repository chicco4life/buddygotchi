extension String {
    /// Trim to at most `maxBytes` UTF-8 bytes, never splitting a character.
    ///
    /// The firmware stores these in fixed `char[N]` buffers and copies with
    /// `strncpy`, which counts BYTES. Bounding by `prefix(n)` counts Swift
    /// Characters, so a hint of 30 emoji is 30 "characters" and 120 bytes: the
    /// device kept the first 63 and left a dangling lead byte, which renders as
    /// garbage and makes the device's own `state` JSON invalid UTF-8 (enough to
    /// crash buddyctl and the HIL suite mid-prompt). Cutting on a Character
    /// boundary here keeps already-flashed devices correct without a reflash.
    func prefix(utf8Bytes maxBytes: Int) -> String {
        guard utf8.count > maxBytes else { return self }
        var out = ""
        var used = 0
        for ch in self {
            let n = String(ch).utf8.count
            if used + n > maxBytes { break }
            out.append(ch)
            used += n
        }
        return out
    }
}
