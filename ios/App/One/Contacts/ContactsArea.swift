import SwiftUI

/// The pages of contacts, payments, recurring invoices, cheques and
/// expenses, to read: clients and vendors, payments received and made,
/// recurring invoices, the cheque register and its layouts, and expenses.
/// Creating and changing them opens the web's forms (`FormBridge`).
@MainActor
enum ContactsArea {
  static func page(for route: Route) -> AnyView? {
    switch route {
    case .contacts(let kind):
      AnyView(CtContactListPage(kind: kind))
    case .contact(let kind, let id):
      AnyView(CtContactPage(kind: kind, id: id))
    case .payments(let direction):
      AnyView(CtPaymentListPage(direction: direction))
    case .payment(let direction, let id):
      AnyView(CtPaymentPage(direction: direction, id: id))
    case .recurring:
      AnyView(CtRecurringListPage())
    case .recurringInvoice(let id):
      AnyView(CtRecurringPage(id: id))
    case .cheques:
      AnyView(CtChequesPage())
    case .chequeLayouts:
      AnyView(CtChequeLayoutsPage())
    case .expenses:
      AnyView(CtExpensesPage())
    default:
      nil
    }
  }
}
