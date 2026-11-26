#if DEBUG
  // Preview mode's made-up books (see PreviewRecords.swift): part of the
  // chart of accounts the web's Kuwait template creates, a few journals, a
  // fixed asset with its depreciation run, an expense, bank statement lines
  // and a filed VAT return. Every name, number and amount is invented.

  import Foundation
  import MahamKit

  extension PreviewRecords {
    static func accountingArea(company: Company) -> [String: [JSONValue]] {
      let c = company.id
      let today = ISODates.today()
      let thisMonth = AcDate.period(today)
      let lastMonth = AcDate.shiftPeriod(thisMonth, -1)
      let bought = AcDate.shiftPeriod(thisMonth, -2) + "-01"
      let runDate = AcDate.periodEnd(lastMonth)
      let quarter = AcDate.presetRange("last-quarter", today)
      let stamp = "\(day(-120))T08:00:00.000Z"

      let accounts = acChart.map { row in
        acAccount(c, row.code, row.name, row.nameAr, row.type, row.role, stamp: stamp)
      }
      let journals = [
        acJournal(
          "p-ac-jr-1", c, "JNL-0001", day(-120), "Owner investment", status: "posted",
          lines: [("1000", "", 25000, 0), ("3000", "", 0, 25000)]),
        acJournal(
          "p-ac-jr-2", c, "JNL-0002", bought, "Laptops for the office", status: "posted",
          lines: [("1520", "", 2500, 0), ("1000", "", 0, 2500)], kind: "asset_purchase", source: "p-ac-as-1"),
        acJournal(
          "p-ac-jr-3", c, "JNL-0003", runDate, "Depreciation \(lastMonth)", status: "posted",
          lines: [("6900", "Office laptops", 83.333, 0), ("1530", "Office laptops", 0, 83.333)], kind: "depreciation",
          source: "p-ac-dr-1"),
        acJournal(
          "p-ac-jr-4", c, "JNL-0004", day(-15), "Office rent", status: "posted",
          lines: [("6060", "Rent for the month", 450, 0), ("2200", "", 0, 450)]),
        acJournal(
          "p-ac-jr-5", c, "JNL-0005", day(-1), "Bank charges correction", status: "draft",
          lines: [("6170", "", 2.5, 0), ("1000", "", 0, 2.5)]),
      ]
      let asset = rec([
        "id": "p-ac-as-1", "companyId": c, "number": "FA-0001", "name": "Office laptops",
        "nameAr": "أجهزة الحاسب المحمولة", "description": "Three laptops for the sales team",
        "assetAccountId": "p-ac-a-1520", "accumulatedAccountId": "p-ac-a-1530", "expenseAccountId": "p-ac-a-6900",
        "purchaseDate": bought, "depreciationStart": bought, "cost": 2500, "salvageValue": 0,
        "usefulLifeMonths": 60, "method": "straight_line", "decliningRate": NSNull(), "openingDepreciation": 0,
        "openingDepreciationDate": NSNull(), "source": "purchase", "billId": NSNull(), "billLineId": NSNull(),
        "vendorId": NSNull(), "paidFromAccountId": "p-ac-a-1000", "journalId": "p-ac-jr-2", "location": "Head office",
        "custodian": "Sales team", "serialNumber": "SN-44821", "notes": "", "status": "active", "disposal": NSNull(),
        "createdAt": "\(bought)T09:00:00.000Z", "updatedAt": "\(bought)T09:00:00.000Z",
      ])
      let run = rec([
        "id": "p-ac-dr-1", "companyId": c, "period": lastMonth, "date": runDate, "journalId": "p-ac-jr-3",
        "lines": [["assetId": "p-ac-as-1", "amount": 83.333]], "total": 83.333, "reversalJournalId": NSNull(),
        "reversedAt": NSNull(), "createdAt": "\(runDate)T18:00:00.000Z", "updatedAt": "\(runDate)T18:00:00.000Z",
      ])
      let expense = rec([
        "id": "p-ac-ex-1", "companyId": c, "number": "EXP-0012", "date": day(-4), "amount": 35, "currency": "KWD",
        "taxes": [], "description": "Courier to the warehouse", "accountId": "p-ac-a-6210",
        "paidFromAccountId": "p-ac-a-1010", "vendorId": NSNull(), "createdAt": "\(day(-4))T10:00:00.000Z",
        "updatedAt": "\(day(-4))T10:00:00.000Z",
      ])
      let statement = [
        acBankLine("p-ac-bt-1", c, day(-8), "TRANSFER SANDLINE INTERIORS TRX-5521", 400, position: 1, match: "p-pay-1"),
        acBankLine("p-ac-bt-2", c, day(-6), "CHQ 100482 DESERT LOGISTICS", -1210, position: 2, match: "p-pay-3"),
        acBankLine("p-ac-bt-3", c, day(-5), "KNET SETTLEMENT 0419", 2400, position: 3, match: "p-pay-2"),
        acBankLine("p-ac-bt-4", c, day(-3), "SERVICE CHARGE", -2.5, position: 4),
        acBankLine("p-ac-bt-5", c, day(-2), "POS STATIONERY CORNER", -18.75, position: 5, ignored: true, balance: 24068.75),
      ]
      let vatReturn = rec([
        "id": "p-ac-vat-1", "companyId": c, "periodStart": quarter.from, "periodEnd": quarter.to, "format": "generic",
        "boxes": [
          ["id": "sales-taxed", "label": "Taxable sales", "amount": 0, "vat": 0],
          ["id": "output", "label": "Tax on sales (output tax)", "amount": 0],
          ["id": "input", "label": "Tax on purchases (input tax)", "amount": 0],
          ["id": "net", "label": "Net tax to pay", "amount": 0],
        ],
        "net": 0, "currency": "KWD", "filedOn": AcDate.addDays(quarter.to, 12), "reference": "VAT-RCPT-2219",
        "journalId": NSNull(), "paymentJournalId": NSNull(), "createdAt": "\(quarter.to)T12:00:00.000Z",
        "updatedAt": "\(quarter.to)T12:00:00.000Z",
      ])
      return [
        "accounts": accounts, "journals": journals, "assets": [asset], "depreciationRuns": [run],
        "expenses": [expense], "bankTransactions": statement, "vatReturns": [vatReturn],
      ]
    }

    /// Part of the Kuwait chart (`KUWAIT` in src/lib/accounting/charts.ts).
    private static let acChart: [(code: String, name: String, nameAr: String, type: String, role: String?)] = [
      ("1000", "Bank – current account", "البنك – الحساب الجاري", "asset_cash", "bank"),
      ("1010", "Petty cash", "العهدة النقدية", "asset_cash", "cash"),
      ("1020", "KNET and card settlements", "تسويات كي نت والبطاقات", "asset_current", nil),
      ("1100", "Accounts receivable", "الذمم المدينة", "asset_receivable", "receivable"),
      ("1110", "Retentions receivable", "محتجزات مدينة", "asset_current", nil),
      ("1150", "Post-dated cheques received", "شيكات آجلة مستلمة", "asset_current", nil),
      ("1200", "Inventory", "المخزون", "asset_current", nil),
      ("1300", "Prepaid expenses", "مصروفات مدفوعة مقدماً", "asset_prepayments", nil),
      ("1350", "Input tax recoverable", "ضريبة مدخلات قابلة للاسترداد", "asset_current", "input_tax"),
      ("1520", "Office equipment and computers", "المعدات المكتبية والحاسب الآلي", "asset_fixed", nil),
      ("1530", "Accumulated depreciation – equipment", "مجمع إهلاك المعدات", "asset_fixed", nil),
      ("1540", "Vehicles", "السيارات", "asset_fixed", nil),
      ("1550", "Accumulated depreciation – vehicles", "مجمع إهلاك السيارات", "asset_fixed", nil),
      ("2000", "Accounts payable", "الذمم الدائنة", "liability_payable", "payable"),
      ("2010", "Retentions payable", "محتجزات دائنة", "liability_current", nil),
      ("2050", "Company credit card", "بطاقة ائتمان الشركة", "liability_credit_card", "credit_card"),
      ("2100", "Output tax", "ضريبة المخرجات", "liability_current", "output_tax"),
      ("2110", "Tax payable", "الضريبة المستحقة", "liability_current", "tax_settlement"),
      ("2150", "Post-dated cheques issued", "شيكات آجلة صادرة", "liability_current", nil),
      ("2200", "Accrued expenses", "مصروفات مستحقة", "liability_current", nil),
      ("2300", "Salaries payable", "رواتب مستحقة", "liability_current", nil),
      ("2700", "End-of-service indemnity provision", "مخصص مكافأة نهاية الخدمة", "liability_non_current", nil),
      ("3000", "Capital", "رأس المال", "equity", "capital"),
      ("3100", "Partners' current accounts", "الحسابات الجارية للشركاء", "equity", "drawings"),
      ("3200", "Statutory reserve", "الاحتياطي الإجباري", "equity", nil),
      ("3210", "Voluntary reserve", "الاحتياطي الاختياري", "equity", nil),
      ("3300", "Retained earnings", "الأرباح المرحلة", "equity", "retained_earnings"),
      ("3900", "Opening balance equity", "أرصدة افتتاحية", "equity", "opening_balance"),
      ("4000", "Sales", "المبيعات", "income", "sales"),
      ("4100", "Service revenue", "إيرادات الخدمات", "income", nil),
      ("4200", "Delivery charges income", "إيرادات التوصيل", "income", "charges"),
      ("4500", "Other income", "إيرادات أخرى", "income_other", nil),
      ("4520", "Gain or loss on disposal of assets", "أرباح وخسائر استبعاد الأصول", "income_other", nil),
      ("5000", "Cost of sales", "تكلفة المبيعات", "expense_direct_cost", "cost_of_sales"),
      ("5300", "Inventory adjustments", "تسويات المخزون", "expense_direct_cost", nil),
      ("6000", "General and administrative expenses", "مصروفات عمومية وإدارية", "expense", "expense"),
      ("6010", "Salaries and wages", "الرواتب والأجور", "expense", nil),
      ("6060", "Rent", "الإيجار", "expense", nil),
      ("6070", "Electricity and water", "الكهرباء والماء", "expense", nil),
      ("6170", "Bank charges", "العمولات والمصاريف البنكية", "expense", "bank_fees"),
      ("6180", "KNET and card fees", "عمولات كي نت والبطاقات", "expense", nil),
      ("6210", "Postage and courier", "البريد والتوصيل", "expense", nil),
      ("6900", "Depreciation", "الإهلاك", "expense_depreciation", nil),
      ("7000", "Exchange gain or loss", "أرباح وخسائر فروق العملة", "expense_other", "fx"),
      ("7100", "Finance costs", "تكاليف التمويل", "expense_other", nil),
      ("7200", "KFAS contribution", "حصة مؤسسة الكويت للتقدم العلمي", "expense_other", nil),
      ("7210", "Zakat", "الزكاة", "expense_other", nil),
    ]

    private static func acAccount(
      _ company: String, _ code: String, _ name: String, _ nameAr: String, _ type: String, _ role: String?,
      stamp: String
    ) -> JSONValue {
      var fields: [String: Any] = [
        "id": "p-ac-a-\(code)", "companyId": company, "code": code, "name": name, "nameAr": nameAr, "type": type,
        "description": "", "role": role.map { $0 as Any } ?? NSNull(), "bank": NSNull(), "archived": false, "createdAt": stamp,
        "updatedAt": stamp,
      ]
      if code == "1000" {
        fields["bank"] = [
          "institution": "Gulf Example Bank", "accountNumber": "0012345678", "iban": "", "bic": "",
        ]
      }
      return rec(fields)
    }

    private static func acJournal(
      _ id: String, _ company: String, _ number: String, _ date: String, _ reference: String, status: String,
      lines: [(code: String, description: String, debit: Double, credit: Double)], kind: String? = nil,
      source: String? = nil
    ) -> JSONValue {
      var rows: [[String: Any]] = []
      for (index, line) in lines.enumerated() {
        rows.append([
          "id": "\(id)-l\(index + 1)", "accountId": "p-ac-a-\(line.code)", "description": line.description,
          "debit": line.debit, "credit": line.credit, "contactId": NSNull(),
        ])
      }
      var fields: [String: Any] = [
        "id": id, "companyId": company, "number": number, "date": date, "reference": reference, "notes": "",
        "status": status, "lines": rows, "vatReturnId": NSNull(), "sourceId": source.map { $0 as Any } ?? NSNull(),
        "reversalOf": NSNull(), "createdAt": "\(date)T09:00:00.000Z", "updatedAt": "\(date)T09:00:00.000Z",
      ]
      if let kind { fields["kind"] = kind }
      return rec(fields)
    }

    private static func acBankLine(
      _ id: String, _ company: String, _ date: String, _ description: String, _ amount: Double, position: Int,
      match: String? = nil, ignored: Bool = false, balance: Double? = nil
    ) -> JSONValue {
      rec([
        "id": id, "companyId": company, "accountId": "p-ac-a-1000", "date": date, "description": description,
        "reference": "", "amount": amount, "balance": balance.map { $0 as Any } ?? NSNull(), "fingerprint": "\(id)-fp",
        "importId": "p-ac-imp-1", "position": position,
        "match": match.map { ["source": "payment", "id": $0] as Any } ?? NSNull(), "ignored": ignored,
        "createdAt": "\(date)T07:00:00.000Z", "updatedAt": "\(date)T07:00:00.000Z",
      ])
    }
  }
#endif
