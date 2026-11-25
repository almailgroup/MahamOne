import Foundation

/// Kuwaiti legal forms and cash limits (src/lib/kuwait-rules.ts).
public enum KuwaitRules {
  public struct LegalForm: Hashable, Sendable {
    public var value: String
    public var label: String
    public var labelAr: String
  }

  public struct CashRule: Hashable, Sendable {
    /// An English key, translated when shown.
    public var label: String
    /// The most cash (KWD) the business may take in one payment; nil for no
    /// limit, 0 for no cash at all.
    public var maxCash: Double?
  }

  /// A company's Kuwait profile (`company.kuwait`), with defaults for
  /// anything not set yet; fields this version doesn't know are kept.
  public static func kuwaitProfile(_ company: JSONValue?) -> JSONValue {
    var profile: [String: JSONValue] = [
      "legalForm": "wll",
      "licenceNumber": "",
      "activity": "general",
      "foreignOwnershipPercent": 0,
      "capital": 0,
      "pamFileNumber": "",
      "pifssEmployerNumber": "",
      "mofTaxCardNumber": "",
      "kcciNumber": "",
      "digitalCommerceNumber": "",
      "wamdPhone": "",
    ]
    for (key, value) in WebJS.spread(company?["kuwait"]) { profile[key] = value }
    return .object(profile)
  }

  public static let legalForms: [LegalForm] = [
    LegalForm(value: "sole_proprietorship", label: "Sole proprietorship", labelAr: "مؤسسة فردية"),
    LegalForm(
      value: "wll", label: "With limited liability company (W.L.L.)", labelAr: "شركة ذات مسؤولية محدودة (ذ.م.م)"),
    LegalForm(value: "spc", label: "Single person company (S.P.C.)", labelAr: "شركة الشخص الواحد"),
    LegalForm(value: "general_partnership", label: "General partnership", labelAr: "شركة تضامن"),
    LegalForm(value: "limited_partnership", label: "Limited partnership", labelAr: "شركة توصية بسيطة"),
    LegalForm(
      value: "kscc", label: "Closed shareholding company (K.S.C.C.)", labelAr: "شركة مساهمة مقفلة (ش.م.ك.م)"),
    LegalForm(
      value: "ksc_listed", label: "Listed shareholding company (K.S.C.P.)",
      labelAr: "شركة مساهمة عامة مدرجة (ش.م.ك.ع)"),
    LegalForm(value: "foreign_branch", label: "Branch of a foreign company", labelAr: "فرع شركة أجنبية"),
    LegalForm(value: "freelance", label: "Freelance or home business licence", labelAr: "ترخيص عمل حر أو منزلي"),
    LegalForm(value: "other", label: "Other", labelAr: "أخرى"),
  ]

  /// Shareholding companies pay Zakat (1%) and KFAS (1%); listed ones also NLST (2.5%).
  public static func isShareholding(_ form: String) -> Bool {
    form == "kscc" || form == "ksc_listed"
  }

  /// The business activities with their cash rules, in the web's order.
  public static let activities: [String] = [
    "general", "health", "salon", "sports_club", "pest_control", "vehicles", "gold_jewellery", "real_estate",
  ]

  /// Cash limits by activity, in Kuwaiti dinars. Sources: MOCI Decision
  /// 32/2026 (KD 10 for health, salons, sports clubs and pest control), the
  /// 2024 ban on cash for vehicle sales, Resolution 182/2025 (gold and
  /// precious metals) and the 2026 real-estate rules.
  public static let cashRules: [String: CashRule] = [
    "general": CashRule(label: "General trading, services or other", maxCash: nil),
    "health": CashRule(label: "Health institute", maxCash: 10),
    "salon": CashRule(label: "Salon (men, women or children)", maxCash: 10),
    "sports_club": CashRule(label: "Sports club", maxCash: 10),
    "pest_control": CashRule(label: "Pest control", maxCash: 10),
    "vehicles": CashRule(label: "Vehicle sales", maxCash: 0),
    "gold_jewellery": CashRule(label: "Gold, jewellery and precious metals", maxCash: 0),
    "real_estate": CashRule(label: "Real estate", maxCash: 0),
  ]

  /// The most cash (KWD) the business may take in one payment, or nil for no
  /// limit (also for an activity this version doesn't know).
  public static func cashLimit(_ activity: String?) -> Double? {
    guard let activity else { return nil }
    return cashRules[activity]?.maxCash
  }
}
