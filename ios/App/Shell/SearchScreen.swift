import SwiftUI

/// Search on a phone (`src/features/search/command-palette.tsx`), full
/// screen: a 56pt input row with a slate-200 line below, the `Search` icon,
/// "Cancel" in primary-700; sections with 12pt slate-500 labels; rows at
/// least 44pt, the icon in a 32pt slate-100 tile, the first result on
/// primary-50. Records come with the sync engine; until then it finds the
/// apps, the pages of the navigation and what can be created.
struct SearchScreen: View {
  let onClose: () -> Void
  @Environment(SuiteState.self) private var suite
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @State private var query = ""
  @FocusState private var focused: Bool
  @AppStorage("maham.search.recent") private var savedRecent = ""

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        IconView(.search, size: 20).foregroundStyle(palette.slate(400))
        ZStack(alignment: .leading) {
          if query.isEmpty {
            Text(t("Search clients, documents, items or pages…"))
              .foregroundStyle(palette.slate(400))
              .lineLimit(1)
              .allowsHitTesting(false)
          }
          TextField("", text: $query)
            .focused($focused)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.go)
            .onSubmit { if let first = sections.first?.entries.first { choose(first) } }
        }
        .font(.web(16))
        .foregroundStyle(palette.slate(900))
        Button(action: onClose) {
          Text(t("Cancel"))
            .font(.web(14, .medium))
            .foregroundStyle(palette.primary(700))
            .padding(.horizontal, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, -8)
      }
      .padding(.horizontal, 16)
      .frame(height: 56)
      .overlay(alignment: .bottom) { Rectangle().fill(palette.slate(200)).frame(height: 1) }

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          if sections.isEmpty {
            empty
          }
          ForEach(sections) { section in
            Text(section.label)
              .font(.web(12, .semibold))
              .foregroundStyle(palette.slate(500))
              .padding(.horizontal, 12)
              .padding(.top, 12)
              .padding(.bottom, 6)
            ForEach(section.entries) { entry in
              row(entry, highlighted: entry.id == sections.first?.entries.first?.id)
            }
          }
        }
        .padding(8)
      }
      .scrollDismissesKeyboard(.interactively)
    }
    .background(palette.surface.ignoresSafeArea())
    .task { focused = true }
  }

  // MARK: Rows

  private func row(_ entry: SearchEntry, highlighted: Bool) -> some View {
    let tile = RoundedRectangle(cornerRadius: WebRadius.sm, style: .continuous)
    return Button {
      choose(entry)
    } label: {
      HStack(spacing: 12) {
        IconView(entry.icon, size: 16)
          .foregroundStyle(highlighted ? palette.primary(700) : palette.slate(500))
          .frame(width: 32, height: 32)
          .background(highlighted ? palette.surface : palette.slate(100), in: tile)
          .border(highlighted ? palette.slate(200) : .clear, in: tile)
          .boxShadow(highlighted ? WebShadow.xs : [], in: tile)
        VStack(alignment: .leading, spacing: 0) {
          Text(entry.title).font(.web(14, .medium)).foregroundStyle(palette.slate(900)).lineLimit(1)
          if let subtitle = entry.subtitle {
            Text(subtitle).font(.web(12)).foregroundStyle(palette.slate(500)).lineLimit(1)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .frame(minHeight: 44)
      .background(
        highlighted ? palette.primary(50) : Color.clear,
        in: RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(PressedFill(radius: WebRadius.md, color: .slate(50)))
  }

  private var empty: some View {
    VStack(spacing: 4) {
      Text(
        query.trimmingCharacters(in: .whitespaces).isEmpty
          ? t("Start typing")
          : t("Nothing found for “{query}”", ["query": query.trimmingCharacters(in: .whitespaces)])
      )
      .font(.web(14, .medium))
      .foregroundStyle(palette.slate(800))
      Text(t("Try a client name, a document number such as INV-0001, or an amount."))
        .font(.web(14))
        .foregroundStyle(palette.slate(500))
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 24)
    .padding(.vertical, 48)
  }

  // MARK: What is found

  private var sections: [SearchSection] {
    let all = SearchIndex.entries(suite: suite, current: suite.currentApp(path: router.currentPath).id)
    let words = SearchText.normalize(query).split(separator: " ").map(String.init)
    if words.isEmpty {
      let recentKeys = savedRecent.split(separator: "\n").map(String.init)
      let byKey = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      let recent = recentKeys.compactMap { byKey[$0] }
      let quick = ["action:invoice", "action:payment_in", "action:expense", "action:bill"]
        .compactMap { byKey[$0] }
        .filter { entry in !recent.contains { $0.id == entry.id } }
      return [
        SearchSection(id: "recent", label: t("Recent"), entries: recent),
        SearchSection(id: "quick", label: t("Quick actions"), entries: quick),
      ].filter { !$0.entries.isEmpty }
    }
    let found = all.filter { entry in words.allSatisfy { entry.terms.contains($0) } }
      .sorted { $0.boost > $1.boost }
      .prefix(50)
    var sections: [SearchSection] = []
    for entry in found {
      let id = entry.kind == .page ? "page" : "action"
      if let index = sections.firstIndex(where: { $0.id == id }) {
        sections[index].entries.append(entry)
      } else {
        sections.append(SearchSection(id: id, label: entry.kind == .page ? t("Pages") : t("Actions"), entries: [entry]))
      }
    }
    return sections
  }

  private func choose(_ entry: SearchEntry) {
    var recent = savedRecent.split(separator: "\n").map(String.init).filter { $0 != entry.id }
    recent.insert(entry.id, at: 0)
    savedRecent = recent.prefix(8).joined(separator: "\n")
    if let app = entry.app { suite.rememberApp(app) }
    onClose()
    router.go(path: entry.to)
  }
}

struct SearchSection: Identifiable {
  let id: String
  let label: String
  var entries: [SearchEntry]
}

/// Something search finds: an app, a page, or something to create.
struct SearchEntry: Identifiable, Sendable {
  enum Kind: Sendable { case page, action }

  /// "page:/invoices", "app:books", "action:invoice", as the web keys them.
  let id: String
  let kind: Kind
  let title: String
  let subtitle: String?
  let to: String
  let icon: Icon
  /// The app an app entry opens.
  var app: SuiteAppID?
  /// What a search matches, normalised.
  let terms: String
  let boost: Int
}

/// The web's static entries (`staticEntries` in `src/features/search/sources.ts`):
/// each app the person may open, its pages (under the app that owns them)
/// and footer links, and what they may create.
enum SearchIndex {
  @MainActor
  static func entries(suite: SuiteState, current: SuiteAppID) -> [SearchEntry] {
    let arabic = LanguageStore.shared.isArabic
    var entries: [SearchEntry] = []
    var seen = Set<String>()
    let apps = suite.visibleApps.sorted { ($0.id == current ? 0 : 1) < ($1.id == current ? 0 : 1) }

    func page(_ to: String, _ label: String, icon: Icon, boost: Int, keywords: String?, group: String?) {
      let key = "page:\(to)"
      guard !seen.contains(key) else { return }
      seen.insert(key)
      entries.append(
        SearchEntry(
          id: key, kind: .page, title: t(label), subtitle: group, to: to, icon: icon,
          terms: SearchText.normalize([t(label), label, keywords ?? "", group ?? ""].joined(separator: " ")),
          boost: boost))
    }

    for app in apps {
      let name = app.title(arabic: arabic)
      entries.append(
        SearchEntry(
          id: "app:\(app.id.rawValue)", kind: .page, title: name, subtitle: t(app.description), to: app.home,
          icon: app.icon, app: app.id,
          terms: SearchText.normalize([name, app.name, app.nameAr, t(app.description)].joined(separator: " ")),
          boost: 35))
      for entry in app.visibleNav(suite.flags) {
        switch entry {
        case .link(let link):
          page(
            link.to, link.label, icon: link.icon, boost: 30, keywords: link.keywords,
            group: app.id == .books ? nil : name)
        case .group(let group):
          for child in group.children {
            let place = app.id == .books ? t(group.label) : "\(name) · \(t(group.label))"
            page(child.to, child.label, icon: group.icon, boost: 30, keywords: child.keywords, group: place)
          }
        }
      }
      for link in app.footer {
        page(link.to, link.label, icon: link.icon, boost: 20, keywords: nil, group: nil)
      }
    }

    for group in suite.createGroups(current: current) {
      for action in group.actions {
        entries.append(
          SearchEntry(
            id: "action:\(action.id)", kind: .action, title: t(action.command), subtitle: nil, to: action.to,
            icon: action.icon,
            terms: SearchText.normalize(
              [t(action.command), action.command, t(action.label), action.label, action.keywords ?? "", "new create add"]
                .joined(separator: " ")),
            boost: 25))
      }
    }
    return entries
  }
}

/// The web's search normalisation (`src/features/search/normalize.ts`), so
/// "أحمد", "احمد" and the name with vowel marks find the same thing, and
/// "Café" matches "cafe": lower case, no marks, one form of each Arabic
/// letter, Western digits, single spaces.
enum SearchText {
  static func normalize(_ text: String) -> String {
    var out = String.UnicodeScalarView()
    var space = false
    for scalar in text.decomposedStringWithCompatibilityMapping.unicodeScalars {
      let v = scalar.value
      // Latin and Arabic marks, tatweel; bidi and joiner controls.
      if (0x0300...0x036F).contains(v) || (0x0610...0x061A).contains(v) || (0x064B...0x065F).contains(v)
        || v == 0x0670 || (0x06D6...0x06ED).contains(v) || v == 0x0640 || (0x200C...0x200F).contains(v)
        || (0x202A...0x202E).contains(v) || (0x2066...0x2069).contains(v)
      {
        continue
      }
      let mapped = map(scalar)
      for lower in String(mapped).lowercased().unicodeScalars {
        if isKept(lower) {
          if space, !out.isEmpty { out.append(" ") }
          space = false
          out.append(lower)
        } else {
          space = true
        }
      }
    }
    return String(out)
  }

  private static func map(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
    switch scalar.value {
    case 0x0623, 0x0625, 0x0622, 0x0671: return "\u{0627}"  // أ إ آ ٱ → ا
    case 0x0649, 0x0626, 0x06CC: return "\u{064A}"  // ى ئ ی → ي
    case 0x0629: return "\u{0647}"  // ة → ه
    case 0x0624: return "\u{0648}"  // ؤ → و
    case 0x06A9: return "\u{0643}"  // ک → ك
    case 0x0660...0x0669: return Unicode.Scalar(scalar.value - 0x0660 + 0x30) ?? scalar
    case 0x06F0...0x06F9: return Unicode.Scalar(scalar.value - 0x06F0 + 0x30) ?? scalar
    default: return scalar
    }
  }

  /// Letters, numbers, and `.@+-`.
  private static func isKept(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
      .decimalNumber, .letterNumber, .otherNumber:
      return true
    default:
      return ".@+-".unicodeScalars.contains(scalar)
    }
  }
}
