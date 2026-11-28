import MahamKit
import SwiftUI

/// The client page's credit hold (`toggleHold` of clients/detail.tsx):
/// putting a client on hold asks first; lifting it doesn't. Saved through
/// the port of the web's `setCreditHold`, which logs it.
struct DcCreditHoldButton: View {
  let contact: JSONValue
  @Environment(AppModel.self) private var model
  @State private var confirm: DcConfirm?
  @State private var busy = false

  init(contact: JSONValue) {
    self.contact = contact
  }

  var body: some View {
    let held = contact.flag("creditHold")
    WebButton(
      held ? t("Lift credit hold") : t("Put on credit hold"), icon: held ? Icon.lockOpen : Icon.lock, variant: .outline,
      size: .sm, loading: busy
    ) {
      if held {
        toggle(false)
      } else {
        confirm = DcConfirm(
          title: t("Put {name} on credit hold?", ["name": contact.str("name")]),
          description: t("New invoices and sales orders for them need an override until the hold is lifted."),
          confirmLabel: t("Put on hold"), danger: true
        ) { toggle(true) }
      }
    }
    .dcConfirm($confirm)
  }

  private func toggle(_ hold: Bool) {
    let id = contact.rid
    busy = true
    Task {
      defer { busy = false }
      do {
        try await model.one.write { ctx in DcRecords.setCreditHold(ctx, clientId: id, hold: hold) }
        model.confirm(hold ? t("Credit hold on") : t("Credit hold lifted"))
      } catch {
        DcWrite.fail(model, error)
      }
    }
  }
}
