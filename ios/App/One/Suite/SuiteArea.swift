import MahamKit
import SwiftUI

// Maham CRM, Maham Compliance and the suite's own pages (files, approvals,
// updates, settings, templates), as the web shows them on a phone. They
// read the company's records and never write them; what is changed on the
// web opens there, inside the app.

/// The pages of this area, by route.
@MainActor
enum SuiteArea {
  static func page(for route: Route) -> AnyView? {
    switch route {
    case .pipeline: AnyView(SuPipelinePage())
    case .prospects: AnyView(SuProspectsPage())
    case .complianceCalendar: AnyView(SuComplianceCalendarPage())
    case .complianceDocuments: AnyView(SuComplianceDocumentsPage())
    case .vehicles: AnyView(SuVehiclesPage())
    case .files: AnyView(SuFilesPage())
    case .approvals: AnyView(SuApprovalsPage())
    case .notifications: AnyView(SuUpdatesPage())
    case .settings(let section): AnyView(SuSettingsPage(section: section))
    case .templates: AnyView(SuTemplatesPage())
    default: nil
    }
  }
}

// MARK: Who is looking

/// What the person's role in the company on screen lets them see
/// (`useRoleView`): payroll and people data, and whether they only look.
@MainActor
struct SuRole {
  let role: MemberRole?
  let userId: String

  init(_ model: AppModel) {
    role = model.business.company?.role
    userId = model.session?.user.id ?? ""
  }

  /// Sees payroll, employees and confidential papers.
  var seesPeople: Bool { Roles.canSeePeople(role) }
  /// A viewer changes nothing.
  var readOnly: Bool { role == .viewer }
  /// Decides approval requests (the owner; the members the owner allowed
  /// are not known on this iPhone).
  var approver: Bool { role == .owner }
}

// MARK: Dates and words

enum SuDates {
  /// A stored timestamp ("2026-11-20T09:30:00.000Z") as a moment.
  static func moment(_ value: String?) -> Date? {
    guard let value, !value.isEmpty else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) { return date }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: value)
  }

  /// The day of a timestamp on this iPhone's calendar (`toISODate(new Date(at))`);
  /// a plain day stays as it is.
  static func localDay(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    if let date = moment(value) { return ISODates.string(from: date) }
    let day = String(value.prefix(10))
    return ISODates.isISODate(day) ? day : nil
  }

  /// "9:40 AM" in the interface language.
  @MainActor
  static func clock(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = LanguageStore.shared.locale
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }

  /// Days in a month of the Gregorian calendar.
  static func daysIn(year: Int, month: Int) -> Int {
    switch month {
    case 2:
      let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
      return leap ? 29 : 28
    case 4, 6, 9, 11: return 30
    default: return 31
    }
  }

  /// "2026-11-26" as its numbers.
  static func parts(_ value: String) -> (year: Int, month: Int, day: Int)? {
    let pieces = value.prefix(10).split(separator: "-")
    guard pieces.count == 3, let year = Int(pieces[0]), let month = Int(pieces[1]), let day = Int(pieces[2]) else {
      return nil
    }
    return (year, month, day)
  }

  /// A day written "yyyy-MM-dd".
  static func iso(_ year: Int, _ month: Int, _ day: Int) -> String {
    "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
  }

  static func pad(_ value: Int, _ width: Int) -> String {
    let digits = String(value)
    return String(repeating: "0", count: max(0, width - digits.count)) + digits
  }

  /// The month `months` after year/month (negative goes back).
  static func addMonths(year: Int, month: Int, _ months: Int) -> (year: Int, month: Int) {
    let total = year * 12 + (month - 1) + months
    let newYear = Int((Double(total) / 12).rounded(.down))
    return (newYear, total - newYear * 12 + 1)
  }
}

/// The parts that aren't empty, joined with " · ".
func suJoin(_ parts: [String?], _ separator: String = " · ") -> String {
  parts.compactMap { $0 }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: separator)
}

/// "Today", "In 5 days" or "3 days ago" (`daysText`).
func suDaysText(_ daysLeft: Int) -> String {
  if daysLeft == 0 { return t("Today") }
  if daysLeft > 0 { return tp(daysLeft, "In {count} day", "In {count} days") }
  return tp(-daysLeft, "{count} day ago", "{count} days ago")
}

// MARK: Shared pieces

/// A button that used to open a page of Maham One on the web. The app
/// opens nothing of the web: until the action it stood for is native, it
/// shows nothing.
struct SuWebButton: View {
  let title: String
  let path: String
  var variant: ButtonVariant = .outline
  var size: ButtonSize = .sm

  init(_ title: String, path: String, variant: ButtonVariant = .outline, size: ButtonSize = .sm) {
    self.title = title
    self.path = path
    self.variant = variant
    self.size = size
  }

  var body: some View { EmptyView() }
}

/// A heading above a group of cards: 14pt, 600, uppercase (the calendar's months, the updates' days).
struct SuHeading: View {
  let text: String
  var tone: Token = .slate(500)
  var size: CGFloat = 14
  @Environment(\.palette) private var palette

  init(_ text: String, tone: Token = .slate(500), size: CGFloat = 14) {
    self.text = text
    self.tone = tone
    self.size = size
  }

  var body: some View {
    Text(text)
      .font(.web(size, .semibold))
      .textCase(.uppercase)
      .foregroundStyle(palette.color(tone))
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 4)
      .padding(.bottom, 8)
      .accessibilityAddTraits(.isHeader)
  }
}

/// The web's `Stat`: a card with the label, the figure (24pt, 600) and a hint.
struct SuStat<Hint: View>: View {
  let label: String
  let value: String
  var danger = false
  let hint: Hint
  @Environment(\.palette) private var palette

  init(_ label: String, value: String, danger: Bool = false, @ViewBuilder hint: () -> Hint) {
    self.label = label
    self.value = value
    self.danger = danger
    self.hint = hint()
  }

  var body: some View {
    Card {
      VStack(alignment: .leading, spacing: 0) {
        Text(label).font(.web(14, .medium)).foregroundStyle(palette.slate(500))
        Text(value)
          .font(.web(24, .semibold, tabular: true))
          .foregroundStyle(danger ? palette[.red(700)] : palette.slate(900))
          .padding(.top, 8)
        hint
          .font(.web(12))
          .foregroundStyle(palette.slate(500))
          .padding(.top, 4)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(20)
    }
  }
}

/// A key figure of the CRM: the label, the figure (18pt, 600) and a hint, in a 2-column grid.
struct SuFigure: View {
  let label: String
  let value: String
  let hint: String
  @Environment(\.palette) private var palette

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.lg, style: .continuous)
    VStack(alignment: .leading, spacing: 0) {
      Text(label).font(.web(12, .medium)).foregroundStyle(palette.slate(500)).lineLimit(1)
      Text(value)
        .font(.web(18, .semibold, tabular: true))
        .foregroundStyle(palette.slate(900))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.top, 8)
      Text(hint).font(.web(12)).foregroundStyle(palette.slate(500)).lineLimit(1).padding(.top, 4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(palette.surface, in: shape)
    .border(palette.slate(200), in: shape)
    .boxShadow(WebShadow.xs, in: shape)
    .accessibilityElement(children: .combine)
  }
}

/// A note in slate-50 with an icon (`role="note"`): what the person doesn't see.
struct SuNote: View {
  let text: String
  var icon: Icon = .info
  @Environment(\.palette) private var palette

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous)
    HStack(alignment: .top, spacing: 8) {
      IconView(icon, size: 16).foregroundStyle(palette.slate(400)).padding(.top, 2)
      Text(text).font(.web(14)).foregroundStyle(palette.slate(600))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(palette.slate(50), in: shape)
    .border(palette.slate(200), in: shape)
  }
}

/// An amber card with a warning: what to set up first.
struct SuNotice<Content: View>: View {
  let content: Content
  @Environment(\.palette) private var palette

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.lg, style: .continuous)
    HStack(alignment: .top, spacing: 12) {
      IconView(.circleAlert, size: 20).foregroundStyle(palette[.amber(600)])
      VStack(alignment: .leading, spacing: 8) { content }
        .font(.web(14))
        .foregroundStyle(palette.slate(700))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(20)
    .background(palette[.amber(50)].opacity(0.6), in: shape)
    .border(palette[.amber(200)], in: shape)
  }
}

/// A text button that reads as a link (primary-700, 14pt medium).
struct SuLink: View {
  let title: String
  var size: CGFloat = 14
  let action: () -> Void
  @Environment(\.palette) private var palette

  init(_ title: String, size: CGFloat = 14, action: @escaping () -> Void) {
    self.title = title
    self.size = size
    self.action = action
  }

  var body: some View {
    Button {
      Haptics.play(.tap)
      action()
    } label: {
      Text(title)
        .font(.web(size, .medium))
        .foregroundStyle(palette.primary(700))
        .multilineTextAlignment(.leading)
        .frame(minHeight: 32)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// A line of text in a list that matched nothing ("No documents match.").
struct SuNoMatch: View {
  let text: String
  @Environment(\.palette) private var palette

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(text)
      .font(.web(14))
      .foregroundStyle(palette.slate(500))
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 24)
      .padding(.vertical, 48)
  }
}

/// A row of a list that isn't a `ListRow`: the slate-100 line above it and,
/// with an action, the pressed fill.
struct SuRow<Content: View>: View {
  var action: (() -> Void)?
  let content: Content
  @Environment(\.palette) private var palette

  init(action: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
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
          padded
        }
        .buttonStyle(PressedFill(radius: 0, color: .slate(100)))
      } else {
        padded
      }
    }
    .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }

  private var padded: some View {
    content
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .frame(minHeight: 56)
      .contentShape(Rectangle())
  }
}

/// While the company's records are still coming, in a card.
struct SuLoadingCard: View {
  var body: some View {
    Card { DataLoadingRow() }
  }
}

/// Whether the company's records are still on their way: nothing is here
/// yet, or what the page shows (`empty`) hasn't come while they download.
@MainActor
func suLoading(_ model: AppModel, empty: Bool) -> Bool {
  if !model.one.hasData { return true }
  guard empty else { return false }
  switch model.one.phase {
  case .downloading, .failed: return true
  default: return false
  }
}
