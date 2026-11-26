import MahamKit
import SwiftUI

// The pieces the inventory pages share: a phone list row with an optional
// third line, the web's `Stat` figures, label–value cards whose values can
// open a page, a table's column heads, and the read-only item dialog.

// MARK: A row

/// One row of a phone list: the title (16pt, 500), a line under it (12pt
/// slate-500) and an optional third (12pt slate-600) at the start; the
/// amount (14pt, 600, tabular) over the badges at the end. With `action`
/// the whole row is one tap target. `indent` moves it in at the start (a
/// sub-warehouse under its main one).
struct InvRow<Badges: View>: View {
  let title: String
  var subtitle: String?
  var detail: String?
  var amount: String?
  var amountTone: Token?
  var icon: Icon?
  var indent: CGFloat
  private let badges: Badges
  var action: (() -> Void)?
  @Environment(\.palette) private var palette

  init(
    title: String, subtitle: String? = nil, detail: String? = nil, amount: String? = nil,
    amountTone: Token? = nil, icon: Icon? = nil, indent: CGFloat = 0,
    @ViewBuilder badges: () -> Badges, action: (() -> Void)? = nil
  ) {
    self.title = title
    self.subtitle = subtitle
    self.detail = detail
    self.amount = amount
    self.amountTone = amountTone
    self.icon = icon
    self.indent = indent
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
    HStack(spacing: 12) {
      if let icon {
        IconView(icon, size: 20).foregroundStyle(palette.slate(indent > 0 ? 300 : 400))
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.web(16, .medium))
          .foregroundStyle(palette.slate(900))
          .lineLimit(2)
          .multilineTextAlignment(.leading)
        if let subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.web(12))
            .foregroundStyle(palette.slate(500))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        }
        if let detail, !detail.isEmpty {
          Text(detail)
            .font(.web(12, tabular: true))
            .foregroundStyle(palette.slate(600))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if amount != nil || Badges.self != EmptyView.self {
        VStack(alignment: .trailing, spacing: 4) {
          if let amount {
            Text(amount)
              .font(.web(14, .semibold, tabular: true))
              .foregroundStyle(palette.color(amountTone ?? .slate(900)))
              .lineLimit(1)
          }
          HStack(spacing: 4) { badges }
        }
        .fixedSize()
      }
    }
    .padding(.leading, 16 + indent)
    .padding(.trailing, 16)
    .padding(.vertical, 12)
    .frame(minHeight: 56)
    .contentShape(Rectangle())
  }
}

extension InvRow where Badges == EmptyView {
  init(
    title: String, subtitle: String? = nil, detail: String? = nil, amount: String? = nil,
    amountTone: Token? = nil, icon: Icon? = nil, indent: CGFloat = 0, action: (() -> Void)? = nil
  ) {
    self.init(
      title: title, subtitle: subtitle, detail: detail, amount: amount, amountTone: amountTone, icon: icon,
      indent: indent, badges: { EmptyView() }, action: action)
  }
}

// MARK: Figures

/// The web's `Stat`: a card (20pt padding) with the label (14pt, 500,
/// slate-500), the figure (24pt, 600, tight; red-700 when it calls for
/// attention) and a hint (12pt slate-500, or a primary-700 link).
struct InvStat: View {
  let label: String
  let value: String
  var hint: String?
  var danger = false
  var onHint: (() -> Void)?
  @Environment(\.palette) private var palette
  @Environment(\.layoutDirection) private var direction

  var body: some View {
    Card {
      VStack(alignment: .leading, spacing: 0) {
        Text(label)
          .font(.web(14, .medium))
          .foregroundStyle(palette.slate(500))
        Text(value)
          .font(.web(24, .semibold, tabular: true))
          .tracking(direction == .rightToLeft ? 0 : -0.6)
          .foregroundStyle(danger ? palette[.red(700)] : palette.slate(900))
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .padding(.top, 8)
        hintView
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(20)
    }
  }

  @ViewBuilder
  private var hintView: some View {
    if let hint, let onHint {
      Button {
        Haptics.play(.tap)
        onHint()
      } label: {
        Text(hint)
          .font(.web(12))
          .foregroundStyle(palette.primary(700))
          .frame(minHeight: 28, alignment: .leading)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .padding(.top, 2)
    } else if let hint {
      Text(hint)
        .font(.web(12))
        .foregroundStyle(palette.slate(500))
        .padding(.top, 4)
    }
  }
}

/// The figures above a list (`grid gap-4 sm:grid-cols-3`): one under the
/// other on a phone, 16pt apart, 24pt above what follows.
struct InvStats<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    VStack(spacing: 16) { content }
      .padding(.bottom, 24)
  }
}

// MARK: Facts

/// A label and its value on a card; with a route, the value is a link.
struct InvFact {
  let label: String
  let value: String
  var route: Route?
  var tone: Token?
  var strong = false
  var tabular = false

  init(
    _ label: String, _ value: String, route: Route? = nil, tone: Token? = nil, strong: Bool = false,
    tabular: Bool = false
  ) {
    self.label = label
    self.value = value
    self.route = route
    self.tone = tone
    self.strong = strong
    self.tabular = tabular
  }
}

/// The label–value rows of a summary card (the web's `dl`): each label in
/// 14pt slate-500 at the start, its value in 14pt slate-900 at the end (a
/// link in primary-700); rows whose value is empty are left out.
struct InvFactRows: View {
  let facts: [InvFact]
  var inset: CGFloat = 20
  var onOpen: ((Route) -> Void)?
  @Environment(\.palette) private var palette

  var body: some View {
    let shown = facts.filter { !$0.value.isEmpty }
    VStack(spacing: 0) {
      ForEach(Array(shown.indices), id: \.self) { index in
        row(shown[index], first: index == 0)
      }
    }
  }

  private func row(_ fact: InvFact, first: Bool) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(fact.label)
        .font(.web(14))
        .foregroundStyle(palette.slate(500))
      Spacer(minLength: 8)
      value(fact)
    }
    .padding(.horizontal, inset)
    .padding(.vertical, 11)
    .overlay(alignment: .top) {
      if !first { Rectangle().fill(palette.slate(100)).frame(height: 1) }
    }
  }

  @ViewBuilder
  private func value(_ fact: InvFact) -> some View {
    if let route = fact.route, let onOpen {
      Button {
        Haptics.play(.tap)
        onOpen(route)
      } label: {
        Text(fact.value)
          .font(.web(14, .medium, tabular: fact.tabular))
          .foregroundStyle(palette.primary(700))
          .multilineTextAlignment(.trailing)
          .frame(minHeight: 22)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    } else {
      Text(fact.value)
        .font(.web(14, fact.strong ? .semibold : .regular, tabular: fact.tabular))
        .foregroundStyle(fact.tone.map { palette.color($0) } ?? palette.slate(900))
        .multilineTextAlignment(.trailing)
        .textSelection(.enabled)
    }
  }
}

/// A card of facts, with an optional title and a note under them; left out
/// when it has nothing to show.
struct InvFactsCard: View {
  let title: String?
  let facts: [InvFact]
  var note: String?
  var onOpen: ((Route) -> Void)?

  init(_ title: String? = nil, facts: [InvFact], note: String? = nil, onOpen: ((Route) -> Void)? = nil) {
    self.title = title
    self.facts = facts
    self.note = note
    self.onOpen = onOpen
  }

  var body: some View {
    if facts.contains(where: { !$0.value.isEmpty }) || note != nil {
      Card {
        if let title { CardHeader(title) }
        InvFactRows(facts: facts, onOpen: onOpen)
          .padding(.vertical, 4)
        if let note {
          InvCardNote(note)
        }
      }
    }
  }
}

/// A line of text across a card (what an entry posted, why nothing is
/// allocated): 14pt slate-600 over a slate-100 line.
struct InvCardNote: View {
  let text: String
  var tone: Token
  var line: Bool
  @Environment(\.palette) private var palette

  init(_ text: String, tone: Token = .slate(600), line: Bool = true) {
    self.text = text
    self.tone = tone
    self.line = line
  }

  var body: some View {
    Text(text)
      .font(.web(14))
      .foregroundStyle(palette.color(tone))
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .overlay(alignment: .top) {
        if line { Rectangle().fill(palette.slate(100)).frame(height: 1) }
      }
  }
}

/// A table's column heads on a phone list (`thead`: 12pt, 500, slate-500
/// on slate-50): the first at the start, the other at the end.
struct InvColumns: View {
  let start: String
  let end: String
  @Environment(\.palette) private var palette

  init(_ start: String, _ end: String) {
    self.start = start
    self.end = end
  }

  var body: some View {
    HStack(spacing: 12) {
      Text(start)
      Spacer(minLength: 8)
      Text(end)
    }
    .font(.web(12, .medium))
    .foregroundStyle(palette.slate(500))
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity)
    .background(palette.slate(50).opacity(0.6))
  }
}

/// "Nothing matches.": the web's line when a search or filter leaves no rows.
struct InvNothingMatches: View {
  @Environment(\.palette) private var palette

  var body: some View {
    Text(t("Nothing matches."))
      .font(.web(14))
      .foregroundStyle(palette.slate(500))
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 16)
      .padding(.vertical, 40)
  }
}

/// A badge of the list rows and titles, from its English label and tone.
struct InvBadge: Identifiable {
  let label: String
  let tone: StatusTone
  var id: String { label }

  init(_ meta: StatusMeta) {
    label = t(meta.label)
    tone = meta.tone
  }

  init(text: String, tone: StatusTone) {
    self.label = text
    self.tone = tone
  }
}

// MARK: The item dialog

/// One movement of an item as its dialog lists it.
struct InvMovementLine: Identifiable {
  let id: String
  let title: String
  let subtitle: String
  let detail: String
  let amount: String?
  let negative: Bool
  let route: Route
}

/// What the read-only item dialog shows, worked out by the page.
struct InvItemSheet {
  let id: String
  let title: String
  let badges: [InvBadge]
  let facts: [InvFact]
  /// On hand in each warehouse (when there is more than one).
  let warehouses: [InvFact]
  let movements: [InvMovementLine]
  /// The item keeps stock (its movements are listed, or "none yet").
  let isStock: Bool
}

/// The item dialog's body: its badges, its fields, the stock per warehouse
/// and every movement (the web's stock-movements report for the item), each
/// opening what it came from.
struct InvItemDetails: View {
  let sheet: InvItemSheet
  let onOpen: (Route) -> Void
  @Environment(\.palette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if !sheet.badges.isEmpty {
        FlowLayout(spacing: 6, lineSpacing: 6) {
          ForEach(sheet.badges) { badge in
            Badge(badge.label, tone: badge.tone)
          }
        }
      }
      InvFactRows(facts: sheet.facts, inset: 0)
      if !sheet.warehouses.isEmpty {
        section(t("Warehouses")) {
          InvFactRows(facts: sheet.warehouses, inset: 0)
        }
      }
      if sheet.isStock {
        section(t("Stock movements")) {
          movementList
        }
      }
    }
  }

  @ViewBuilder
  private var movementList: some View {
    if sheet.movements.isEmpty {
      Text(t("No movements in this period."))
        .font(.web(14))
        .foregroundStyle(palette.slate(500))
    } else {
      VStack(spacing: 0) {
        ForEach(sheet.movements) { line in
          movementRow(line)
        }
      }
      .padding(.horizontal, -16)
    }
  }

  private func movementRow(_ line: InvMovementLine) -> some View {
    InvRow(
      title: line.title, subtitle: line.subtitle, detail: line.detail, amount: line.amount,
      amountTone: line.negative ? .red(600) : nil, action: { onOpen(line.route) })
  }

  private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.web(14, .semibold))
        .foregroundStyle(palette.slate(900))
      content()
    }
  }
}
