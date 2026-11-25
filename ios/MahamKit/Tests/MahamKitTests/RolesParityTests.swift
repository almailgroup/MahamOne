import Foundation
import Testing

@testable import MahamKit

/// The guards of src/cloud/roles.ts over every pair of the samples the web's
/// SQL parity tests use (super-admin-sql, approvals-sql, cheque-approvals-sql,
/// payroll-approval-roles, letter-roles, warehouse-issues-sql) and more,
/// against what the web's TypeScript answers for the same (WebFixtures). The
/// samples are built here as the web's tests build them; their hash is
/// checked against the web's copy first, so both run the same inputs.
@Suite("Roles, as the web answers")
struct RolesParityTests {
  // MARK: The company record

  static func rule(_ extra: [String: JSONValue?] = [:]) -> JSONValue {
    (["pattern": "INV-{counter}", "next": 1, "padding": 4, "reset": "never"] as JSONValue).with(extra)
  }

  static let books: [JSONValue] = {
    let base: JSONValue = [
      "id": "c", "name": "Acme", "numbering": ["invoice": rule(), "employee": rule(["pattern": "E"])],
      "accounting": ["lockDate": nil, "template": "kuwait"], "payment": ["bankDetails": "NBK"],
    ]
    return [
      base,
      base.with(["name": "Changed"]),
      base.with(["holidays": [["date": "2026-02-25"]]]),
      base.with(["accounting": ["lockDate": "2026-12-31", "template": "kuwait"]]),
      base.with(["accounting": ["template": "kuwait"]]),
      base.with(["accounting": nil]),
      base.with(["accounting": .null]),
      base.with(["payment": ["bankDetails": "KFH"]]),
      base.with(["defaults": ["numberOnIssue": true]]),
      base.with(["taxesEnabled": true]),
      base.with(["numbering": ["invoice": rule(["next": 9, "period": "2026"]), "employee": rule()]]),
      base.with(["numbering": ["invoice": rule(["pattern": "X"]), "employee": rule(["pattern": "E"])]]),
      base.with(["numbering": ["invoice": rule(), "employee": rule(["pattern": "EMP"])]]),
      base.with(["numbering": ["invoice": rule(), "employee": rule(), "journal": rule(["pattern": "MJ"])]]),
      base.with(["numbering": ["invoice": "odd"]]),
      base.with(["numbering": .null]),
      base.with(["kuwait": ["licenceNumber": "L-1", "wamdPhone": ""]]),
      base.with(["kuwait": ["licenceNumber": "L-2"]]),
      base.with(["kuwait": ["licenceNumber": "L-1", "wamdPhone": nil]]),
      base.with(["kuwait": ["licenceNumber": "L-1", "wamdPhone": "+965 9871 2046"]]),
      base.with(["kuwait": ["wamdPhone": "+965 9999 9999"]]),
      base.with(["kuwait": ["wamdPhone": 99_999_999]]),
      base.with(["kuwait": "odd"]),
      base.with(["kuwait": ["+965 9999 9999"]]),
      base.with(["kuwait": .null]),
      base.with(["bankAccount": ["bank": "NBOK", "iban": "KW00"]]),
      base.with(["bankAccount": ["bank": "NBOK", "iban": "KW99"]]),
      base.with(["emailTemplates": ["invoice": ["subject": "Invoice", "body": "Pay at {paymentLink}"]]]),
      base.with(["emailTemplates": ["invoice": ["subject": "Invoice", "body": "Pay elsewhere"]]]),
      base.with(["labels": ["invoice": "Bill"]]),
      base.with(["numbering": ["x"]]),
      base.with(["numbering": ["invoice": nil, "employee": rule()]]),
    ]
  }()

  @Test("see the books' settings change, and staff change only counters, as the web does")
  func companyRecord() {
    #expect(webHash(.array(Self.books)) == WebFixtures["booksSamples"].string)
    let changed = WebFixtures["booksChanged"].chars
    let staff = WebFixtures["staffCompanyOk"].chars
    var i = 0
    for before in Self.books {
      for after in Self.books {
        #expect(Roles.companyBooksChanged(before, after) == (changed[i] == "1"), "books \(i)")
        #expect(Roles.staffCompanyChangeOk(before, after) == (staff[i] == "1"), "staff \(i)")
        i += 1
      }
    }
    #expect(i == changed.count)
  }

  // MARK: Documents

  static func invoice(_ id: String, _ extra: [String: JSONValue?] = [:]) -> JSONValue {
    let base: JSONValue = [
      "id": .string(id), "companyId": "c", "type": "invoice", "number": .string("INV-\(id)"), "status": "sent",
      "clientId": "cl-1", "issueDate": "2026-10-01", "dueDate": "2026-10-31", "poNumber": "", "currency": "KWD",
      "items": [
        [
          "id": "line-1", "kind": "item", "productId": nil, "name": "Guarding, October", "description": "",
          "quantity": 2, "unit": "", "unitPrice": 150, "discount": 0, "discountType": "percent", "taxes": [],
        ]
      ],
      "discount": 0, "discountType": "percent", "taxes": [], "charges": [], "pricesIncludeTax": false, "deposit": 0,
      "depositDueDate": nil, "notes": "", "terms": "Payment within 30 days.", "footer": "", "privateNotes": "",
      "templateId": nil,
      "totals": ["subtotal": 300, "discount": 0, "taxTotal": 0, "total": 300, "paid": 0, "balance": 300],
      "sentAt": "2026-10-01T08:00:00.000Z", "paidAt": nil, "sourceId": nil, "convertedToId": nil, "recurringId": nil,
      "archived": false, "createdAt": "2026-10-01T08:00:00.000Z", "updatedAt": "2026-10-01T08:00:00.000Z",
    ]
    return base.with(extra)
  }

  static let docs: [JSONValue?] = {
    let inv = invoice("inv-1")
    let line = inv["items"]?[0] ?? .null
    let totals = inv["totals"] ?? .null
    let link = { (url: JSONValue) -> JSONValue in ["provider": "tap", "url": url, "expiresAt": nil] }
    return [
      nil,
      inv,
      inv.with(["items": [line.with(["unitPrice": 120])]]),
      inv.with(["clientId": "cl-2"]),
      inv.with(["status": "void"]),
      inv.with(["status": "draft"]),
      inv.with(["status": "paid", "totals": totals.with(["paid": 300, "balance": 0]), "paidAt": "2026-10-05"]),
      inv.with(["privateNotes": "internal", "posting": ["taxExempt": false]]),
      inv.with(["paymentLink": link("https://pay.example.com/a")]),
      inv.with(["paymentLink": link("https://pay.example.com/b")]),
      inv.with(["paymentLink": .null]),
      inv.with(["type": "credit", "number": "CN-1"]),
      inv.with(["type": "quote", "number": "QUO-1"]),
      inv.with(["number": "", "status": "sent"]),
      inv.with(["number": "  ", "status": "draft"]),
      inv.with(["type": "credit", "number": "", "status": "void"]),
      inv.with(["items": [line.with(["sku": .null, "nameAr": "حراسة"])]]),
      inv.with(["notes": .null]),
      [:],
    ]
  }()

  static let ruleSets: [JSONValue?] = [
    nil,
    [:],
    ["documentTypes": ["invoice", "credit"], "voidInsteadOfDelete": true, "expireDays": 14],
    ["documentTypes": ["invoice"]],
    ["documentTypes": "invoice"],
    ["documentTypes": ["quote"], "voidInsteadOfDelete": false],
  ]

  @Test("decide what changes of issued documents need an approver, as the web does")
  func documents() {
    #expect(webHash(.array(Self.docs.map { $0 ?? .null })) == WebFixtures["docSamples"].string)
    #expect(webHash(.array(Self.ruleSets.map { $0 ?? .null })) == webHash(WebFixtures["ruleSets"]))
    let expected = WebFixtures["docBits"].chars
    var i = 0
    for rules in Self.ruleSets {
      for before in Self.docs {
        for after in Self.docs {
          let label = "rules \(webHash(rules)) case \(i / 3)"
          #expect(Roles.documentChangeNeedsApproval(rules, before, after) == (expected[i] == "1"), "\(label)")
          #expect(Roles.paymentLinkNeedsApprover(rules, before, after) == (expected[i + 1] == "1"), "\(label)")
          let kept = after.map { WebJS.json(Roles.keepPaymentLink(rules, before, $0)) != WebJS.json($0) } ?? false
          #expect(kept == (expected[i + 2] == "1"), "\(label)")
          if kept, let after {
            // The stored link stays; nothing else changes.
            #expect(Roles.keepPaymentLink(rules, before, after) == after.with(["paymentLink": before?["paymentLink"]]))
          }
          i += 3
        }
      }
    }
    #expect(i == expected.count)
  }

  @Test("keep documents and requests from being deleted, as the web does")
  func deleting() {
    let expected = WebFixtures["deleteCodes"].chars
    func code(_ keeper: Roles.DeleteKeeper?) -> Character {
      keeper.map { Character(String($0.rawValue.prefix(1))) } ?? "-"
    }
    var i = 0
    for rules in Self.ruleSets {
      for doc in Self.docs {
        for table in ["documents", "approvals", "payments"] {
          #expect(code(Roles.deleteKeptBy(rules, table, doc, approver: true)) == expected[i], "\(i)")
          #expect(code(Roles.deleteKeptBy(rules, table, doc, approver: false)) == expected[i + 1], "\(i)")
          #expect(Roles.rulesKeepRecord(rules, table, doc) == (expected[i + 2] == "1"), "\(i)")
          i += 3
        }
      }
    }
    #expect(i == expected.count)
  }

  @Test("refuse issuing without a number while numbers come on issue, as the web does")
  func numberOnIssue() {
    let companies = WebFixtures["companies"].array ?? []
    let expected = WebFixtures["numberBits"].chars
    var i = 0
    for company in companies {
      for before in Self.docs {
        for after in Self.docs {
          #expect(Roles.issuesWithoutNumber(company, before, after) == (expected[i] == "1"), "\(i)")
          i += 1
        }
      }
    }
    #expect(i == expected.count)
  }

  @Test("read what a document says, as the web does")
  func invoiceContent() {
    let expected = WebFixtures["invoiceContent"].strings
    for (doc, want) in zip(Self.docs, expected) { #expect(webHash(Roles.invoiceContent(doc)) == want) }
    #expect(Roles.invoiceContent(Self.invoice("inv-1")) == WebFixtures["invoiceContentBase"])
  }

  // MARK: Cheques

  static let cb: JSONValue = [
    "id": "p-1", "companyId": "c", "direction": "out", "clientId": "vendor-1", "number": "PAYM-p-1",
    "date": "2026-10-05", "amount": 250, "currency": "KWD", "accountId": "acc-2150", "method": "cheque",
    "reference": "000101", "notes": "", "allocations": [["documentId": "bill-1", "amount": 250]],
    "documentIds": ["bill-1"], "creditId": nil,
    "cheque": [
      "number": "000101", "bank": "BRGN", "date": "2026-10-20", "drawer": "Made-up Supplies Co.", "status": "held",
    ],
    "postingRules": 2, "createdAt": "2026-10-05T08:00:00.000Z", "updatedAt": "2026-10-05T08:00:00.000Z",
  ]

  static func chequeWith(_ details: [String: JSONValue?], _ extra: [String: JSONValue?] = [:]) -> JSONValue {
    var fields = extra
    fields["cheque"] = (cb["cheque"] ?? .null).with(details)
    return cb.with(fields)
  }

  static func security(_ id: String, _ extra: [String: JSONValue?] = [:]) -> JSONValue {
    let base: JSONValue = [
      "id": .string(id), "companyId": "c", "direction": "out", "clientId": nil, "number": "000555", "bank": "KFHO",
      "date": nil, "amount": 1000, "currency": "KWD", "drawer": "Made-up Landlord", "purpose": "Rent deposit, office 4",
      "notes": "", "status": "held", "returnedOn": nil, "cashedOn": nil, "paymentId": nil,
      "createdAt": "2026-10-05T08:00:00.000Z", "updatedAt": "2026-10-05T08:00:00.000Z",
    ]
    return base.with(extra)
  }

  static let chequePairs: [(JSONValue?, JSONValue?)] = {
    let cb = Self.cb
    let leaf: JSONValue = ["number": "000101", "at": "2026-10-06T09:00:00.000Z", "reason": "Jammed"]
    let edits: [JSONValue] = [
      cb.with(["amount": 2500]), cb.with(["currency": "USD", "exchangeRate": 0.307]), cb.with(["exchangeRate": 2]),
      cb.with(["date": "2026-09-01"]), cb.with(["clientId": "vendor-2"]), chequeWith(["drawer": "Someone Else"]),
      chequeWith(["number": "000999"]), chequeWith(["bank": "NBOK"]), chequeWith(["date": "2026-12-31"]),
      chequeWith(["drawerCivilId": "290010112345"]), cb.with(["direction": "in"]),
      cb.with(["method": "bank_transfer", "cheque": .null]), cb.with(["accountId": "acc-petty-cash"]),
    ]
    let life: [JSONValue] = [
      cb.with(["notes": "Handed to the courier"]), cb.with(["allocations": [], "documentIds": []]),
      chequeWith([
        "status": "cleared", "clearedOn": "2026-10-21", "bankAccountId": "acc-bank", "clearingJournalId": "jr-1",
      ]),
      chequeWith(
        ["status": "returned", "returnedOn": "2026-10-22"],
        ["voided": true, "voidReason": "Insufficient funds", "voidedOn": "2026-10-22"]),
      chequeWith(["status": "cancelled"], ["voided": true, "voidReason": "Given back", "voidedOn": "2026-10-22"]),
      chequeWith([
        "printedAt": "2026-10-06T09:00:00.000Z", "printCount": 1, "printedLayoutId": "preset-BRGN", "crossed": true,
      ]),
      chequeWith(["number": "000102", "printCount": 1, "spoiledLeaves": [leaf]], ["reference": "000102"]),
      chequeWith(["number": "000102", "spoiledLeaves": [["number": " 000101 "]]], ["reference": "000102"]),
      chequeWith(["number": "000102", "spoiledLeaves": [["number": 101]]], ["reference": "000102"]),
      chequeWith(["number": "000102", "spoiledLeaves": ["000101", nil, ["number": nil]]], ["reference": "000102"]),
      cb.with(["postingRules": 3, "updatedAt": "2026-10-07T08:00:00.000Z"]), cb.with(["exchangeRate": 1]),
      chequeWith(["drawerCivilId": ""]),
    ]
    var pairs: [(JSONValue?, JSONValue?)] = edits.map { (cb, $0) } + life.map { (cb, $0) }
    pairs += [
      (nil, cb), (cb, nil), (cb.with(["accountId": .null]), cb), (cb.with(["accountId": nil]), cb),
      (cb.with(["accountId": ""]), cb), (cb, cb.with(["accountId": .null])), (nil, cb.with(["direction": "in"])),
      (nil, cb.with(["method": "bank_transfer", "cheque": .null])),
      (chequeWith(["number": 101]), chequeWith(["number": "000102", "spoiledLeaves": [["number": "101"]]])),
      (cb.with(["direction": "in"]), cb.with(["direction": "in", "amount": 1])),
      (cb.with(["cheque": []]), cb.with(["cheque": []])),
    ]
    return pairs
  }()

  static let securityPairs: [(JSONValue?, JSONValue?)] = {
    let given = security("s-1")
    return [
      (nil, given), (given, given.with(["amount": 1])), (given, given.with(["status": "returned"])),
      (nil, given.with(["direction": "in"])), (given, nil), (given, given.with(["drawerCivilId": ""])),
      (given.with(["drawerCivilId": ""]), given.with(["drawerCivilId": "290"])),
    ]
  }()

  static func pairsJSON(_ pairs: [(JSONValue?, JSONValue?)]) -> JSONValue {
    .array(pairs.map { .array([$0.0 ?? .null, $0.1 ?? .null]) })
  }

  @Test("decide which cheques wait for an approver, as the web does")
  func cheques() {
    #expect(webHash(Self.pairsJSON(Self.chequePairs)) == WebFixtures["chequePairs"].string)
    #expect(webHash(Self.pairsJSON(Self.securityPairs)) == WebFixtures["securityPairs"].string)
    let rules = WebFixtures["chequeRules"].array ?? []
    let expected = WebFixtures["chequeBits"].chars
    var i = 0
    for rule in rules {
      let ruled: JSONValue? = rule.isNull ? nil : rule
      for (n, (before, after)) in Self.chequePairs.enumerated() {
        #expect(
          Roles.chequeChangeNeedsApprover(ruled, "payments", before, after) == (expected[i] == "1"),
          "\(webHash(rule)) pair \(n)")
        i += 1
      }
      for (n, (before, after)) in Self.securityPairs.enumerated() {
        #expect(
          Roles.chequeChangeNeedsApprover(ruled, "securityCheques", before, after) == (expected[i] == "1"),
          "\(webHash(rule)) security \(n)")
        i += 1
      }
      #expect(Roles.chequeChangeNeedsApprover(ruled, "documents", Self.cb, nil) == (expected[i] == "1"))
      i += 1
    }
    #expect(i == expected.count)
  }

  @Test("read what a cheque says, as the web does")
  func chequeContent() {
    let cb = Self.cb
    let samples: [JSONValue?] = [
      cb, cb.with(["exchangeRate": 1]), cb.with(["exchangeRate": .null, "direction": nil]),
      Self.chequeWith(["drawerCivilId": ""]), cb.with(["cheque": .null, "method": "cash"]),
      cb.with(["accountId": .null]),
      [:],
    ]
    for (sample, want) in zip(samples, WebFixtures["chequeContent"].strings) {
      #expect(webHash(Roles.chequeContent(sample)) == want)
    }
    let securities: [JSONValue?] = [Self.security("s-1"), Self.security("s-2", ["drawerCivilId": ""]), [:]]
    for (sample, want) in zip(securities, WebFixtures["securityContent"].strings) {
      #expect(webHash(Roles.securityChequeContent(sample)) == want)
    }
  }

  // MARK: Approval requests

  static func asked(_ id: String, _ extra: [String: JSONValue?], payroll: Bool) -> JSONValue {
    let base: JSONValue = [
      "id": .string(id), "companyId": "c", "kind": payroll ? "payroll" : "invoice_void",
      "subjectTbl": payroll ? "payRuns" : "documents", "subjectId": "inv-1", "subjectNumber": "INV-1",
      "before": ["status": "sent"], "after": ["status": "void"], "reason": "Entered twice.", "status": "pending",
      "requestedBy": "requester", "requestedByName": "Made-up Staff", "requestedAt": "2026-10-02T08:00:00.000Z",
      "decidedBy": nil, "decidedAt": nil, "decisionNote": "", "createdAt": "2026-10-02T08:00:00.000Z",
      "updatedAt": "2026-10-02T08:00:00.000Z",
    ]
    return base.with(extra)
  }

  static let afters: [[String: JSONValue?]] = [
    ["expired": true, "resultId": "pay-x", "extra": "x"],
    ["status": "cancelled", "resultId": "pay-x", "note": "x"],
    ["status": "cancelled", "expired": true],
    ["status": "approved", "decisionNote": "Fine.", "resultId": "pay-x"],
    ["status": "applied", "resultId": "pay-1", "expired": true],
    ["status": "rejected", "decisionNote": "No."],
    ["status": "pending", "decidedBy": "requester"],
    ["status": "maybe"],
    ["requestedBy": "owner", "after": ["status": "draft"], "decidedBy": "owner"],
    ["status": 5],
    ["status": .null, "updatedAt": "2026-10-03T08:00:00.000Z"],
  ]

  @Test("store and refuse approval requests as the web does, salary approval on or off")
  func approvals() {
    let now = "2026-10-22T08:00:00.000Z"
    let users: [(String, Bool, Bool)] = [
      ("owner", true, true), ("deputy", true, false), ("accountant", false, false), ("requester", false, false),
    ]
    let staff = Roles.ApprovalWriter(userId: "requester", approver: false, owner: false, now: now)
    let owner = Roles.ApprovalWriter(userId: "owner", approver: true, owner: true, now: now)
    func answer(_ write: Roles.ApprovalWrite) -> String {
      switch write {
      case .data(let data): webHash(data)
      case .refused(let why): why.rawValue
      }
    }
    let expected = WebFixtures["approvals"].strings
    var i = 0
    for payrollKind in [false, true] {
      let switches: [Roles.PayrollSwitch?] =
        payrollKind
        ? [
          Roles.PayrollSwitch(on: true, poster: true), Roles.PayrollSwitch(on: true, poster: false),
          Roles.PayrollSwitch(on: false, poster: true), nil,
        ] : [nil]
      for payroll in switches {
        for (user, approver, isOwner) in users {
          let who = Roles.ApprovalWriter(userId: user, approver: approver, owner: isOwner, now: now)
          var n = 0
          for start in ["pending", "approved", "applied", "rejected"] {
            for change in Self.afters {
              n += 1
              let id = "g-\(n)"
              var before: JSONValue? = nil
              if case .data(let first) = Roles.guardApprovalWrite(
                nil, Self.asked(id, [:], payroll: payrollKind), who: staff, payroll: payroll)
              {
                before = first
              }
              if start != "pending", let stored = before {
                let decided = Roles.guardApprovalWrite(
                  stored, Self.asked(id, ["status": .string(start)], payroll: payrollKind), who: owner, payroll: payroll
                )
                if case .data(let data) = decided { before = data }
              }
              var extra: [String: JSONValue?] = ["status": before?["status"]]
              for (key, value) in change { extra[key] = value }
              let data = Self.asked(id, extra, payroll: payrollKind)
              let got = webHash(before) + answer(Roles.guardApprovalWrite(before, data, who: who, payroll: payroll))
              #expect(got == expected[i], "payroll \(payrollKind) \(String(describing: payroll)) \(user) \(start) \(n)")
              i += 1
            }
          }
          for status in ["pending", "approved", "applied", "cancelled", nil] as [String?] {
            n += 1
            let data = Self.asked(
              "g-\(n)",
              [
                "status": status.map(JSONValue.string), "decidedBy": "owner", "decidedAt": "2026-10-02T09:00:00.000Z",
                "resultId": "pay-x", "expired": true,
              ], payroll: payrollKind)
            let got = answer(Roles.guardApprovalWrite(nil, data, who: who, payroll: payroll))
            #expect(got == expected[i], "payroll \(payrollKind) \(user) new \(status ?? "none")")
            i += 1
          }
        }
      }
    }
    #expect(i == expected.count)
  }

  @Test("refuse decisions on pay runs as the web does")
  func payrollDecisions() {
    let req: JSONValue = [
      "id": "req-1", "kind": "payroll", "subjectTbl": "payRuns", "subjectId": "run-1", "status": "pending",
      "requestedBy": "deputy", "after": ["runUpdatedAt": "2026-10-20T08:00:00.000Z"],
    ]
    let run: JSONValue = ["id": "run-1", "updatedAt": "2026-10-20T08:00:00.000Z"]
    let befores: [JSONValue?] = [
      nil, req, req.with(["requestedBy": "boss"]), req.with(["status": "approved"]), req.with(["status": "rejected"]),
      req.with(["status": nil]), req.with(["requestedBy": "shut"]), req.with(["after": "x"]), req.with(["status": 7]),
    ]
    let statuses: [JSONValue?] = [nil, "pending", "approved", "rejected", "cancelled", "applied", "odd", .null]
    let whos: [(String, Bool, Bool?)] = [
      ("deputy", false, nil), ("boss", true, nil), ("other", false, nil), ("shut", false, true), ("shut", true, true),
      ("deputy", false, true),
    ]
    let runs: [JSONValue?] = [run, run.with(["updatedAt": "2026-10-21T08:00:00.000Z"]), nil, ["id": "run-1"]]
    let samples: JSONValue = [
      .array(befores.map { $0 ?? .null }),
      .array(statuses.map { $0 ?? "__missing__" }),
      .array(
        whos.map { who in
          var fields: [String: JSONValue] = ["userId": .string(who.0), "owner": .bool(who.1)]
          if let shut = who.2 { fields["peopleShut"] = .bool(shut) }
          return .object(fields)
        }),
      .array(runs.map { $0 ?? .null }),
    ]
    #expect(webHash(samples) == WebFixtures["payrollSamples"].string)
    let expected = WebFixtures["payrollCodes"].chars
    let codes: [Roles.PayrollRefusal: Character] = [.selfApproval: "S", .stale: "t", .people: "p"]
    var i = 0
    for before in befores {
      for status in statuses {
        for who in whos {
          for r in runs {
            let after = (before ?? req).with(["status": status])
            let refusal = Roles.payrollDecisionRefusal(
              before, after, userId: who.0, owner: who.1, peopleShut: who.2 ?? false, run: r)
            #expect((refusal.flatMap { codes[$0] } ?? "-") == expected[i], "\(i)")
            i += 1
          }
        }
      }
    }
    #expect(i == expected.count)
  }

  // MARK: Letters

  @Test("guard and keep letters as the web does")
  func letters() {
    let draft: JSONValue = ["id": "let-1", "status": "draft", "number": "", "body": "Text"]
    let issued = draft.with(["status": "issued", "number": "HR-2026-0001", "body": "Done"])
    let letters: [JSONValue?] = [
      nil, draft, draft.with(["body": "Other"]), issued, issued.with(["body": "Other"]),
      issued.with(["status": "void", "voidReason": "Wrong", "voidedOn": "2026-10-21"]),
      issued.with(["printedAt": "2026-10-22T08:00:00.000Z", "updatedAt": "u"]),
      issued.with(["printedAt": "2026-10-22T09:00:00.000Z"]), issued.with(["number": "HR-2026-0002"]),
      issued.with(["status": nil]), issued.with(["status": .null]),
      issued.with(["status": "void", "voidReason": "Other", "voidedOn": .null, "updatedAt": .null]), ["id": "let-2"],
      issued.with(["printedAt": 5]),
    ]
    #expect(webHash(.array(letters.map { $0 ?? .null })) == WebFixtures["letters"].string)
    let codes = WebFixtures["letterCodes"].chars
    let keeps = WebFixtures["letterKeeps"].strings
    var i = 0
    var k = 0
    for before in letters {
      for after in letters {
        for issuer in [false, true] {
          let refusal = Roles.letterWriteRefusal(before, after, issuer: issuer)
          let code: Character = refusal == nil ? "-" : refusal == .issued ? "d" : "r"
          #expect(code == codes[i], "\(i)")
          i += 1
        }
        if let after {
          #expect(webHash(Roles.keepIssuedLetter(before, after)) == keeps[k], "keep \(k)")
          k += 1
        }
      }
    }
    #expect(i == codes.count)
    #expect(k == keeps.count)
    for (letter, want) in zip(letters, WebFixtures["letterContent"].strings) {
      #expect(webHash(Roles.letterContent(letter)) == want)
    }
    let kept = WebFixtures["letterKept"].chars
    for (letter, want) in zip(letters, kept) { #expect(Roles.letterKept(letter) == (want == "1")) }
  }

  // MARK: Warehouses

  @Test("guard warehouses, sub-warehouses and items issued as the web does")
  func warehouses() {
    let keeper: JSONValue = ["userId": "keeper", "name": " Made-up Keeper ", "jobTitle": "Storekeeper"]
    let order = ["main", "sub", "subOld", "subNoKeeper", "kept", "odd"]
    let warehouses: [String: JSONValue] = [
      "main": ["id": "main", "name": "Main"],
      "sub": ["id": "sub", "name": "Van 1", "parentId": "main", "keeper": keeper],
      "subOld": ["id": "subOld", "parentId": "main", "keeper": keeper, "archived": true],
      "subNoKeeper": ["id": "subNoKeeper", "parentId": "main"],
      "kept": ["id": "kept", "keeper": ["userId": "keeper", "name": "Made-up Keeper", "jobTitle": ""]],
      "odd": ["id": "odd", "parentId": "", "keeper": nil],
    ]
    let find: Roles.WarehouseLookup = { warehouses[$0] }
    let members: [Roles.WarehouseWriter] = [
      .init(role: .owner, userId: "boss", approver: true), .init(role: .admin, userId: "admin", approver: false),
      .init(role: .accountant, userId: "acc", approver: true), .init(role: .staff, userId: "keeper", approver: false),
      .init(role: .staff, userId: "other", approver: false), .init(role: .viewer, userId: "keeper", approver: false),
      .init(role: nil, userId: nil, approver: false), .init(role: .staff, userId: "", approver: true),
    ]
    func doc(_ lines: [JSONValue], _ extra: [String: JSONValue?] = [:]) -> JSONValue {
      (["id": "d", "type": "invoice", "status": "sent", "items": .array(lines)] as JSONValue).with(extra)
    }
    func line(_ id: String, _ warehouseId: JSONValue, _ quantity: JSONValue = 1) -> JSONValue {
      ["id": .string(id), "productId": "p-1", "warehouseId": warehouseId, "quantity": quantity]
    }
    let rows: [(String, [JSONValue?])] = [
      ("warehouses", [nil] + order.map { warehouses[$0] } + [["id": "main", "name": "Renamed"]]),
      (
        "stockEntries",
        [
          nil, ["id": "e", "warehouseId": "main"], ["id": "e", "warehouseId": "sub"],
          ["id": "e", "warehouseId": "main", "toWarehouseId": "sub"], ["id": "e", "warehouseId": "nowhere"],
          ["id": "e", "toWarehouseId": "kept"],
        ]
      ),
      ("stockIssues", [nil, ["id": "i", "warehouseId": "sub"]]),
      (
        "documents",
        [
          nil, doc([line("l1", "main")]), doc([line("l1", "sub")]), doc([line("l1", "sub", 2)]),
          doc([line("l2", "sub"), line("l1", "sub")]), doc([line("l1", "sub"), line("l2", "sub")]),
          doc([line("l1", "sub")], ["status": "void"]), doc([line("l1", "sub")], ["type": "bill"]),
          doc([line("l1", "sub", .null)]), doc([line("l1", "subOld", 1.5)]), doc([]), ["id": "d"],
          doc([line("é", "sub"), line("e", "sub"), line("𝄞", "sub"), line("\u{ffff}", "sub")]),
        ]
      ),
      (
        "approvals",
        [
          nil, ["id": "a", "kind": "stock_issue", "after": ["warehouseId": "sub"]],
          ["id": "a", "kind": "stock_issue", "after": ["warehouseId": "subOld"]],
          ["id": "a", "kind": "stock_issue", "after": ["warehouseId": "main"]],
          ["id": "a", "kind": "stock_issue", "after": ["warehouseId": "kept"]],
          ["id": "a", "kind": "invoice_void", "after": [:]], ["id": "a", "kind": "stock_issue"],
        ]
      ),
      ("clients", [nil, ["id": "c"]]),
    ]
    let samples: JSONValue = [
      .object(warehouses),
      .array(
        members.map { m in
          [
            "role": m.role.map { .string($0.rawValue) } ?? .null, "userId": m.userId.map(JSONValue.string) ?? .null,
            "approver": .bool(m.approver),
          ]
        }),
      .array(rows.map { .array([.string($0.0), .array($0.1.map { $0 ?? .null })]) }),
    ]
    #expect(webHash(samples) == WebFixtures["warehouseSamples"].string)
    let expected = WebFixtures["warehouseCodes"].chars
    var i = 0
    for member in members {
      for (table, samples) in rows {
        for before in samples {
          for after in samples {
            let refusal = Roles.warehouseWriteRefusal(member, table, before, after, warehouses: find)
            let code: Character = refusal.map { Character(String($0.rawValue.prefix(1))) } ?? "-"
            #expect(code == expected[i], "\(String(describing: member.role)) \(table) \(i)")
            i += 1
          }
        }
      }
    }
    #expect(i == expected.count)
    let documents = rows.first { $0.0 == "documents" }?.1 ?? []
    for (document, want) in zip(documents, WebFixtures["subWarehouseLines"].strings) {
      #expect(Roles.subWarehouseLines(document, find) == want)
    }
    var issuers = (WebFixtures["issuers"].array ?? [])[...]
    for member in members {
      for id in order {
        guard let want = issuers.popFirst() else { break }
        #expect(Roles.issuesFromWarehouse(member.role, userId: member.userId, find(id)) == want[3]?.bool, "\(id)")
        #expect(Roles.issuerName(userId: member.userId, find(id)) == want[4]?.string, "\(id)")
      }
    }
    #expect(issuers.isEmpty)
  }

  // MARK: Writing, limits and apps

  @Test("decide who writes what, the owner's limits and each record's app, as the web does")
  func writesAndLimits() {
    let perms: [JSONValue?] = [
      nil, ["apps": ["books": "view", "compliance": "none", "people": "edit"]], ["apps": ["people": "view"]],
      ["apps": ["books": "none", "crm": "view"]],
    ]
    let tables = [
      "companies", "clients", "documents", "journals", "employees", "payRuns", "complianceDocuments", "renewals",
      "vehicles", "attachments", "activities", "approvals", "stockIssues", "later",
    ]
    let records: [JSONValue] = [
      [:], ["kind": "payroll"], ["kind": "transfer"], ["employeeId": "emp-1"], ["employeeId": ""],
      ["ownerId": "emp-1"], ["ownerId": "inv-1"], ["ownerId": "veh-1"], ["ownerId": "nobody"],
    ]
    let owners: [String: [String: JSONValue]] = [
      "employees": ["emp-1": ["id": "emp-1"]], "documents": ["inv-1": ["id": "inv-1"]],
      "vehicles": ["veh-1": ["id": "veh-1"]],
    ]
    let samples: JSONValue = [
      .array(perms.map { $0 ?? .null }), .array(tables.map(JSONValue.string)), .array(records),
      .object(owners.mapValues { .object($0) }),
    ]
    #expect(webHash(samples) == WebFixtures["limitSamples"].string)
    let lookup: Roles.RecordLookup = { owners[$0]?[$1] }

    let appCodes = WebFixtures["appCodes"].chars
    func app(_ value: Roles.CoreApp?) -> Character {
      guard let value else { return "-" }
      return value == .compliance ? "C" : Character(String(value.rawValue.prefix(1)))
    }
    var i = 0
    for table in tables {
      for record in records {
        #expect(app(Roles.recordApp(table, record, lookup: lookup)) == appCodes[i], "\(table) \(record)")
        #expect(app(Roles.recordApp(table, record)) == appCodes[i + 1], "\(table) \(record)")
        i += 2
      }
    }
    #expect(i == appCodes.count)

    let roles: [MemberRole?] = [.owner, .admin, .accountant, .staff, .viewer, nil]
    let limitBits = WebFixtures["limitBits"].chars
    i = 0
    for role in roles {
      for perm in perms {
        let permissions = perm.map(Roles.readPermissions)
        for table in tables {
          for record in records {
            #expect(
              Roles.limitBlocksWrite(role, permissions, table, record, lookup: lookup) == (limitBits[i] == "1"), "\(i)")
            i += 1
          }
        }
        #expect(Roles.hasLimits(role, permissions) == (limitBits[i] == "1"))
        #expect(Roles.canPostPayroll(role, permissions) == (limitBits[i + 1] == "1"))
        i += 2
      }
    }
    #expect(i == limitBits.count)

    let writeBits = WebFixtures["writeBits"].chars
    i = 0
    for role in roles {
      for table in tables {
        for record in records {
          #expect(
            canWrite(role, table, record, lookup) == (writeBits[i] == "1"),
            "\(String(describing: role)) \(table) \(record)")
          i += 1
        }
      }
    }
    #expect(i == writeBits.count)
  }
}
