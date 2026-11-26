import MahamKit
import SwiftUI

// `/books` (src/apps/books/pages/dashboard.tsx with
// features/dashboard/model.ts), the classic layout on a phone: the four key
// figures, who owes the company, what needs attention, cheques due, low
// stock, invoiced against collected and the recent activity.

/// The dashboard's figures (`dashboardFigures`, `cashAccounts`).
struct AcDashboardFigures {
  let aging: AcAging
  let otherCurrencies: [(currency: String, amount: Double)]
  let overdue: [(doc: JSONValue, days: Int)]
  let overdueTotal: Double
  let billsDue: [JSONValue]
  let billsDueTotal: Double
  let billsOverdue: [(doc: JSONValue, days: Int)]
  let billsOverdueTotal: Double
  let chequesIn: [(payment: JSONValue, minor: Int)]
  let chequesOut: [(payment: JSONValue, minor: Int)]
  let invoiced: [Double]
  let collected: [Double]
  let months: [String]
  let quotesWaiting: [JSONValue]
  let vatDue: (period: AcRange, due: String)?
  let cashTotal: Int
  let cashAccounts: Int

  /// Days ahead the dashboard looks for cheques.
  static let chequeDays = 14

  @MainActor
  static func build(_ one: OneData) -> AcDashboardFigures {
    let books = one.acBooks
    let base = books.currency
    let precision = books.precision
    let now = AcDate.today
    let docs = one.records(.documents)
    let payments = one.records(.payments)
    let clients = one.records(.clients)
    func isOpen(_ doc: JSONValue) -> Bool {
      let status = doc.str("status")
      return (status == "sent" || status == "partial") && (doc.obj("totals")?.num("balance") ?? 0) > 0
    }
    func balance(_ doc: JSONValue) -> Double { doc.obj("totals")?.num("balance") ?? 0 }
    func late(_ list: [JSONValue]) -> [(doc: JSONValue, days: Int)] {
      var rows: [(doc: JSONValue, days: Int)] = []
      for doc in list where DocRules.displayStatus(doc, today: now) == "overdue" {
        var days = 0
        if let due = doc.text("dueDate") { days = AcDate.daysBetween(due, now) }
        rows.append((doc: doc, days: days))
      }
      // The longest overdue first; ties keep their order.
      let indexed = Array(rows.enumerated())
      let sorted = indexed.sorted { (a, b) -> Bool in
        if a.element.days != b.element.days { return a.element.days > b.element.days }
        return a.offset < b.offset
      }
      return sorted.map { $0.element }
    }
    let invoices = docs.filter { $0.str("type") == "invoice" }
    let open = invoices.filter(isOpen)

    // Who owes you: unpaid invoices in the company currency by age; other currencies apart.
    let aging = AcReports.aging(docs, clients, currency: base, asOf: now, type: "invoice")
    var otherOrder: [String] = []
    var others: [String: Double] = [:]
    for doc in open where doc.str("currency") != base {
      let code = doc.str("currency")
      if others[code] == nil { otherOrder.append(code) }
      others[code, default: 0] += balance(doc)
    }
    let overdue = late(open)
    let overdueTotal = overdue.filter { $0.doc.str("currency") == base }.reduce(0) { $0 + balance($1.doc) }

    // What you owe this week: bills due in the next seven days or already late.
    let weekEnd = AcDate.addDays(now, 6)
    let openBills = docs.filter { $0.str("type") == "bill" && isOpen($0) }
    let billsDue = openBills.filter { ($0.text("dueDate") ?? $0.str("issueDate")) <= weekEnd }
    let billsOverdue = late(openBills)
    func sumBase(_ list: [JSONValue]) -> Double {
      list.filter { $0.str("currency") == base }.reduce(0) { $0 + balance($1) }
    }

    // Cheques: open ones dated in the next 14 days, or late.
    let horizon = AcDate.addDays(now, chequeDays - 1)
    let live = payments.filter { !$0.flag("voided") }
    func dueCheques(_ out: Bool) -> [(payment: JSONValue, minor: Int)] {
      live.filter { payment in
        guard payment.str("method") == "cheque", let cheque = payment.obj("cheque"),
          (payment.str("direction") == "out") == out
        else { return false }
        let status = cheque.str("status")
        guard status == "held" || status == "deposited", cheque.str("date") <= horizon else { return false }
        return status == "held" || cheque.str("date") >= now
      }
      .map { payment -> (payment: JSONValue, minor: Int) in
        let rate = payment.str("currency") == base ? 1 : (payment.number("exchangeRate").flatMap { $0 > 0 ? $0 : nil } ?? 1)
        return (payment: payment, minor: AcLedger.minor(Money.dec(payment.num("amount")) * Money.dec(rate), precision))
      }
      .sorted { ($0.payment.obj("cheque")?.str("date") ?? "") < ($1.payment.obj("cheque")?.str("date") ?? "") }
    }

    // Invoiced against collected, month by month.
    let months = monthKeys(12, now)
    let issued = invoices.filter { $0.str("status") != "draft" && $0.str("status") != "void" && $0.str("currency") == base }
    let cash = live.filter { $0.str("direction") != "out" && $0.str("method") != "credit_note" && $0.str("currency") == base }
    let invoiced = months.map { month in
      issued.filter { $0.str("issueDate") >= "\(month)-01" && $0.str("issueDate") <= "\(month)-31" }
        .reduce(0) { $0 + ($1.obj("totals")?.num("total") ?? 0) }
    }
    let collected = months.map { month in
      cash.filter { $0.str("date") >= "\(month)-01" && $0.str("date") <= "\(month)-31" }.reduce(0) { $0 + $1.num("amount") }
    }
    let quotes = docs.filter { $0.str("type") == "quote" && DocRules.displayStatus($0, today: now) == "sent" }

    // Cash and bank: bank and cash accounts in use.
    var balances: [String: Int] = [:]
    for line in books.lines { balances[line.accountId, default: 0] += line.amount }
    let cashAccounts = books.accounts.filter { $0.type == "asset_cash" && !$0.archived }
    return AcDashboardFigures(
      aging: aging, otherCurrencies: otherOrder.map { (currency: $0, amount: others[$0] ?? 0) }, overdue: overdue,
      overdueTotal: overdueTotal, billsDue: billsDue, billsDueTotal: sumBase(billsDue), billsOverdue: billsOverdue,
      billsOverdueTotal: sumBase(billsOverdue.map { $0.doc }), chequesIn: dueCheques(false), chequesOut: dueCheques(true),
      invoiced: invoiced, collected: collected, months: months, quotesWaiting: quotes,
      vatDue: vatToFile(one, books: books, now: now), cashTotal: cashAccounts.reduce(0) { $0 + (balances[$1.id] ?? 0) },
      cashAccounts: cashAccounts.count)
  }

  /// `monthKeys`: the `count` months up to the one `from` is in, oldest first.
  static func monthKeys(_ count: Int, _ from: String) -> [String] {
    let current = AcDate.period(from)
    return (0..<count).reversed().map { AcDate.shiftPeriod(current, -$0) }
  }

  /// The last ended VAT period, until it is marked as filed (when taxes are on).
  @MainActor
  static func vatToFile(_ one: OneData, books: AcBooks, now: String) -> (period: AcRange, due: String)? {
    let company = one.company
    let taxesOn = company?["taxesEnabled"]?.bool ?? !one.records(.taxRates).isEmpty
    guard taxesOn else { return nil }
    let vat = AcVatSettings(company: company, settings: books.settings)
    guard vat.registered else { return nil }
    let period = AcVat.periodOf(AcDate.addDays(AcVat.periodOf(now, vat).from, -1), vat)
    if one.records(.vatReturns).contains(where: { $0.str("periodStart") == period.from }) { return nil }
    let active =
      one.records(.documents).contains { AcLedger.isPosted($0) && $0.str("issueDate") <= period.to }
      || one.records(.expenses).contains { $0.str("date") <= period.to }
    guard active else { return nil }
    return (period, AcVat.dueDate(period, vat.format))
  }
}

struct AcDashboardPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let one = model.one
    let format = one.format
    let figures = AcDashboardFigures.build(one)
    WebPage(spacing: 20, refresh: { [model] in await model.one.sync() }) {
      VStack(alignment: .leading, spacing: 4) {
        Text(t("Dashboard")).webText(.pageTitle).accessibilityAddTraits(.isHeader)
        Text(subtitle(format)).font(.web(14)).foregroundStyle(palette.slate(500)).lineLimit(1)
      }
      AcPayrollNote()
      keyFigures(figures, format: format)
      AcReceivablesCard(figures: figures)
      AcAttentionCard(figures: figures)
      AcChequesCard(figures: figures)
      AcLowStockCard()
      AcInvoicedCard(figures: figures)
      AcActivityCard()
    }
  }

  private func subtitle(_ format: CompanyFormat) -> String {
    let name = model.one.company.map { localName($0) } ?? ""
    return name.isEmpty ? format.date(AcDate.today) : "\(name) · \(format.date(AcDate.today))"
  }

  private func keyFigures(_ figures: AcDashboardFigures, format: CompanyFormat) -> some View {
    let p = Money.precision(format.currency)
    let chequesIn = figures.chequesIn.reduce(0) { $0 + $1.minor }
    let chequesOut = figures.chequesOut.reduce(0) { $0 + $1.minor }
    let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    return LazyVGrid(columns: columns, spacing: 12) {
      AcKpi(
        icon: .landmark, label: t("Cash and bank"), amount: format.acMoney(figures.cashTotal), muted: figures.cashTotal == 0,
        hint: figures.cashAccounts == 0
          ? t("No bank accounts yet") : tp(figures.cashAccounts, "In {count} account", "In {count} accounts")
      ) { router.push(.banking) }
      AcKpi(
        icon: .handCoins, label: t("Owed to you"), amount: format.money(figures.aging.total),
        muted: figures.aging.total == 0, hint: owedHint(figures, format), danger: figures.overdueTotal > 0
      ) { router.push(.report("aging")) }
      AcKpi(
        icon: .receipt, label: t("You owe this week"), amount: format.money(figures.billsDueTotal),
        muted: figures.billsDueTotal == 0, hint: billsHint(figures, format),
        danger: !figures.billsDue.isEmpty && figures.billsOverdueTotal > 0
      ) { router.push(.purchaseDocuments(.bill)) }
      AcKpi(
        icon: .walletCards, label: t("Cheques due"), amount: format.acMoney(chequesIn), muted: chequesIn == 0,
        hint: figures.chequesIn.isEmpty && figures.chequesOut.isEmpty
          ? tp(
            AcDashboardFigures.chequeDays, "None in the next {count} day", "None in the next {count} days")
          : t("{amount} to pay out", ["amount": format.money(Money.toNumber(Money.fromMinor(Int64(chequesOut), p)))])
      ) { router.push(.cheques) }
    }
  }

  private func owedHint(_ figures: AcDashboardFigures, _ format: CompanyFormat) -> String {
    if figures.overdueTotal > 0 { return t("{amount} overdue", ["amount": format.money(figures.overdueTotal)]) }
    return figures.aging.total > 0 ? t("Nothing overdue") : t("No unpaid invoices")
  }

  private func billsHint(_ figures: AcDashboardFigures, _ format: CompanyFormat) -> String {
    if figures.billsDue.isEmpty { return t("No bills due") }
    if figures.billsOverdueTotal > 0 {
      return t("{amount} overdue", ["amount": format.money(figures.billsOverdueTotal)])
    }
    return tp(figures.billsDue.count, "{count} bill due", "{count} bills due")
  }
}

/// A key figure (`Kpi`): the icon and label, the amount and a hint.
struct AcKpi: View {
  let icon: Icon
  let label: String
  let amount: String
  var muted = false
  let hint: String
  var danger = false
  let action: () -> Void
  @Environment(\.palette) private var palette

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.lg, style: .continuous)
    Button {
      Haptics.play(.tap)
      action()
    } label: {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 8) {
          IconView(icon, size: 16).foregroundStyle(palette.slate(400))
          Text(label).font(.web(12, .medium)).foregroundStyle(palette.slate(500)).lineLimit(1)
        }
        Text(amount)
          .font(.web(amount.count > 13 ? 16 : 18, .semibold, tabular: true))
          .foregroundStyle(muted ? palette.slate(400) : palette.slate(900))
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .environment(\.layoutDirection, .leftToRight)
          .padding(.top, 8)
        Text(hint)
          .font(.web(12))
          .foregroundStyle(danger ? palette[.red(700)] : palette.slate(500))
          .lineLimit(1)
          .padding(.top, 4)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(14)
      .background(palette.surface, in: shape)
      .border(palette.slate(200), in: shape)
      .boxShadow(WebShadow.xs, in: shape)
      .contentShape(shape)
    }
    .buttonStyle(PressedScale())
  }
}

/// A card's header with a link at the end (`CardLink`).
struct AcCardHeader: View {
  let title: String
  var description: String?
  var link: String?
  var onLink: (() -> Void)?
  @Environment(\.palette) private var palette

  var body: some View {
    CardHeader(title, description: description) {
      if let link, let onLink {
        Button {
          Haptics.play(.tap)
          onLink()
        } label: {
          Text(link).font(.web(14, .medium)).foregroundStyle(palette.primary(700))
        }
        .buttonStyle(.plain)
      }
    }
  }
}

/// `ReceivablesCard`: who owes the company, by how late.
struct AcReceivablesCard: View {
  let figures: AcDashboardFigures
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let format = model.one.format
    let aging = figures.aging
    Card {
      AcCardHeader(
        title: t("Who owes you"), description: t("Unpaid invoices by how late they are"), link: t("Aging report"),
        onLink: { router.push(.report("aging")) })
      if aging.total == 0, figures.otherCurrencies.isEmpty {
        HStack(spacing: 12) {
          IconView(.circleCheck, size: 20).foregroundStyle(palette[.emerald(600)])
          Text(t("No unpaid invoices. Everything you invoiced has been paid."))
            .font(.web(14))
            .foregroundStyle(palette.slate(600))
        }
        .padding(20)
      } else {
        VStack(alignment: .leading, spacing: 12) {
          agingBar(aging)
          VStack(spacing: 0) {
            ForEach(aging.totals.indices, id: \.self) { index in
              if aging.totals[index] != 0 {
                bucketRow(index, amount: aging.totals[index], format: format)
              }
            }
            ForEach(figures.otherCurrencies.indices, id: \.self) { index in
              AcLineRow(
                label: t("In {currency}", ["currency": figures.otherCurrencies[index].currency]),
                value: format.money(figures.otherCurrencies[index].amount, figures.otherCurrencies[index].currency))
            }
          }
          Text(t("Largest balances")).font(.web(12, .medium)).foregroundStyle(palette.slate(500))
          if aging.rows.isEmpty {
            Text(t("Only invoices in other currencies.")).font(.web(14)).foregroundStyle(palette.slate(500))
          } else {
            VStack(spacing: 0) {
              ForEach(aging.rows.prefix(3).indices, id: \.self) { index in
                largestRow(aging.rows[index], format: format)
              }
            }
          }
        }
        .padding(20)
      }
    }
  }

  private func agingBar(_ aging: AcAging) -> some View {
    GeometryReader { proxy in
      HStack(spacing: 2) {
        ForEach(aging.totals.indices, id: \.self) { index in
          if aging.totals[index] > 0, aging.total > 0 {
            Rectangle()
              .fill(palette.color(.aging(index + 1)))
              .frame(width: max(2, proxy.size.width * aging.totals[index] / aging.total))
          }
        }
      }
    }
    .frame(height: 12)
    .background(palette.slate(100))
    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
  }

  private func bucketRow(_ index: Int, amount: Double, format: CompanyFormat) -> some View {
    HStack(spacing: 8) {
      RoundedRectangle(cornerRadius: 2).fill(palette.color(.aging(index + 1))).frame(width: 10, height: 10)
      Text(t(AcReports.agingBuckets[index])).font(.web(14)).foregroundStyle(palette.slate(600))
      Spacer()
      Text(format.money(amount))
        .font(.web(14, tabular: true))
        .foregroundStyle(palette.slate(900))
        .environment(\.layoutDirection, .leftToRight)
    }
    .padding(.vertical, 6)
  }

  private func largestRow(_ row: AcAgingRow, format: CompanyFormat) -> some View {
    let late = row.buckets.dropFirst().reduce(0, +)
    let name = model.one.contactName(row.clientId)
    return Button {
      Haptics.play(.tap)
      router.push(.contact(.customer, id: row.clientId))
    } label: {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(name.isEmpty ? row.clientName : name).font(.web(14, .medium)).foregroundStyle(palette.slate(800))
          if late > 0 {
            Text(t("{amount} overdue", ["amount": format.money(late)])).font(.web(12)).foregroundStyle(palette[.red(700)])
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Text(format.money(row.total))
          .font(.web(14, .semibold, tabular: true))
          .foregroundStyle(palette.slate(900))
          .environment(\.layoutDirection, .leftToRight)
      }
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// `Needs attention`: overdue invoices and bills, the bank statement, VAT and quotes.
struct AcAttentionCard: View {
  let figures: AcDashboardFigures
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let one = model.one
    let format = one.format
    let toMatch = one.records(.bankTransactions).filter { $0.obj("match") == nil && !$0.flag("ignored") }
    let nothing =
      figures.overdue.isEmpty && figures.billsOverdue.isEmpty && figures.quotesWaiting.isEmpty && figures.vatDue == nil
      && toMatch.isEmpty
    Card {
      AcCardHeader(
        title: t("Needs attention"), link: figures.overdue.isEmpty ? nil : t("Overdue invoices"),
        onLink: { router.push(.salesDocuments(.invoice)) })
      if nothing {
        VStack(spacing: 4) {
          IconView(.circleCheck, size: 32).foregroundStyle(palette[.emerald(600)])
          Text(t("All caught up")).font(.web(14, .medium)).foregroundStyle(palette.slate(800)).padding(.top, 4)
          Text(t("No overdue invoices or bills.")).font(.web(14)).foregroundStyle(palette.slate(500))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
      } else {
        VStack(spacing: 0) {
          ForEach(figures.overdue.prefix(3).indices, id: \.self) { index in
            documentRow(figures.overdue[index], bill: false, format: format)
          }
          ForEach(figures.billsOverdue.prefix(2).indices, id: \.self) { index in
            documentRow(figures.billsOverdue[index], bill: true, format: format)
          }
          if !toMatch.isEmpty {
            AcAttentionRow(
              icon: .banknote, title: t("Bank statement"),
              detail: tp(toMatch.count, "{count} line to match", "{count} lines to match"), tone: nil, amount: nil
            ) { router.push(bankRoute(toMatch)) }
          }
          if let vat = figures.vatDue {
            AcAttentionRow(
              icon: .landmark, title: t("VAT return to file"),
              detail: t(
                "{start} – {end} · due {date}",
                ["start": format.date(vat.period.from), "end": format.date(vat.period.to), "date": format.date(vat.due)]),
              tone: vat.due < AcDate.today ? Token.red(700) : nil, amount: nil
            ) { router.push(.vatReturn(start: vat.period.from)) }
          }
          ForEach(figures.quotesWaiting.prefix(2).map(Rec.init)) { record in
            AcAttentionRow(
              icon: .clock, title: name(record.raw),
              detail: t("Quote {number} awaiting reply", ["number": record.raw.str("number")]), tone: nil,
              amount: format.money(record.raw.obj("totals")?.num("total") ?? 0, record.raw.text("currency"))
            ) { router.push(.salesDocument(.quote, id: record.id)) }
          }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
      }
    }
  }

  private func name(_ doc: JSONValue) -> String {
    let name = model.one.contactName(doc.text("clientId"))
    return name.isEmpty ? "—" : name
  }

  private func bankRoute(_ lines: [JSONValue]) -> Route {
    let accounts = Set(lines.map { $0.str("accountId") })
    if accounts.count == 1, let id = accounts.first { return .bankAccount(id: id) }
    return .banking
  }

  private func documentRow(_ item: (doc: JSONValue, days: Int), bill: Bool, format: CompanyFormat) -> some View {
    let doc = item.doc
    let number = doc.str("number")
    let detail =
      bill
      ? tp(item.days, "Bill {number} · {count} day overdue", "Bill {number} · {count} days overdue", ["number": number])
      : tp(item.days, "{number} · {count} day overdue", "{number} · {count} days overdue", ["number": number])
    return AcAttentionRow(
      icon: bill ? Icon.receipt : Icon.circleAlert, title: name(doc), detail: detail,
      tone: bill ? Token.amber(700) : Token.red(700),
      amount: format.money(doc.obj("totals")?.num("balance") ?? 0, doc.text("currency"))
    ) {
      router.push(bill ? .purchaseDocument(.bill, id: doc.rid) : .salesDocument(.invoice, id: doc.rid))
    }
  }
}

/// One line of "Needs attention" (`AttentionRow`).
struct AcAttentionRow: View {
  let icon: Icon
  let title: String
  let detail: String
  let tone: Token?
  let amount: String?
  let action: () -> Void
  @Environment(\.palette) private var palette

  var body: some View {
    Button {
      Haptics.play(.tap)
      action()
    } label: {
      HStack(spacing: 12) {
        HStack(alignment: .top, spacing: 10) {
          IconView(icon, size: 16)
            .foregroundStyle(tone.map { palette.color($0) } ?? palette.slate(400))
            .padding(.top, 2)
          VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.web(14, .medium)).foregroundStyle(palette.slate(800)).lineLimit(1)
            Text(detail).font(.web(12)).foregroundStyle(tone.map { palette.color($0) } ?? palette.slate(500))
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if let amount {
          Text(amount)
            .font(.web(14, .semibold, tabular: true))
            .foregroundStyle(palette.slate(900))
            .environment(\.layoutDirection, .leftToRight)
        } else {
          IconView(.arrowRight, size: 16).foregroundStyle(palette.slate(400))
        }
      }
      .frame(minHeight: 48)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }
}

/// `ChequesCard`: cheques received and issued that fall due in the next 14 days.
struct AcChequesCard: View {
  let figures: AcDashboardFigures
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let rows = self.rows
    Card {
      AcCardHeader(
        title: t("Cheques due"),
        description: tp(
          AcDashboardFigures.chequeDays, "Received and issued, next {count} day", "Received and issued, next {count} days"),
        link: t("Register"), onLink: { router.push(.cheques) })
      VStack(alignment: .leading, spacing: 0) {
        if rows.isEmpty {
          Text(
            tp(
              AcDashboardFigures.chequeDays, "No cheques fall due in the next {count} day.",
              "No cheques fall due in the next {count} days.")
          )
          .font(.web(14))
          .foregroundStyle(palette.slate(500))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
        } else {
          ForEach(rows.prefix(5).indices, id: \.self) { index in
            chequeRow(rows[index].payment, minor: rows[index].minor, out: rows[index].out)
          }
          if rows.count > 5 {
            Text(tp(rows.count - 5, "{count} more in the register", "{count} more in the register"))
              .font(.web(12))
              .foregroundStyle(palette.slate(500))
              .padding(.vertical, 8)
          }
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 8)
    }
  }

  private var rows: [(payment: JSONValue, minor: Int, out: Bool)] {
    var all: [(payment: JSONValue, minor: Int, out: Bool)] = []
    for row in figures.chequesIn { all.append((row.payment, row.minor, false)) }
    for row in figures.chequesOut { all.append((row.payment, row.minor, true)) }
    return all.enumerated().sorted { a, b in
      let x = a.element.payment.obj("cheque")?.str("date") ?? ""
      let y = b.element.payment.obj("cheque")?.str("date") ?? ""
      return x == y ? a.offset < b.offset : x < y
    }.map { $0.element }
  }

  /// `daysText`: today, in N days, or N days ago.
  private func daysText(_ days: Int) -> String {
    if days == 0 { return t("Today") }
    if days > 0 { return tp(days, "In {count} day", "In {count} days") }
    return tp(-days, "{count} day ago", "{count} days ago")
  }

  private func chequeRow(_ payment: JSONValue, minor: Int, out: Bool) -> some View {
    let format = model.one.format
    let cheque = payment.obj("cheque")
    let date = cheque?.str("date") ?? ""
    let days = AcDate.daysBetween(AcDate.today, date)
    let bank = cheque?.str("bank").trimmingCharacters(in: .whitespaces) ?? ""
    let known = Kuwait.banks.first { $0.code == bank.uppercased() }
    let drawer = cheque?.text("drawer") ?? known.map { $0.name[LanguageStore.shared.isArabic ? .ar : .en] } ?? bank
    let detail = [out ? t("Issued") : t("Received"), format.date(date), daysText(days)].joined(separator: " · ")
    return Button {
      Haptics.play(.tap)
      router.push(.payment(out ? .made : .received, id: payment.rid))
    } label: {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(drawer).font(.web(14, .medium)).foregroundStyle(palette.slate(800)).lineLimit(1)
          Text(detail).font(.web(12)).foregroundStyle(days < 0 ? palette[.red(700)] : palette.slate(500)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Text(format.acMoney(out ? -minor : minor))
          .font(.web(14, .semibold, tabular: true))
          .foregroundStyle(out ? palette.slate(900) : palette[.emerald(700)])
          .environment(\.layoutDirection, .leftToRight)
      }
      .frame(minHeight: 48)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }
}

/// `LowStockCard`: stock items at or below their reorder level.
struct AcLowStockCard: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let one = model.one
    let format = one.format
    let items = one.records(.products).filter { $0.str("kind") == "stock" && !$0.flag("archived") }
    let levels = AcStock.levels(one.records(.stockMovements), Money.precision(format.currency))
    let low = items.filter { $0.number("reorderLevel") != nil }
      .map { (product: $0, onHand: levels[$0.rid]?.quantity ?? 0) }
      .filter { $0.onHand <= ($0.product.number("reorderLevel") ?? 0) }
      .sorted { $0.onHand < $1.onHand }
    if !items.isEmpty {
      Card {
        AcCardHeader(
          title: t("Low stock"),
          description: low.isEmpty
            ? t("Every item is above its reorder level.")
            : tp(low.count, "{count} item to reorder", "{count} items to reorder"),
          link: low.isEmpty ? nil : t("View"), onLink: { router.push(.report("low-stock")) })
        if !low.isEmpty {
          VStack(spacing: 0) {
            ForEach(low.prefix(3).indices, id: \.self) { index in
              HStack(spacing: 10) {
                IconView(.packageX, size: 16).foregroundStyle(palette[.amber(600)])
                Text(localName(low[index].product)).font(.web(14, .medium)).foregroundStyle(palette.slate(800))
                  .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(format.quantity(low[index].onHand)) \(low[index].product.str("unit"))")
                  .font(.web(14, tabular: true))
                  .foregroundStyle(palette.slate(600))
              }
              .frame(minHeight: 44)
              .overlay(alignment: .top) {
                if index > 0 { Rectangle().fill(palette.slate(100)).frame(height: 1) }
              }
            }
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 8)
        }
      }
    }
  }
}

/// `InvoicedCard`: invoiced and collected per month, the last 12 months.
struct AcInvoicedCard: View {
  let figures: AcDashboardFigures
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    let format = model.one.format
    let empty = figures.invoiced.allSatisfy { $0 == 0 } && figures.collected.allSatisfy { $0 == 0 }
    Card {
      CardHeader(
        t("Invoiced vs collected"),
        description: tp(12, "Last {count} month · {currency}", "Last {count} months · {currency}", ["currency": format.currency]))
      if empty {
        WebEmptyState(
          icon: .fileText, title: tp(12, "No invoices in the last {count} month", "No invoices in the last {count} months"),
          description: t("Your monthly sales and the payments you collect will show here."))
      } else {
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 16) {
            legend(t("Invoiced"), .chart1)
            legend(t("Collected"), .chart2)
          }
          chart
        }
        .padding(20)
      }
    }
  }

  private func legend(_ label: String, _ token: Token) -> some View {
    HStack(spacing: 6) {
      RoundedRectangle(cornerRadius: 2).fill(palette.color(token)).frame(width: 10, height: 10)
      Text(label).font(.web(12)).foregroundStyle(palette.slate(600))
    }
  }

  private var chart: some View {
    let peak = max(1, (figures.invoiced + figures.collected).max() ?? 1)
    return HStack(alignment: .bottom, spacing: 4) {
      ForEach(figures.months.indices, id: \.self) { index in
        VStack(spacing: 4) {
          HStack(alignment: .bottom, spacing: 1) {
            bar(figures.invoiced[index], peak: peak, token: .chart1)
            bar(figures.collected[index], peak: peak, token: .chart2)
          }
          .frame(height: 120, alignment: .bottom)
          Text(monthLabel(figures.months[index]))
            .font(.web(10))
            .foregroundStyle(palette.slate(500))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
      }
    }
  }

  private func bar(_ value: Double, peak: Double, token: Token) -> some View {
    RoundedRectangle(cornerRadius: 2, style: .continuous)
      .fill(palette.color(token))
      .frame(height: max(value > 0 ? 2 : 0, 120 * value / peak))
      .frame(maxWidth: .infinity)
  }

  /// "Mar", with the year on January ("Jan ’26") (`monthLabels`).
  private func monthLabel(_ key: String) -> String {
    let pieces = key.split(separator: "-")
    guard pieces.count == 2, let month = Int(pieces[1]) else { return key }
    let name = AcDate.monthName(month, arabic: LanguageStore.shared.isArabic, short: true)
    return month == 1 ? "\(name) ’\(pieces[0].suffix(2))" : name
  }
}

/// `ActivityCard`: the six latest things done in the company.
struct AcActivityCard: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let activity = model.one.records(.activities).sorted { $0.str("at") > $1.str("at") }.prefix(6)
    Card {
      CardHeader(t("Recent activity"))
      if activity.isEmpty {
        Text(t("What you and your team do will show here."))
          .font(.web(14))
          .foregroundStyle(palette.slate(500))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 20)
      } else {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(Array(activity).map(Rec.init)) { record in
            activityRow(record.raw)
          }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
      }
    }
  }

  private func activityRow(_ entry: JSONValue) -> some View {
    let route = link(entry)
    return Button {
      if let route {
        Haptics.play(.tap)
        router.push(route)
      }
    } label: {
      HStack(alignment: .top, spacing: 12) {
        Circle().fill(palette.primary(400)).frame(width: 8, height: 8).padding(.top, 6)
        VStack(alignment: .leading, spacing: 2) {
          Text(text(entry)).font(.web(14)).foregroundStyle(palette.slate(700))
          Text(byline(entry)).font(.web(12)).foregroundStyle(palette.slate(500))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.vertical, 6)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(route == nil)
  }

  private func link(_ entry: JSONValue) -> Route? {
    if let id = entry.text("documentId"), let doc = model.one.record(.documents, id), let route = AcLinks.document(doc) {
      return route
    }
    if entry.str("entity") == "client", let id = entry.text("entityId") { return .contact(.customer, id: id) }
    return nil
  }

  /// `activityText`: the message in the reader's language, dates and amounts formatted.
  private func text(_ entry: JSONValue) -> String {
    let format = model.one.format
    func dates(_ text: String) -> String {
      var out = text
      let pattern = "\\d{4}-\\d{2}-\\d{2}"
      while let range = out.range(of: pattern, options: .regularExpression) {
        let formatted = format.date(String(out[range]))
        if formatted == String(out[range]) { break }
        out.replaceSubrange(range, with: formatted)
      }
      return out
    }
    guard let key = entry.text("messageKey") else { return dates(entry.str("message")) }
    var vars: [String: String] = [:]
    let arabic = LanguageStore.shared.isArabic ? entry.obj("messageVarsAr") : nil
    for (name, value) in entry.obj("messageVars")?.object ?? [:] {
      let shown = arabic?[name] ?? value
      if let text = shown.string {
        vars[name] = dates(text)
      } else if let number = shown.double {
        vars[name] = Money.jsString(number)
      }
    }
    for (name, money) in entry.obj("messageMoney")?.object ?? [:] {
      vars[name] = format.money(money.num("amount"), money.text("currency"))
    }
    return t(key, vars)
  }

  /// When it happened, and by whom when that is known (`activityByline`, `when`).
  private func byline(_ entry: JSONValue) -> String {
    let when = whenText(entry.str("at"))
    let name = entry.str("byName").trimmingCharacters(in: .whitespaces)
    return name.isEmpty ? when : t("{when} · by {name}", ["when": when, "name": name])
  }

  private func whenText(_ at: String) -> String {
    guard let time = MahamDates.parseTimestamp(at) else { return "" }
    let minutes = Int((Date().timeIntervalSince(time) / 60).rounded())
    if minutes < 1 { return t("Just now") }
    if minutes < 60 { return tp(minutes, "{count} minute ago", "{count} minutes ago") }
    let local = ISODates.string(from: time)
    let clock = DateFormatter.localizedString(from: time, dateStyle: .none, timeStyle: .short)
    if local == AcDate.today { return t("Today at {time}", ["time": clock]) }
    if local == AcDate.addDays(AcDate.today, -1) { return t("Yesterday at {time}", ["time": clock]) }
    return model.one.format.date(local)
  }
}
