import Foundation

// The ids records are made with (src/lib/ids.ts).

/// A random UUID v4 in lower case, as every record's id
/// (`crypto.randomUUID()` on the web).
public func newId() -> String {
  UUID().uuidString.lowercased()
}

/// A short random id for line items and other nested rows: 12 hex characters.
public func shortId() -> String {
  String(newId().replacingOccurrences(of: "-", with: "").prefix(12))
}

/// An id that follows from `text`: the same text gives the same id on every
/// device, 32 hex characters from two independent 53-bit hashes. Ported bit
/// for bit from the web, which names stock movements (`sm-` +
/// `stableId("\(key)|\(n)")`), cheque payments and automatic letters with it,
/// so both must give the same id for the same text. The text is read as
/// UTF-16 code units, as JavaScript's `charCodeAt` reads it.
public func stableId(_ text: String) -> String {
  let units = Array(text.utf16)
  func hash(_ seed: UInt32) -> String {
    // Math.imul is a 32-bit multiplication: wrapping UInt32 arithmetic has
    // the same bits, and >>> is a logical shift.
    var h1: UInt32 = 0xdead_beef ^ seed
    var h2: UInt32 = 0x41c6_ce57 ^ seed
    for unit in units {
      let ch = UInt32(unit)
      h1 = (h1 ^ ch) &* 2_654_435_761
      h2 = (h2 ^ ch) &* 1_597_334_677
    }
    h1 = ((h1 ^ (h1 >> 16)) &* 2_246_822_507) ^ ((h2 ^ (h2 >> 13)) &* 3_266_489_909)
    h2 = ((h2 ^ (h2 >> 16)) &* 2_246_822_507) ^ ((h1 ^ (h1 >> 13)) &* 3_266_489_909)
    // 4294967296 * (2097151 & h2) + (h1 >>> 0): at most 53 bits, exact in a double.
    let value = (UInt64(h2 & 2_097_151) << 32) | UInt64(h1)
    return WebJS.padStart(String(value, radix: 16), 14)
  }
  let joined = WebJS.padStart(hash(1) + hash(2), 32)
  return String(joined.suffix(32))
}
