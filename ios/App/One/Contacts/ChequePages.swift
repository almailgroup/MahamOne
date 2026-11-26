import MahamKit
import SwiftUI

// The cheque register (`src/apps/books/pages/cheques/index.tsx`): cheques
// received and issued (payments by cheque) and security cheques, and the
// cheque layouts (`cheques/layouts.tsx`, `src/lib/cheque-layouts.ts`).

/// Open cheques falling due in a window: how many, and their total in
/// company-currency minor units.
struct CtMaturity {
  var count = 0
  var amount: Int64 = 0
}

/// `/cheques`: Cheques received / Cheques issued / Security cheques.
struct CtChequesPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @State private var tab = "received"
  @State private var filter = "open"
  @State private var heldOnly = "held"
  @State private var query = ""
  @State private var shown = 50

  init() {}

  var body: some View {
    let one = model.one
    let received = cheques(out: false)
    let issued = cheques(out: true)
    let security = one.records(.securityCheques)
    let held = security.filter { $0.str("status") == "held" }
    WebPage(refresh: { [model] in await model.one.sync() }) {
      PageHeader(
        t("Cheques"), description: t("Post-dated cheques received and issued, and security cheques you hold.")
      ) {
        headerActions
      }
      Segmented(
        selection: $tab,
        options: [
          SegmentOption("received", t("Cheques received"), count: received.filter { isOpen($0) }.count),
          SegmentOption("issued", t("Cheques issued"), count: issued.filter { isOpen($0) }.count),
          SegmentOption("security", t("Security cheques"), count: held.count),
        ]
      )
      .padding(.bottom, 20)
      if tab == "security" {
        securityTab(security, held: held)
      } else {
        register(tab == "issued" ? issued : received, outgoing: tab == "issued")
      }
    }
    .onChange(of: tab) { _, _ in shown = 50 }
    .onChange(of: filter) { _, _ in shown = 50 }
    .onChange(of: query) { _, _ in shown = 50 }
  }

  @ViewBuilder private var headerActions: some View {
    if tab == "issued", model.one.company?.flag("chequePrinting") == true {
      WebButton(t("Cheque layouts"), icon: .layoutTemplate, variant: .outline) { router.push(.chequeLayouts) }
    }
    newAction
  }

  /// Record a cheque received or issued (security cheques are added on the web).
  @ViewBuilder private var newAction: some View {
    if tab == "issued" {
      WebButton(t("Record cheque issued"), icon: .plus, haptic: .press) { router.push(.newPayment(.made)) }
    } else if tab == "received" {
      WebButton(t("Record cheque received"), icon: .plus, haptic: .press) { router.push(.newPayment(.received)) }
    }
  }

  /// Payments with a tracked cheque, received or issued (`chequePayments`).
  private func cheques(out: Bool) -> [JSONValue] {
    model.one.records(.payments).filter { payment in
      payment.str("method") == "cheque" && payment.obj("cheque") != nil && CtPayments.isOut(payment) == out
    }
  }

  private func isOpen(_ payment: JSONValue) -> Bool {
    CtCheques.isOpen(payment.obj("cheque")?.str("status") ?? "")
  }

  private var companyCurrency: String { model.one.format.currency }
  private var precision: Int { Money.precision(companyCurrency) }

  private func companyMoney(_ minor: Int64) -> String {
    model.one.format.money(ctMajor(minor, precision), companyCurrency)
  }

  // MARK: Received and issued

  @ViewBuilder private func register(_ list: [JSONValue], outgoing: Bool) -> some View {
    let today = DocRules.today
    let strip = maturity(list, today: today)
    CtFigureGrid {
      CtFigure(
        label: outgoing ? t("Past date, not cleared") : t("Overdue to deposit"), value: companyMoney(strip[0].amount),
        hint: tp(strip[0].count, "{count} cheque", "{count} cheques"), alert: strip[0].count > 0)
      CtFigure(
        label: t("Due today"), value: companyMoney(strip[1].amount),
        hint: tp(strip[1].count, "{count} cheque", "{count} cheques"))
      CtFigure(
        label: t("Next 7 days"), value: companyMoney(strip[2].amount),
        hint: tp(strip[2].count, "{count} cheque", "{count} cheques"))
      CtFigure(
        label: t("Next 30 days"), value: companyMoney(strip[3].amount),
        hint: tp(strip[3].count, "{count} cheque", "{count} cheques"))
    }
    .padding(.bottom, 20)
    if list.isEmpty {
      Card {
        if !model.one.hasData {
          DataLoadingRow()
        } else {
          WebEmptyState(
            icon: .banknote, title: outgoing ? t("No cheques issued yet") : t("No cheques received yet"),
            description: outgoing
              ? t("Pay a bill by cheque to follow it here until the vendor presents it.")
              : t(
                "Record a payment by cheque to follow it here until it clears. Post-dated cheques show when they can be deposited."
              )
          ) {
            newAction
          }
        }
      }
    } else {
      let rows = self.rows(list, today: today)
      ListCard {
        Segmented(selection: $filter, options: filters(outgoing: outgoing), small: true)
        TextInput(text: $query, placeholder: t("Search cheques…"), leadingIcon: .search)
      } rows: {
        if rows.isEmpty {
          CtEmptyText(t("No cheques match."), centered: true)
        } else {
          ForEach(rows.prefix(shown).map(Rec.init)) { record in
            CtChequeRow(payment: record.raw, outgoing: outgoing, today: today)
          }
          if rows.count > shown {
            ListShowMore(remaining: rows.count - shown) { shown += 50 }
          }
        }
        ListCardFooter {
          Text(tp(rows.count, "{count} cheque", "{count} cheques"))
          HStack(spacing: 4) {
            Text(t("Total"))
            Text(companyMoney(total(rows)))
              .foregroundStyle(palette.slate(900))
              .fontWeight(.semibold)
              .environment(\.layoutDirection, .leftToRight)
          }
        }
      }
    }
  }

  private func filters(outgoing: Bool) -> [SegmentOption<String>] {
    [
      SegmentOption("open", t("Open")),
      SegmentOption("week", t("Due in 7 days")),
      SegmentOption("overdue", outgoing ? t("Past date") : t("Overdue to deposit")),
      SegmentOption("returned", t("Returned")),
      SegmentOption("all", t("All")),
    ]
  }

  /// The cheques under the filter and search: open ones soonest first, the rest newest first.
  private func rows(_ list: [JSONValue], today: String) -> [JSONValue] {
    let one = model.one
    let matching = list.filter { payment in
      guard let cheque = payment.obj("cheque"), CtCheques.matches(cheque, filter, today: today) else { return false }
      return query.isEmpty || CtChequesPage.searchText(payment, cheque: cheque, one: one).matches(query)
    }
    let ascending = filter == "open" || filter == "week" || filter == "overdue"
    return matching.sorted { a, b in
      let (da, db) = (a.obj("cheque")?.str("date") ?? "", b.obj("cheque")?.str("date") ?? "")
      return ascending ? da < db : da > db
    }
  }

  static func searchText(_ payment: JSONValue, cheque: JSONValue, one: OneData) -> String {
    let contact = one.record(.clients, payment.str("clientId"))
    return [
      cheque.str("number"), cheque.str("drawer"), payment.str("number"), contact?.str("name") ?? "",
      contact?.str("nameAr") ?? "", CtCheques.bankName(cheque.str("bank")), cheque.str("bank"),
    ].joined(separator: " ")
  }

  /// Overdue, due today, the next 7 days and the next 30 (`maturity`).
  private func maturity(_ list: [JSONValue], today: String) -> [CtMaturity] {
    let currency = companyCurrency
    let places = precision
    var result = [CtMaturity(), CtMaturity(), CtMaturity(), CtMaturity()]
    let week = ISODates.addDays(today, 6)
    let month = ISODates.addDays(today, 29)
    for payment in list {
      guard let cheque = payment.obj("cheque") else { continue }
      let status = cheque.str("status")
      guard CtCheques.isOpen(status) else { continue }
      let date = cheque.str("date")
      let amount = CtCheques.minor(payment, companyCurrency: currency, precision: places)
      if status == "held", date < today { add(&result[0], amount) }
      if date == today { add(&result[1], amount) }
      if date >= today, date <= week { add(&result[2], amount) }
      if date >= today, date <= month { add(&result[3], amount) }
    }
    return result
  }

  private func add(_ bucket: inout CtMaturity, _ amount: Int64) {
    bucket.count += 1
    bucket.amount += amount
  }

  /// What the shown cheques add up to, void ones left out.
  private func total(_ rows: [JSONValue]) -> Int64 {
    let currency = companyCurrency
    let places = precision
    return rows.filter { !$0.flag("voided") }.reduce(Int64(0)) { sum, payment in
      sum + CtCheques.minor(payment, companyCurrency: currency, precision: places)
    }
  }

  // MARK: Security cheques

  @ViewBuilder private func securityTab(_ security: [JSONValue], held: [JSONValue]) -> some View {
    let currency = companyCurrency
    let places = precision
    let heldTotal = held.filter { $0.str("currency") == currency }.reduce(Int64(0)) { sum, cheque in
      sum + CtCheques.minor(cheque, companyCurrency: currency, precision: places)
    }
    Card {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          IconView(.shieldCheck, size: 16).foregroundStyle(palette[.amber(500)])
          Text(t("Held as security")).foregroundStyle(palette.slate(600))
        }
        .font(.web(14))
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Text(companyMoney(heldTotal))
            .font(.web(18, .semibold, tabular: true))
            .foregroundStyle(palette.slate(900))
            .environment(\.layoutDirection, .leftToRight)
          Text(tp(held.count, "{count} cheque", "{count} cheques"))
            .font(.web(14))
            .foregroundStyle(palette.slate(500))
        }
        Text(t("Not in the books until cashed."))
          .font(.web(14))
          .foregroundStyle(palette.slate(500))
      }
      .padding(16)
    }
    .padding(.bottom, 20)
    if security.isEmpty {
      Card {
        if !model.one.hasData {
          DataLoadingRow()
        } else {
          WebEmptyState(
            icon: .shieldCheck, title: t("No security cheques"),
            description: t(
              "Keep guarantee cheques here, such as rent deposits. They stay off the books, and only become a payment if you cash them."
            ))
        }
      }
    } else {
      let rows = securityRows(security)
      ListCard {
        Segmented(
          selection: $heldOnly, options: [SegmentOption("held", t("Held")), SegmentOption("all", t("All"))],
          small: true)
        TextInput(text: $query, placeholder: t("Search cheques…"), leadingIcon: .search)
      } rows: {
        if rows.isEmpty {
          CtEmptyText(t("No cheques match."), centered: true)
        } else {
          ForEach(rows.map(Rec.init)) { record in
            CtSecurityChequeRow(cheque: record.raw)
          }
        }
      }
    }
  }

  /// Held ones (or all), newest first.
  private func securityRows(_ security: [JSONValue]) -> [JSONValue] {
    let one = model.one
    return security
      .filter { heldOnly == "all" || $0.str("status") == "held" }
      .filter { query.isEmpty || CtChequesPage.securitySearch($0, one: one).matches(query) }
      .sorted { a, b in
        (a.text("date") ?? a.str("createdAt")) > (b.text("date") ?? b.str("createdAt"))
      }
  }

  static func securitySearch(_ cheque: JSONValue, one: OneData) -> String {
    let contact = cheque.text("clientId").flatMap { one.record(.clients, $0) }
    return [
      cheque.str("number"), cheque.str("drawer"), cheque.str("purpose"), contact?.str("name") ?? "",
      contact?.str("nameAr") ?? "", CtCheques.bankName(cheque.str("bank")),
    ].joined(separator: " ")
  }
}

/// A cheque in the register: its number and status; the drawer (or payee);
/// "date · days to maturity · bank"; the amount. It opens its payment.
struct CtChequeRow: View {
  let payment: JSONValue
  let outgoing: Bool
  let today: String
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let cheque = payment.obj("cheque") ?? .object([:])
    let format = model.one.format
    let party = model.one.contactName(payment.text("clientId"))
    let status = cheque.str("status")
    let late = status == "held" && CtCheques.daysToMaturity(cheque.str("date"), today: today) < 0
    CtListRow(
      title: cheque.str("number"), subtitle: cheque.text("drawer") ?? (party.isEmpty ? "—" : party),
      detail: detail(cheque, format: format), detailTone: late ? .red(600) : nil,
      amount: format.money(payment.num("amount"), payment.text("currency")), amountMuted: payment.flag("voided")
    ) {
      Badge(status: StatusMeta.cheque(status, outgoing: outgoing))
      if cheque.text("replacedById") != nil { Badge(t("Replaced"), tone: .gray) }
    } action: {
      router.push(.payment(outgoing ? .made : .received, id: payment.rid))
    }
  }

  private func detail(_ cheque: JSONValue, format: CompanyFormat) -> String {
    var parts = [format.date(cheque.text("date")), CtCheques.maturityText(cheque, today: today)]
    if let bank = cheque.text("bank") { parts.append(CtCheques.bankName(bank)) }
    if cheque.str("status") == "returned", let reason = cheque.text("returnReason") { parts.append(reason) }
    return parts.filter { !$0.isEmpty }.joined(separator: " · ")
  }
}

/// A security cheque: its number, status and "Given"; who signed it (or
/// holds it) and what it guarantees; date, bank and when it was given back
/// or cashed; the amount. A cashed one opens its payment.
struct CtSecurityChequeRow: View {
  let cheque: JSONValue
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let format = model.one.format
    let party = model.one.contactName(cheque.text("clientId"))
    let who = cheque.text("drawer") ?? (party.isEmpty ? "—" : party)
    let subtitle = [who, cheque.str("purpose")].filter { !$0.isEmpty }.joined(separator: " · ")
    CtListRow(
      title: cheque.str("number"), subtitle: subtitle, detail: detail(format),
      amount: format.money(cheque.num("amount"), cheque.text("currency")),
      badges: {
        Badge(status: StatusMeta.securityCheque(cheque.str("status")))
        if cheque.str("direction") == "out" { Badge(t("Given")) }
      },
      action: openPayment)
  }

  /// A cashed cheque opens the payment it became.
  private var openPayment: (() -> Void)? {
    guard let paymentId = cheque.text("paymentId") else { return nil }
    let direction: PaymentDirection = cheque.str("direction") == "out" ? .made : .received
    return { router.push(.payment(direction, id: paymentId)) }
  }

  private func detail(_ format: CompanyFormat) -> String {
    var parts = [cheque.text("date").map { format.date($0) } ?? t("Undated")]
    if let bank = cheque.text("bank") { parts.append(CtCheques.bankName(bank)) }
    let status = cheque.str("status")
    if status == "returned", let date = cheque.text("returnedOn") {
      parts.append(t("Given back on {date}", ["date": format.date(date)]))
    }
    if status == "cashed", let date = cheque.text("cashedOn") {
      parts.append(t("Cashed on {date}", ["date": format.date(date)]))
    }
    return parts.joined(separator: " · ")
  }
}

// MARK: Cheque layouts

/// A field's box on a leaf, in millimetres from its top left corner.
struct CtLayoutField: Identifiable {
  let key: String
  let label: String
  let x: CGFloat
  let y: CGFloat
  let width: CGFloat
  let height: CGFloat
  var id: String { key }
}

/// Where a bank's cheque leaf takes each field (`ChequeLayout`).
struct CtLayout {
  var bank: String
  var name: String
  var nameAr: String
  var width: CGFloat
  var height: CGFloat
  var offsetX: CGFloat = 0
  var offsetY: CGFloat = 0
  var fields: [CtLayoutField] = []
  var dateStyle = "slashes"
  var wordsLanguage = "ar"
  var prefix = ""
  var guardText = "**"
  var calibrated = false
  /// The company's own layout, not the built-in one.
  var own = false
}

/// The layouts: the built-in Burgan Bank and KFH ones, replaced by the
/// company's own (`src/lib/cheque-layouts.ts`).
enum CtLayouts {
  static let presetBanks = ["BRGN", "KFHO"]

  /// The fields in the order they are shown, with their labels.
  static let fieldKeys = ["date", "payee", "wordsLine1", "wordsLine2", "figures", "crossing"]

  static func fieldLabel(_ key: String) -> String {
    switch key {
    case "date": t("Date")
    case "payee": t("Pay to")
    case "wordsLine1": t("Amount in words, line 1")
    case "wordsLine2": t("Amount in words, line 2")
    case "figures": t("Amount in figures")
    default: t("A/C payee only")
    }
  }

  /// Banks with a layout: the built-in ones, then any other the company made one for.
  static func banks(_ saved: [JSONValue]) -> [String] {
    var banks = presetBanks
    for layout in saved where !layout.flag("archived") {
      let code = layout.str("bank").trimmingCharacters(in: .whitespaces).uppercased()
      if !code.isEmpty, !banks.contains(code) { banks.append(code) }
    }
    return banks
  }

  /// The layout a cheque on `bank` prints with (`layoutFor`).
  static func layout(for bank: String, saved: [JSONValue]) -> CtLayout? {
    let code = bank.trimmingCharacters(in: .whitespaces).uppercased()
    let own =
      saved
      .filter { !$0.flag("archived") && $0.str("bank").trimmingCharacters(in: .whitespaces).uppercased() == code }
      .sorted { $0.str("updatedAt") > $1.str("updatedAt") }
      .first
    if let own { return read(own) }
    return preset(code)
  }

  private static func read(_ record: JSONValue) -> CtLayout {
    let size = record.obj("size")
    let offset = record.obj("offset")
    let figures = record.obj("figures")
    var layout = CtLayout(
      bank: record.str("bank"), name: record.str("name"), nameAr: record.str("nameAr"),
      width: CGFloat(size?.num("width") ?? 0), height: CGFloat(size?.num("height") ?? 0))
    layout.offsetX = CGFloat(offset?.num("x") ?? 0)
    layout.offsetY = CGFloat(offset?.num("y") ?? 0)
    layout.dateStyle = record.str("dateStyle")
    layout.wordsLanguage = record.str("wordsLanguage")
    layout.prefix = figures?.str("prefix") ?? ""
    layout.guardText = figures?.str("guard") ?? ""
    layout.calibrated = record.flag("calibrated")
    layout.own = true
    let boxes = record.obj("fields")
    layout.fields = fieldKeys.compactMap { key in
      guard let box = boxes?.obj(key) else { return nil }
      return CtLayoutField(
        key: key, label: fieldLabel(key), x: CGFloat(box.num("x")), y: CGFloat(box.num("y")),
        width: CGFloat(box.num("width")), height: CGFloat(box.num("height")))
    }
    return layout
  }

  /// The built-in layouts, not yet measured on real leaves.
  private static func preset(_ code: String) -> CtLayout? {
    let bank = Kuwait.banks.first { $0.code == code }
    func box(_ key: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CtLayoutField {
      CtLayoutField(key: key, label: fieldLabel(key), x: x, y: y, width: width, height: height)
    }
    switch code {
    case "BRGN":
      var layout = CtLayout(
        bank: code, name: bank?.name.en ?? code, nameAr: bank?.name.ar ?? code, width: 178, height: 82)
      layout.fields = [
        box("date", 128, 8, 44, 7), box("payee", 24, 22, 112, 7), box("wordsLine1", 30, 31, 106, 7),
        box("wordsLine2", 8, 39, 128, 7), box("figures", 138, 31, 34, 8), box("crossing", 6, 4, 42, 9),
      ]
      layout.dateStyle = "boxes"
      return layout
    case "KFHO":
      var layout = CtLayout(
        bank: code, name: bank?.name.en ?? code, nameAr: bank?.name.ar ?? code, width: 175, height: 80)
      layout.fields = [
        box("date", 130, 9, 38, 7), box("payee", 22, 23, 112, 7), box("wordsLine1", 28, 32, 106, 7),
        box("wordsLine2", 8, 40, 126, 7), box("figures", 136, 32, 33, 8), box("crossing", 6, 4, 42, 9),
      ]
      return layout
    default:
      return nil
    }
  }
}

/// `/cheques/layouts`: each bank's leaf, where it takes each field, drawn to scale.
struct CtChequeLayoutsPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @State private var bank = ""

  init() {}

  var body: some View {
    let one = model.one
    let format = one.format
    let saved = one.records(.chequeLayouts)
    let banks = CtLayouts.banks(saved)
    let chosen = banks.contains(bank) ? bank : (banks.first ?? "BRGN")
    let layout = CtLayouts.layout(for: chosen, saved: saved)
    WebPage(spacing: 0, refresh: { [model] in await model.one.sync() }) {
      PageHeader(
        t("Cheque layouts"),
        description: t(
          "Where each bank’s cheque leaf takes the date, the payee and the amount, for printing cheques issued."),
        breadcrumb: t("Cheques"),
        onBreadcrumb: {
          if router.path.isEmpty { router.go(.cheques) } else { router.back() }
        })
      if one.company?.flag("chequePrinting") != true {
        CtNote(
          .info,
          lines: [t("Cheque printing is off. The owner turns it on in {place}.", ["place": t("Settings → Payment details")])]
        )
        .padding(.bottom, 16)
      }
      Segmented(
        selection: Binding(get: { chosen }, set: { bank = $0 }),
        options: banks.map { SegmentOption($0, CtCheques.bankName($0)) }
      )
      .padding(.bottom, 20)
      if let layout {
        VStack(alignment: .leading, spacing: 24) {
          Card {
            CardHeader(t("Preview"), description: t("Measured from the top left corner of the leaf, in millimetres."))
            CtLeafPreview(layout: layout)
              .padding(16)
          }
          CtInfoCard(t("Leaf"), rows: leafRows(layout, format: format))
          CtLayoutFieldsCard(layout: layout, format: format)
          CtNote(
            .info,
            lines: [
              layout.own
                ? t("This company’s layout prints cheques on this bank.")
                : t("The built-in layout prints cheques on this bank.")
            ])
        }
      }
    }
  }

  private func leafRows(_ layout: CtLayout, format: CompanyFormat) -> [CtRow] {
    let mm = { (value: CGFloat) in format.quantity(Double(value)) }
    var rows: [CtRow] = []
    rows.append(CtRow(t("Name"), layout.name))
    rows.append(CtRow(t("Name in Arabic"), layout.nameAr))
    rows.append(CtRow(t("Width (mm)"), mm(layout.width), tabular: true))
    rows.append(CtRow(t("Height (mm)"), mm(layout.height), tabular: true))
    rows.append(CtRow(t("Move every field right (mm)"), mm(layout.offsetX), tabular: true))
    rows.append(CtRow(t("Move every field down (mm)"), mm(layout.offsetY), tabular: true))
    rows.append(CtRow(t("Amount in words"), layout.wordsLanguage == "en" ? t("English") : t("Arabic")))
    rows.append(CtRow(t("Date written as"), layout.dateStyle == "boxes" ? t("One digit per box") : "12/10/2026"))
    rows.append(CtRow(t("Before the figures"), layout.prefix))
    rows.append(CtRow(t("Around the figures"), layout.guardText))
    rows.append(CtRow(t("Checked against a real leaf"), layout.calibrated ? t("Yes") : t("No")))
    return rows
  }
}

/// Each field's place: from the left, from the top, width and height.
struct CtLayoutFieldsCard: View {
  let layout: CtLayout
  let format: CompanyFormat
  @Environment(\.palette) private var palette

  var body: some View {
    Card {
      CardHeader(t("Fields"))
      VStack(spacing: 0) {
        ForEach(Array(layout.fields.enumerated()), id: \.offset) { index, field in
          VStack(alignment: .leading, spacing: 2) {
            Text(field.label)
              .font(.web(14, .medium))
              .foregroundStyle(palette.slate(700))
            Text(measures(field))
              .font(.web(12, tabular: true))
              .foregroundStyle(palette.slate(500))
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 20)
          .padding(.vertical, 10)
          .overlay(alignment: .top) {
            if index > 0 { Rectangle().fill(palette.slate(100)).frame(height: 1) }
          }
        }
      }
      .padding(.vertical, 4)
    }
  }

  private func measures(_ field: CtLayoutField) -> String {
    let mm = { (value: CGFloat) in format.quantity(Double(value)) }
    return [
      "\(t("From the left")) \(mm(field.x))", "\(t("From the top")) \(mm(field.y))",
      "\(t("Width")) \(mm(field.width))", "\(t("Height")) \(mm(field.height))",
    ].joined(separator: " · ")
  }
}

/// The leaf drawn to scale with each field's box (it doesn't turn round in Arabic).
struct CtLeafPreview: View {
  let layout: CtLayout
  @Environment(\.palette) private var palette

  var body: some View {
    let ratio = layout.height > 0 ? layout.width / layout.height : 2
    GeometryReader { proxy in
      let scale = layout.width > 0 ? proxy.size.width / layout.width : 1
      ZStack(alignment: .topLeading) {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(palette.surface)
          .border(palette.slate(300), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        ForEach(layout.fields) { field in
          box(field, scale: scale)
        }
      }
    }
    .aspectRatio(ratio, contentMode: .fit)
    .padding(12)
    .background(palette.slate(100), in: RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous))
    .environment(\.layoutDirection, .leftToRight)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(t("Preview")))
  }

  private func box(_ field: CtLayoutField, scale: CGFloat) -> some View {
    Text(field.label)
      .font(.web(8, .medium))
      .foregroundStyle(palette.primary(700))
      .lineLimit(1)
      .minimumScaleFactor(0.5)
      .padding(.horizontal, 2)
      .frame(width: max(1, field.width * scale), height: max(1, field.height * scale), alignment: .leading)
      .background(palette.primary(50).opacity(0.7))
      .overlay {
        Rectangle().strokeBorder(palette.primary(400), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
      }
      .offset(x: (field.x + layout.offsetX) * scale, y: (field.y + layout.offsetY) * scale)
  }
}
