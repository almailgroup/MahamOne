import Contacts
import ContactsUI
import MahamKit
import SwiftUI

/// iOS's own new-contact card, filled in from a client: the company, the
/// person to ask for, phone numbers, email addresses, the website and the
/// city. The person checks it and taps Done (or Cancel).
struct NewClientContactView: UIViewControllerRepresentable {
  let client: Client
  let onDone: () -> Void

  init(client: Client, onDone: @escaping () -> Void) {
    self.client = client
    self.onDone = onDone
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onDone: onDone)
  }

  func makeUIViewController(context: Context) -> UINavigationController {
    let card = CNContactViewController(forNewContact: Self.contact(for: client))
    card.contactStore = CNContactStore()
    card.delegate = context.coordinator
    return UINavigationController(rootViewController: card)
  }

  func updateUIViewController(_ controller: UINavigationController, context: Context) {
    context.coordinator.onDone = onDone
  }

  /// Closes the sheet once the card is saved or cancelled.
  @MainActor
  final class Coordinator: NSObject, CNContactViewControllerDelegate {
    var onDone: () -> Void

    init(onDone: @escaping () -> Void) {
      self.onDone = onDone
      super.init()
    }

    nonisolated func contactViewController(
      _ viewController: CNContactViewController, didCompleteWith contact: CNContact?
    ) {
      MainActor.assumeIsolated {
        self.onDone()
      }
    }
  }

  // MARK: The card

  static func contact(for client: Client) -> CNMutableContact {
    let contact = CNMutableContact()
    let company = client.name.trimmingCharacters(in: .whitespacesAndNewlines)
    contact.organizationName = company

    // The person to ask for, when there is one; the company's card otherwise.
    let main = client.contacts.first(where: \.primary) ?? client.contacts.first
    let person = main?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if person.isEmpty {
      contact.contactType = .organization
    } else {
      let words = person.split(separator: " ", maxSplits: 1).map(String.init)
      contact.givenName = words.first ?? person
      contact.familyName = words.count > 1 ? words[1] : ""
    }

    var phones: [CNLabeledValue<CNPhoneNumber>] = []
    var seenPhones: Set<String> = []
    func addPhone(_ number: String, label: String) {
      let text = number.trimmingCharacters(in: .whitespacesAndNewlines)
      let key = BusinessUI.dialable(text) ?? text
      guard !text.isEmpty, !seenPhones.contains(key) else { return }
      seenPhones.insert(key)
      phones.append(CNLabeledValue(label: label, value: CNPhoneNumber(stringValue: text)))
    }
    addPhone(client.phone, label: CNLabelPhoneNumberMain)
    for other in client.contacts {
      let name = other.name.trimmingCharacters(in: .whitespacesAndNewlines)
      addPhone(other.phone, label: name.isEmpty ? CNLabelWork : name)
    }
    contact.phoneNumbers = phones

    var emails: [CNLabeledValue<NSString>] = []
    var seenEmails: Set<String> = []
    func addEmail(_ address: String, label: String) {
      let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
      let key = text.lowercased()
      guard text.contains("@"), !seenEmails.contains(key) else { return }
      seenEmails.insert(key)
      emails.append(CNLabeledValue(label: label, value: text as NSString))
    }
    addEmail(client.email, label: CNLabelWork)
    for other in client.contacts {
      let name = other.name.trimmingCharacters(in: .whitespacesAndNewlines)
      addEmail(other.email, label: name.isEmpty ? CNLabelWork : name)
    }
    contact.emailAddresses = emails

    if let site = BusinessUI.websiteURL(client.website) {
      contact.urlAddresses = [CNLabeledValue(label: CNLabelURLAddressHomePage, value: site.absoluteString as NSString)]
    }

    let city = client.city.trimmingCharacters(in: .whitespacesAndNewlines)
    if !city.isEmpty {
      let address = CNMutablePostalAddress()
      address.city = city
      contact.postalAddresses = [CNLabeledValue<CNPostalAddress>(label: CNLabelWork, value: address)]
    }
    return contact
  }
}
