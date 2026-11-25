import Foundation
import Testing

@testable import MahamKit

// The web's src/lib/format.test.ts, case for case.

/// Intl separates symbols with non-breaking spaces; normalise for readability.
private func plain(_ text: String) -> String {
  text.replacingOccurrences(of: "\u{A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
}

private let arabic: FormatLocale = "ar-KW-u-nu-latn"

@Suite("format.test: money helpers")
struct FormatMoneyHelperTests {
  @Test("rounds half away from zero")
  func rounds() {
    #expect(Money.round(1.005, 2) == Decimal(string: "1.01"))
    #expect(Money.round(-1.005, 2) == Decimal(string: "-1.01"))
    #expect(Money.round(2.5, 0) == 3)
    #expect(Money.round(-0.001, 2) == 0)
    #expect(!Money.round(-0.001, 2).isSignMinus)
  }

  @Test("knows currency precision")
  func precision() {
    #expect(Money.precision("USD") == 2)
    #expect(Money.precision("JPY") == 0)
    #expect(Money.precision("KWD") == 3)
  }

  @Test("parses user input")
  func parses() {
    #expect(Money.parseAmount("1,234.50") == 1234.5)
    #expect(Money.parseAmount("12.5%") == 12.5)
    #expect(Money.parseAmount("abc") == 0)
    #expect(Money.parseAmount("") == 0)
  }
}

@Suite("format.test: formatting")
struct FormattingTests {
  @Test("formats money in the currency precision")
  func money() {
    #expect(Format.money(1234.5, currency: "USD", locale: "en-US") == "$1,234.50")
    #expect(Format.money(1234, currency: "JPY", locale: "en-US") == "¥1,234")
    #expect(plain(Format.money(1.5, currency: "KWD", locale: "en-US")) == "KWD 1.500")
    #expect(plain(Format.money(1234.5, currency: "EUR", locale: "de-DE")) == "1.234,50 €")
  }

  @Test("keeps extra decimals for unit prices")
  func unitPrices() {
    #expect(Format.unitPrice(0.537, currency: "USD", locale: "en-US") == "$0.537")
    #expect(Format.unitPrice(12, currency: "USD", locale: "en-US") == "$12.00")
  }

  @Test("formats quantities and percentages")
  func quantities() {
    #expect(Format.quantity(1500, locale: "en-US") == "1,500")
    #expect(Format.quantity(2.25, locale: "en-US") == "2.25")
    #expect(Format.percent(7.5, locale: "en-US") == "7.5%")
  }

  @Test("formats dates")
  func dates() {
    #expect(Format.date("2026-12-31", format: "dd/MM/yyyy", locale: "en-US") == "31/12/2026")
    #expect(Format.date("2026-12-31", format: "d MMM yyyy", locale: "en-US") == "31 Dec 2026")
    #expect(Format.date("2026-12-31", format: .locale, locale: "en-US") == "Dec 31, 2026")
    #expect(Format.date("2026-12-31", format: .locale, locale: "en-GB") == "31 Dec 2026")
    #expect(Format.date(nil, format: .locale, locale: "en-US") == "")
    #expect(Format.date("not a date", format: .locale, locale: "en-US") == "")
  }
}

@Suite("format.test: dates")
struct FormatDatesTests {
  @Test("validates ISO dates")
  func validates() {
    #expect(ISODates.isISODate("2026-02-28"))
    #expect(!ISODates.isISODate("2026-02-30"))
    #expect(!ISODates.isISODate("2026-2-3"))
  }

  @Test("adds days and measures gaps")
  func addsDays() {
    #expect(ISODates.addDays("2026-12-30", 3) == "2027-01-02")
    #expect(ISODates.daysBetween("2026-01-01", "2026-01-31") == 30)
  }

  @Test("computes schedule occurrences without month-end drift")
  func occurrences() {
    #expect(ISODates.occurrenceDate("2026-01-31", .monthly, 1) == "2026-02-28")
    #expect(ISODates.occurrenceDate("2026-01-31", .monthly, 2) == "2026-03-31")
    #expect(ISODates.occurrenceDate("2026-01-15", .quarterly, 3) == "2026-10-15")
    #expect(ISODates.occurrenceDate("2026-01-01", .biweekly, 2) == "2026-01-29")
    #expect(ISODates.occurrenceDate("2024-02-29", .yearly, 1) == "2025-02-28")
  }
}

@Suite("format.test: Kuwaiti dinars")
struct KuwaitiDinarTests {
  @Test("always show three decimals (fils)")
  func fils() {
    #expect(Format.money(1234.5, currency: "KWD", locale: "en-KW") == "KWD\u{A0}1,234.500")
    #expect(Format.money(0.005, currency: "KWD", locale: "en-KW") == "KWD\u{A0}0.005")
  }

  @Test("can be written the Kuwaiti way")
  func local() {
    #expect(Format.money(1234.5, currency: "KWD", locale: "en-KW", display: .local) == "KD\u{A0}1,234.500")
    #expect(Format.money(1234.5, currency: "KWD", locale: arabic, display: .local).contains("1,234.500\u{A0}د.ك"))
    #expect(!Format.money(1234.5, currency: "KWD", locale: arabic, display: .local).contains("د.ك."))
    #expect(Format.money(10, currency: "USD", locale: "en-KW", display: .local) == "$10.00")
    #expect(Format.currencySymbol("KWD", locale: "en-KW", display: .local) == "KD")
  }
}

@Suite("format.test: Arabic")
struct FormatArabicTests {
  @Test("writes foreign currencies by code in Arabic")
  func foreignByCode() {
    #expect(Format.money(1234.5, currency: "USD", locale: arabic, display: .local).contains("1,234.50\u{A0}USD"))
    #expect(Format.money(1234.5, currency: "KWD", locale: arabic, display: .code).contains("1,234.500\u{A0}KWD"))
  }

  @Test("writes month names in Arabic")
  func monthNames() {
    #expect(Format.date("2026-10-03", format: "d MMM yyyy", locale: arabic) == "3 أكتوبر 2026")
    #expect(Format.date("2026-10-03", format: "dd/MM/yyyy", locale: arabic) == "03/10/2026")
  }
}

@Suite("format.test: amounts on screen")
struct AmountsOnScreenTests {
  let rli = "\u{2067}"
  let lri = "\u{2066}"
  let pdi = "\u{2069}"

  @Test("keep the minus sign with the figure and the currency after it in Arabic")
  func arabicAmounts() {
    #expect(
      Format.isolateAmount(Format.money(-12.5, currency: "KWD", locale: arabic, display: .local), locale: arabic)
        == "\(rli)\(lri)-12.500\(pdi)\u{A0}د.ك\(pdi)")
    #expect(
      Format.isolateAmount(Format.money(1234.5, currency: "KWD", locale: arabic, display: .local), locale: arabic)
        == "\(rli)\(lri)1,234.500\(pdi)\u{A0}د.ك\(pdi)")
    #expect(
      Format.isolateAmount(Format.money(-5.83, currency: "USD", locale: arabic, display: .code), locale: arabic)
        == "\(rli)\(lri)-5.83\(pdi)\u{A0}USD\(pdi)")
  }

  @Test("leave English amounts as they are")
  func english() {
    let text = Format.money(-12.5, currency: "KWD", locale: "en-KW", display: .local)
    #expect(Format.isolateAmount(text, locale: "en-KW") == text)
  }
}

@Suite("format.test: date-times")
struct FormatDateTimeTests {
  @Test("writes Arabic date-times with the app’s date format")
  func arabicDateTimes() throws {
    // new Date(2026, 9, 3, 23, 54): 11:54 PM on 3 October in the device's zone.
    let zone = try #require(TimeZone(identifier: "Asia/Kuwait"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let moment = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 23, minute: 54)))
    #expect(Format.dateTime(moment, locale: arabic, dateFormat: "dd/MM/yyyy", zone: zone) == "03/10/2026، 11:54 م")
    #expect(Format.dateTime(moment, locale: "en-US", dateFormat: "dd/MM/yyyy", zone: zone) == "Oct 3, 2026, 11:54 PM")
  }
}

@Suite("useFormat")
struct CompanyFormatTests {
  @Test("amounts the company's way, in the interface language, isolated for the screen")
  func company() {
    let english = CompanyFormat(language: .en, companyLocale: "en-KW", currency: "KWD", dateFormat: "dd/MM/yyyy")
    #expect(english.money(1234.5) == "KD\u{A0}1,234.500")
    #expect(english.moneyText(10, currency: "USD") == "$10.00")
    #expect(english.date("2026-10-03") == "03/10/2026")
    #expect(english.percent(5) == "5%")
    let arabicFormat = CompanyFormat(language: .ar, companyLocale: "en-KW", currency: "KWD", dateFormat: "d MMM yyyy")
    #expect(arabicFormat.money(-12.5) == "\u{2067}\u{2066}-12.500\u{2069}\u{A0}د.ك\u{2069}")
    #expect(arabicFormat.moneyText(-5.83, currency: "USD") == "\u{2067}\u{2066}-5.83\u{2069}\u{A0}USD\u{2069}")
    #expect(arabicFormat.date("2026-10-03") == "3 أكتوبر 2026")
    let international = CompanyFormat(
      language: .en, companyLocale: nil, currency: "KWD", currencyDisplay: .code, dateFormat: .locale)
    #expect(international.money(1.5) == "KWD\u{A0}1.500")
    #expect(international.date("2026-12-31") == "Dec 31, 2026")
  }
}
