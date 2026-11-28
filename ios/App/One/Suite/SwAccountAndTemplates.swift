import MahamKit
import SwiftUI
import UIKit

// The design of documents chosen natively (Templates: a type's template,
// quotes and credit notes like invoices or with their own design), the
// gallery's thumbnails from the app's bundle, and the password changed
// from Settings → Your account.

// MARK: Templates

@MainActor
enum SwTemplates {
  private static var cache: [String: UIImage] = [:]

  /// A design's thumbnail in a language ("modern", "modern-ar", "modern-ar-en"), from the bundle.
  static func thumbnail(_ id: String, language: String) -> UIImage? {
    let suffix = language == "ar" ? "-ar" : language == "ar-en" ? "-ar-en" : ""
    let name = id + suffix
    if let image = cache[name] { return image }
    let url =
      Bundle.main.url(forResource: name, withExtension: "jpg")
      ?? Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Templates")
    guard let url, let image = UIImage(contentsOfFile: url.path) else { return nil }
    cache[name] = image
    return image
  }

  /// Owners, admins and accountants choose the design; staff and viewers look.
  static func editable(_ model: AppModel) -> Bool {
    SwAccess(model).designs && SwAccess.can(.companies)
  }

  /// What the web says once a type prints with another design.
  static func applied(_ name: String, type: String) -> String {
    switch type {
    case "quote": t("Quotes now print with {name}", ["name": name])
    case "credit": t("Credit notes now print with {name}", ["name": name])
    default: t("{name} is now your default template", ["name": name])
    }
  }
}

/// A design of the gallery made the type's (`applyTemplate`: `withTypeDesign(c, type, { templateId })`).
struct SwUseTemplateButton: View {
  let template: SuTemplate
  let type: String
  @Environment(AppModel.self) private var model
  @State private var busy = false

  var body: some View {
    if SwTemplates.editable(model) {
      WebButton(t("Use"), variant: .outline, size: .sm, loading: busy) { use() }
        .accessibilityLabel(Text(t("Use {name} as the default template", ["name": t(template.name)])))
    }
  }

  private func use() {
    guard let company = model.one.company else { return }
    let next = SwCompany.withTemplate(company, type: type, templateId: template.id)
    let done = SwTemplates.applied(t(template.name), type: type)
    busy = true
    Task {
      await SwSave.run(model, done: done) { ctx in SwCompany.save(ctx, next) }
      busy = false
    }
  }
}

/// Quotes or credit notes printed like invoices, or with a design of their own (`withSameAsInvoices`).
struct SwSameAsInvoicesSwitch: View {
  let type: String
  @Environment(AppModel.self) private var model
  @State private var busy = false

  var body: some View {
    if type != "invoice" && SwTemplates.editable(model) {
      let same = SuDesign(company: model.one.company, type: type).sameAsInvoices
      Card {
        CardBody {
          Switch(t("Same as invoices"), isOn: Binding(get: { same }, set: { change($0) }))
            .disabled(busy)
        }
      }
    }
  }

  private func change(_ same: Bool) {
    guard let company = model.one.company else { return }
    let next = SwCompany.withSameAsInvoices(company, type: type, same: same)
    busy = true
    Task {
      await SwSave.run(model, done: t("Settings saved")) { ctx in SwCompany.save(ctx, next) }
      busy = false
    }
  }
}

// MARK: The password

/// Settings → Your account → Password (`Password` of account.tsx): a new
/// password of at least 8 characters, saved with Supabase Auth.
struct SwPasswordCard: View {
  @Environment(AppModel.self) private var model
  @State private var password = ""
  @State private var busy = false
  @State private var error: String?

  /// `MIN_PASSWORD`.
  private static let minimum = 8

  var body: some View {
    Card {
      CardHeader(t("Password"), description: t("Change the password you sign in with."))
      CardBody {
        Field(t("New password"), error: error) {
          TextInput(text: $password, secure: true, contentType: .newPassword, submitLabel: .done, onSubmit: { save() })
        }
        HStack {
          Spacer(minLength: 0)
          WebButton(t("Change password"), loading: busy) { save() }
            .disabled(password.isEmpty)
        }
      }
    }
  }

  private func save() {
    guard !password.isEmpty, !busy else { return }
    if password.utf16.count < Self.minimum {
      error = t("Choose a password of at least {count} characters.", ["count": String(Self.minimum)])
      return
    }
    guard let auth = model.services?.auth else { return }
    let chosen = password
    busy = true
    error = nil
    Task {
      do {
        try await auth.updatePassword(chosen)
        password = ""
        model.confirm(t("Your new password is saved."))
      } catch {
        self.error = Self.message(error)
      }
      busy = false
    }
  }

  /// Supabase Auth's refusals in the web's words (`AUTH_MESSAGES`).
  static func message(_ error: Error) -> String {
    let words: [String: String] = [
      "weak_password": "Choose a stronger password: at least 8 characters.",
      "same_password": "Choose a password you have not used here before.",
      "over_request_rate_limit": "Too many attempts. Wait a few minutes and try again.",
      "session_not_found": "Your session has ended. Sign in again.",
      "validation_failed": "Check the email address and password.",
    ]
    if case MahamError.server(_, let code, _) = error, let code, let text = words[code] { return t(text) }
    if error is URLError || (error as? MahamError) == .offline {
      return t("No connection. Check your internet and try again.")
    }
    return t("Something went wrong. Try again in a moment.")
  }
}
