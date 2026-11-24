import MahamKit
import SwiftUI

/// Signing in with the Maham One account: the same email and password as on
/// the web, for both departments.
struct SignInView: View {
  @Environment(AppModel.self) private var model
  @State private var email = ""
  @State private var password = ""
  @State private var working = false
  @State private var problem: String?
  @State private var showingReset = false
  @FocusState private var focus: Field?

  private enum Field { case email, password }

  var body: some View {
    ScrollView {
      VStack(spacing: 28) {
        Spacer(minLength: 40)
        VStack(spacing: 14) {
          BrandMark(size: 84)
          Text("Maham One")
            .font(.largeTitle.bold())
          Text("Your company and your team's tasks, in one place.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }

        VStack(spacing: 14) {
          TextField("Email", text: $email)
            .textContentType(.username)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .focused($focus, equals: .email)
            .onSubmit { focus = .password }
            .padding(14)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))

          SecureField("Password", text: $password)
            .textContentType(.password)
            .submitLabel(.go)
            .focused($focus, equals: .password)
            .onSubmit(signIn)
            .padding(14)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))

          if let problem {
            Label(LocalizedStringKey(problem), systemImage: "exclamationmark.triangle.fill")
              .font(.footnote)
              .foregroundStyle(.red)
              .frame(maxWidth: .infinity, alignment: .leading)
              .transition(.opacity)
          }

          Button(action: signIn) {
            Group {
              if working {
                ProgressView().tint(.white)
              } else {
                Text("Sign In").fontWeight(.semibold)
              }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
          }
          .buttonStyle(.glassProminent)
          .controlSize(.large)
          .disabled(working || email.isEmpty || password.isEmpty)
          .keyboardShortcut(.defaultAction)

          Button("Forgot your password?") { showingReset = true }
            .font(.footnote.weight(.medium))
            .buttonStyle(.borderless)
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 30, style: .continuous))
        .frame(maxWidth: 440)

        Text("New to the team? Ask your company's owner for an invite.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 40)
      .frame(maxWidth: .infinity)
    }
    .scrollDismissesKeyboard(.interactively)
    .background { MahamBackground() }
    .animation(.smooth, value: problem)
    .sensoryFeedback(Haptics.failed, trigger: problem) { _, new in new != nil }
    .sheet(isPresented: $showingReset) {
      PasswordResetSheet(email: email)
    }
  }

  private func signIn() {
    guard !working, !email.isEmpty, !password.isEmpty else { return }
    working = true
    problem = nil
    focus = nil
    Task {
      defer { working = false }
      do {
        try await model.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
        password = ""
      } catch let error as MahamError {
        problem = error.message
      } catch {
        problem = error.localizedDescription
      }
    }
  }
}

/// "Forgot your password?": the link comes by email and opens on the web.
private struct PasswordResetSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State var email: String
  @State private var sent = false
  @State private var working = false
  @State private var problem: String?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Email", text: $email)
            .textContentType(.username)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } footer: {
          Text("We'll email you a link to choose a new password.")
        }
        if sent {
          Label("Check your email for the link.", systemImage: "envelope.badge")
            .foregroundStyle(.green)
        }
        if let problem {
          Label(LocalizedStringKey(problem), systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
        }
      }
      .mahamScreen()
      .navigationTitle("Reset Password")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close", systemImage: "xmark") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Send", systemImage: "paperplane") { send() }
            .disabled(working || email.isEmpty || sent)
        }
      }
    }
    .presentationDetents([.medium])
  }

  private func send() {
    working = true
    Task {
      defer { working = false }
      do {
        try await model.sendPasswordReset(email: email.trimmingCharacters(in: .whitespaces))
        sent = true
        problem = nil
      } catch {
        problem = (error as? MahamError)?.message ?? error.localizedDescription
      }
    }
  }
}
