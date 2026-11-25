import Foundation

/// JSON as the sync engine reads and writes it: a parser and a writer for
/// `JSONValue` that are fast enough for a company of ~50k records (the
/// mirror's files and pulled pages), and the web's own comparisons.
///
/// The writer prints numbers as JavaScript's `String(n)` does and leaves
/// non-ASCII text as it is, so what it writes has the length the web's
/// `JSON.stringify` measures (the 512 KB push batches).
public enum SyncJSON {
  public enum ParseError: Error, Equatable, Sendable {
    case invalid(offset: Int)
  }

  // MARK: Parsing

  public static func parse(_ data: Data) throws -> JSONValue {
    try data.withUnsafeBytes { raw in
      let bytes = raw.bindMemory(to: UInt8.self)
      var parser = Parser(bytes: bytes)
      parser.skipSpace()
      let value = try parser.value(depth: 0)
      parser.skipSpace()
      guard parser.at == bytes.count else { throw ParseError.invalid(offset: parser.at) }
      return value
    }
  }

  public static func parse(_ text: String) throws -> JSONValue {
    try parse(Data(text.utf8))
  }

  private struct Parser {
    let bytes: UnsafeBufferPointer<UInt8>
    var at = 0

    init(bytes: UnsafeBufferPointer<UInt8>) { self.bytes = bytes }

    mutating func skipSpace() {
      while at < bytes.count {
        switch bytes[at] {
        case 0x20, 0x0A, 0x0D, 0x09: at += 1
        default: return
        }
      }
    }

    func fail() -> ParseError { .invalid(offset: at) }

    mutating func value(depth: Int) throws -> JSONValue {
      guard depth < 512, at < bytes.count else { throw fail() }
      switch bytes[at] {
      case UInt8(ascii: "{"): return try object(depth: depth)
      case UInt8(ascii: "["): return try array(depth: depth)
      case UInt8(ascii: "\""): return .string(try string())
      case UInt8(ascii: "t"): try literal("true"); return .bool(true)
      case UInt8(ascii: "f"): try literal("false"); return .bool(false)
      case UInt8(ascii: "n"): try literal("null"); return .null
      default: return .number(try number())
      }
    }

    mutating func literal(_ word: StaticString) throws {
      let count = word.utf8CodeUnitCount
      guard at + count <= bytes.count else { throw fail() }
      let start = word.utf8Start
      for i in 0..<count where bytes[at + i] != start[i] { throw fail() }
      at += count
    }

    mutating func object(depth: Int) throws -> JSONValue {
      at += 1
      var fields: [String: JSONValue] = [:]
      skipSpace()
      if at < bytes.count, bytes[at] == UInt8(ascii: "}") {
        at += 1
        return .object(fields)
      }
      while true {
        skipSpace()
        guard at < bytes.count, bytes[at] == UInt8(ascii: "\"") else { throw fail() }
        let key = try string()
        skipSpace()
        guard at < bytes.count, bytes[at] == UInt8(ascii: ":") else { throw fail() }
        at += 1
        skipSpace()
        // As JSON.parse: a repeated key keeps the last value.
        fields[key] = try value(depth: depth + 1)
        skipSpace()
        guard at < bytes.count else { throw fail() }
        if bytes[at] == UInt8(ascii: ",") {
          at += 1
          continue
        }
        guard bytes[at] == UInt8(ascii: "}") else { throw fail() }
        at += 1
        return .object(fields)
      }
    }

    mutating func array(depth: Int) throws -> JSONValue {
      at += 1
      var items: [JSONValue] = []
      skipSpace()
      if at < bytes.count, bytes[at] == UInt8(ascii: "]") {
        at += 1
        return .array(items)
      }
      while true {
        skipSpace()
        items.append(try value(depth: depth + 1))
        skipSpace()
        guard at < bytes.count else { throw fail() }
        if bytes[at] == UInt8(ascii: ",") {
          at += 1
          continue
        }
        guard bytes[at] == UInt8(ascii: "]") else { throw fail() }
        at += 1
        return .array(items)
      }
    }

    mutating func string() throws -> String {
      at += 1
      let start = at
      // The usual case: no escapes, read the bytes as they are.
      while at < bytes.count {
        let byte = bytes[at]
        if byte == UInt8(ascii: "\"") {
          let slice = UnsafeBufferPointer(rebasing: bytes[start..<at])
          at += 1
          guard let text = String(validating: slice, as: UTF8.self) else { throw fail() }
          return text
        }
        if byte == UInt8(ascii: "\\") { break }
        if byte < 0x20 { throw fail() }
        at += 1
      }
      var out: [UInt8] = Array(bytes[start..<at])
      while at < bytes.count {
        let byte = bytes[at]
        if byte == UInt8(ascii: "\"") {
          at += 1
          guard let text = String(validating: out, as: UTF8.self) else { throw fail() }
          return text
        }
        if byte < 0x20 { throw fail() }
        if byte != UInt8(ascii: "\\") {
          out.append(byte)
          at += 1
          continue
        }
        at += 1
        guard at < bytes.count else { throw fail() }
        let escape = bytes[at]
        at += 1
        switch escape {
        case UInt8(ascii: "\""): out.append(0x22)
        case UInt8(ascii: "\\"): out.append(0x5C)
        case UInt8(ascii: "/"): out.append(0x2F)
        case UInt8(ascii: "b"): out.append(0x08)
        case UInt8(ascii: "f"): out.append(0x0C)
        case UInt8(ascii: "n"): out.append(0x0A)
        case UInt8(ascii: "r"): out.append(0x0D)
        case UInt8(ascii: "t"): out.append(0x09)
        case UInt8(ascii: "u"):
          var scalar = try hex4()
          if (0xD800..<0xDC00).contains(scalar) {
            // A surrogate pair: the second half must follow.
            guard at + 1 < bytes.count, bytes[at] == UInt8(ascii: "\\"), bytes[at + 1] == UInt8(ascii: "u")
            else { throw fail() }
            at += 2
            let low = try hex4()
            guard (0xDC00..<0xE000).contains(low) else { throw fail() }
            scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
          } else if (0xDC00..<0xE000).contains(scalar) {
            throw fail()
          }
          guard let unicode = Unicode.Scalar(scalar) else { throw fail() }
          out.append(contentsOf: Array(String(Character(unicode)).utf8))
        default:
          throw fail()
        }
      }
      throw fail()
    }

    mutating func hex4() throws -> UInt32 {
      guard at + 4 <= bytes.count else { throw fail() }
      var value: UInt32 = 0
      for _ in 0..<4 {
        let byte = bytes[at]
        let digit: UInt32
        switch byte {
        case 0x30...0x39: digit = UInt32(byte - 0x30)
        case 0x41...0x46: digit = UInt32(byte - 0x41 + 10)
        case 0x61...0x66: digit = UInt32(byte - 0x61 + 10)
        default: throw fail()
        }
        value = value * 16 + digit
        at += 1
      }
      return value
    }

    mutating func number() throws -> Double {
      let start = at
      if at < bytes.count, bytes[at] == UInt8(ascii: "-") { at += 1 }
      guard at < bytes.count else { throw fail() }
      if bytes[at] == UInt8(ascii: "0") {
        at += 1
      } else if (0x31...0x39).contains(bytes[at]) {
        while at < bytes.count, (0x30...0x39).contains(bytes[at]) { at += 1 }
      } else {
        throw fail()
      }
      if at < bytes.count, bytes[at] == UInt8(ascii: ".") {
        at += 1
        let digits = at
        while at < bytes.count, (0x30...0x39).contains(bytes[at]) { at += 1 }
        guard at > digits else { throw fail() }
      }
      if at < bytes.count, bytes[at] == UInt8(ascii: "e") || bytes[at] == UInt8(ascii: "E") {
        at += 1
        if at < bytes.count, bytes[at] == UInt8(ascii: "+") || bytes[at] == UInt8(ascii: "-") { at += 1 }
        let digits = at
        while at < bytes.count, (0x30...0x39).contains(bytes[at]) { at += 1 }
        guard at > digits else { throw fail() }
      }
      let text = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<at]), as: UTF8.self)
      guard let value = Double(text) else { throw fail() }
      return value
    }
  }

  // MARK: Writing

  /// JSON text of a value, as UTF-8.
  public static func data(_ value: JSONValue) -> Data {
    var out: [UInt8] = []
    out.reserveCapacity(256)
    write(value, into: &out)
    return Data(out)
  }

  public static func string(_ value: JSONValue) -> String {
    var out: [UInt8] = []
    write(value, into: &out)
    return String(decoding: out, as: UTF8.self)
  }

  /// The length `JSON.stringify(value).length` has in the web app (UTF-16 units).
  public static func jsLength(_ value: JSONValue) -> Int {
    string(value).utf16.count
  }

  public static func write(_ value: JSONValue, into out: inout [UInt8]) {
    switch value {
    case .null: out.append(contentsOf: [0x6E, 0x75, 0x6C, 0x6C])
    case .bool(let flag): out.append(contentsOf: Array((flag ? "true" : "false").utf8))
    case .number(let number): out.append(contentsOf: Array(jsNumber(number).utf8))
    case .string(let text): writeString(text, into: &out)
    case .array(let items):
      out.append(UInt8(ascii: "["))
      for (i, item) in items.enumerated() {
        if i > 0 { out.append(UInt8(ascii: ",")) }
        write(item, into: &out)
      }
      out.append(UInt8(ascii: "]"))
    case .object(let fields):
      out.append(UInt8(ascii: "{"))
      // Sorted, so the same value always gives the same bytes.
      for (i, key) in fields.keys.sorted().enumerated() {
        if i > 0 { out.append(UInt8(ascii: ",")) }
        writeString(key, into: &out)
        out.append(UInt8(ascii: ":"))
        if let field = fields[key] { write(field, into: &out) }
      }
      out.append(UInt8(ascii: "}"))
    }
  }

  private static func writeString(_ text: String, into out: inout [UInt8]) {
    out.append(0x22)
    for byte in text.utf8 {
      switch byte {
      case 0x22: out.append(contentsOf: [0x5C, 0x22])
      case 0x5C: out.append(contentsOf: [0x5C, 0x5C])
      case 0x08: out.append(contentsOf: [0x5C, UInt8(ascii: "b")])
      case 0x0C: out.append(contentsOf: [0x5C, UInt8(ascii: "f")])
      case 0x0A: out.append(contentsOf: [0x5C, UInt8(ascii: "n")])
      case 0x0D: out.append(contentsOf: [0x5C, UInt8(ascii: "r")])
      case 0x09: out.append(contentsOf: [0x5C, UInt8(ascii: "t")])
      case 0x00..<0x20:
        let hex = Array("0123456789abcdef".utf8)
        out.append(contentsOf: [0x5C, UInt8(ascii: "u"), 0x30, 0x30, hex[Int(byte >> 4)], hex[Int(byte & 0x0F)]])
      default: out.append(byte)
      }
    }
    out.append(0x22)
  }

  /// A number as JavaScript prints it (`String(n)`): `5`, `0.1`, `1e+21`,
  /// `1.5e-7`. Not finite: `null`, as JSON.stringify writes it.
  public static func jsNumber(_ number: Double) -> String {
    guard number.isFinite else { return "null" }
    if number == 0 { return "0" }
    let sign = number < 0 ? "-" : ""
    // Swift's description has the shortest digits that read back the same, as JavaScript's.
    let text = abs(number).description
    let parts = text.split(separator: "e", maxSplits: 1)
    let mantissa = parts[0]
    let exponent = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
    let pieces = mantissa.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    let whole = String(pieces[0])
    let fraction = pieces.count > 1 ? String(pieces[1]) : ""
    var digits = Array(whole + fraction)
    // The decimal point sits after `point` digits.
    var point = whole.count + exponent
    while digits.first == "0", digits.count > 1 {
      digits.removeFirst()
      point -= 1
    }
    while digits.last == "0", digits.count > 1 { digits.removeLast() }
    let k = digits.count
    let n = point
    let body: String
    if k <= n && n <= 21 {
      body = String(digits) + String(repeating: "0", count: n - k)
    } else if 0 < n && n <= 21 {
      body = String(digits[0..<n]) + "." + String(digits[n...])
    } else if -6 < n && n <= 0 {
      body = "0." + String(repeating: "0", count: -n) + String(digits)
    } else {
      let e = n - 1
      let head = k == 1 ? String(digits) : String(digits[0]) + "." + String(digits[1...])
      body = head + "e" + (e >= 0 ? "+" : "-") + String(abs(e))
    }
    return sign + body
  }

  // MARK: The web's comparisons

  /// The web's `sameData` (src/cloud/roles.ts) exactly: deep equality where a
  /// missing value (nil) and null are the same at the top, and where an
  /// object's keys must match (a key holding null is still a key).
  public static func sameData(_ a: JSONValue?, _ b: JSONValue?) -> Bool {
    switch (a, b) {
    case (.some(.object(let left)), .some(.object(let right))):
      guard left.count == right.count else { return false }
      for (key, value) in left {
        guard let other = right[key], sameData(value, other) else { return false }
      }
      return true
    case (.some(.array(let left)), .some(.array(let right))):
      return left.count == right.count && zip(left, right).allSatisfy { sameData($0, $1) }
    case (.some(.object), .some(.array)), (.some(.array), .some(.object)):
      return false
    case (.some(.number(let x)), .some(.number(let y))):
      // JavaScript's ===: NaN is never itself (JSON has no NaN anyway).
      return x == y
    default:
      return (a ?? .null) == (b ?? .null)
    }
  }

  /// JavaScript's `===` on two fields: a missing field (nil) is not null, and
  /// two objects or arrays are never the same object.
  static func strictEqual(_ a: JSONValue?, _ b: JSONValue?) -> Bool {
    switch (a, b) {
    case (.none, .none): return true
    case (.some(.object), _), (.some(.array), _), (_, .some(.object)), (_, .some(.array)): return false
    case (.some(let x), .some(let y)): return x == y
    default: return false
    }
  }

  /// JavaScript's truthiness of a field (`Boolean(value)`).
  public static func truthy(_ value: JSONValue?) -> Bool {
    switch value {
    case .none, .some(.null): return false
    case .some(.bool(let flag)): return flag
    case .some(.number(let number)): return number != 0 && !number.isNaN
    case .some(.string(let text)): return !text.isEmpty
    case .some(.array), .some(.object): return true
    }
  }

  /// A non-empty string field (`typeof v === 'string' && v !== ''`).
  static func nonEmptyString(_ value: JSONValue?) -> String? {
    guard case .some(.string(let text)) = value, !text.isEmpty else { return nil }
    return text
  }

  /// JavaScript's `<` on two strings: by UTF-16 code units.
  static func jsLess(_ a: String, _ b: String) -> Bool {
    a.utf16.lexicographicallyPrecedes(b.utf16)
  }
}

extension JSONValue {
  /// The value as the mirror and the wire write it (see SyncJSON).
  var syncData: Data { SyncJSON.data(self) }

  /// A copy without these fields (does nothing to a value that isn't an object).
  func removing(_ keys: String...) -> JSONValue {
    guard case .object(var fields) = self else { return self }
    for key in keys { fields[key] = nil }
    return .object(fields)
  }

  /// The value, or nil for JSON null. (`JSONValue` takes the `nil` literal
  /// as null, so a bare `nil` in a ternary would be null, not nothing.)
  var nonNull: JSONValue? {
    if case .null = self { return Optional.none }
    return .some(self)
  }

  func setting(_ key: String, _ value: JSONValue?) -> JSONValue {
    var copy = self
    copy.set(key, value)
    return copy
  }
}
