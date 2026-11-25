import MahamKit
import SwiftUI

/// What is on screen: signing in, the lock, or the app: Maham One's phone
/// shell (`WebShell`), in the web's theme, fonts and reading direction. The
/// sign-in and lock screens stay as they were, in the system's fonts.
struct RootView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    ZStack {
      switch model.phase {
      case .notConfigured:
        NotConfiguredView()
          .systemDesign()
      case .starting:
        StartingView()
          .systemDesign()
      case .signedOut:
        SignInView()
          .systemDesign()
          .transition(.opacity)
      case .secondStep:
        SecondStepView()
          .systemDesign()
          .transition(.move(edge: .trailing).combined(with: .opacity))
      case .locked:
        LockView()
          .systemDesign()
          .transition(.opacity)
      case .ready:
        WebShell()
          .transition(.opacity)
      }
    }
    .animation(.smooth(duration: 0.35), value: model.phase)
    .webToast($model.toast)
    .webTheme()
  }
}

/// The moment between launch and knowing who is signed in.
private struct StartingView: View {
  var body: some View {
    VStack(spacing: 18) {
      BrandMark(size: 76)
      ProgressView()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { MahamBackground() }
  }
}

/// The Maham One mark, on glass.
struct BrandMark: View {
  var size: CGFloat = 64

  var body: some View {
    Image("Logo")
      .resizable()
      .interpolation(.high)
      .scaledToFit()
      .frame(width: size, height: size)
      .clipShape(.rect(cornerRadius: size * 0.225, style: .continuous))
      .padding(size * 0.08)
      .glassEffect(.regular, in: .rect(cornerRadius: size * 0.3, style: .continuous))
      .accessibilityLabel(Text("Maham One"))
  }
}
