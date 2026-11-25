import SwiftUI

/// One choice of a `Combobox`.
struct ComboOption: Identifiable, Hashable, Sendable {
  let value: String
  let label: String
  /// Secondary text (email, SKU, price…).
  var detail: String?
  /// Words that find it but are not shown.
  var keywords: String?
  var id: String { value }

  init(value: String, label: String, detail: String? = nil, keywords: String? = nil) {
    self.value = value
    self.label = label
    self.detail = detail
    self.keywords = keywords
  }
}

/// The web's searchable select (`src/components/ui/combobox.tsx`): a field
/// that opens a panel with a search box, the matching options (the chosen
/// one checked) and, with `onCreate`, a "Create …" row for the text typed.
struct Combobox: View {
  @Binding var selection: String?
  let options: [ComboOption]
  var placeholder: String?
  var searchPlaceholder: String?
  var emptyText: String?
  var createLabel: String?
  var onCreate: ((String) -> Void)?
  @State private var open = false
  @State private var width: CGFloat = 256
  @Environment(\.palette) private var palette

  init(
    selection: Binding<String?>, options: [ComboOption], placeholder: String? = nil,
    searchPlaceholder: String? = nil, emptyText: String? = nil, createLabel: String? = nil,
    onCreate: ((String) -> Void)? = nil
  ) {
    _selection = selection
    self.options = options
    self.placeholder = placeholder
    self.searchPlaceholder = searchPlaceholder
    self.emptyText = emptyText
    self.createLabel = createLabel
    self.onCreate = onCreate
  }

  private var selected: ComboOption? {
    options.first { $0.value == selection }
  }

  var body: some View {
    Button {
      open = true
    } label: {
      HStack(spacing: 8) {
        Text(selected?.label ?? placeholder ?? t("Select…"))
          .foregroundStyle(selected == nil ? palette.slate(500) : palette.slate(900))
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
        IconView(.chevronsUpDown, size: 16).foregroundStyle(palette.slate(400))
      }
      .padding(.horizontal, 12)
      .modifier(InputChrome(focused: open))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    .anchoredPanel(isPresented: $open, alignment: .start, width: max(256, width)) {
      ComboPanel(
        selection: $selection, options: options, searchPlaceholder: searchPlaceholder,
        emptyText: emptyText, createLabel: createLabel, onCreate: onCreate)
    }
  }
}

private struct ComboPanel: View {
  @Binding var selection: String?
  let options: [ComboOption]
  let searchPlaceholder: String?
  let emptyText: String?
  let createLabel: String?
  let onCreate: ((String) -> Void)?
  @State private var query = ""
  @FocusState private var focused: Bool
  @Environment(\.palette) private var palette
  @Environment(\.dismissPanel) private var dismissPanel

  private var filtered: [ComboOption] {
    let q = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !q.isEmpty else { return Array(options.prefix(200)) }
    return Array(
      options.filter { "\($0.label) \($0.detail ?? "") \($0.keywords ?? "")".lowercased().contains(q) }
        .prefix(200))
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous)
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        IconView(.search, size: 16).foregroundStyle(palette.slate(400))
        ZStack(alignment: .leading) {
          if query.isEmpty {
            Text(searchPlaceholder ?? t("Search…")).foregroundStyle(palette.slate(400))
              .allowsHitTesting(false)
          }
          TextField("", text: $query)
            .focused($focused)
            .submitLabel(.done)
            .onSubmit(chooseFirst)
        }
        .font(.web(14))
      }
      .padding(.horizontal, 12)
      .frame(height: 40)
      .overlay(alignment: .bottom) { Rectangle().fill(palette.slate(100)).frame(height: 1) }

      ScrollView {
        VStack(spacing: 0) {
          if filtered.isEmpty && onCreate == nil {
            Text(emptyText ?? t("No matches"))
              .font(.web(14))
              .foregroundStyle(palette.slate(500))
              .frame(maxWidth: .infinity)
              .padding(.vertical, 24)
          }
          ForEach(filtered) { option in
            Button {
              selection = option.value
              dismissPanel()
            } label: {
              HStack(spacing: 8) {
                IconView(.check, size: 16)
                  .foregroundStyle(palette.primary(600))
                  .opacity(option.value == selection ? 1 : 0)
                VStack(alignment: .leading, spacing: 0) {
                  Text(option.label).font(.web(14)).foregroundStyle(palette.slate(900)).lineLimit(1)
                  if let detail = option.detail {
                    Text(detail).font(.web(12)).foregroundStyle(palette.slate(500)).lineLimit(1)
                  }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
              .padding(.horizontal, 10)
              .padding(.vertical, 8)
              .contentShape(Rectangle())
            }
            .buttonStyle(PressedFill(radius: WebRadius.sm))
            .accessibilityAddTraits(option.value == selection ? .isSelected : [])
          }
          if let onCreate {
            Button {
              onCreate(query.trimmingCharacters(in: .whitespaces))
              dismissPanel()
            } label: {
              HStack(spacing: 8) {
                IconView(.plus, size: 16)
                Text(createText).font(.web(14, .medium)).lineLimit(1)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .foregroundStyle(palette.primary(700))
              .padding(.horizontal, 10)
              .padding(.vertical, 8)
              .contentShape(Rectangle())
            }
            .buttonStyle(PressedFill(radius: WebRadius.sm, color: .primary(50)))
          }
        }
        .padding(4)
      }
      .frame(maxHeight: 288)
      .fixedSize(horizontal: false, vertical: true)
    }
    .background(palette.surface, in: shape)
    .clipShape(shape)
    .border(palette.slate(200), in: shape)
    .boxShadow(WebShadow.lg, in: shape)
    .task { focused = true }
  }

  private var createText: String {
    let text = query.trimmingCharacters(in: .whitespaces)
    let action = createLabel ?? t("Create")
    return text.isEmpty ? action : t("{action} “{text}”", ["action": action, "text": text])
  }

  private func chooseFirst() {
    if let first = filtered.first {
      selection = first.value
      dismissPanel()
    } else if let onCreate {
      onCreate(query.trimmingCharacters(in: .whitespaces))
      dismissPanel()
    }
  }
}
