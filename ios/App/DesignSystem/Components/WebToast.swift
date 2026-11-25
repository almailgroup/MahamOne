import SwiftUI
import UIKit

/// The web's toasts (Sonner, `richColors`, with a close button): at the
/// bottom, 92pt above the safe area, so they clear the tab bar; gone after
/// four seconds. Each plays the success or error haptic as it shows and is
/// read out by VoiceOver.
extension View {
  func webToast(_ toast: Binding<Toast?>) -> some View {
    modifier(WebToastModifier(toast: toast))
  }
}

private struct WebToastModifier: ViewModifier {
  @Binding var toast: Toast?

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .bottom) {
        if let current = toast {
          ToastCard(toast: current) { dismiss(current) }
            .padding(.horizontal, 16)
            .padding(.bottom, 92)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: current.id) {
              try? await Task.sleep(for: .seconds(4))
              dismiss(current)
            }
        }
      }
      .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.4), value: toast?.id)
      .onChange(of: toast?.id) { _, id in
        guard id != nil, let shown = toast else { return }
        Haptics.play(shown.kind == .error ? .error : .success)
        UIAccessibility.post(notification: .announcement, argument: shown.message)
      }
  }

  private func dismiss(_ shown: Toast) {
    if toast?.id == shown.id { toast = nil }
  }
}

private struct ToastCard: View {
  let toast: Toast
  let onClose: () -> Void
  @Environment(\.palette) private var palette
  @Environment(\.layoutDirection) private var direction

  var body: some View {
    let colors = ToastColors(kind: toast.kind, dark: palette.isDark)
    let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
    HStack(alignment: .center, spacing: 6) {
      ZStack {
        Circle().fill(colors.text).frame(width: 16, height: 16)
        IconView(toast.kind == .success ? .checkBold : .x, size: 10).foregroundStyle(colors.fill)
      }
      .accessibilityHidden(true)
      Text(toast.message)
        .font(.web(13, .medium))
        .foregroundStyle(colors.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(16)
    .background(colors.fill, in: shape)
    .border(colors.border, in: shape)
    .boxShadow([BoxShadow(color: .black.opacity(0.1), y: 4, blur: 12)], in: shape)
    // At the start corner, half outside, as Sonner places it (mirrored in Arabic).
    .overlay(alignment: .topLeading) {
      Button {
        Haptics.play(.tap)
        onClose()
      } label: {
        IconView(.x, size: 12)
          .foregroundStyle(colors.text)
          .frame(width: 20, height: 20)
          .background(colors.fill, in: Circle())
          .border(colors.border, in: Circle())
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .offset(x: direction == .rightToLeft ? 19 : -19, y: -19)
      .accessibilityLabel(Text(t("Close")))
    }
    .accessibilityElement(children: .contain)
  }
}

/// Sonner's rich colours, light and dark.
private struct ToastColors {
  let fill: Color
  let border: Color
  let text: Color

  init(kind: Toast.Kind, dark: Bool) {
    switch (kind, dark) {
    case (.success, false):
      fill = Color(red: 0.926, green: 0.994, blue: 0.952)
      border = Color(red: 0.750, green: 0.990, blue: 0.850)
      text = Color(red: 0, green: 0.54, blue: 0.18)
    case (.error, false):
      fill = Color(red: 1, green: 0.94, blue: 0.941)
      border = Color(red: 1, green: 0.88, blue: 0.882)
      text = Color(red: 0.9, green: 0, blue: 0)
    case (.success, true):
      fill = Color(red: 0, green: 0.12, blue: 0.06)
      border = Color(red: 0, green: 0.24, blue: 0.108)
      text = Color(red: 0.349, green: 0.951, blue: 0.65)
    case (.error, true):
      fill = Color(red: 0.176, green: 0.024, blue: 0.029)
      border = Color(red: 0.302, green: 0.018, blue: 0.032)
      text = Color(red: 1, green: 0.62, blue: 0.633)
    }
  }
}
