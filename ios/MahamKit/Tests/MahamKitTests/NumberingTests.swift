import Foundation
import Testing

@testable import MahamKit

/// src/lib/numbering.test.ts, then the web's answers for many more patterns,
/// counters and dates (WebFixtures).
@Suite("Numbering")
struct NumberingTests {
  func rule(
    pattern: String = "INV-{year}-{counter}", next: Int = 1, padding: Int = 4, reset: CounterReset = .never,
    period: String = ""
  ) -> NumberingRule {
    NumberingRule(pattern: pattern, next: next, padding: padding, reset: reset, period: period)
  }

  @Test("formats placeholders")
  func formatsPlaceholders() {
    #expect(Numbering.formatNumber(rule(), 7, "2026-03-09") == "INV-2026-0007")
    #expect(
      Numbering.formatNumber(
        pattern: "{client}/{yy}{month}{day}/{counter}", padding: 3, counter: 12, date: "2026-03-09",
        clientNumber: "C-01") == "C-01/260309/012")
  }

  @Test("appends the counter when the pattern has none")
  func appendsCounter() {
    #expect(Numbering.formatNumber(pattern: "Q-", padding: 2, counter: 3, date: "2026-01-01") == "Q-03")
    #expect(Numbering.formatNumber(pattern: "", padding: 0, counter: 3, date: "2026-01-01") == "3")
  }

  @Test("leaves unknown placeholders untouched")
  func unknownPlaceholders() {
    #expect(Numbering.formatNumber(pattern: "{foo}-{counter}", padding: 1, counter: 1, date: "2026-01-01") == "{foo}-1")
  }

  @Test("resets yearly and monthly counters when the period changes")
  func resets() {
    #expect(Numbering.currentCounter(rule(next: 40, reset: .yearly, period: "2025"), "2026-01-02") == 1)
    #expect(Numbering.currentCounter(rule(next: 40, reset: .yearly, period: "2026"), "2026-05-02") == 40)
    #expect(Numbering.currentCounter(rule(next: 9, reset: .monthly, period: "2026-04"), "2026-05-02") == 1)
    #expect(Numbering.currentCounter(rule(next: 9, reset: .never, period: "2020"), "2026-05-02") == 9)
  }

  @Test("allocates the next free number and advances the rule")
  func allocates() {
    let taken: Set<String> = ["INV-2026-0003", "INV-2026-0004"]
    let result = Numbering.allocateNumber(rule(next: 3, reset: .yearly, period: "2026"), "2026-06-01") {
      taken.contains($0)
    }
    #expect(result.number == "INV-2026-0005")
    #expect(result.rule.raw["next"] == 6)
    #expect(result.rule.raw["period"] == "2026")
  }

  @Test("skips numbers in use whatever their case")
  func skipsCaseInsensitively() {
    let taken = Set(["inv-2026-0001", "INV-2026-0002"].map { $0.lowercased() })
    let result = Numbering.allocateNumber(rule(), "2026-06-01", taken: taken)
    #expect(result.number == "INV-2026-0003")
    #expect(result.rule.raw["next"] == 4)
  }

  @Test("previews without mutating")
  func previews() {
    let r = rule(next: 12)
    #expect(Numbering.previewNumber(r, "2026-02-01") == "INV-2026-0012")
    #expect(r.raw["next"] == 12)
  }

  @Test("knows the numbers a rule writes")
  func knowsItsNumbers() {
    let sku = (pattern: "SKU-{counter}", padding: 5.0)
    #expect(Numbering.writtenBy(pattern: sku.pattern, padding: sku.padding, "SKU-00004"))
    #expect(Numbering.writtenBy(pattern: sku.pattern, padding: sku.padding, " sku-123456 "))
    #expect(!Numbering.writtenBy(pattern: sku.pattern, padding: sku.padding, "SKU-04"))
    #expect(!Numbering.writtenBy(pattern: sku.pattern, padding: sku.padding, "GL-01"))
    #expect(!Numbering.writtenBy(pattern: sku.pattern, padding: sku.padding, "SKU-00004-B"))
    #expect(Numbering.writtenBy(pattern: "P.{yy}{month}-{counter}", padding: 3, "P.2610-007"))
    #expect(!Numbering.writtenBy(pattern: "P.{yy}{month}-{counter}", padding: 3, "PX2610-007"))
  }

  @Test("starts new companies with the web's rules")
  func defaultRules() {
    let rules = Numbering.defaultRules()
    #expect(Set(rules.keys) == Set(Numbering.kinds))
    #expect(rules.count == 17)
    #expect(
      rules["invoice"]?.raw == [
        "pattern": "INV-{year}-{counter}", "next": 1, "padding": 4, "reset": "never", "period": "",
      ])
    #expect(rules["employee"]?.padding == 3)
    #expect(rules["product"]?.pattern == "SKU-{counter}")
    #expect(rules["product"]?.padding == 5)
    #expect(rules["letter"]?.reset == "yearly")
  }

  // MARK: The web's answers

  static let patterns = WebFixtures["numberingPatterns"].strings

  @Test("formats every pattern, padding, counter and date as the web does")
  func formatParity() {
    let expected = WebFixtures["numberingFormat"].strings
    let paddings: [Double] = [0, 1, 3, 4, 5, 12, 20, -1, 2.7]
    let dates = ["2026-03-09", "2026-01-01", "", "2026", "2026-1-5", "1999-12-31-extra"]
    var got: [String] = []
    for pattern in Self.patterns {
      for padding in paddings {
        for date in dates.prefix(4) {
          got.append(
            Numbering.formatNumber(pattern: pattern, padding: padding, counter: 7, date: date, clientNumber: "C-01"))
        }
      }
    }
    for counter in [1, 7, 12, 123_456] {
      for date in dates {
        got.append(Numbering.formatNumber(pattern: "INV-{year}-{counter}", padding: 4, counter: counter, date: date))
      }
    }
    #expect(got.count == expected.count)
    for (i, (a, b)) in zip(got, expected).enumerated() { #expect(a == b, "case \(i)") }
  }

  @Test("recognises the numbers each pattern writes as the web does")
  func writtenByParity() {
    let expected = WebFixtures["numberingWrittenBy"].chars
    let texts = WebFixtures["numberingTexts"].strings
    var i = 0
    for pattern in Self.patterns {
      for padding in [1.0, 3, 4, 5] {
        for text in texts {
          let want = expected[i] == "1"
          #expect(
            Numbering.writtenBy(pattern: pattern, padding: padding, text) == want, "\(pattern) \(padding) \(text)")
          i += 1
        }
      }
    }
    #expect(i == expected.count)
  }

  @Test("reads stored counters, odd ones included, as the web does")
  func counterParity() {
    for item in WebFixtures["numberingCounter"].array ?? [] {
      let rule = NumberingRule(item[0] ?? .null)
      let date = item[1]?.string ?? ""
      #expect(Numbering.currentCounter(rule, date) == item[2]?.int, "\(item)")
      #expect(Numbering.periodKey(rule.reset, date) == item[3]?.string, "\(item)")
    }
  }

  @Test("allocates from local and reserved counters as the web does")
  func allocateParity() {
    let taken = Set(["INV-2026-0003", "inv-2026-0004", "INV-2026-0006", "X0001", "X0002"].map { $0.lowercased() })
    let cases = WebFixtures["numberingAllocate"].array ?? []
    #expect(cases.count == 20)
    for item in cases {
      let rule = NumberingRule(item[0] ?? .null)
      let date = item[1]?.string ?? ""
      let reserved = item[2].flatMap { value -> ReservedCounter? in
        guard let counter = value["counter"]?.int, let period = value["period"]?.string else { return nil }
        return ReservedCounter(counter: counter, period: period)
      }
      let result =
        reserved == nil
        ? Numbering.allocateNumber(rule, date, clientNumber: "C-9", taken: taken)
        : Numbering.allocateFrom(rule, date, clientNumber: "C-9", reserved: reserved) {
          taken.contains($0.lowercased())
        }
      #expect(result.number == item[3]?.string, "\(item)")
      #expect(result.rule.raw == item[4], "\(item)")
    }
  }

  @Test("previews as the web does")
  func previewParity() {
    let expected = WebFixtures["numberingPreview"].strings
    #expect(
      Numbering.previewNumber(NumberingRule(pattern: "INV-{year}-{counter}", next: 12), "2026-02-01") == expected[0])
    #expect(
      Numbering.previewNumber(NumberingRule(pattern: "{client}-{counter}", next: 2, padding: 3), "2026-02-01")
        == expected[1])
  }
}
