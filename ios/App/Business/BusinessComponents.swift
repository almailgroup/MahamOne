import MahamKit
import SwiftUI

// What the Maham One screens share: names in the reader's language, money in
// a document's currency, the links behind the contact buttons, and which
// expiry dates a role may see. Read-only: every change is made on the web.

enum BusinessUI {
  /// The app is being read in Arabic.
  static var isArabic: Bool {
    Locale.current.language.languageCode?.identifier == "ar"
  }

  // MARK: Names

  static func name(_ client: Client) -> String {
    MahamKit.localName(client.name, client.nameAr, arabic: isArabic)
  }

  static func name(_ employee: Employee) -> String {
    MahamKit.localName(employee.name, employee.nameAr, arabic: isArabic)
  }

  /// The spelling not in use: the Arabic name under the English one, or the
  /// English one under the Arabic.
  static func otherName(_ name: String, _ nameAr: String?) -> String? {
    let arabic = nameAr?.trimmingCharacters(in: .whitespaces) ?? ""
    let english = name.trimmingCharacters(in: .whitespaces)
    guard !arabic.isEmpty, arabic != english else { return nil }
    if isArabic { return english.isEmpty ? nil : english }
    return arabic
  }

  /// "SA" for "Sara Ali".
  static func initials(_ name: String) -> String {
    let words = name.split(whereSeparator: { $0.isWhitespace })
    let letters = words.prefix(2).compactMap { $0.first }.map { String($0) }.joined()
    return letters.isEmpty ? "?" : letters.uppercased()
  }

  /// A nationality as the reader's language names it, when it is a country
  /// code ("KW"); as written otherwise.
  static func nationality(_ value: String) -> String {
    let text = value.trimmingCharacters(in: .whitespaces)
    if text.count == 2, let name = Locale.current.localizedString(forRegionCode: text.uppercased()) {
      return name
    }
    return text
  }

  // MARK: Money

  /// An amount in a document's own currency; the company's way when it is
  /// the company's currency.
  @MainActor
  static func money(_ amount: Double, currency: String, in store: BusinessStore) -> String {
    let code = currency.trimmingCharacters(in: .whitespaces).uppercased()
    if code.isEmpty || code == store.currency.uppercased() { return store.format(amount) }
    return Money.format(amount, currency: code)
  }

  /// What is still owed on these invoices.
  static func openBalance(_ invoices: [SalesDocument]) -> Double {
    invoices.filter(\.isOpen).reduce(0.0) { $0 + $1.totals.balance }
  }

  // MARK: Links

  /// The digits of a phone number (and a leading plus), as `tel:` wants them.
  static func dialable(_ phone: String) -> String? {
    var out = ""
    for character in phone {
      if character == "+", out.isEmpty {
        out.append(character)
      } else if character.isNumber, let digit = character.wholeNumberValue, (0...9).contains(digit) {
        out.append(String(digit))
      }
    }
    return out.filter(\.isNumber).count >= 3 ? out : nil
  }

  /// `tel:`, `sms:` or `facetime:` with a number.
  static func phoneURL(_ scheme: String, _ phone: String) -> URL? {
    guard let number = dialable(phone) else { return nil }
    return URL(string: "\(scheme):\(number)")
  }

  static func emailURL(_ email: String, subject: String? = nil) -> URL? {
    let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
    guard address.contains("@"), !address.contains(" ") else { return nil }
    var parts = URLComponents()
    parts.scheme = "mailto"
    parts.path = address
    if let subject, !subject.isEmpty {
      parts.queryItems = [URLQueryItem(name: "subject", value: subject)]
    }
    return parts.url
  }

  static func websiteURL(_ site: String) -> URL? {
    let text = site.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !text.contains(" ") else { return nil }
    let full = text.contains("://") ? text : "https://\(text)"
    guard let url = URL(string: full), let scheme = url.scheme?.lowercased(),
      scheme == "https" || scheme == "http", url.host() != nil
    else { return nil }
    return url
  }

  /// Apple Maps searching for a place.
  static func mapsURL(_ place: String) -> URL? {
    let text = place.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
    guard let query = text.addingPercentEncoding(withAllowedCharacters: safe) else { return nil }
    return URL(string: "maps://?q=\(query)")
  }

  // MARK: Expiry dates

  /// The expiry dates this role may see. The database already gives staff
  /// and viewers no employees; employees' papers are left out here as well,
  /// whatever came back.
  @MainActor
  static func visibleExpiries(in store: BusinessStore) -> [Expiry] {
    if store.role.seesPeople { return store.expiries }
    let register = store.documents.filter { ($0.employeeId ?? "").isEmpty }
    return MahamKit.expiries(documents: register, employees: [])
  }

  /// Red once expired, orange within 30 days.
  static func expiryTint(_ daysLeft: Int) -> Color {
    if daysLeft < 0 { return .red }
    if daysLeft <= 30 { return .orange }
    return .green
  }

  static func daysLeftText(_ daysLeft: Int) -> Text {
    if daysLeft < 0 { return Text("Expired \(-daysLeft) days ago") }
    if daysLeft == 0 { return Text("Expires today") }
    return Text("\(daysLeft) days left")
  }

  /// An employee's paper by its name in the reader's language; a document of
  /// the register as it was named.
  static func expiryTitle(_ expiry: Expiry) -> Text {
    if expiry.id.hasSuffix("-civil"), expiry.title == "Civil ID" { return Text("Civil ID") }
    if expiry.id.hasSuffix("-passport"), expiry.title == "Passport" { return Text("Passport") }
    if expiry.id.hasSuffix("-residency"), expiry.title == "Residency" { return Text("Residency") }
    if expiry.id.hasSuffix("-permit"), expiry.title == "Work permit" { return Text("Work permit") }
    return Text(expiry.title)
  }
}

// MARK: Rows

/// A name and its value on one line: "Subtotal … KWD 100.000".
struct BusinessInfoRow: View {
  let title: LocalizedStringKey
  let value: String
  var tint: Color?
  var emphasized: Bool

  init(title: LocalizedStringKey, value: String, tint: Color? = nil, emphasized: Bool = false) {
    self.title = title
    self.value = value
    self.tint = tint
    self.emphasized = emphasized
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(title)
        .foregroundStyle(.secondary)
      Spacer(minLength: 12)
      Text(value)
        .fontWeight(emphasized ? .semibold : .regular)
        .monospacedDigit()
        .foregroundStyle(tint ?? Color.primary)
        .multilineTextAlignment(.trailing)
    }
    .font(.subheadline)
    .accessibilityElement(children: .combine)
  }
}

/// A paper or licence and how long it has left.
struct BusinessExpiryRow: View {
  let expiry: Expiry
  let today: LocalDate
  var showsOwner: Bool

  init(expiry: Expiry, today: LocalDate, showsOwner: Bool = true) {
    self.expiry = expiry
    self.today = today
    self.showsOwner = showsOwner
  }

  var body: some View {
    let days = expiry.daysLeft(today: today)
    let tint = BusinessUI.expiryTint(days)
    HStack(spacing: 12) {
      Image(systemName: days < 0 ? "exclamationmark.triangle.fill" : "calendar")
        .font(.body.weight(.semibold))
        .foregroundStyle(tint)
        .frame(width: 28)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        BusinessUI.expiryTitle(expiry)
          .font(.body.weight(.medium))
        if showsOwner, !expiry.owner.isEmpty {
          Text(expiry.owner)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Text(expiry.date.display)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      BusinessUI.daysLeftText(days)
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14), in: .capsule)
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }
}

// MARK: Buttons

/// An icon over a word, for the glass buttons under a record.
struct BusinessActionLabel: View {
  let title: LocalizedStringKey
  let symbol: String

  var body: some View {
    VStack(spacing: 4) {
      Image(systemName: symbol)
        .font(.title3)
        .symbolRenderingMode(.hierarchical)
      Text(title)
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .frame(maxWidth: .infinity, minHeight: 44)
    .padding(.vertical, 4)
  }
}

/// One way to reach someone: a call, a message, an email, the website.
struct BusinessContactAction: Identifiable {
  let id: String
  let title: LocalizedStringKey
  let symbol: String
  let url: URL
}

/// The ways to reach a client or an employee, as a row of glass buttons.
struct BusinessContactActions: View {
  let actions: [BusinessContactAction]
  @Environment(\.openURL) private var openURL

  init(actions: [BusinessContactAction]) {
    self.actions = actions
  }

  var body: some View {
    GlassEffectContainer(spacing: 10) {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 10)], spacing: 10) {
        ForEach(actions) { action in
          Button {
            openURL(action.url)
          } label: {
            BusinessActionLabel(title: action.title, symbol: action.symbol)
          }
          .buttonStyle(.glass)
          .buttonBorderShape(.roundedRectangle(radius: 18))
        }
      }
    }
  }

  /// Call, Message and FaceTime for a number; Email for an address.
  static func person(phone: String?, email: String?) -> [BusinessContactAction] {
    var actions: [BusinessContactAction] = []
    if let phone, let url = BusinessUI.phoneURL("tel", phone) {
      actions.append(BusinessContactAction(id: "call", title: "Call", symbol: "phone.fill", url: url))
    }
    if let phone, let url = BusinessUI.phoneURL("sms", phone) {
      actions.append(BusinessContactAction(id: "message", title: "Message", symbol: "message.fill", url: url))
    }
    if let email, let url = BusinessUI.emailURL(email) {
      actions.append(BusinessContactAction(id: "email", title: "Email", symbol: "envelope.fill", url: url))
    }
    if let phone, let url = BusinessUI.phoneURL("facetime", phone) {
      actions.append(BusinessContactAction(id: "facetime", title: "FaceTime", symbol: "video.fill", url: url))
    }
    return actions
  }
}

/// The record on mahamone.com, where it can be changed.
struct OpenInMahamOneButton: View {
  let url: URL?
  @Environment(\.openURL) private var openURL

  init(url: URL?) {
    self.url = url
  }

  var body: some View {
    if let url {
      Button {
        openURL(url.absoluteURL)
      } label: {
        Label("Open in Maham One", systemImage: "arrow.up.forward.app")
          .font(.body.weight(.semibold))
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.glassProminent)
      .controlSize(.large)
    }
  }
}
