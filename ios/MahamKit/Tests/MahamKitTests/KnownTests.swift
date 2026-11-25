import Foundation
import Testing

@testable import MahamKit

/// src/lib/known.test.ts ("looking up a stored value"). The rest of that file
/// tests the modules that use `lookup` (leave, employees, statuses…), ported
/// with them.
@Suite("Known values")
struct KnownTests {
  @Test("finds known values, and falls back for others and for inherited keys")
  func lookingUp() {
    let map = ["a": 1, "b": 2]
    #expect(Known.lookup(map, "a", 0) == 1)
    #expect(Known.lookup(map, "c", 0) == 0)
    #expect(Known.lookup(map, "constructor", 0) == 0)
    #expect(Known.lookup(map, nil as String?, 0) == 0)
    #expect(Known.isKnown(map, "b"))
    #expect(!Known.isKnown(map, "toString"))
  }

  @Test("reads stored values, which may not be text")
  func storedValues() {
    let map = ["a": 1]
    #expect(Known.lookup(map, JSONValue.string("a"), 0) == 1)
    #expect(Known.lookup(map, JSONValue.number(1), 0) == 0)
    #expect(Known.lookup(map, JSONValue.null, 0) == 0)
    #expect(!Known.isKnown(map, JSONValue.bool(true)))
  }

  @Test("gives a fallback case for a value of a newer version")
  func enumCases() {
    #expect(Known.lookup(JSONValue.string("yearly"), CounterReset.never) == .yearly)
    #expect(Known.lookup(JSONValue.string("weekly"), CounterReset.never) == .never)
    #expect(Known.lookup(nil as JSONValue?, CounterReset.monthly) == .monthly)
    #expect(Known.lookup("staff", MemberRole.viewer) == .staff)
    #expect(Known.lookup("boss", MemberRole.viewer) == .viewer)
  }
}
