import Foundation

/// A unit items are counted and sold in: built in, or one of the company's own.
public struct ItemUnit: Hashable, Sendable {
  public var id: String
  /// Printed on English documents and stored as the line's unit.
  public var name: String
  public var nameAr: String
  public var archived: Bool

  public init(id: String, name: String, nameAr: String, archived: Bool = false) {
    self.id = id
    self.name = name
    self.nameAr = nameAr
    self.archived = archived
  }
}

/// Units items are counted and sold in (src/lib/units.ts): a fixed list with
/// Arabic names, plus the company's own (`company.items.customUnits`). A line
/// keeps the unit as printed text (`unit`) and, when it was picked from the
/// list, its id (`unitId`), so Arabic documents can print the Arabic name.
public enum Units {
  public struct BuiltIn: Hashable, Sendable {
    public var id: String
    public var name: String
    public var nameAr: String
    /// Other ways the unit is written, in English and Arabic.
    public var aliases: [String]

    public var unit: ItemUnit { ItemUnit(id: id, name: name, nameAr: nameAr) }
  }

  /// The built-in units. Their ids never change: lines and items keep them.
  public static let builtIn: [BuiltIn] = [
    BuiltIn(
      id: "pcs", name: "pcs", nameAr: "قطعة",
      aliases: ["pc", "pce", "piece", "pieces", "ea", "each", "nos", "no", "قطع", "حبة", "حبات"]),
    BuiltIn(id: "box", name: "box", nameAr: "علبة", aliases: ["boxes", "bx", "علب"]),
    BuiltIn(id: "carton", name: "carton", nameAr: "كرتون", aliases: ["cartons", "ctn", "ctns", "كراتين"]),
    BuiltIn(
      id: "kg", name: "kg", nameAr: "كغ",
      aliases: ["kgs", "kilo", "kilos", "kilogram", "kilograms", "كجم", "كيلو", "كيلوغرام"]),
    BuiltIn(
      id: "l", name: "litre", nameAr: "لتر", aliases: ["l", "ltr", "ltrs", "litres", "liter", "liters", "لترات"]),
    BuiltIn(
      id: "m", name: "m", nameAr: "متر", aliases: ["mtr", "mtrs", "metre", "metres", "meter", "meters", "أمتار"]),
    BuiltIn(id: "hour", name: "hour", nameAr: "ساعة", aliases: ["h", "hr", "hrs", "hours", "ساعات"]),
    BuiltIn(id: "day", name: "day", nameAr: "يوم", aliases: ["days", "أيام"]),
    BuiltIn(id: "month", name: "month", nameAr: "شهر", aliases: ["months", "mo", "أشهر", "شهور"]),
    BuiltIn(id: "trip", name: "trip", nameAr: "رحلة", aliases: ["trips", "رحلات"]),
    BuiltIn(id: "set", name: "set", nameAr: "طقم", aliases: ["sets", "أطقم"]),
  ]

  /// Text folded for comparing: lower case, no dots or spaces at the ends,
  /// and Arabic without diacritics, tatweel or the variants of alef, yaa and
  /// taa marbuta.
  public static func fold(_ text: String) -> String {
    var folded = String.UnicodeScalarView()
    for scalar in text.precomposedStringWithCompatibilityMapping.lowercased().unicodeScalars {
      switch scalar.value {
      case 0x064B...0x065F, 0x0670, 0x0640: continue
      case 0x0623, 0x0625, 0x0622: folded.append("\u{0627}")
      case 0x0649: folded.append("\u{064A}")
      case 0x0629: folded.append("\u{0647}")
      default: folded.append(scalar)
      }
    }
    // \s+ → one space
    var spaced = String.UnicodeScalarView()
    var inSpace = false
    for scalar in folded {
      if WebJS.isSpace(scalar) {
        if !inSpace { spaced.append(" ") }
        inSpace = true
      } else {
        spaced.append(scalar)
        inSpace = false
      }
    }
    // ^[\s.]+|[\s.]+$ → ''
    let scalars = Array(spaced)
    let edge = { (s: Unicode.Scalar) in WebJS.isSpace(s) || s == "." }
    guard let first = scalars.firstIndex(where: { !edge($0) }), let last = scalars.lastIndex(where: { !edge($0) })
    else { return "" }
    return String(String.UnicodeScalarView(scalars[first...last]))
  }

  /// The company's own units, archived ones included.
  public static func customUnits(_ company: JSONValue?) -> [ItemUnit] {
    guard let units = company?["items"]?["customUnits"]?.array else { return [] }
    return units.map { unit in
      ItemUnit(
        id: unit["id"]?.string ?? "", name: unit["name"]?.string ?? "", nameAr: unit["nameAr"]?.string ?? "",
        archived: WebJS.truthy(unit["archived"]))
    }
  }

  /// A company unit as listed: one given only an Arabic name prints that name
  /// on English documents too, and is stored with it (never an empty unit).
  private static func ownUnit(_ unit: ItemUnit) -> ItemUnit {
    if !WebJS.trim(unit.name).isEmpty { return unit }
    var copy = unit
    copy.name = WebJS.trim(unit.nameAr)
    return copy
  }

  /// Units to pick from: the built-in ones, then the company's own that aren't archived.
  public static func unitChoices(_ company: JSONValue?) -> [ItemUnit] {
    builtIn.map(\.unit) + customUnits(company).filter { !$0.archived }.map(ownUnit)
  }

  /// The unit with this id, built in or the company's (archived too); nil when unknown.
  public static func findUnit(_ company: JSONValue?, _ id: String?) -> ItemUnit? {
    guard let id, !id.isEmpty else { return nil }
    if let found = builtIn.first(where: { $0.id == id }) { return found.unit }
    return customUnits(company).first { $0.id == id }.map(ownUnit)
  }

  /// The unit a text stands for ("pc", "Pcs.", "قطعة" are all pieces), for
  /// items saved before units came from a list: the company's own units
  /// first, then the built-in ones; nil when nothing matches.
  public static func matchUnit(_ text: String?, _ company: JSONValue? = nil) -> String? {
    let folded = fold(text ?? "")
    if folded.isEmpty { return nil }
    if let own = customUnits(company).first(where: {
      !$0.archived && (fold($0.name) == folded || fold($0.nameAr) == folded)
    }) {
      return own.id
    }
    return builtIn.first { unit in
      ([unit.id, unit.name, unit.nameAr] + unit.aliases).contains { fold($0) == folded }
    }?.id
  }

  /// A unit's name in a document's language ("en", "ar", "ar-en", …).
  public static func unitName(_ unit: ItemUnit, _ language: String) -> String {
    guard language == "ar" || language == "ar-en" else { return unit.name }
    let arabic = WebJS.trim(unit.nameAr)
    return arabic.isEmpty ? unit.name : arabic
  }

  /// Whether `text` is one of the unit's names (or, for a built-in unit, the ways it is written).
  public static func namesUnit(_ text: String?, _ unit: ItemUnit) -> Bool {
    let folded = fold(text ?? "")
    if folded.isEmpty { return false }
    let extra = builtIn.first { $0.id == unit.id }.map { [$0.id] + $0.aliases } ?? []
    return ([unit.name, unit.nameAr] + extra).contains { fold($0) == folded }
  }

  /// The unit of an item (or a line) picked from the list, while its text is
  /// still that unit's: an older version may have typed another unit over it
  /// and kept the id. Nil otherwise.
  public static func listedUnit(_ company: JSONValue?, unit: String, unitId: String?) -> ItemUnit? {
    guard let found = findUnit(company, unitId), namesUnit(unit, found) else { return nil }
    return found
  }

  /// How an item's (or a line's) unit reads in a document's language: on
  /// Arabic and bilingual documents the Arabic name of a unit picked from the
  /// list; else the unit as stored.
  public static func unitText(_ company: JSONValue?, unit: String, unitId: String?, language: String) -> String {
    guard language == "ar" || language == "ar-en" else { return unit }
    let arabic = listedUnit(company, unit: unit, unitId: unitId).map { WebJS.trim($0.nameAr) } ?? ""
    return arabic.isEmpty ? unit : arabic
  }
}
