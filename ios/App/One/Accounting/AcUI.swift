import MahamKit
import SwiftUI

// What the accounting pages share: money in minor units, the web's figures
// (`Stat`), notices, label–value lines, the period pickers, and where a
// ledger line's document opens.

// MARK: Money

extension CompanyFormat {
  /// Minor units of the company currency as money: "KD 1,234.500".
  func acMoney(_ minor: Int) -> String {
    Format.money(
      Money.fromMinor(Int64(minor), Money.precision(currency)), currency: currency, locale: locale, display: display)
  }

  /// Minor units as a plain figure, without the currency: "1,234.500".
  func acAmount(_ minor: Int) -> String {
    Format.amount(Money.fromMinor(Int64(minor), Money.precision(currency)), currency: currency, locale: locale)
  }

  /// A figure as statements show it (`statementFigure`): brackets for
  /// negatives, a dash for nothing (blank in ledgers).
  func acFigure(_ value: Int?, ledger: Bool) -> String {
    guard let value else { return "" }
    if value == 0 { return ledger ? "" : "–" }
    return value < 0 ? "(\(acAmount(-value)))" : acAmount(value)
  }

  /// An amount in whole units of the currency (UK VAT boxes 6–9).
  func acWhole(_ minor: Int) -> String {
    // The boxes are already whole units: the money without its decimals.
    let full = acMoney(minor)
    return full.replacingOccurrences(of: "\\.0+(?![0-9])", with: "", options: .regularExpression)
  }
}

// MARK: Where a line's document opens

enum AcLinks {
  /// `sourceLink`: the page of the document behind a ledger line.
  @MainActor
  static func source(_ source: AcSource, _ id: String, one: OneData) -> Route {
    switch source {
    case .invoice: .salesDocument(.invoice, id: id)
    case .credit: .salesDocument(.credit, id: id)
    case .bill: .purchaseDocument(.bill, id: id)
    case .vendorCredit: .purchaseDocument(.vendorCredit, id: id)
    case .payment: .payment(one.record(.payments, id)?.str("direction") == "out" ? .made : .received, id: id)
    case .expense: .expenses
    case .journal: .journal(id: id)
    case .stock: .stockEntry(id: id)
    case .issue: .stockIssue(id: id)
    }
  }

  /// `ledgerLink`: the general ledger of one account, over a range.
  static func ledger(_ accountId: String, _ range: AcRange? = nil) -> Route {
    var query = "account=\(accountId)"
    if let range { query += "&from=\(range.from)&to=\(range.to)" }
    return .report("general-ledger?\(query)")
  }

  /// A document's page, by its type.
  static func document(_ doc: JSONValue) -> Route? {
    let id = doc.rid
    switch doc.str("type") {
    case "invoice": return .salesDocument(.invoice, id: id)
    case "quote": return .salesDocument(.quote, id: id)
    case "credit": return .salesDocument(.credit, id: id)
    case "proforma": return .salesDocument(.proforma, id: id)
    case "sales_order": return .salesDocument(.salesOrder, id: id)
    case "delivery_note": return .salesDocument(.deliveryNote, id: id)
    case "bill": return .purchaseDocument(.bill, id: id)
    case "vendor_credit": return .purchaseDocument(.vendorCredit, id: id)
    case "purchase_order": return .purchaseDocument(.purchaseOrder, id: id)
    default: return nil
    }
  }
}

// MARK: Pieces

/// The tones of the web's notices.
enum AcTone: Sendable {
  case amber, blue, slate, green, red

  var fill: Token {
    switch self {
    case .amber: .amber(50)
    case .blue: .blue(50)
    case .slate: .slate(50)
    case .green: .emerald(50)
    case .red: .red(50)
    }
  }

  var text: Token {
    switch self {
    case .amber: .amber(900)
    case .blue: .blue(900)
    case .slate: .slate(700)
    case .green: .emerald(800)
    case .red: .red(700)
    }
  }

  var border: Token {
    switch self {
    case .amber: .amber(200)
    case .blue: .blue(100)
    case .slate: .slate(200)
    case .green: .emerald(200)
    case .red: .red(200)
    }
  }
}

/// A notice (an info, warning or lock box): an icon, the text and an optional link.
struct AcNotice: View {
  let icon: Icon
  let tone: AcTone
  let text: String
  var link: String?
  var onLink: (() -> Void)?
  @Environment(\.palette) private var palette

  init(_ text: String, icon: Icon = .info, tone: AcTone = .amber, link: String? = nil, onLink: (() -> Void)? = nil) {
    self.text = text
    self.icon = icon
    self.tone = tone
    self.link = link
    self.onLink = onLink
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.lg, style: .continuous)
    HStack(alignment: .top, spacing: 10) {
      IconView(icon, size: 16).padding(.top, 2)
      VStack(alignment: .leading, spacing: 4) {
        Text(text).font(.web(14)).fixedSize(horizontal: false, vertical: true)
        if let link, let onLink {
          Button {
            Haptics.play(.tap)
            onLink()
          } label: {
            Text(link).font(.web(14, .medium)).underline()
          }
          .buttonStyle(.plain)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .foregroundStyle(palette.color(tone.text))
    .padding(14)
    .background(palette.color(tone.fill), in: shape)
    .border(palette.color(tone.border), in: shape)
  }
}

/// The web's `Stat`: a card with a label, a figure and a hint.
struct AcStat: View {
  let label: String
  let value: String
  var hint: String?
  var tone: Token?
  @Environment(\.palette) private var palette

  init(_ label: String, value: String, hint: String? = nil, tone: Token? = nil) {
    self.label = label
    self.value = value
    self.hint = hint
    self.tone = tone
  }

  var body: some View {
    Card {
      VStack(alignment: .leading, spacing: 0) {
        Text(label).font(.web(14, .medium)).foregroundStyle(palette.slate(500))
        Text(value)
          .font(.web(24, .semibold, tabular: true))
          .foregroundStyle(tone.map { palette.color($0) } ?? palette.slate(900))
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .padding(.top, 8)
          .environment(\.layoutDirection, .leftToRight)
        if let hint {
          Text(hint).font(.web(12)).foregroundStyle(palette.slate(500)).padding(.top, 4)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(20)
    }
  }
}

/// A label at the start and a value at the end, with a line above (the web's `Figure`).
struct AcLineRow: View {
  let label: String
  let value: String
  var strong = false
  var tone: Token?
  var divider = true
  @Environment(\.palette) private var palette

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(label).font(.web(14)).foregroundStyle(palette.slate(500))
      Spacer(minLength: 8)
      Text(value)
        .font(.web(14, strong ? .semibold : .regular, tabular: true))
        .foregroundStyle(tone.map { palette.color($0) } ?? (strong ? palette.slate(900) : palette.slate(700)))
        .multilineTextAlignment(.trailing)
        .environment(\.layoutDirection, .leftToRight)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 10)
    .overlay(alignment: .top) {
      if divider { Rectangle().fill(palette.slate(100)).frame(height: 1) }
    }
  }
}

/// A plain line of text in a card (an empty card's message).
struct AcCardText: View {
  let text: String
  var centered = false
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
      .padding(.horizontal, 20)
      .padding(.vertical, centered ? 40 : 20)
  }
}

/// "Payroll isn’t included in what you see." for staff and viewers (`PayrollNotIncluded`).
struct AcPayrollNote: View {
  @Environment(SuiteState.self) private var suite: SuiteState?
  @Environment(\.palette) private var palette

  var body: some View {
    if let role = suite?.role, role == .staff || role == .viewer {
      HStack(alignment: .top, spacing: 8) {
        IconView(.info, size: 16).foregroundStyle(palette.slate(400)).padding(.top, 2)
        Text(t("Payroll isn’t included in what you see.")).font(.web(14)).foregroundStyle(palette.slate(600))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(palette.slate(50), in: RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous))
      .border(palette.slate(200), in: RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous))
      .padding(.bottom, 16)
    }
  }
}

/// A heading inside a card's list: 12pt uppercase slate-500.
struct AcGroupHeading: View {
  let title: String
  @Environment(\.palette) private var palette

  var body: some View {
    Text(title.uppercased())
      .font(.web(12, .semibold))
      .tracking(0.3)
      .foregroundStyle(palette.slate(500))
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.top, 16)
      .padding(.bottom, 8)
      .background(palette.slate(50).opacity(0.4))
      .overlay(alignment: .top) { Rectangle().fill(palette.slate(200)).frame(height: 1) }
  }
}

/// A tappable row of a card that opens a page.
struct AcTapRow<Content: View>: View {
  let action: (() -> Void)?
  let content: Content
  @Environment(\.palette) private var palette

  init(action: (() -> Void)?, @ViewBuilder content: () -> Content) {
    self.action = action
    self.content = content()
  }

  var body: some View {
    Group {
      if let action {
        Button {
          Haptics.play(.tap)
          action()
        } label: {
          content.contentShape(Rectangle())
        }
        .buttonStyle(PressedFill(radius: 0, color: .slate(100)))
      } else {
        content
      }
    }
    .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }
}

// MARK: Periods

/// The statements' periods (`PERIODS` in financial.tsx).
enum AcPeriods {
  static let statement: [(value: String, label: String)] = [
    ("this-year", "This financial year"), ("last-year", "Last financial year"), ("this-quarter", "This quarter"),
    ("last-quarter", "Last quarter"), ("this-month", "This month"), ("last-month", "Last month"),
    ("custom", "Custom dates"),
  ]

  /// `AS_OF`.
  static let asOf: [(value: String, label: String)] = [
    ("today", "Today"), ("last-month", "End of last month"), ("last-quarter", "End of last quarter"),
    ("year-end", "End of this financial year"), ("last-year", "End of last financial year"),
    ("custom", "Custom date"),
  ]
}

/// A preset select and, for custom dates, the two dates.
struct AcRangePicker: View {
  @Binding var preset: String
  @Binding var custom: AcRange
  let options: [(value: String, label: String)]
  @Environment(\.palette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Select(selection: $preset, options: selectOptions)
      if preset == "custom" {
        HStack(spacing: 8) {
          DateField(value: fromBinding, required: true)
          Text(verbatim: "–").foregroundStyle(palette.slate(500))
          DateField(value: toBinding, required: true)
        }
      }
    }
  }

  private var selectOptions: [SelectOption<String>] {
    options.map { SelectOption($0.value, t($0.label)) }
  }

  private var fromBinding: Binding<String> {
    Binding(
      get: { custom.from },
      set: { value in if !value.isEmpty { custom = AcRange(from: value, to: custom.to) } })
  }

  private var toBinding: Binding<String> {
    Binding(
      get: { custom.to },
      set: { value in if !value.isEmpty { custom = AcRange(from: custom.from, to: value) } })
  }
}

/// An "as at" select and, for a custom date, the date.
struct AcAsOfPicker: View {
  @Binding var preset: String
  @Binding var custom: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Select(selection: $preset, options: AcPeriods.asOf.map { SelectOption($0.value, t($0.label)) })
      if preset == "custom" {
        DateField(value: $custom, required: true)
      }
    }
  }
}

/// The toolbar of a report: its controls stacked, a line below.
struct AcToolbar<Content: View>: View {
  let content: Content
  @Environment(\.palette) private var palette

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) { content }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
      .overlay(alignment: .bottom) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }
}
