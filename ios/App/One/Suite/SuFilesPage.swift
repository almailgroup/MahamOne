import MahamKit
import SwiftUI

// Files (`src/pages/files.tsx`, `src/features/files/file-index.ts`): every
// file kept with the company's records, with what it is kept with, found by
// name, by that record and its number. Employees' files and confidential
// papers are left out for those who don't see People. Opening a file comes
// with a later version: they are listed with their record, date and size.

/// What a file is kept with.
enum SuFileKind: String, CaseIterable, Sendable {
  case document, expense, payment, asset, paper, employee, letter, certificate, other

  var label: String {
    switch self {
    case .document: "Sales and purchases"
    case .expense: "Expenses"
    case .payment: "Payments"
    case .asset: "Fixed assets"
    case .paper: "Papers"
    case .employee: "Employees"
    case .letter: "Letters"
    case .certificate: "Clearance certificates"
    case .other: "Other"
    }
  }
}

/// What a file holds, told by its name.
enum SuFileFormat: Sendable {
  case pdf, image, other

  static let images: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tif", "tiff", "avif"]

  init(name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    let parts = trimmed.split(separator: ".")
    let ext = parts.count > 1 ? String(parts.last ?? "").lowercased() : ""
    if ext == "pdf" {
      self = .pdf
    } else {
      self = SuFileFormat.images.contains(ext) ? .image : .other
    }
  }
}

/// A file of the company, with what it is kept with.
struct SuFileEntry: Identifiable {
  let id: String
  let name: String
  let size: Double
  let format: SuFileFormat
  let kind: SuFileKind
  /// "Bill BILL-0004", an employee's name.
  let owner: String
  /// The vendor, "Personnel file", whom a paper belongs to.
  let detail: String
  let route: Route?
  /// The date of what it is kept with (newest first), else when the file was added.
  let date: String?
  /// Its content is in the cloud, not on this iPhone.
  let inCloud: Bool
  let terms: [String]
}

/// What a file is kept with, described.
private struct SuOwnerInfo {
  var kind: SuFileKind
  var owner: String
  var detail = ""
  var route: Route?
  var date: String?
  var terms: [String] = []
}

/// The company's files, newest record first (`loadFileIndex`).
@MainActor
struct SuFileIndex {
  let one: OneData
  let people: Bool

  var entries: [SuFileEntry] {
    let employees = byId(.employees)
    let products = byId(.products)
    // What makes a file private: an employee, a letter, a private paper or its renewal.
    let tables: [String: [String: JSONValue]] = [
      "employees": employees, "letterTemplates": byId(.letterTemplates), "employeeLetters": byId(.employeeLetters),
      "complianceDocuments": byId(.complianceDocuments), "renewals": byId(.renewals),
    ]
    let lookup: Privacy.Lookup = { table, id in tables[table]?[id] }
    var out: [SuFileEntry] = []
    var described: [String: SuOwnerInfo] = [:]
    for file in one.records(.attachments) {
      let ownerId = file.str("ownerId")
      // An employee's photo and an item's pictures are shown with them, not as files.
      if employees[ownerId]?.str("photoId") == file.rid || products[ownerId] != nil { continue }
      let info = described[ownerId] ?? describe(ownerId)
      described[ownerId] = info
      let isPrivate = Privacy.isPrivateRecord("attachments", file, lookup: lookup)
      if !people && (isPrivate || info.kind == .other) { continue }
      out.append(entry(file, info))
    }
    return out.sorted { Self.order($0, $1) }
  }

  private func entry(_ file: JSONValue, _ info: SuOwnerInfo) -> SuFileEntry {
    let name = file.str("name")
    let missing = file["contentMissing"]?.double == 1 || file.str("dataUrl").isEmpty
    return SuFileEntry(
      id: file.rid, name: name, size: file.num("size"), format: SuFileFormat(name: name), kind: info.kind,
      owner: info.owner, detail: info.detail, route: info.route,
      date: info.date ?? SuDates.localDay(file.text("createdAt")), inCloud: missing, terms: info.terms)
  }

  static func order(_ a: SuFileEntry, _ b: SuFileEntry) -> Bool {
    let (da, db) = (a.date ?? "", b.date ?? "")
    if da != db { return da > db }
    if a.owner != b.owner { return a.owner.localizedCompare(b.owner) == .orderedAscending }
    return a.name.localizedCompare(b.name) == .orderedAscending
  }

  private func byId(_ kind: RecordKind) -> [String: JSONValue] {
    var map: [String: JSONValue] = [:]
    for record in one.records(kind) { map[record.rid] = record }
    return map
  }

  private func words(_ list: [String?]) -> [String] {
    list.compactMap { $0 }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
  }

  /// What the record `ownerId` is, in words, with its page.
  private func describe(_ ownerId: String) -> SuOwnerInfo {
    if let document = one.record(.documents, ownerId) { return describe(document: document) }
    if let expense = one.record(.expenses, ownerId) { return describe(expense: expense) }
    if let payment = one.record(.payments, ownerId) { return describe(payment: payment) }
    if let asset = one.record(.assets, ownerId) { return describe(asset: asset) }
    if let paper = one.record(.complianceDocuments, ownerId) { return describe(paper: paper) }
    if let renewal = one.record(.renewals, ownerId) { return describe(renewal: renewal) }
    if let employee = one.record(.employees, ownerId) { return describe(employee: employee) }
    if let letter = one.record(.employeeLetters, ownerId) { return describe(letter: letter) }
    if let template = one.record(.letterTemplates, ownerId) {
      let name = localName(template)
      return SuOwnerInfo(
        kind: .letter, owner: name.isEmpty ? t("Letter template") : name, detail: t("Letter template"),
        terms: words([template.str("name"), template.str("nameAr")]))
    }
    if let held = certificate(ownerId) { return held }
    return SuOwnerInfo(kind: .other, owner: t("Other"))
  }

  private func describe(document: JSONValue) -> SuOwnerInfo {
    let type = DocType(rawValue: document.str("type"))
    let label = type.map { t($0.singular) } ?? t("Document")
    let client = one.record(.clients, document.str("clientId"))
    return SuOwnerInfo(
      kind: .document, owner: "\(label) \(document.str("number"))".trimmingCharacters(in: .whitespaces),
      detail: client.map { localName($0) } ?? "", route: type?.route(document.rid), date: document.text("issueDate"),
      terms: words([label, client?.str("name"), client?.str("nameAr"), document.str("poNumber"),
        document.str("vendorReference")]))
  }

  private func describe(expense: JSONValue) -> SuOwnerInfo {
    let vendor = one.record(.clients, expense.str("vendorId"))
    let detail = expense.text("description") ?? vendor.map { localName($0) } ?? expense.str("payee")
    return SuOwnerInfo(
      kind: .expense, owner: "\(t("Expense")) \(expense.str("number"))".trimmingCharacters(in: .whitespaces),
      detail: detail, route: .expenses, date: expense.text("date"),
      terms: words([expense.str("description"), vendor?.str("name"), vendor?.str("nameAr"), expense.str("reference")]))
  }

  private func describe(payment: JSONValue) -> SuOwnerInfo {
    let out = payment.str("direction") == "out"
    let client = one.record(.clients, payment.str("clientId"))
    let label = out ? t("Payment made") : t("Payment received")
    return SuOwnerInfo(
      kind: .payment, owner: "\(label) \(payment.str("number"))".trimmingCharacters(in: .whitespaces),
      detail: client.map { localName($0) } ?? "", route: .payment(out ? .made : .received, id: payment.rid),
      date: payment.text("date"),
      terms: words([client?.str("name"), client?.str("nameAr"), payment.str("reference")]))
  }

  private func describe(asset: JSONValue) -> SuOwnerInfo {
    let name = localName(asset)
    return SuOwnerInfo(
      kind: .asset, owner: name.isEmpty ? asset.str("number") : name,
      detail: suJoin([t("Fixed asset"), asset.str("number")]), route: .asset(id: asset.rid),
      date: asset.text("purchaseDate"),
      terms: words([asset.str("name"), asset.str("nameAr"), asset.str("location"), asset.str("serialNumber")]))
  }

  /// A paper of the register: its name, whom it belongs to; an employee's opens the employee.
  private func describe(paper: JSONValue) -> SuOwnerInfo {
    let entry = SuCompliance.recordEntry(paper, days: [], byType: [:])
    let employeeId = paper.text("employeeId")
    let employee = employeeId.flatMap { one.record(.employees, $0) }
    let route: Route = employeeId.map { Route.employee(id: $0) } ?? .complianceDocuments
    return SuOwnerInfo(
      kind: .paper, owner: SuCompliance.title(paper), detail: paperOwner(entry), route: route,
      date: paper.text("expiryDate") ?? paper.text("issueDate"),
      terms: words([paper.str("title"), t(SuDocTypes.label(paper.str("type"))), paper.str("ownerName"),
        paper.str("issuer"), employee?.str("name"), employee?.str("nameAr"), paper.str("number")]))
  }

  private func paperOwner(_ entry: SuEntry) -> String {
    if entry.ownerType == "employee" {
      let name = entry.employeeId.flatMap { one.record(.employees, $0) }.map { localName($0) } ?? ""
      return name.isEmpty ? t("Employee") : name
    }
    if entry.ownerType == "company" { return one.company.map { localName($0) } ?? "" }
    if let id = entry.clientId, let client = one.record(.clients, id) { return localName(client) }
    if !entry.ownerName.isEmpty { return entry.ownerName }
    let plate = entry.vehicleId.flatMap { one.record(.vehicles, $0) }?.str("plate") ?? ""
    return plate.isEmpty ? t(SuDocTypes.ownerLabel(entry.ownerType)) : plate
  }

  private func describe(renewal: JSONValue) -> SuOwnerInfo {
    if let id = Privacy.renewedDocumentId(renewal), let paper = one.record(.complianceDocuments, id) {
      var info = describe(paper: paper)
      info.detail = suJoin([t("Renewal"), info.detail])
      return info
    }
    let employeeId = renewal.text("employeeId")
    let employee = employeeId.flatMap { one.record(.employees, $0) }
    return SuOwnerInfo(
      kind: .paper, owner: t(SuDocTypes.label(renewal.str("type"))),
      detail: suJoin([t("Renewal"), employee.map { localName($0) }]), route: employeeId.map { Route.employee(id: $0) },
      date: renewal.text("renewedOn"), terms: words([employee?.str("name"), employee?.str("nameAr")]))
  }

  private func describe(employee: JSONValue) -> SuOwnerInfo {
    SuOwnerInfo(
      kind: .employee, owner: localName(employee), detail: t("Personnel file"), route: .employee(id: employee.rid),
      terms: words([employee.str("name"), employee.str("nameAr"), employee.str("jobTitle"), employee.str("number")]))
  }

  private func describe(letter: JSONValue) -> SuOwnerInfo {
    let person = one.record(.employees, letter.str("employeeId"))
    let name = person.map { localName($0) } ?? ""
    return SuOwnerInfo(
      kind: .letter, owner: name.isEmpty ? t("Letter") : name, detail: suJoin([t("Letter"), letter.str("number")]),
      route: .employee(id: letter.str("employeeId")), date: letter.text("issuedOn"),
      terms: words([person?.str("name"), person?.str("nameAr"), letter.str("subject"), letter.str("number")]))
  }

  /// A customer's clearance certificate.
  private func certificate(_ ownerId: String) -> SuOwnerInfo? {
    for client in one.records(.clients) {
      guard let held = client.list("clearanceCertificates").first(where: { $0.rid == ownerId }) else { continue }
      return SuOwnerInfo(
        kind: .certificate,
        owner: "\(t("Clearance certificate")) \(held.str("number"))".trimmingCharacters(in: .whitespaces),
        detail: localName(client), route: .contact(.customer, id: client.rid), date: held.text("issueDate"),
        terms: words([client.str("name"), client.str("nameAr"), held.str("number")]))
    }
    return nil
  }
}

/// `/files`: every file of the company, by what it is kept with, with a search.
struct SuFilesPage: View {
  @Environment(AppModel.self) private var model
  @State private var kind = ""
  @State private var query = ""
  @State private var limit = 100

  var body: some View {
    let role = SuRole(model)
    let on = model.one.company?["fileFinder"]?.bool == true
    WebPage(spacing: 16, refresh: { [model] in await model.one.sync() }) {
      if suLoading(model, empty: model.one.company == nil) {
        PageHeader(t("Files")).padding(.bottom, -16)
        SuLoadingCard()
      } else if !on {
        PageHeader(t("Files")).padding(.bottom, -16)
        finderOff(canSwitch: role.seesPeople && !role.readOnly)
      } else {
        PageHeader(
          t("Files"),
          description: t(
            "Every file kept with the company’s records: scanned bills, receipts, register papers and personnel files."
          )
        )
        .padding(.bottom, -24)
        if !role.seesPeople {
          SuNote(text: t("Employees’ files and confidential papers aren’t included in what you see."))
        }
        SuFileFinder(
          files: SuFileIndex(one: model.one, people: role.seesPeople).entries, kind: $kind, query: $query,
          limit: $limit)
      }
    }
  }

  private func finderOff(canSwitch: Bool) -> some View {
    Card {
      WebEmptyState(
        icon: .fileSearch, title: t("Finding files and papers is off"),
        description: canSwitch
          ? t(
            "Switch it on to list every file of the company here, and to find files, papers, expenses, fixed assets and security cheques in search."
          )
          : t("Ask the owner of the company to switch it on in Compliance → Settings.")
      ) {
        if canSwitch && SwAccess.can(.companies, .activities) {
          WebButton(t("Switch on"), size: .md) {
            Task {
              await SwSave.run(model, done: t("Finding files and papers switched on")) { ctx in
                SwCompliance.setFileFinder(ctx, on: true)
              }
            }
          }
        }
      }
    }
  }
}

private struct SuFileFinder: View {
  let files: [SuFileEntry]
  @Binding var kind: String
  @Binding var query: String
  @Binding var limit: Int
  @Environment(AppModel.self) private var model

  var body: some View {
    let kinds = SuFileKind.allCases.filter { option in files.contains(where: { $0.kind == option }) }
    let shownKind = kinds.contains(where: { $0.rawValue == kind }) ? kind : ""
    let filtered = files.filter { matches($0, kind: shownKind) }
    if files.isEmpty {
      Card {
        WebEmptyState(
          icon: .fileSearch, title: t("No files yet"),
          description: t("Files attached to bills, expenses, fixed assets, register papers and employees show here."))
      }
    } else {
      ListCard {
        Select(selection: $kind, options: options(kinds))
        TextInput(text: $query, placeholder: t("Search files…"), leadingIcon: .search)
      } rows: {
        if filtered.isEmpty {
          SuNoMatch(t("No files match."))
        } else {
          ForEach(filtered.prefix(limit)) { file in
            SuFileRow(file: file)
          }
          if filtered.count > limit {
            ListShowMore(remaining: filtered.count - limit) { limit += 100 }
          }
        }
        ListCardFooter {
          Text(tp(filtered.count, "{count} file", "{count} files"))
        }
      }
      .onChange(of: kind) { _, _ in limit = 100 }
      .onChange(of: query) { _, _ in limit = 100 }
    }
  }

  private func options(_ kinds: [SuFileKind]) -> [SelectOption<String>] {
    [SelectOption("", t("Every file"))] + kinds.map { SelectOption($0.rawValue, t($0.label)) }
  }

  private func matches(_ file: SuFileEntry, kind: String) -> Bool {
    guard kind.isEmpty || file.kind.rawValue == kind else { return false }
    return ([file.name, file.owner, file.detail] + file.terms).joined(separator: " ").matches(query)
  }
}

/// A file: its format, its name, what it is kept with, its date and size;
/// "In the cloud" until it is on this iPhone. Opens what it is kept with.
private struct SuFileRow: View {
  let file: SuFileEntry
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    SuRow(action: action) {
      HStack(spacing: 12) {
        icon
        VStack(alignment: .leading, spacing: 2) {
          Text(file.name)
            .font(.web(14, .medium))
            .foregroundStyle(palette.slate(900))
            .lineLimit(1)
          Text(suJoin([file.owner, file.detail]))
            .font(.web(12))
            .foregroundStyle(palette.slate(500))
            .lineLimit(1)
          Text(suJoin([model.one.format.date(file.date), SuFileSize.text(file.size), t(file.kind.label)]))
            .font(.web(12, tabular: true))
            .foregroundStyle(palette.slate(500))
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if file.inCloud {
          HStack(spacing: 4) {
            IconView(.cloudDownload, size: 12)
            Text(t("In the cloud"))
          }
          .font(.web(12, .medium))
          .foregroundStyle(palette.slate(700))
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(palette.slate(200), in: Capsule())
          .fixedSize()
        }
      }
    }
  }

  /// Opens what the file is kept with, when it has a page.
  private var action: (() -> Void)? {
    guard let route = file.route else { return nil }
    return { router.push(route) }
  }

  private var symbol: Icon {
    switch file.format {
    case .pdf: .fileText
    case .image: .imageIcon
    case .other: .file
    }
  }

  private var icon: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.sm, style: .continuous)
    let pdf = file.format == .pdf
    return IconView(symbol, size: 16)
      .foregroundStyle(pdf ? palette[.red(600)] : palette.slate(500))
      .frame(width: 36, height: 36)
      .background(pdf ? palette[.red(50)] : palette.slate(100), in: shape)
      .accessibilityHidden(true)
  }
}

/// "12 KB", "3.4 MB" (`formatBytes`).
enum SuFileSize {
  static func text(_ bytes: Double) -> String {
    guard bytes > 0 else { return "" }
    if bytes < 1024 { return "\(Int(bytes)) B" }
    let units = ["KB", "MB", "GB"]
    var value = bytes / 1024
    var unit = 0
    while value >= 1024 && unit < units.count - 1 {
      value /= 1024
      unit += 1
    }
    let digits = value < 10 ? String(format: "%.1f", value) : String(format: "%.0f", value)
    return "\(digits) \(units[unit])"
  }
}
