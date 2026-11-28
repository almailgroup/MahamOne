import MahamKit
import SwiftUI

// Payroll settings and the company's leave reasons saved natively, as the
// web's `/payroll/settings` and `/payroll/leave-reasons` save them: the
// settings as a form with Save settings (`savePayrollSettings`, keeping the
// leave reasons as they are saved now), each leave reason on its own
// (`updateLeaveReasons`), and the two switches of the reasons page with
// Save changes (`saveLeaveReasonSettings`).

// MARK: - Payroll settings

/// `/payroll/settings`, editable.
struct PwPayrollSettingsView: View {
  @Environment(AppModel.self) private var model
  @State private var draft: PwDraft?
  @State private var busy = false

  var body: some View {
    let saved = savedSettings
    let value = Binding<PwDraft>(get: { draft ?? PwDraft(saved) }, set: { draft = $0 })
    WebPage(refresh: { [model] in await model.one.sync() }) {
      PePayrollHeader(tab: "settings")
      VStack(alignment: .leading, spacing: 24) {
        PwPaySettingsCard(value: value)
        PwRatesCard(value: value, gcc: false)
        PwRatesCard(value: value, gcc: true)
        PwLeavePolicyEditor(value: value, saved: saved.obj("leavePolicy"))
        PwProvisionsCard(value: value)
        PwPayrollAccountsCard(value: value)
        buttons
      }
    }
  }

  /// `getPayrollSettings`: what is saved, the defaults for the rest.
  private var savedSettings: JSONValue {
    let one = model.one
    let companyId = one.companyId ?? ""
    return PwSettings.payroll(
      saved: one.record(.payrollSettings, companyId), companyId: companyId, stamp: Defaults.nowStamp())
  }

  private var buttons: some View {
    HStack(spacing: 8) {
      Spacer(minLength: 0)
      if draft != nil {
        WebButton(t("Discard changes"), variant: .outline) { draft = nil }
      }
      WebButton(t("Save settings"), loading: busy) { Task { await save() } }
        .disabled(draft == nil)
    }
  }

  private func save() async {
    guard let edited = draft?.json else { return }
    busy = true
    defer { busy = false }
    let text = PwText.app
    guard
      await PwSave.run(
        model, success: t("Payroll settings saved"),
        { ctx in
          // The leave reasons and their switches are changed on their own page:
          // kept as they are saved now, not as they were when editing began.
          let now = PwSettings.payroll(ctx)
          var fields = edited.object ?? [:]
          for key in ["leaveReasons", "leaveReasonsOn", "leaveAccrualPause"] {
            if let current = now[key] { fields[key] = current }
          }
          return try PwSettings.savePayrollSettings(ctx, .object(fields), text: text)
        }) != nil
    else { return }
    draft = nil
  }
}

/// Pay day, the salaries account, working days, the overtime basis, the minimum wage, the PAM file.
private struct PwPaySettingsCard: View {
  @Binding var value: PwDraft
  @Environment(AppModel.self) private var model

  var body: some View {
    PeCard(t("Pay")) {
      Field(t("Pay day"), hint: t("The pay date suggested for each month.")) {
        Select(selection: $value.number("payDay"), options: payDays)
      }
      Field(t("Salaries paid from")) { Select(selection: bank, options: banks) }
      Field(
        t("Working days in a month"),
        hint: t("The daily rate is the monthly wage divided by this; 26 for a six-day week (art. 67).")
      ) { PwNumberField(value: $value.number("dailyDivisor")) }
      Field(
        t("Overtime and unpaid absence use"),
        hint: t(
          "Overtime is paid at 125%, on rest days 150% and on public holidays 200% of the hourly rate. Unpaid leave costs a share of the month’s pay."
        )
      ) {
        Select(
          selection: $value.text("rateBase"),
          options: [SelectOption("wage", t("Basic salary and allowances")), SelectOption("basic", t("Basic salary only"))])
      }
      minimumWage
      Field(
        t("PAM file number"), hint: t("Your company file with the Public Authority for Manpower, for the salary file."),
        optional: true
      ) { TextInput(text: $value.text("pamFileNumber")) }
    }
  }

  private var minimumWage: some View {
    Field(
      t("Minimum wage"),
      hint: t(
        "Pay runs warn when net pay is below it. Commonly cited as {amount}.", ["amount": model.one.format.money(75)])
    ) {
      HStack(spacing: 8) {
        PwNumberField(value: $value.number("minimumWage"))
        Badge(t("Verify"), tone: .amber)
      }
    }
  }

  private var payDays: [SelectOption<Double>] {
    (1...28).map { SelectOption(Double($0), t("Day {day} of the month", ["day": String($0)])) }
      + [SelectOption(31, t("Last day of the month"))]
  }

  /// The account chosen, or "" for the default (saved as null).
  private var bank: Binding<String> {
    Binding<String>(
      get: { value.fields["bankAccountId"]?.string ?? "" },
      set: { value.fields["bankAccountId"] = $0.isEmpty ? .null : .string($0) })
  }

  /// `moneyAccounts`: the bank and cash accounts (the one chosen even if archived), the main bank as the default.
  private var banks: [SelectOption<String>] {
    let one = model.one
    let keep = value.fields["bankAccountId"]?.string
    let main = one.records(.accounts).first { $0.str("role") == "bank" }
    let first = main.map { t("{account} (default)", ["account": localName($0)]) } ?? t("Default account")
    let others = one.records(.accounts)
      .filter { $0.str("type") == "asset_cash" && (!$0.flag("archived") || $0.rid == keep) && $0.rid != main?.rid }
      .sorted { $0.str("code").localizedStandardCompare($1.str("code")) == .orderedAscending }
      .map { SelectOption($0.rid, $0.str("code") + " " + localName($0)) }
    return [SelectOption("", first)] + others
  }
}

/// The PIFSS rates of Kuwaiti staff by the date they apply from, or the GCC schemes by country.
private struct PwRatesCard: View {
  @Binding var value: PwDraft
  let gcc: Bool

  var body: some View {
    if gcc {
      PeCard(
        t("GCC nationals"),
        description: t(
          "GCC nationals contribute to their home scheme through PIFSS. Enter the rates of each country you employ; until then they are paid without contributions."
        )
      ) { rows }
    } else {
      PeCard(
        t("PIFSS rates for Kuwaiti staff"),
        description: t(
          "Shares of the insured salary (basic salary and allowances) up to the cap. Rates apply from their date until newer ones."
        ),
        actions: { Badge(t("Verify"), tone: .amber) }
      ) { rows }
    }
  }

  private var key: String { gcc ? "gcc" : "pifss" }

  private var list: Binding<[PwDraft]> {
    Binding<[PwDraft]>(
      get: { (value.fields[key]?.array ?? []).map { PwDraft($0) } },
      set: { value.fields[key] = .array($0.map(\.json)) })
  }

  private var used: Set<String> { Set(list.wrappedValue.map { $0.text("country") }) }

  @ViewBuilder
  private var rows: some View {
    ForEach(list.wrappedValue.indices, id: \.self) { index in
      PwRateRow(row: list.row(index), countries: countries(index), gcc: gcc) { remove(index) }
    }
    if !gcc {
      WebButton(t("Add new rates"), icon: .plus, variant: .outline, size: .sm) { addRates() }
    } else if let free = PePeople.gccCountries.first(where: { !used.contains($0) }) {
      WebButton(t("Add a country"), icon: .plus, variant: .outline, size: .sm) {
        let row = PwDraft(["country": .string(free), "employee": 0, "employer": 0, "cap": .null])
        list.wrappedValue = list.wrappedValue + [row]
      }
    }
  }

  /// New rates from today: the latest ones, or the law's.
  private func addRates() {
    var last = list.wrappedValue.last ?? PwDraft(["employer": 11.5, "employee": 10.5, "cap": 2750])
    last.fields["from"] = .string(ISODates.today())
    list.wrappedValue = list.wrappedValue + [last]
  }

  private func remove(_ index: Int) {
    var rows = list.wrappedValue
    guard rows.indices.contains(index) else { return }
    rows.remove(at: index)
    list.wrappedValue = rows
  }

  /// The countries a row may choose: its own and those no other row has.
  private func countries(_ index: Int) -> [String] {
    let rows = list.wrappedValue
    let own = rows.indices.contains(index) ? rows[index].text("country") : ""
    return PePeople.gccCountries.filter { $0 == own || !used.contains($0) }
  }
}

private struct PwRateRow: View {
  @Binding var row: PwDraft
  let countries: [String]
  let gcc: Bool
  let onRemove: () -> Void
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .bottom, spacing: 8) {
        first
        WebButton(icon: .trash2, label: t("Remove"), action: onRemove)
      }
      HStack(alignment: .top, spacing: 8) {
        Field(t("Employee %")) { PwNumberField(value: $row.number("employee")) }
        Field(t("Employer %")) { PwNumberField(value: $row.number("employer")) }
      }
      Field(t("Salary cap")) { PwOptionalNumberField(value: cap, placeholder: t("None")) }
    }
    .padding(.vertical, 8)
    .overlay(alignment: .bottom) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }

  @ViewBuilder
  private var first: some View {
    if gcc {
      Field(t("Country")) {
        Select(
          selection: $row.text("country"),
          options: countries.map { SelectOption($0, Geo.countryName($0, locale: model.one.format.locale.identifier)) })
      }
    } else {
      Field(t("From")) { DateField(value: $row.text("from"), required: true) }
    }
  }

  private var cap: Binding<Double?> {
    Binding<Double?>(
      get: { row.fields["cap"]?.double },
      set: { row.fields["cap"] = $0.map { $0 > 0 ? JSONValue.number($0) : .null } ?? .null })
  }
}

/// The company's annual leave policy: the law's until one is set.
private struct PwLeavePolicyEditor: View {
  @Binding var value: PwDraft
  let saved: JSONValue?
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    if value.fields["leavePolicy"]?.object != nil {
      PeCard(
        t("Annual leave"),
        description: t(
          "Days a year are earned from their date on; balances before the first date are the law’s and don’t change.")
      ) {
        olderVersions
        PwAnnualDaysRows(policy: policy, saved: saved)
        PwPolicyRules(policy: policy, locked: locked)
      }
    } else {
      PeCard(
        t("Annual leave"),
        description: t(
          "The law’s leave applies: 30 working days a year, 2.5 days for each month of service, usable after nine months (art. 70). Unused days carry forward and are paid when the employee leaves (art. 73)."
        )
      ) {
        Text(
          t(
            "Set a policy for more days a year, contract entitlements, a cap on the days carried forward, or leave counted in calendar days. Balances before the date it applies from don’t change."
          )
        )
        .font(.web(14))
        .foregroundStyle(palette.slate(600))
        olderVersions
        WebButton(t("Set the company’s leave policy"), icon: .plus, variant: .outline) { start() }
      }
    }
  }

  /// The company is kept in the cloud: other devices may still run an older version.
  private var olderVersions: some View {
    PeNote(
      t(
        "Update the app on every device that records leave or approves pay runs first: older versions count annual leave as the law does."
      ))
  }

  private var locked: Bool { PeLeave.annualLeaveRecorded(model.one.peLeaveRecords) }

  private var policy: Binding<PwDraft> {
    Binding<PwDraft>(
      get: { PwDraft(value.fields["leavePolicy"]) },
      set: { value.fields["leavePolicy"] = $0.json })
  }

  /// `newLeavePolicy`: the law's, its days from the first of next month.
  private func start() {
    value.fields["leavePolicy"] = [
      "annualDays": [["from": .string(PwSettings.nextMonthStart(ISODates.today())), "days": 30]],
      "firstYearMonths": 9, "carryForwardMax": .null, "counting": "working",
    ]
  }
}

/// A note under a row of days: an error, or a warning.
private struct PwRowNote {
  let text: String
  let error: Bool
}

/// The days a year, each from a date.
private struct PwAnnualDaysRows: View {
  @Binding var policy: PwDraft
  let saved: JSONValue?
  @Environment(\.palette) private var palette

  var body: some View {
    let rows = days.wrappedValue
    VStack(alignment: .leading, spacing: 8) {
      ForEach(rows.indices, id: \.self) { index in
        PwAnnualDaysRow(row: days.row(index), note: note(rows[index]), single: rows.count == 1) { remove(index) }
      }
      if pastRemoved {
        Text(
          t(
            "A date that has passed was removed or moved: balances from it change, and the next approved pay run’s leave provision takes in the difference."
          )
        )
        .font(.web(12))
        .foregroundStyle(palette[.amber(700)])
      }
      WebButton(t("Change the days from a date"), icon: .plus, variant: .outline, size: .sm) { add() }
    }
  }

  private var days: Binding<[PwDraft]> {
    Binding<[PwDraft]>(
      get: { (policy.fields["annualDays"]?.array ?? []).map { PwDraft($0) } },
      set: { policy.fields["annualDays"] = .array($0.map(\.json)) })
  }

  private var savedDays: [JSONValue] { saved?.list("annualDays") ?? [] }

  /// A saved date that has passed, removed or moved: balances from it change too.
  private var pastRemoved: Bool {
    let today = ISODates.today()
    let rows = days.wrappedValue
    return savedDays.contains { old in
      old.str("from") <= today && !rows.contains { $0.text("from") == old.str("from") }
    }
  }

  private func note(_ row: PwDraft) -> PwRowNote? {
    if row.number("days") < 30 { return PwRowNote(text: t("At least 30 days a year (art. 70)."), error: true) }
    let unsaved = !savedDays.contains { $0.str("from") == row.text("from") && $0.num("days") == row.number("days") }
    guard unsaved, row.text("from") <= ISODates.today() else { return nil }
    return PwRowNote(
      text: t(
        "This date has passed: balances from it change, and the next approved pay run’s leave provision takes in the difference."
      ), error: false)
  }

  private func add() {
    let rows = days.wrappedValue
    let last = rows.last?.number("days") ?? 30
    days.wrappedValue =
      rows + [PwDraft(["from": .string(PwSettings.nextMonthStart(ISODates.today())), "days": .number(last)])]
  }

  private func remove(_ index: Int) {
    var rows = days.wrappedValue
    guard rows.count > 1, rows.indices.contains(index) else { return }
    rows.remove(at: index)
    days.wrappedValue = rows
  }
}

private struct PwAnnualDaysRow: View {
  @Binding var row: PwDraft
  let note: PwRowNote?
  let single: Bool
  let onRemove: () -> Void
  @Environment(\.palette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .bottom, spacing: 8) {
        Field(t("From")) { DateField(value: $row.text("from"), required: true) }
        Field(t("Days a year")) { PwNumberField(value: $row.number("days")) }
        WebButton(icon: .trash2, label: t("Remove"), action: onRemove)
          .disabled(single)
      }
      if let note {
        Text(note.text)
          .font(.web(12))
          .foregroundStyle(note.error ? palette[.red(600)] : palette[.amber(700)])
      }
    }
  }
}

/// The months before the first leave, the days carried into a new year, and how leave is counted.
private struct PwPolicyRules: View {
  @Binding var policy: PwDraft
  let locked: Bool

  var body: some View {
    Field(
      t("Months before the first leave"),
      hint: t("Nine under the Labour Law (art. 70); fewer lets new staff take leave sooner.")
    ) {
      Select(selection: $policy.number("firstYearMonths"), options: months)
    }
    Field(
      t("Most days carried into a new year"),
      hint: t(
        "Unused days above it are lost when a new year starts. Leave it empty to carry every day forward: unused days are paid when the employee leaves (art. 73)."
      ), optional: true
    ) { PwOptionalNumberField(value: carry, placeholder: t("No cap")) }
    Field(
      t("Leave is counted in"),
      hint: locked
        ? t("Annual leave has been recorded, so the way it is counted stays as it is.")
        : t("Working days skip Fridays, Saturdays and public holidays.")
    ) {
      Select(
        selection: counting,
        options: [SelectOption("working", t("Working days")), SelectOption("calendar", t("Calendar days"))]
      )
      .disabled(locked)
    }
  }

  /// Nine months (the law) down to none.
  private var months: [SelectOption<Double>] {
    (0...9).reversed().map { SelectOption(Double($0), tp($0, "{count} month", "{count} months")) }
  }

  private var carry: Binding<Double?> {
    Binding<Double?>(
      get: { policy.fields["carryForwardMax"]?.double },
      set: { policy.fields["carryForwardMax"] = $0.map { $0 > 0 ? JSONValue.number($0) : .null } ?? .null })
  }

  private var counting: Binding<String> {
    Binding<String>(
      get: { policy.text("counting") == "calendar" ? "calendar" : "working" },
      set: { policy.fields["counting"] = .string($0 == "calendar" ? "calendar" : "working") })
  }
}

private struct PwProvisionsCard: View {
  @Binding var value: PwDraft

  var body: some View {
    PeCard(t("Provisions")) {
      Switch(
        t("Post end-of-service and leave provisions each month"),
        description: t(
          "When a pay run is approved, the end-of-service provision is brought to what everyone would get at the month end, and the leave salary provision to the value of unused leave."
        ), isOn: $value.flag("provisions"))
      Switch(
        t("Include staff insured with PIFSS in the end-of-service provision"),
        description: t(
          "For Kuwaiti and GCC staff the employer pays only what PIFSS does not cover. Leave it off unless you owe them an indemnity."
        ), isOn: $value.flag("eosForInsured")
      )
      .disabled(!value.flag("provisions"))
    }
  }
}

/// Where the payroll posts: the account found by code or name, or one chosen.
private struct PwPayrollAccountsCard: View {
  @Binding var value: PwDraft
  @Environment(AppModel.self) private var model

  var body: some View {
    PeCard(
      t("Accounts"),
      description: t("Where the payroll posts. Accounts that are missing are created when first used.")
    ) {
      ForEach(PePayrollAccounts.specs, id: \.key) { spec in
        Field(PePayrollAccounts.label(spec.key)) {
          Select(selection: chosen(spec.key), options: options(spec))
        }
      }
    }
  }

  private func chosen(_ key: String) -> Binding<String> {
    Binding<String>(
      get: { value.fields["accounts"]?[key]?.string ?? "" },
      set: { id in
        var accounts = value.fields["accounts"]?.object ?? [:]
        accounts[key] = id.isEmpty ? nil : .string(id)
        value.fields["accounts"] = .object(accounts)
      })
  }

  private func options(_ spec: PeAccountSpec) -> [SelectOption<String>] {
    let one = model.one
    let found = PePayrollAccounts.found(spec, one)
    let first =
      found.map { $0.str("code") + " " + localName($0) }
      ?? t("{code} {name} (created when used)", ["code": spec.code, "name": localName(spec.name, spec.nameAr)])
    let others = one.records(.accounts)
      .filter { !$0.flag("archived") && $0.rid != found?.rid }
      .sorted { $0.str("code").localizedStandardCompare($1.str("code")) == .orderedAscending }
      .map { SelectOption($0.rid, $0.str("code") + " " + localName($0)) }
    return [SelectOption("", first)] + others
  }
}

// MARK: - Leave reasons

/// `/payroll/leave-reasons`, editable.
struct PwLeaveReasonsView: View {
  @Environment(AppModel.self) private var model
  /// The two switches as changed, nil until one is.
  @State private var switches: PwDraft?
  @State private var busy = false
  /// The reason in the dialog, nil when it is closed.
  @State private var editing: PwDraft?
  @State private var editingIsNew = false
  @State private var editingError: String?
  @State private var savingReason = false
  @State private var removing: PeLeaveReason?

  var body: some View {
    let settings = model.one.pePayrollSettings
    WebPage(refresh: { [model] in await model.one.sync() }) {
      PePayrollHeader(
        tab: "reasons",
        description: t("Reasons for leave of the company’s own, besides the six types of the Labour Law."))
      VStack(alignment: .leading, spacing: 24) {
        PwReasonsCard(
          settings: settings, on: on, onEdit: edit,
          onArchive: { reason, archived in Task { await setArchived(reason, archived) } },
          onRemove: { removing = $0 }, onRecommended: { Task { await addRecommended() } })
        PwAccrualPauseCard(settings: settings, pause: pause)
        buttons
      }
    }
    .modifier(
      PwLeaveReasonDialog(
        editing: $editing, error: $editingError, isNew: editingIsNew, saving: savingReason, locked: locked
      ) { Task { await saveReason() } }
    )
    .pwConfirm(
      removingShown, title: t("Remove {name}?", ["name": removing?.displayName ?? ""]),
      description: t("No leave is recorded with it, so it can be removed."), confirmLabel: t("Remove"), danger: true
    ) { Task { await remove() } }
  }

  /// The switches as changed, or as saved.
  private var switchesNow: PwDraft {
    if let switches { return switches }
    let raw = model.one.pePayrollSettings.raw
    return PwDraft([
      "leaveReasonsOn": raw?["leaveReasonsOn"] ?? .null, "leaveAccrualPause": raw?["leaveAccrualPause"] ?? .null,
    ])
  }

  private var on: Binding<Bool> {
    Binding<Bool>(
      get: { switchesNow.flag("leaveReasonsOn") },
      set: { now in
        var next = switchesNow
        next.fields["leaveReasonsOn"] = .bool(now)
        switches = next
      })
  }

  /// The day the pause of long unpaid leave starts, nil while it is off.
  private var pause: Binding<String?> {
    Binding<String?>(
      get: { switchesNow.fields["leaveAccrualPause"]?["from"]?.string },
      set: { from in
        var next = switchesNow
        next.fields["leaveAccrualPause"] = from.map { ["from": .string($0)] } ?? .null
        switches = next
      })
  }

  private var buttons: some View {
    HStack(spacing: 8) {
      Spacer(minLength: 0)
      if switches != nil {
        WebButton(t("Discard changes"), variant: .outline) { switches = nil }
      }
      WebButton(t("Save changes"), loading: busy) { Task { await saveSwitches() } }
        .disabled(switches == nil)
    }
  }

  /// Leave is recorded with the reason being edited: how it is paid stays.
  private var locked: Bool {
    guard let id = editing?.text("id") else { return false }
    return model.one.peLeaveRecords.contains { $0.reasonId == id }
  }

  private var removingShown: Binding<Bool> {
    Binding<Bool>(get: { removing != nil }, set: { if !$0 { removing = nil } })
  }

  /// `newLeaveReason()` (on full pay, as most are), or the reason as saved.
  private func edit(_ reason: PeLeaveReason?) {
    editing = PwDraft(
      reason?.raw ?? ["id": .string(newId()), "name": "", "nameAr": "", "base": "bereavement", "pay": "full"])
    editingIsNew = (reason?.name ?? "").isEmpty
    editingError = nil
  }

  private func saveSwitches() async {
    guard let changed = switches?.json else { return }
    busy = true
    defer { busy = false }
    let text = PwText.app
    guard
      await PwSave.run(
        model, success: t("Leave reasons saved"),
        { ctx in try PwSettings.saveLeaveReasonSettings(ctx, changed, text: text) }) != nil
    else { return }
    switches = nil
  }

  private func saveReason() async {
    guard let reason = editing?.json else { return }
    if reason.str("name").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      editingError = t("Enter the name of each leave reason.")
      return
    }
    savingReason = true
    defer { savingReason = false }
    editingError = nil
    let text = PwText.app
    guard
      await PwSave.run(
        model, success: t("Leave reason saved"), failed: { editingError = $0 },
        { ctx in
          try PwSettings.updateLeaveReasons(ctx, text: text) { list in
            list.contains { $0.rid == reason.rid }
              ? list.map { $0.rid == reason.rid ? reason : $0 } : list + [reason]
          }
        }) != nil
    else { return }
    editing = nil
  }

  private func setArchived(_ reason: PeLeaveReason, _ archived: Bool) async {
    let id = reason.id
    let text = PwText.app
    await PwSave.run(model, success: archived ? t("Leave reason archived") : t("Leave reason restored")) { ctx in
      try PwSettings.updateLeaveReasons(ctx, text: text) { list in
        list.map { item in
          guard item.rid == id else { return item }
          var changed = item
          changed.set("archived", .bool(archived))
          return changed
        }
      }
    }
  }

  private func remove() async {
    guard let id = removing?.id else { return }
    removing = nil
    let text = PwText.app
    await PwSave.run(model, success: t("Leave reason removed")) { ctx in
      try PwSettings.updateLeaveReasons(ctx, text: text) { list in list.filter { $0.rid != id } }
    }
  }

  /// The owner's recommended reasons: emergency leave taken from annual leave, and compensatory days added by hand.
  private func addRecommended() async {
    let recommended: [JSONValue] = [
      ["id": .string(newId()), "name": "Emergency leave", "nameAr": "إجازة طارئة", "base": "annual", "pay": "annual"],
      [
        "id": .string(newId()), "name": "Compensatory days", "nameAr": "أيام تعويضية", "base": "bereavement",
        "pay": "balance",
      ],
    ]
    let text = PwText.app
    await PwSave.run(model, success: t("Recommended leave reasons added")) { ctx in
      try PwSettings.updateLeaveReasons(ctx, text: text) { list in list + recommended }
    }
  }
}

/// The reasons, the switch that offers them, and what can be done with each.
private struct PwReasonsCard: View {
  let settings: PePayrollSettings
  @Binding var on: Bool
  let onEdit: (PeLeaveReason?) -> Void
  let onArchive: (PeLeaveReason, Bool) -> Void
  let onRemove: (PeLeaveReason) -> Void
  let onRecommended: () -> Void
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    PeCard(
      t("Leave reasons"),
      description: t(
        "Such as emergency leave or compensatory days. Each one says how its leave is paid and what it does to the balances. Leave keeps the pay it was recorded with."
      ),
      actions: {
        WebButton(t("Add a reason"), icon: .plus, size: .sm) { onEdit(nil) }
      }
    ) {
      Switch(
        t("Offer these reasons when leave is recorded"),
        description: t(
          "Off: leave is recorded with the six types of the Labour Law only, as before. Leave already recorded with a reason keeps its pay either way."
        ), isOn: $on)
      PeNote(
        t(
          "Ask your auditor to confirm how each reason is paid before you switch them on: leave taken from annual leave lowers the annual leave balance and the leave salary provision, and leave on half pay or without pay lowers the month’s pay."
        ))
      PeNote(
        t(
          "Update the app on every device that records leave or prepares pay runs first. Older versions show each reason’s leave as one of the six types (see below each reason), and a pay run they work out can’t be approved here until it is updated from the records."
        ))
      list
    }
  }

  @ViewBuilder
  private var list: some View {
    if settings.leaveReasons.isEmpty {
      WebEmptyState(
        icon: .tags, title: t("No leave reasons yet"),
        description: t(
          "We recommend emergency leave taken from annual leave, and compensatory days added by hand. Any other reason starts on full pay; give it the most days a year it allows."
        )
      ) {
        WebButton(t("Add the recommended reasons"), icon: .listPlus, variant: .outline, action: onRecommended)
      }
    } else {
      VStack(spacing: 0) {
        ForEach(sorted) { reason in
          PwReasonRow(
            reason: reason, inUse: used.contains(reason.id), onEdit: { onEdit(reason) },
            onArchive: { onArchive(reason, !reason.archived) }, onRemove: { onRemove(reason) })
        }
      }
      .border(palette.slate(200), in: RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous))
    }
  }

  private var used: Set<String> { Set(model.one.peLeaveRecords.compactMap(\.reasonId)) }

  /// Archived ones last, otherwise as saved.
  private var sorted: [PeLeaveReason] {
    let all = settings.leaveReasons
    return all.filter { !$0.archived } + all.filter(\.archived)
  }
}

private struct PwReasonRow: View {
  let reason: PeLeaveReason
  let inUse: Bool
  let onEdit: () -> Void
  let onArchive: () -> Void
  let onRemove: () -> Void
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      FlowLayout(spacing: 8) {
        Text(reason.displayName).font(.web(14, .medium)).foregroundStyle(palette.slate(900))
        if reason.archived { Badge(t("Archived"), tone: .slate) }
        if inUse { Badge(t("In use"), tone: .blue) }
      }
      Text(details).font(.web(12)).foregroundStyle(palette.slate(500))
      if let older = PeLeave.reasonOlderText(reason) {
        Text(older).font(.web(12)).foregroundStyle(palette.slate(400))
      }
      actions
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }

  private var actions: some View {
    FlowLayout(spacing: 4) {
      WebButton(t("Edit"), icon: .pencil, variant: .ghost, size: .xs, action: onEdit)
      WebButton(
        reason.archived ? t("Restore") : t("Archive"), icon: reason.archived ? .archiveRestore : .archive,
        variant: .ghost, size: .xs, action: onArchive)
      if !inUse {
        WebButton(t("Remove"), icon: .trash2, variant: .ghost, size: .xs, action: onRemove)
      }
    }
  }

  private var details: String {
    var parts = [PeLeave.reasonPayLabel(reason)]
    if let max = reason.maxDaysPerYear {
      parts.append(t("At most {days} days a year", ["days": model.one.format.quantity(max)]))
    }
    if !reason.categories.isEmpty {
      let separator = LanguageStore.shared.isArabic ? "، " : ", "
      let names = reason.categories.map { PePeople.categoryLabel($0) }.joined(separator: separator)
      parts.append(t("For: {categories}", ["categories": names]))
    }
    if reason.noteRequired { parts.append(t("A note is needed")) }
    return parts.joined(separator: " · ")
  }
}

/// Long unpaid leave: from a date, a month of service with more than 15 days of it earns no annual leave.
private struct PwAccrualPauseCard: View {
  let settings: PePayrollSettings
  @Binding var pause: String?

  var body: some View {
    PeCard(
      t("Long unpaid leave"),
      description: t(
        "Annual leave is earned for each month of service, counted from the hire date (or the opening balance).")
    ) {
      Switch(
        t("A month of service with more than {days} days of unpaid leave earns no annual leave", ["days": "15"]),
        description: t(
          "Off: every month of service earns annual leave, as before. Unpaid leave counts in calendar days; leave on half pay doesn’t count."
        ), isOn: on)
      PeNote(
        t(
          "Ask your auditor to confirm that a month of service with more than 15 days of unpaid leave earns no annual leave before you switch this on: it lowers the annual leave balance, the leave salary provision and the final settlement of staff on long unpaid leave."
        ))
      if pause != nil {
        Field(t("From"), hint: hint) { DateField(value: from, required: true) }
      }
    }
  }

  private var on: Binding<Bool> {
    Binding<Bool>(
      get: { pause != nil },
      set: { now in
        pause = now ? (settings.accrualPauseFrom ?? PwSettings.nextMonthStart(ISODates.today())) : nil
      })
  }

  private var from: Binding<String> {
    Binding<String>(
      get: { pause ?? "" },
      set: { if ISODates.isISODate($0) { pause = $0 } })
  }

  private var hint: String {
    if pause != settings.accrualPauseFrom, let pause, pause <= ISODates.today() {
      return t(
        "This date has passed: balances from it change, and the next approved pay run’s leave provision takes in the difference."
      )
    }
    return t("Months of service that start before this date earn as before.")
  }
}

/// Adding or changing one leave reason. Its fields are kept by the page.
private struct PwLeaveReasonDialog: ViewModifier {
  @Binding var editing: PwDraft?
  @Binding var error: String?
  let isNew: Bool
  let saving: Bool
  let locked: Bool
  let onSave: () -> Void
  @Environment(\.palette) private var palette

  func body(content: Content) -> some View {
    content.webDialog(
      isPresented: shown, title: isNew ? t("Add a leave reason") : t("Edit leave reason"),
      description: t("Leave of this reason is recorded and paid as set here.")
    ) {
      PwLeaveReasonFields(reason: reason, locked: locked)
      if let error {
        Text(error).font(.web(14)).foregroundStyle(palette[.red(600)])
      }
    } footer: {
      WebButton(t("Cancel"), variant: .outline) { editing = nil }
      WebButton(t("Save"), loading: saving, action: onSave)
    }
  }

  private var shown: Binding<Bool> {
    Binding<Bool>(get: { editing != nil }, set: { if !$0 { editing = nil } })
  }

  private var reason: Binding<PwDraft> {
    Binding<PwDraft>(
      get: { editing ?? PwDraft(nil) },
      set: { if editing != nil { editing = $0 } })
  }
}

private struct PwLeaveReasonFields: View {
  @Binding var reason: PwDraft
  let locked: Bool

  static let pays = ["full", "half", "unpaid", "annual", "balance"]
  static let categories = ["kuwaiti", "gcc", "expat", "domestic"]

  var body: some View {
    Field(t("Name (English)")) { TextInput(text: $reason.text("name")) }
    Field(t("Name (Arabic)"), optional: true) { TextInput(text: $reason.text("nameAr")) }
    Field(t("How it is paid"), hint: payHint) {
      Select(selection: pay, options: payOptions)
        .disabled(locked || !known)
    }
    Field(
      t("Most days a year"),
      hint: t("Leave over it is still recorded, with a warning. Leave counts in the year it starts."), optional: true
    ) { PwOptionalNumberField(value: maxDays, placeholder: t("No limit")) }
    categoryFields
    Switch(
      t("A note is needed"), description: t("Leave of this reason can’t be saved without a note."),
      isOn: $reason.flag("noteRequired"))
  }

  private var categoryFields: some View {
    Field(
      t("For"),
      hint: t(
        "Tick none for everyone. Domestic workers come under their own law (Law 68/2015), so they can have reasons of their own."
      )
    ) {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Self.categories, id: \.self) { category in
          Switch(PePeople.categoryLabel(category), isOn: ticked(category))
        }
      }
    }
  }

  private var known: Bool { Self.pays.contains(reason.text("pay")) }

  private var payOptions: [SelectOption<String>] {
    let all = Self.pays.map { SelectOption($0, PeLeave.reasonPayLabel(PeLeaveReason(["pay": .string($0)]))) }
    return known ? all : [SelectOption(reason.text("pay"), t("Other leave"))] + all
  }

  private var payHint: String? {
    if locked {
      return t(
        "Leave is recorded with this reason, so how it is paid stays as it is. To change it, archive this reason and add a new one."
      )
    }
    guard known else { return nil }
    let older = PeLeave.reasonOlderText(PeLeaveReason(reason.json)) ?? ""
    return Self.payText(reason.text("pay")) + " " + older
  }

  /// `LEAVE_REASON_PAY_HINTS`.
  nonisolated static func payText(_ pay: String) -> String {
    switch pay {
    case "half": t("Each calendar day of it costs half a day’s pay.")
    case "unpaid": t("Each calendar day of it costs a day’s pay, like unpaid leave.")
    case "annual": t("Paid in full and taken from the annual leave balance, like annual leave.")
    case "balance":
      t(
        "Paid in full from a balance of its own: add days to it by hand, such as compensatory days for work on a rest day."
      )
    default: t("Paid in full; the annual leave balance doesn’t change.")
    }
  }

  /// How it is paid, and the type its leave keeps (`leaveReasonBase`).
  private var pay: Binding<String> {
    Binding<String>(
      get: { reason.text("pay") },
      set: { pay in
        reason.fields["pay"] = .string(pay)
        reason.fields["base"] = .string(Self.base(pay))
      })
  }

  nonisolated static func base(_ pay: String) -> String {
    switch pay {
    case "half", "unpaid": "unpaid"
    case "annual": "annual"
    default: "bereavement"
    }
  }

  private var maxDays: Binding<Double?> {
    Binding<Double?>(
      get: { reason.fields["maxDaysPerYear"]?.double },
      set: { reason.fields["maxDaysPerYear"] = $0.map { $0 > 0 ? JSONValue.number($0) : .null } ?? .null })
  }

  private func ticked(_ category: String) -> Binding<Bool> {
    Binding<Bool>(
      get: { (reason.fields["categories"]?.array ?? []).contains(.string(category)) },
      set: { on in
        var list = reason.fields["categories"]?.array ?? []
        if on {
          if !list.contains(.string(category)) { list.append(.string(category)) }
        } else {
          list.removeAll { $0 == .string(category) }
        }
        reason.fields["categories"] = .array(list)
      })
  }
}
