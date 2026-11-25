import SwiftUI

/// The web's dialogs are centred, not bottom sheets
/// (`src/components/ui/overlay.tsx`): the screen's width less 32pt, a 12pt
/// radius, shadow-xl, popping in from 97%. The header (20×16pt padding, a
/// line below) has the title and a close button; the body scrolls; the
/// footer sticks to the bottom on slate-50 with its buttons full width,
/// stacked with the last one (the primary) on top. The close and footer
/// buttons are Liquid Glass; the footer's play their haptics as they are
/// tapped, closing by the backdrop or the close button plays its own.
///
///     .webDialog(isPresented: $confirming, title: t("Sign out?")) {
///       Text(t("You can sign in again at any time."))
///     } footer: {
///       WebButton(t("Cancel"), variant: .outline) { confirming = false }
///       WebButton(t("Sign out")) { … }
///     }
extension View {
  func webDialog<DialogContent: View, Footer: View>(
    isPresented: Binding<Bool>, title: String, description: String? = nil,
    @ViewBuilder content: @escaping () -> DialogContent, @ViewBuilder footer: @escaping () -> Footer
  ) -> some View {
    modifier(
      WebDialogModifier(
        isPresented: isPresented, title: title, description: description, dialogContent: content,
        footer: footer))
  }

  func webDialog<DialogContent: View>(
    isPresented: Binding<Bool>, title: String, description: String? = nil,
    @ViewBuilder content: @escaping () -> DialogContent
  ) -> some View {
    webDialog(isPresented: isPresented, title: title, description: description, content: content) { EmptyView() }
  }
}

private struct WebDialogModifier<DialogBody: View, Footer: View>: ViewModifier {
  @Binding var isPresented: Bool
  let title: String
  let description: String?
  let dialogContent: () -> DialogBody
  let footer: () -> Footer
  /// The cover under the dialog; put up and taken down without the cover's
  /// own slide, so the dialog's pop-in is all that shows.
  @State private var covered = false

  func body(content: Content) -> some View {
    content
      .onChange(of: isPresented, initial: true) { _, wanted in
        if wanted && !covered { withoutAnimation { covered = true } }
      }
      .fullScreenCover(isPresented: $covered) {
        DialogFrame(
          isPresented: $isPresented, title: title, description: description,
          onGone: { withoutAnimation { covered = false } }, content: dialogContent, footer: footer
        )
        .presentationBackground(.clear)
        .webTheme()
      }
  }
}

private struct DialogFrame<DialogBody: View, Footer: View>: View {
  @Binding var isPresented: Bool
  let title: String
  let description: String?
  let onGone: () -> Void
  let content: () -> DialogBody
  let footer: () -> Footer
  @State private var shown = false
  @Environment(\.palette) private var palette

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        palette.overlay.opacity(shown ? 0.4 : 0)
          .ignoresSafeArea()
          .onTapGesture { close() }
          .accessibilityHidden(true)
        if shown {
          // The whole dialog when it fits; else its body scrolls between
          // the header and the footer.
          ViewThatFits(in: .vertical) {
            panel(scrolls: false)
            panel(scrolls: true)
          }
          .frame(width: max(0, proxy.size.width - 32), height: max(0, proxy.size.height - 32))
          .transition(.scale(scale: 0.97).combined(with: .opacity))
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .overlayHost()
    .onAppear {
      withAnimation(WebMotion.popIn) { shown = true }
    }
    .onChange(of: isPresented) { _, open in
      guard !open else { return }
      withAnimation(WebMotion.fade, completionCriteria: .logicallyComplete) {
        shown = false
      } completion: {
        onGone()
      }
    }
  }

  private func panel(scrolls: Bool) -> some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.lg, style: .continuous)
    return VStack(spacing: 0) {
      header
      if scrolls {
        ScrollView { bodyContent }
      } else {
        bodyContent
      }
      if Footer.self != EmptyView.self {
        StackedFooter(spacing: 8) { footer() }
          .environment(\.webButtonFullWidth, true)
          .padding(.horizontal, 20)
          .padding(.vertical, 12)
          .frame(maxWidth: .infinity)
          .background(palette.slate(50))
          .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
      }
    }
    .background(palette.surface, in: shape)
    .clipShape(shape)
    .boxShadow(WebShadow.xl, in: shape)
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
    .accessibilityAction(.escape) { close() }
  }

  private func close() {
    Haptics.play(.close)
    isPresented = false
  }

  private var bodyContent: some View {
    VStack(alignment: .leading, spacing: 16) { content() }
      .font(.web(14))
      .foregroundStyle(palette.slate(600))
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 20)
      .padding(.vertical, 16)
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title).webText(.cardTitle)
          .accessibilityAddTraits(.isHeader)
        if let description {
          Text(description).font(.web(14)).foregroundStyle(palette.slate(500))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      GlassIconButton(.x, label: t("Close"), shape: .rounded(WebRadius.md), haptic: nil) { close() }
        .padding(.top, -10)
        .padding(.trailing, -10)
        .padding(.bottom, -10)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
    .overlay(alignment: .bottom) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }
}

/// CSS `flex-col-reverse`: the views stacked full width, the last on top.
struct StackedFooter: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
    let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
    let total = heights.reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1))
    return CGSize(width: width, height: total)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var y = bounds.minY
    for subview in subviews.reversed() {
      let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
      subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: size.height))
      y += size.height + spacing
    }
  }
}
