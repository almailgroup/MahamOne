import Foundation

// Employee letters (#19): the ports of src/db/letters.ts (the switch,
// templates, drafts, issuing, voiding, printing, asking an approver and the
// drafts an employee's save makes), src/lib/hr/letters.ts (the fields and
// how a letter is filled) and src/lib/hr/letter-templates.ts (the default
// wording).

public enum PwLetters {
  public static let kinds = [
    "salary_certificate", "experience_certificate", "employment_certificate", "warning", "noc", "salary_transfer", "custom",
  ]
  public static let defaultKinds = ["salary_certificate", "experience_certificate", "employment_certificate", "warning", "noc"]
  public static let triggers = ["joining", "leaving", "salary_change"]
  static let maxAutoDrafts = 5

  struct Wording {
    let name: String
    let nameAr: String
    let subjectEn: String
    let subjectAr: String
    let bodyEn: String
    let bodyAr: String
  }

  /// `DEFAULT_WORDING`: the wording a company starts with for each kind (src/lib/hr/letter-templates.ts).
  static let wording: [String: Wording] = [
    "salary_certificate": Wording(
      name: "Salary certificate", nameAr: "شهادة راتب", subjectEn: "Salary certificate", subjectAr: "شهادة راتب",
      bodyEn: [
        "{letter.addressee}",
        "",
        "This is to certify that the holder of this certificate is employed by {company.name} as follows:",
        "",
        "Name: {employee.name}",
        "Nationality: {employee.nationality}",
        "Job title: {employee.jobTitle}",
        "Department: {employee.department}",
        "Date of joining: {employee.hireDate}",
        "Total monthly salary: {salary.total}",
        "({salary.totalWords})",
        "",
        "This certificate is issued at the employee’s request, without any liability on the company.",
      ].joined(separator: "\n"),
      bodyAr: [
        "{letter.addressee}",
        "",
        "تشهد {company.name} بأن صاحب هذه الشهادة يعمل لديها وفق البيانات التالية:",
        "",
        "الاسم: {employee.name}",
        "الجنسية: {employee.nationality}",
        "المسمى الوظيفي: {employee.jobTitle}",
        "القسم: {employee.department}",
        "تاريخ التعيين: {employee.hireDate}",
        "الراتب الشهري الإجمالي: {salary.total}",
        "({salary.totalWords})",
        "",
        "وقد أُعطيت هذه الشهادة بناءً على طلبه دون أدنى مسؤولية على الشركة.",
      ].joined(separator: "\n")),
    "experience_certificate": Wording(
      name: "Experience certificate", nameAr: "شهادة خبرة", subjectEn: "Experience certificate", subjectAr: "شهادة خبرة",
      bodyEn: [
        "{letter.addressee}",
        "",
        "This is to certify that the holder of this certificate worked for {company.name} as follows:",
        "",
        "Name: {employee.name}",
        "Nationality: {employee.nationality}",
        "Job title: {employee.jobTitle}",
        "Department: {employee.department}",
        "Period of service: from {employee.hireDate} to {service.end} ({service.length})",
        "",
        "This certificate is issued at the employee’s request, without any liability on the company. We wish them every success.",
      ].joined(separator: "\n"),
      bodyAr: [
        "{letter.addressee}",
        "",
        "تشهد {company.name} بأن صاحب هذه الشهادة عمل لديها وفق البيانات التالية:",
        "",
        "الاسم: {employee.name}",
        "الجنسية: {employee.nationality}",
        "المسمى الوظيفي: {employee.jobTitle}",
        "القسم: {employee.department}",
        "مدة الخدمة: من {employee.hireDate} إلى {service.end} ({service.length})",
        "",
        "وقد أُعطيت هذه الشهادة بناءً على طلبه دون أدنى مسؤولية على الشركة، مع تمنياتنا له بالتوفيق.",
      ].joined(separator: "\n")),
    "employment_certificate": Wording(
      name: "Employment certificate", nameAr: "شهادة عمل", subjectEn: "Employment certificate", subjectAr: "شهادة عمل",
      bodyEn: [
        "{letter.addressee}",
        "",
        "This is to certify that the holder of this certificate is employed by {company.name} to date as follows:",
        "",
        "Name: {employee.name}",
        "Employee number: {employee.number}",
        "Nationality: {employee.nationality}",
        "Job title: {employee.jobTitle}",
        "Department: {employee.department}",
        "Date of joining: {employee.hireDate}",
        "",
        "This certificate is issued at the employee’s request, without any liability on the company.",
      ].joined(separator: "\n"),
      bodyAr: [
        "{letter.addressee}",
        "",
        "تشهد {company.name} بأن صاحب هذه الشهادة يعمل لديها حتى تاريخه وفق البيانات التالية:",
        "",
        "الاسم: {employee.name}",
        "الرقم الوظيفي: {employee.number}",
        "الجنسية: {employee.nationality}",
        "المسمى الوظيفي: {employee.jobTitle}",
        "القسم: {employee.department}",
        "تاريخ التعيين: {employee.hireDate}",
        "",
        "وقد أُعطيت هذه الشهادة بناءً على طلبه دون أدنى مسؤولية على الشركة.",
      ].joined(separator: "\n")),
    "warning": Wording(
      name: "Warning letter", nameAr: "خطاب إنذار", subjectEn: "Warning", subjectAr: "إنذار",
      bodyEn: [
        "To: {employee.name}",
        "Employee number: {employee.number}",
        "Job title: {employee.jobTitle}",
        "Department: {employee.department}",
        "",
        "The following was noted: {letter.purpose}",
        "",
        "This breaches the company’s work rules, and this letter is a formal warning. Please follow the work rules from now on: repeating the breach may lead to the penalties set out in the Private Sector Labour Law and the company’s penalties regulation.",
        "",
        "Please sign below to confirm that you received this letter.",
        "",
        "Employee’s signature: ____________",
        "Date received: ____________",
      ].joined(separator: "\n"),
      bodyAr: [
        "إلى: {employee.name}",
        "الرقم الوظيفي: {employee.number}",
        "المسمى الوظيفي: {employee.jobTitle}",
        "القسم: {employee.department}",
        "",
        "لوحظ ما يلي: {letter.purpose}",
        "",
        "ويُعد ذلك مخالفة لأنظمة العمل لدى الشركة، لذا نوجّه إليكم هذا الإنذار. نرجو الالتزام بأنظمة العمل مستقبلاً، علماً بأن تكرار المخالفة قد يعرّضكم للجزاءات المنصوص عليها في قانون العمل في القطاع الأهلي ولائحة الجزاءات لدى الشركة.",
        "",
        "يرجى التوقيع بما يفيد الاستلام.",
        "",
        "توقيع الموظف: ____________",
        "تاريخ الاستلام: ____________",
      ].joined(separator: "\n")),
    "noc": Wording(
      name: "No objection certificate", nameAr: "شهادة عدم ممانعة", subjectEn: "No objection certificate", subjectAr: "شهادة عدم ممانعة",
      bodyEn: [
        "{letter.addressee}",
        "",
        "{company.name} has no objection to {letter.purpose} for the holder of this certificate, whose details are:",
        "",
        "Name: {employee.name}",
        "Nationality: {employee.nationality}",
        "Job title: {employee.jobTitle}",
        "Date of joining: {employee.hireDate}",
        "",
        "This certificate is issued at the employee’s request, without any liability on the company.",
      ].joined(separator: "\n"),
      bodyAr: [
        "{letter.addressee}",
        "",
        "تفيد {company.name} بأنه لا مانع لديها من {letter.purpose} لصاحب هذه الشهادة، وبياناته كالتالي:",
        "",
        "الاسم: {employee.name}",
        "الجنسية: {employee.nationality}",
        "المسمى الوظيفي: {employee.jobTitle}",
        "تاريخ التعيين: {employee.hireDate}",
        "",
        "وقد أُعطيت هذه الشهادة بناءً على طلبه دون أدنى مسؤولية على الشركة.",
      ].joined(separator: "\n")),
    "salary_transfer": Wording(
      name: "Salary transfer letter", nameAr: "خطاب تحويل راتب", subjectEn: "Salary transfer", subjectAr: "تحويل راتب",
      bodyEn: [
        "{letter.addressee}",
        "",
        "{company.name} confirms that the holder of this letter has been employed as {employee.jobTitle} since {employee.hireDate}, with a total monthly salary of {salary.total} ({salary.totalWords}).",
        "",
        "The company will transfer the monthly salary to the employee’s account with you.",
      ].joined(separator: "\n"),
      bodyAr: [
        "{letter.addressee}",
        "",
        "تفيد {company.name} بأن صاحب هذا الخطاب يعمل لديها بوظيفة {employee.jobTitle} منذ {employee.hireDate}، ويتقاضى راتباً شهرياً إجمالياً قدره {salary.total} ({salary.totalWords}).",
        "",
        "وستحوّل الشركة راتبه الشهري إلى حسابه لديكم.",
      ].joined(separator: "\n")),
    "custom": Wording(
      name: "Letter", nameAr: "خطاب", subjectEn: "", subjectAr: "",
      bodyEn: [
        "{letter.addressee}",
        "",
      ].joined(separator: "\n"),
      bodyAr: [
        "{letter.addressee}",
        "",
      ].joined(separator: "\n")),
  ]

  // MARK: Who and when

  /// `lettersAvailable(link)`: on this device, or once the server has letters.
  public static func available(_ link: PwLink?) -> Bool { PwLink.has(link, "employee_letters") }

  /// `lettersInEffect(settings, link)`.
  public static func inEffect(_ settings: JSONValue?, _ link: PwLink?) -> Bool {
    available(link) && Roles.lettersSwitchedOn(settings)
  }

  /// `canDraftLetters(link)`.
  public static func canDraft(_ link: PwLink?) -> Bool {
    guard let link else { return true }
    return !link.removed && link.mayWrite("employeeLetters")
  }

  /// `canIssueLetters(link)`.
  public static func canIssue(_ link: PwLink?) -> Bool {
    Roles.issuesLetters(link?.role, link?.approver) && canDraft(link)
  }

  /// `asksToIssue(link)`: an accountant who isn't an approver.
  public static func asksToIssue(_ link: PwLink?) -> Bool { link != nil && canDraft(link) && !canIssue(link) }

  /// `setLettersOn(companyId, on)`: the owner or an admin.
  @discardableResult
  public static func setOn(_ ctx: WriteContext, _ on: Bool, link: PwLink?) throws -> JSONValue {
    if let link, !Roles.switchesLetters(link.role) {
      throw pwFail("Only the owner or an admin turns employee letters on or off.")
    }
    if !available(link) {
      throw pwFail("The cloud needs the latest database script first. Ask the owner of the company to run it.")
    }
    if on, let company = ctx.pwCompany, WebJS.present(company["numbering"]?["letter"]) == nil {
      var numbering = WebJS.spread(company["numbering"])
      numbering["letter"] = Numbering.defaultRules()["letter"]?.raw ?? .null
      ctx.put("companies", company.pwWith("numbering", .object(numbering)))
    }
    let before = PwSettings.people(ctx)
    if (before["letters"]?.bool == true) == on { return before }
    let settings = PwSettings.normalizePeople(before.pwWith("letters", .bool(on))).pwWith("updatedAt", .string(ctx.stamp))
    ctx.put("peopleSettings", settings)
    PwLog.add(
      ctx, "payroll", settings.pwId, "settings", on ? "Employee letters turned on" : "Employee letters turned off")
    return settings
  }

  // MARK: Templates

  /// `defaultTemplateId`.
  public static func defaultTemplateId(_ companyId: String, _ kind: String) -> String { "default:\(companyId):\(kind)" }

  /// `defaultTemplateKind`.
  public static func defaultTemplateKind(_ id: String) -> String? {
    guard id.hasPrefix("default:"), let colon = id.lastIndex(of: ":") else { return nil }
    let kind = String(id[id.index(after: colon)...])
    return wording[kind] != nil ? kind : nil
  }

  /// `templateFromWording`.
  static func fromWording(_ companyId: String, _ kind: String, id: String, stamp: String) -> JSONValue {
    let w = wording[kind] ?? wording["custom"]!
    return [
      "id": .string(id), "companyId": .string(companyId), "kind": .string(kind), "name": .string(w.name),
      "nameAr": .string(w.nameAr), "language": "ar", "subjectEn": .string(w.subjectEn),
      "subjectAr": .string(w.subjectAr), "bodyEn": .string(w.bodyEn), "bodyAr": .string(w.bodyAr), "showStamp": true,
      "showSignature": true, "signatoryName": "", "signatoryTitle": "", "archived": false,
      "createdAt": .string(stamp), "updatedAt": .string(stamp),
    ]
  }

  /// `defaultTemplate(companyId, kind)`.
  public static func defaultTemplate(_ companyId: String, _ kind: String) -> JSONValue {
    fromWording(companyId, kind, id: defaultTemplateId(companyId, kind), stamp: "")
  }

  /// `newTemplate(companyId, kind)`: a kind's starting wording, not saved yet.
  public static func newTemplate(companyId: String, kind: String, now: Date = Date()) -> JSONValue {
    fromWording(companyId, kind, id: newId(), stamp: Defaults.nowStamp(now))
  }

  private static func kindOrder(_ kind: String) -> Int { kinds.firstIndex(of: kind) ?? kinds.count }

  /// `sortTemplates`: by kind, then by name.
  public static func sortTemplates(_ list: [JSONValue]) -> [JSONValue] {
    PwSort.stable(list) { a, b in
      let order = kindOrder(a.pwStr("kind")) - kindOrder(b.pwStr("kind"))
      return order != 0 ? order : PwSort.localeCompare(a.pwStr("name"), b.pwStr("name"))
    }
  }

  /// `listTemplates`: those stored, and the defaults as written until changed.
  public static func templates(stored: [JSONValue], companyId: String) -> [JSONValue] {
    let ids = Set(stored.map(\.pwId))
    let defaults = defaultKinds.map { defaultTemplate(companyId, $0) }.filter { !ids.contains($0.pwId) }
    return sortTemplates(stored + defaults)
  }

  /// `getTemplate(companyId, id)`.
  static func findTemplate(_ ctx: WriteContext, _ companyId: String, _ id: String) -> JSONValue? {
    if let stored = ctx.get("letterTemplates", id) { return stored.pwStr("companyId") == companyId ? stored : nil }
    guard let kind = defaultTemplateKind(id), id == defaultTemplateId(companyId, kind) else { return nil }
    return defaultTemplate(companyId, kind)
  }

  /// `tidyLine`: spaces as one, trimmed, at most `max` long.
  static func tidyLine(_ text: String?, _ max: Int = 200) -> String { WebJS.prefix(PwPay.tidy(text ?? ""), max) }

  /// `tidyText`: line ends as \n, trimmed, at most 20,000 long.
  static func tidyText(_ text: String?) -> String {
    let unified = (text ?? "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    return WebJS.prefix(WebJS.trim(unified), 20_000)
  }

  /// `letterLanguage(value)`.
  static func language(_ value: JSONValue?) -> String {
    let text = value?.string
    return text == "en" || text == "ar-en" ? text! : "ar"
  }

  /// `normalizeTemplate`: tidy, with only the kinds, languages and events this version knows.
  public static func normalizeTemplate(_ input: JSONValue) -> JSONValue {
    var autoOn: [String] = []
    for item in input.pwList("autoOn") {
      guard let text = item.string, triggers.contains(text), !autoOn.contains(text) else { continue }
      autoOn.append(text)
    }
    var out = input.pwFields
    out["kind"] = .string(kinds.contains(input.pwStr("kind")) ? input.pwStr("kind") : "custom")
    out["name"] = .string(tidyLine(input.pwText("name")))
    out["nameAr"] = .string(tidyLine(input.pwText("nameAr")))
    out["language"] = .string(language(input["language"]))
    out["subjectEn"] = .string(tidyLine(input.pwText("subjectEn"), 300))
    out["subjectAr"] = .string(tidyLine(input.pwText("subjectAr"), 300))
    out["bodyEn"] = .string(tidyText(input.pwText("bodyEn")))
    out["bodyAr"] = .string(tidyText(input.pwText("bodyAr")))
    out["showStamp"] = .bool(input["showStamp"]?.bool == true)
    out["showSignature"] = .bool(input["showSignature"]?.bool == true)
    out["signatoryName"] = .string(tidyLine(input.pwText("signatoryName")))
    out["signatoryTitle"] = .string(tidyLine(input.pwText("signatoryTitle")))
    out["archived"] = .bool(input["archived"]?.bool == true)
    out["autoOn"] = autoOn.isEmpty ? nil : .array(autoOn.map(JSONValue.string))
    out["privateFields"] = input["privateFields"]?.bool == true ? .bool(true) : nil
    return .object(out)
  }

  private static func checkTemplate(_ template: JSONValue) throws {
    if template.pwStr("name").isEmpty && template.pwStr("nameAr").isEmpty {
      throw pwFail("Give the template a name.")
    }
    let lang = template.pwStr("language")
    if lang != "en" && template.pwStr("bodyAr").isEmpty { throw pwFail("Write the letter’s Arabic text.") }
    if lang != "ar" && template.pwStr("bodyEn").isEmpty { throw pwFail("Write the letter’s English text.") }
  }

  /// `saveTemplate(input)`: only someone who issues letters lets it show private details.
  @discardableResult
  public static func saveTemplate(_ ctx: WriteContext, _ input: JSONValue, link: PwLink?) throws -> JSONValue {
    if !canDraft(link) { throw pwFail("Your role can’t change letter templates.") }
    let companyId = input.pwStr("companyId")
    let stored = ctx.get("letterTemplates", input.pwId) ?? findTemplate(ctx, companyId, input.pwId)
    if let stored, stored.pwStr("companyId") != companyId { throw pwFail("This template could not be found.") }
    let created: JSONValue = {
      if let made = stored?["createdAt"], WebJS.truthy(made) { return made }
      if let made = input["createdAt"], WebJS.truthy(made) { return made }
      return .string(ctx.stamp)
    }()
    var template = normalizeTemplate(input.pwMerging(["createdAt": created, "updatedAt": .string(ctx.stamp)]))
    if !canIssue(link) {
      template.set("privateFields", stored?["privateFields"]?.bool == true ? .bool(true) : nil)
    }
    try checkTemplate(template)
    ctx.put("letterTemplates", template)
    let name = template.pwStr("name").isEmpty ? template.pwStr("nameAr") : template.pwStr("name")
    PwLog.add(
      ctx, "payroll", template.pwId, "letter_template", "Letter template {name} saved", vars: ["name": .text(name)],
      arabic: ["name": template.pwText("nameAr")])
    return template
  }

  /// `setTemplateArchived(companyId, id, archived)`.
  @discardableResult
  public static func setTemplateArchived(_ ctx: WriteContext, id: String, archived: Bool, link: PwLink?) throws
    -> JSONValue
  {
    guard let found = findTemplate(ctx, ctx.companyId, id) else { throw pwFail("This template could not be found.") }
    return try saveTemplate(ctx, found.pwWith("archived", .bool(archived)), link: link)
  }

  /// `restoreDefaultWording(companyId, id)`: a default template's wording put back.
  @discardableResult
  public static func restoreDefaultWording(_ ctx: WriteContext, id: String, link: PwLink?) throws -> JSONValue {
    guard let found = findTemplate(ctx, ctx.companyId, id), let kind = defaultTemplateKind(id) else {
      throw pwFail("This template has no default wording.")
    }
    let w = defaultTemplate(ctx.companyId, kind)
    var fields: [String: JSONValue] = [:]
    for key in ["name", "nameAr", "subjectEn", "subjectAr", "bodyEn", "bodyAr"] { fields[key] = w[key] ?? .null }
    return try saveTemplate(ctx, found.pwMerging(fields), link: link)
  }

  // MARK: Filling a letter

  /// `fieldsIn(text)`: `{group.name}` fields, once each, in order.
  static func fieldsIn(_ text: String) -> [String] {
    var out: [String] = []
    let units = Array(text.unicodeScalars)
    var i = 0
    while i < units.count {
      if units[i] == "{", let (key, end) = field(units, at: i) {
        if !out.contains(key) { out.append(key) }
        i = end
        continue
      }
      i += 1
    }
    return out
  }

  /// `/\{([a-z]+\.[a-zA-Z]+)\}/` at `start`: the key and the index after the brace.
  private static func field(_ s: [Unicode.Scalar], at start: Int) -> (String, Int)? {
    var i = start + 1
    let groupStart = i
    while i < s.count, ("a"..."z").contains(s[i]) { i += 1 }
    guard i > groupStart, i < s.count, s[i] == "." else { return nil }
    i += 1
    let nameStart = i
    while i < s.count, ("a"..."z").contains(s[i]) || ("A"..."Z").contains(s[i]) { i += 1 }
    guard i > nameStart, i < s.count, s[i] == "}" else { return nil }
    var key = String.UnicodeScalarView()
    key.append(contentsOf: s[(start + 1)..<i])
    return (String(key), i + 1)
  }

  /// `fillLetter(text, values)`.
  public static func fill(_ text: String, _ values: [String: String]) -> String {
    let s = Array(text.unicodeScalars)
    var out = String.UnicodeScalarView()
    var i = 0
    while i < s.count {
      if s[i] == "{", let (key, end) = field(s, at: i) {
        if let value = values[key] {
          out.append(contentsOf: value.unicodeScalars)
        } else {
          out.append(contentsOf: s[i..<end])
        }
        i = end
        continue
      }
      out.append(s[i])
      i += 1
    }
    return tidyFilled(String(out))
  }

  /// `.replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim()`.
  private static func tidyFilled(_ text: String) -> String {
    var lines: [Unicode.Scalar] = []
    var pending: [Unicode.Scalar] = []
    for scalar in text.unicodeScalars {
      if scalar == " " || scalar == "\t" {
        pending.append(scalar)
        continue
      }
      if scalar != "\n" { lines += pending }
      pending = []
      lines.append(scalar)
    }
    lines += pending
    var collapsed = String.UnicodeScalarView()
    var newlines = 0
    for scalar in lines {
      if scalar == "\n" {
        newlines += 1
        continue
      }
      if newlines > 0 {
        let keep = newlines >= 3 ? 2 : newlines
        collapsed.append(contentsOf: Array(repeating: "\n" as Unicode.Scalar, count: keep))
        newlines = 0
      }
      collapsed.append(scalar)
    }
    if newlines > 0 {
      collapsed.append(contentsOf: Array(repeating: "\n" as Unicode.Scalar, count: newlines >= 3 ? 2 : newlines))
    }
    return WebJS.trim(String(collapsed))
  }

  /// The marks Intl puts around figures (`BIDI_MARKS`), removed, and trimmed.
  private static func clean(_ text: String) -> String {
    WebJS.trim(
      WebJS.removing(text) { s in
        s.value == 0x200E || s.value == 0x200F || s.value == 0x061C || (0x2066...0x2069).contains(s.value)
      })
  }

  /// `letterPay`: the basic salary and every allowance.
  static func pay(_ employee: JSONValue, _ currency: String) -> (basic: Double, allowances: Double, total: Double) {
    let places = PwM.places(currency)
    let allowances = PwM.round(PwM.total(employee.pwList("allowances").map { $0.pwNum("amount") }), places)
    let basic = PwM.round(employee.pwNum("basicSalary"), places)
    return (basic, allowances, PwM.round(PwM.dec(basic) + PwM.dec(allowances), places))
  }

  /// `serviceLength(months, language)`.
  static func serviceLength(_ months: Int, _ language: String) -> String {
    let whole = max(0, months)
    let years = whole / 12
    let rest = whole % 12
    if language == "ar" {
      let yearsText =
        years == 1 ? "سنة واحدة" : years == 2 ? "سنتان" : (3...10).contains(years) ? "\(years) سنوات" : "\(years) سنة"
      let monthsText =
        rest == 1 ? "شهر واحد" : rest == 2 ? "شهران" : (3...10).contains(rest) ? "\(rest) أشهر" : "\(rest) شهراً"
      if years == 0 && rest == 0 { return "أقل من شهر" }
      if years == 0 { return monthsText }
      if rest == 0 { return yearsText }
      return "\(yearsText) و\(monthsText)"
    }
    let yearsText = years == 1 ? "1 year" : "\(years) years"
    let monthsText = rest == 1 ? "1 month" : "\(rest) months"
    if years == 0 && rest == 0 { return "less than a month" }
    if years == 0 { return monthsText }
    if rest == 0 { return yearsText }
    return "\(yearsText) and \(monthsText)"
  }

  /// `serviceMonths(hireDate, until)`.
  static func serviceMonths(_ hireDate: String?, _ until: String) -> Int {
    guard let hireDate, PwDates.isDate(hireDate), PwDates.isDate(until), !WebJS.less(until, hireDate) else { return 0 }
    return PwDates.differenceInMonths(PwDates.addDays(until, 1), hireDate)
  }

  /// What a letter is filled with (`LetterContext`).
  struct Context {
    var employee: JSONValue
    var company: JSONValue
    var departments: [JSONValue]
    var privateFields: Bool
    var number: String
    var date: String
    var addressee: String
    var purpose: String
  }

  /// `letterValues(ctx, language)`: every field's value in one language.
  static func values(_ c: Context, _ lang: String) -> [String: String] {
    let e = c.employee
    let locale = FormatLocale(lang == "ar" ? "ar-KW-u-nu-latn" : "en-KW")
    let format = Format.DateFormat(c.company.pwText("dateFormat") ?? "dd/MM/yyyy")
    let currency = c.company.pwStr("currency")
    let display = Format.CurrencyDisplay(rawValue: c.company.pwText("currencyDisplay") ?? "local") ?? .local
    func date(_ value: String?) -> String { clean(Format.date(value, format: format, locale: locale)) }
    func money(_ amount: Double) -> String {
      clean(Format.money(amount, currency: currency, locale: locale, display: display))
    }
    let salary = pay(e, currency)
    let leaving = e.pwText("leavingDate")
    let left = e.pwStr("status") == "left" && PwDates.isDate(leaving)
    let until = left ? leaving! : c.date
    let bank = Kuwait.banks.first { $0.code == e.pwStr("bank") } ?? Kuwait.bankFromIban(e.pwStr("iban"))
    let language: Bilingual.Language = lang == "ar" ? .ar : .en
    func secret(_ value: String) -> String { c.privateFields ? value : Format.maskNumber(value) }
    let gender = e.pwStr("gender")
    let title =
      gender == "male" ? (lang == "ar" ? "السيد" : "Mr.") : gender == "female" ? (lang == "ar" ? "السيدة" : "Ms.") : ""
    func localName(_ record: JSONValue) -> String {
      let arabic = WebJS.trim(record.pwStr("nameAr"))
      return lang == "ar" && !arabic.isEmpty ? arabic : record.pwStr("name")
    }
    let jobTitleAr = WebJS.trim(e.pwStr("jobTitleAr"))
    let jobTitle = e.pwStr("jobTitle")
    let department = PwSettings.findDepartment(c.departments, e.pwText("department"))
    let addressee = WebJS.trim(c.addressee)
    return [
      "employee.name": localName(e), "employee.title": title, "employee.number": e.pwStr("number"),
      "employee.jobTitle": lang == "ar"
        ? (jobTitleAr.isEmpty ? jobTitle : jobTitleAr) : (jobTitle.isEmpty ? jobTitleAr : jobTitle),
      "employee.department": department.map(localName) ?? PwPay.tidy(e.pwText("department")),
      "employee.nationality": clean(Geo.countryName(e.pwStr("nationality"), locale: lang)),
      "employee.hireDate": date(e.pwText("hireDate")),
      "employee.leavingDate": left ? date(leaving) : "",
      "service.length": serviceLength(serviceMonths(e.pwText("hireDate"), until), lang),
      "service.end": date(until),
      "salary.basic": money(salary.basic), "salary.allowances": money(salary.allowances),
      "salary.total": money(salary.total),
      "salary.totalWords": Words.amountInWords(salary.total, currency: currency, language: lang == "ar" ? .ar : .en),
      "letter.number": c.number, "letter.date": date(c.date),
      "letter.addressee": addressee.isEmpty ? (lang == "ar" ? "إلى من يهمه الأمر" : "To whom it may concern") : addressee,
      "letter.purpose": WebJS.trim(c.purpose), "company.name": localName(c.company),
      "employee.civilId": secret(e.pwStr("civilId")), "employee.passportNumber": secret(e.pwStr("passportNumber")),
      "employee.bank": bank.map { $0.name[language] } ?? e.pwStr("bank"),
      "employee.iban": secret(Kuwait.formatIban(e.pwStr("iban"))),
      "employee.accountNumber": secret(e.pwStr("accountNumber")),
    ]
  }

  /// `letterTexts(letter, context, on)` for a draft about to be issued: its
  /// texts filled with the employee's record as it is now.
  static func filledTexts(_ letter: JSONValue, _ c: Context) -> [String: JSONValue] {
    let lang = language(letter["language"])
    let main = values(c, lang == "en" ? "en" : "ar")
    var texts: [String: JSONValue] = [
      "subject": .string(fill(letter.pwStr("subject"), main)), "body": .string(fill(letter.pwStr("body"), main)),
    ]
    if lang == "ar-en" {
      let english = values(c, "en")
      texts["subjectEn"] = .string(fill(letter.pwStr("subjectEn"), english))
      texts["bodyEn"] = .string(fill(letter.pwStr("bodyEn"), english))
    }
    return texts
  }

  /// The texts of a draft as it would be printed now (`letterTexts`), for the page.
  public static func preview(_ ctx: WriteContext, letterId: String, link: PwLink?) -> (subject: String, body: String)? {
    guard let letter = ctx.get("employeeLetters", letterId) else { return nil }
    guard letter.pwStr("status") == "draft", let employee = ctx.get("employees", letter.pwStr("employeeId")),
      let company = ctx.pwCompany
    else { return (letter.pwStr("subject"), letter.pwStr("body")) }
    let template = letter.pwText("templateId").flatMap { findTemplate(ctx, ctx.companyId, $0) }
    let settings = PwSettings.people(ctx)
    let c = Context(
      employee: employee, company: company, departments: settings.pwList("departments"),
      privateFields: template?["privateFields"]?.bool == true && canIssue(link), number: letter.pwStr("number"),
      date: letter.pwText("issuedOn") ?? ctx.today, addressee: letter.pwStr("addressee"),
      purpose: letter.pwStr("purpose"))
    let texts = filledTexts(letter, c)
    return (texts["subject"]?.string ?? "", texts["body"]?.string ?? "")
  }

  /// The texts of a draft not saved yet as it would print now
  /// (`useLetterTexts`): filled with the employee's record when there is
  /// one, else as written. `subjectEn`/`bodyEn` only for a letter in both languages.
  public static func previewDraft(_ ctx: WriteContext, _ draft: JSONValue, link: PwLink?) -> [String: String] {
    let lang = language(draft["language"])
    var texts: [String: JSONValue] = ["subject": draft["subject"] ?? "", "body": draft["body"] ?? ""]
    if lang == "ar-en" {
      texts["subjectEn"] = .string(draft.pwStr("subjectEn"))
      texts["bodyEn"] = .string(draft.pwStr("bodyEn"))
    }
    if let employee = ctx.get("employees", draft.pwStr("employeeId")), let company = ctx.pwCompany {
      let template = draft.pwText("templateId").flatMap { findTemplate(ctx, ctx.companyId, $0) }
      let settings = PwSettings.people(ctx)
      let c = Context(
        employee: employee, company: company, departments: settings.pwList("departments"),
        privateFields: template?["privateFields"]?.bool == true && canIssue(link), number: "", date: ctx.today,
        addressee: draft.pwStr("addressee"), purpose: draft.pwStr("purpose"))
      texts = filledTexts(draft, c)
    }
    return texts.compactMapValues(\.string)
  }

  // MARK: Drafts

  /// `templateTexts(template, language)`.
  public static func templateTexts(_ template: JSONValue, _ lang: String) -> [String: JSONValue] {
    switch lang {
    case "en": return ["subject": template["subjectEn"] ?? "", "body": template["bodyEn"] ?? ""]
    case "ar": return ["subject": template["subjectAr"] ?? "", "body": template["bodyAr"] ?? ""]
    default:
      return [
        "subject": template["subjectAr"] ?? "", "body": template["bodyAr"] ?? "",
        "subjectEn": template["subjectEn"] ?? "", "bodyEn": template["bodyEn"] ?? "",
      ]
    }
  }

  /// `draftFromTemplate(template, employeeId, language)`: a draft input, not saved yet.
  public static func draftFromTemplate(_ template: JSONValue, employeeId: String, language: String? = nil) -> JSONValue {
    let lang = self.language(language.map(JSONValue.string) ?? template["language"])
    var fields: [String: JSONValue] = [
      "companyId": template["companyId"] ?? .null, "employeeId": .string(employeeId),
      "templateId": template["id"] ?? .null, "kind": template["kind"] ?? .null, "language": .string(lang),
      "addressee": "", "purpose": "",
    ]
    for (key, value) in templateTexts(template, lang) { fields[key] = value }
    return .object(fields)
  }

  static let purposeNeeded: [String: String] = [
    "warning": "Write what happened. It is printed in the warning letter.",
    "noc": "Write what the company has no objection to. It is printed in the certificate.",
  ]

  /// `missingPurpose(letter)`: a warning letter or certificate that prints its purpose must say it.
  public static func missingPurpose(_ letter: JSONValue) -> String? {
    guard let message = purposeNeeded[letter.pwStr("kind")], WebJS.trim(letter.pwStr("purpose")).isEmpty else {
      return nil
    }
    let text = [letter.pwStr("subject"), letter.pwStr("body"), letter.pwStr("subjectEn"), letter.pwStr("bodyEn")]
      .joined(separator: "\n")
    return fieldsIn(text).contains("letter.purpose") ? message : nil
  }

  /// `pendingLetterRequest(letterId)`.
  public static func pendingRequest(_ ctx: WriteContext, _ letterId: String) -> JSONValue? {
    ctx.all("approvals").first {
      $0.pwStr("subjectId") == letterId && $0.pwStr("status") == "pending" && Roles.isLetterApproval($0)
    }
  }

  /// `draftRecord(input, existing, id)`.
  static func draftRecord(_ ctx: WriteContext, _ input: JSONValue, _ existing: JSONValue?, id: String) -> JSONValue {
    let lang = language(input["language"])
    let stamp = ctx.stamp
    var letter = existing?.pwFields ?? [:]
    let trigger: JSONValue? = existing != nil ? existing?["trigger"] : (WebJS.present(input["trigger"]) ?? .null)
    let fields: [String: JSONValue] = [
      "id": .string(id), "companyId": input["companyId"] ?? .null, "employeeId": input["employeeId"] ?? .null,
      "templateId": input["templateId"] ?? .null,
      "kind": .string(kinds.contains(input.pwStr("kind")) ? input.pwStr("kind") : "custom"), "number": "",
      "language": .string(lang), "addressee": .string(tidyLine(input.pwText("addressee"), 300)),
      "purpose": .string(WebJS.prefix(tidyText(input.pwText("purpose")), 2000)),
      "subject": .string(tidyLine(input.pwText("subject"), 300)), "body": .string(tidyText(input.pwText("body"))),
      "issuedOn": .null, "status": "draft", "createdAt": existing?["createdAt"] ?? .string(stamp),
      "updatedAt": .string(stamp),
    ]
    for (key, value) in fields { letter[key] = value }
    letter["trigger"] = trigger
    letter["subjectEn"] = nil
    letter["bodyEn"] = nil
    if lang == "ar-en" {
      letter["subjectEn"] = .string(tidyLine(input.pwText("subjectEn"), 300))
      letter["bodyEn"] = .string(tidyText(input.pwText("bodyEn")))
    }
    return .object(letter)
  }

  /// `saveLetterDraft(input)`: a draft, new or changed.
  @discardableResult
  public static func saveDraft(_ ctx: WriteContext, _ input: JSONValue, link: PwLink?) throws -> JSONValue {
    let companyId = input.pwStr("companyId")
    let settings = PwSettings.people(ctx, companyId)
    if !inEffect(settings, link) { throw pwFail("Employee letters are off for this company.") }
    if !canDraft(link) { throw pwFail("Your role can’t make letters.") }
    guard let employee = ctx.get("employees", input.pwStr("employeeId")), employee.pwStr("companyId") == companyId else {
      throw pwFail("Choose the employee the letter is for.")
    }
    let given = input.pwText("id").flatMap { $0.isEmpty ? nil : $0 }
    let existing = given.flatMap { ctx.get("employeeLetters", $0) }
    if let existing {
      if existing.pwStr("companyId") != companyId { throw pwFail("This letter could not be found.") }
      if existing.pwStr("status") != "draft" { throw pwFail("This letter is issued, so it can’t be changed.") }
      if pendingRequest(ctx, existing.pwId) != nil {
        throw pwFail("This letter is waiting for approval. Take the request back to change it.")
      }
    }
    let id = existing?.pwId ?? given ?? ctx.newId()
    let letter = draftRecord(ctx, input, existing, id: id)
    if letter.pwStr("body").isEmpty { throw pwFail("Write the letter’s text.") }
    if letter.pwStr("language") == "ar-en" && letter.pwStr("bodyEn").isEmpty {
      throw pwFail("Write the letter’s English text.")
    }
    ctx.put("employeeLetters", letter)
    if existing == nil {
      PwLog.add(
        ctx, "employee", employee.pwId, "letter_draft", "Letter draft made for {name}",
        vars: ["name": .text(employee.pwStr("name"))], arabic: ["name": employee.pwText("nameAr")],
        refs: ActivityRefs(employeeId: employee.pwId))
    }
    return letter
  }

  /// `deleteLetterDraft(id)`.
  public static func deleteDraft(_ ctx: WriteContext, id: String) throws {
    guard let letter = ctx.get("employeeLetters", id) else { return }
    if letter.pwStr("status") != "draft" {
      throw pwFail("Issued letters are kept, so their numbers stay used. Void it instead.")
    }
    if pendingRequest(ctx, id) != nil {
      throw pwFail("This letter is waiting for approval. Take the request back to delete it.")
    }
    ctx.delete("employeeLetters", id)
  }

  // MARK: Issuing

  /// The letter rule and the numbers in use, for the cloud's counter asked before issuing.
  public static func localNumber(_ ctx: WriteContext, letterId: String, on: String) -> (kind: String, min: Int)? {
    guard let company = ctx.pwCompany else { return nil }
    let rule = NumberingRule(
      WebJS.present(company["numbering"]?["letter"]) ?? Numbering.defaultRules()["letter"]?.raw ?? .null)
    let taken = takenNumbers(ctx, letterId)
    let local = Numbering.allocateNumber(rule, on) { taken.contains($0.lowercased()) }
    return ("letter", Int(local.rule.next) - 1)
  }

  private static func takenNumbers(_ ctx: WriteContext, _ exceptId: String) -> Set<String> {
    Set(
      ctx.pwAll("employeeLetters").filter { $0.pwId != exceptId && !$0.pwStr("number").isEmpty }
        .map { $0.pwStr("number").lowercased() })
  }

  /// `issueLetter(id, on)`: numbered, filled with the employee's record and
  /// frozen. `reserved` is the counter the cloud gave, asked before (nil
  /// offline or on this device only).
  @discardableResult
  public static func issue(
    _ ctx: WriteContext, id: String, on: String, reserved: ReservedCounter? = nil, link: PwLink?
  ) throws -> JSONValue {
    if !PwDates.isDate(on) { throw pwFail("Choose the letter’s date.") }
    guard let letter = ctx.get("employeeLetters", id) else { throw pwFail("This letter could not be found.") }
    if letter.pwStr("status") != "draft" { throw pwFail("This letter is already issued.") }
    guard let company = ctx.get("companies", letter.pwStr("companyId")) else { throw pwFail("Company not found") }
    let settings = PwSettings.people(ctx, letter.pwStr("companyId"))
    let found = ctx.get("employees", letter.pwStr("employeeId"))
    if !inEffect(settings, link) { throw pwFail("Employee letters are off for this company.") }
    if !canIssue(link) {
      throw pwFail("Only the owner, an admin or an approver issues letters. Ask for approval instead.")
    }
    guard let employee = found else { throw pwFail("The employee of this letter no longer exists.") }
    if let purpose = missingPurpose(letter) { throw pwFail(purpose) }
    let template = letter.pwText("templateId").flatMap { findTemplate(ctx, letter.pwStr("companyId"), $0) }
    let rule = NumberingRule(
      WebJS.present(company["numbering"]?["letter"]) ?? Numbering.defaultRules()["letter"]?.raw ?? .null)
    let taken = takenNumbers(ctx, letter.pwId)
    let allocated = Numbering.allocateFrom(rule, on, clientNumber: "", reserved: reserved) {
      taken.contains($0.lowercased())
    }
    var numbering = WebJS.spread(company["numbering"])
    numbering["letter"] = allocated.rule.raw
    ctx.put("companies", company.pwWith("numbering", .object(numbering)))
    let c = Context(
      employee: employee, company: company.pwWith("numbering", .object(numbering)),
      departments: settings.pwList("departments"),
      privateFields: template?["privateFields"]?.bool == true && canIssue(link), number: allocated.number, date: on,
      addressee: letter.pwStr("addressee"), purpose: letter.pwStr("purpose"))
    var issued = letter.pwFields
    if language(letter["language"]) == "ar-en" {
      issued["subjectEn"] = .string(letter.pwStr("subjectEn"))
      issued["bodyEn"] = .string(letter.pwStr("bodyEn"))
    }
    for (key, value) in filledTexts(letter, c) { issued[key] = value }
    issued["number"] = .string(allocated.number)
    issued["issuedOn"] = .string(on)
    issued["status"] = "issued"
    issued["signatoryName"] = template?["signatoryName"] ?? ""
    issued["signatoryTitle"] = template?["signatoryTitle"] ?? ""
    if let template {
      issued["showStamp"] = template["showStamp"]
      issued["showSignature"] = template["showSignature"]
    } else {
      issued["showStamp"] = true
      issued["showSignature"] = true
    }
    issued["updatedAt"] = .string(ctx.stamp)
    if language(letter["language"]) != "ar-en" {
      issued["subjectEn"] = nil
      issued["bodyEn"] = nil
    }
    let record = JSONValue.object(issued)
    ctx.put("employeeLetters", record)
    PwLog.add(
      ctx, "employee", employee.pwId, "letter_issued", "Letter {number} issued",
      vars: ["number": .text(allocated.number)], refs: ActivityRefs(employeeId: employee.pwId))
    return record
  }

  /// `voidLetter(id, reason)`: it keeps its number, never given again.
  @discardableResult
  public static func voidLetter(_ ctx: WriteContext, id: String, reason: String, link: PwLink?) throws -> JSONValue {
    let why = WebJS.trim(reason)
    if why.isEmpty { throw pwFail("Say why the letter is void.") }
    guard let letter = ctx.get("employeeLetters", id) else { throw pwFail("This letter could not be found.") }
    if letter.pwStr("status") != "issued" { throw pwFail("Only an issued letter is voided.") }
    if !canIssue(link) { throw pwFail("Only the owner, an admin or an approver voids letters.") }
    let voided = letter.pwMerging([
      "status": "void", "voidReason": .string(WebJS.prefix(why, 1000)), "voidedOn": .string(ctx.today),
      "updatedAt": .string(ctx.stamp),
    ])
    ctx.put("employeeLetters", voided)
    PwLog.add(
      ctx, "employee", letter.pwStr("employeeId"), "letter_void", "Letter {number} voided",
      vars: ["number": .text(letter.pwStr("number"))], refs: ActivityRefs(employeeId: letter.pwStr("employeeId")))
    return voided
  }

  /// `markLettersPrinted(ids)`.
  public static func markPrinted(_ ctx: WriteContext, ids: [String]) {
    for id in ids {
      guard let letter = ctx.get("employeeLetters", id), letter.pwStr("status") == "issued" else { continue }
      ctx.put("employeeLetters", letter.pwMerging(["printedAt": .string(ctx.stamp), "updatedAt": .string(ctx.stamp)]))
    }
  }

  // MARK: Asking an approver

  /// `requestLetterIssue(id, { note, byName })`: an accountant asks an approver to issue a draft.
  @discardableResult
  public static func requestIssue(
    _ ctx: WriteContext, id: String, note: String = "", byName: String = "", link: PwLink?
  ) throws -> JSONValue {
    guard let letter = ctx.get("employeeLetters", id) else { throw pwFail("This letter could not be found.") }
    if letter.pwStr("status") != "draft" { throw pwFail("This letter is already issued.") }
    let settings = PwSettings.people(ctx, letter.pwStr("companyId"))
    let employee = ctx.get("employees", letter.pwStr("employeeId"))
    guard let link, inEffect(settings, link) else { throw pwFail("Employee letters are off for this company.") }
    if !canDraft(link) { throw pwFail("Your role can’t make letters.") }
    if let purpose = missingPurpose(letter) { throw pwFail(purpose) }
    if pendingRequest(ctx, letter.pwId) != nil { throw pwFail("This letter is already waiting for approval.") }
    let now = ctx.stamp
    var fields: [String: JSONValue] = [
      "id": .string(ctx.newId()), "companyId": letter["companyId"] ?? .null, "kind": "letter",
      "subjectTbl": "employeeLetters", "subjectId": .string(letter.pwId),
      "subjectNumber": .string(employee?.pwStr("number") ?? ""), "before": .null,
      "after": [
        "letterUpdatedAt": letter["updatedAt"] ?? .null, "kind": letter["kind"] ?? .null,
        "employeeId": letter["employeeId"] ?? .null,
      ],
      "reason": .string(WebJS.prefix(WebJS.trim(note), 1000)), "status": "pending", "requestedBy": .string(link.userId),
      "requestedAt": .string(now), "decidedBy": .null, "decidedAt": .null, "decisionNote": "",
      "createdAt": .string(now), "updatedAt": .string(now),
    ]
    let name = WebJS.trim(byName)
    if !name.isEmpty { fields["requestedByName"] = .string(WebJS.prefix(name, 200)) }
    let request = JSONValue.object(fields)
    ctx.put("approvals", request)
    let about = letter.pwStr("employeeId")
    PwLog.add(
      ctx, "employee", about.isEmpty ? letter.pwId : about, "approval:asked", "Letter sent for approval",
      refs: ActivityRefs(employeeId: about.isEmpty ? nil : about))
    return request
  }

  // MARK: Automatic drafts

  /// `employeeEvents(before, after, currency)`: joining, leaving, a salary changed.
  static func events(_ before: JSONValue?, _ after: JSONValue, _ currency: String, today: String) -> [(
    trigger: String, date: String
  )] {
    guard let before else {
      return [("joining", WebJS.present(after["hireDate"])?.string ?? today)]
    }
    var out: [(trigger: String, date: String)] = []
    if before.pwStr("status") != "left" && after.pwStr("status") == "left" {
      out.append(("leaving", WebJS.present(after["leavingDate"])?.string ?? today))
    }
    if before.pwStr("status") != "left" && after.pwStr("status") != "left"
      && pay(before, currency).total != pay(after, currency).total
    {
      out.append(("salary_change", today))
    }
    return out
  }

  /// `autoDraftId(templateId, employeeId, trigger, date)`.
  static func autoDraftId(_ templateId: String, _ employeeId: String, _ trigger: String, _ date: String) -> String {
    "auto:" + stableId("\(templateId):\(employeeId):\(trigger):\(date)")
  }

  /// `autoDrafts(before, after)`: the drafts the company's templates ask for when an employee joins,
  /// leaves or has their salary changed, at most five a save. Never issued.
  @discardableResult
  static func autoDrafts(_ ctx: WriteContext, before: JSONValue?, after: JSONValue, link: PwLink?, text: PwText) -> Int {
    let settings = PwSettings.people(ctx, after.pwStr("companyId"))
    guard let company = ctx.get("companies", after.pwStr("companyId")), inEffect(settings, link), canDraft(link) else {
      return 0
    }
    let events = events(before, after, company.pwStr("currency"), today: ctx.today)
    if events.isEmpty { return 0 }
    let templates = ctx.all("letterTemplates").filter {
      $0.pwStr("companyId") == after.pwStr("companyId") && !$0.pwTruthy("archived") && !$0.pwList("autoOn").isEmpty
    }.map(normalizeTemplate)
    var wanted: [(template: JSONValue, trigger: String, date: String)] = []
    for template in sortTemplates(templates) {
      let on = template.pwList("autoOn").compactMap(\.string)
      for event in events where on.contains(event.trigger) { wanted.append((template, event.trigger, event.date)) }
    }
    var made = 0
    for item in wanted.prefix(maxAutoDrafts) {
      let id = autoDraftId(item.template.pwId, after.pwId, item.trigger, item.date)
      if ctx.get("employeeLetters", id) != nil { continue }
      let input = draftFromTemplate(item.template, employeeId: after.pwId).pwWith("trigger", .string(item.trigger))
      let draft = draftRecord(ctx, input, nil, id: id)
      if draft.pwStr("body").isEmpty { continue }
      ctx.put("employeeLetters", draft)
      made += 1
    }
    return made
  }
}
