import Foundation
import Testing

@testable import MahamKit

// The web's src/i18n/i18n.test.tsx (all but `tr`, which builds React
// elements), and the generated Arabic dictionary, Shared/Resources/ar.json.

private let invoices: [String: I18n.Entry] = [
  "{count} invoices": .plural(
    .init(
      zero: "لا توجد فواتير", one: "فاتورة واحدة", two: "فاتورتان", few: "{count} فواتير", many: "{count} فاتورة",
      other: "{count} فاتورة"))
]

/// The app's Arabic strings, as `scripts/ios-strings.ts` writes them.
private func arabicTable() throws -> I18n.Table {
  let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Shared/Resources/ar.json")
  return try I18n.Table(json: Data(contentsOf: url))
}

@Suite("i18n.test: t")
struct TranslateTests {
  @Test("returns English when there is no translation")
  func english() {
    let t = I18n.Translator.english
    #expect(t.t("Save") == "Save")
    #expect(t.t("Invoice {number} sent", ["number": "INV-1"]) == "Invoice INV-1 sent")
  }

  @Test("translates and fills placeholders")
  func translates() {
    let t = I18n.Translator(
      language: .ar, table: .init(["Invoice {number} sent": .text("تم إرسال الفاتورة {number}")]))
    #expect(t.t("Invoice {number} sent", ["number": "INV-1"]) == "تم إرسال الفاتورة INV-1")
  }
}

@Suite("i18n.test: tp")
struct PluralTests {
  @Test("uses one and other in English")
  func english() {
    let t = I18n.Translator.english
    #expect(t.tp(1, "{count} invoice", "{count} invoices") == "1 invoice")
    #expect(t.tp(1200, "{count} invoice", "{count} invoices") == "1,200 invoices")
  }

  @Test("picks the Arabic plural form")
  func arabic() {
    let t = I18n.Translator(language: .ar, table: .init(invoices))
    let n = { (count: Int) in t.tp(count, "{count} invoice", "{count} invoices") }
    #expect(n(0) == "لا توجد فواتير")
    #expect(n(1) == "فاتورة واحدة")
    #expect(n(2) == "فاتورتان")
    #expect(n(5) == "5 فواتير")
    #expect(n(11) == "11 فاتورة")
    #expect(n(100) == "100 فاتورة")
  }
}

@Suite("i18n.test: switching language")
struct LanguageSwitchTests {
  @Test("switches the page direction and number locale")
  func switches() throws {
    #expect(InterfaceLanguage.ar.isRightToLeft)
    #expect(InterfaceLanguage.ar.tag == "ar-KW")
    #expect(FormatLocale.interface(.ar, companyLocale: "en-KW").identifier == "ar-KW-u-nu-latn")
    let arabic = I18n.Translator(language: .ar, table: try arabicTable())
    #expect(arabic.t("Governorate") == "المحافظة")
    #expect(!InterfaceLanguage.en.isRightToLeft)
    #expect(InterfaceLanguage.en.tag == "en")
    #expect(FormatLocale.interface(.en, companyLocale: "en-KW").identifier == "en-KW")
  }
}

@Suite("Interface text")
struct InterfaceTextTests {
  @Test("placeholders are letters, digits and _; unknown ones stay")
  func interpolation() {
    #expect(I18n.interpolate("{a} and {b}", ["a": "1"]) == "1 and {b}")
    #expect(I18n.interpolate("{{count}}", ["count": "5"]) == "{5}")
    #expect(I18n.interpolate("{ count } {}", ["count": "5", "": "x"]) == "{ count } {}")
    #expect(I18n.interpolate("{n_1}{n_1}", ["n_1": "x"]) == "xx")
    #expect(I18n.interpolate("{اسم}", ["اسم": "x"]) == "{اسم}")
    #expect(I18n.interpolate("{a}", [:]) == "{a}")
  }

  @Test("a plural entry used by t gives its other form; missing text stays English")
  func pluralWithT() {
    let t = I18n.Translator(language: .ar, table: .init(invoices))
    #expect(t.t("{count} invoices", ["count": "3"]) == "3 فاتورة")
    #expect(t.tp(3, "{count} invoice", "{count} invoice drafts") == "3 invoice drafts")
    #expect(t.tp(1, "{count} invoice", "{count} invoice drafts") == "1 invoice")
  }

  @Test("tp lets the variables replace the count and writes decimals")
  func counts() {
    let t = I18n.Translator.english
    #expect(t.tp(2, "{count} day", "{count} days", ["count": "two"]) == "two days")
    #expect(t.tp(1.5, "{count} day", "{count} days") == "1.5 days")
    #expect(t.tp(1.0004, "{count} day", "{count} days") == "1 days")
  }

  @Test("Arabic plural rules, as Intl.PluralRules('ar')")
  func rules() {
    let cases: [(Double, I18n.PluralCategory)] = [
      (0, .zero), (1, .one), (2, .two), (3, .few), (10, .few), (11, .many), (99, .many), (100, .other),
      (101, .other), (102, .other), (103, .few), (111, .many), (1000, .other), (1.5, .other), (1.0001, .one),
      (-1, .one), (-3, .few), (0.5, .other), (2.0004, .two), (0.0004, .zero), (0.0005, .other),
      (3.0004, .few), (1e21, .other),
    ]
    for (count, category) in cases {
      #expect(I18n.pluralCategory(count, language: .ar) == category, "\(count)")
    }
  }

  @Test("the real dictionary's plurals")
  func dictionary() throws {
    let t = I18n.Translator(language: .ar, table: try arabicTable())
    let years = { (count: Int) in t.tp(count, "{count} year", "{count} years") }
    #expect(years(1) == "سنة واحدة")
    #expect(years(2) == "سنتان")
    #expect(years(3) == "3 سنوات")
    #expect(years(11) == "11 سنة")
    #expect(years(100) == "100 سنة")
    #expect(years(0) == "0 سنة")
    #expect(years(1200) == "1,200 سنة")
    #expect(t.tp(0, "{count} invoice", "{count} invoices") == "لا توجد فواتير")
  }

  @Test("the generated dictionary is whole")
  func generated() throws {
    let table = try arabicTable()
    #expect(table.count > 6000)
    #expect(table["Save"] == .text("حفظ"))
    guard case .plural(let forms) = table["{count} invoices"] else {
      Issue.record("{count} invoices has no plural forms")
      return
    }
    #expect(forms.zero == "لا توجد فواتير")
    #expect(forms.other == "{count} فاتورة")
  }

  @Test("Arabic names in the Arabic interface, when there is one")
  func names() {
    #expect(I18n.localName("Acme", " أكمي ", language: .ar) == "أكمي")
    #expect(I18n.localName("Acme", "  ", language: .ar) == "Acme")
    #expect(I18n.localName("Acme", nil, language: .ar) == "Acme")
    #expect(I18n.localName("Acme", "أكمي", language: .en) == "Acme")
  }

  @Test("the first language follows the device, then the saved choice")
  func stored() {
    #expect(InterfaceLanguage.stored(nil, preferredLanguages: ["ar-KW", "en"]) == .ar)
    #expect(InterfaceLanguage.stored(nil, preferredLanguages: ["en-KW", "ar"]) == .en)
    #expect(InterfaceLanguage.stored(nil, preferredLanguages: []) == .en)
    #expect(InterfaceLanguage.stored("en", preferredLanguages: ["ar"]) == .en)
    #expect(InterfaceLanguage.stored("fr", preferredLanguages: ["AR"]) == .ar)
  }
}
