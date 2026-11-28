import Foundation

/// The port of the company record's settings as the web saves them
/// (src/db/records.ts `saveCompany`; the settings pages' changes:
/// src/features/company/taxes.ts `withTaxes`, settings/app-layout.tsx
/// `withAppLayout`, src/features/ai/availability.ts `withAiSwitch`,
/// src/pdf/template-resolve.ts `withTypeDesign`/`withSameAsInvoices`,
/// src/features/company/company-types.ts `withTidyProfile`) and of the tax
/// rates (`saveTaxRate`, `deleteTaxRate`). The company is put whole; the
/// sync engine sends the fields that changed (CompanyPatch).
public enum SwCompany {
  /// `saveCompany(company)`: stored with the moment it changed.
  @discardableResult
  public static func save(_ ctx: WriteContext, _ company: JSONValue) -> JSONValue {
    var fields = SwField.fields(company)
    fields["updatedAt"] = .string(ctx.stamp)
    ctx.put("companies", .object(fields))
    return .object(fields)
  }

  // MARK: The settings pages' changes

  /// `withTaxes(company, enabled)`: taxes switched on or off, and the editor defaults to match.
  public static func withTaxes(_ company: JSONValue, enabled: Bool) -> JSONValue {
    var fields = SwField.fields(company)
    var defaults = WebJS.spread(fields["defaults"])
    if enabled {
      defaults["lineTaxes"] = .bool(WebJS.truthy(defaults["lineTaxes"]) || !WebJS.truthy(defaults["documentTaxes"]))
    } else {
      defaults["lineTaxes"] = false
      defaults["documentTaxes"] = false
    }
    fields["taxesEnabled"] = .bool(enabled)
    fields["defaults"] = .object(defaults)
    return .object(fields)
  }

  /// `taxesEnabled(company, rateCount)`.
  public static func taxesEnabled(_ company: JSONValue?, rates: Int) -> Bool {
    if let set = company?["taxesEnabled"], !set.isNull { return WebJS.truthy(set) }
    return rates > 0
  }

  /// `withAppLayout(company, split)`: Sales, Books and Inventory as their own apps, or one.
  public static func withAppLayout(_ company: JSONValue, split: Bool) -> JSONValue {
    var fields = SwField.fields(company)
    fields.removeValue(forKey: "appLayout")
    if split { fields["appLayout"] = "split" }
    return .object(fields)
  }

  /// `withAiSwitch(company, on)`: off is as before the switch existed (no `ai`).
  public static func withAiSwitch(_ company: JSONValue, on: Bool) -> JSONValue {
    var fields = SwField.fields(company)
    var others = WebJS.spread(fields["ai"])
    others.removeValue(forKey: "on")
    fields.removeValue(forKey: "ai")
    if on {
      others["on"] = true
      fields["ai"] = .object(others)
    } else if !others.isEmpty {
      fields["ai"] = .object(others)
    }
    return .object(fields)
  }

  /// `withTypeDesign(company, type, { templateId })`: the template a type of document prints with.
  public static func withTemplate(_ company: JSONValue, type: String, templateId: String) -> JSONValue {
    var fields = SwField.fields(company)
    var branding = WebJS.spread(fields["branding"])
    if type == "invoice" {
      branding["templateId"] = .string(templateId)
      fields["branding"] = .object(branding)
      return .object(fields)
    }
    var byType = WebJS.spread(branding["byType"])
    var own = WebJS.object(byType[type]) ?? companyDesign(branding)
    own["templateId"] = .string(templateId)
    byType[type] = .object(own)
    branding["byType"] = .object(byType)
    fields["branding"] = .object(branding)
    return .object(fields)
  }

  /// `companyDesign(branding)`: a type's own design, starting as a copy of the company's.
  static func companyDesign(_ branding: [String: JSONValue]) -> [String: JSONValue] {
    [
      "templateId": branding["templateId"] ?? .null, "accentColor": branding["accentColor"] ?? .null,
      "layout": .object(WebJS.spread(WebJS.present(branding["layout"]))),
    ]
  }

  /// `withSameAsInvoices(company, type, same)`: quotes or credit notes
  /// printed like invoices again, or with a design of their own.
  public static func withSameAsInvoices(_ company: JSONValue, type: String, same: Bool) -> JSONValue {
    var fields = SwField.fields(company)
    var branding = WebJS.spread(fields["branding"])
    let byType = WebJS.present(branding["byType"])
    if !same {
      if let own = byType?[type], WebJS.truthy(own) { return company }
      var types = WebJS.spread(byType)
      types[type] = .object(companyDesign(branding))
      branding["byType"] = .object(types)
      fields["branding"] = .object(branding)
      return .object(fields)
    }
    var rest = WebJS.spread(byType)
    rest.removeValue(forKey: type)
    branding.removeValue(forKey: "byType")
    if !rest.isEmpty { branding["byType"] = .object(rest) }
    fields["branding"] = .object(branding)
    return .object(fields)
  }

  // MARK: The company's type and legal form

  /// `COMPANY_TYPES`: offered on every device, in this order.
  public static let builtInTypes: [JSONValue] = [
    ["id": "security", "name": "Security services", "nameAr": "الخدمات الأمنية"],
    ["id": "manpower", "name": "Manpower supply", "nameAr": "توريد العمالة"],
    ["id": "cleaning", "name": "Cleaning services", "nameAr": "خدمات التنظيف"],
    ["id": "trading", "name": "General trading", "nameAr": "التجارة العامة"],
    ["id": "contracting", "name": "Contracting", "nameAr": "المقاولات"],
  ]

  static func builtIn(_ id: String) -> JSONValue? {
    builtInTypes.first { $0["id"] == .string(id) }
  }

  /// `tidy` of company-types.ts: text trimmed with single spaces, "" for anything else.
  static func tidyName(_ value: JSONValue?) -> String {
    guard case .some(.string(let text)) = value else { return "" }
    return SwText.tidy(text)
  }

  /// `normalizeCompanyType(type)`: names trimmed, or nil when it has no name.
  public static func normalizeType(_ type: JSONValue?) -> JSONValue? {
    guard case .some(.object(let fields)) = type else { return nil }
    let nameAr = tidyName(fields["nameAr"])
    let typed = tidyName(fields["name"])
    let name = typed.isEmpty ? nameAr : typed
    if name.isEmpty { return nil }
    let ownId = tidyName(fields["id"])
    let id = ownId.isEmpty ? stableId("company-type:\(SwText.normalizeSearch(name))") : ownId
    var out: [String: JSONValue] = ["id": .string(id), "name": .string(name)]
    if !nameAr.isEmpty { out["nameAr"] = .string(nameAr) }
    return .object(out)
  }

  /// `companyTypeOptions(companies)`: the built-in types, then those the given companies use, once each.
  public static func typeOptions(_ companies: [JSONValue]) -> [JSONValue] {
    var used: [String: JSONValue] = [:]
    var order: [String] = []
    for company in companies {
      guard let type = normalizeType(company["companyType"]), let id = type["id"]?.string, builtIn(id) == nil else {
        continue
      }
      if let before = used[id] {
        if (before["nameAr"]?.string ?? "").isEmpty && !(type["nameAr"]?.string ?? "").isEmpty { used[id] = type }
      } else {
        used[id] = type
        order.append(id)
      }
    }
    let others = order.compactMap { used[$0] }.sorted {
      ($0["name"]?.string ?? "").localizedCompare($1["name"]?.string ?? "") == .orderedAscending
    }
    return builtInTypes + others
  }

  /// `resolveCompanyType(type, known)`: the type to save, a known type typed again being that type.
  public static func resolveType(_ type: JSONValue?, known: [JSONValue]) -> JSONValue? {
    guard let tidied = normalizeType(type), let tidiedId = tidied["id"]?.string else { return nil }
    if let fixed = builtIn(tidiedId) { return fixed }
    if known.contains(where: { $0["id"] == .string(tidiedId) }) { return tidied }
    func names(_ value: JSONValue?) -> [String] {
      [tidyName(value?["name"]), tidyName(value?["nameAr"])].map(SwText.normalizeSearch).filter { !$0.isEmpty }
    }
    let typed = names(type)
    if let same = known.first(where: { candidate in typed.allSatisfy { names(candidate).contains($0) } }) {
      return normalizeType(same) ?? tidied
    }
    let english = SwText.normalizeSearch(tidyName(type?["name"]))
    let nameAr = tidyName(type?["nameAr"])
    if !english.isEmpty && !nameAr.isEmpty,
      let renamed = known.first(where: { SwText.normalizeSearch(tidyName($0["name"])) == english })
    {
      if let own = builtIn(renamed["id"]?.string ?? "") { return own }
      let fields: [String: JSONValue] = [
        "id": renamed["id"] ?? .null, "name": .string(tidyName(renamed["name"])), "nameAr": .string(nameAr),
      ]
      return .object(fields)
    }
    return tidied
  }

  /// `withTidyProfile(company, known)`: the company as the profile form
  /// saves it, its type resolved (left out when empty) and the description
  /// of the legal form kept only, trimmed, while the legal form is Other.
  public static func withTidyProfile(_ company: JSONValue, known: [JSONValue]) -> JSONValue {
    var fields = SwField.fields(company)
    if let type = resolveType(fields["companyType"], known: known) {
      fields["companyType"] = type
    } else {
      fields.removeValue(forKey: "companyType")
    }
    if let kuwaitValue = fields["kuwait"], WebJS.truthy(kuwaitValue) {
      var kuwait = WebJS.spread(kuwaitValue)
      let other = kuwait["legalFormOther"]
      kuwait.removeValue(forKey: "legalFormOther")
      let described = kuwait["legalForm"] == .string("other") ? tidyName(other) : ""
      if !described.isEmpty { kuwait["legalFormOther"] = .string(described) }
      fields["kuwait"] = .object(kuwait)
    }
    return .object(fields)
  }

  // MARK: Tax rates

  /// `saveTaxRate(rate)`: its name trimmed, stored with the moment it changed.
  @discardableResult
  public static func saveTaxRate(_ ctx: WriteContext, _ rate: JSONValue) -> JSONValue {
    var fields = SwField.fields(rate)
    fields["name"] = .string(SwText.trim(fields["name"]?.string))
    fields["updatedAt"] = .string(ctx.stamp)
    ctx.put("taxRates", .object(fields))
    return .object(fields)
  }

  /// Settings → Taxes → Add rate: `saveTaxRate(createTaxRate(companyId, { name, rate: 0, kind: 'zero' }))`.
  @discardableResult
  public static func addTaxRate(_ ctx: WriteContext, name: String) -> JSONValue {
    let stamp = ctx.stamp
    let rate: JSONValue = [
      "id": .string(ctx.newId()), "companyId": .string(ctx.companyId), "name": .string(name), "rate": 0,
      "archived": false, "createdAt": .string(stamp), "updatedAt": .string(stamp), "kind": "zero",
    ]
    return saveTaxRate(ctx, rate)
  }

  /// `deleteTaxRate(id)`: existing documents keep their own copy of the rate;
  /// the company's defaults and the items forget it.
  public static func deleteTaxRate(_ ctx: WriteContext, id: String) {
    guard let rate = ctx.get("taxRates", id)?.object else { return }
    ctx.delete("taxRates", id)
    let companyId = SwField.text(rate, "companyId")
    if var company = ctx.get("companies", companyId)?.object,
      let ids = company["defaults"]?["defaultTaxRateIds"]?.array, ids.contains(.string(id))
    {
      var defaults = WebJS.spread(company["defaults"])
      defaults["defaultTaxRateIds"] = .array(ids.filter { $0 != .string(id) })
      company["defaults"] = .object(defaults)
      ctx.put("companies", .object(company))
    }
    for product in ctx.all("products") where product["companyId"] == .string(companyId) {
      guard var fields = product.object, let ids = fields["taxRateIds"]?.array, ids.contains(.string(id)) else {
        continue
      }
      fields["taxRateIds"] = .array(ids.filter { $0 != .string(id) })
      ctx.put("products", .object(fields))
    }
  }
}
