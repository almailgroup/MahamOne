import MahamKit
import SwiftUI

// The home's cards under the launcher (`src/suite/home/index.tsx`): Needs
// attention, and At a glance; and each app's status line in the launcher.
// The money topics (cheques, bills, overdue invoices) come from the
// company's records here, with the web's rules (`src/alerts/collect.ts`).

/// One line of Needs attention.
struct HomeAlert: Identifiable {
  enum Topic: String, CaseIterable { case cheques, bills, invoices }

  let topic: Topic
  let key: String
  let date: String
  let daysLeft: Int
  let red: Bool
  let title: String
  let status: String
  let detail: String
  let amount: String
  let route: Route

  var id: String { key }

  /// The topic's chip label (`TOPIC_LABELS`) and its page.
  var topicLabel: String { HomeAlert.label(topic) }

  static func label(_ topic: Topic) -> String {
    switch topic {
    case .cheques: t("Cheques")
    case .bills: t("Bills to pay")
    case .invoices: t("Overdue invoices")
    }
  }

  static func page(_ topic: Topic) -> Route {
    switch topic {
    case .cheques: .cheques
    case .bills: .purchaseDocuments(.bill)
    case .invoices: .salesDocuments(.invoice)
    }
  }
}

/// The web's alert collectors for the money topics, over the mirror.
@MainActor
enum HomeAlerts {
  /// Bills and cheques due within this many days count.
  static let dueWindow = 7

  static func collect(_ one: OneData, today: String = ISODates.today()) -> [HomeAlert] {
    let format = one.format
    var alerts = cheques(one, format: format, today: today)
    alerts += bills(one, format: format, today: today)
    alerts += invoices(one, format: format, today: today)
    // Red first, then by date and key (`homeAlerts`).
    return alerts.sorted { a, b in
      if a.red != b.red { return a.red }
      if a.date != b.date { return a.date < b.date }
      return a.key < b.key
    }
  }

  private static func isOpen(_ doc: JSONValue) -> Bool {
    let status = doc.str("status")
    return (status == "sent" || status == "partial") && (doc.obj("totals")?.num("balance") ?? 0) > 0
  }

  private static func daysText(_ daysLeft: Int) -> String {
    if daysLeft == 0 { return t("Today") }
    if daysLeft > 0 { return tp(daysLeft, "In {count} day", "In {count} days") }
    return tp(-daysLeft, "{count} day ago", "{count} days ago")
  }

  private static func days(_ from: String, _ to: String) -> Int {
    ISODates.daysBetween(from, to) ?? 0
  }

  private static func cheques(_ one: OneData, format: CompanyFormat, today: String) -> [HomeAlert] {
    let windowEnd = ISODates.addDays(today, dueWindow - 1)
    var alerts: [HomeAlert] = []
    for payment in one.records(.payments) {
      guard !payment.flag("voided"), payment.str("method") == "cheque", let cheque = payment.obj("cheque") else {
        continue
      }
      let status = cheque.str("status")
      guard status == "held" || status == "deposited" else { continue }
      let received = payment.str("direction") != "out"
      let date = cheque.str("date")
      let late = received && status == "held" && date < today
      let due = date >= today && date <= windowEnd && (!received || status == "held")
      guard late || due else { continue }
      let daysLeft = days(today, date)
      let number = cheque.text("number") ?? "—"
      let name = cheque.text("drawer") ?? one.contactName(payment.text("clientId"))
      let title =
        name.isEmpty
        ? t("Cheque {number}", ["number": number])
        : (received
          ? t("Cheque {number} from {name}", ["number": number, "name": name])
          : t("Cheque {number} to {name}", ["number": number, "name": name]))
      var detail: [String] = []
      if !late { detail.append(received ? t("To deposit") : t("To be cashed")) }
      if let bank = cheque.text("bank") { detail.append(bank) }
      detail.append(t("Dated {date}", ["date": format.date(date)]))
      alerts.append(
        HomeAlert(
          topic: .cheques, key: "cheques:\(payment.rid):\(date):\(late ? "late" : "due")", date: date,
          daysLeft: daysLeft, red: late || date == today, title: title,
          status: late ? t("Not deposited yet") : daysText(daysLeft), detail: detail.joined(separator: " · "),
          amount: format.money(payment.num("amount"), payment.text("currency")),
          route: .payment(received ? .received : .made, id: payment.rid)))
    }
    return alerts
  }

  private static func bills(_ one: OneData, format: CompanyFormat, today: String) -> [HomeAlert] {
    let windowEnd = ISODates.addDays(today, dueWindow - 1)
    var alerts: [HomeAlert] = []
    for doc in one.records(.documents) where doc.str("type") == "bill" && isOpen(doc) {
      let due = doc.text("dueDate") ?? doc.str("issueDate")
      guard due <= windowEnd else { continue }
      let overdue = due < today
      let daysLeft = days(today, due)
      let number = doc.text("vendorReference") ?? doc.str("number")
      let vendor = one.contactName(doc.text("clientId"))
      alerts.append(
        HomeAlert(
          topic: .bills, key: "bills:\(doc.rid):\(due):\(overdue ? "overdue" : "due")", date: due,
          daysLeft: daysLeft, red: overdue,
          title: vendor.isEmpty
            ? t("Bill {number}", ["number": number])
            : t("Bill {number} · {vendor}", ["number": number, "vendor": vendor]),
          status: overdue ? tp(-daysLeft, "{count} day late", "{count} days late") : daysText(daysLeft),
          detail: t("Due {date}", ["date": format.date(due)]),
          amount: format.money(doc.obj("totals")?.num("balance") ?? 0, doc.text("currency")),
          route: .purchaseDocument(.bill, id: doc.rid)))
    }
    return alerts
  }

  private static func invoices(_ one: OneData, format: CompanyFormat, today: String) -> [HomeAlert] {
    var alerts: [HomeAlert] = []
    for doc in one.records(.documents) where doc.str("type") == "invoice" && isOpen(doc) {
      guard let due = doc.text("dueDate"), due < today else { continue }
      let daysLeft = days(today, due)
      let client = one.contactName(doc.text("clientId"))
      let number = doc.str("number")
      alerts.append(
        HomeAlert(
          topic: .invoices, key: "invoices:\(doc.rid):\(due)", date: due, daysLeft: daysLeft, red: true,
          title: client.isEmpty
            ? t("Invoice {number}", ["number": number])
            : t("Invoice {number} · {client}", ["number": number, "client": client]),
          status: tp(-daysLeft, "{count} day overdue", "{count} days overdue"),
          detail: t("Due {date}", ["date": format.date(due)]),
          amount: format.money(doc.obj("totals")?.num("balance") ?? 0, doc.text("currency")),
          route: .salesDocument(.invoice, id: doc.rid)))
    }
    return alerts
  }
}

/// Needs attention: the topics as chips with their counts, up to eight
/// lines (red or amber), then "And N more".
struct NeedsAttentionCard: View {
  let alerts: [HomeAlert]
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  private static let maxLines = 8

  var body: some View {
    Card {
      CardHeader(t("Needs attention"))
      if !model.one.hasData {
        DataLoadingRow()
      } else if alerts.isEmpty {
        VStack(spacing: 12) {
          IconView(.circleCheck, size: 32).foregroundStyle(palette[.emerald(600)])
          Text(t("Nothing needs attention right now."))
            .font(.web(14, .medium))
            .foregroundStyle(palette.slate(900))
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
      } else {
        VStack(alignment: .leading, spacing: 12) {
          FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(topics, id: \.self) { topic in
              chip(topic)
            }
          }
          VStack(spacing: 0) {
            ForEach(Array(alerts.prefix(Self.maxLines).enumerated()), id: \.element.id) { index, alert in
              line(alert, first: index == 0)
            }
          }
          if alerts.count > Self.maxLines {
            Text(tp(alerts.count - Self.maxLines, "And {count} more.", "And {count} more."))
              .font(.web(12))
              .foregroundStyle(palette.slate(500))
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 16)
      }
    }
  }

  private var topics: [HomeAlert.Topic] {
    HomeAlert.Topic.allCases.filter { topic in alerts.contains { $0.topic == topic } }
  }

  private func chip(_ topic: HomeAlert.Topic) -> some View {
    let count = alerts.filter { $0.topic == topic }.count
    return Button {
      Haptics.play(.tap)
      router.go(HomeAlert.page(topic))
    } label: {
      HStack(spacing: 6) {
        Text(HomeAlert.label(topic)).foregroundStyle(palette.slate(700))
        Text(model.one.format.count(count)).foregroundStyle(palette.slate(500))
      }
      .font(.web(12, .medium))
      .padding(.horizontal, 12)
      .frame(minHeight: 36)
      .overlay(Capsule().strokeBorder(palette.slate(200), lineWidth: 1))
      .contentShape(Capsule())
    }
    .buttonStyle(PressedScale())
  }

  private func line(_ alert: HomeAlert, first: Bool) -> some View {
    Button {
      Haptics.play(.tap)
      router.push(alert.route)
    } label: {
      HStack(alignment: .center, spacing: 10) {
        IconView(icon(alert.topic), size: 16)
          .foregroundStyle(alert.red ? palette[.red(600)] : palette[.amber(600)])
        VStack(alignment: .leading, spacing: 2) {
          Text(alert.title)
            .font(.web(14, .medium))
            .foregroundStyle(palette.slate(800))
            .lineLimit(1)
          HStack(spacing: 0) {
            Text(alert.status).foregroundStyle(alert.red ? palette[.red(700)] : palette[.amber(700)])
            if !alert.detail.isEmpty {
              Text(verbatim: " · " + alert.detail).foregroundStyle(palette.slate(500))
            }
          }
          .font(.web(12))
          .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Text(alert.amount)
          .font(.web(14, .medium, tabular: true))
          .foregroundStyle(palette.slate(800))
          .environment(\.layoutDirection, .leftToRight)
      }
      .padding(.vertical, 10)
      .frame(minHeight: 52)
      .contentShape(Rectangle())
      .overlay(alignment: .top) {
        if !first { Rectangle().fill(palette.slate(100)).frame(height: 1) }
      }
    }
    .buttonStyle(.plain)
  }

  private func icon(_ topic: HomeAlert.Topic) -> Icon {
    switch topic {
    case .cheques: .walletCards
    case .bills: .receipt
    case .invoices: .fileText
    }
  }
}

/// At a glance: what is owed to the company, its bills to pay and the
/// cheques in hand, in its own currency.
struct AtAGlanceCard: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let format = model.one.format
    Card {
      CardHeader(t("At a glance"))
      VStack(spacing: 0) {
        row(.handCoins, t("Owed to you"), format.money(open("invoice")), to: .report("aging"), first: true)
        row(.receipt, t("Bills to pay"), format.money(open("bill")), to: .purchaseDocuments(.bill), first: false)
        row(.walletCards, t("Cheques in hand"), format.money(inHand), to: .cheques, first: false)
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 8)
    }
  }

  /// The balance still open on sent or part-paid documents of a type, in the company's currency.
  private func open(_ type: String) -> Double {
    let base = model.one.format.currency
    let amounts = model.one.records(.documents)
      .filter { doc in
        let status = doc.str("status")
        return doc.str("type") == type && (status == "sent" || status == "partial")
          && (doc.obj("totals")?.num("balance") ?? 0) > 0 && (doc.text("currency") ?? base) == base
      }
      .map { $0.obj("totals")?.num("balance") ?? 0 }
    return round(amounts)
  }

  /// Received cheques not yet taken to the bank.
  private var inHand: Double {
    let base = model.one.format.currency
    let amounts = model.one.records(.payments)
      .filter { payment in
        !payment.flag("voided") && payment.str("direction") != "out"
          && (payment.text("currency") ?? base) == base && payment.obj("cheque")?.str("status") == "held"
      }
      .map { $0.num("amount") }
    return round(amounts)
  }

  /// Sums as the web does: decimal, rounded to the currency's precision.
  private func round(_ amounts: [Double]) -> Double {
    let total = amounts.reduce(Decimal(0)) { $0 + Money.dec($1) }
    let rounded = Money.round(total, Money.precision(model.one.format.currency))
    return NSDecimalNumber(decimal: rounded).doubleValue
  }

  private func row(_ icon: Icon, _ label: String, _ value: String, to route: Route, first: Bool) -> some View {
    Button {
      Haptics.play(.tap)
      router.go(route)
    } label: {
      HStack(spacing: 12) {
        IconView(icon, size: 16).foregroundStyle(palette.slate(400))
        Text(label)
          .font(.web(14))
          .foregroundStyle(palette.slate(700))
          .frame(maxWidth: .infinity, alignment: .leading)
        Text(value)
          .font(.web(14, .semibold, tabular: true))
          .foregroundStyle(palette.slate(900))
          .environment(\.layoutDirection, .leftToRight)
      }
      .frame(minHeight: 48)
      .contentShape(Rectangle())
      .overlay(alignment: .top) {
        if !first { Rectangle().fill(palette.slate(100)).frame(height: 1) }
      }
    }
    .buttonStyle(.plain)
  }
}

/// Each app's line in the launcher ("3 overdue invoices", "12 employees").
@MainActor
enum HomeStats {
  static func lines(_ one: OneData, suite: SuiteState, today: String = ISODates.today()) -> [SuiteAppID: String] {
    guard one.hasData else { return [:] }
    var result: [SuiteAppID: String] = [:]
    let overdue = one.records(.documents)
      .filter { $0.str("type") == "invoice" && DocRules.displayStatus($0, today: today) == "overdue" }
      .count
    let split = suite.apps.contains { $0.id == .sales }
    result[split ? .sales : .books] =
      overdue > 0 ? tp(overdue, "{count} overdue invoice", "{count} overdue invoices") : t("Nothing overdue")
    if suite.access(.people).canOpen {
      let staff = one.records(.employees).filter { $0.str("status") != "left" }.count
      result[.people] = tp(staff, "{count} employee", "{count} employees")
    }
    if split {
      let items = one.records(.products).filter { !$0.flag("archived") }.count
      result[.inventory] = tp(items, "{count} item", "{count} items")
    }
    return result
  }
}
