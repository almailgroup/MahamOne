import MahamKit
import SwiftUI

// Updates (`src/pages/notifications.tsx`, `src/features/notifications`):
// what the team changed in the company, newest first, by day. On this
// iPhone it is read from the company's activity log (who changed what, as
// each record's history shows it); the person's own changes are left out,
// and changes about payroll and people for those who don't see them.

enum SuUpdates {
  /// Changes shown at a time.
  static let page = 50

  /// The kinds of change in words (`CHANGE_KIND_LABELS`), for the filter.
  static func kindLabel(_ kind: String) -> String {
    switch kind {
    case "document": "Invoices and documents"
    case "payment": "Payments"
    case "cheque": "Cheques"
    case "approval": "Approval requests"
    case "settings": "Company settings"
    case "member": "Team"
    case "people": "Payroll and people"
    case "compliance": "Compliance"
    case "contact": "Customers and vendors"
    case "item": "Items and stock"
    case "expense": "Expenses"
    case "accounting": "Accounting"
    case "file": "Files"
    default: "Other changes"
    }
  }

  static let kinds = [
    "document", "payment", "cheque", "approval", "settings", "member", "people", "compliance", "contact", "item",
    "expense", "accounting", "file",
  ]

  /// The kind of change an activity is, by what it is about.
  static func kind(_ activity: JSONValue) -> String {
    let entity = activity.str("entity")
    if DocType(rawValue: entity) != nil || entity == "recurring" { return "document" }
    switch entity {
    case "payment": return "payment"
    case "cheque": return "cheque"
    case "approval": return "approval"
    case "company": return "settings"
    case "member": return "member"
    case "employee", "payroll", "costing": return "people"
    case "compliance": return "compliance"
    case "client": return "contact"
    case "product", "stock": return "item"
    case "expense": return "expense"
    case "account", "journal", "vat_return", "bank", "asset", "year_end": return "accounting"
    default: return "other"
    }
  }

  /// An activity's message in the interface language (`activityText`): its
  /// key with its values, Arabic names for Arabic readers, amounts and
  /// dates the reader's way.
  @MainActor
  static func text(_ activity: JSONValue, format: CompanyFormat) -> String {
    guard let key = activity.text("messageKey") else { return dates(activity.str("message"), format: format) }
    let arabic = LanguageStore.shared.isArabic ? (activity.obj("messageVarsAr")?.object ?? [:]) : [:]
    var vars: [String: String] = [:]
    for (name, value) in activity.obj("messageVars")?.object ?? [:] {
      let shown = arabic[name] ?? value
      if let text = shown.string {
        vars[name] = dates(text, format: format)
      } else if let number = shown.double {
        vars[name] = Money.jsString(number)
      }
    }
    for (name, money) in activity.obj("messageMoney")?.object ?? [:] {
      vars[name] = format.money(money.num("amount"), money.text("currency"))
    }
    return t(key, vars)
  }

  /// Days ("2026-11-26") in a text, written the company's way.
  static func dates(_ text: String, format: CompanyFormat) -> String {
    let chars = Array(text)
    guard chars.count >= 10 else { return text }
    var out = ""
    var index = 0
    while index < chars.count {
      if index + 10 <= chars.count, isDay(chars, at: index), boundary(chars, index - 1), boundary(chars, index + 10) {
        let day = String(chars[index..<(index + 10)])
        let written = format.date(day)
        out += written.isEmpty ? day : written
        index += 10
      } else {
        out.append(chars[index])
        index += 1
      }
    }
    return out
  }

  /// "dddd-dd-dd" starts at `start`.
  private static func isDay(_ chars: [Character], at start: Int) -> Bool {
    for offset in 0..<10 {
      let char = chars[start + offset]
      if offset == 4 || offset == 7 {
        if char != "-" { return false }
      } else if !(char.isASCII && char.isNumber) {
        return false
      }
    }
    return true
  }

  /// Not a letter, digit or underscore (or the end): where a word starts or stops.
  private static func boundary(_ chars: [Character], _ index: Int) -> Bool {
    guard index >= 0, index < chars.count else { return true }
    let char = chars[index]
    return !(char.isLetter || char.isNumber || char == "_")
  }

  /// "Just now", "12 minutes ago", "Today at 9:40", or the date and time.
  @MainActor
  static func when(_ at: String, format: CompanyFormat, now: Date = Date()) -> String {
    guard let time = SuDates.moment(at) else { return "" }
    let minutes = Int((now.timeIntervalSince(time) / 60).rounded())
    if minutes < 1 { return t("Just now") }
    if minutes < 60 { return tp(minutes, "{count} minute ago", "{count} minutes ago") }
    let day = ISODates.string(from: time)
    let today = ISODates.today()
    if day == today { return t("Today at {time}", ["time": SuDates.clock(time)]) }
    if day == ISODates.addDays(today, -1) { return t("Yesterday at {time}", ["time": SuDates.clock(time)]) }
    return format.dateTime(at)
  }

  /// "Today", "Yesterday" or the date.
  static func dayLabel(_ day: String, format: CompanyFormat) -> String {
    let today = ISODates.today()
    if day == today { return t("Today") }
    if day == ISODates.addDays(today, -1) { return t("Yesterday") }
    return format.date(day)
  }

  /// Where a change opens: the document, the customer, the payment… or nothing.
  @MainActor
  static func route(_ activity: JSONValue, one: OneData) -> Route? {
    if let id = activity.text("documentId"), let doc = one.record(.documents, id),
      let type = DocType(rawValue: doc.str("type"))
    {
      return type.route(id)
    }
    let id = activity.str("entityId")
    switch activity.str("entity") {
    case "client":
      return id.isEmpty ? nil : .contact(.customer, id: id)
    case "payment", "cheque":
      guard let payment = one.record(.payments, id) else { return nil }
      return .payment(payment.str("direction") == "out" ? .made : .received, id: id)
    case "expense": return .expenses
    case "employee": return id.isEmpty ? .employees : .employee(id: id)
    case "compliance": return .complianceDocuments
    case "approval": return .approvals
    case "journal": return id.isEmpty ? .journals : .journal(id: id)
    case "asset": return id.isEmpty ? .assets : .asset(id: id)
    case "product", "stock": return .products
    case "company": return .settings(section: "company")
    default: return nil
    }
  }
}

/// A day of changes.
private struct SuUpdateDay: Identifiable {
  let day: String
  var events: [JSONValue]
  var id: String { day }
}

/// `/notifications`: the team's changes by day, with a filter by kind.
struct SuUpdatesPage: View {
  @Environment(AppModel.self) private var model
  @State private var kind = ""
  @State private var limit = SuUpdates.page

  var body: some View {
    let role = SuRole(model)
    let company = model.one.company.map { localName($0) } ?? (model.business.company?.name ?? "")
    WebPage(spacing: 16, refresh: { [model] in await model.one.sync() }) {
      PageHeader(t("Updates"), description: t("What your team changed in {company}.", ["company": company]))
        .padding(.bottom, -16)
      if !(role.role == .owner || role.role == .admin || role.role == .accountant) {
        Card {
          WebEmptyState(
            icon: .bell, title: t("No updates here"),
            description: t("Only the owner and the members the owner allowed to approve see the changes of the team."))
        }
      } else {
        let events = changes(role)
        if suLoading(model, empty: events.isEmpty) {
          SuLoadingCard()
        } else {
          SuUpdatesFeed(events: events, kind: $kind, limit: $limit)
        }
      }
    }
  }

  /// The team's changes this person sees, newest first: never their own,
  /// and payroll and people only for those who see them.
  private func changes(_ role: SuRole) -> [JSONValue] {
    let one = model.one
    let tables: [String: [String: JSONValue]] = [
      "complianceDocuments": byId(.complianceDocuments), "renewals": byId(.renewals),
    ]
    let lookup: Privacy.Lookup = { table, id in tables[table]?[id] }
    let shown = one.records(.activities).filter { activity in
      let isPrivate = Privacy.isPrivateRecord("activities", activity, lookup: lookup)
      return Roles.seesChange(actor: activity.text("by"), isPrivate: isPrivate, viewer: role.userId, role: role.role)
    }
    return shown.sorted { $0.str("at") > $1.str("at") }
  }

  private func byId(_ kind: RecordKind) -> [String: JSONValue] {
    var map: [String: JSONValue] = [:]
    for record in model.one.records(kind) { map[record.rid] = record }
    return map
  }
}

private struct SuUpdatesFeed: View {
  let events: [JSONValue]
  @Binding var kind: String
  @Binding var limit: Int
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    let shown = events.filter { kind.isEmpty || SuUpdates.kind($0) == kind }
    let days = groups(Array(shown.prefix(limit)))
    let format = model.one.format
    VStack(alignment: .leading, spacing: 16) {
      if !events.isEmpty {
        Select(selection: $kind, options: options)
      }
      if days.isEmpty {
        Card {
          WebEmptyState(
            icon: .bell, title: events.isEmpty ? t("Nothing new from your team yet.") : t("Nothing matches"),
            description: events.isEmpty
              ? t("Changes the others make appear here as soon as their device syncs.") : t("Try another filter."))
        }
      } else {
        ForEach(days) { group in
          VStack(spacing: 0) {
            SuHeading(SuUpdates.dayLabel(group.day, format: format), size: 12)
            ListCard(rows: {
              ForEach(group.events.map(Rec.init)) { record in
                SuChangeRow(activity: record.raw, format: format)
              }
            })
          }
        }
      }
      if shown.count > limit {
        HStack {
          Spacer(minLength: 0)
          WebButton(t("Show older changes"), variant: .outline) { limit += SuUpdates.page }
          Spacer(minLength: 0)
        }
      }
    }
    .onChange(of: kind) { _, _ in limit = SuUpdates.page }
  }

  /// "Every kind of change", then the kinds the changes have.
  private var options: [SelectOption<String>] {
    let present = Set(events.map { SuUpdates.kind($0) })
    let kinds = (SuUpdates.kinds + ["other"]).filter { present.contains($0) }
    return [SelectOption("", t("Every kind of change"))] + kinds.map { SelectOption($0, t(SuUpdates.kindLabel($0))) }
  }

  /// By day, the newest first.
  private func groups(_ list: [JSONValue]) -> [SuUpdateDay] {
    var out: [SuUpdateDay] = []
    for event in list {
      let day = SuDates.localDay(event.text("at")) ?? ""
      if let last = out.indices.last, out[last].day == day {
        out[last].events.append(event)
      } else {
        out.append(SuUpdateDay(day: day, events: [event]))
      }
    }
    return out
  }
}

/// One change: who, what was done, when; opens the record.
private struct SuChangeRow: View {
  let activity: JSONValue
  let format: CompanyFormat
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let actor = activity.str("byName").trimmingCharacters(in: .whitespaces)
    SuRow(action: action) {
      HStack(alignment: .top, spacing: 12) {
        Circle().fill(palette.primary(400)).frame(width: 8, height: 8).padding(.top, 6).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(line(actor: actor))
            .font(.web(14))
            .foregroundStyle(palette.slate(700))
            .frame(maxWidth: .infinity, alignment: .leading)
          Text(SuUpdates.when(activity.str("at"), format: format))
            .font(.web(12))
            .foregroundStyle(palette.slate(500))
        }
      }
    }
  }

  /// The actor in bold, then what they did.
  private func line(actor: String) -> AttributedString {
    let text = AttributedString(SuUpdates.text(activity, format: format))
    guard !actor.isEmpty else { return text }
    var name = AttributedString(actor + " ")
    let bold: Font = Font.web(14, .semibold)
    let ink: Color = palette.slate(900)
    name.font = bold
    name.foregroundColor = ink
    name.append(text)
    return name
  }

  private var action: (() -> Void)? {
    guard let route = SuUpdates.route(activity, one: model.one) else { return nil }
    return { router.push(route) }
  }
}
