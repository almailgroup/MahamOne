import MahamKit
import SwiftUI

// What every Maham One page builds on: reading fields of raw records, the
// company's way of writing money and dates, a list page and a detail page
// laid out as the web lays them out on a phone. Records stay raw JSON (as
// the sync engine keeps them); pages only read them.

// MARK: Reading records

extension JSONValue {
  /// A text field ("" when missing).
  func str(_ key: String) -> String { self[key]?.string ?? "" }
  /// A text field, nil when missing or empty.
  func text(_ key: String) -> String? {
    guard let value = self[key]?.string, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    return value
  }
  /// A number field (0 when missing).
  func num(_ key: String) -> Double { self[key]?.double ?? 0 }
  /// A number field, nil when missing.
  func number(_ key: String) -> Double? { self[key]?.double }
  /// A yes/no field (false when missing).
  func flag(_ key: String) -> Bool { self[key]?.bool ?? false }
  /// A list field (empty when missing).
  func list(_ key: String) -> [JSONValue] { self[key]?.array ?? [] }
  /// A nested object, nil when missing.
  func obj(_ key: String) -> JSONValue? {
    guard let value = self[key], value.object != nil else { return nil }
    return value
  }
  /// The record's id.
  var rid: String { str("id") }
}

/// A raw record with its id, for lists (`ForEach`).
struct Rec: Identifiable, Hashable {
  let raw: JSONValue
  var id: String { raw.rid }

  init(_ raw: JSONValue) { self.raw = raw }

  static func == (a: Rec, b: Rec) -> Bool { a.id == b.id }
  func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: The company's formats

/// Money and dates the way the company writes them (its currency, locale,
/// date format and currency display), in the interface language.
struct CompanyFormat {
  let currency: String
  let locale: FormatLocale
  let dateFormat: Format.DateFormat
  let display: Format.CurrencyDisplay

  @MainActor
  init(company: JSONValue?) {
    currency = company?.text("currency") ?? "KWD"
    locale = Localization.formatLocale(companyLocale: company?.text("locale"))
    dateFormat = Format.DateFormat(company?.text("dateFormat") ?? "dd/MM/yyyy")
    display = Format.CurrencyDisplay(rawValue: company?.str("currencyDisplay") ?? "") ?? .local
  }

  /// "KD 1,234.500", in `currency` or the company's own.
  func money(_ amount: Double, _ currency: String? = nil) -> String {
    let code = (currency?.isEmpty == false ? currency : nil) ?? self.currency
    return Format.money(amount, currency: code, locale: locale, display: display)
  }

  /// "25/11/2026" ("" when there is no date).
  func date(_ value: String?) -> String {
    Format.date(value, format: dateFormat, locale: locale)
  }

  /// "25/11/2026, 3:40 PM" for a timestamp.
  func dateTime(_ value: String?) -> String {
    Format.dateTime(value, locale: locale, dateFormat: dateFormat)
  }

  /// "3.5", "12".
  func quantity(_ value: Double) -> String {
    Format.quantity(value, locale: locale)
  }

  /// "5%".
  func percent(_ value: Double) -> String {
    Format.percent(value, locale: locale)
  }

  /// "1,234".
  func count(_ value: Int) -> String {
    Format.number(value, locale: locale)
  }
}

extension OneData {
  /// How the company writes money and dates.
  var format: CompanyFormat { CompanyFormat(company: company) }

  /// A contact's name (clients and vendors share `clients`).
  func contactName(_ id: String?) -> String {
    guard let id, !id.isEmpty, let contact = record(.clients, id) else { return "" }
    return LanguageStore.shared.isArabic ? (contact.text("nameAr") ?? contact.str("name")) : contact.str("name")
  }

  /// An account's name, by id.
  func accountName(_ id: String?) -> String {
    guard let id, !id.isEmpty, let account = record(.accounts, id) else { return "" }
    return LanguageStore.shared.isArabic ? (account.text("nameAr") ?? account.str("name")) : account.str("name")
  }

  /// An employee's name, by id.
  func employeeName(_ id: String?) -> String {
    guard let id, !id.isEmpty, let employee = record(.employees, id) else { return "" }
    return LanguageStore.shared.isArabic ? (employee.text("nameAr") ?? employee.str("name")) : employee.str("name")
  }
}

/// A name in the language being read: `nameAr` in Arabic when there is one.
@MainActor
func localName(_ record: JSONValue, key: String = "name") -> String {
  if LanguageStore.shared.isArabic, let arabic = record.text(key + "Ar") { return arabic }
  return record.str(key)
}

// MARK: Searching

extension String {
  /// Matches a search the way the web does: every word of `query` somewhere
  /// in the text, ignoring case and accents.
  func matches(_ query: String) -> Bool {
    let words = query.split(whereSeparator: \.isWhitespace)
    guard !words.isEmpty else { return true }
    let haystack = folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    return words.allSatisfy {
      haystack.contains(String($0).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))
    }
  }
}

// MARK: A list page

/// A filter chip of a list: its key, label and how many records it holds.
struct ListChip: Identifiable, Hashable {
  let id: String
  let label: String
  var count: Int?

  init(_ id: String, _ label: String, count: Int? = nil) {
    self.id = id
    self.label = label
    self.count = count
  }
}

/// A list page as the web's lists (`src/apps/books/pages/documents/list.tsx`
/// and the rest), on a phone: the header (title, description, the New
/// button), then a card with the status chips and the search box, one row
/// per record, "Show more (N remaining)" after 50, and a footer (count and
/// totals). While the company downloads, a spinner with the progress; when
/// nothing matches, the empty state.
struct RecordListPage<Row: View, Footer: View>: View {
  let title: String
  var description: String?
  let records: [Rec]
  var chips: [ListChip] = []
  var chipFilter: ((Rec, String) -> Bool)?
  var searchPlaceholder: String = t("Search")
  var searchText: ((Rec) -> String)?
  var newLabel: String?
  var onNew: (() -> Void)?
  var emptyIcon: Icon = .inbox
  var emptyTitle: String
  var emptyDescription: String?
  let row: (Rec) -> Row
  let footer: ([Rec]) -> Footer

  @Environment(AppModel.self) private var model
  @State private var chip = "all"
  @State private var query = ""
  @State private var shown = 50

  init(
    title: String, description: String? = nil, records: [Rec], chips: [ListChip] = [],
    chipFilter: ((Rec, String) -> Bool)? = nil, searchPlaceholder: String = t("Search"),
    searchText: ((Rec) -> String)? = nil, newLabel: String? = nil, onNew: (() -> Void)? = nil,
    emptyIcon: Icon = .inbox, emptyTitle: String, emptyDescription: String? = nil,
    @ViewBuilder row: @escaping (Rec) -> Row, @ViewBuilder footer: @escaping ([Rec]) -> Footer
  ) {
    self.title = title
    self.description = description
    self.records = records
    self.chips = chips
    self.chipFilter = chipFilter
    self.searchPlaceholder = searchPlaceholder
    self.searchText = searchText
    self.newLabel = newLabel
    self.onNew = onNew
    self.emptyIcon = emptyIcon
    self.emptyTitle = emptyTitle
    self.emptyDescription = emptyDescription
    self.row = row
    self.footer = footer
  }

  var body: some View {
    let visible = filtered
    WebPage(refresh: { [model] in await model.one.sync() }) {
      PageHeader(title, description: description) {
        if let newLabel, let onNew {
          WebButton(newLabel, icon: .plus, haptic: .press, action: onNew)
        }
      }
      ListCard {
        if !chips.isEmpty {
          Segmented(
            selection: $chip,
            options: chips.map { SegmentOption($0.id, $0.label, count: $0.count) })
        }
        if searchText != nil {
          TextInput(text: $query, placeholder: searchPlaceholder, leadingIcon: .search)
        }
      } rows: {
        if records.isEmpty, !model.one.hasData || isDownloading {
          DataLoadingRow()
        } else if visible.isEmpty {
          WebEmptyState(
            icon: emptyIcon, title: query.isEmpty ? emptyTitle : t("No results"),
            description: query.isEmpty ? emptyDescription : nil)
        } else {
          ForEach(visible.prefix(shown)) { record in
            row(record)
          }
          if visible.count > shown {
            ListShowMore(remaining: visible.count - shown) { shown += 50 }
          }
          if Footer.self != EmptyView.self {
            ListCardFooter { footer(visible) }
          }
        }
      }
    }
    .onChange(of: chip) { _, _ in shown = 50 }
    .onChange(of: query) { _, _ in shown = 50 }
  }

  private var isDownloading: Bool {
    if case .downloading = model.one.phase { return true }
    return false
  }

  private var filtered: [Rec] {
    records.filter { record in
      (chip == "all" || chipFilter?(record, chip) ?? true)
        && (query.isEmpty || (searchText?(record) ?? "").matches(query))
    }
  }
}

extension RecordListPage where Footer == EmptyView {
  init(
    title: String, description: String? = nil, records: [Rec], chips: [ListChip] = [],
    chipFilter: ((Rec, String) -> Bool)? = nil, searchPlaceholder: String = t("Search"),
    searchText: ((Rec) -> String)? = nil, newLabel: String? = nil, onNew: (() -> Void)? = nil,
    emptyIcon: Icon = .inbox, emptyTitle: String, emptyDescription: String? = nil,
    @ViewBuilder row: @escaping (Rec) -> Row
  ) {
    self.init(
      title: title, description: description, records: records, chips: chips, chipFilter: chipFilter,
      searchPlaceholder: searchPlaceholder, searchText: searchText, newLabel: newLabel, onNew: onNew,
      emptyIcon: emptyIcon, emptyTitle: emptyTitle, emptyDescription: emptyDescription, row: row,
      footer: { _ in EmptyView() })
  }
}

/// While the company's records are still coming: a spinner with the progress.
struct DataLoadingRow: View {
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    VStack(spacing: 8) {
      switch model.one.phase {
      case .downloading(let done, let total) where total > 0:
        Spinner(t("Downloading {done} of {total}", ["done": "\(done)", "total": "\(total)"]))
      case .failed(let message):
        Text(message)
          .font(.web(14))
          .foregroundStyle(palette.slate(500))
          .multilineTextAlignment(.center)
        WebButton(t("Try again"), variant: .outline, size: .sm) {
          Task { await model.one.sync() }
        }
      default:
        Spinner(t("Loading…"))
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
    .padding(.horizontal, 16)
  }
}

// MARK: A detail page

/// A record's page (the web's view pages on a phone): the breadcrumb back to
/// its list, the title with its badges, a line under it, the actions, then
/// the cards. A record that isn't on this iPhone (deleted, or not yet
/// downloaded) shows the web's "not found" state instead.
struct RecordDetailPage<Badges: View, Actions: View, Content: View>: View {
  let record: JSONValue?
  let title: String
  var subtitle: String?
  var breadcrumb: String?
  let badges: Badges
  let actions: Actions
  let content: Content
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  init(
    record: JSONValue?, title: String, subtitle: String? = nil, breadcrumb: String? = nil,
    @ViewBuilder badges: () -> Badges, @ViewBuilder actions: () -> Actions, @ViewBuilder content: () -> Content
  ) {
    self.record = record
    self.title = title
    self.subtitle = subtitle
    self.breadcrumb = breadcrumb
    self.badges = badges()
    self.actions = actions()
    self.content = content()
  }

  var body: some View {
    WebPage(spacing: 16, refresh: { [model] in await model.one.sync() }) {
      if record == nil {
        if model.one.hasData, model.one.phase == .ready {
          Card {
            WebEmptyState(
              icon: .fileSearch, title: t("Not found"),
              description: t("It may have been deleted, or it hasn't reached this device yet."))
          }
        } else {
          Card { DataLoadingRow() }
        }
      } else {
        VStack(alignment: .leading, spacing: 8) {
          if let breadcrumb {
            Button {
              Haptics.play(.tap)
              router.back()
            } label: {
              HStack(spacing: 4) {
                IconView(.chevronLeft, size: 14)
                Text(breadcrumb)
              }
              .font(.web(14))
              .foregroundStyle(palette.slate(500))
              .frame(minHeight: 32)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
          Text(title)
            .webText(.pageTitle)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .accessibilityAddTraits(.isHeader)
          if Badges.self != EmptyView.self {
            FlowLayout(spacing: 6, lineSpacing: 6) { badges }
          }
          if let subtitle {
            Text(subtitle).font(.web(14)).foregroundStyle(palette.slate(500))
          }
          if Actions.self != EmptyView.self {
            FlowLayout(spacing: 8, lineSpacing: 8) { actions }
              .padding(.top, 8)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
        content
      }
    }
  }
}

extension RecordDetailPage where Actions == EmptyView {
  init(
    record: JSONValue?, title: String, subtitle: String? = nil, breadcrumb: String? = nil,
    @ViewBuilder badges: () -> Badges, @ViewBuilder content: () -> Content
  ) {
    self.init(
      record: record, title: title, subtitle: subtitle, breadcrumb: breadcrumb, badges: badges,
      actions: { EmptyView() }, content: content)
  }
}

extension RecordDetailPage where Badges == EmptyView, Actions == EmptyView {
  init(
    record: JSONValue?, title: String, subtitle: String? = nil, breadcrumb: String? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.init(
      record: record, title: title, subtitle: subtitle, breadcrumb: breadcrumb, badges: { EmptyView() },
      actions: { EmptyView() }, content: content)
  }
}

/// A card of label–value rows (the web's summary cards): each label in
/// 14pt slate-500 at the start, its value in 14pt slate-900 at the end;
/// rows whose value is empty are left out.
struct InfoCard: View {
  let title: String?
  let rows: [InfoRow]
  @Environment(\.palette) private var palette

  init(_ title: String? = nil, rows: [InfoRow]) {
    self.title = title
    self.rows = rows
  }

  var body: some View {
    let shown = rows.filter { !$0.value.isEmpty }
    if !shown.isEmpty {
      Card {
        if let title { CardHeader(title) }
        VStack(spacing: 0) {
          ForEach(Array(shown.enumerated()), id: \.offset) { index, row in
            HStack(alignment: .firstTextBaseline, spacing: 12) {
              Text(row.label)
                .font(.web(14))
                .foregroundStyle(palette.slate(500))
              Spacer(minLength: 8)
              Text(row.value)
                .font(.web(14, row.strong ? .semibold : .regular, tabular: row.tabular))
                .foregroundStyle(row.tone.map { palette.color($0) } ?? palette.slate(900))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .overlay(alignment: .top) {
              if index > 0 { Rectangle().fill(palette.slate(100)).frame(height: 1) }
            }
          }
        }
        .padding(.vertical, 4)
      }
    }
  }
}

/// One row of an `InfoCard`.
struct InfoRow {
  let label: String
  let value: String
  var strong = false
  var tabular = false
  var tone: Token?

  init(_ label: String, _ value: String, strong: Bool = false, tabular: Bool = false, tone: Token? = nil) {
    self.label = label
    self.value = value
    self.strong = strong
    self.tabular = tabular
    self.tone = tone
  }
}

/// A card of text (notes, terms, an address), left out when empty.
struct TextCard: View {
  let title: String
  let text: String?
  @Environment(\.palette) private var palette

  var body: some View {
    if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      Card {
        CardHeader(title)
        Text(text)
          .font(.web(14))
          .foregroundStyle(palette.slate(700))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 20)
          .padding(.bottom, 16)
      }
    }
  }
}

/// A card listing related records, each a row that opens it; left out when there are none.
struct RelatedCard<Row: View>: View {
  let title: String
  let records: [Rec]
  let row: (Rec) -> Row

  init(_ title: String, records: [Rec], @ViewBuilder row: @escaping (Rec) -> Row) {
    self.title = title
    self.records = records
    self.row = row
  }

  var body: some View {
    if !records.isEmpty {
      ListCard {
        Text(title).font(.web(16, .semibold))
      } rows: {
        ForEach(records.prefix(100)) { record in row(record) }
      }
    }
  }
}

/// A badge for a record's status, from the web's status meanings.
@MainActor
func statusBadge(_ status: String) -> Badge {
  let meta = StatusMeta.document(status)
  return Badge(status: meta == .unknown && !status.isEmpty ? StatusMeta(label: status.capitalized, tone: .gray) : meta)
}
