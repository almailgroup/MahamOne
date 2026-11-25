import SwiftUI

/// An app's icon on its colour (`AppMark` in `src/suite/switcher.tsx`).
struct AppMark: View {
  enum Size {
    /// 28pt, 8pt radius, a 16pt icon.
    case small
    /// 40pt, 12pt radius, a 20pt icon.
    case medium
    /// 48pt, 16pt radius, a 24pt icon.
    case large

    var side: CGFloat {
      switch self {
      case .small: 28
      case .medium: 40
      case .large: 48
      }
    }

    var radius: CGFloat {
      switch self {
      case .small: 8
      case .medium: 12
      case .large: 16
      }
    }

    var icon: CGFloat {
      switch self {
      case .small: 16
      case .medium: 20
      case .large: 24
      }
    }
  }

  let icon: Icon
  let tone: AppTone
  var size: Size = .medium
  @Environment(\.palette) private var palette

  var body: some View {
    IconView(icon, size: size.icon)
      .foregroundStyle(palette.color(tone.foreground))
      .frame(width: size.side, height: size.side)
      .background(
        palette.color(tone.background), in: RoundedRectangle(cornerRadius: size.radius, style: .continuous))
      .accessibilityHidden(true)
  }
}

/// An entry of the app switcher: one of Maham One's apps, or Maham Tasks
/// (the native app's second department; the web has no switcher for it).
enum SwitcherEntry: Identifiable {
  case app(SuiteApp)
  case tasks

  var id: String {
    switch self {
    case .app(let app): app.id.rawValue
    case .tasks: "tasks"
    }
  }

  var icon: Icon {
    switch self {
    case .app(let app): app.icon
    case .tasks: .listChecks
    }
  }

  var tone: AppTone {
    switch self {
    case .app(let app): app.tone
    case .tasks: .blue
    }
  }

  var preview: Bool {
    switch self {
    case .app(let app): app.preview
    case .tasks: false
    }
  }

  func title(arabic: Bool) -> String {
    switch self {
    case .app(let app): app.title(arabic: arabic)
    case .tasks: arabic ? "مهام تاسكس" : "Maham Tasks"
    }
  }
}

extension SuiteState {
  /// The switcher's entries: the apps the person may open, then Maham Tasks.
  var switcherEntries: [SwitcherEntry] {
    visibleApps.map { SwitcherEntry.app($0) } + [.tasks]
  }

  /// The entry on screen.
  func currentEntry(path: String) -> String {
    department == .tasks ? "tasks" : currentApp(path: path).id.rawValue
  }

  /// Opens an app chosen as a whole: remembered first, so its home opens
  /// with its own drawer (`useOpenApp`).
  func open(_ entry: SwitcherEntry, router: ShellRouter) {
    switch entry {
    case .app(let app):
      rememberApp(app.id)
      department = .one
      router.go(path: app.home)
    case .tasks:
      department = .tasks
    }
  }
}

/// The header's grid button: the apps the person may open, and the Maham One home.
struct AppSwitcherButton: View {
  @State private var open = false
  @Environment(ShellChrome.self) private var chrome

  var body: some View {
    WebButton(icon: .layoutGrid, label: t("Switch app"), variant: .ghost) { open = true }
      .anchoredPanel(isPresented: $open, alignment: .end, width: min(368, chrome.screenSize.width - 24)) {
        AppSwitcherPanel()
      }
  }
}

/// The switcher's panel: 23rem wide, 16pt radius, shadow-xl, four columns
/// (three when there are more than four apps).
struct AppSwitcherPanel: View {
  @Environment(SuiteState.self) private var suite
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @Environment(\.dismissPanel) private var dismissPanel

  var body: some View {
    let entries = suite.switcherEntries
    let current = suite.currentEntry(path: router.currentPath)
    let arabic = LanguageStore.shared.isArabic
    let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: entries.count > 4 ? 3 : 4)
    let shape = RoundedRectangle(cornerRadius: WebRadius.xl, style: .continuous)
    VStack(alignment: .leading, spacing: 0) {
      SuiteLogo(height: 24)
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 10)
      LazyVGrid(columns: columns, spacing: 4) {
        ForEach(entries) { entry in
          let active = entry.id == current
          Button {
            Haptics.play(.selection)
            dismissPanel()
            suite.open(entry, router: router)
          } label: {
            VStack(spacing: 6) {
              AppMark(icon: entry.icon, tone: entry.tone)
              Text(entry.title(arabic: arabic))
                .font(.web(12, .semibold))
                .foregroundStyle(palette.slate(900))
                .multilineTextAlignment(.center)
                .lineLimit(2)
              if entry.preview { Pill(t("Beta")) }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(
              active ? palette.slate(50) : Color.clear,
              in: RoundedRectangle(cornerRadius: WebRadius.lg, style: .continuous)
            )
            .ring(active ? palette.hairline : .clear, in: RoundedRectangle(cornerRadius: WebRadius.lg, style: .continuous))
            .overlay(alignment: .topTrailing) {
              if active {
                IconView(.check, size: 14).foregroundStyle(palette.primary(600)).padding(8)
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(PressedFill(radius: WebRadius.lg))
          .accessibilityAddTraits(active ? .isSelected : [])
        }
      }
      Rectangle().fill(palette.slate(100)).frame(height: 1).padding(.vertical, 8)
      Button {
        Haptics.play(.tap)
        dismissPanel()
        suite.department = .one
        router.go(.home)
      } label: {
        HStack(spacing: 10) {
          IconView(.house, size: 16).foregroundStyle(palette.slate(400))
          Text(t("{suite} home", ["suite": arabic ? "مهام ون" : "Maham One"]))
            .font(.web(14))
            .foregroundStyle(palette.slate(700))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(PressedFill(radius: WebRadius.md))
    }
    .padding(8)
    .background(palette.surface, in: shape)
    .ring(palette.hairline, in: shape)
    .boxShadow(WebShadow.xl, in: shape)
  }
}

/// The Maham One logo, with the white-"Maham" version on dark themes.
struct SuiteLogo: View {
  var height: CGFloat = 32
  @Environment(\.palette) private var palette

  var body: some View {
    Image(palette.isDark ? "SuiteLogoDark" : "SuiteLogo")
      .resizable()
      .interpolation(.high)
      .aspectRatio(955 / 192, contentMode: .fit)
      .frame(height: height)
      .accessibilityLabel(Text(verbatim: LanguageStore.shared.isArabic ? "مهام ون" : "Maham One"))
  }
}

/// The phone menu's app tiles: every app a tap away; the current one on surface.
struct AppTiles: View {
  let onNavigate: () -> Void
  @Environment(SuiteState.self) private var suite
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let entries = suite.switcherEntries
    let current = suite.currentEntry(path: router.currentPath)
    let arabic = LanguageStore.shared.isArabic
    let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: entries.count > 4 ? 3 : 4)
    LazyVGrid(columns: columns, spacing: 4) {
      ForEach(entries) { entry in
        let active = entry.id == current
        let shape = RoundedRectangle(cornerRadius: WebRadius.lg, style: .continuous)
        Button {
          Haptics.play(.selection)
          onNavigate()
          suite.open(entry, router: router)
        } label: {
          VStack(spacing: 4) {
            AppMark(icon: entry.icon, tone: entry.tone, size: .small)
            Text(entry.title(arabic: arabic))
              .font(.web(11, .medium))
              .foregroundStyle(palette.slate(700))
              .multilineTextAlignment(.center)
              .lineLimit(2)
          }
          .frame(maxWidth: .infinity, minHeight: 48)
          .padding(.horizontal, 2)
          .padding(.vertical, 8)
          .background(active ? palette.surface : Color.clear, in: shape)
          .ring(active ? palette.hairline : .clear, in: shape)
          .boxShadow(active ? WebShadow.xs : [], in: shape)
          .contentShape(Rectangle())
        }
        .buttonStyle(PressedFill(radius: WebRadius.lg, color: .surface))
        .accessibilityAddTraits(active ? .isSelected : [])
      }
    }
  }
}
