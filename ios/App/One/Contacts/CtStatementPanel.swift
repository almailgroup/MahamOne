import MahamKit
import SwiftUI

// A contact's Statement and Retentions sections
// (`src/apps/books/features/statements/statement-panel.tsx`,
// `src/features/clients/retention-panel.tsx`), to read on the phone.

/// The statement of account for a period: the opening balance, each line
/// with the running balance, the closing balance, aging, retention held and
/// the cheques not cleared yet.
struct CtStatementPanel: View {
  let data: CtContactData
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @State private var period = "this-month"
  @State private var currency = ""

  init(data: CtContactData) {
    self.data = data
  }

  var body: some View {
    let currencies = self.currencies
    let chosen = currencies.contains(currency) ? currency : (currencies.first ?? data.companyCurrency)
    let range = CtStatements.range(period, today: data.today)
    let statement = CtStatements.build(
      side: data.copy.side, documents: data.docs, payments: data.allPayments, from: range.from, to: range.to,
      currency: chosen)
    let money = { (minor: Int64) in data.format.money(ctMajor(minor, statement.precision), chosen) }
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 12) {
        Segmented(selection: $period, options: periods, small: true)
        if currencies.count > 1 {
          Field(t("Currency")) {
            Select(
              selection: Binding(get: { chosen }, set: { currency = $0 }),
              options: currencies.map { SelectOption($0, $0) })
          }
        }
        Text(t("{from} to {to}", ["from": data.format.date(range.from), "to": data.format.date(range.to)]))
          .font(.web(14))
          .foregroundStyle(palette.slate(500))
      }
      CtFigureGrid {
        CtFigure(label: t("Opening balance"), value: money(statement.opening))
        CtFigure(label: t("Debits"), value: money(statement.debits))
        CtFigure(label: t("Credits"), value: money(statement.credits))
        CtFigure(
          label: statement.closing < 0 ? t("In credit") : t("Balance due"), value: money(abs(statement.closing)),
          tone: .highlight)
      }
      if !statement.otherCurrencies.isEmpty {
        CtNote(
          .warning,
          lines: [
            t(
              "Documents in {currencies} are on their own statement. Pick the currency above.",
              ["currencies": statement.otherCurrencies.joined(separator: ", ")])
          ])
      }
      lines(statement, money: money)
      CtStatementAging(statement: statement, today: data.today, format: data.format, money: money)
      if statement.retentionHeld != 0 {
        HStack(spacing: 8) {
          Text(t("Retention held, not yet due"))
          Spacer(minLength: 8)
          Text(money(statement.retentionHeld))
            .font(.web(14, .semibold, tabular: true))
            .environment(\.layoutDirection, .leftToRight)
        }
        .font(.web(14))
        .foregroundStyle(palette[.violet(900)])
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(palette[.violet(50)], in: RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous))
      }
      if !statement.cheques.isEmpty {
        chequesCard(statement, money: money)
      }
    }
  }

  private var periods: [SegmentOption<String>] {
    [
      SegmentOption("this-month", t("This month")),
      SegmentOption("last-month", t("Last month")),
      SegmentOption("this-quarter", t("This quarter")),
      SegmentOption("this-year", t("This year")),
    ]
  }

  /// The contact's own currency first, then the others its documents are in.
  private var currencies: [String] {
    let own = data.contact.text("currency") ?? data.companyCurrency
    let used = Set(data.docs.filter(CtStatements.counted).map { $0.str("currency") }).filter { !$0.isEmpty && $0 != own }
    return [own] + used.sorted()
  }

  private func lines(_ statement: CtStatement, money: @escaping (Int64) -> String) -> some View {
    Card {
      CtStatementEdge(label: t("Balance brought forward"), value: money(statement.opening), strong: false)
      if statement.entries.isEmpty {
        CtEmptyText(t("No transactions in this period."), centered: true)
      } else {
        ForEach(statement.entries) { entry in
          entryRow(entry, money: money)
        }
      }
      CtStatementEdge(label: t("Closing balance"), value: money(statement.closing), strong: true)
    }
  }

  private func entryRow(_ entry: CtEntry, money: (Int64) -> String) -> some View {
    let route = self.route(of: entry)
    let reference = entry.chequeNumber.map { number in
      [number, CtCheques.bankName(entry.chequeBank ?? "")].filter { !$0.isEmpty }.joined(separator: " · ")
    } ?? entry.reference
    let muted = entry.kind == "retention" || entry.voided || entry.kind == "release_undone"
    return CtListRow(
      title: "\(CtStatementPanel.kindLabel(entry, side: data.copy.side, format: data.format)) \(entry.number)",
      subtitle: [data.format.date(entry.date), reference].filter { !$0.isEmpty }.joined(separator: " · "),
      amount: money(entry.debit != 0 ? entry.debit : -entry.credit), amountCaption: money(entry.balance),
      amountMuted: muted, amountTone: entry.amount < 0 && !muted ? .emerald(700) : nil
    ) {
      if entry.voided { Badge(t("Returned"), tone: .red) }
    } action: {
      if let route { router.push(route) }
    }
  }

  /// The payment or document a line opens.
  private func route(of entry: CtEntry) -> Route? {
    if let id = entry.paymentId { return .payment(data.copy.paymentDirection, id: id) }
    guard let id = entry.documentId, let doc = data.docs.first(where: { $0.rid == id }) else { return nil }
    return data.route(of: doc)
  }

  private func chequesCard(_ statement: CtStatement, money: @escaping (Int64) -> String) -> some View {
    CtRowsCard(
      data.kind == .vendor ? t("Cheques not yet presented") : t("Cheques not yet cleared"),
      description: t("They are in the payments above and count once the bank clears them.")
    ) {
      ForEach(statement.cheques) { cheque in
        ListRow(
          title: t("Cheque {number}", ["number": cheque.chequeNumber]),
          subtitle: [CtCheques.bankName(cheque.bank), data.format.date(cheque.date)].filter { !$0.isEmpty }
            .joined(separator: " · "),
          amount: money(cheque.amount)
        ) {
          Badge(status: StatusMeta.cheque(cheque.status))
        } action: {
          router.push(.payment(data.copy.paymentDirection, id: cheque.id))
        }
      }
    }
  }

  /// What a statement line is, without its number (`entryKindLabel`).
  static func kindLabel(_ entry: CtEntry, side: CtSide, format: CompanyFormat) -> String {
    switch entry.kind {
    case "payment":
      return side == .vendor ? t("Payment made") : t("Payment received")
    case "payment_void":
      switch entry.voidKind {
      case "returned": return t("Cheque returned")
      case "cancelled": return t("Cheque cancelled")
      default: return t("Payment voided")
      }
    case "invoice": return t("Invoice")
    case "bill": return t("Bill")
    case "opening": return t("Opening balance")
    case "credit": return t("Credit note")
    case "vendor_credit": return t("Vendor credit")
    case "retention":
      guard let percent = entry.percent, percent != 0 else { return t("Retention held") }
      return "\(t("Retention held")) (\(format.percent(percent)))"
    case "release": return t("Retention released")
    case "release_undone": return t("Retention release undone")
    default: return entry.kind
    }
  }
}

/// The first and last line of a statement: slate-50, the balance at the end.
struct CtStatementEdge: View {
  let label: String
  let value: String
  let strong: Bool
  @Environment(\.palette) private var palette

  var body: some View {
    HStack(spacing: 12) {
      Text(label)
        .font(.web(14, strong ? .semibold : .medium))
        .foregroundStyle(strong ? palette.slate(900) : palette.slate(700))
      Spacer(minLength: 8)
      Text(value)
        .font(.web(14, .semibold, tabular: true))
        .foregroundStyle(palette.slate(900))
        .environment(\.layoutDirection, .leftToRight)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity)
    .background(palette.slate(50))
    .overlay(alignment: .top) {
      if strong { Rectangle().fill(palette.slate(100)).frame(height: 1) }
    }
  }
}

/// "Aging on {date}": what is still owed by days past due, and the total.
struct CtStatementAging: View {
  let statement: CtStatement
  let today: String
  let format: CompanyFormat
  let money: (Int64) -> String
  @Environment(\.palette) private var palette

  var body: some View {
    let labels = [t("Not yet due"), t("1 to 30 days"), t("31 to 60 days"), t("61 to 90 days"), t("Over 90 days")]
    Card {
      CardHeader(t("Aging on {date}", ["date": format.date(statement.to)]))
      VStack(alignment: .leading, spacing: 8) {
        LazyVGrid(
          columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], alignment: .leading,
          spacing: 8
        ) {
          ForEach(0..<5, id: \.self) { index in
            cell(labels[index], money(statement.buckets[index]), danger: index > 0 && statement.buckets[index] > 0)
          }
          cell(t("Total"), money(statement.buckets.reduce(0, +)), danger: false, highlight: true)
        }
        if statement.unapplied != 0 {
          Text(t("Less credits not yet applied: {amount}", ["amount": money(statement.unapplied)]))
            .font(.web(12))
            .foregroundStyle(palette.slate(500))
        }
      }
      .padding(16)
    }
  }

  private func cell(_ label: String, _ value: String, danger: Bool, highlight: Bool = false) -> some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous)
    return VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.web(12))
        .foregroundStyle(highlight ? palette.primary(700) : palette.slate(500))
      Text(value)
        .font(.web(14, .semibold, tabular: true))
        .foregroundStyle(valueColor(danger: danger, highlight: highlight))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .environment(\.layoutDirection, .leftToRight)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(highlight ? palette.primary(50) : palette.surface, in: shape)
    .border(highlight ? palette.primary(200) : palette.slate(200), in: shape)
  }

  private func valueColor(danger: Bool, highlight: Bool) -> Color {
    if highlight { return palette.primary(800) }
    return danger ? palette[.red(600)] : palette.slate(900)
  }
}

// MARK: Retentions

/// A contact's retentions: the rate and where it stands, what is held back,
/// the clearance certificates and what was released.
struct CtRetentionPanel: View {
  let data: CtContactData
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let retained = self.retained
    let held = retained.filter { CtContacts.heldRetention($0) > 0 }
    let certificates = data.contact.list("clearanceCertificates")
    let releases = self.releases(retained)
    VStack(alignment: .leading, spacing: 16) {
      settings(certificates)
      CtRowsCard(
        t("Held back"),
        description: held.isEmpty ? nil : t("Total held: {amount}", ["amount": totals(held)])
      ) {
        if held.isEmpty {
          WebEmptyState(
            title: t("Nothing is held back"),
            description: data.kind == .vendor
              ? t("Retentions on bills show here until you release them.")
              : t("Retentions on invoices show here until they are released."))
        } else {
          ForEach(held.map(Rec.init)) { record in
            heldRow(record.raw)
          }
        }
      }
      CtRowsCard(
        t("Clearance certificates"),
        description: data.kind == .vendor
          ? t("Certificates this vendor gave you. While one is valid, new bills hold nothing back.")
          : t("Certificates you gave this client. While one is valid, new invoices hold nothing back.")
      ) {
        if certificates.isEmpty {
          CtEmptyText(t("No certificates yet."))
        } else {
          ForEach(Array(certificates.enumerated()), id: \.offset) { _, certificate in
            certificateRow(certificate)
          }
        }
      }
      if !releases.isEmpty {
        CtRowsCard(t("Released")) {
          ForEach(releases) { release in
            releaseRow(release)
          }
        }
      }
    }
  }

  /// Invoices (or bills) that held a retention back, oldest first.
  private var retained: [JSONValue] {
    data.docs
      .filter { doc in
        doc.str("type") == data.copy.docType && CtContacts.isPosted(doc) && (doc.obj("totals")?.num("retention") ?? 0) > 0
      }
      .sorted { $0.str("issueDate") < $1.str("issueDate") }
  }

  private func releases(_ docs: [JSONValue]) -> [CtRelease] {
    var found: [CtRelease] = []
    for doc in docs {
      for release in doc.list("retentionReleases") {
        found.append(CtRelease(doc: doc, release: release))
      }
    }
    return found.sorted { $0.release.str("date") > $1.release.str("date") }
  }

  /// What is held, per currency: "KD 120.000 + USD 40.00".
  private func totals(_ held: [JSONValue]) -> String {
    var sums: [String: Double] = [:]
    var order: [String] = []
    for doc in held {
      let currency = doc.text("currency") ?? data.companyCurrency
      if sums[currency] == nil { order.append(currency) }
      sums[currency, default: 0] += CtContacts.heldRetention(doc)
    }
    return order.map { data.format.money(sums[$0] ?? 0, $0) }.joined(separator: " + ")
  }

  private func settings(_ certificates: [JSONValue]) -> some View {
    let percent = data.retention
    let kind = data.contact.text("retentionKind")
    let title =
      percent > 0
      ? t("{kind} of {percent}", ["kind": CtContacts.retentionKindLabel(kind), "percent": data.format.percent(percent)])
      : (data.kind == .vendor ? t("You hold nothing back from this vendor.") : t("This client holds nothing back."))
    let hint =
      percent > 0
      ? (kind == "contract"
        ? t("Held until handover of the work.") : t("Held until the Ministry of Finance clearance certificate is shown."))
      : t("Set a retention when the contract or the law asks for one.")
    let status = statusMeta(kind: kind, certificates: certificates)
    return Card {
      HStack(alignment: .top, spacing: 12) {
        IconView(.shieldCheck, size: 20)
          .foregroundStyle(palette[.violet(600)])
          .padding(.top, 1)
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.web(14, .medium))
            .foregroundStyle(palette.slate(900))
          Text(hint)
            .font(.web(12))
            .foregroundStyle(palette.slate(500))
          if percent > 0 {
            Badge(status: status).padding(.top, 4)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(16)
    }
  }

  /// Where a retention stands (`retentionStatus`).
  private func statusMeta(kind: String?, certificates: [JSONValue]) -> StatusMeta {
    if kind == "contract" { return StatusMeta(label: "Waiting for handover", tone: .blue) }
    if certificates.contains(where: { CtRetentionPanel.validOn($0, data.today) }) {
      return StatusMeta(label: "Certificate on file", tone: .green)
    }
    return certificates.isEmpty
      ? StatusMeta(label: "Waiting for certificate", tone: .amber) : StatusMeta(label: "Certificate expired", tone: .red)
  }

  /// A certificate covers a date: issued on or before it and not expired.
  static func validOn(_ certificate: JSONValue, _ date: String) -> Bool {
    guard let issued = certificate.text("issueDate"), issued <= date else { return false }
    guard let expiry = certificate.text("expiryDate") else { return true }
    return expiry >= date
  }

  private func heldRow(_ doc: JSONValue) -> some View {
    let days = ISODates.daysBetween(doc.str("issueDate"), data.today) ?? 0
    let percent = doc.number("retentionPercent").map { data.format.percent($0) } ?? ""
    let kind = CtContacts.retentionKindLabel(doc.text("retentionKind") ?? data.contact.text("retentionKind"))
    let age = days > 0 ? tp(days, "{count} day", "{count} days") : t("Today")
    let route = data.route(of: doc)
    return ListRow(
      title: doc.str("number"),
      subtitle: [data.format.date(doc.text("issueDate")), age, percent, kind].filter { !$0.isEmpty }
        .joined(separator: " · "),
      amount: data.format.money(CtContacts.heldRetention(doc), doc.text("currency")),
      action: {
        if let route { router.push(route) }
      })
  }

  private func certificateRow(_ certificate: JSONValue) -> some View {
    let valid = CtRetentionPanel.validOn(certificate, data.today)
    let notYet = certificate.str("issueDate") > data.today
    let dates =
      certificate.text("expiryDate").map { expiry in
        t("{from} to {to}", ["from": data.format.date(certificate.text("issueDate")), "to": data.format.date(expiry)])
      } ?? t("Issued {date}", ["date": data.format.date(certificate.text("issueDate"))])
    let line = [dates, certificate.str("notes")].filter { !$0.isEmpty }.joined(separator: " · ")
    return CtListRow(
      title: certificate.str("number"), subtitle: line,
      badges: {
        if valid {
          Badge(t("Valid"), tone: .green)
        } else if notYet {
          Badge(t("Not valid yet"), tone: .amber)
        } else {
          Badge(t("Expired"), tone: .red)
        }
      })
  }

  private func releaseRow(_ item: CtRelease) -> some View {
    let release = item.release
    let reference = release.str("reference")
    let basis =
      release.str("basis") == "certificate"
      ? t("Certificate {number}", ["number": reference]) : (reference.isEmpty ? t("Handover") : reference)
    let undone = release.text("reversedOn")
    return CtListRow(
      title: item.doc.str("number"),
      subtitle: [data.format.date(release.text("date")), basis].joined(separator: " · "),
      amount: data.format.money(release.num("amount"), item.doc.text("currency")), amountMuted: undone != nil,
      badges: {
        if let undone { Badge(t("Undone {date}", ["date": data.format.date(undone)]), tone: .slate) }
      })
  }
}

/// A retention released on one of the documents.
struct CtRelease: Identifiable {
  let doc: JSONValue
  let release: JSONValue
  var id: String { "\(doc.rid)-\(release.rid)" }
}
