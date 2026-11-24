import MahamKit
import SwiftUI

/// What is on screen: signing in, the lock, or the app.
struct RootView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    ZStack {
      switch model.phase {
      case .notConfigured:
        NotConfiguredView()
      case .starting:
        StartingView()
      case .signedOut:
        SignInView()
          .transition(.opacity)
      case .secondStep:
        SecondStepView()
          .transition(.move(edge: .trailing).combined(with: .opacity))
      case .locked:
        LockView()
          .transition(.opacity)
      case .ready:
        MainTabView()
          .transition(.opacity)
      }
    }
    .animation(.smooth(duration: 0.35), value: model.phase)
    .toast($model.toast)
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
