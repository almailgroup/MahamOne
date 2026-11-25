import Foundation
import Testing

@testable import MahamKit

@Suite("Sync: JSON")
struct SyncJSONTests {
  @Test("reads and writes back every value, escapes and all")
  func roundTrip() throws {
    let text = #"{"id":"d1","name":"مؤسسة \"الخليج\"\n","lines":[{"qty":2,"price":150.25,"tax":null,"ok":true}],"emoji":"😀","esc":"a\/b\u0007"}"#
    let value = try SyncJSON.parse(text)
    #expect(value["name"]?.string == "مؤسسة \"الخليج\"\n")
    #expect(value["emoji"]?.string == "😀")
    #expect(value["esc"]?.string == "a/b\u{07}")
    #expect(value["lines"]?[0]?["tax"] == .null)
    #expect(value["lines"]?[0]?["ok"] == .bool(true))
    #expect(try SyncJSON.parse(SyncJSON.data(value)) == value)
    #expect(try JSONValue.parse(SyncJSON.data(value)) == value)
    #expect(SyncJSON.string(["a": 1, "b": [true, nil]]) == #"{"a":1,"b":[true,null]}"#)
  }

  @Test("refuses what isn't JSON")
  func invalid() {
    for text in [#"{"a":1"#, #"{"a":1}x"#, #"["\ud800"]"#, #"{"a":01}"#, #"[1,]"#, "nul", "\"tab\u{09}in\""] {
      #expect(throws: SyncJSON.ParseError.self) { try SyncJSON.parse(text) }
    }
  }

  @Test("prints numbers as JavaScript's String(n)")
  func numbers() {
    let cases: [(Double, String)] = [
      (5, "5"), (0.1, "0.1"), (150.25, "150.25"), (-2.5, "-2.5"), (1e21, "1e+21"), (1.5e-7, "1.5e-7"),
      (1e-7, "1e-7"), (0.000001, "0.000001"), (123_456_789_012, "123456789012"), (-0.0, "0"),
      (73_786_976_294_838_206_464, "73786976294838210000"), (100, "100"), (1e300, "1e+300"), (0.3, "0.3"),
    ]
    for (number, text) in cases { #expect(SyncJSON.jsNumber(number) == text, "\(number)") }
  }

  @Test("measures length as the web does, in UTF-16 units")
  func length() {
    #expect(SyncJSON.jsLength(["name": "كويت"]) == #"{"name":"كويت"}"#.utf16.count)
    #expect(SyncJSON.jsLength(["e": "😀"]) == 10)
  }

  @Test("sameData is the web's exactly: a key holding null is still a key")
  func sameData() {
    #expect(SyncJSON.sameData(nil, .null))
    #expect(SyncJSON.sameData(["a": [1, ["b": "x"]]], ["a": [1, ["b": "x"]]]))
    #expect(!SyncJSON.sameData(["a": nil], [:]))
    #expect(!SyncJSON.sameData(["a": 1], ["a": 1, "b": nil]))
    #expect(!SyncJSON.sameData([:], []))
    #expect(!SyncJSON.sameData(["a": 1], nil))
    #expect(!SyncJSON.sameData(1, "1"))
    // JSONValue.sameData is looser (null and missing alike); the sync uses the web's.
    #expect(JSONValue.object(["a": nil]).sameData([:]))
  }

  @Test("truthiness as JavaScript's")
  func truthy() {
    #expect(!SyncJSON.truthy(nil))
    #expect(!SyncJSON.truthy(.null))
    #expect(!SyncJSON.truthy(""))
    #expect(!SyncJSON.truthy(0))
    #expect(SyncJSON.truthy("e1"))
    #expect(SyncJSON.truthy(1))
    #expect(SyncJSON.truthy([:]))
  }
}
