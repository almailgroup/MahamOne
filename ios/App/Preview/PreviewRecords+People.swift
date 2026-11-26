#if DEBUG
  // Preview mode's made-up Maham People records (see PreviewRecords.swift):
  // a few employees (Kuwaiti, GCC and expatriate, one who has left), last
  // month's pay run, leave, a staff loan, a final settlement, letters and a
  // letter template, and a manpower costing. Every name, Civil ID, number and
  // amount here is invented; nothing is a real person or record.

  import Foundation
  import MahamKit

  extension PreviewRecords {
    /// The People area's records.
    static func peopleArea(company: Company) -> [String: [JSONValue]] {
      let c = company.id
      let period = peLastMonth()
      return [
        "employees": peEmployees(c),
        "peopleSettings": [pePeopleSettings(c)],
        "payrollSettings": [pePayrollSettings(c)],
        "payRuns": [pePayRun(c, period: period)],
        "leaveRecords": peLeave(c),
        "staffLoans": [peLoan(c, period: period)],
        "finalSettlements": [peSettlement(c)],
        "letterTemplates": [peTemplate(c)],
        "employeeLetters": peLetters(c),
        "staffingCostings": [peCosting(c)],
        "complianceDocuments": peDocuments(c),
        "renewals": [peRenewal(c)],
      ]
    }

    // MARK: Days

    /// Last month, as `yyyy-MM`.
    private static func peLastMonth() -> String {
      let today = day(0)
      let year = Int(today.prefix(4)) ?? 2026
      let month = Int(today.dropFirst(5).prefix(2)) ?? 1
      let last = month == 1 ? (year - 1, 12) : (year, month - 1)
      return String(format: "%04d-%02d", last.0, last.1)
    }

    /// The month's last day.
    private static func peMonthEnd(_ period: String) -> String {
      let year = Int(period.prefix(4)) ?? 2026
      let month = Int(period.suffix(2)) ?? 1
      let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
      let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][max(0, min(11, month - 1))]
      return "\(period)-\(days)"
    }

    private static func peStamp(_ date: String) -> String { "\(date)T08:00:00.000Z" }

    // MARK: Employees

    private static func peEmployee(_ c: String, _ fields: [String: Any]) -> JSONValue {
      var record: [String: Any] = [
        "companyId": c, "nationality": "", "category": "expat", "birthDate": NSNull(), "gender": NSNull(),
        "civilId": "", "civilIdExpiry": NSNull(), "passportNumber": "", "passportExpiry": NSNull(),
        "residencyArticle": "", "residencyNumber": "", "residencyExpiry": NSNull(), "workPermitNumber": "",
        "pamJobTitle": "", "permitSalary": 0, "workPermitExpiry": NSNull(), "jobTitle": "", "department": "",
        "hireDate": NSNull(), "probationEnd": NSNull(), "contractType": "unlimited", "contractEnd": NSNull(),
        "payBasis": "monthly", "basicSalary": 0, "allowances": [], "bank": "", "iban": "", "accountNumber": "",
        "pifssNumber": "", "phone": "", "email": "", "status": "active", "leavingDate": NSNull(),
        "leavingReason": NSNull(), "notes": "", "photoId": NSNull(),
      ]
      for (key, value) in fields { record[key] = value }
      let hire = (fields["hireDate"] as? String) ?? day(-365)
      record["createdAt"] = peStamp(hire)
      record["updatedAt"] = peStamp(day(-3))
      return rec(record)
    }

    private static func peEmployees(_ c: String) -> [JSONValue] {
      [
        peEmployee(
          c,
          [
            "id": "p-pe-emp-1", "number": "E-0101", "name": "Yousef Al-Nadeem", "nameAr": "يوسف النديم",
            "nationality": "KW", "category": "kuwaiti", "gender": "male", "birthDate": "1988-04-12",
            "civilId": "000000000101", "civilIdExpiry": day(200), "passportNumber": "P0000101",
            "passportExpiry": day(900), "jobTitle": "Accountant", "jobTitleAr": "محاسب", "department": "Finance",
            "hireDate": day(-1400), "basicSalary": 950,
            "allowances": [
              ["id": "p-pe-al-1", "name": "Housing", "nameAr": "سكن", "amount": 150, "countsForEos": true],
              ["id": "p-pe-al-2", "name": "Transport", "nameAr": "مواصلات", "amount": 50, "countsForEos": false],
            ],
            "accountNumber": "4000 0000 0000 0101", "pifssNumber": "PF-000101", "phone": "+965 5000 0101",
            "email": "yousef@example.com",
          ]),
        peEmployee(
          c,
          [
            "id": "p-pe-emp-2", "number": "E-0102", "name": "Ravi Kumar Pillai", "nameAr": "رافي كومار بيلاي",
            "nationality": "IN", "category": "expat", "gender": "male", "civilId": "000000000102",
            "civilIdExpiry": day(300), "passportNumber": "P0000102", "passportExpiry": day(1200),
            "residencyArticle": "18", "residencyNumber": "R-000102", "residencyExpiry": day(25),
            "workPermitNumber": "WP-000102", "workPermitExpiry": day(-5), "permitSalary": 180,
            "jobTitle": "Security Guard", "jobTitleAr": "حارس أمن", "department": "Security",
            "hireDate": day(-700), "basicSalary": 180,
            "allowances": [["id": "p-pe-al-3", "name": "Food", "nameAr": "طعام", "amount": 20, "countsForEos": true]],
            "accountNumber": "4000 0000 0000 0102", "phone": "+965 5000 0102",
          ]),
        peEmployee(
          c,
          [
            "id": "p-pe-emp-3", "number": "E-0103", "name": "Mona Farouk", "nameAr": "منى فاروق",
            "nationality": "EG", "category": "expat", "gender": "female", "civilId": "000000000103",
            "civilIdExpiry": day(340), "residencyArticle": "18", "residencyNumber": "R-000103",
            "residencyExpiry": day(340), "jobTitle": "Office Administrator", "jobTitleAr": "إداري",
            "department": "Administration", "hireDate": day(-20), "probationEnd": day(80),
            "contractType": "fixed", "contractEnd": day(345), "basicSalary": 450,
            "accountNumber": "4000 0000 0000 0103", "phone": "+965 5000 0103", "email": "mona@example.com",
          ]),
        peEmployee(
          c,
          [
            "id": "p-pe-emp-4", "number": "E-0104", "name": "Nawaf Al-Sahli", "nameAr": "نواف السهلي",
            "nationality": "SA", "category": "gcc", "gender": "male", "civilId": "000000000104",
            "civilIdExpiry": day(15), "passportNumber": "P0000104", "passportExpiry": day(600),
            "jobTitle": "Driver", "jobTitleAr": "سائق", "department": "Operations", "hireDate": day(-2200),
            "basicSalary": 600,
            "allowances": [["id": "p-pe-al-4", "name": "Car", "nameAr": "سيارة", "amount": 100, "countsForEos": true]],
            "accountNumber": "4000 0000 0000 0104", "phone": "+965 5000 0104",
          ]),
        peEmployee(
          c,
          [
            "id": "p-pe-emp-5", "number": "E-0098", "name": "Joseph Fernandes", "nameAr": "جوزيف فرنانديز",
            "nationality": "IN", "category": "expat", "gender": "male", "civilId": "000000000098",
            "jobTitle": "Storekeeper", "jobTitleAr": "أمين مخزن", "department": "Operations",
            "hireDate": day(-1940), "basicSalary": 400, "status": "left", "leavingDate": day(-40),
            "leavingReason": "resignation", "accountNumber": "4000 0000 0000 0098",
          ]),
      ]
    }

    // MARK: Settings

    private static func pePeopleSettings(_ c: String) -> JSONValue {
      rec([
        "id": c, "companyId": c, "kuwaitizationTarget": 30, "eosDailyDivisor": 26, "reminderDays": [60, 30, 7],
        "auditFilingMonths": 3, "pifssDueDay": 15, "letters": true,
        "departments": [
          ["id": "p-pe-dp-1", "name": "Finance", "nameAr": "المالية"],
          ["id": "p-pe-dp-2", "name": "Security", "nameAr": "الأمن"],
          ["id": "p-pe-dp-3", "name": "Administration", "nameAr": "الإدارة"],
          ["id": "p-pe-dp-4", "name": "Operations", "nameAr": "العمليات"],
        ],
        "costing": ["on": true, "overheadPercent": 10, "marginPercent": 15],
        "updatedAt": peStamp(day(-30)),
      ])
    }

    private static func pePayrollSettings(_ c: String) -> JSONValue {
      rec([
        "id": c, "companyId": c, "dailyDivisor": 26, "rateBase": "wage",
        "pifss": [["from": "2026-01-01", "employer": 11.5, "employee": 10.5, "cap": 2750]], "gcc": [],
        "minimumWage": 75, "payDay": 31, "bankAccountId": NSNull(), "accounts": [String: String](), "provisions": true,
        "eosForInsured": false, "pamFileNumber": "PAM-000-0001", "leaveReasonsOn": true,
        "leaveReasons": [
          [
            "id": "p-pe-lr-1", "name": "Emergency leave", "nameAr": "إجازة طارئة", "base": "annual", "pay": "annual",
            "maxDaysPerYear": 6,
          ],
          ["id": "p-pe-lr-2", "name": "Compensatory days", "nameAr": "أيام تعويضية", "base": "bereavement", "pay": "balance"],
        ],
        "updatedAt": peStamp(day(-30)),
      ])
    }

    // MARK: Payroll

    private static func peLine(
      _ id: String, employee: String, number: String, name: String, nameAr: String, category: String,
      nationality: String, basic: Double, allowance: (String, String, Double)?, pifss: (Double, Double),
      loan: Double, days: Int
    ) -> [String: Any] {
      let extra = allowance?.2 ?? 0
      let gross = basic + extra
      var allowances: [[String: Any]] = []
      if let allowance {
        allowances.append([
          "id": "\(id)-a", "name": allowance.0, "nameAr": allowance.1, "monthly": allowance.2, "amount": allowance.2,
        ])
      }
      let loans: [[String: Any]] = loan > 0 ? [["loanId": "p-pe-ln-1", "amount": loan]] : []
      return [
        "id": id, "employeeId": employee, "number": number, "name": name, "nameAr": nameAr, "jobTitle": "",
        "jobTitleAr": "", "category": category, "nationality": nationality, "civilId": "", "iban": "",
        "accountNumber": "4000 0000 0000 0000", "hireDate": NSNull(), "leavingDate": NSNull(), "permitSalary": 0,
        "monthlyBasic": basic, "allowances": allowances, "daysWorked": days, "daysInMonth": days,
        "overtime": ["normal": 0, "restDay": 0, "holiday": 0], "absentDays": 0, "unpaidLeaveDays": 0,
        "reducedPay": [], "adjustments": [], "loans": loans,
        "basic": basic, "allowanceTotal": extra, "overtimePay": 0, "absenceDeduction": 0, "additions": 0,
        "gross": gross, "pifssBase": pifss.0 > 0 ? gross : 0, "pifssEmployee": pifss.0, "pifssEmployer": pifss.1,
        "loanDeduction": loan, "otherDeductions": 0, "net": gross - pifss.0 - loan,
      ]
    }

    private static func pePayRun(_ c: String, period: String) -> JSONValue {
      let end = peMonthEnd(period)
      let days = Int(end.suffix(2)) ?? 30
      let lines: [[String: Any]] = [
        peLine(
          "p-pe-pl-1", employee: "p-pe-emp-1", number: "E-0101", name: "Yousef Al-Nadeem", nameAr: "يوسف النديم",
          category: "kuwaiti", nationality: "KW", basic: 950, allowance: ("Housing and transport", "سكن ومواصلات", 200),
          pifss: (120.75, 132.25), loan: 0, days: days),
        peLine(
          "p-pe-pl-2", employee: "p-pe-emp-2", number: "E-0102", name: "Ravi Kumar Pillai",
          nameAr: "رافي كومار بيلاي", category: "expat", nationality: "IN", basic: 180,
          allowance: ("Food", "طعام", 20), pifss: (0, 0), loan: 20, days: days),
        peLine(
          "p-pe-pl-3", employee: "p-pe-emp-4", number: "E-0104", name: "Nawaf Al-Sahli", nameAr: "نواف السهلي",
          category: "gcc", nationality: "SA", basic: 600, allowance: ("Car", "سيارة", 100), pifss: (0, 0), loan: 0,
          days: days),
      ]
      return rec([
        "id": "p-pe-run-1", "companyId": c, "period": period, "status": "paid", "date": end, "payDate": end,
        "lines": lines,
        "rules": [
          "dailyDivisor": 26, "rateBase": "wage",
          "pifss": ["from": "2026-01-01", "employer": 11.5, "employee": 10.5, "cap": 2750], "gcc": [],
          "minimumWage": 75,
        ],
        "deductionAccountId": NSNull(), "journalId": NSNull(), "provisionJournalId": NSNull(),
        "provisions": [
          ["employeeId": "p-pe-emp-1", "eos": 1612.5, "leaveDays": 21.5, "leave": 951.0],
          ["employeeId": "p-pe-emp-2", "eos": 157.692, "leaveDays": 14, "leave": 107.692],
          ["employeeId": "p-pe-emp-4", "eos": 2425.0, "leaveDays": 30, "leave": 807.692],
        ],
        "paidOn": end, "paymentJournalId": NSNull(), "bankAccountId": NSNull(), "reversalJournalIds": [],
        "notes": "", "createdAt": peStamp(end), "updatedAt": peStamp(end),
      ])
    }

    private static func peLoan(_ c: String, period: String) -> JSONValue {
      rec([
        "id": "p-pe-ln-1", "companyId": c, "employeeId": "p-pe-emp-2", "date": day(-75), "amount": 300,
        "instalment": 20, "firstPeriod": period, "paidFromAccountId": NSNull(), "journalId": NSNull(),
        "status": "active", "cancelJournalId": NSNull(), "notes": "Advance for travel home.",
        "createdAt": peStamp(day(-75)), "updatedAt": peStamp(day(-75)),
      ])
    }

    private static func peSettlement(_ c: String) -> JSONValue {
      rec([
        "id": "p-pe-set-1", "companyId": c, "employeeId": "p-pe-emp-5", "status": "paid", "leavingDate": day(-40),
        "reason": "resignation", "years": 5.2, "eosWage": 400, "indemnity": 822.564, "pifssOffset": 0,
        "noticeMonths": 0, "noticePay": 0, "leaveDays": 12, "leavePay": 184.615,
        "lastSalary": [
          "period": String(day(-40).prefix(7)), "days": 10, "daysInMonth": 30, "basic": 133.333,
          "allowances": 0, "gross": 133.333, "pifssEmployee": 0, "pifssEmployer": 0,
        ],
        "loans": [], "otherDeductions": 0, "deductionNote": "", "eosProvision": 780.0, "leaveProvision": 170.0,
        "net": 1140.512, "journalId": NSNull(), "paidOn": day(-35), "paymentJournalId": NSNull(),
        "bankAccountId": NSNull(), "reversalJournalIds": [], "notes": "",
        "createdAt": peStamp(day(-38)), "updatedAt": peStamp(day(-35)),
      ])
    }

    // MARK: Leave

    private static func peLeaveRecord(
      _ id: String, _ c: String, employee: String, type: String, kind: String = "leave", start: String,
      end: String, days: Double, reason: String? = nil, notes: String = ""
    ) -> JSONValue {
      var fields: [String: Any] = [
        "id": id, "companyId": c, "employeeId": employee, "type": type, "kind": kind, "start": start, "end": end,
        "days": days, "status": "approved", "notes": notes, "createdAt": peStamp(start), "updatedAt": peStamp(start),
      ]
      if let reason { fields["reasonId"] = reason }
      return rec(fields)
    }

    private static func peLeave(_ c: String) -> [JSONValue] {
      [
        peLeaveRecord(
          "p-pe-lv-1", c, employee: "p-pe-emp-4", type: "annual", start: day(-2), end: day(5), days: 6,
          notes: "Family visit"),
        peLeaveRecord("p-pe-lv-2", c, employee: "p-pe-emp-1", type: "sick", start: day(-60), end: day(-58), days: 3),
        peLeaveRecord("p-pe-lv-3", c, employee: "p-pe-emp-2", type: "annual", start: day(-100), end: day(-91), days: 8),
        peLeaveRecord(
          "p-pe-lv-4", c, employee: "p-pe-emp-4", type: "bereavement", kind: "adjustment", start: day(-30),
          end: day(-30), days: 2, reason: "p-pe-lr-2", notes: "Worked two Fridays"),
        peLeaveRecord(
          "p-pe-lv-5", c, employee: "p-pe-emp-1", type: "annual", start: day(-150), end: day(-150), days: 1,
          reason: "p-pe-lr-1"),
      ]
    }

    // MARK: Letters

    private static func peTemplate(_ c: String) -> JSONValue {
      rec([
        "id": "p-pe-lt-1", "companyId": c, "kind": "salary_transfer", "name": "Salary transfer letter",
        "nameAr": "خطاب تحويل راتب", "language": "ar-en", "subjectEn": "Salary transfer", "subjectAr": "تحويل راتب",
        "bodyEn": "{letter.addressee}\n\n{company.name} confirms that the holder of this letter has been employed as {employee.jobTitle} since {employee.hireDate}, with a total monthly salary of {salary.total}.",
        "bodyAr": "{letter.addressee}\n\nتفيد {company.name} بأن صاحب هذا الخطاب يعمل لديها بوظيفة {employee.jobTitle} منذ {employee.hireDate}، ويتقاضى راتباً شهرياً إجمالياً قدره {salary.total}.",
        "showStamp": true, "showSignature": true, "signatoryName": "Huda Al-Karim", "signatoryTitle": "HR Manager",
        "autoOn": ["salary_change"], "privateFields": true, "archived": false,
        "createdAt": peStamp(day(-200)), "updatedAt": peStamp(day(-60)),
      ])
    }

    private static func peLetters(_ c: String) -> [JSONValue] {
      [
        rec([
          "id": "p-pe-el-1", "companyId": c, "employeeId": "p-pe-emp-1", "templateId": NSNull(),
          "kind": "salary_certificate", "number": "HR-2026-0001", "language": "ar",
          "addressee": "إلى من يهمه الأمر", "purpose": "", "subject": "شهادة راتب",
          "body": "إلى من يهمه الأمر\n\nتشهد الشركة بأن صاحب هذه الشهادة يعمل لديها بوظيفة محاسب، ويتقاضى راتباً شهرياً إجمالياً قدره 1,150.000 د.ك.",
          "issuedOn": day(-3), "status": "issued", "trigger": NSNull(), "showStamp": true, "showSignature": true,
          "createdAt": peStamp(day(-4)), "updatedAt": peStamp(day(-3)),
        ]),
        rec([
          "id": "p-pe-el-2", "companyId": c, "employeeId": "p-pe-emp-3", "templateId": NSNull(),
          "kind": "employment_certificate", "number": "", "language": "en", "addressee": "To whom it may concern",
          "purpose": "", "subject": "Employment certificate",
          "body": "To whom it may concern\n\nThis is to certify that the holder of this certificate is employed by the company to date as an Office Administrator.",
          "issuedOn": NSNull(), "status": "draft", "trigger": "joining",
          "createdAt": peStamp(day(-20)), "updatedAt": peStamp(day(-20)),
        ]),
      ]
    }

    // MARK: Costing

    private static func peCosting(_ c: String) -> JSONValue {
      rec([
        "id": "p-pe-cs-1", "companyId": c, "name": "Tower A, night shift", "clientId": "p-cl-1", "quoteId": NSNull(),
        "status": "draft", "overheadPercent": 10, "marginPercent": 15,
        "notes": "Night cover for the lobby and the car park.",
        "posts": [
          [
            "id": "p-pe-cp-1", "jobTitle": "Security Guard", "jobTitleAr": "حارس أمن", "category": "expat",
            "headcount": 4, "hoursPerDay": 12, "daysPerMonth": 26, "basic": 180, "allowances": 20, "otherCosts": 25,
            "employerPifss": 0, "eosiMonthly": 0, "leaveMonthly": 0, "monthlyCost": 0, "sellPrice": 420,
          ],
          [
            "id": "p-pe-cp-2", "jobTitle": "Security Supervisor", "jobTitleAr": "مشرف أمن", "category": "kuwaiti",
            "headcount": 1, "hoursPerDay": 8, "daysPerMonth": 26, "basic": 900, "allowances": 100, "otherCosts": 0,
            "employerPifss": 0, "eosiMonthly": 0, "leaveMonthly": 0, "monthlyCost": 0, "sellPrice": 1550,
          ],
        ],
        "createdAt": peStamp(day(-12)), "updatedAt": peStamp(day(-2)),
      ])
    }

    // MARK: Papers

    private static func peDocuments(_ c: String) -> [JSONValue] {
      [
        rec([
          "id": "p-pe-cd-1", "companyId": c, "type": "driving_licence", "title": "", "number": "DL-000104",
          "issuer": "", "issueDate": NSNull(), "expiryDate": day(400), "renewalCost": 0, "reminderDays": NSNull(),
          "ownerType": "employee", "employeeId": "p-pe-emp-4", "ownerName": "", "notes": "", "archived": false,
          "licenceClass": "Private", "createdAt": peStamp(day(-300)), "updatedAt": peStamp(day(-300)),
        ]),
        rec([
          "id": "p-pe-cd-2", "companyId": c, "type": "health_insurance", "title": "", "number": "HI-000102",
          "issuer": "", "issueDate": NSNull(), "expiryDate": day(10), "renewalCost": 0, "reminderDays": NSNull(),
          "ownerType": "employee", "employeeId": "p-pe-emp-2", "ownerName": "", "notes": "", "archived": false,
          "createdAt": peStamp(day(-355)), "updatedAt": peStamp(day(-355)),
        ]),
      ]
    }

    private static func peRenewal(_ c: String) -> JSONValue {
      rec([
        "id": "p-pe-rn-1", "companyId": c, "documentKey": "emp:p-pe-emp-1:civil_id", "documentId": NSNull(),
        "employeeId": "p-pe-emp-1", "type": "civil_id", "renewedOn": day(-165), "previousExpiry": day(-170),
        "newExpiry": day(200), "fee": 5, "expenseId": NSNull(), "note": "", "createdAt": peStamp(day(-165)),
      ])
    }
  }
#endif
