import Foundation
import Testing

@testable import MahamKit

/// src/db/defaults.ts, src/lib/regions.ts and src/lib/geo.ts have no tests
/// of their own: these check the records, defaults and addresses against
/// the web's, made by running its TypeScript (WebFixtures).
@Suite("Defaults")
struct DefaultsTests {
  /// The record with what changes between runs set to fixed values, as the generator does.
  func fixed(_ record: JSONValue) -> String {
    var copy = record
    copy.set("id", "ID")
    copy.set("createdAt", "STAMP")
    copy.set("updatedAt", "STAMP")
    for key in ["issueDate", "startDate", "nextIssueDate"] where record[key] != nil { copy.set(key, "TODAY") }
    return webHash(copy)
  }

  @Test("new records are shaped exactly as the web makes them")
  func records() {
    let expected = WebFixtures["defaults"]
    let cases: [(String, JSONValue)] = [
      ("company", Defaults.createCompany()),
      ("companyUS", Defaults.createCompany(["locale": "en-US", "language": "en", "name": "Acme"])),
      ("companyAr", Defaults.createCompany(["locale": "ar-KW", "language": "ar"])),
      ("companyNull", Defaults.createCompany(["locale": .null, "language": .null])),
      ("companyCA", Defaults.createCompany(["locale": "fr-CA"])),
      ("client", Defaults.createClient(companyId: "co-1")),
      ("clientOver", Defaults.createClient(companyId: "co-1", ["name": "Gulf Pearl", "currency": "USD", "extra": 1])),
      ("product", Defaults.createProduct(companyId: "co-1")),
      ("taxRate", Defaults.createTaxRate(companyId: "co-1", ["name": "VAT", "rate": 5])),
      ("invoice", Defaults.createDocument(companyId: "co-1", type: "invoice")),
      ("bill", Defaults.createDocument(companyId: "co-1", type: "bill", ["currency": "USD"])),
      ("recurring", Defaults.createRecurring(companyId: "co-1")),
    ]
    for (name, record) in cases {
      #expect(fixed(record) == expected[name]?.string, "\(name)")
    }
    #expect(webHash(Defaults.defaultEmailTemplatesAr()) == expected["emailAr"]?.string)
    for item in expected["notes"]?.array ?? [] {
      let notes = Defaults.defaultNotes(item[0]?.string ?? "")
      #expect(notes.invoiceNotes == item[1]?["invoiceNotes"]?.string)
      #expect(notes.quoteNotes == item[1]?["quoteNotes"]?.string)
    }
  }

  @Test("new records get a new id and the same stamp for both times")
  func stamps() {
    let now = Date(timeIntervalSince1970: 1_764_067_440.123)
    let a = Defaults.createClient(companyId: "co-1", now: now)
    let b = Defaults.createClient(companyId: "co-1", now: now)
    #expect(a["id"] != b["id"])
    #expect(a["createdAt"] == "2025-11-25T10:44:00.123Z")
    #expect(a["updatedAt"] == a["createdAt"])
    #expect(Defaults.createClient(companyId: "co-1", ["id": "mine"])["id"] == "mine")
    #expect(Defaults.createCompany()["numbering"] == Defaults.defaultNumbering())
  }

  @Test("times are written as JavaScript's toISOString")
  func isoStrings() {
    for item in WebFixtures["stamps"].array ?? [] {
      // new Date(ms) keeps whole milliseconds.
      let ms = (item[0]?.double ?? 0).rounded(.towardZero)
      #expect(Defaults.isoString(milliseconds: Int64(ms)) == item[1]?.string, "\(ms)")
      // A Date holds its time to the microsecond only until about 2100.
      if abs(ms) < 4e12 {
        #expect(Defaults.nowStamp(Date(timeIntervalSince1970: ms / 1000)) == item[1]?.string, "\(ms)")
      }
    }
  }

  @Test("today is the local calendar date")
  func today() throws {
    let kuwait = try #require(TimeZone(identifier: "Asia/Kuwait"))
    let honolulu = try #require(TimeZone(identifier: "Pacific/Honolulu"))
    let evening = Date(timeIntervalSince1970: 1_764_108_000)  // 2025-11-25T22:00:00Z
    #expect(Defaults.today(evening, in: kuwait) == "2025-11-26")
    #expect(Defaults.today(evening, in: .gmt) == "2025-11-25")
    #expect(Defaults.today(Date(timeIntervalSince1970: 1_764_028_800), in: honolulu) == "2025-11-24")
    let doc = Defaults.createDocument(companyId: "c", type: "quote", now: evening, zone: kuwait)
    #expect(doc["issueDate"] == "2025-11-26")
  }

  @Test("each country starts with the web's settings")
  func regions() {
    for item in WebFixtures["regions"].array ?? [] {
      let got = Regions.regionDefaults(item[0]?.string ?? "")
      let want = item[1]
      #expect(got.currency == want?["currency"]?.string)
      #expect(got.locale == want?["locale"]?.string)
      #expect(got.dateFormat == want?["dateFormat"]?.string)
      #expect(got.pageSize == want?["pageSize"]?.string)
      #expect(got.language == want?["language"]?.string)
      #expect(got.taxIdLabel == want?["taxIdLabel"]?.string)
      #expect(got.tax?.name == want?["tax"]?["name"]?.string)
      #expect(got.tax?.rate == want?["tax"]?["rate"]?.double)
    }
  }

  @Test("addresses are written as the web writes them")
  func addresses() {
    for item in WebFixtures["addresses"].array ?? [] {
      let address = item[0]
      let label = address?["line1"]?.string ?? ""
      #expect(
        JSONValue.array(Geo.formatAddressLines(address, locale: "en", includeCountry: false).map(JSONValue.string))
          == item[1], "\(label)")
      #expect(
        JSONValue.array(Geo.formatAddressLines(address, locale: "ar-KW", includeCountry: false).map(JSONValue.string))
          == item[2], "\(label)")
      if let english = item[3], !english.isNull {
        #expect(
          JSONValue.array(Geo.formatAddressLines(address, locale: "en").map(JSONValue.string)) == english, "\(label)")
      }
      if let arabic = item[4], !arabic.isNull {
        #expect(
          JSONValue.array(Geo.formatAddressLines(address, locale: "ar").map(JSONValue.string)) == arabic, "\(label)")
      }
      #expect(Geo.isAddressEmpty(address) == item[5]?.bool, "\(label)")
    }
    #expect(Geo.formatAddressLines(nil) == [])
    #expect(
      Geo.emptyAddress("KW") == ["line1": "", "line2": "", "city": "", "state": "", "postalCode": "", "country": "KW"])
  }

  @Test("countries and currencies are named from the platform's data")
  func names() {
    #expect(Geo.countryName("KW") == "Kuwait")
    #expect(Geo.countryName("kw", locale: "ar") == "الكويت")
    #expect(Geo.countryName("") == "")
    #expect(Geo.countryName("KWT") == "KWT")
    #expect(Geo.currencyName("KWD") == "Kuwaiti Dinar")
    #expect(Geo.currencyName("dinar") == "dinar")
    #expect(Geo.countryCodes.count == 250)
    let currencies = Geo.currencyOptions().map(\.value)
    #expect(Array(currencies.prefix(Geo.commonCurrencies.count)) == Geo.commonCurrencies)
    #expect(currencies.count == 162)
    #expect(Geo.countryOptions().count == 250)
  }
}
