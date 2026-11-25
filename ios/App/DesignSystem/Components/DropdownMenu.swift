import SwiftUI

/// The web's dropdown menus (`DropdownMenu` in `src/components/ui/overlay.tsx`):
/// an anchored panel on surface with an 8pt radius, a slate-200 border, 4pt
/// padding and shadow-lg, at least 192pt wide. Fill it with `DropdownItem`,
/// `DropdownLabel` and `DropdownSeparator`; an item closes the menu once chosen.
///
///     DropdownMenu(alignment: .end) {
///       IconView(.moreHorizontal)
///     } items: {
///       DropdownItem(t("Edit"), icon: .pencil) { … }
///       DropdownSeparator()
///       DropdownItem(t("Delete"), icon: .trash2, danger: true) { … }
///     }
struct DropdownMenu<Label: View, Items: View>: View {
  var alignment: PanelAlignment
  var width: CGFloat?
  private let label: Label
  private let items: () -> Items
  @State private var open = false

  init(
    alignment: PanelAlignment = .end, width: CGFloat? = nil, @ViewBuilder label: () -> Label,
    @ViewBuilder items: @escaping () -> Items
  ) {
    self.alignment = alignment
    self.width = width
    self.label = label()
    self.items = items
  }

  var body: some View {
    Button {
      open = true
    } label: {
      label
    }
    .buttonStyle(.plain)
    .dropdownPanel(isPresented: $open, alignment: alignment, width: width, items: items)
  }
}

extension View {
  /// The dropdown panel anchored to this view, for a button styled elsewhere.
  func dropdownPanel<Items: View>(
    isPresented: Binding<Bool>, alignment: PanelAlignment = .end, width: CGFloat? = nil,
    @ViewBuilder items: @escaping () -> Items
  ) -> some View {
    anchoredPanel(isPresented: isPresented, alignment: alignment, width: width) {
      DropdownPanel(content: items)
    }
  }
}

/// The panel's look, for menus built by hand.
struct DropdownPanel<Content: View>: View {
  private let content: Content
  @Environment(\.palette) private var palette

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous)
    VStack(alignment: .leading, spacing: 0) { content }
      .padding(4)
      .frame(minWidth: 192, alignment: .leading)
      .background(palette.surface, in: shape)
      .border(palette.slate(200), in: shape)
      .boxShadow(WebShadow.lg, in: shape)
  }
}

/// A menu row: at least 44pt, 14pt slate-700 with a 16pt slate-500 icon;
/// a danger row is red-600 on red-50.
struct DropdownItem<Trailing: View>: View {
  let title: String
  var icon: Icon?
  /// Keeps the icon's room when there is none (the unchecked rows of a list).
  var reservesIcon = false
  var danger: Bool
  private let trailing: Trailing
  let action: () -> Void
  @Environment(\.palette) private var palette
  @Environment(\.dismissPanel) private var dismissPanel
  @Environment(\.isEnabled) private var isEnabled

  init(
    _ title: String, icon: Icon? = nil, reservesIcon: Bool = false, danger: Bool = false,
    @ViewBuilder trailing: () -> Trailing, action: @escaping () -> Void
  ) {
    self.title = title
    self.icon = icon
    self.reservesIcon = reservesIcon
    self.danger = danger
    self.trailing = trailing()
    self.action = action
  }

  var body: some View {
    Button {
      dismissPanel()
      action()
    } label: {
      HStack(spacing: 8) {
        if let icon {
          IconView(icon, size: 16).foregroundStyle(danger ? palette[.red(500)] : palette.slate(500))
        } else if reservesIcon {
          Color.clear.frame(width: 16, height: 16)
        }
        Text(title)
          .font(.web(14))
          .foregroundStyle(danger ? palette[.red(600)] : palette.slate(700))
          .frame(maxWidth: .infinity, alignment: .leading)
        trailing
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(PressedFill(radius: WebRadius.sm, color: danger ? .red(50) : .slate(100)))
    .opacity(isEnabled ? 1 : 0.5)
  }
}

extension DropdownItem where Trailing == EmptyView {
  init(
    _ title: String, icon: Icon? = nil, reservesIcon: Bool = false, danger: Bool = false,
    action: @escaping () -> Void
  ) {
    self.init(title, icon: icon, reservesIcon: reservesIcon, danger: danger, trailing: { EmptyView() }, action: action)
  }
}

/// A heading in a menu: 12pt weight 500 slate-500.
struct DropdownLabel: View {
  let title: String
  @Environment(\.palette) private var palette

  init(_ title: String) { self.title = title }

  var body: some View {
    Text(title)
      .font(.web(12, .medium))
      .foregroundStyle(palette.slate(500))
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// A slate-100 line between a menu's groups.
struct DropdownSeparator: View {
  @Environment(\.palette) private var palette

  var body: some View {
    Rectangle().fill(palette.slate(100)).frame(height: 1).padding(.vertical, 4)
  }
}
