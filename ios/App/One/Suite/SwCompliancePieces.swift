import MahamKit
import SwiftUI

// The register's buttons that save natively: a deadline done or not done,
// a paper renewed, and the vehicles' own (add one, link the papers that
// name a vehicle by its plate).

/// A calendar line's action, below it as on a phone: Renew a paper, Done
/// or Undo for a statutory deadline (`markComplianceDone`).
struct SwCalendarAction: View {
  let item: SuCalendarItem
  /// The line's title, which names it in the activity log.
  let title: String
  let onRenew: (SuEntry) -> Void
  @Environment(AppModel.self) private var model

  var body: some View {
    if shown {
      HStack(spacing: 8) { button }
        .padding(.leading, 80)
        .padding(.trailing, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var shown: Bool {
    guard SwAccess(model).edits else { return false }
    if let entry = item.entry { return SwComplianceGate.renews(entry) }
    return SwComplianceGate.marks
  }

  @ViewBuilder
  private var button: some View {
    if let entry = item.entry {
      WebButton(t("Renew"), icon: .refreshCw, variant: .outline, size: .sm) { onRenew(entry) }
    } else if item.status == .done {
      WebButton(t("Undo"), icon: .undo2, variant: .ghost, size: .sm) { undo() }
    } else {
      WebButton(t("Done"), icon: .check, variant: .outline, size: .sm) { done() }
    }
  }

  private func done() {
    let key = item.key
    let label = title
    Task {
      await SwSave.run(model, done: t("Marked as done")) { ctx in
        SwCompliance.markDone(ctx, key: key, label: label)
      }
    }
  }

  private func undo() {
    let key = item.key
    let label = title
    Task {
      await SwSave.run(model) { ctx in SwCompliance.clearMark(ctx, key: key, label: label) }
    }
  }
}

/// A register line's Renew button, below it.
struct SwRenewAction: View {
  let entry: SuEntry
  let title: String
  let onRenew: () -> Void
  @Environment(AppModel.self) private var model

  var body: some View {
    if SwAccess(model).edits && SwComplianceGate.renews(entry) {
      HStack {
        WebButton(t("Renew"), icon: .refreshCw, variant: .outline, size: .sm) { onRenew() }
          .accessibilityLabel(Text(t("Renew {document}", ["document": title])))
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 12)
      .frame(maxWidth: .infinity, alignment: .trailing)
    }
  }
}

/// The vehicles page's buttons: Link vehicles (when papers name a vehicle
/// by its plate only) and Add vehicle.
struct SwVehicleActions: View {
  let register: SuRegister
  @Binding var linking: Bool
  let onAdd: (SwVehicleDraft) -> Void
  @Environment(AppModel.self) private var model
  @State private var confirming = false

  /// View only, or a cloud without the records of version 16, changes no vehicle (`canChange`).
  static func editable(_ model: AppModel) -> Bool {
    SwAccess(model).edits && SwComplianceGate.vehicles && (model.one.cloud?.has("tables_v16") ?? true)
  }

  var body: some View {
    let groups = SwVehicles.unlinked(documents: register.documents, vehicles: register.vehicles)
    if Self.editable(model), let companyId = register.company?.rid {
      HStack(spacing: 8) {
        Spacer(minLength: 0)
        if !groups.isEmpty {
          WebButton(t("Link vehicles"), icon: .link2, variant: .outline, loading: linking) { confirming = true }
        }
        WebButton(t("Add vehicle"), icon: .plus) {
          onAdd(SwVehicleDraft(SwVehicles.newVehicle(companyId: companyId), isNew: true))
        }
      }
      .webDialog(
        isPresented: $confirming,
        title: tp(groups.count, "Link the papers of {count} vehicle?", "Link the papers of {count} vehicles?")
      ) {
        SwUnlinkedList(groups: groups)
      } footer: {
        SwConfirmFooter(label: t("Link vehicles"), onCancel: { confirming = false }) {
          confirming = false
          link()
        }
      }
    }
  }

  private func link() {
    let cloud = model.one.cloud
    linking = true
    Task {
      var done: (vehicles: Int, papers: Int)?
      await SwSave.run(model) { ctx in done = try SwVehicles.linkPapers(ctx, cloud: cloud) }
      linking = false
      guard let done else { return }
      var message = tp(done.papers, "{count} paper linked", "{count} papers linked")
      if done.vehicles > 0 {
        message += " · " + tp(done.vehicles, "{count} vehicle added", "{count} vehicles added")
      }
      model.confirm(message)
    }
  }
}

/// The plates whose papers are linked, with how many papers each has.
private struct SwUnlinkedList: View {
  let groups: [SwVehicles.Unlinked]
  @Environment(\.palette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(groups.indices, id: \.self) { index in
        Text(line(groups[index]))
          .font(.web(14))
          .foregroundStyle(palette.slate(700))
      }
    }
    Text(
      t(
        "Papers that name the same plate go with one vehicle. A vehicle is added for each plate that isn’t on the list yet."
      ))
  }

  private func line(_ group: SwVehicles.Unlinked) -> String {
    let count = tp(group.documents.count, "{count} paper", "{count} papers")
    let added = group.vehicle == nil ? " (\(t("new vehicle")))" : ""
    return "• \(group.name): \(count)\(added)"
  }
}
