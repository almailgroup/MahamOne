import Foundation
import Testing

@testable import MahamKit

// The web's src/lib/words.test.ts, case for case.

@Suite("words.test: English")
struct EnglishWordsTests {
  @Test("writes numbers")
  func numbers() {
    #expect(Words.englishNumber(0) == "Zero")
    #expect(Words.englishNumber(15) == "Fifteen")
    #expect(Words.englishNumber(40) == "Forty")
    #expect(Words.englishNumber(1234) == "One Thousand Two Hundred Thirty-Four")
    #expect(Words.englishNumber(2_000_015) == "Two Million Fifteen")
  }

  @Test("writes Kuwaiti dinars and fils")
  func dinars() {
    #expect(
      Words.amountInWords(1234.5, currency: "KWD", language: .en)
        == "One Thousand Two Hundred Thirty-Four Kuwaiti Dinars and Five Hundred Fils Only")
    #expect(Words.amountInWords(1, currency: "KWD", language: .en) == "One Kuwaiti Dinar Only")
    #expect(Words.amountInWords(0.075, currency: "KWD", language: .en) == "Seventy-Five Fils Only")
    #expect(Words.amountInWords(0, currency: "KWD", language: .en) == "Zero Kuwaiti Dinars Only")
    #expect(Words.amountInWords(12.01, currency: "USD", language: .en) == "Twelve US Dollars and One Cent Only")
  }
}

@Suite("words.test: Arabic")
struct ArabicWordsTests {
  @Test("writes numbers with the right gender")
  func numbers() {
    #expect(Words.arabicNumber(3) == "ثلاثة")
    #expect(Words.arabicNumber(3, gender: .feminine) == "ثلاث")
    #expect(Words.arabicNumber(11) == "أحد عشر")
    #expect(Words.arabicNumber(11, gender: .feminine) == "إحدى عشرة")
    #expect(Words.arabicNumber(21) == "واحد وعشرون")
    #expect(Words.arabicNumber(1234) == "ألف ومائتان وأربعة وثلاثون")
    #expect(Words.arabicNumber(3000) == "ثلاثة آلاف")
    #expect(Words.arabicNumber(11000) == "أحد عشر ألفًا")
    #expect(Words.arabicNumber(200_000) == "مائتا ألف")
    #expect(Words.arabicNumber(2_500_000) == "مليونان وخمسمائة ألف")
  }

  @Test("writes Kuwaiti dinars and fils")
  func dinars() {
    #expect(
      Words.amountInWords(1234.5, currency: "KWD", language: .ar)
        == "فقط ألف ومائتان وأربعة وثلاثون دينارًا كويتيًا وخمسمائة فلس لا غير")
    #expect(Words.amountInWords(1, currency: "KWD", language: .ar) == "فقط دينار كويتي واحد لا غير")
    #expect(Words.amountInWords(2, currency: "KWD", language: .ar) == "فقط ديناران كويتيان لا غير")
    #expect(Words.amountInWords(5, currency: "KWD", language: .ar) == "فقط خمسة دنانير كويتية لا غير")
    #expect(Words.amountInWords(100, currency: "KWD", language: .ar) == "فقط مائة دينار كويتي لا غير")
    #expect(Words.amountInWords(200, currency: "KWD", language: .ar) == "فقط مائتا دينار كويتي لا غير")
    #expect(Words.amountInWords(2000, currency: "KWD", language: .ar) == "فقط ألفا دينار كويتي لا غير")
    #expect(Words.amountInWords(0.25, currency: "KWD", language: .ar) == "فقط مائتان وخمسون فلسًا لا غير")
    #expect(
      Words.amountInWords(7.003, currency: "KWD", language: .ar) == "فقط سبعة دنانير كويتية وثلاثة فلوس لا غير")
    #expect(
      Words.amountInWords(13.5, currency: "SAR", language: .ar) == "فقط ثلاثة عشر ريالًا سعوديًا وخمسون هللة لا غير")
  }

  @Test("falls back to English for currencies without Arabic names")
  func fallsBack() {
    #expect(Words.amountInWords(3, currency: "JPY", language: .ar) == "Three JPY Only")
  }
}

@Suite("words.test: amounts")
struct SplitAmountTests {
  @Test("splits amounts by the currency decimals")
  func splits() {
    let dinars = Words.splitAmount(12.345, currency: "KWD")
    #expect(dinars.major == 12 && dinars.minor == 345)
    let dollars = Words.splitAmount(-12.5, currency: "USD")
    #expect(dollars.major == 12 && dollars.minor == 50)
  }
}
