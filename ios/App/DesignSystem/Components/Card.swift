import SwiftUI

/// The web's `Card`: surface, 12pt radius, a slate-200 border and shadow-xs.
/// Its content stacks from the top, full width.
struct Card<Content: View>: View {
  private let content: Content
  @Environment(\.palette) private var palette

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.lg, style: .continuous)
    VStack(alignment: .leading, spacing: 0) {
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(palette.surface, in: shape)
    .clipShape(shape)
    .border(palette.slate(200), in: shape)
    .boxShadow(WebShadow.xs, in: shape)
  }
}

/// A card's title row: 20×16pt padding and a slate-100 line below; the
/// actions sit at the end.
struct CardHeader<Actions: View>: View {
  let title: String
  var description: String?
  private let actions: Actions
  @Environment(\.palette) private var palette

  init(_ title: String, description: String? = nil, @ViewBuilder actions: () -> Actions) {
    self.title = title
    self.description = description
    self.actions = actions()
  }

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title).webText(.cardTitle)
        if let description {
          Text(description).font(.web(14)).foregroundStyle(palette.slate(500))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      HStack(spacing: 8) { actions }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
    .overlay(alignment: .bottom) {
      Rectangle().fill(palette.slate(100)).frame(height: 1)
    }
  }
}

extension CardHeader where Actions == EmptyView {
  init(_ title: String, description: String? = nil) {
    self.init(title, description: description) { EmptyView() }
  }
}

/// A card's body: 20pt padding.
struct CardBody<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) { content }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(20)
  }
}
