"""Writes WebFixtures.swift (the web's answers the Swift parity tests check)
from fixtures.json, written by fixtures.gen.ts. See vitest.gen.config.mjs.

usage: emit_swift.py fixtures.json WebFixtures.swift
"""
import json, sys
src, dst = sys.argv[1], sys.argv[2]
d = json.load(open(src))
lines = []
keys = list(d.keys())
for i, k in enumerate(keys):
    comma = ',' if i < len(keys) - 1 else ''
    lines.append(json.dumps(k) + ': ' + json.dumps(d[k], ensure_ascii=True, separators=(',', ':')) + comma)
body = '\n'.join(lines)
assert '"""#' not in body
header = '''import Foundation

@testable import MahamKit

/// What the web's own rules answer for the inputs of the parity tests,
/// written by running the TypeScript (src/lib, src/db/defaults.ts,
/// src/cloud/roles.ts) under vitest. Large inputs are rebuilt by the tests
/// themselves, the same way the web's tests build them, and checked against
/// the hash of the web's copy (`samples` keys); answers that are records are
/// hashes too: `webHash`, 12 hex characters of stableId over JSON with
/// sorted keys. Regenerate when the web's rules change.
enum WebFixtures {
  static let all: JSONValue = {
    do {
      return try JSONValue.parse(Data(text.utf8))
    } catch {
      fatalError("The web fixtures are not JSON: \\(error)")
    }
  }()

  static subscript(key: String) -> JSONValue {
    guard let value = all[key] else { fatalError("No web fixture \\(key)") }
    return value
  }

  private static let text = #"""
{
'''
footer = '''
}
"""#
}

/// The web's hash of a value for the fixtures: 12 hex characters of
/// stableId over its JSON with sorted keys (`canon` in the generator).
func webHash(_ value: JSONValue?) -> String {
  String(stableId(WebJS.json(value ?? .null)).dropFirst(4).prefix(12))
}

extension JSONValue {
  /// `{ ...self, ...extra }`: a nil in `extra` leaves the field out, as
  /// `undefined` does in JavaScript.
  func with(_ extra: [String: JSONValue?]) -> JSONValue {
    var fields = object ?? [:]
    for (key, value) in extra { fields[key] = value }
    return .object(fields)
  }

  /// The characters of a fixture's string of answers.
  var chars: [Character] { Array(string ?? "") }
  var strings: [String] { (array ?? []).map { $0.string ?? "" } }
}
'''
open(dst, 'w').write(header + body + footer)
