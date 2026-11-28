import Foundation
import Testing

@testable import MahamKit

/// The web's own outputs for a write port (Fixtures/writes-<area>.json,
/// written by ios/scripts/web-fixtures/writes-<area>.gen.ts): each scenario
/// holds every table before and after the web's write function ran, with
/// fixed ids and a fixed clock. A port's test starts a `WriteContext` on
/// `before` with the same ids and clock (`context`), runs the port, and
/// checks every table against `after` (`assertMatches`).
struct WriteScenario {
  let name: String
  let now: Date
  let today: String
  let userId: String?
  let userName: String?
  let role: MemberRole
  let input: JSONValue
  let idStart: Int
  let before: [String: [JSONValue]]
  let after: [String: [JSONValue]]
  let error: String?

  /// The web's id number `n` ("00000001-0000-4000-8000-000000000000").
  static func fixedId(_ n: Int) -> String {
    let hex = String(n, radix: 16)
    return String(repeating: "0", count: max(0, 8 - hex.count)) + hex + "-0000-4000-8000-000000000000"
  }

  /// A context on `before`, handing out the same ids as the web did and stopped at the same moment.
  func context(companyId: String? = nil) -> WriteContext {
    var counter = idStart
    let tables = before.mapValues { rows in
      Dictionary(rows.compactMap { row in row["id"]?.string.map { ($0, row) } }, uniquingKeysWith: { _, last in last })
    }
    let company = companyId ?? before["companies"]?.first?["id"]?.string ?? ""
    return WriteContext(
      companyId: company, userId: userId, userName: userName, role: role, now: now, today: today,
      makeId: {
        counter += 1
        return WriteScenario.fixedId(counter)
      },
      records: { tables[$0] ?? [:] })
  }

  /// What every table holds once `changes` are applied to `before`, each sorted by id.
  func applying(_ changes: [RecordChange]) -> [String: [JSONValue]] {
    var tables = before.mapValues { rows in
      Dictionary(rows.compactMap { row in row["id"]?.string.map { ($0, row) } }, uniquingKeysWith: { _, last in last })
    }
    for change in changes {
      switch change {
      case .put(let table, let record):
        if let id = record["id"]?.string { tables[table, default: [:]][id] = record }
      case .delete(let table, let id):
        tables[table]?[id] = nil
      }
    }
    var result: [String: [JSONValue]] = [:]
    for (table, rows) in tables where !rows.isEmpty {
      result[table] = rows.keys.sorted().compactMap { rows[$0] }
    }
    return result
  }
}

enum WriteParity {
  /// The scenarios of Fixtures/writes-<area>.json.
  static func scenarios(_ area: String) throws -> [WriteScenario] {
    guard
      let url = Bundle.module.url(forResource: "writes-\(area)", withExtension: "json", subdirectory: "Fixtures")
    else {
      throw FixtureError.missing("Fixtures/writes-\(area).json")
    }
    let root = try JSONValue.parse(Data(contentsOf: url))
    return (root["scenarios"]?.array ?? []).map { item in
      WriteScenario(
        name: item["name"]?.string ?? "",
        now: parseStamp(item["now"]?.string ?? "") ?? Date(timeIntervalSince1970: 0),
        today: item["today"]?.string ?? "",
        userId: item["userId"]?.string,
        userName: item["userName"]?.string,
        role: MemberRole(rawValue: item["role"]?.string ?? "") ?? .owner,
        input: item["input"] ?? .null,
        idStart: item["idStart"]?.int ?? 0,
        before: tables(item["before"]),
        after: tables(item["after"]),
        error: item["error"]?.string)
    }
  }

  enum FixtureError: Error, CustomStringConvertible {
    case missing(String)
    var description: String {
      switch self {
      case .missing(let path): "\(path) is missing: run the generator (Fixtures/README.md)."
      }
    }
  }

  private static func tables(_ value: JSONValue?) -> [String: [JSONValue]] {
    (value?.object ?? [:]).mapValues { $0.array ?? [] }
  }

  /// "2026-11-28T09:00:00.000Z" as a Date.
  static func parseStamp(_ text: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
  }

  /// Every table the port left must equal the web's, record for record
  /// (`sameData`: numbers as numbers, objects without key order). The
  /// first differences are reported with the record and the field.
  static func assertMatches(
    _ actual: [String: [JSONValue]], _ expected: [String: [JSONValue]], scenario: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let names = Set(actual.keys).union(expected.keys).sorted()
    var problems: [String] = []
    for name in names {
      let mine = Dictionary(
        (actual[name] ?? []).map { ($0["id"]?.string ?? "", $0) }, uniquingKeysWith: { _, last in last })
      let web = Dictionary(
        (expected[name] ?? []).map { ($0["id"]?.string ?? "", $0) }, uniquingKeysWith: { _, last in last })
      for id in Set(mine.keys).union(web.keys).sorted() {
        switch (mine[id], web[id]) {
        case (nil, .some):
          problems.append("\(name)/\(id): the web has it, the port doesn't")
        case (.some, nil):
          problems.append("\(name)/\(id): the port has it, the web doesn't")
        case (.some(let a), .some(let b)) where !a.sameData(b):
          problems.append("\(name)/\(id): \(difference(a, b))")
        default:
          break
        }
      }
    }
    if !problems.isEmpty {
      Issue.record(
        "\(scenario): \(problems.count) difference(s)\n  " + problems.prefix(12).joined(separator: "\n  "),
        sourceLocation: sourceLocation)
    }
  }

  /// The first field (as a path) where two records differ.
  static func difference(_ a: JSONValue, _ b: JSONValue, path: String = "") -> String {
    switch (a, b) {
    case (.object(let x), .object(let y)):
      for key in Set(x.keys).union(y.keys).sorted() {
        let left = x[key]
        let right = y[key]
        if let left, let right {
          if !left.sameData(right) { return difference(left, right, path: "\(path).\(key)") }
        } else if left != nil || right != nil {
          // A field one side has and the other leaves out (JSON drops undefined).
          return "\(path).\(key): port \(describe(left)) vs web \(describe(right))"
        }
      }
      return "\(path): differ"
    case (.array(let x), .array(let y)):
      if x.count != y.count { return "\(path): \(x.count) items vs web \(y.count)" }
      for (index, pair) in zip(x, y).enumerated() where !pair.0.sameData(pair.1) {
        return difference(pair.0, pair.1, path: "\(path)[\(index)]")
      }
      return "\(path): differ"
    default:
      return "\(path.isEmpty ? "record" : path): port \(describe(a)) vs web \(describe(b))"
    }
  }

  private static func describe(_ value: JSONValue?) -> String {
    guard let value else { return "(missing)" }
    guard let data = try? value.data(), let text = String(data: data, encoding: .utf8) else { return "?" }
    return text.count > 120 ? String(text.prefix(117)) + "…" : text
  }
}
