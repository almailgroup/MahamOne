import MahamKit
import SwiftUI

// What the contact, payment, recurring, cheque and expense pages share: a
// list page with a filter (chips or a select), rows with a third line and
// a caption under the amount, figures, notes, label–value cards whose
// values can open a record, and the web's words for payment methods,
// providers, cheques and banks.

// MARK: A list page

/// The filter above a list: status chips, or a select (methods, categories).
enum CtFilter {
  case none
  case chips([ListChip])
  case select([SelectOption<String>])
}

/// A list page as the web's payment, expense and contact lists on a phone:
/// the header (title, description, the New button); with no records at all
/// the empty state with the New button; else a card with the filter and the
/// search box, the rows (the web's "No … match." when none do), "Show more"
/// after 50 and the footer (count and totals).
struct CtListPage<Row: View, Footer: View>: View {
  let title: String
  var description: String?
  let records: [Rec]
  var filter: CtFilter
  var matches: ((Rec, String) -> Bool)?
  var searchPlaceholder: String
  var searchText: ((Rec) -> String)?
  var newLabel: String?
  var onNew: (() -> Void)?
  var emptyIcon: Icon
  var emptyTitle: String
  var emptyDescription: String?
  var noMatch: String
  let row: (Rec) -> Row
  let footer: ([Rec]) -> Footer

  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette
  @State private var selection: String
  @State private var query = ""
  @State private var shown = 50

  init(
    title: String, description: String? = nil, records: [Rec], filter: CtFilter = .none, initial: String = "",
    matches: ((Rec, String) -> Bool)? = nil, searchPlaceholder: String = t("Search"),
    searchText: ((Rec) -> String)? = nil, newLabel: String? = nil, onNew: (() -> Void)? = nil,
    emptyIcon: Icon = .inbox, emptyTitle: String, emptyDescription: String? = nil, noMatch: String,
    @ViewBuilder row: @escaping (Rec) -> Row, @ViewBuilder footer: @escaping ([Rec]) -> Footer
  ) {
    self.title = title
    self.description = description
    self.records = records
    self.filter = filter
    self.matches = matches
    self.searchPlaceholder = searchPlaceholder
    self.searchText = searchText
    self.newLabel = newLabel
    self.onNew = onNew
    self.emptyIcon = emptyIcon
    self.emptyTitle = emptyTitle
    self.emptyDescription = emptyDescription
    self.noMatch = noMatch
    self.row = row
    self.footer = footer
    _selection = State(initialValue: initial)
  }

  var body: some View {
    WebPage(refresh: { [model] in await model.one.sync() }) {
      PageHeader(title, description: description) {
        newButton
      }
      content
    }
    .onChange(of: selection) { _, _ in shown = 50 }
    .onChange(of: query) { _, _ in shown = 50 }
  }

  @ViewBuilder private var newButton: some View {
    if let newLabel, let onNew {
      WebButton(newLabel, icon: .plus, haptic: .press, action: onNew)
    }
  }

  @ViewBuilder private var content: some View {
    if records.isEmpty {
      Card {
        if !model.one.hasData || isDownloading {
          DataLoadingRow()
        } else {
          WebEmptyState(icon: emptyIcon, title: emptyTitle, description: emptyDescription) {
            newButton
          }
        }
      }
    } else {
      let visible = filtered
      ListCard {
        filterView
        TextInput(text: $query, placeholder: searchPlaceholder, leadingIcon: .search)
      } rows: {
        if visible.isEmpty {
          CtEmptyText(noMatch, centered: true)
        } else {
          ForEach(visible.prefix(shown)) { record in
            row(record)
          }
          if visible.count > shown {
            ListShowMore(remaining: visible.count - shown) { shown += 50 }
          }
        }
        if Footer.self != EmptyView.self {
          ListCardFooter { footer(visible) }
        }
      }
    }
  }

  @ViewBuilder private var filterView: some View {
    switch filter {
    case .none:
      EmptyView()
    case .chips(let chips):
      Segmented(selection: $selection, options: chips.map { SegmentOption($0.id, $0.label, count: $0.count) })
    case .select(let options):
      Select(selection: $selection, options: options)
    }
  }

  private var isDownloading: Bool {
    if case .downloading = model.one.phase { return true }
    return false
  }

  private var filtered: [Rec] {
    records.filter { record in
      (matches?(record, selection) ?? true) && (query.isEmpty || (searchText?(record) ?? "").matches(query))
    }
  }
}

extension CtListPage where Footer == EmptyView {
  init(
    title: String, description: String? = nil, records: [Rec], filter: CtFilter = .none, initial: String = "",
    matches: ((Rec, String) -> Bool)? = nil, searchPlaceholder: String = t("Search"),
    searchText: ((Rec) -> String)? = nil, newLabel: String? = nil, onNew: (() -> Void)? = nil,
    emptyIcon: Icon = .inbox, emptyTitle: String, emptyDescription: String? = nil, noMatch: String,
    @ViewBuilder row: @escaping (Rec) -> Row
  ) {
    self.init(
      title: title, description: description, records: records, filter: filter, initial: initial,
      matches: matches, searchPlaceholder: searchPlaceholder, searchText: searchText, newLabel: newLabel,
      onNew: onNew, emptyIcon: emptyIcon, emptyTitle: emptyTitle, emptyDescription: emptyDescription,
      noMatch: noMatch, row: row, footer: { _ in EmptyView() })
  }
}

/// The web's quiet line where a list or a card has nothing: 14pt slate-500.
struct CtEmptyText: View {
  let text: String
  var centered: Bool
  @Environment(\.palette) private var palette

  init(_ text: String, centered: Bool = false) {
    self.text = text
    self.centered = centered
  }

  var body: some View {
    Text(text)
      .font(.web(14))
      .foregroundStyle(palette.slate(500))
      .multilineTextAlignment(centered ? .center : .leading)
      .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
      .padding(.horizontal, centered ? 24 : 20)
      .padding(.vertical, centered ? 48 : 24)
      .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }
}

// MARK: Rows

/// One row of a phone list, as the web's contact, recurring and cheque
/// cards: the title (16pt, 500), a line under it and maybe a third (12pt),
/// the badges under them (or under the amount, `trailingBadges`); the amount
/// (14pt, 600, tabular) with a caption under it at the end.
struct CtListRow<Badges: View>: View {
  let title: String
  var subtitle: String?
  var detail: String?
  var detailTone: Token?
  var amount: String?
  var amountCaption: String?
  var amountMuted: Bool
  var amountTone: Token?
  var trailingBadges: Bool
  private let badges: Badges
  var action: (() -> Void)?
  @Environment(\.palette) private var palette

  init(
    title: String, subtitle: String? = nil, detail: String? = nil, detailTone: Token? = nil,
    amount: String? = nil, amountCaption: String? = nil, amountMuted: Bool = false, amountTone: Token? = nil,
    trailingBadges: Bool = false, @ViewBuilder badges: () -> Badges, action: (() -> Void)? = nil
  ) {
    self.title = title
    self.subtitle = subtitle
    self.detail = detail
    self.detailTone = detailTone
    self.amount = amount
    self.amountCaption = amountCaption
    self.amountMuted = amountMuted
    self.amountTone = amountTone
    self.trailingBadges = trailingBadges
    self.badges = badges()
    self.action = action
  }

  var body: some View {
    Group {
      if let action {
        Button {
          Haptics.play(.tap)
          action()
        } label: {
          content
        }
        .buttonStyle(PressedFill(radius: 0, color: .slate(100)))
      } else {
        content
      }
    }
    .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }

  private var content: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.web(16, .medium))
          .foregroundStyle(palette.slate(900))
          .lineLimit(1)
        if let subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.web(12))
            .foregroundStyle(palette.slate(500))
            .lineLimit(1)
        }
        if let detail, !detail.isEmpty {
          Text(detail)
            .font(.web(12))
            .foregroundStyle(detailColor)
            .lineLimit(2)
        }
        if !trailingBadges, Badges.self != EmptyView.self {
          FlowLayout(spacing: 4, lineSpacing: 4) { badges }
            .padding(.top, 4)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if amount != nil || amountCaption != nil || trailingBadges {
        trailing.fixedSize()
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(minHeight: 56)
    .contentShape(Rectangle())
  }

  private var trailing: some View {
    VStack(alignment: .trailing, spacing: 3) {
      if let amount {
        Text(amount)
          .font(.web(14, amountMuted ? .regular : .semibold, tabular: true))
          .foregroundStyle(amountColor)
          .lineLimit(1)
          .environment(\.layoutDirection, .leftToRight)
      }
      if let amountCaption, !amountCaption.isEmpty {
        Text(amountCaption)
          .font(.web(12))
          .foregroundStyle(palette.slate(500))
          .lineLimit(1)
      }
      if trailingBadges, Badges.self != EmptyView.self {
        HStack(spacing: 4) { badges }
      }
    }
  }

  private var detailColor: Color {
    guard let detailTone else { return palette.slate(500) }
    return palette.color(detailTone)
  }

  private var amountColor: Color {
    if let amountTone { return palette.color(amountTone) }
    return amountMuted ? palette.slate(500) : palette.slate(900)
  }
}

extension CtListRow where Badges == EmptyView {
  init(
    title: String, subtitle: String? = nil, detail: String? = nil, detailTone: Token? = nil,
    amount: String? = nil, amountCaption: String? = nil, amountMuted: Bool = false, amountTone: Token? = nil,
    action: (() -> Void)? = nil
  ) {
    self.init(
      title: title, subtitle: subtitle, detail: detail, detailTone: detailTone, amount: amount,
      amountCaption: amountCaption, amountMuted: amountMuted, amountTone: amountTone, trailingBadges: false,
      badges: { EmptyView() }, action: action)
  }
}

/// A card with a title row (and actions at its end), then rows divided by
/// slate-100 lines, as the web's cards of open invoices, payments and the
/// rest.
struct CtRowsCard<Actions: View, Rows: View>: View {
  let title: String
  var description: String?
  private let actions: Actions
  private let rows: Rows

  init(
    _ title: String, description: String? = nil, @ViewBuilder actions: () -> Actions,
    @ViewBuilder rows: () -> Rows
  ) {
    self.title = title
    self.description = description
    self.actions = actions()
    self.rows = rows()
  }

  var body: some View {
    Card {
      CardHeader(title, description: description) { actions }
      VStack(spacing: 0) { rows }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, -1)
        .clipped()
    }
  }
}

extension CtRowsCard where Actions == EmptyView {
  init(_ title: String, description: String? = nil, @ViewBuilder rows: () -> Rows) {
    self.init(title, description: description, actions: { EmptyView() }, rows: rows)
  }
}

// MARK: Label and value

/// One line of a `CtInfoCard`: a label and its value; a value with a
/// `route` opens that page (primary-700, as the web's links).
struct CtRow {
  let label: String
  let value: String
  var strong = false
  var tabular = false
  var tone: Token?
  var route: Route?
  var multiline = false

  init(
    _ label: String, _ value: String, strong: Bool = false, tabular: Bool = false, tone: Token? = nil,
    route: Route? = nil, multiline: Bool = false
  ) {
    self.label = label
    self.value = value
    self.strong = strong
    self.tabular = tabular
    self.tone = tone
    self.route = route
    self.multiline = multiline
  }
}

/// A card of label–value lines (the web's details cards), with something at
/// the end of its title row (a status badge); lines without a value are
/// left out, and so is the card when none has one.
struct CtInfoCard<Accessory: View>: View {
  let title: String
  var description: String?
  let rows: [CtRow]
  private let accessory: Accessory

  init(_ title: String, description: String? = nil, rows: [CtRow], @ViewBuilder accessory: () -> Accessory) {
    self.title = title
    self.description = description
    self.rows = rows
    self.accessory = accessory()
  }

  var body: some View {
    let shown = rows.filter { !$0.value.isEmpty }
    if !shown.isEmpty {
      Card {
        CardHeader(title, description: description) { accessory }
        CtDetailRows(rows: shown, inset: 20)
          .padding(.vertical, 4)
      }
    }
  }
}

extension CtInfoCard where Accessory == EmptyView {
  init(_ title: String, description: String? = nil, rows: [CtRow]) {
    self.init(title, description: description, rows: rows) { EmptyView() }
  }
}

/// Label–value lines divided by slate-100 lines (in a card, or a dialog).
struct CtDetailRows: View {
  let rows: [CtRow]
  var inset: CGFloat = 0
  @Environment(ShellRouter.self) private var router: ShellRouter?
  @Environment(\.palette) private var palette

  var body: some View {
    let shown = rows.filter { !$0.value.isEmpty }
    VStack(spacing: 0) {
      ForEach(Array(shown.enumerated()), id: \.offset) { index, row in
        line(row)
          .overlay(alignment: .top) {
            if index > 0 { Rectangle().fill(palette.slate(100)).frame(height: 1) }
          }
      }
    }
  }

  @ViewBuilder private func line(_ row: CtRow) -> some View {
    if let route = row.route, let router {
      Button {
        Haptics.play(.tap)
        router.push(route)
      } label: {
        content(row, link: true)
      }
      .buttonStyle(PressedFill(radius: 0, color: .slate(50)))
    } else {
      content(row, link: false)
    }
  }

  private func content(_ row: CtRow, link: Bool) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(row.label)
        .font(.web(14))
        .foregroundStyle(palette.slate(500))
      Spacer(minLength: 8)
      Text(row.value)
        .font(.web(14, weight(row, link: link), tabular: row.tabular))
        .foregroundStyle(valueColor(row, link: link))
        .multilineTextAlignment(.trailing)
        .lineLimit(row.multiline ? nil : 3)
        .textSelection(.enabled)
    }
    .padding(.horizontal, inset)
    .padding(.vertical, 11)
    .contentShape(Rectangle())
  }

  private func valueColor(_ row: CtRow, link: Bool) -> Color {
    if let tone = row.tone { return palette.color(tone) }
    return link ? palette.primary(700) : palette.slate(900)
  }

  private func weight(_ row: CtRow, link: Bool) -> FontWeight {
    if link { return .medium }
    return row.strong ? .semibold : .regular
  }
}

// MARK: Figures and notes

/// How a figure reads: plain, red (overdue), green, or the primary tint of
/// a statement's balance.
enum CtTone {
  case plain, danger, success, highlight
}

/// One of the web's figure cards (`Figure`, the cheque tiles): a 12pt
/// label, the value (20pt, 600, tabular), an optional bar and a hint; with
/// `alert` the card turns red (cheques overdue). With `action` it opens
/// something (the last payment).
struct CtFigure: View {
  let label: String
  let value: String
  var hint: String?
  var tone: CtTone = .plain
  var alert = false
  /// Credit used against the limit, when there is one: used ÷ limit.
  var share: Double?
  var action: (() -> Void)?
  @Environment(\.palette) private var palette

  var body: some View {
    if let action {
      Button {
        Haptics.play(.tap)
        action()
      } label: {
        card
      }
      .buttonStyle(.plain)
    } else {
      card
    }
  }

  private var card: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.lg, style: .continuous)
    return VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.web(12, .medium))
        .foregroundStyle(labelColor)
        .lineLimit(2)
      Text(value)
        .font(.web(20, .semibold, tabular: true))
        .foregroundStyle(valueColor)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .environment(\.layoutDirection, .leftToRight)
      if let share {
        CtCreditBar(share: share).padding(.top, 4)
      }
      if let hint, !hint.isEmpty {
        Text(hint)
          .font(.web(12))
          .foregroundStyle(palette.slate(500))
          .lineLimit(3)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .padding(16)
    .background(fill, in: shape)
    .border(borderColor, in: shape)
    .boxShadow(WebShadow.xs, in: shape)
    .contentShape(shape)
  }

  private var isAlert: Bool { alert }

  private var fill: Color {
    if isAlert { return palette[.red(50)].opacity(0.6) }
    if tone == .highlight { return palette.primary(50) }
    return palette.surface
  }

  private var borderColor: Color {
    if isAlert { return palette[.red(200)] }
    if tone == .highlight { return palette.primary(200) }
    return palette.slate(200)
  }

  private var labelColor: Color {
    if isAlert { return palette[.red(700)] }
    if tone == .highlight { return palette.primary(700) }
    return palette.slate(500)
  }

  private var valueColor: Color {
    if isAlert { return palette[.red(700)] }
    switch tone {
    case .plain: return palette.slate(900)
    case .danger: return palette[.red(600)]
    case .success: return palette[.emerald(600)]
    case .highlight: return palette.primary(800)
    }
  }
}

/// Credit used against the limit, as a bar that turns amber near it and red above it.
struct CtCreditBar: View {
  let share: Double
  @Environment(\.palette) private var palette

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(palette.slate(100))
        Capsule()
          .fill(color)
          .frame(width: proxy.size.width * min(1, max(0, share)))
      }
    }
    .frame(height: 8)
    .accessibilityLabel(Text(t("Credit used")))
  }

  private var color: Color {
    if share > 1 { return palette[.red(500)] }
    if share >= 0.75 { return palette[.amber(500)] }
    return palette[.emerald(500)]
  }
}

/// Figures two to a row, as the web's grids on a phone.
struct CtFigureGrid<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    LazyVGrid(
      columns: [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)],
      alignment: .leading, spacing: 12
    ) {
      content
    }
  }
}

/// A note on a page: slate (information), amber (a warning) or red (a void payment).
struct CtNote: View {
  enum Tone { case info, warning, danger }

  let tone: Tone
  let title: String?
  let lines: [String]
  @Environment(\.palette) private var palette

  init(_ tone: Tone, title: String? = nil, lines: [String]) {
    self.tone = tone
    self.title = title
    self.lines = lines
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: tone == .danger ? WebRadius.lg : WebRadius.md, style: .continuous)
    HStack(alignment: .top, spacing: 10) {
      IconView(tone == .info ? .info : .triangleAlert, size: tone == .danger ? 20 : 16)
        .foregroundStyle(iconColor)
        .padding(.top, 1)
      VStack(alignment: .leading, spacing: 4) {
        if let title {
          Text(title).font(.web(14, .medium))
        }
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
          Text(line).font(.web(14))
        }
      }
      .foregroundStyle(textColor)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(fill, in: shape)
    .border(borderColor, in: shape)
  }

  private var fill: Color {
    switch tone {
    case .info: palette.slate(50)
    case .warning: palette[.amber(50)]
    case .danger: palette[.red(50)]
    }
  }

  private var borderColor: Color {
    switch tone {
    case .info: palette.slate(200)
    case .warning: palette[.amber(600)].opacity(0.2)
    case .danger: palette[.red(200)]
    }
  }

  private var textColor: Color {
    switch tone {
    case .info: palette.slate(600)
    case .warning: palette[.amber(900)]
    case .danger: palette[.red(900)]
    }
  }

  private var iconColor: Color {
    switch tone {
    case .info: palette.slate(600)
    case .warning: palette[.amber(900)]
    case .danger: palette[.red(500)]
    }
  }
}

// MARK: Payments

/// Payment methods and providers as the web names them (`PAYMENT_METHODS`,
/// `PAYMENT_PROVIDERS` in `src/lib/payment-methods.ts`).
enum CtPayments {
  /// A method's label in the interface language.
  static func methodLabel(_ method: String) -> String {
    switch method {
    case "bank_transfer": t("Bank transfer")
    case "knet": t("KNET")
    case "cash": t("Cash")
    case "wamd": t("WAMD")
    case "cheque": t("Cheque")
    case "link": t("Payment link")
    case "card": t("Credit card")
    case "bnpl": t("Buy now, pay later")
    case "cod": t("Cash on delivery")
    case "credit_note": t("Credit note")
    case "other": t("Other")
    case "paypal": "PayPal"
    case "stripe": "Stripe"
    case "mobile_money": t("Mobile money")
    default: method
    }
  }

  /// The methods offered for new payments, in the web's order (`offeredMethods`).
  static func offered(_ direction: PaymentDirection) -> [String] {
    direction == .received
      ? ["bank_transfer", "knet", "cash", "wamd", "cheque", "link", "card", "bnpl", "cod", "credit_note", "other"]
      : ["bank_transfer", "knet", "cash", "wamd", "cheque", "card", "credit_note", "other"]
  }

  /// A payment link or buy-now-pay-later provider's name.
  static func providerLabel(_ provider: String) -> String {
    switch provider {
    case "myfatoorah": "MyFatoorah"
    case "tap": "Tap"
    case "upayments": "UPayments"
    case "hesabe": "Hesabe"
    case "ottu": "Ottu"
    case "bank": t("Bank payment link")
    case "taly": "Taly"
    case "deema": "Deema"
    case "tabby": "Tabby"
    case "other": t("Other")
    default: provider
    }
  }

  /// Paid to a vendor (`direction: "out"`), else received.
  static func isOut(_ payment: JSONValue) -> Bool { payment.str("direction") == "out" }

  /// The page a payment opens on.
  static func direction(_ payment: JSONValue) -> PaymentDirection { isOut(payment) ? .made : .received }

  /// What is not applied to a document yet (`unappliedAmount`).
  static func unapplied(_ payment: JSONValue) -> Double {
    let rest = payment.list("allocations").reduce(Money.dec(payment.num("amount"))) { sum, allocation in
      sum - Money.dec(allocation.num("amount"))
    }
    return Money.toNumber(rest)
  }

  /// The badge of a payment (`PaymentStatusBadge`): its cheque's status, or "Voided".
  static func status(_ payment: JSONValue) -> StatusMeta? {
    if let cheque = payment.obj("cheque") {
      return StatusMeta.cheque(cheque.str("status"), outgoing: isOut(payment))
    }
    if payment.flag("voided") { return StatusMeta(label: "Voided", tone: .slate) }
    return nil
  }
}

// MARK: Cheques

/// The cheque register's rules (`src/lib/cheques.ts`, `features/cheques/register.ts`).
enum CtCheques {
  /// A bank's name from its code (`KUWAIT_BANKS`), or the text as entered.
  static func bankName(_ value: String) -> String {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let bank = Kuwait.banks.first(where: { $0.code == text.uppercased() }) else { return text }
    return Localization.language == .ar ? bank.name.ar : bank.name.en
  }

  /// Still waiting for the money: in hand (or issued) or deposited.
  static func isOpen(_ status: String) -> Bool { status == "held" || status == "deposited" }

  /// Days from today to the cheque date: positive while it is still ahead.
  static func daysToMaturity(_ date: String, today: String) -> Int {
    ISODates.daysBetween(today, date) ?? 0
  }

  /// "In 3 days", "Today", "2 days overdue" for open cheques; a dash for the rest.
  static func maturityText(_ cheque: JSONValue, today: String) -> String {
    let status = cheque.str("status")
    guard isOpen(status) else { return "—" }
    let days = daysToMaturity(cheque.str("date"), today: today)
    if days == 0 { return t("Today") }
    if days > 0 { return tp(days, "In {count} day", "In {count} days") }
    if status == "deposited" { return t("Presented") }
    return tp(-days, "{count} day overdue", "{count} days overdue")
  }

  /// Whether a cheque is shown under a filter (`matchesChequeFilter`).
  static func matches(_ cheque: JSONValue, _ filter: String, today: String) -> Bool {
    let status = cheque.str("status")
    let date = cheque.str("date")
    switch filter {
    case "open": return isOpen(status)
    case "week": return isOpen(status) && date >= today && date <= ISODates.addDays(today, 6)
    case "overdue": return status == "held" && date < today
    case "returned": return status == "returned"
    default: return true
    }
  }

  /// A payment's amount in company-currency minor units (`paymentMinor`).
  static func minor(_ record: JSONValue, companyCurrency: String, precision: Int) -> Int64 {
    let rate = record.str("currency") == companyCurrency ? 1 : record.num("exchangeRate")
    let factor = rate > 0 ? Money.dec(rate) : Decimal(1)
    return Money.toMinor(Money.dec(record.num("amount")) * factor, precision)
  }
}

/// Minor units as an amount, for `CompanyFormat.money`.
func ctMajor(_ minor: Int64, _ precision: Int) -> Double {
  Money.toNumber(Money.fromMinor(minor, precision))
}

/// The name of an account, "1010 Bank", or "—".
@MainActor
func ctAccountLabel(_ account: JSONValue?) -> String {
  guard let account else { return "—" }
  let name = localName(account)
  let code = account.str("code")
  return code.isEmpty ? name : "\(code) \(name)"
}

/// A file's size, "240 KB".
func ctFileSize(_ bytes: Double) -> String {
  if bytes <= 0 { return "" }
  if bytes < 1024 { return "\(Int(bytes)) B" }
  if bytes < 1024 * 1024 { return "\(Int((bytes / 1024).rounded())) KB" }
  let tenths = (bytes / (1024 * 1024) * 10).rounded() / 10
  return "\(tenths) MB"
}

/// Compares text as the web's `localeCompare` does (collation, not code points).
func ctCollate(_ a: String, _ b: String) -> ComparisonResult {
  a.compare(b, options: [], range: nil, locale: Locale(identifier: "en"))
}

/// Compares document and payment numbers as the web does with `{ numeric: true }`.
func ctNumeric(_ a: String, _ b: String) -> ComparisonResult {
  a.compare(b, options: [.numeric], range: nil, locale: Locale(identifier: "en"))
}
