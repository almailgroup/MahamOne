import Foundation

/// Any JSON value, kept exactly as it came: the native app stores Maham One's
/// records as the web wrote them and sends them back whole, so a field this
/// version doesn't know about is never lost (pushes replace whole records;
/// a dropped field would be deleted for every device).
///
/// Numbers are `Double`, as they are in the web app (JavaScript numbers), so
/// a record read and written back unchanged compares equal on both sides.
/// Money is never computed in `Double`: it goes through `Decimal` built from
/// the number's shortest string (see Money).
public enum JSONValue: Hashable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  // MARK: Reading

  public subscript(key: String) -> JSONValue? {
    if case .object(let fields) = self { return fields[key] }
    return nil
  }

  public subscript(index: Int) -> JSONValue? {
    if case .array(let items) = self, items.indices.contains(index) { return items[index] }
    return nil
  }

  public var string: String? {
    if case .string(let value) = self { return value }
    return nil
  }

  public var double: Double? {
    if case .number(let value) = self { return value }
    return nil
  }

  public var int: Int? {
    if case .number(let value) = self, value.rounded() == value, abs(value) < 9e15 { return Int(value) }
    return nil
  }

  public var bool: Bool? {
    if case .bool(let value) = self { return value }
    return nil
  }

  public var array: [JSONValue]? {
    if case .array(let items) = self { return items }
    return nil
  }

  public var object: [String: JSONValue]? {
    if case .object(let fields) = self { return fields }
    return nil
  }

  public var isNull: Bool {
    if case .null = self { return true }
    return false
  }

  // MARK: Changing

  /// Sets (or, with nil, removes) a field of an object; does nothing to a
  /// value that isn't an object.
  public mutating func set(_ key: String, _ value: JSONValue?) {
    guard case .object(var fields) = self else { return }
    fields[key] = value
    self = .object(fields)
  }

  /// The web's `sameData`: deep equality where a missing field and `null`
  /// are the same thing.
  public func sameData(_ other: JSONValue) -> Bool {
    switch (self, other) {
    case (.object(let a), .object(let b)):
      for key in Set(a.keys).union(b.keys) {
        let left = a[key] ?? .null
        let right = b[key] ?? .null
        if !left.sameData(right) { return false }
      }
      return true
    case (.array(let a), .array(let b)):
      return a.count == b.count && zip(a, b).allSatisfy { $0.sameData($1) }
    case (.number(let a), .number(let b)):
      return a == b || (a.isNaN && b.isNaN)
    default:
      return self == other
    }
  }
}

// MARK: JSON text

extension JSONValue: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not JSON")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }

  /// Parses JSON text (UTF-8 data).
  public static func parse(_ data: Data) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: data)
  }

  /// JSON text, keys sorted so the same value always gives the same bytes.
  public func data() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self)
  }
}

// MARK: Literals

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
  ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral,
  ExpressibleByDictionaryLiteral
{
  public init(nilLiteral: ()) { self = .null }
  public init(booleanLiteral value: Bool) { self = .bool(value) }
  public init(integerLiteral value: Int) { self = .number(Double(value)) }
  public init(floatLiteral value: Double) { self = .number(value) }
  public init(stringLiteral value: String) { self = .string(value) }
  public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
  public init(dictionaryLiteral elements: (String, JSONValue)...) {
    self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
  }
}
