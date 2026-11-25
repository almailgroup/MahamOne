import SwiftUI

/// Maham One's home, `/` (`src/suite/home/index.tsx`): the greeting, the
/// company and the date, then the launcher. Sections are 20pt apart.
/// Pulling down syncs again. (Needs attention, approval requests and At a
/// glance follow with the sync engine.)
struct HomePage: View {
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette
  /// A line under each app: "3 overdue invoices", "12 employees".
  var stats: [SuiteAppID: String] = [:]

  var body: some View {
    let company = ShellCompany.name(model.business)
    WebPage(spacing: 20, refresh: { [model] in await model.refreshAll() }) {
      VStack(alignment: .leading, spacing: 4) {
        Text(Self.greeting(hour: Calendar.current.component(.hour, from: Date())))
          .webText(.pageTitle)
          .accessibilityAddTraits(.isHeader)
        HStack(spacing: 0) {
          if !company.isEmpty {
            Text(company).lineLimit(1)
            // Spaced by padding, not spaces: spaces around a lone dot swap
            // sides in Arabic.
            Text(verbatim: "·").fixedSize().padding(.horizontal, 4)
          }
          Text(CalendarDay.today.display).fixedSize()
        }
        .font(.web(14))
        .foregroundStyle(palette.slate(500))
      }
      Launcher(stats: stats)
    }
  }

  /// Before 12:00, before 18:00, after.
  static func greeting(hour: Int) -> String {
    if hour < 12 { return t("Good morning") }
    if hour < 18 { return t("Good afternoon") }
    return t("Good evening")
  }
}
