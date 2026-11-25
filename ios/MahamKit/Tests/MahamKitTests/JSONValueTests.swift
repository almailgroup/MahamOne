import Foundation
import Testing

@testable import MahamKit

@Suite("Raw records")
struct JSONValueTests {
  @Test("a record read and written back keeps every field, known or not")
  func roundTrip() throws {
    let text = #"{"id":"d1","companyId":"c1","futureField":{"nested":[1,2.5,"x",null,true]},"total":1234.5}"#
    let value = try JSONValue.parse(Data(text.utf8))
    let again = try JSONValue.parse(try value.data())
    #expect(again == value)
    #expect(value["futureField"]?["nested"]?[1]?.double == 2.5)
    #expect(value["total"]?.double == 1234.5)
  }

  @Test("booleans stay booleans and numbers stay numbers")
  func types() throws {
    let value = try JSONValue.parse(Data(#"{"a":true,"b":1,"c":0,"d":false}"#.utf8))
    #expect(value["a"] == .bool(true))
    #expect(value["b"] == .number(1))
    #expect(value["c"] == .number(0))
    #expect(value["d"] == .bool(false))
  }

  @Test("the web's sameData: missing and null are the same")
  func sameData() {
    let a: JSONValue = ["id": "x", "notes": nil, "lines": [["qty": 1]]]
    let b: JSONValue = ["id": "x", "lines": [["qty": 1]]]
    let c: JSONValue = ["id": "x", "lines": [["qty": 2]]]
    #expect(a.sameData(b))
    #expect(!a.sameData(c))
  }

  @Test("setting and removing a field")
  func setting() {
    var value: JSONValue = ["id": "x"]
    value.set("status", "paid")
    #expect(value["status"]?.string == "paid")
    value.set("status", nil)
    #expect(value["status"] == nil)
  }
}
