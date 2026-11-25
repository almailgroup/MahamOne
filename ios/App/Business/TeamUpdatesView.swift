import MahamKit
import SwiftUI

/// What the team changed in Maham One lately (for the owner and the members
/// who approve; nothing for others): who, what, and when.
struct TeamUpdatesView: View {
  @Environment(AppModel.self) private var model

  init() {}

  var body: some View {
    let business = model.business
    let events = Self.visibleUpdates(in: business)
    List {
      ForEach(events) { event in
        BusinessTeamUpdateRow(event: event)
          .glassRow()
      }
    }
    .mahamScreen()
    .navigationTitle("Team updates")
    .overlay {
      if events.isEmpty {
        EmptyState(
          title: "No updates yet", symbol: "bell",
          message: "Changes your team makes on mahamone.com show here.")
      }
    }
    .refreshable {
      await Haptics.refresh()
      await business.refreshCompany()
    }
  }

  /// The team's changes this role may read. The database leaves payroll and
  /// people changes out for staff and viewers; this leaves them out as well.
  static func visibleUpdates(in store: BusinessStore) -> [ChangeEvent] {
    if store.role.seesPeople { return store.updates }
    return store.updates.filter { $0.kind != "people" }
  }
}

/// One change: who made it, what it was, who it was about, when; a dot when
/// it matters.
private struct BusinessTeamUpdateRow: View {
  let event: ChangeEvent

  var body: some View {
    let actor = (event.actorName ?? "").trimmingCharacters(in: .whitespaces)
    let subject = (event.subjectName ?? "").trimmingCharacters(in: .whitespaces)
    let who: Text = actor.isEmpty ? Text("Maham One") : Text(actor)
    HStack(alignment: .top, spacing: 12) {
      AvatarView(
        initials: actor.isEmpty ? "M1" : BusinessUI.initials(actor), id: actor.isEmpty ? "maham-one" : actor,
        size: 34)
      VStack(alignment: .leading, spacing: 3) {
        who
          .font(.subheadline.weight(.semibold))
        what
          .font(.subheadline)
        if !subject.isEmpty {
          Text(subject)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        Text(event.at, format: .relative(presentation: .named))
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
      Spacer(minLength: 8)
      if event.important {
        Image(systemName: "circle.fill")
          .font(.system(size: 9))
          .foregroundStyle(.orange)
          .padding(.top, 6)
          .accessibilityLabel(Text("Important"))
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }

  /// "Added a payment", "Changed a document", "12 changes to expenses".
  private var what: Text {
    if event.count > 1 {
      return Text("\(event.count) changes to \(Self.many(event.kind))")
    }
    switch event.op {
    case "insert": return Text("Added \(Self.one(event.kind))")
    case "delete": return Text("Deleted \(Self.one(event.kind))")
    default: return Text("Changed \(Self.one(event.kind))")
    }
  }

  /// One record of a kind, in the middle of a sentence.
  private static func one(_ kind: String) -> Text {
    switch kind {
    case "document": Text("a document")
    case "payment": Text("a payment")
    case "cheque": Text("a cheque")
    case "approval": Text("an approval request")
    case "settings": Text("the company settings")
    case "member": Text("the team")
    case "people": Text("payroll or people data")
    case "compliance": Text("a compliance record")
    case "contact": Text("a customer or vendor")
    case "item": Text("an item")
    case "expense": Text("an expense")
    case "accounting": Text("the accounts")
    case "file": Text("a file")
    case "document_expiry": Text("an expiry reminder")
    default: Text("a record")
    }
  }

  /// Records of a kind, after "12 changes to".
  private static func many(_ kind: String) -> Text {
    switch kind {
    case "document": Text("invoices and documents")
    case "payment": Text("payments")
    case "cheque": Text("cheques")
    case "approval": Text("approval requests")
    case "settings": Text("the company settings")
    case "member": Text("the team")
    case "people": Text("payroll and people data")
    case "compliance": Text("compliance records")
    case "contact": Text("customers and vendors")
    case "item": Text("items and stock")
    case "expense": Text("expenses")
    case "accounting": Text("the accounts")
    case "file": Text("files")
    case "document_expiry": Text("expiry reminders")
    default: Text("records")
    }
  }
}
