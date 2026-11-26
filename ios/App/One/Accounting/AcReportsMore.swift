import MahamKit
import SwiftUI

// The reports outside the statements: aging, tax, sales and payments for
// sales and purchases (src/apps/books/pages/reports/sales.tsx), credit
// control (receivables.tsx), stock (inventory.tsx) and the auditor pack.

// MARK: Sales and purchases

/// Aging, totals per contact and payments, for sales or purchases; and the tax summary.
struct AcSalesReport: View {
  let report: String
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @State private var preset = "this-quarter"
  @State private var custom = AcDate.presetRange("this-quarter", AcDate.today)
  @State private var currency: String?

  private var out: Bool { report == "payables" || report == "purchases" || report == "payments-made" }

  /// `KIND`: purchase reports are the sales ones seen from the other side.
  private var kind: String {
    switch report {
    case "payables": "aging"
    case "purchases": "sales"
    case "payments-made": "payments"
    default: report
    }
  }

  var body: some View {
    let one = model.one
    let format = one.format
    let code = currency ?? format.currency
    let range = preset == "custom" ? custom : AcDate.presetRange(preset, AcDate.today)
    VStack(alignment: .leading, spacing: 16) {
      Card {
        AcToolbar {
          if kind != "aging" {
            AcRangePicker(preset: $preset, custom: $custom, options: rangeOptions)
          }
          Select(selection: currencyBinding(format), options: currencyOptions(format))
        }
      }
      switch kind {
      case "aging": agingCard(code, format: format)
      case "tax": taxCards(code, range: range, format: format)
      case "sales": salesCard(code, range: range, format: format)
      default: paymentsCards(code, range: range, format: format)
      }
    }
  }

  private var rangeOptions: [(value: String, label: String)] {
    AcReports.rangePresets + [("custom", "Custom…")]
  }

  private func currencyBinding(_ format: CompanyFormat) -> Binding<String> {
    Binding(get: { currency ?? format.currency }, set: { currency = $0 })
  }

  /// The company currency and every currency the documents and payments use.
  private func currencyOptions(_ format: CompanyFormat) -> [SelectOption<String>] {
    var codes = [format.currency]
    for record in model.one.records(.documents) + model.one.records(.payments) {
      if let code = record.text("currency"), !codes.contains(code) { codes.append(code) }
    }
    return codes.map { SelectOption($0, $0) }
  }

  private func money(_ value: Double, _ code: String, _ format: CompanyFormat) -> String {
    format.money(value, code)
  }

  private func rangeText(_ range: AcRange, _ format: CompanyFormat) -> String {
    preset == "all"
      ? t("at any time")
      : t("from {from} to {to}", ["from": format.date(range.from), "to": format.date(range.to)])
  }

  private func contactName(_ id: String, fallback: String = "—") -> String {
    let name = model.one.contactName(id)
    return name.isEmpty ? fallback : name
  }

  private func contactRoute(_ id: String) -> Route {
    .contact(out ? .vendor : .customer, id: id)
  }

  // MARK: Aging

  @ViewBuilder
  private func agingCard(_ code: String, format: CompanyFormat) -> some View {
    let one = model.one
    let aging = AcReports.aging(
      one.records(.documents), one.records(.clients), currency: code, asOf: AcDate.today, type: out ? "bill" : "invoice")
    ListCard {
      Text(
        out
          ? t("Unpaid bills by how late they are, as at {date}.", ["date": format.date(AcDate.today)])
          : t("Unpaid invoices by how late they are, as at {date}.", ["date": format.date(AcDate.today)])
      )
      .font(.web(14))
      .foregroundStyle(palette.slate(500))
    } rows: {
      if aging.rows.isEmpty {
        AcCardText(t("Nothing outstanding in {currency}.", ["currency": code]), centered: true)
      } else {
        ForEach(aging.rows.indices, id: \.self) { index in
          agingRow(aging.rows[index], code: code, format: format)
        }
        agingTotals(aging, code: code, format: format)
      }
    }
  }

  private func agingRow(_ row: AcAgingRow, code: String, format: CompanyFormat) -> some View {
    AcTapRow(action: { router.push(contactRoute(row.clientId)) }) {
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text(contactName(row.clientId, fallback: row.clientName))
            .font(.web(16, .medium))
            .foregroundStyle(palette.slate(900))
            .frame(maxWidth: .infinity, alignment: .leading)
          Text(money(row.total, code, format))
            .font(.web(14, .semibold, tabular: true))
            .foregroundStyle(palette.slate(900))
            .environment(\.layoutDirection, .leftToRight)
        }
        FlowLayout(spacing: 10, lineSpacing: 4) {
          ForEach(row.buckets.indices, id: \.self) { index in
            if row.buckets[index] != 0 {
              Text("\(t(AcReports.agingBuckets[index])) \(money(row.buckets[index], code, format))")
                .font(.web(12, index >= 3 ? .medium : .regular, tabular: true))
                .foregroundStyle(index >= 3 ? palette[.red(600)] : palette.slate(500))
            }
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
    }
  }

  private func agingTotals(_ aging: AcAging, code: String, format: CompanyFormat) -> some View {
    VStack(spacing: 0) {
      ForEach(aging.totals.indices, id: \.self) { index in
        AcLineRow(label: t(AcReports.agingBuckets[index]), value: money(aging.totals[index], code, format))
      }
      AcLineRow(label: t("Total"), value: money(aging.total, code, format), strong: true)
    }
    .background(palette.slate(50).opacity(0.6))
    .overlay(alignment: .top) { Rectangle().fill(palette.slate(200)).frame(height: 2) }
  }

  // MARK: Tax

  @ViewBuilder
  private func taxCards(_ code: String, range: AcRange, format: CompanyFormat) -> some View {
    let one = model.one
    let tax = AcReports.tax(one.records(.documents), one.records(.clients), currency: code, range: range)
    AcStat(t("Net sales"), value: money(tax.net, code, format))
    AcStat(t("Tax collected"), value: money(tax.tax, code, format))
    AcStat(t("Gross"), value: money(tax.gross, code, format))
    ListCard {
      Text(
        tp(
          tax.documents,
          "{count} invoice or credit note issued {range} (drafts and void left out; credit notes deducted).",
          "{count} invoices and credit notes issued {range} (drafts and void left out; credit notes deducted).",
          ["range": rangeText(range, format)])
      )
      .font(.web(14))
      .foregroundStyle(palette.slate(500))
    } rows: {
      if tax.rows.isEmpty {
        AcCardText(t("No taxed sales in this period."), centered: true)
      } else {
        ForEach(tax.rows.indices, id: \.self) { index in
          let row = tax.rows[index]
          ListRow(
            title: row.name,
            subtitle: "\(format.percent(row.rate)) · \(t("Taxable amount")) \(money(row.base, code, format))",
            amount: money(row.tax, code, format))
        }
      }
    }
  }

  // MARK: By contact

  @ViewBuilder
  private func salesCard(_ code: String, range: AcRange, format: CompanyFormat) -> some View {
    let one = model.one
    let sales = AcReports.byContact(
      one.records(.documents), one.records(.clients), currency: code, range: range, type: out ? "bill" : "invoice")
    ListCard {
      Text(
        out
          ? t("Bills received {range}.", ["range": rangeText(range, format)])
          : t("Invoices issued {range}.", ["range": rangeText(range, format)])
      )
      .font(.web(14))
      .foregroundStyle(palette.slate(500))
    } rows: {
      if sales.rows.isEmpty {
        AcCardText(out ? t("No bills in this period.") : t("No invoices in this period."), centered: true)
      } else {
        ForEach(sales.rows.indices, id: \.self) { index in
          let row = sales.rows[index]
          ListRow(
            title: contactName(row.clientId, fallback: row.clientName),
            subtitle: salesLine(row.invoices, paid: row.paid, outstanding: row.outstanding, code: code, format: format),
            amount: money(row.invoiced, code, format),
            action: { router.push(contactRoute(row.clientId)) })
        }
        ListCardFooter {
          Text("\(t("Total")) · \(t(out ? "Billed" : "Invoiced")) \(money(sales.invoiced, code, format))")
            .foregroundStyle(palette.slate(900))
          Text(salesLine(sales.invoices, paid: sales.paid, outstanding: sales.outstanding, code: code, format: format))
        }
      }
    }
  }

  private func salesLine(_ count: Int, paid: Double, outstanding: Double, code: String, format: CompanyFormat) -> String {
    [
      "\(t(out ? "Bills" : "Invoices")) \(format.quantity(Double(count)))",
      "\(t("Amount paid")) \(money(paid, code, format))",
      "\(t("Outstanding")) \(money(outstanding, code, format))",
    ].joined(separator: " · ")
  }

  // MARK: Payments

  @ViewBuilder
  private func paymentsCards(_ code: String, range: AcRange, format: CompanyFormat) -> some View {
    let one = model.one
    let report = AcReports.payments(one.records(.payments), currency: code, range: range, out: out)
    Card {
      VStack(alignment: .leading, spacing: 0) {
        Text(
          out
            ? t("Paid {range}", ["range": rangeText(range, format)])
            : t("Received {range}", ["range": rangeText(range, format)])
        )
        .font(.web(14))
        .foregroundStyle(palette.slate(500))
        Text(money(report.total, code, format))
          .font(.web(24, .semibold, tabular: true))
          .foregroundStyle(palette.slate(900))
          .environment(\.layoutDirection, .leftToRight)
          .padding(.top, 4)
          .padding(.bottom, 12)
        ForEach(report.byMethod.indices, id: \.self) { index in
          HStack {
            Text(t(AcReports.methodLabel(report.byMethod[index].method))).foregroundStyle(palette.slate(600))
            Spacer()
            Text(money(report.byMethod[index].amount, code, format))
              .fontWeight(.medium)
              .foregroundStyle(palette.slate(900))
              .environment(\.layoutDirection, .leftToRight)
          }
          .font(.web(14, tabular: true))
          .padding(.vertical, 4)
        }
      }
      .padding(20)
    }
    ListCard {
      if report.list.isEmpty {
        AcCardText(t("No payments in this period."), centered: true)
      } else {
        ForEach(report.list.map(Rec.init)) { record in
          let payment = record.raw
          ListRow(
            title: contactName(payment.str("clientId")),
            subtitle: [
              payment.str("number"), format.date(payment.text("date")), t(AcReports.methodLabel(payment.str("method"))),
            ].joined(separator: " · "),
            amount: money(payment.num("amount"), code, format),
            action: { router.push(.payment(out ? .made : .received, id: payment.rid)) })
        }
      }
    }
  }
}

// MARK: Credit control

/// Statements of account, customer exposure and retentions (`ReceivablesReports`).
struct AcReceivablesReport: View {
  let report: String
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @State private var period = "last-month"
  @State private var custom = AcDate.presetRange("last-month", AcDate.today)
  @State private var side = "customer"

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      switch report {
      case "statements": statements
      case "exposure": exposure
      default: retentions
      }
    }
  }

  /// Every contact's documents and payments.
  private func grouped() -> (documents: [String: [JSONValue]], payments: [String: [JSONValue]]) {
    var documents: [String: [JSONValue]] = [:]
    var payments: [String: [JSONValue]] = [:]
    for doc in model.one.records(.documents) { documents[doc.str("clientId"), default: []].append(doc) }
    for payment in model.one.records(.payments) { payments[payment.str("clientId"), default: []].append(payment) }
    return (documents, payments)
  }

  private func sortedClients() -> [JSONValue] {
    model.one.records(.clients).sorted { AcText.compare(localName($0), localName($1)) == .orderedAscending }
  }

  // MARK: Statements

  private var range: AcRange {
    if period == "custom" {
      return custom.from <= custom.to ? custom : AcRange(from: custom.to, to: custom.from)
    }
    return AcDate.presetRange(period, AcDate.today)
  }

  @ViewBuilder
  private var statements: some View {
    let format = model.one.format
    let range = self.range
    let rows = statementRows(range, format: format)
    Card {
      AcToolbar {
        Segmented(
          selection: $period,
          options: AcAccountStatements.periods.map { SegmentOption($0.value, t($0.label)) }, small: true)
        if period == "custom" {
          HStack(spacing: 8) {
            DateField(value: customFrom, required: true)
            DateField(value: customTo, required: true)
          }
        }
        Text(
          t(
            "Clients with a balance on {date}, with what happened from {from} to {to}.",
            ["date": format.date(range.to), "from": format.date(range.from), "to": format.date(range.to)])
        )
        .font(.web(14))
        .foregroundStyle(palette.slate(500))
      }
    }
    ListCard {
      if rows.isEmpty {
        WebEmptyState(
          title: t("No client has a balance"),
          description: t("Statements show here for clients who owe you or are in credit."))
      } else {
        ForEach(rows.indices, id: \.self) { index in
          statementRow(rows[index].client, rows[index].statement, format: format)
        }
      }
    }
  }

  private var customFrom: Binding<String> {
    Binding(get: { custom.from }, set: { custom = AcRange(from: $0, to: custom.to) })
  }

  private var customTo: Binding<String> {
    Binding(get: { custom.to }, set: { custom = AcRange(from: custom.from, to: $0) })
  }

  private func statementRows(_ range: AcRange, format: CompanyFormat) -> [(client: JSONValue, statement: AcStatement)] {
    let records = grouped()
    var out: [(client: JSONValue, statement: AcStatement)] = []
    for client in sortedClients() where client["isCustomer"]?.bool != false && !client.flag("archived") {
      let statement = AcAccountStatements.build(
        customer: true, documents: records.documents[client.rid] ?? [], payments: records.payments[client.rid] ?? [],
        from: range.from, to: range.to, currency: client.text("currency") ?? format.currency)
      if statement.closing != 0 { out.append((client, statement)) }
    }
    return out
  }

  private func statementRow(_ client: JSONValue, _ s: AcStatement, format: CompanyFormat) -> some View {
    func m(_ minor: Int) -> String {
      format.money(Money.toNumber(Money.fromMinor(Int64(minor), s.precision)), s.currency)
    }
    return AcTapRow(action: { router.push(.contact(.customer, id: client.rid)) }) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 2) {
            Text(localName(client)).font(.web(16, .medium)).foregroundStyle(palette.slate(900))
            Text(client.str("number")).font(.web(12)).foregroundStyle(palette.slate(500))
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          Text(m(s.closing))
            .font(.web(14, .semibold, tabular: true))
            .foregroundStyle(palette.slate(900))
            .environment(\.layoutDirection, .leftToRight)
        }
        Text(
          [
            "\(t("Opening balance")) \(m(s.opening))", "\(t("Debits")) \(m(s.debits))",
            "\(t("Credits")) \(m(s.credits))",
          ].joined(separator: " · ")
        )
        .font(.web(12, tabular: true))
        .foregroundStyle(palette.slate(500))
        Text("\(t("Overdue")) \(m(s.overdue))")
          .font(.web(12, s.overdue > 0 ? .medium : .regular, tabular: true))
          .foregroundStyle(s.overdue > 0 ? palette[.red(600)] : palette.slate(500))
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
    }
  }

  // MARK: Exposure

  @ViewBuilder
  private var exposure: some View {
    let format = model.one.format
    let rows = exposureRows(format)
    Card {
      Text(t("What each client owes, plus cheques they gave that have not cleared yet."))
        .font(.web(14))
        .foregroundStyle(palette.slate(500))
        .padding(16)
    }
    ListCard {
      if rows.isEmpty {
        WebEmptyState(
          title: t("No credit to watch"),
          description: t("Clients who owe you, have a credit limit or are on hold show here."))
      } else {
        ForEach(rows.indices, id: \.self) { index in
          exposureRow(rows[index].client, rows[index].position, returned: rows[index].returned, format: format)
        }
      }
    }
  }

  private func exposureRows(_ format: CompanyFormat) -> [(client: JSONValue, position: AcExposure, returned: Int)] {
    let records = grouped()
    let today = AcDate.today
    var rows: [(client: JSONValue, position: AcExposure, returned: Int)] = []
    for client in sortedClients() where client["isCustomer"]?.bool != false && !client.flag("archived") {
      let payments = records.payments[client.rid] ?? []
      let position = AcAccountStatements.exposure(
        client: client, documents: records.documents[client.rid] ?? [], payments: payments,
        companyCurrency: format.currency, today: today)
      let returned = payments.filter { $0.str("direction") != "out" && $0.obj("cheque")?.str("status") == "returned" }
        .count
      if position.exposure > 0 || position.limit != nil || client.flag("creditHold") || returned > 0 {
        rows.append((client, position, returned))
      }
    }
    func share(_ p: AcExposure) -> Double {
      if let limit = p.limit, limit != 0 { return Double(p.exposure) / Double(limit) }
      return p.exposure != 0 ? 1 : 0
    }
    return rows.enumerated().sorted { a, b in
      let x = share(a.element.position)
      let y = share(b.element.position)
      if x != y { return x > y }
      if a.element.position.exposure != b.element.position.exposure {
        return a.element.position.exposure > b.element.position.exposure
      }
      return a.offset < b.offset
    }.map { $0.element }
  }

  private func exposureRow(_ client: JSONValue, _ p: AcExposure, returned: Int, format: CompanyFormat) -> some View {
    func m(_ minor: Int) -> String { format.acMoney(minor) }
    return AcTapRow(action: { router.push(.contact(.customer, id: client.rid)) }) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline) {
          Text(localName(client)).font(.web(16, .medium)).foregroundStyle(palette.slate(900))
            .frame(maxWidth: .infinity, alignment: .leading)
          Text(m(p.exposure))
            .font(.web(14, .semibold, tabular: true))
            .foregroundStyle(palette.slate(900))
            .environment(\.layoutDirection, .leftToRight)
        }
        if client.flag("creditHold") || returned > 0 {
          HStack(spacing: 6) {
            if client.flag("creditHold") { Badge(t("On credit hold"), tone: .red) }
            if returned > 0 {
              Badge(tp(returned, "{count} returned cheque", "{count} returned cheques"), tone: .red)
            }
          }
        }
        Text(
          [
            "\(t("Balance due")) \(m(p.balance))", "\(t("Cheques not yet cleared")) \(m(p.uncleared))",
          ].joined(separator: " · ")
        )
        .font(.web(12, tabular: true))
        .foregroundStyle(palette.slate(500))
        Text(limitText(p, m))
          .font(.web(12, tabular: true))
          .foregroundStyle(palette.slate(600))
        Text("\(t("Overdue")) \(m(p.overdue))")
          .font(.web(12, p.overdue > 0 ? .medium : .regular, tabular: true))
          .foregroundStyle(p.overdue > 0 ? palette[.red(600)] : palette.slate(500))
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
    }
  }

  private func documentAction(_ doc: JSONValue) -> (() -> Void)? {
    guard let route = AcLinks.document(doc) else { return nil }
    return { router.push(route) }
  }

  private func limitText(_ p: AcExposure, _ m: (Int) -> String) -> String {
    guard let limit = p.limit else { return t("No credit limit") }
    if let available = p.available, available < 0 {
      return t("{amount} over the limit of {limit}", ["amount": m(-available), "limit": m(limit)])
    }
    return t("{amount} left of {limit}", ["amount": m(p.available ?? 0), "limit": m(limit)])
  }

  // MARK: Retentions

  private static let bands: [(label: String, max: Int)] = [
    ("Under 3 months", 90), ("3 to 6 months", 182), ("6 to 12 months", 365), ("Over a year", Int.max),
  ]

  @ViewBuilder
  private var retentions: some View {
    let format = model.one.format
    let rows = retentionRows()
    let own = rows.filter { $0.doc.str("currency") == format.currency }
    let total = own.reduce(0) { $0 + $1.held }
    Card {
      AcToolbar {
        Segmented(
          selection: $side,
          options: [SegmentOption("customer", t("Held by clients")), SegmentOption("vendor", t("Held from vendors"))],
          small: true)
      }
    }
    ForEach(Self.bands.indices, id: \.self) { index in
      AcLineRow(label: t(Self.bands[index].label), value: format.money(bandTotal(own, index)), divider: false)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous))
        .border(palette.slate(200), in: RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous))
    }
    AcLineRow(label: t("Total held"), value: format.money(total), strong: true, tone: .primary(800), divider: false)
      .background(palette.primary(50), in: RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous))
      .border(palette.primary(200), in: RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous))
    ListCard {
      if rows.isEmpty {
        WebEmptyState(
          title: t("Nothing is held back"),
          description: side == "vendor"
            ? t("Retentions you hold from vendors’ bills show here until you release them.")
            : t("Retentions clients hold from your invoices show here until they are released."))
      } else {
        ForEach(rows.indices, id: \.self) { index in
          retentionRow(rows[index], format: format)
        }
      }
    }
  }

  private func bandTotal(_ rows: [(client: JSONValue, doc: JSONValue, held: Double, age: Int, status: String)], _ index: Int)
    -> Double
  {
    let band = Self.bands[index]
    let lower = index == 0 ? Int.min : Self.bands[index - 1].max
    return rows.filter { $0.age <= band.max && (index == 0 || $0.age > lower) }.reduce(0) { $0 + $1.held }
  }

  private func retentionRows() -> [(client: JSONValue, doc: JSONValue, held: Double, age: Int, status: String)] {
    let records = grouped()
    let type = side == "vendor" ? "bill" : "invoice"
    let today = AcDate.today
    var out: [(client: JSONValue, doc: JSONValue, held: Double, age: Int, status: String)] = []
    for client in sortedClients() {
      let matches = side == "vendor" ? client["isVendor"]?.bool == true : client["isCustomer"]?.bool != false
      guard matches else { continue }
      let docs = (records.documents[client.rid] ?? []).filter {
        $0.str("type") == type && AcLedger.isPosted($0) && AcRetentions.held($0) > 0
      }.sorted { $0.str("issueDate") < $1.str("issueDate") }
      for doc in docs {
        let kind = doc.text("retentionKind") ?? client.text("retentionKind")
        out.append(
          (
            client, doc, AcRetentions.held(doc), AcDate.daysBetween(doc.str("issueDate"), today),
            AcRetentions.status(kind, client, today)
          ))
      }
    }
    return out
  }

  private func retentionRow(
    _ row: (client: JSONValue, doc: JSONValue, held: Double, age: Int, status: String), format: CompanyFormat
  ) -> some View {
    let kind = row.doc.text("retentionKind") ?? row.client.text("retentionKind")
    var details = [format.date(row.doc.text("issueDate"))]
    if let percent = row.doc.number("retentionPercent"), percent != 0 { details.append(format.percent(percent)) }
    details.append(t(AcRetentions.kindLabel(kind)))
    let age = row.age > 0 ? tp(row.age, "{count} day", "{count} days") : t("Today")
    return AcTapRow(action: documentAction(row.doc)) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline) {
          Text(localName(row.client)).font(.web(16, .medium)).foregroundStyle(palette.slate(900))
            .frame(maxWidth: .infinity, alignment: .leading)
          Text(format.money(row.held, row.doc.text("currency")))
            .font(.web(14, .semibold, tabular: true))
            .foregroundStyle(palette.slate(900))
            .environment(\.layoutDirection, .leftToRight)
        }
        Text("\(row.doc.str("number")) · \(details.joined(separator: " · "))")
          .font(.web(12))
          .foregroundStyle(palette.slate(500))
        HStack(spacing: 8) {
          Text(age).font(.web(12)).foregroundStyle(palette.slate(500))
          Badge(status: AcRetentions.statusMeta(row.status))
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
    }
  }
}

// MARK: Inventory

/// Stock on hand, valuation, an item's movements, low stock and issued items (`InventoryReports`).
struct AcInventoryReport: View {
  let report: String
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @State private var asAt = AcDate.today
  @State private var itemId: String?
  @State private var warehouseId = ""
  @State private var from = ""
  @State private var to = ""
  @State private var employeeId: String?

  init(report: String, params: [String: String]) {
    self.report = report
    _itemId = State(initialValue: params["item"])
  }

  private var stockItems: [JSONValue] {
    model.one.records(.products).filter { $0.str("kind") == "stock" }
      .sorted { AcText.compare(localName($0), localName($1)) == .orderedAscending }
  }

  /// The default warehouse first, archived last, then by name.
  private var warehouses: [JSONValue] {
    model.one.records(.warehouses).sorted { a, b in
      if a.flag("isDefault") != b.flag("isDefault") { return a.flag("isDefault") }
      if a.flag("archived") != b.flag("archived") { return !a.flag("archived") }
      return AcText.compare(localName(a), localName(b)) == .orderedAscending
    }
  }

  private var precision: Int { Money.precision(model.one.format.currency) }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if stockItems.isEmpty {
        Card {
          WebEmptyState(
            title: t("No stock items yet"),
            description: t(
              "Mark the goods you keep as stock items. Bills bring them in, invoices take them out, and the cost of sales follows."
            ))
        }
      } else {
        switch report {
        case "stock-on-hand": onHand
        case "stock-valuation": valuation
        case "stock-movements": movements
        case "issued-items": issued
        default: lowStock
        }
      }
    }
  }

  private func warehouseName(_ id: String) -> String {
    model.one.record(.warehouses, id).map { localName($0) } ?? ""
  }

  private func asAtPicker() -> some View {
    Card {
      AcToolbar {
        Field(t("As at")) { DateField(value: $asAt, required: true) }
      }
    }
  }

  // MARK: Stock on hand

  @ViewBuilder
  private var onHand: some View {
    let format = model.one.format
    let levels = AcStock.levels(model.one.records(.stockMovements), precision, asAt: asAt)
    let houses = warehouses.filter { house in
      !house.flag("archived") || levels.values.contains { ($0.byWarehouse[house.rid] ?? 0) != 0 }
    }
    let items = stockItems.filter { !$0.flag("archived") || (levels[$0.rid]?.quantity ?? 0) != 0 }
    let total = items.reduce(0) { $0 + AcLedger.minor(levels[$1.rid]?.value ?? 0, precision) }
    asAtPicker()
    ListCard {
      Text(t("Quantity of each stock item by warehouse, at the end of {date}.", ["date": format.date(asAt)]))
        .font(.web(14))
        .foregroundStyle(palette.slate(500))
    } rows: {
      ForEach(items.map(Rec.init)) { record in
        let level = levels[record.id]
        AcTapRow(action: { router.push(.report("stock-movements?item=\(record.id)")) }) {
          VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
              Text(localName(record.raw)).font(.web(16, .medium)).foregroundStyle(palette.slate(900))
              if let sku = record.raw.text("sku") { Text(sku).font(.web(12)).foregroundStyle(palette.slate(500)) }
              Spacer()
              Text(format.money(level?.value ?? 0))
                .font(.web(14, .semibold, tabular: true))
                .environment(\.layoutDirection, .leftToRight)
            }
            Text(quantities(level, houses, format))
              .font(.web(12, tabular: true))
              .foregroundStyle((level?.quantity ?? 0) < 0 ? palette[.red(600)] : palette.slate(500))
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
        }
      }
      ListCardFooter {
        Text("\(t("Total")) \(format.acMoney(total))").foregroundStyle(palette.slate(900)).fontWeight(.semibold)
      }
    }
  }

  private func quantities(_ level: AcStockLevel?, _ houses: [JSONValue], _ format: CompanyFormat) -> String {
    var parts: [String] = []
    if houses.count > 1 {
      for house in houses { parts.append("\(localName(house)) \(format.quantity(level?.byWarehouse[house.rid] ?? 0))") }
      parts.append("\(t("Total")) \(format.quantity(level?.quantity ?? 0))")
    } else {
      parts.append(format.quantity(level?.quantity ?? 0))
    }
    return parts.joined(separator: " · ")
  }

  // MARK: Valuation

  @ViewBuilder
  private var valuation: some View {
    let one = model.one
    let format = one.format
    let books = one.acBooks
    let levels = AcStock.levels(one.records(.stockMovements), precision, asAt: asAt)
    let items = stockItems.filter { (levels[$0.rid]?.quantity ?? 0) != 0 || (levels[$0.rid]?.value ?? 0) != 0 }
    let total = items.reduce(0) { $0 + AcLedger.minor(levels[$1.rid]?.value ?? 0, precision) }
    let account = AcSpec.inventory.find(books.accounts, template: books.settings.template)
    asAtPicker()
    ListCard {
      Text(t("Stock valued at weighted average cost (IAS 2), at the end of {date}.", ["date": format.date(asAt)]))
        .font(.web(14))
        .foregroundStyle(palette.slate(500))
    } rows: {
      if items.isEmpty {
        AcCardText(t("No stock on that date."), centered: true)
      } else {
        ForEach(items.map(Rec.init)) { record in
          let level = levels[record.id]
          let unit = record.raw.text("unit").map { " \($0)" } ?? ""
          ListRow(
            title: localName(record.raw),
            subtitle:
              "\(format.quantity(level?.quantity ?? 0))\(unit) · \(t("Average cost")) \(Format.unitPrice(level?.unitCost ?? 0, currency: format.currency, locale: format.locale, display: format.display))",
            amount: format.money(level?.value ?? 0))
        }
        ListCardFooter {
          Text("\(t("Total")) \(format.acMoney(total))").foregroundStyle(palette.slate(900)).fontWeight(.semibold)
        }
      }
    }
    if let account {
      let inBooks = books.lines.reduce(0) { $1.accountId == account.id && $1.date <= asAt ? $0 + $1.amount : $0 }
      Card {
        VStack(alignment: .leading, spacing: 8) {
          Text(
            t(
              "Balance of {account} in the books: {amount}",
              ["account": "\(account.code) \(localName(account.raw))", "amount": format.acMoney(inBooks)])
          )
          .font(.web(14))
          .foregroundStyle(palette.slate(600))
          if inBooks == total {
            Badge(t("Agrees with the books"), tone: .green)
          } else {
            Badge(t("Difference of {amount}", ["amount": format.acMoney(inBooks - total)]), tone: .amber)
          }
        }
        .padding(16)
      }
    }
  }

  // MARK: Movements

  private var movementItem: String? {
    if let itemId, !itemId.isEmpty { return itemId }
    return stockItems.first?.rid
  }

  @ViewBuilder
  private var movements: some View {
    let format = model.one.format
    let item = movementItem.flatMap { model.one.record(.products, $0) }
    let rows = movementRows(item?.rid ?? "")
    let unit = item?.text("unit").map { " \($0)" } ?? ""
    Card {
      AcToolbar {
        Field(t("Item")) {
          Combobox(
            selection: $itemId,
            options: stockItems.map { ComboOption(value: $0.rid, label: localName($0), detail: $0.text("sku")) },
            placeholder: t("Choose an item…"), searchPlaceholder: t("Search items…"))
        }
        if warehouses.count > 1 { warehouseSelect }
        dateRange
      }
    }
    ListCard {
      Text(
        warehouseId.isEmpty
          ? t(
            "Every movement of {item}, with the quantity and value after each one.",
            ["item": item.map { localName($0) } ?? "—"])
          : t(
            "Every movement of {item} in {warehouse}.",
            ["item": item.map { localName($0) } ?? "—", "warehouse": warehouseName(warehouseId)])
      )
      .font(.web(14))
      .foregroundStyle(palette.slate(500))
    } rows: {
      if rows.shown.isEmpty, rows.opening == nil {
        AcCardText(t("No movements in this period."), centered: true)
      } else {
        if let opening = rows.opening {
          ListRow(
            title: t("Balance before"), subtitle: format.date(from),
            amount: "\(format.quantity(opening.quantity))\(unit)")
        }
        ForEach(rows.shown.indices, id: \.self) { index in
          movementRow(rows.shown[index], unit: unit, format: format)
        }
      }
    }
  }

  private var warehouseSelect: some View {
    Field(t("Warehouse")) {
      Select(selection: $warehouseId, options: [SelectOption("", t("All warehouses"))] + warehouseOptions)
    }
  }

  private var warehouseOptions: [SelectOption<String>] {
    warehouses.map { SelectOption($0.rid, localName($0)) }
  }

  private var dateRange: some View {
    HStack(spacing: 8) {
      Field(t("From")) { DateField(value: $from) }
      Field(t("To")) { DateField(value: $to) }
    }
  }

  private func movementRows(_ item: String)
    -> (shown: [(movement: JSONValue, quantity: Double, value: Int)], opening: (quantity: Double, value: Int)?)
  {
    let all = model.one.records(.stockMovements)
      .filter { $0.str("productId") == item && (warehouseId.isEmpty || $0.str("warehouseId") == warehouseId) }
      .sorted(by: AcStock.inOrder)
    var quantity = Decimal(0)
    var value = 0
    var opening: (quantity: Double, value: Int)?
    var shown: [(movement: JSONValue, quantity: Double, value: Int)] = []
    for movement in all {
      if !to.isEmpty, movement.str("date") > to { break }
      if !from.isEmpty, movement.str("date") < from {
        quantity += Money.dec(movement.num("quantity"))
        value += AcLedger.minor(movement.num("value"), precision)
        continue
      }
      if !from.isEmpty, opening == nil { opening = (Money.toNumber(quantity), value) }
      quantity += Money.dec(movement.num("quantity"))
      value += AcLedger.minor(movement.num("value"), precision)
      shown.append((movement, Money.toNumber(quantity), value))
    }
    if !from.isEmpty, opening == nil { opening = (Money.toNumber(quantity), value) }
    return (shown, opening)
  }

  private func movementRow(
    _ row: (movement: JSONValue, quantity: Double, value: Int), unit: String, format: CompanyFormat
  ) -> some View {
    let m = row.movement
    let q = m.num("quantity")
    var details = [format.date(m.text("date"))]
    if warehouses.count > 1, warehouseId.isEmpty { details.append(warehouseName(m.str("warehouseId"))) }
    details.append(
      "\(q > 0 ? t("In") : t("Out")) \(format.quantity(abs(q))) × \(Format.unitPrice(m.num("unitCost"), currency: format.currency, locale: format.locale, display: format.display))"
    )
    var after = "\(t("On hand")) \(format.quantity(row.quantity))\(unit)"
    if warehouseId.isEmpty {
      after += " · \(t("Stock value")) \(format.acMoney(row.value))"
    }
    return ListRow(
      title: "\(t(AcStock.movementLabel(m.str("sourceType")))) \(m.str("number"))",
      subtitle: (details + [after]).joined(separator: " · "), amount: format.money(m.num("value")),
      action: { movementLink(m) })
  }

  private func movementLink(_ m: JSONValue) {
    if let doc = m.text("documentId").flatMap({ model.one.record(.documents, $0) }), let route = AcLinks.document(doc) {
      router.push(route)
    } else if m.str("sourceType") == "issue" {
      router.push(.stockIssue(id: m.str("sourceId")))
    } else if m.str("sourceType") == "opening" || m.str("sourceType") == "adjustment" || m.str("sourceType") == "transfer" {
      router.push(.stockEntry(id: m.str("sourceId")))
    } else if m.str("sourceType") == "landed_cost" {
      router.push(.landedCost(id: m.str("sourceId")))
    }
  }

  // MARK: Low stock

  @ViewBuilder
  private var lowStock: some View {
    let one = model.one
    let format = one.format
    let levels = AcStock.levels(one.records(.stockMovements), precision)
    let live = stockItems.filter { !$0.flag("archived") }
    let tracked = live.filter { $0.number("reorderLevel") != nil }
    let low = tracked.filter { (levels[$0.rid]?.quantity ?? 0) <= ($0.number("reorderLevel") ?? 0) }
    let groups = lowGroups(low)
    Card {
      Text(
        t(
          "Stock items at or below their reorder level. The suggested order brings them to twice the reorder level."
        )
      )
      .font(.web(14))
      .foregroundStyle(palette.slate(500))
      .padding(16)
    }
    if low.isEmpty {
      Card {
        AcCardText(
          tracked.isEmpty
            ? t("Set a reorder level on your stock items to see what to reorder.")
            : t("Nothing is at or below its reorder level."), centered: true)
      }
    } else {
      ForEach(groups.indices, id: \.self) { index in
        ListCard {
          Text(vendorName(groups[index].vendor)).font(.web(16, .semibold)).foregroundStyle(palette.slate(900))
        } rows: {
          ForEach(groups[index].items.map(Rec.init)) { record in
            let onHand = levels[record.id]?.quantity ?? 0
            let unit = record.raw.text("unit").map { " \($0)" } ?? ""
            ListRow(
              title: localName(record.raw),
              subtitle:
                "\(t("On hand")) \(format.quantity(onHand)) · \(t("Reorder level")) \(format.quantity(record.raw.num("reorderLevel")))",
              amount: "\(format.quantity(suggested(record.raw, onHand)))\(unit)",
              action: { router.push(.report("stock-movements?item=\(record.id)")) })
          }
        }
      }
    }
  }

  private func suggested(_ item: JSONValue, _ onHand: Double) -> Double {
    let value = Money.dec(item.num("reorderLevel")) * 2 - Money.dec(onHand)
    return max(0, Money.toNumber(Money.round(value, 6)))
  }

  private func lowGroups(_ low: [JSONValue]) -> [(vendor: String, items: [JSONValue])] {
    var order: [String] = []
    var byVendor: [String: [JSONValue]] = [:]
    for item in low {
      let key = item.text("preferredVendorId") ?? ""
      if byVendor[key] == nil { order.append(key) }
      byVendor[key, default: []].append(item)
    }
    return order.map { (vendor: $0, items: byVendor[$0] ?? []) }
  }

  private func vendorName(_ id: String) -> String {
    if id.isEmpty { return t("No preferred vendor") }
    let name = model.one.contactName(id)
    return name.isEmpty ? t("Unknown vendor") : name
  }

  // MARK: Issued items

  @ViewBuilder
  private var issued: some View {
    let format = model.one.format
    let kept = model.one.records(.stockIssues).filter { $0.str("status") == "posted" }
    let rows = issuedRows(kept)
    let total = rows.reduce(Decimal(0)) { $0 + Money.dec($1.line.num("quantity")) }
    Card {
      AcToolbar {
        Field(t("Employee")) {
          Combobox(
            selection: $employeeId, options: employeeOptions(kept), placeholder: t("All employees"),
            searchPlaceholder: t("Search employees…"))
        }
        Field(t("Item")) {
          Combobox(
            selection: $itemId, options: itemOptions(kept), placeholder: t("All items"),
            searchPlaceholder: t("Search items…"))
        }
        if warehouses.count > 1 { warehouseSelect }
        dateRange
      }
    }
    ListCard {
      if rows.isEmpty {
        WebEmptyState(
          title: t("No items issued"), description: t("Items issued to employees and confirmed show here, line by line."))
      } else {
        ForEach(rows.indices, id: \.self) { index in
          issuedRow(rows[index].issue, rows[index].line, format: format)
        }
        ListCardFooter {
          Text("\(t("Total")) \(format.quantity(Money.toNumber(total)))").foregroundStyle(palette.slate(900))
        }
      }
    }
  }

  private func issuedRows(_ kept: [JSONValue]) -> [(issue: JSONValue, line: JSONValue)] {
    let employee = employeeId ?? ""
    let item = itemId ?? ""
    let issues = kept.filter { issue in
      (warehouseId.isEmpty || issue.str("warehouseId") == warehouseId)
        && (employee.isEmpty || issue.obj("recipient")?.str("employeeId") == employee)
        && (from.isEmpty || issue.str("date") >= from) && (to.isEmpty || issue.str("date") <= to)
    }.sorted { a, b in
      a.str("date") != b.str("date")
        ? a.str("date") > b.str("date") : AcText.compare(a.str("number"), b.str("number")) == .orderedDescending
    }
    var out: [(issue: JSONValue, line: JSONValue)] = []
    for issue in issues {
      for line in issue.list("lines") where item.isEmpty || line.str("productId") == item { out.append((issue, line)) }
    }
    return out
  }

  private func person(_ recipient: JSONValue?) -> String {
    guard let recipient else { return "" }
    let arabic = LanguageStore.shared.isArabic
    let name = (arabic ? recipient.text("nameAr") : nil) ?? recipient.str("name")
    let title = (arabic ? recipient.text("jobTitleAr") : nil) ?? recipient.str("jobTitle")
    return title.isEmpty ? name : "\(name) (\(title))"
  }

  private func employeeOptions(_ kept: [JSONValue]) -> [ComboOption] {
    var seen = Set<String>()
    var options = [ComboOption(value: "", label: t("All employees"))]
    for issue in kept {
      guard let recipient = issue.obj("recipient") else { continue }
      let id = recipient.str("employeeId")
      if seen.contains(id) { continue }
      seen.insert(id)
      options.append(ComboOption(value: id, label: person(recipient), detail: recipient.text("number")))
    }
    return options
  }

  private func itemOptions(_ kept: [JSONValue]) -> [ComboOption] {
    var seen = Set<String>()
    var options = [ComboOption(value: "", label: t("All items"))]
    let arabic = LanguageStore.shared.isArabic
    for issue in kept {
      for line in issue.list("lines") where !seen.contains(line.str("productId")) {
        seen.insert(line.str("productId"))
        options.append(
          ComboOption(value: line.str("productId"), label: (arabic ? line.text("nameAr") : nil) ?? line.str("name")))
      }
    }
    return options
  }

  private func issuedRow(_ issue: JSONValue, _ line: JSONValue, format: CompanyFormat) -> some View {
    let arabic = LanguageStore.shared.isArabic
    let name = (arabic ? line.text("nameAr") : nil) ?? line.str("name")
    var details = [format.date(issue.text("date")), issue.str("number"), warehouseName(issue.str("warehouseId"))]
    let issuer = issue.text("issuedByName") ?? ""
    if !issuer.isEmpty { details.append(issuer) }
    return ListRow(
      title: person(issue.obj("recipient")),
      subtitle: "\(name) · " + details.filter { !$0.isEmpty }.joined(separator: " · "),
      amount: "\(format.quantity(line.num("quantity"))) \(line.str("unit"))",
      action: { router.push(.stockIssue(id: issue.rid)) })
  }
}

// MARK: Auditor pack

/// `AuditorPack`: what the year's pack holds and whether the year is closed.
struct AcAuditorPack: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @State private var chosen: String?

  private static let files: [(name: String, label: String)] = [
    ("statement-of-financial-position.csv", "Statement of financial position"),
    ("statement-of-profit-or-loss.csv", "Statement of profit or loss"),
    ("statement-of-changes-in-equity.csv", "Statement of changes in equity"),
    ("statement-of-cash-flows.csv", "Statement of cash flows"),
    ("trial-balance.csv", "Trial balance"),
    ("fixed-asset-schedule.csv", "Fixed asset schedule"),
    ("general-ledger.csv", "General ledger"),
    ("receivables-aging.csv", "Receivables aging"),
    ("payables-aging.csv", "Payables aging"),
    ("fixed-asset-register.csv", "Fixed asset register"),
    ("chart-of-accounts.csv", "Chart of accounts"),
  ]

  var body: some View {
    let one = model.one
    let books = one.acBooks
    let today = AcDate.today
    let years = AcFiscal.years(books.lines.first?.date, books.fiscalYearEnd, today)
    let year = pick(years, today: today)
    let label = AcFiscal.label(year.from, year.to)
    let closed = one.records(.yearEnds).contains { $0.str("status") == "closed" && $0.str("yearEnd") == year.to }
    let locked = (books.settings.lockDate ?? "") >= year.to
    Card {
      AcToolbar {
        Field(t("Financial year")) {
          Select(
            selection: Binding(get: { chosen ?? year.to }, set: { chosen = $0 }),
            options: years.map { SelectOption($0.to, AcFiscal.label($0.from, $0.to)) })
        }
      }
      VStack(alignment: .leading, spacing: 16) {
        HStack(alignment: .top, spacing: 12) {
          IconView(.folderDown, size: 20)
            .foregroundStyle(palette.primary(600))
            .frame(width: 40, height: 40)
            .background(palette.primary(50), in: Circle())
          VStack(alignment: .leading, spacing: 2) {
            Text(t("Auditor pack for {year}", ["year": label])).font(.web(16, .semibold)).foregroundStyle(palette.slate(900))
            Text(
              t(
                "The financial statements with last year’s figures, the trial balance, the general ledger, aging and the fixed asset register, as spreadsheet files in one ZIP."
              )
            )
            .font(.web(14))
            .foregroundStyle(palette.slate(500))
          }
        }
        if closed, locked {
          AcNotice(t("This year is closed and locked, so the figures will not change."), icon: .lock, tone: .green)
        } else {
          AcNotice(
            t("This year is still open, so the figures can change."), link: t("Close the year"),
            onLink: { router.push(.yearEnd) })
        }
        VStack(spacing: 8) {
          ForEach(Self.files.indices, id: \.self) { index in
            fileRow(Self.files[index].label, Self.files[index].name)
          }
        }
      }
      .padding(20)
    }
  }

  private func pick(_ years: [AcRange], today: String) -> AcRange {
    if let chosen, let found = years.first(where: { $0.to == chosen }) { return found }
    if let ended = years.first(where: { $0.to < today }) { return ended }
    return years.first ?? AcRange(from: today, to: today)
  }

  private func fileRow(_ label: String, _ name: String) -> some View {
    HStack(spacing: 12) {
      IconView(.fileSpreadsheet, size: 16).foregroundStyle(palette[.emerald(600)])
      VStack(alignment: .leading, spacing: 1) {
        Text(t(label)).font(.web(14, .medium)).foregroundStyle(palette.slate(800))
        Text(verbatim: name).font(.web(12)).foregroundStyle(palette.slate(500)).environment(\.layoutDirection, .leftToRight)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .border(palette.slate(200), in: RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous))
  }
}
