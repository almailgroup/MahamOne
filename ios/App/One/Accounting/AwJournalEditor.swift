import MahamKit
import SwiftUI

// The journal editor (src/apps/books/pages/accounting/journal-editor.tsx):
// `/journals/new`, and `/journals/:id` for a journal that can still be
// changed by hand. Entries another part of the app made, and the entry that
// closes a VAT return, stay read only (AcJournalPage).

@MainActor
enum AwJournalEditing {
  /// A journal changed here: not one the app owns, nor one closing a VAT return.
  static func editable(_ journal: JSONValue) -> Bool {
    journal.text("vatReturnId") == nil && AcJournalKind.of(journal)?.owner == nil
  }

  /// Whether the person may change it: staff only the transfers their work makes.
  static func allowed(_ journal: JSONValue?, _ access: AwAccess) -> Bool {
    journal?.str("kind") == "transfer" ? access.edits : access.accounting
  }
}

/// `/journals/new`: a new draft journal, dated today.
struct AwJournalEditorPage: View {
  let id: String?
  @Environment(AppModel.self) private var model
  @State private var fresh: JSONValue?

  init(id: String?) {
    self.id = id
  }

  var body: some View {
    let existing = id.flatMap { model.one.record(.journals, $0) }
    content(existing)
      .onAppear {
        if id == nil, fresh == nil, let companyId = model.one.companyId {
          fresh = AwJournals.blank(companyId: companyId, today: AcDate.today, status: "draft")
        }
      }
  }

  @ViewBuilder
  private func content(_ existing: JSONValue?) -> some View {
    if let initial = existing ?? fresh {
      AwJournalEditor(initial: initial, isNew: existing == nil)
        .id(initial.rid + initial.str("updatedAt"))
    } else {
      RecordDetailPage(record: nil, title: t("New journal")) { EmptyView() }
    }
  }
}

/// The editor: date, reference and notes, the lines with their accounts,
/// debits and credits, the totals and any difference.
struct AwJournalEditor: View {
  let initial: JSONValue
  let isNew: Bool
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @State private var date: String
  @State private var reference: String
  @State private var notes: String
  @State private var lines: [JSONValue]
  @State private var saving: String?
  @State private var confirm: AwConfirm?

  init(initial: JSONValue, isNew: Bool) {
    self.initial = initial
    self.isNew = isNew
    _date = State(initialValue: initial.str("date"))
    _reference = State(initialValue: initial.str("reference"))
    _notes = State(initialValue: initial.str("notes"))
    _lines = State(initialValue: initial.list("lines"))
  }

  var body: some View {
    let format = model.one.format
    let totals = AwJournals.totals(lines, Money.precision(format.currency))
    WebPage(spacing: 16) {
      PageHeader(
        isNew ? t("New journal") : t("Journal {number}", ["number": initial.str("number")]),
        breadcrumb: t("Manual journals"), onBreadcrumb: { leave() }
      ) {
        if !isNew {
          WebButton(t("Delete"), icon: .trash2, variant: .ghost, size: .sm) { askDelete() }
        }
      }
      .padding(.bottom, -16)
      details
      linesCard(totals, format: format)
    }
    .stickyActions {
      WebButton(t("Save as draft"), variant: .outline, loading: saving == "draft") { save("draft") }
        .disabled(saving != nil)
      WebButton(t("Save and post"), loading: saving == "posted") { save("posted") }
        .disabled(saving != nil)
    }
    .awConfirm($confirm)
  }

  // MARK: The journal

  private var details: some View {
    Card {
      CardBody {
        Field(t("Date")) {
          DateField(value: $date, required: true)
        }
        Field(t("Reference"), hint: t("Shown in the reports, e.g. “Owner investment”.")) {
          TextInput(text: $reference)
        }
        Field(t("Notes"), optional: true) {
          AwTextArea(text: $notes)
        }
      }
    }
  }

  private func linesCard(_ totals: (debit: Double, credit: Double, difference: Double), format: CompanyFormat)
    -> some View
  {
    Card {
      CardHeader(
        t("Lines"),
        description: t("Amounts in {currency}. Each line has a debit or a credit.", ["currency": format.currency]))
      VStack(spacing: 0) {
        ForEach(lineRows) { row in
          lineEditor(row.id, number: row.number)
        }
      }
      HStack {
        WebButton(t("Add line"), icon: .plus, variant: .outline, size: .sm) {
          lines.append(AwJournals.blankLine())
        }
        Spacer()
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      .overlay(alignment: .top) { Rectangle().fill(palette.slate(200)).frame(height: 1) }
      AcLineRow(label: t("Total") + " · " + t("Debit"), value: format.money(totals.debit), strong: true)
      AcLineRow(label: t("Total") + " · " + t("Credit"), value: format.money(totals.credit), strong: true)
      if totals.difference != 0 {
        AcLineRow(
          label: t("Difference"), value: differenceText(totals.difference, format), strong: true, tone: .red(600))
      }
    }
  }

  private func differenceText(_ difference: Double, _ format: CompanyFormat) -> String {
    let amount = format.money(abs(difference))
    return difference > 0 ? t("{amount} more debit", ["amount": amount]) : t("{amount} more credit", ["amount": amount])
  }

  private func lineEditor(_ lineId: String, number: Int) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .center, spacing: 8) {
        Combobox(
          selection: accountBinding(lineId), options: accountOptions, placeholder: t("Choose an account…"),
          searchPlaceholder: t("Search accounts…"))
        WebButton(icon: .trash2, label: t("Remove line {line}", ["line": "\(number)"]), variant: .ghost) {
          lines.removeAll { $0.rid == lineId }
        }
        .disabled(lines.count <= 2)
      }
      TextInput(text: textBinding(lineId, "description"), placeholder: t("Description"))
      HStack(spacing: 8) {
        Field(t("Debit")) {
          AwAmountField(value: amountBinding(lineId, "debit", other: "credit"))
        }
        Field(t("Credit")) {
          AwAmountField(value: amountBinding(lineId, "credit", other: "debit"))
        }
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
    .overlay(alignment: .top) {
      if number > 1 { Rectangle().fill(palette.slate(100)).frame(height: 1) }
    }
  }

  private struct LineRow: Identifiable {
    let id: String
    let number: Int
  }

  /// The lines by id, numbered from 1.
  private var lineRows: [LineRow] {
    var rows: [LineRow] = []
    for line in lines { rows.append(LineRow(id: line.rid, number: rows.count + 1)) }
    return rows
  }

  /// Accounts in use (and archived ones a line already has), by code.
  private var accountOptions: [ComboOption] {
    let used = Set(lines.map { $0.str("accountId") })
    let accounts = model.one.records(.accounts).filter { !$0.flag("archived") || used.contains($0.rid) }
    return AwPick.options(AwPick.byCode(accounts))
  }

  // MARK: Editing a line

  private func line(_ lineId: String) -> JSONValue? {
    lines.first { $0.rid == lineId }
  }

  private func update(_ lineId: String, _ patch: [String: JSONValue]) {
    guard let index = lines.firstIndex(where: { $0.rid == lineId }) else { return }
    var fields = lines[index].object ?? [:]
    for (key, value) in patch { fields[key] = value }
    lines[index] = .object(fields)
  }

  private func accountBinding(_ lineId: String) -> Binding<String?> {
    Binding(
      get: { line(lineId)?.text("accountId") },
      set: { update(lineId, ["accountId": .string($0 ?? "")]) })
  }

  private func textBinding(_ lineId: String, _ key: String) -> Binding<String> {
    Binding(
      get: { line(lineId)?.str(key) ?? "" },
      set: { update(lineId, [key: .string($0)]) })
  }

  /// A debit or credit; one typed clears the other.
  private func amountBinding(_ lineId: String, _ key: String, other: String) -> Binding<Double> {
    Binding(
      get: { line(lineId)?.num(key) ?? 0 },
      set: { typed in
        let value = max(0, typed)
        var patch: [String: JSONValue] = [key: .number(value)]
        if value != 0 { patch[other] = .number(0) }
        update(lineId, patch)
      })
  }

  // MARK: Saving

  private func current(status: String) -> JSONValue {
    var fields = initial.object ?? [:]
    fields["date"] = .string(date)
    fields["reference"] = .string(reference)
    fields["notes"] = .string(notes)
    fields["lines"] = .array(lines)
    fields["status"] = .string(status)
    return .object(fields)
  }

  private var dirty: Bool { current(status: initial.str("status")) != initial }

  private func leave() {
    if dirty {
      confirm = AwUnsaved.confirm { router.back() }
    } else {
      router.back()
    }
  }

  private func save(_ status: String) {
    let journal = current(status: status)
    saving = status
    Task {
      let saved = await AwSave.run(model) { ctx, tr in try AwJournals.save(ctx, journal, tr: tr) }
      saving = nil
      guard let saved else { return }
      let number = saved.str("number")
      model.confirm(
        status == "posted"
          ? t("Journal {number} posted", ["number": number]) : t("Journal {number} saved as draft", ["number": number]))
      router.back()
    }
  }

  private func askDelete() {
    let id = initial.rid
    confirm = AwConfirm(
      title: t("Delete journal {number}?", ["number": initial.str("number")]),
      description: t("Its amounts are removed from the books."), confirmLabel: t("Delete"), danger: true
    ) {
      Task {
        let deleted = await AwSave.perform(model, done: t("Journal deleted")) { ctx, tr in
          try AwJournals.delete(ctx, id: id, tr: tr)
        }
        if deleted { router.back() }
      }
    }
  }
}
