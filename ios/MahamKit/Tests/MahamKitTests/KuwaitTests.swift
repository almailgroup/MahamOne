import Foundation
import Testing

@testable import MahamKit

/// src/lib/kuwait.test.ts (with its addresses, from src/lib/geo.ts), then the
/// web's answers for many more IBANs, Civil IDs, phones, banks and dates
/// (WebFixtures), and src/lib/kuwait-rules.ts.
@Suite("Kuwait")
struct KuwaitTests {
  // MARK: kuwait.test.ts

  @Test("accepts a valid Kuwaiti IBAN with or without spaces")
  func validIban() {
    #expect(Kuwait.isValidIban("KW81CBKU0000000000001234560101"))
    #expect(Kuwait.isValidIban("kw81 cbku 0000 0000 0000 1234 5601 01"))
    #expect(Kuwait.formatIban("KW81CBKU0000000000001234560101") == "KW81 CBKU 0000 0000 0000 1234 5601 01")
  }

  @Test("rejects wrong check digits and lengths")
  func invalidIban() {
    #expect(!Kuwait.isValidIban("KW82CBKU0000000000001234560101"))
    #expect(!Kuwait.isValidIban("KW81CBKU000000000000123456010"))
    #expect(Kuwait.isValidIban("GB82WEST12345698765432"))
  }

  @Test("names the bank")
  func namesTheBank() {
    #expect(Kuwait.bankFromIban("KW12NBOK0000000000001000372151")?.name.en == "National Bank of Kuwait")
    #expect(Kuwait.bankFromIban("GB82WEST12345698765432") == nil)
  }

  @Test("checks the birth date and check digit of a Civil ID")
  func civilId() {
    let base = "28501011235"
    let weights = [2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2]
    let sum = zip(weights, base).reduce(0) { $0 + $1.0 * ($1.1.wholeNumberValue ?? 0) }
    let check = 11 - sum % 11
    #expect(check < 10)
    #expect(Kuwait.isValidCivilId(base + String(check)))
    #expect(!Kuwait.isValidCivilId(base + String((check + 1) % 10)))
    #expect(!Kuwait.isValidCivilId("28513011235" + String(check)))
    #expect(!Kuwait.isValidCivilId("1234"))
  }

  @Test("formats Kuwaiti phone numbers")
  func phones() {
    #expect(Kuwait.normalizeKuwaitPhone("+965 9988 7766") == "+965 9988 7766")
    #expect(Kuwait.normalizeKuwaitPhone("0096522445566") == "+965 2244 5566")
    #expect(Kuwait.normalizeKuwaitPhone("55667788") == "+965 5566 7788")
    #expect(Kuwait.normalizeKuwaitPhone("12345678") == nil)
  }

  @Test("knows areas in both languages")
  func areas() {
    #expect(Kuwait.findArea("salmiya")?.ar == "السالمية")
    #expect(Kuwait.placeName("السالمية", .en) == "Salmiya")
    #expect(Kuwait.placeName("Hawalli", .ar) == "حولي")
    #expect(Kuwait.placeName("Somewhere", .ar) == "Somewhere")
  }

  @Test("lists the public holidays of a year")
  func holidays2026() {
    let dates = Kuwait.kuwaitHolidays(2026).map(\.date)
    for date in ["2026-01-01", "2026-02-25", "2026-02-26", "2026-03-20", "2026-05-27"] {
      #expect(dates.contains(date), "\(date)")
    }
    #expect(dates.count == 13)
  }

  @Test("formats Hijri dates")
  func hijri() {
    #expect(Kuwait.formatHijri("2026-10-03", .en).contains("1448"))
    #expect(Kuwait.formatHijri("2026-10-03", .ar).contains("1448"))
  }

  static let address: JSONValue = [
    "line1": "Al Hamra Tower", "line2": "", "city": "Salmiya", "state": "Hawalli", "postalCode": "22001",
    "country": "KW", "block": "3", "street": "12", "avenue": "", "building": "15", "floor": "2", "unit": "5",
    "paci": "12345678",
  ]

  @Test("writes Kuwaiti addresses block first, in English")
  func addressEnglish() {
    #expect(
      Geo.formatAddressLines(Self.address, locale: "en-KW") == [
        "Block 3, Street 12, Building 15, Floor 2, Unit 5",
        "Al Hamra Tower",
        "Salmiya, Hawalli 22001",
        "PACI no. 12345678",
        "Kuwait",
      ])
  }

  @Test("and in Arabic")
  func addressArabic() {
    #expect(
      Geo.formatAddressLines(Self.address, locale: "ar-KW") == [
        "قطعة 3، شارع 12، مبنى 15، الدور 2، وحدة 5",
        "Al Hamra Tower",
        "السالمية، حولي 22001",
        "الرقم الآلي 12345678",
        "الكويت",
      ])
  }

  // MARK: The web's answers

  @Test("checks and formats IBANs as the web does")
  func ibanParity() {
    for item in WebFixtures["iban"].array ?? [] {
      let text = item[0]?.string ?? ""
      #expect(Kuwait.isValidIban(text) == item[1]?.bool, "\(text)")
      #expect(Kuwait.formatIban(text) == item[2]?.string, "\(text)")
      #expect(Kuwait.bankFromIban(text)?.code == item[3]?.string, "\(text)")
    }
  }

  @Test("checks Civil IDs as the web does")
  func civilIdParity() {
    let ids = WebFixtures["civilIds"].strings
    let expected = WebFixtures["civilId"].chars
    #expect(ids.count == expected.count)
    #expect(ids.count > 400)
    for (id, want) in zip(ids, expected) { #expect(Kuwait.isValidCivilId(id) == (want == "1"), "\(id)") }
    #expect(expected.contains("1"))
  }

  @Test("formats phones, checks cards and finds banks as the web does")
  func phoneCardBankParity() {
    for item in WebFixtures["phone"].array ?? [] {
      #expect(Kuwait.normalizeKuwaitPhone(item[0]?.string ?? "") == item[1]?.string, "\(item)")
    }
    for item in WebFixtures["card"].array ?? [] {
      #expect(Kuwait.isValidCardNumber(item[0]?.string ?? "") == item[1]?.bool, "\(item)")
    }
    for item in WebFixtures["bank"].array ?? [] {
      #expect(Kuwait.findBank(item[0]?.string ?? "")?.code == item[1]?.string, "\(item)")
    }
    for item in WebFixtures["place"].array ?? [] {
      let name = item[0]?.string ?? ""
      #expect(Kuwait.placeName(name, .en) == item[1]?.string, "\(name)")
      #expect(Kuwait.placeName(name, .ar) == item[2]?.string, "\(name)")
    }
  }

  @Test("lists the same public holidays as the web, 2020 to 2035")
  func holidayParity() {
    for year in 2020...2035 {
      let expected = WebFixtures["holidays"][String(year)]?.array ?? []
      let got = Kuwait.kuwaitHolidays(year)
      #expect(got.count == expected.count, "\(year)")
      for (holiday, want) in zip(got, expected) {
        #expect(holiday.date == want[0]?.string, "\(year)")
        #expect(holiday.name.en == want[1]?.string, "\(year) \(holiday.date)")
        #expect(holiday.name.ar == want[2]?.string, "\(year) \(holiday.date)")
      }
    }
  }

  @Test("writes Hijri dates as the web does")
  func hijriParity() {
    let cases = WebFixtures["hijri"].array ?? []
    #expect(cases.count > 100)
    for item in cases {
      let date = item[0]?.string ?? ""
      #expect(Kuwait.formatHijri(date, .en) == item[1]?.string, "\(date)")
      #expect(Kuwait.formatHijri(date, .ar) == item[2]?.string, "\(date)")
    }
  }

  // MARK: kuwait-rules.ts

  @Test("fills a Kuwait profile with defaults, keeping what is set")
  func profile() {
    for item in WebFixtures["kuwaitProfile"].array ?? [] {
      #expect(KuwaitRules.kuwaitProfile(item[0]) == item[1], "\(item[0] ?? .null)")
    }
  }

  @Test("knows the cash limits and the shareholding companies")
  func cash() {
    for item in WebFixtures["cashLimit"].array ?? [] {
      #expect(KuwaitRules.cashLimit(item[0]?.string) == item[1]?.double, "\(item)")
    }
    #expect(KuwaitRules.isShareholding("kscc"))
    #expect(KuwaitRules.isShareholding("ksc_listed"))
    #expect(!KuwaitRules.isShareholding("wll"))
    #expect(KuwaitRules.legalForms.count == 10)
    #expect(Set(KuwaitRules.cashRules.keys) == Set(KuwaitRules.activities))
  }
}
