import Foundation
import Testing

@testable import MahamKit

/// src/lib/units.test.ts, then the web's answers for many more ways of
/// writing units (WebFixtures).
@Suite("Units")
struct UnitsTests {
  func company(_ units: [JSONValue]) -> JSONValue {
    ["items": ["units": true, "customUnits": .array(units)]]
  }

  @Test("read pieces however they were typed, in English or Arabic")
  func pieces() {
    for text in ["pc", "pcs", "PCS", "Pcs.", " piece ", "قطعة", "قطعه", "قطع", "pcs"] {
      #expect(Units.matchUnit(text) == "pcs", "\(text)")
    }
    #expect(Units.matchUnit("box") == "box")
    #expect(Units.matchUnit("علبة") == "box")
    #expect(Units.matchUnit("Ctn") == "carton")
    #expect(Units.matchUnit("hrs") == "hour")
    #expect(Units.matchUnit("ساعات") == "hour")
    #expect(Units.matchUnit("Ltr") == "l")
  }

  @Test("leave a unit they don’t know as it was typed")
  func unknown() {
    #expect(Units.matchUnit("roll") == nil)
    #expect(Units.matchUnit("") == nil)
    #expect(Units.matchUnit(nil) == nil)
  }

  @Test("match the company’s own units first, and never an archived one")
  func ownUnits() {
    let own = company([
      ["id": "u-roll", "name": "roll", "nameAr": "لفة"],
      ["id": "u-old", "name": "bag", "nameAr": "كيس", "archived": true],
    ])
    #expect(Units.matchUnit("Roll", own) == "u-roll")
    #expect(Units.matchUnit("لفه", own) == "u-roll")
    #expect(Units.matchUnit("bag", own) == nil)
    #expect(Units.unitChoices(own).map(\.id) == Units.builtIn.map(\.id) + ["u-roll"])
    // A line that has an archived unit still finds it.
    #expect(Units.findUnit(own, "u-old")?.nameAr == "كيس")
    #expect(Units.findUnit(own, "nothing") == nil)
  }

  @Test("are named in Arabic on Arabic and bilingual documents")
  func arabicNames() throws {
    let box = try #require(Units.findUnit(nil, "box"))
    #expect(Units.unitName(box, "ar") == "علبة")
    #expect(Units.unitName(box, "ar-en") == "علبة")
    #expect(Units.unitName(box, "en") == "box")
    #expect(Units.unitName(ItemUnit(id: "u", name: "roll", nameAr: ""), "ar") == "roll")
  }

  @Test("have ids of their own")
  func ownIds() {
    let ids = Units.builtIn.map(\.id)
    #expect(Set(ids).count == ids.count)
    // No alias stands for two units.
    for unit in Units.builtIn {
      for alias in [unit.name, unit.nameAr] + unit.aliases {
        #expect(Units.matchUnit(alias) == unit.id, "\(alias)")
      }
    }
  }

  @Test("print in Arabic only while the text is still the unit picked")
  func printing() {
    #expect(Units.unitText(nil, unit: "box", unitId: "box", language: "ar") == "علبة")
    #expect(Units.unitText(nil, unit: "Boxes", unitId: "box", language: "ar-en") == "علبة")
    #expect(Units.unitText(nil, unit: "box", unitId: "box", language: "en") == "box")
    // An older version typed another unit over it and kept the id.
    #expect(Units.listedUnit(nil, unit: "carton", unitId: "box") == nil)
    #expect(Units.unitText(nil, unit: "carton", unitId: "box", language: "ar") == "carton")
    #expect(Units.unitText(nil, unit: "pcs", unitId: nil, language: "ar") == "pcs")
  }

  @Test("store and print a company unit given only an Arabic name by that name")
  func arabicOnly() throws {
    let own = company([["id": "u-bag", "name": "", "nameAr": " كيس "]])
    let bag = try #require(Units.findUnit(own, "u-bag"))
    // What the unit picker stores on the item: never an empty unit.
    #expect(bag.name == "كيس")
    #expect(Units.unitChoices(own).first { $0.id == "u-bag" }?.name == "كيس")
    #expect(Units.unitText(own, unit: bag.name, unitId: bag.id, language: "ar") == "كيس")
    #expect(Units.unitText(own, unit: bag.name, unitId: bag.id, language: "ar-en") == "كيس")
    #expect(Units.unitText(own, unit: bag.name, unitId: bag.id, language: "en") == "كيس")
    #expect(Units.listedUnit(own, unit: bag.name, unitId: bag.id)?.id == "u-bag")
    #expect(Units.matchUnit("كيس", own) == "u-bag")
  }

  // MARK: The web's answers

  @Test("match units as the web does, with and without the company's own")
  func matchParity() {
    let own = WebFixtures["unitsCompany"]
    for item in WebFixtures["units"].array ?? [] {
      let text = item[0]?.string ?? ""
      #expect(Units.matchUnit(text) == item[1]?.string, "\(text)")
      #expect(Units.matchUnit(text, own) == item[2]?.string, "\(text)")
    }
  }

  @Test("list, find and print units as the web does")
  func listParity() {
    let own = WebFixtures["unitsCompany"]
    for item in WebFixtures["unitText"].array ?? [] {
      let unit = item[0]?.string ?? ""
      #expect(
        Units.unitText(own, unit: unit, unitId: item[1]?.string, language: item[2]?.string ?? "")
          == item[3]?.string, "\(item)")
    }
    let choices = Units.unitChoices(own).map {
      JSONValue.array([.string($0.id), .string($0.name), .string($0.nameAr)])
    }
    #expect(JSONValue.array(choices) == WebFixtures["unitChoices"])
    for item in WebFixtures["findUnit"].array ?? [] {
      #expect(Units.findUnit(own, item[0]?.string)?.name == item[1]?.string, "\(item)")
    }
  }
}
