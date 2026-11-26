import MahamKit
import SwiftUI
import UIKit

// Maham People on a phone: the overview and directory, employees and their
// files, payroll, leave, loans, settlements, letters and manpower costing,
// read from the company's records as the web shows them. Payroll, salaries
// and employee documents are for the owner, admins and accountants only:
// every page here opens through `PeGate`, which shows the web's lock card
// (`PeopleLocked`) to anyone else, whatever the server sends.

/// The pages of Maham People, by route.
@MainActor
enum PeopleArea {
  static func page(for route: Route) -> AnyView? {
    switch route {
    case .peopleOverview: AnyView(PeOverviewPage())
    case .directory: AnyView(PeDirectoryPage())
    case .allCompanies: AnyView(PeAllCompaniesPage())
    case .employees: AnyView(PeEmployeesPage())
    case .employee(let id): AnyView(PeEmployeePage(id: id))
    case .settlement(let employeeId): AnyView(PeSettlementPage(employeeId: employeeId))
    case .payroll: AnyView(PePayrollPage())
    case .payRun(let id): AnyView(PePayRunPage(id: id))
    case .leave: AnyView(PeLeavePage())
    case .leaveReasons: AnyView(PeLeaveReasonsPage())
    case .loans: AnyView(PeLoansPage())
    case .payrollSettings: AnyView(PePayrollSettingsPage())
    case .letters: AnyView(PeLettersPage())
    case .letterTemplates: AnyView(PeLetterTemplatesPage())
    case .letterTemplate(let id): AnyView(PeLetterTemplatePage(id: id))
    case .costings: AnyView(PeCostingsPage())
    case .costing(let id): AnyView(PeCostingPage(id: id))
    default: nil
    }
  }
}

// MARK: - The gate

/// Every page of Maham People opens through here, as the web's `AppGate`
/// for People: nothing until the role is known (a page of salaries must not
/// flash up), the lock card for a role that doesn't see People, a spinner
/// while the company's records come, then the page.
struct PeGate<Content: View>: View {
  @Environment(SuiteState.self) private var suite
  @Environment(AppModel.self) private var model
  private let content: () -> Content

  init(@ViewBuilder content: @escaping () -> Content) {
    self.content = content
  }

  var body: some View {
    if !suite.roleKnown {
      PeLoadingPage()
    } else if !suite.access(.people).canOpen {
      PeLockedPage(role: suite.role)
    } else if model.one.peLoading {
      PeLoadingPage()
    } else {
      content()
    }
  }
}

extension OneData {
  /// Nothing of the company is here yet to show.
  var peLoading: Bool {
    if !hasData { return true }
    if case .downloading = phase { return records(.employees).isEmpty }
    return false
  }
}

/// A page with the spinner (and the download's progress).
struct PeLoadingPage: View {
  var body: some View {
    WebPage {
      Card { DataLoadingRow() }
    }
  }
}

/// `PeopleLocked`: in place of a payroll or people page, for a role that doesn't see them.
struct PeLockedPage: View {
  let role: MemberRole?
  @Environment(ShellRouter.self) private var router

  var body: some View {
    WebPage {
      Card {
        WebEmptyState(
          icon: .lock, title: t("Payroll and people are private"),
          description: t(
            "As {role} in this company you don’t see salaries, payroll or employee documents. Ask the owner if you need them.",
            ["role": roleLabel])
        ) {
          WebButton(t("Go to the home page"), variant: .outline) { router.go(.home) }
        }
      }
    }
  }

  private var roleLabel: String {
    switch role ?? .viewer {
    case .owner: t("Owner")
    case .admin: t("Admin")
    case .accountant: t("Accountant")
    case .staff: t("Staff")
    case .viewer: t("Viewer")
    }
  }
}

/// A record that isn't on this iPhone: the web's words for it, or the spinner while it may still come.
struct PeNotFound: View {
  let message: String
  let back: String
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    if model.one.hasData, model.one.phase == .ready {
      Card {
        WebEmptyState(icon: .fileSearch, title: message) {
          WebButton(back, variant: .outline) { router.back() }
        }
      }
    } else {
      Card { DataLoadingRow() }
    }
  }
}

// MARK: - Pieces of the pages

/// A figure on its card: the label, the value, a hint (`Stat`, and the overview's `Figure`).
struct PeStat: View {
  let label: String
  let value: String
  var hint: String?
  var icon: Icon?
  var tone: Token?
  var small = false
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
      .buttonStyle(PressedScale())
    } else {
      card
    }
  }

  private var card: some View {
    Card {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 8) {
          if let icon {
            IconView(icon, size: 16).foregroundStyle(palette.slate(400))
          }
          Text(label)
            .font(.web(icon == nil ? 14 : 12, .medium))
            .foregroundStyle(palette.slate(500))
            .lineLimit(2)
        }
        Text(value)
          .font(.web(small ? 20 : 24, .semibold, tabular: true))
          .foregroundStyle(tone.map { palette.color($0) } ?? palette.slate(900))
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .padding(.top, 8)
        if let hint {
          Text(hint)
            .font(.web(12))
            .foregroundStyle(palette.slate(500))
            .padding(.top, 4)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(icon == nil ? 20 : 14)
    }
    .frame(maxHeight: .infinity)
  }
}

/// Two cards side by side, as tall as each other (a 2-column grid on a phone).
struct PePair<First: View, Second: View>: View {
  private let first: First
  private let second: Second

  init(@ViewBuilder first: () -> First, @ViewBuilder second: () -> Second) {
    self.first = first()
    self.second = second()
  }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      first.frame(maxWidth: .infinity, maxHeight: .infinity)
      second.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .fixedSize(horizontal: false, vertical: true)
  }
}

/// An employee's initials on a round tint (`EmployeeAvatar`), or their photo.
struct PeAvatar: View {
  let name: String
  var size: CGFloat = 36
  var image: UIImage?
  @Environment(\.palette) private var palette

  var body: some View {
    ZStack {
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        palette.primary(100)
        Text(verbatim: PePeople.initials(name))
          .font(.web(max(11, size * 0.33), .semibold))
          .foregroundStyle(palette.primary(800))
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .accessibilityHidden(true)
  }
}

/// Rows divided by slate-100 lines; each row draws the line above it, the first one's cut off.
struct PeRows<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    VStack(spacing: 0) { content }
      .padding(.top, -1)
      .clipped()
  }
}

/// A line of a card: a title over a detail at the start, values or badges at the end; a tap opens it.
struct PeLineRow<Leading: View, Trailing: View>: View {
  let title: String
  var detail: String?
  var detail2: String?
  var titleStruck = false
  private let leading: Leading
  private let trailing: Trailing
  var action: (() -> Void)?
  @Environment(\.palette) private var palette

  init(
    title: String, detail: String? = nil, detail2: String? = nil, titleStruck: Bool = false,
    @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing, action: (() -> Void)? = nil
  ) {
    self.title = title
    self.detail = detail
    self.detail2 = detail2
    self.titleStruck = titleStruck
    self.leading = leading()
    self.trailing = trailing()
    self.action = action
  }

  var body: some View {
    Group {
      if let action {
        Button {
          Haptics.play(.tap)
          action()
        } label: {
          row
        }
        .buttonStyle(PressedFill(radius: 0, color: .slate(100)))
      } else {
        row
      }
    }
    .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }

  private var row: some View {
    HStack(spacing: 12) {
      if Leading.self != EmptyView.self { leading }
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.web(14, .medium))
          .foregroundStyle(palette.slate(900))
          .strikethrough(titleStruck)
          .multilineTextAlignment(.leading)
        if let detail, !detail.isEmpty {
          Text(detail)
            .font(.web(12))
            .foregroundStyle(palette.slate(500))
            .multilineTextAlignment(.leading)
        }
        if let detail2, !detail2.isEmpty {
          Text(detail2)
            .font(.web(12))
            .foregroundStyle(palette.slate(500))
            .multilineTextAlignment(.leading)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if Trailing.self != EmptyView.self {
        VStack(alignment: .trailing, spacing: 4) { trailing }
          .fixedSize()
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
    .frame(minHeight: 52)
    .contentShape(Rectangle())
  }
}

extension PeLineRow where Leading == EmptyView {
  init(
    title: String, detail: String? = nil, detail2: String? = nil, titleStruck: Bool = false,
    @ViewBuilder trailing: () -> Trailing, action: (() -> Void)? = nil
  ) {
    self.init(
      title: title, detail: detail, detail2: detail2, titleStruck: titleStruck, leading: { EmptyView() },
      trailing: trailing, action: action)
  }
}

extension PeLineRow where Leading == EmptyView, Trailing == EmptyView {
  /// A line that only says something (nothing at its end, no tap).
  init(title: String, detail: String? = nil, detail2: String? = nil) {
    self.init(
      title: title, detail: detail, detail2: detail2, leading: { EmptyView() }, trailing: { EmptyView() },
      action: nil)
  }
}

/// A label and a value on one line (`AmountRow`): strong for totals, muted for what is shown aside.
struct PeAmount: Identifiable {
  let id: Int
  let label: String
  let value: String
  var strong = false
  var muted = false
  var tone: Token?
}

/// Amounts one under the other, divided by lines.
struct PeAmountList: View {
  let rows: [PeAmount]
  @Environment(\.palette) private var palette

  var body: some View {
    VStack(spacing: 0) {
      ForEach(rows) { row in
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Text(row.label)
            .font(.web(14, row.strong ? .semibold : .regular))
            .foregroundStyle(row.strong ? palette.slate(900) : (row.muted ? palette.slate(500) : palette.slate(600)))
            .frame(maxWidth: .infinity, alignment: .leading)
          Text(row.value)
            .font(.web(14, row.strong ? .semibold : .regular, tabular: true))
            .foregroundStyle(
              row.tone.map { palette.color($0) }
                ?? (row.strong ? palette.slate(900) : (row.muted ? palette.slate(500) : palette.slate(900)))
            )
            .multilineTextAlignment(.trailing)
            .textSelection(.enabled)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
          if row.id > 0 { Rectangle().fill(palette.slate(100)).frame(height: 1) }
        }
      }
    }
  }
}

/// Builds the rows of a `PeAmountList`, numbering them.
struct PeAmountRows {
  private(set) var rows: [PeAmount] = []

  mutating func add(_ label: String, _ value: String, strong: Bool = false, muted: Bool = false, tone: Token? = nil) {
    rows.append(PeAmount(id: rows.count, label: label, value: value, strong: strong, muted: muted, tone: tone))
  }
}

/// A card with its header and a body of 20pt padding.
struct PeCard<Actions: View, Content: View>: View {
  let title: String
  var description: String?
  private let actions: Actions
  private let content: Content

  init(
    _ title: String, description: String? = nil, @ViewBuilder actions: () -> Actions,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.description = description
    self.actions = actions()
    self.content = content()
  }

  var body: some View {
    Card {
      CardHeader(title, description: description) { actions }
      VStack(alignment: .leading, spacing: 12) { content }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
  }
}

extension PeCard where Actions == EmptyView {
  init(_ title: String, description: String? = nil, @ViewBuilder content: () -> Content) {
    self.init(title, description: description, actions: { EmptyView() }, content: content)
  }
}

/// A card's header with rows under it (no padding around the rows).
struct PeListCard<Actions: View, Content: View>: View {
  let title: String
  var description: String?
  private let actions: Actions
  private let content: Content

  init(
    _ title: String, description: String? = nil, @ViewBuilder actions: () -> Actions,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.description = description
    self.actions = actions()
    self.content = content()
  }

  var body: some View {
    Card {
      CardHeader(title, description: description) { actions }
      PeRows { content }
    }
  }
}

extension PeListCard where Actions == EmptyView {
  init(_ title: String, description: String? = nil, @ViewBuilder content: () -> Content) {
    self.init(title, description: description, actions: { EmptyView() }, content: content)
  }
}

/// Text in a card's body where a list would be (14pt slate-500).
struct PeCardNote: View {
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
      .padding(.vertical, centered ? 32 : 24)
  }
}

/// A tinted note (`rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-900`).
struct PeNote: View {
  enum Tone { case amber, blue, slate }
  let text: String
  var tone: Tone = .amber
  @Environment(\.palette) private var palette

  init(_ text: String, tone: Tone = .amber) {
    self.text = text
    self.tone = tone
  }

  var body: some View {
    Text(text)
      .font(.web(14))
      .foregroundStyle(foreground)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(background, in: RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous))
  }

  private var foreground: Color {
    switch tone {
    case .amber: palette[.amber(900)]
    case .blue: palette[.blue(800)]
    case .slate: palette.slate(700)
    }
  }

  private var background: Color {
    switch tone {
    case .amber: palette[.amber(50)]
    case .blue: palette[.blue(50)]
    case .slate: palette.slate(100)
    }
  }
}

/// A switch as the web shows it, read only here: its label, description and position.
struct PeSwitchRow: View {
  let label: String
  var description: String?
  let isOn: Bool
  @Environment(\.palette) private var palette

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 2) {
        Text(label).font(.web(14, .medium)).foregroundStyle(palette.slate(800))
        if let description {
          Text(description).font(.web(14)).foregroundStyle(palette.slate(500))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      SwitchTrack(isOn: isOn)
        .opacity(0.5)
    }
    .frame(minHeight: 44)
    .accessibilityElement(children: .combine)
    .accessibilityValue(Text(isOn ? t("Switched on") : t("Switched off")))
  }
}

/// The payroll pages' title and their tabs: Pay runs / Leave / Loans / Settings (`PayrollHeader`).
struct PePayrollHeader: View {
  /// "runs", "leave", "loans", "settings", or another for none.
  let tab: String
  var description: String?
  @Environment(ShellRouter.self) private var router

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      PageHeader(t("Payroll"), description: description ?? t("Monthly pay runs, PIFSS, payslips, leave and staff loans."))
      Segmented(
        selection: Binding(get: { tab }, set: { open($0) }),
        options: [
          SegmentOption("runs", t("Pay runs")), SegmentOption("leave", t("Leave")),
          SegmentOption("loans", t("Loans")), SegmentOption("settings", t("Settings")),
        ]
      )
      .padding(.top, -8)
      .padding(.bottom, 24)
    }
  }

  /// The tab's page in place of this one, keeping the way back.
  private func open(_ next: String) {
    guard next != tab else { return }
    let route: Route =
      switch next {
      case "leave": .leave
      case "loans": .loans
      case "settings": .payrollSettings
      default: .payroll
      }
    if router.path.isEmpty {
      router.go(route)
    } else {
      router.path[router.path.count - 1] = route
    }
  }
}

/// A link to a journal entry the payroll posted: "Salaries · JV-0012 · 31/10/2026".
struct PeEntryLink: View {
  let label: String
  let journalId: String?
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    if let journalId, let journal = model.one.record(.journals, journalId) {
      PeLineRow(title: label) {
        Text(verbatim: "\(journal.str("number")) · \(model.one.format.date(journal.text("date")))")
          .font(.web(14, .medium))
          .foregroundStyle(palette.primary(700))
      } action: {
        router.push(.journal(id: journalId))
      }
    }
  }
}

/// Valid, expiring (with the days left) or expired (`ExpiryBadge`).
struct PeExpiryBadge: View {
  let info: PeExpiry

  var body: some View {
    if let left = info.daysLeft {
      Badge(label(left), tone: tone(left))
    } else {
      Badge(t("No expiry date"), tone: .gray)
    }
  }

  private func label(_ left: Int) -> String {
    switch info.status {
    case .expired: t("Expired")
    case .expiring: left == 0 ? t("Expires today") : tp(left, "Expires in {count} day", "Expires in {count} days")
    case .valid: t("Valid")
    }
  }

  private func tone(_ left: Int) -> StatusTone {
    switch info.status {
    case .expired: .red
    case .expiring: left <= 7 ? .red : .amber
    case .valid: .green
    }
  }
}

/// Opens a phone number or an email address.
enum PeContactLinks {
  static func phone(_ number: String) -> URL? {
    let digits = number.filter { $0.isNumber || $0 == "+" }
    return digits.isEmpty ? nil : URL(string: "tel:" + digits)
  }

  static func email(_ address: String) -> URL? {
    let trimmed = address.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? nil : URL(string: "mailto:" + trimmed)
  }
}

/// A photo kept as a data URL in an attachment.
enum PePhotos {
  @MainActor
  static func image(_ one: OneData, id: String?) -> UIImage? {
    guard let id, let file = one.record(.attachments, id), let url = file.text("dataUrl"),
      let comma = url.firstIndex(of: ",")
    else { return nil }
    guard let data = Data(base64Encoded: String(url[url.index(after: comma)...])) else { return nil }
    return UIImage(data: data)
  }
}
