import Foundation
import Testing

@testable import MahamKit

/// src/lib/ids.ts has no tests of its own: these check the ids against the
/// web's, worked out by running its TypeScript (see WebFixtures).
@Suite("Ids")
struct IdsTests {
  @Test("stableId gives the web's id for the same text, bit for bit")
  func stableIdMatchesTheWeb() {
    let cases = WebFixtures["stableId"].array ?? []
    #expect(cases.count == 12)
    for pair in cases {
      let text = pair[0]?.string ?? ""
      #expect(stableId(text) == pair[1]?.string, "\(text.prefix(40))")
    }
  }

  @Test("stableId of known texts, as the web computes them")
  func stableIdKnownValues() {
    #expect(stableId("") == "00001c4425d7d009e10791d3587ca4bf")
    #expect(stableId("hello") == "00001897bfcd0b34430b4f13a1bb1a72")
    // A stock movement's id: sm- and the key of what it is.
    #expect("sm-" + stableId("co-1|doc-1|out:prod-1:wh-1|0") == "sm-" + (WebFixtures["stableId"][6]?[1]?.string ?? ""))
    #expect(stableId("a").count == 32)
  }

  @Test("stableId reads text as UTF-16, as JavaScript does")
  func stableIdUTF16() {
    // The same characters, composed and not, are different texts.
    #expect(stableId("\u{e9}") != stableId("e\u{301}"))
    #expect(stableId("😀").count == 32)
  }

  @Test("newId is a lowercase UUID v4")
  func newIdShape() {
    let id = newId()
    #expect(id.count == 36)
    #expect(id == id.lowercased())
    let parts = id.split(separator: "-")
    #expect(parts.map(\.count) == [8, 4, 4, 4, 12])
    #expect(parts[2].first == "4")
    #expect(["8", "9", "a", "b"].contains(parts[3].first))
    #expect(newId() != newId())
  }

  @Test("shortId is 12 hex characters")
  func shortIdShape() {
    let id = shortId()
    #expect(id.count == 12)
    #expect(id.allSatisfy { $0.isHexDigit && !$0.isUppercase })
  }
}
