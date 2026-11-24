import LocalAuthentication
import MahamKit
import SwiftUI

/// The authenticator app's six digits, after the password.
struct SecondStepView: View {
  @Environment(AppModel.self) private var model
  @State private var code = ""
  @State private var working = false
  @State private var problem: String?
  @FocusState private var focused: Bool

  var body: some View {
    VStack(spacing: 24) {
      Spacer()
      Image(systemName: "lock.shield")
        .font(.system(size: 52, weight: .semibold))
        .foregroundStyle(.tint)
        .symbolEffect(.pulse, options: .repeating, isActive: working)
        .padding(22)
        .glassEffect(.regular, in: .circle)

      VStack(spacing: 8) {
        Text("Two-Step Sign-In")
          .font(.title.bold())
        Text("Enter the 6-digit code from your authenticator app.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }

      TextField("123456", text: $code)
        .textContentType(.oneTimeCode)
        .keyboardType(.numberPad)
        .font(.system(size: 34, weight: .semibold, design: .monospaced))
        .multilineTextAlignment(.center)
        .focused($focused)
        .padding(.vertical, 14)
        .frame(maxWidth: 260)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .onChange(of: code) { _, new in
          let digits = String(new.filter(\.isNumber).prefix(6))
          if digits != new { code = digits }
          if digits.count == 6 { verify() }
        }

      if let problem {
        Label(LocalizedStringKey(problem), systemImage: "exclamationmark.triangle.fill")
          .font(.footnote)
          .foregroundStyle(.red)
      }

      Button(action: verify) {
        Group {
          if working { ProgressView().tint(.white) } else { Text("Verify").fontWeight(.semibold) }
        }
        .frame(maxWidth: 260)
        .padding(.vertical, 6)
      }
      .buttonStyle(.glassProminent)
      .controlSize(.large)
      .disabled(working || code.count != 6)

      Spacer()

      Button("Use a Different Account") {
        Task { await model.signOut() }
      }
      .font(.footnote.weight(.medium))
      .padding(.bottom, 24)
    }
    .padding(.horizontal, 24)
    .frame(maxWidth: .infinity)
    .background { MahamBackground() }
    .onAppear { focused = true }
    .sensoryFeedback(Haptics.failed, trigger: problem) { _, new in new != nil }
  }

  private func verify() {
    guard !working, code.count == 6 else { return }
    working = true
    problem = nil
    Task {
      defer { working = false }
      do {
        try await model.verify(code: code)
      } catch {
        problem = (error as? MahamError)?.message ?? error.localizedDescription
        code = ""
      }
    }
  }
}

/// Face ID before the company's data shows, when the app comes back.
struct LockView: View {
  @Environment(AppModel.self) private var model
  @State private var tried = false

  var body: some View {
    VStack(spacing: 22) {
      Spacer()
      BrandMark(size: 84)
      Text("Maham One is locked")
        .font(.title2.bold())
      Button {
        Task { await model.unlock() }
      } label: {
        Label(unlockTitle, systemImage: unlockSymbol)
          .fontWeight(.semibold)
          .padding(.horizontal, 8)
          .padding(.vertical, 6)
      }
      .buttonStyle(.glassProminent)
      .controlSize(.large)
      Spacer()
      Button("Sign Out") {
        Task { await model.signOut() }
      }
      .font(.footnote.weight(.medium))
      .padding(.bottom, 24)
    }
    .frame(maxWidth: .infinity)
    .background { MahamBackground() }
    .task {
      guard !tried else { return }
      tried = true
      await model.unlock()
    }
  }

  private var unlockTitle: LocalizedStringKey {
    switch Biometrics.kind {
    case .faceID: "Unlock with Face ID"
    case .touchID: "Unlock with Touch ID"
    case .opticID: "Unlock with Optic ID"
    default: "Unlock"
    }
  }

  private var unlockSymbol: String {
    switch Biometrics.kind {
    case .faceID: "faceid"
    case .touchID: "touchid"
    case .opticID: "opticid"
    default: "lock.open"
    }
  }
}

/// A build without the database's publishable key (Config/Local.xcconfig).
struct NotConfiguredView: View {
  var body: some View {
    VStack(spacing: 18) {
      BrandMark(size: 72)
      Text("Almost ready")
        .font(.title2.bold())
      Text("This build of Maham One doesn't have the database's publishable key yet. Add it to ios/Config/Local.xcconfig and build again (see ios/README.md).")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding(28)
    .glassEffect(.regular, in: .rect(cornerRadius: 30, style: .continuous))
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { MahamBackground() }
  }
}
