import SwiftUI

/// The phone list (`src/apps/books/pages/documents/list.tsx`): a card with
/// an optional header (the segmented filter and the search box, 16pt
/// padding, a line below), then the rows divided by slate-100 lines.
///
///     ListCard {
///       Segmented(selection: $filter, options: …)
///       TextInput(text: $query, placeholder: t("Search number, client, PO…"), leadingIcon: .search)
///     } rows: {
///       ForEach(rows) { ListRow(title: …, subtitle: …, amount: …) { Badge(status: …) } action: { … } }
///     }
struct ListCard<Header: View, Rows: View>: View {
  private let header: Header
  private let rows: Rows
  @Environment(\.palette) private var palette

  init(@ViewBuilder header: () -> Header, @ViewBuilder rows: () -> Rows) {
    self.header = header()
    self.rows = rows()
  }

  var body: some View {
    Card {
      if Header.self != EmptyView.self {
        VStack(alignment: .leading, spacing: 12) { header }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(16)
          .overlay(alignment: .bottom) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
      }
      // Each row draws the line above it; the first one's is cut off, as
      // CSS's divide-y leaves it out.
      VStack(spacing: 0) { rows }
        .padding(.top, -1)
        .clipped()
    }
  }
}

extension ListCard where Header == EmptyView {
  init(@ViewBuilder rows: () -> Rows) {
    self.init(header: { EmptyView() }, rows: rows)
  }
}

/// One row of a phone list, a single tap target at least 56pt tall: the
/// title (16pt, 500) over "number · date" (12pt slate-500) at the start;
/// the amount (14pt, 600, tabular) over the badges at the end.
struct ListRow<Leading: View, Status: View>: View {
  let title: String
  var subtitle: String?
  var amount: String?
  private let leading: Leading
  private let status: Status
  var action: (() -> Void)?
  @Environment(\.palette) private var palette

  init(
    title: String, subtitle: String? = nil, amount: String? = nil,
    @ViewBuilder leading: () -> Leading, @ViewBuilder status: () -> Status, action: (() -> Void)? = nil
  ) {
    self.title = title
    self.subtitle = subtitle
    self.amount = amount
    self.leading = leading()
    self.status = status()
    self.action = action
  }

  var body: some View {
    Group {
      if let action {
        Button(action: action) { content }
          .buttonStyle(PressedFill(radius: 0, color: .slate(100)))
      } else {
        content
      }
    }
    .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }

  private var content: some View {
    HStack(spacing: 12) {
      if Leading.self != EmptyView.self {
        leading
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.web(16, .medium))
          .foregroundStyle(palette.slate(900))
          .lineLimit(1)
        if let subtitle {
          Text(subtitle)
            .font(.web(12))
            .foregroundStyle(palette.slate(500))
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if amount != nil || Status.self != EmptyView.self {
        VStack(alignment: .trailing, spacing: 4) {
          if let amount {
            Text(amount)
              .font(.web(14, .semibold, tabular: true))
              .foregroundStyle(palette.slate(900))
              .lineLimit(1)
              .environment(\.layoutDirection, .leftToRight)
          }
          HStack(spacing: 4) { status }
        }
        .fixedSize()
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(minHeight: 56)
    .contentShape(Rectangle())
  }
}

extension ListRow where Leading == EmptyView {
  init(
    title: String, subtitle: String? = nil, amount: String? = nil,
    @ViewBuilder status: () -> Status, action: (() -> Void)? = nil
  ) {
    self.init(title: title, subtitle: subtitle, amount: amount, leading: { EmptyView() }, status: status, action: action)
  }
}

extension ListRow where Leading == EmptyView, Status == EmptyView {
  init(title: String, subtitle: String? = nil, amount: String? = nil, action: (() -> Void)? = nil) {
    self.init(
      title: title, subtitle: subtitle, amount: amount, leading: { EmptyView() }, status: { EmptyView() },
      action: action)
  }
}

/// Below a list: the count and totals, 14pt slate-500 over a line.
struct ListCardFooter<Content: View>: View {
  private let content: Content
  @Environment(\.palette) private var palette

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) { content }
      .font(.web(14))
      .foregroundStyle(palette.slate(500))
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }
}

/// "Show more (N remaining)" after the rows shown.
struct ListShowMore: View {
  let remaining: Int
  let action: () -> Void
  @Environment(\.palette) private var palette

  var body: some View {
    WebButton(t("Show more ({count} remaining)", ["count": "\(remaining)"]), variant: .ghost, size: .sm, action: action)
      .frame(maxWidth: .infinity)
      .padding(12)
      .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }
}
