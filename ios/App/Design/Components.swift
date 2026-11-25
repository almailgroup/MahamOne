import MahamKit
import SwiftUI

// The pieces every screen is made of. Liquid Glass sits on the controls and
// the cards; under them is one soft gradient, so the glass has colour to
// bend. Screens use these instead of their own, so the app reads as one.

// MARK: The background

/// The gradient under every screen: the brand's indigo, a little teal and
/// violet, quiet in both light and dark.
struct MahamBackground: View {
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    MeshGradient(
      width: 3, height: 3,
      points: [
        [0, 0], [0.5, 0], [1, 0],
        [0, 0.5], [0.62, 0.42], [1, 0.5],
        [0, 1], [0.5, 1], [1, 1],
      ],
      colors: scheme == .dark ? Self.dark : Self.light
    )
    .ignoresSafeArea()
    .accessibilityHidden(true)
  }

  private static let light: [Color] = [
    Color(red: 0.90, green: 0.91, blue: 0.99), Color(red: 0.94, green: 0.95, blue: 0.98), Color(red: 0.88, green: 0.96, blue: 0.96),
    Color(red: 0.95, green: 0.94, blue: 0.99), Color(red: 0.94, green: 0.95, blue: 0.97), Color(red: 0.93, green: 0.92, blue: 0.99),
    Color(red: 0.92, green: 0.96, blue: 0.98), Color(red: 0.94, green: 0.95, blue: 0.97), Color(red: 0.91, green: 0.90, blue: 0.99),
  ]

  private static let dark: [Color] = [
    Color(red: 0.10, green: 0.11, blue: 0.26), Color(red: 0.05, green: 0.07, blue: 0.13), Color(red: 0.03, green: 0.14, blue: 0.17),
    Color(red: 0.08, green: 0.07, blue: 0.18), Color(red: 0.05, green: 0.07, blue: 0.13), Color(red: 0.12, green: 0.07, blue: 0.22),
    Color(red: 0.04, green: 0.10, blue: 0.16), Color(red: 0.05, green: 0.07, blue: 0.13), Color(red: 0.09, green: 0.08, blue: 0.22),
  ]
}

extension View {
  /// A screen's base: the gradient behind, lists and forms see-through.
  func mahamScreen() -> some View {
    self
      .scrollContentBackground(.hidden)
      .background { MahamBackground() }
  }

  /// A card of Liquid Glass. `tint` colours it lightly; `interactive` makes it
  /// respond to a touch (for cards that are buttons).
  func glassCard(
    cornerRadius: CGFloat = 24, padding: CGFloat = 16, tint: Color? = nil, interactive: Bool = false
  ) -> some View {
    self
      .padding(padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .glassEffect(
        Glass.regular.tint(tint?.opacity(0.18)).interactive(interactive),
        in: .rect(cornerRadius: cornerRadius, style: .continuous))
  }

  /// A list row see-through to the gradient, instead of the grouped list's
  /// grey.
  func glassRow() -> some View {
    self.listRowBackground(Rectangle().fill(.regularMaterial))
  }
}

// MARK: Cards

/// A titled group of content on glass, for scroll views (not lists).
struct GlassSection<Content: View, Trailing: View>: View {
  let title: LocalizedStringKey
  var symbol: String?
  @ViewBuilder var trailing: Trailing
  @ViewBuilder var content: Content

  init(
    _ title: LocalizedStringKey, symbol: String? = nil,
    @ViewBuilder trailing: () -> Trailing,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.symbol = symbol
    self.trailing = trailing()
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        if let symbol {
          Label(title, systemImage: symbol).font(.headline)
        } else {
          Text(title).font(.headline)
        }
        Spacer()
        trailing.font(.subheadline)
      }
      content
    }
    .glassCard()
  }
}

extension GlassSection where Trailing == EmptyView {
  init(_ title: LocalizedStringKey, symbol: String? = nil, @ViewBuilder content: () -> Content) {
    self.init(title, symbol: symbol, trailing: { EmptyView() }, content: content)
  }
}

/// A number with a name: "3 Overdue", "KWD 1,250.000 Receivable".
struct MetricTile: View {
  let title: LocalizedStringKey
  let value: String
  var symbol: String
  var tint: Color = .accentColor
  var detail: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Image(systemName: symbol)
        .font(.title3.weight(.semibold))
        .foregroundStyle(tint)
        .symbolRenderingMode(.hierarchical)
      Text(value)
        .font(.title2.weight(.bold))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .contentTransition(.numericText())
      Text(title)
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
      if let detail {
        Text(detail).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
      }
    }
    .glassCard(cornerRadius: 22, padding: 14, tint: tint)
    .accessibilityElement(children: .combine)
  }
}

// MARK: Badges

/// A task's status, coloured as on the web.
struct StatusBadge: View {
  let status: TaskStatus
  var compact = false

  var body: some View {
    Label(status.label, systemImage: status.symbol)
      .labelStyle(.titleAndIcon)
      .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
      .foregroundStyle(status.color)
      .padding(.horizontal, compact ? 6 : 8)
      .padding(.vertical, compact ? 2 : 4)
      .background(status.color.opacity(0.14), in: .capsule)
  }
}

/// An invoice's state.
struct DocumentBadge: View {
  let status: DocumentStatus
  var overdue = false

  var body: some View {
    let color = overdue ? Color.red : status.color
    Text(overdue ? LocalizedStringKey("Overdue") : status.label)
      .font(.caption.weight(.semibold))
      .foregroundStyle(color)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(color.opacity(0.14), in: .capsule)
  }
}

/// Four bars, filled to the priority, as the website draws it.
struct PriorityBars: View {
  let priority: TaskPriority

  var body: some View {
    HStack(alignment: .bottom, spacing: 2) {
      ForEach(1...4, id: \.self) { bar in
        RoundedRectangle(cornerRadius: 1.5)
          .fill(bar <= priority.weight ? priority.color : Color.secondary.opacity(0.25))
          .frame(width: 3, height: CGFloat(4 + bar * 3))
      }
    }
    .accessibilityElement()
    .accessibilityLabel(Text("Priority: \(Text(priority.label))"))
  }
}

/// A due date: red when it has passed.
struct DueLabel: View {
  let date: Date
  var done = false

  var body: some View {
    let late = !done && date < .now
    Label(date.relativeDue, systemImage: late ? "exclamationmark.circle" : "calendar")
      .font(.caption.weight(.medium))
      .foregroundStyle(late ? .red : .secondary)
  }
}

// MARK: People

/// A person's initials on their colour.
struct AvatarView: View {
  let name: String
  let id: String
  var size: CGFloat = 28

  init(profile: TasksProfile, size: CGFloat = 28) {
    name = profile.initials
    id = profile.id
    self.size = size
  }

  init(initials: String, id: String, size: CGFloat = 28) {
    name = initials
    self.id = id
    self.size = size
  }

  var body: some View {
    Text(name)
      .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(PersonColor.of(id).gradient, in: .circle)
      .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
      .accessibilityHidden(true)
  }
}

/// Up to three avatars, overlapping, and "+2" for the rest.
struct AvatarStack: View {
  let people: [TasksProfile]
  var size: CGFloat = 24

  var body: some View {
    HStack(spacing: -size * 0.3) {
      ForEach(people.prefix(3)) { AvatarView(profile: $0, size: size) }
      if people.count > 3 {
        Text("+\(people.count - 3)")
          .font(.system(size: size * 0.38, weight: .semibold))
          .frame(width: size, height: size)
          .background(.thinMaterial, in: .circle)
      }
    }
    .accessibilityElement()
    .accessibilityLabel(Text(people.map(\.displayName).formatted(.list(type: .and))))
  }
}

// MARK: States

/// Nothing to show, said kindly.
struct EmptyState: View {
  let title: LocalizedStringKey
  let symbol: String
  var message: LocalizedStringKey?

  var body: some View {
    ContentUnavailableView {
      Label(title, systemImage: symbol)
    } description: {
      if let message { Text(message) }
    }
  }
}

/// A banner at the top of a screen: offline, read-only, not in Tasks.
struct NoticeBanner: View {
  let text: LocalizedStringKey
  var symbol = "info.circle"
  var tint: Color = .blue

  var body: some View {
    Label(text, systemImage: symbol)
      .font(.footnote.weight(.medium))
      .foregroundStyle(tint)
      .glassCard(cornerRadius: 16, padding: 12, tint: tint)
  }
}

// MARK: Toasts

extension View {
  /// The app's messages ("Saved", "You're offline") at the bottom of the
  /// screen, on glass, gone after a few seconds.
  func toast(_ toast: Binding<Toast?>) -> some View {
    modifier(ToastModifier(toast: toast))
  }
}

private struct ToastModifier: ViewModifier {
  @Binding var toast: Toast?

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .bottom) {
        if let current = toast {
          Label {
            Text(LocalizedStringKey(current.message))
          } icon: {
            Image(systemName: current.kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
              .foregroundStyle(current.kind == .success ? .green : .orange)
          }
          .font(.subheadline.weight(.medium))
          .padding(.horizontal, 18)
          .padding(.vertical, 12)
          .glassEffect(.regular.interactive(), in: .capsule)
          .padding(.horizontal, 24)
          .padding(.bottom, 96)
          .transition(.move(edge: .bottom).combined(with: .opacity))
          .onTapGesture { toast = nil }
          .task(id: current.id) {
            try? await Task.sleep(for: .seconds(3.5))
            if toast?.id == current.id { toast = nil }
          }
          .accessibilityAddTraits(.updatesFrequently)
        }
      }
      .animation(.spring(duration: 0.35), value: toast)
      .haptic(trigger: toast) { _, new in
        guard let new else { return nil }
        return new.kind == .error ? .error : .success
      }
  }
}
