import MahamKit
import SwiftUI

// Manpower costings saved natively, as the web's costing editor saves them:
// its name, customer, overhead, margin, status and notes, its posts by hand
// or from the rate card (`saveCosting`, priced again with today's
// settings), deleted (`deleteCosting`); and the costing switch.

/// `/people/costing?new=1`, and a costing changed on its own page.
struct PwCostingEditorPage: View {
  let id: String?

  var body: some View {
    WebPage {
      PwCostingEditor(id: id)
    }
  }
}

/// The editor of one costing, new (`id` nil) or saved.
struct PwCostingEditor: View {
  let id: String?
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @State private var draft: PwDraft?
  @State private var fresh: JSONValue?
  @State private var busy: String?
  @State private var confirmingDelete = false

  var body: some View {
    content.onAppear(perform: start)
  }

  @ViewBuilder
  private var content: some View {
    let one = model.one
    if !one.pePeopleSettings.costing.on || (id != nil && stored == nil) {
      Card {
        WebEmptyState(
          icon: .calculator, title: id != nil && stored == nil ? t("Costing not found") : t("Manpower costing is off")
        ) {
          WebButton(t("Manpower costing"), icon: .arrowLeft, variant: .outline) { router.push(.costings) }
        }
      }
    } else if let costing = current {
      editor(costing)
    }
  }

  @ViewBuilder
  private func editor(_ costing: JSONValue) -> some View {
    let value = Binding<PwDraft>(get: { draft ?? PwDraft(costing) }, set: { draft = $0 })
    PageHeader(
      costing.text("name") ?? t("New costing"), breadcrumb: t("Manpower costing"), onBreadcrumb: { router.back() }
    ) {
      WebButton(t("Save"), loading: busy == "save") { Task { await save() } }
    }
    VStack(alignment: .leading, spacing: 24) {
      PwCostingMain(value: value)
      PwCostingPosts(value: value)
      PwCostingTotals(costing: value.wrappedValue.json)
      if id != nil {
        WebButton(t("Delete costing"), icon: .trash2, variant: .ghost) { confirmingDelete = true }
      }
    }
    .padding(.bottom, 24)
    .pwConfirm(
      $confirmingDelete, title: t("Delete this costing?"), description: deleteText(costing), confirmLabel: t("Delete"),
      danger: true
    ) { Task { await remove() } }
  }

  private var stored: JSONValue? { id.flatMap { model.one.record(.staffingCostings, $0) } }

  /// The costing as edited, or as saved, or a new one made once.
  private var current: JSONValue? {
    if let draft { return draft.json }
    if id != nil { return stored }
    return fresh
  }

  /// `newCosting`, made once: the company's overhead and margin, no posts.
  private func start() {
    let one = model.one
    guard id == nil, fresh == nil, let companyId = one.companyId else { return }
    let settings = one.pePeopleSettings.costing
    fresh = PwCosting.newCosting(
      companyId: companyId, overheadPercent: settings.overheadPercent, marginPercent: settings.marginPercent)
  }

  private func deleteText(_ costing: JSONValue) -> String {
    guard let quote = costing.text("quoteId").flatMap({ model.one.record(.documents, $0) }) else {
      return t("This can’t be undone.")
    }
    return t("Quote {number} made from it stays as it is.", ["number": quote.text("number") ?? t("Draft")])
  }

  private func save() async {
    guard let input = current else { return }
    busy = "save"
    defer { busy = nil }
    let link = model.one.pwLink
    guard
      let saved = await PwSave.run(
        model, success: t("Costing saved"), { ctx in try PwCosting.save(ctx, input, link: link) })
    else { return }
    draft = nil
    if id == nil { PwNav.replaceTop(router, with: .costing(id: saved.rid)) }
  }

  private func remove() async {
    guard let id else { return }
    busy = "delete"
    defer { busy = nil }
    let link = model.one.pwLink
    guard await PwSave.run(model, { ctx in try PwCosting.delete(ctx, id: id, link: link) }) != nil else { return }
    PwNav.replaceTop(router, with: .costings)
  }
}

/// Name, customer, overhead, margin, status and notes.
private struct PwCostingMain: View {
  @Binding var value: PwDraft
  @Environment(AppModel.self) private var model

  var body: some View {
    Card {
      CardBody {
        VStack(alignment: .leading, spacing: 16) {
          Field(t("Name"), hint: t("For the company only, never on the quote.")) {
            TextInput(text: $value.text("name"), placeholder: t("For example: Tower A, night shift"))
          }
          Field(t("Customer")) {
            Combobox(selection: customer, options: customers, placeholder: t("Choose a customer"))
          }
          Field(t("Overhead (%)"), hint: t("At most {max}%.", ["max": "200"])) {
            PwNumberField(value: $value.number("overheadPercent"))
          }
          Field(
            t("Margin (% of the sell price)"),
            hint: t("At most {max}%.", ["max": "90"]) + " " + PeCosting.marginExplained(value.number("marginPercent"))
          ) { PwNumberField(value: $value.number("marginPercent")) }
          Field(t("Status")) {
            Select(
              selection: $value.text("status"),
              options: PwCosting.statuses.map { SelectOption($0, t(PeCosting.statusMeta($0).label)) })
          }
          Field(t("Internal notes"), hint: t("Never on the quote."), optional: true) {
            PwTextArea(text: $value.text("notes"), minHeight: 64)
          }
        }
      }
    }
  }

  private var customer: Binding<String?> {
    Binding<String?>(
      get: { value.fields["clientId"]?.string },
      set: { value.fields["clientId"] = $0.map(JSONValue.string) ?? .null })
  }

  /// The customers to choose from: those not archived, and the one chosen.
  private var customers: [ComboOption] {
    let chosen = value.fields["clientId"]?.string
    return model.one.records(.clients)
      .filter { !$0.flag("archived") || $0.rid == chosen }
      .sorted { localName($0).localizedCompare(localName($1)) == .orderedAscending }
      .map { client in
        ComboOption(
          value: client.rid, label: localName(client), detail: client.text("number"),
          keywords: client.str("name") + " " + client.str("nameAr"))
      }
  }
}

/// The posts: each with its pay and what it costs and sells for, added by hand or from the rate card.
private struct PwCostingPosts: View {
  @Binding var value: PwDraft
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    let one = model.one
    let basis = PeCosting.basis(one.pePayrollSettings, one.pePeopleSettings, precision: one.pePrecision)
    let priced = PeCosting.price(value.json, basis: basis).posts
    VStack(alignment: .leading, spacing: 12) {
      Text(t("Posts")).webText(.cardTitle)
      Text(
        t(
          "Pay per person a month. Hours past 8 a day are overtime at 1.25; days past {days} a month are rest days worked, at 1.5.",
          ["days": Money.jsString(basis.dailyDivisor)])
      )
      .font(.web(14))
      .foregroundStyle(palette.slate(500))
      if posts.wrappedValue.isEmpty {
        Card {
          WebEmptyState(
            icon: .calculator, title: t("No posts yet"),
            description: t("Add the posts the customer asks for, from the rate card or by hand."))
        }
      }
      ForEach(posts.wrappedValue.indices, id: \.self) { index in
        PwPostEditor(post: posts.row(index), priced: priced.indices.contains(index) ? priced[index] : nil) {
          remove(index)
        }
      }
      adding
    }
  }

  private var posts: Binding<[PwDraft]> {
    Binding<[PwDraft]>(
      get: { (value.fields["posts"]?.array ?? []).map { PwDraft($0) } },
      set: { value.fields["posts"] = .array($0.map(\.json)) })
  }

  private var adding: some View {
    FlowLayout(spacing: 8) {
      WebButton(t("Add post"), icon: .plus, variant: .outline, size: .sm) { add(nil) }
      if !rates.isEmpty {
        Select(selection: rateChoice, options: rateOptions, placeholder: t("Add from the rate card…"))
      }
    }
  }

  /// The rate card: the one saved, or the average pay of each job title.
  private var rates: [PeCostingRate] {
    let one = model.one
    return one.pePeopleSettings.costing.rates ?? PeCosting.averageRates(one.peEmployees, one.pePrecision)
  }

  private var rateOptions: [SelectOption<String>] {
    [SelectOption("", t("Add from the rate card…"))]
      + rates.map { rate in
        SelectOption(
          rate.id, localName(rate.jobTitle, rate.jobTitleAr) + " · " + PeCosting.categoryLabel(rate.category))
      }
  }

  /// Choosing a rate adds a post from it.
  private var rateChoice: Binding<String> {
    Binding<String>(
      get: { "" },
      set: { id in
        guard let rate = rates.first(where: { $0.id == id }) else { return }
        add(rate)
      })
  }

  /// `newPost(rate)`.
  private func add(_ rate: PeCostingRate?) {
    let json: JSONValue? = rate.map { rate in
      var fields: [String: JSONValue] = [
        "id": .string(rate.id), "jobTitle": .string(rate.jobTitle), "category": .string(rate.category),
        "nationality": .string(rate.nationality), "basic": .number(rate.basic), "allowances": .number(rate.allowances),
        "otherCosts": .number(rate.otherCosts),
      ]
      if let arabic = rate.jobTitleAr { fields["jobTitleAr"] = .string(arabic) }
      if let eos = rate.eosAllowances { fields["eosAllowances"] = .number(eos) }
      return .object(fields)
    }
    posts.wrappedValue = posts.wrappedValue + [PwDraft(PwCosting.newPost(rate: json))]
  }

  private func remove(_ index: Int) {
    var list = posts.wrappedValue
    guard list.indices.contains(index) else { return }
    list.remove(at: index)
    posts.wrappedValue = list
  }
}

/// One post: who, how many and how long, their pay, and what it costs and sells for.
private struct PwPostEditor: View {
  @Binding var post: PwDraft
  let priced: PePricedPost?
  let onRemove: () -> Void
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    Card {
      CardBody {
        VStack(alignment: .leading, spacing: 12) {
          Field(t("Job title")) { TextInput(text: $post.text("jobTitle")) }
          Field(t("Arabic job title"), optional: true) {
            TextInput(text: $post.text("jobTitleAr")).environment(\.layoutDirection, .rightToLeft)
          }
          Field(t("Category")) {
            Select(
              selection: category,
              options: ["expat", "kuwaiti", "gcc"].map { SelectOption($0, PeCosting.categoryLabel($0)) })
          }
          if category.wrappedValue == "gcc" {
            Field(t("Nationality")) { Select(selection: $post.text("nationality"), options: nationalities) }
          }
          PwPostNumbers(post: $post)
          if let priced { PwPostFigures(post: priced) }
          WebButton(t("Remove post"), icon: .trash2, variant: .ghost, size: .sm, action: onRemove)
        }
      }
    }
  }

  private var category: Binding<String> {
    Binding<String>(
      get: { post.text("category").isEmpty ? "expat" : post.text("category") },
      set: { post.fields["category"] = .string($0) })
  }

  private var nationalities: [SelectOption<String>] {
    [SelectOption("", t("Choose…"))]
      + PePeople.gccCountries.map {
        SelectOption($0, Geo.countryName($0, locale: model.one.format.locale.identifier))
      }
  }
}

private struct PwPostNumbers: View {
  @Binding var post: PwDraft

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Field(t("Headcount")) { PwNumberField(value: $post.number("headcount")) }
      Field(t("Hours a day")) { PwNumberField(value: $post.number("hoursPerDay")) }
      Field(t("Days a month")) { PwNumberField(value: $post.number("daysPerMonth")) }
    }
    HStack(alignment: .top, spacing: 8) {
      Field(t("Basic salary")) { PwNumberField(value: $post.number("basic")) }
      Field(t("Allowances")) { PwNumberField(value: $post.number("allowances")) }
    }
    HStack(alignment: .top, spacing: 8) {
      Field(t("Allowances for indemnity")) { PwNumberField(value: eosAllowances) }
      Field(t("Other costs")) { PwNumberField(value: $post.number("otherCosts")) }
    }
  }

  /// The allowances the indemnity counts: all of them until changed.
  private var eosAllowances: Binding<Double> {
    Binding<Double>(
      get: { post.fields["eosAllowances"]?.double ?? post.number("allowances") },
      set: { post.fields["eosAllowances"] = .number($0) })
  }
}

/// What one person of a post costs and sells for a month, and the post in all.
private struct PwPostFigures: View {
  let post: PePricedPost
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    let format = model.one.format
    VStack(alignment: .leading, spacing: 8) {
      PeAmountList(rows: rows(format))
      ForEach(0..<post.warnings.count, id: \.self) { index in
        HStack(alignment: .top, spacing: 8) {
          IconView(.triangleAlert, size: 16).foregroundStyle(palette[.amber(500)])
          Text(PeCosting.warningText(post.warnings[index], format))
            .font(.web(14))
            .foregroundStyle(palette[.amber(800)])
        }
      }
    }
  }

  private func rows(_ format: CompanyFormat) -> [PeAmount] {
    var rows = PeAmountRows()
    rows.add(t("Overtime"), format.money(post.overtime), muted: true)
    rows.add(t("Employer PIFSS"), format.money(post.employerPifss), muted: true)
    rows.add(t("Indemnity"), format.money(post.eosi), muted: true)
    rows.add(t("Leave"), format.money(post.leave), muted: true)
    rows.add(t("Cost a person"), format.money(post.cost))
    rows.add(t("With overhead"), format.money(post.fullCost))
    rows.add(t("Sell price a person"), format.money(post.sell), strong: true)
    rows.add(t("A month"), format.money(post.totalSell), strong: true)
    return rows.rows
  }
}

/// The costing's totals a month.
private struct PwCostingTotals: View {
  let costing: JSONValue
  @Environment(AppModel.self) private var model

  var body: some View {
    let one = model.one
    let format = one.format
    let basis = PeCosting.basis(one.pePayrollSettings, one.pePeopleSettings, precision: one.pePrecision)
    let totals = PeCosting.price(costing, basis: basis).totals
    PeCard(
      t("Totals a month"),
      description: t(
        "The quote shows the job titles, hours, days, people and sell prices only. Costs, salaries and the margin stay here."
      ) + " " + t("The sell prices are before tax: tax, when the company charges it, is added on top.")
    ) {
      PeAmountList(rows: rows(totals, format))
    }
  }

  private func rows(_ totals: PeCostingTotals, _ format: CompanyFormat) -> [PeAmount] {
    var rows = PeAmountRows()
    rows.add(t("Headcount"), format.count(totals.headcount))
    rows.add(t("Cost a month"), format.money(totals.cost))
    rows.add(t("Overhead"), format.money(totals.overhead))
    rows.add(t("Sell price a month"), format.money(totals.sell), strong: true)
    rows.add(t("Margin"), format.money(totals.margin))
    rows.add(t("Margin of the sell price"), Money.jsString(totals.marginPercent) + "%")
    rows.add(t("Markup on cost"), Money.jsString(totals.markupPercent) + "%")
    return rows.rows
  }
}

// MARK: - The costing switch

/// "Use manpower costing", saved when it is turned (`setCostingsOn`).
struct PwCostingSwitchRow: View {
  let on: Bool
  @Environment(AppModel.self) private var model
  @State private var busy = false

  var body: some View {
    Switch(
      t("Use manpower costing"),
      description: t(
        "Off: nothing changes, as before. On: the owner, admins and accountants make costings here. Costings, their salaries, costs and margins stay private like payroll: staff and viewers never see them, and the quote shows the sell prices only."
      ), isOn: Binding<Bool>(get: { on }, set: { value in Task { await turn(value) } })
    )
    .disabled(busy)
  }

  private func turn(_ value: Bool) async {
    busy = true
    defer { busy = false }
    let link = model.one.pwLink
    await PwSave.run(
      model, success: value ? t("Manpower costing turned on") : t("Manpower costing turned off")
    ) { ctx in try PwCosting.setOn(ctx, value, link: link) }
  }
}
