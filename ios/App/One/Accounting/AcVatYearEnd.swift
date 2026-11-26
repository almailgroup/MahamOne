import Foundation
import MahamKit

// VAT returns worked out from the ledger (`src/lib/accounting/vat.ts`) and the
// Kuwaiti year-end close (`src/lib/accounting/year-end.ts`).

// MARK: VAT

/// `vatSettings(company)`, with defaults from the country and tax number.
struct AcVatSettings: Sendable {
  let registered: Bool
  /// "uk", "ae" or "generic".
  let format: String
  /// "monthly" or "quarterly".
  let frequency: String
  let startMonth: Int
  let emirate: String?

  init(company: JSONValue?, settings: AcSettings) {
    if let saved = settings.vat {
      registered = saved.flag("registered")
      format = saved.text("format") ?? "generic"
      frequency = saved.text("frequency") ?? "quarterly"
      startMonth = Int(saved.number("startMonth") ?? 1)
      emirate = saved.text("emirate")
      return
    }
    let country = settings.country.uppercased()
    // Kuwait has no VAT: a tax card or CR number doesn't make a company VAT-registered.
    let taxId = company?.str("taxId").trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    registered = country != "KW" && !taxId.isEmpty
    format = country == "GB" || country == "IM" ? "uk" : country == "AE" ? "ae" : "generic"
    frequency = "quarterly"
    startMonth = 1
    emirate = country == "AE" ? AcVat.emirateFromAddress(company?.obj("address")) ?? "DU" : nil
  }
}

/// A box of a return (`VatBox`), minor units.
struct AcVatBox: Sendable {
  let id: String
  let label: String
  let amount: Int
  var vat: Int?
  var total = false
  var whole = false
}

struct AcVatReturn: Sendable {
  let format: String
  let period: AcRange
  let boxes: [AcVatBox]
  /// Positive: to pay; negative: to reclaim.
  let net: Int
  /// Sale and purchase lines that had no tax rate.
  let untaxed: [AcLine]
}

enum AcVat {
  static let emirates: [(code: String, supplies: String, match: String)] = [
    ("AZ", "Standard rated supplies in Abu Dhabi", "abu\\s*dhabi|al\\s*ain"),
    ("DU", "Standard rated supplies in Dubai", "dubai"),
    ("SH", "Standard rated supplies in Sharjah", "sharjah"),
    ("AJ", "Standard rated supplies in Ajman", "ajman"),
    ("UQ", "Standard rated supplies in Umm Al Quwain", "umm\\s*al\\s*quwain"),
    ("RK", "Standard rated supplies in Ras Al Khaimah", "ras\\s*al\\s*khaimah"),
    ("FU", "Standard rated supplies in Fujairah", "fujairah"),
  ]

  static func emirateFromAddress(_ address: JSONValue?) -> String? {
    let text = (address?.str("state") ?? "") + " " + (address?.str("city") ?? "")
    return emirates.first { text.range(of: $0.match, options: [.regularExpression, .caseInsensitive]) != nil }?.code
  }

  /// `vatPeriodOf`: the return period a date falls in.
  static func periodOf(_ date: String, _ settings: AcVatSettings) -> AcRange {
    guard let d = AcDate.parts(date) else { return AcRange(from: date, to: date) }
    let monthly = settings.frequency == "monthly"
    let length = monthly ? 1 : 3
    let offset = monthly ? 0 : (((settings.startMonth - 1) % 3) + 3) % 3
    let index = d.y * 12 + (d.m - 1) - offset
    let startIndex = index - (((index % length) + length) % length) + offset
    let year = Int((Double(startIndex) / 12).rounded(.down))
    let month = startIndex - year * 12
    let start = AcDate.make(year, month, 1)
    let end = AcDate.make(year, month + length, 0)
    return AcRange(from: start, to: end)
  }

  /// `vatPeriods`: from the period containing `from` to the one containing `to`.
  static func periods(_ settings: AcVatSettings, _ from: String, _ to: String) -> [AcRange] {
    var periods: [AcRange] = []
    var period = periodOf(from, settings)
    while period.from <= to, periods.count < 600 {
      periods.append(period)
      period = periodOf(AcDate.addDays(period.to, 1), settings)
    }
    return periods
  }

  /// `vatDueDate`: the filing (and payment) deadline.
  static func dueDate(_ period: AcRange, _ format: String) -> String {
    if format == "ae" { return AcDate.addDays(period.to, 28) }
    guard let end = AcDate.parts(period.to) else { return period.to }
    let nextMonthEnd = AcDate.make(end.y, end.m - 1 + 2, 0)
    return format == "uk" ? AcDate.addDays(nextMonthEnd, 7) : nextMonthEnd
  }

  /// `vatLines`: lines of the period that count, the closing entry left out.
  static func lines(_ all: [AcLine], _ period: AcRange) -> [AcLine] {
    all.filter { $0.date >= period.from && $0.date <= period.to && !$0.settlement }
  }

  typealias Pick = (AcLine) -> Int

  /// `boxPickers`: what each box adds up, per line.
  static func pickers(_ format: String, roles: [String: String]) -> [String: (pick: Pick, vat: Pick?)] {
    let outputTax = roles["output_tax"]
    let inputTax = roles["input_tax"]
    let output: Pick = { $0.accountId == outputTax ? -$0.amount : 0 }
    let input: Pick = { $0.accountId == inputTax ? $0.amount : 0 }
    func base(_ flow: String, _ kinds: [String]) -> Pick {
      { line in
        guard let vat = line.vat, vat.part == "base", vat.flow == flow, kinds.contains(vat.kind) else { return 0 }
        return flow == "sale" ? -line.amount : line.amount
      }
    }
    func tax(_ account: @escaping Pick, _ kinds: [String]?) -> Pick {
      { line in
        if let kinds {
          guard let vat = line.vat, kinds.contains(vat.kind) else { return 0 }
        }
        return account(line)
      }
    }
    let reported = ["standard", "reduced", "zero", "exempt", "none"]
    if format == "uk" {
      let sales = base("sale", reported + ["reverse_charge"])
      let bought = base("purchase", ["reverse_charge"])
      return [
        "1": (output, nil),
        "4": (input, nil),
        "6": ({ sales($0) + bought($0) }, nil),
        "7": (base("purchase", reported + ["reverse_charge"]), nil),
      ]
    }
    if format == "ae" {
      let standard = ["standard", "reduced"]
      let taggedOutput = tax(output, standard)
      let taggedInput = tax(input, standard)
      let standardOutput: Pick = { line in
        line.vat != nil ? taggedOutput(line) : (line.accountId == outputTax ? -line.amount : 0)
      }
      let standardInput: Pick = { line in
        line.vat != nil ? taggedInput(line) : (line.accountId == inputTax ? line.amount : 0)
      }
      return [
        "1": (base("sale", standard), standardOutput),
        "3": (base("purchase", ["reverse_charge"]), tax(output, ["reverse_charge"])),
        "4": (base("sale", ["zero", "none"]), nil),
        "5": (base("sale", ["exempt"]), nil),
        "9": (base("purchase", standard), standardInput),
        "10": (base("purchase", ["reverse_charge"]), tax(input, ["reverse_charge"])),
      ]
    }
    func notReverse(_ account: @escaping Pick) -> Pick {
      { $0.vat?.kind == "reverse_charge" ? 0 : account($0) }
    }
    return [
      "sales-taxed": (base("sale", ["standard", "reduced"]), notReverse(output)),
      "sales-zero": (base("sale", ["zero"]), nil),
      "sales-exempt": (base("sale", ["exempt"]), nil),
      "sales-none": (base("sale", ["none"]), nil),
      "purchases-taxed": (base("purchase", ["standard", "reduced"]), notReverse(input)),
      "purchases-other": (base("purchase", ["zero", "exempt", "none"]), nil),
      "reverse": (base("purchase", ["reverse_charge"]), tax(input, ["reverse_charge"])),
    ]
  }

  private static func whole(_ minor: Int, _ precision: Int) -> Int {
    var unit = 1
    for _ in 0..<max(0, precision) { unit *= 10 }
    return (minor / unit) * unit
  }

  /// `vatReturn`.
  static func compute(_ all: [AcLine], _ period: AcRange, _ format: String, roles: [String: String], precision: Int,
    emirate: String?) -> AcVatReturn
  {
    let lines = AcVat.lines(all, period)
    let pickers = AcVat.pickers(format, roles: roles)
    func amount(_ id: String) -> Int {
      guard let pick = pickers[id]?.pick else { return 0 }
      return lines.reduce(0) { $0 + pick($1) }
    }
    func vat(_ id: String) -> Int {
      guard let pick = pickers[id]?.vat else { return 0 }
      return lines.reduce(0) { $0 + pick($1) }
    }
    let untaxed = lines.filter { $0.vat?.part == "base" && $0.vat?.kind == "none" }
    var boxes: [AcVatBox] = []
    var net = 0
    if format == "uk" {
      let box1 = amount("1")
      let box4 = amount("4")
      net = box1 - box4
      boxes = [
        AcVatBox(id: "1", label: "VAT due on sales and other outputs", amount: box1),
        AcVatBox(
          id: "2", label: "VAT due on acquisitions of goods made in Northern Ireland from EU member states", amount: 0),
        AcVatBox(id: "3", label: "Total VAT due (box 1 + box 2)", amount: box1, total: true),
        AcVatBox(
          id: "4",
          label:
            "VAT reclaimed on purchases and other inputs (including acquisitions in Northern Ireland from EU member states)",
          amount: box4),
        AcVatBox(
          id: "5", label: "Net VAT to pay to HMRC or reclaim (difference between box 3 and box 4)", amount: abs(net),
          total: true),
        AcVatBox(
          id: "6", label: "Total value of sales and all other outputs excluding any VAT",
          amount: whole(amount("6"), precision), whole: true),
        AcVatBox(
          id: "7", label: "Total value of purchases and all other inputs excluding any VAT",
          amount: whole(amount("7"), precision), whole: true),
        AcVatBox(
          id: "8",
          label:
            "Total value of dispatches of goods and related costs (excluding VAT) from Northern Ireland to EU member states",
          amount: 0, whole: true),
        AcVatBox(
          id: "9",
          label:
            "Total value of acquisitions of goods and related costs (excluding VAT) made in Northern Ireland from EU member states",
          amount: 0, whole: true),
      ]
    } else if format == "ae" {
      let home = emirate ?? "DU"
      var outputs: [AcVatBox] = []
      for (index, item) in emirates.enumerated() {
        let letter = String(Array("abcdefg")[index])
        let isHome = item.code == home
        outputs.append(
          AcVatBox(id: "1" + letter, label: item.supplies, amount: isHome ? amount("1") : 0, vat: isHome ? vat("1") : 0))
      }
      outputs.append(
        AcVatBox(
          id: "2", label: "Tax refunds provided to tourists under the tax refunds for tourists scheme", amount: 0,
          vat: 0))
      outputs.append(
        AcVatBox(id: "3", label: "Supplies subject to the reverse charge provisions", amount: amount("3"), vat: vat("3")))
      outputs.append(AcVatBox(id: "4", label: "Zero rated supplies", amount: amount("4")))
      outputs.append(AcVatBox(id: "5", label: "Exempt supplies", amount: amount("5")))
      outputs.append(AcVatBox(id: "6", label: "Goods imported into the UAE", amount: 0, vat: 0))
      outputs.append(AcVatBox(id: "7", label: "Adjustments to goods imported into the UAE", amount: 0, vat: 0))
      let box8 = (outputs.reduce(0) { $0 + $1.amount }, outputs.reduce(0) { $0 + ($1.vat ?? 0) })
      let inputs = [
        AcVatBox(id: "9", label: "Standard rated expenses", amount: amount("9"), vat: vat("9")),
        AcVatBox(
          id: "10", label: "Supplies subject to the reverse charge provisions", amount: amount("10"), vat: vat("10")),
      ]
      let box11 = (inputs.reduce(0) { $0 + $1.amount }, inputs.reduce(0) { $0 + ($1.vat ?? 0) })
      net = box8.1 - box11.1
      boxes = outputs
      boxes.append(AcVatBox(id: "8", label: "Totals", amount: box8.0, vat: box8.1, total: true))
      boxes += inputs
      boxes.append(AcVatBox(id: "11", label: "Totals", amount: box11.0, vat: box11.1, total: true))
      boxes.append(AcVatBox(id: "12", label: "Total value of due tax for the period", amount: box8.1, total: true))
      boxes.append(
        AcVatBox(id: "13", label: "Total value of recoverable tax for the period", amount: box11.1, total: true))
      boxes.append(AcVatBox(id: "14", label: "Payable tax for the period", amount: net, total: true))
    } else {
      let outputTax = roles["output_tax"]
      let inputTax = roles["input_tax"]
      let output = lines.reduce(0) { $0 + ($1.accountId == outputTax ? -$1.amount : 0) }
      let input = lines.reduce(0) { $0 + ($1.accountId == inputTax ? $1.amount : 0) }
      net = output - input
      boxes = [
        AcVatBox(id: "sales-taxed", label: "Taxable sales", amount: amount("sales-taxed"), vat: vat("sales-taxed")),
        AcVatBox(id: "sales-zero", label: "Zero-rated sales", amount: amount("sales-zero")),
        AcVatBox(id: "sales-exempt", label: "Exempt sales", amount: amount("sales-exempt")),
        AcVatBox(id: "sales-none", label: "Sales without a tax rate", amount: amount("sales-none")),
        AcVatBox(
          id: "purchases-taxed", label: "Taxable purchases", amount: amount("purchases-taxed"),
          vat: vat("purchases-taxed")),
        AcVatBox(id: "purchases-other", label: "Purchases without tax", amount: amount("purchases-other")),
        AcVatBox(
          id: "reverse", label: "Purchases under reverse charge (tax due and reclaimed)", amount: amount("reverse"),
          vat: vat("reverse")),
        AcVatBox(id: "output", label: "Tax on sales (output tax)", amount: output, total: true),
        AcVatBox(id: "input", label: "Tax on purchases (input tax)", amount: input, total: true),
        AcVatBox(id: "net", label: "Net tax to pay", amount: net, total: true),
      ]
    }
    return AcVatReturn(format: format, period: period, boxes: boxes, net: net, untaxed: untaxed)
  }

  /// `vatBoxLines`: the ledger lines behind one box, for drill-down.
  static func boxLines(
    _ all: [AcLine], _ period: AcRange, _ format: String, roles: [String: String], emirate: String?, box: String
  ) -> [(line: AcLine, amount: Int, vat: Int)] {
    var key = box
    if format == "ae", box.count == 2, box.hasPrefix("1"), let letter = box.last,
      let index = Array("abcdefg").firstIndex(of: letter)
    {
      // Supplies are reported in the emirate the business is established in.
      if emirates[index].code != (emirate ?? "DU") { return [] }
      key = "1"
    }
    guard let picker = AcVat.pickers(format, roles: roles)[key] else { return [] }
    var out: [(line: AcLine, amount: Int, vat: Int)] = []
    for line in AcVat.lines(all, period) {
      let amount = picker.pick(line)
      let vat = picker.vat?(line) ?? 0
      if amount != 0 || vat != 0 { out.append((line, amount, vat)) }
    }
    return out
  }

  /// `VatStatus`: filed, in progress, ready to file or overdue.
  static func status(_ period: AcRange, filed: Bool, format: String, now: String) -> String {
    if filed { return "filed" }
    if period.to >= now { return "open" }
    return dueDate(period, format) < now ? "overdue" : "ready"
  }

  static func statusMeta(_ status: String) -> StatusMeta {
    switch status {
    case "filed": StatusMeta(label: "Filed", tone: .green)
    case "open": StatusMeta(label: "In progress", tone: .gray)
    case "ready": StatusMeta(label: "Ready to file", tone: .amber)
    case "overdue": StatusMeta(label: "Overdue", tone: .red)
    default: .unknown
    }
  }

  /// `OFFICE`: where the figures are submitted.
  static func office(_ format: String) -> String {
    switch format {
    case "uk":
      "Submit the figures to HMRC with your Making Tax Digital software or HMRC online services, then mark the return as filed here."
    case "ae": "Submit the figures on the FTA EmaraTax portal, then mark the return as filed here."
    default: "Submit the figures to your tax office, then mark the return as filed here."
    }
  }
}

// MARK: Year-end close

/// One proposed levy or transfer (`YearEndProposal`).
struct AcYearEndProposal: Sendable {
  let kind: String
  let applies: Bool
  let base: Int
  let rate: Double
  let amount: Int
  var room: Int?
  var roomKnown = false
}

/// `YearEndFigures`.
struct AcYearEndFigures: Sendable {
  let yearStart: String
  let yearEnd: String
  let profit: Int
  let profitBeforeLevies: Int
  let capital: Int
  /// "profile", "books" or "none".
  let capitalSource: String
  let statutoryReserve: Int
  let lossesBroughtForward: Int
  let proposals: [AcYearEndProposal]
}

/// `LevyRates`, in percent.
struct AcLevyRates: Sendable {
  var statutoryReserve = 10.0
  var statutoryReserveCap = 50.0
  var kfas = 1.0
  var zakat = 1.0
  var nlst = 2.5
  var incomeTax = 15.0

  /// `levyRates`: the company's rates, with the legal defaults.
  init(_ levies: JSONValue?) {
    guard let levies else { return }
    statutoryReserve = levies.number("statutoryReserve") ?? statutoryReserve
    statutoryReserveCap = levies.number("statutoryReserveCap") ?? statutoryReserveCap
    kfas = levies.number("kfas") ?? kfas
    zakat = levies.number("zakat") ?? zakat
    nlst = levies.number("nlst") ?? nlst
    incomeTax = levies.number("incomeTax") ?? incomeTax
  }
}

enum AcYearEnd {
  /// `YEAR_END_LABELS`.
  static func label(_ kind: String) -> String {
    switch kind {
    case "statutory_reserve": "Transfer to statutory reserve"
    case "voluntary_reserve": "Transfer to voluntary reserve"
    case "kfas": "KFAS contribution"
    case "zakat": "Zakat"
    case "nlst": "National Labour Support Tax"
    case "income_tax": "Income tax"
    default: kind
    }
  }

  static func keepsStatutoryReserve(_ form: String) -> Bool {
    form != "sole_proprietorship" && form != "freelance"
  }

  /// `foreignShare`: a foreign branch is wholly foreign.
  static func foreignShare(_ form: String, _ percent: Double) -> Double {
    if form == "foreign_branch" { return 100 }
    return min(100, max(0, percent.isFinite ? percent : 0))
  }

  private static func percentOf(_ base: Int, _ rate: Double) -> Int {
    base > 0 && rate > 0 ? AcLedger.minor(Decimal(base) * Money.dec(rate) / 100) : 0
  }

  /// `yearEndProposals`, in posting order.
  static func proposals(
    profitBeforeLevies: Int, legalForm: String, foreignOwnershipPercent: Double, capital: Int, statutoryReserve: Int,
    lossesBroughtForward: Int, rates: AcLevyRates
  ) -> [AcYearEndProposal] {
    let profit = max(0, profitBeforeLevies)
    let shareholding = KuwaitRules.isShareholding(legalForm)
    let reserveApplies = keepsStatutoryReserve(legalForm)
    let uncapped = reserveApplies ? percentOf(profit, rates.statutoryReserve) : 0
    let room: Int? =
      capital > 0 ? max(0, percentOf(capital, rates.statutoryReserveCap) - statutoryReserve) : nil
    let reserve = room.map { min(uncapped, $0) } ?? uncapped
    let kfasBase = max(0, profit - reserve - max(0, lossesBroughtForward))
    let foreign = foreignShare(legalForm, foreignOwnershipPercent)
    let taxBase = foreign > 0 ? percentOf(profit, foreign) : 0
    let listed = legalForm == "ksc_listed"
    return [
      AcYearEndProposal(
        kind: "statutory_reserve", applies: reserveApplies, base: reserveApplies ? profit : 0,
        rate: rates.statutoryReserve, amount: reserve, room: room, roomKnown: true),
      AcYearEndProposal(kind: "voluntary_reserve", applies: reserveApplies, base: profit, rate: 0, amount: 0),
      AcYearEndProposal(
        kind: "kfas", applies: shareholding, base: shareholding ? kfasBase : 0, rate: rates.kfas,
        amount: shareholding ? percentOf(kfasBase, rates.kfas) : 0),
      AcYearEndProposal(
        kind: "zakat", applies: shareholding, base: shareholding ? profit : 0, rate: rates.zakat,
        amount: shareholding ? percentOf(profit, rates.zakat) : 0),
      AcYearEndProposal(
        kind: "nlst", applies: listed, base: listed ? profit : 0, rate: rates.nlst,
        amount: listed ? percentOf(profit, rates.nlst) : 0),
      AcYearEndProposal(
        kind: "income_tax", applies: foreign > 0, base: taxBase, rate: rates.incomeTax,
        amount: percentOf(taxBase, rates.incomeTax)),
    ]
  }

  /// `yearEndFigures`: the year's profit, reserve and capital, and the
  /// proposed levies; entries of an earlier close of the year are left out.
  static func figures(
    _ books: AcBooks, date: String, profile: JSONValue, rates: AcLevyRates, exclude: Set<String>
  ) -> AcYearEndFigures {
    let yearEnd = books.fiscalYearEnd
    let start = AcFiscal.start(date, yearEnd)
    let end = AcFiscal.end(date, yearEnd)
    let lines =
      exclude.isEmpty ? books.lines : books.lines.filter { !($0.source == .journal && exclude.contains($0.sourceId)) }
    let special = AcSpecial(books.accounts, template: books.settings.template)
    let pl = AcStatements.profitOrLoss(lines, books.accounts, AcRange(from: start, to: end), special)
    let position = AcStatements.financialPosition(lines, books.accounts, end, yearEnd, special)
    let before = AcStatements.financialPosition(lines, books.accounts, AcDate.addDays(start, -1), yearEnd, special)
    func total(_ list: [AcCaption], _ key: String) -> Int { list.first { $0.key == key }?.total ?? 0 }
    let profileCapital = AcLedger.minor(profile.num("capital"), books.precision)
    let booksCapital = total(position.equity, "capital")
    let capital = profileCapital > 0 ? profileCapital : max(0, booksCapital)
    let statutoryReserve = total(position.equity, "statutory")
    let losses = max(0, -total(before.equity, "retained"))
    return AcYearEndFigures(
      yearStart: start, yearEnd: end, profit: pl.profit, profitBeforeLevies: pl.profitBeforeLevies, capital: capital,
      capitalSource: profileCapital > 0 ? "profile" : booksCapital > 0 ? "books" : "none",
      statutoryReserve: statutoryReserve, lossesBroughtForward: losses,
      proposals: proposals(
        profitBeforeLevies: pl.profitBeforeLevies, legalForm: profile.str("legalForm"),
        foreignOwnershipPercent: profile.num("foreignOwnershipPercent"), capital: capital,
        statutoryReserve: statutoryReserve, lossesBroughtForward: losses, rates: rates))
  }
}
