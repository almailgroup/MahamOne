import Foundation

/// A country's starting settings for a new company (src/lib/regions.ts).
public struct RegionDefaults: Hashable, Sendable {
  public struct Tax: Hashable, Sendable {
    public var name: String
    public var rate: Double
  }

  public var currency: String
  public var locale: String
  public var dateFormat: String
  public var pageSize: String
  public var language: String
  public var taxIdLabel: String
  /// The typical standard tax; nil where there is no general sales tax or VAT.
  public var tax: Tax?
}

public enum Regions {
  private static func base(
    _ currency: String, _ locale: String, _ taxIdLabel: String, _ tax: (String, Double)?,
    dateFormat: String = "dd/MM/yyyy", pageSize: String = "A4", language: String = "en"
  ) -> RegionDefaults {
    RegionDefaults(
      currency: currency, locale: locale, dateFormat: dateFormat, pageSize: pageSize, language: language,
      taxIdLabel: taxIdLabel, tax: tax.map { RegionDefaults.Tax(name: $0.0, rate: $0.1) })
  }

  /// Sensible starting points per country. Rates are the common standard
  /// rates and can be changed in Settings → Taxes.
  public static let defaults: [String: RegionDefaults] = [
    "US": base("USD", "en-US", "EIN", nil, dateFormat: "MM/dd/yyyy", pageSize: "LETTER"),
    "CA": base("CAD", "en-CA", "GST/HST No.", ("GST", 5), dateFormat: "yyyy-MM-dd", pageSize: "LETTER"),
    "GB": base("GBP", "en-GB", "VAT No.", ("VAT", 20)),
    "IE": base("EUR", "en-IE", "VAT No.", ("VAT", 23)),
    "AE": base("AED", "en-AE", "TRN", ("VAT", 5)),
    "SA": base("SAR", "en-US", "VAT No.", ("VAT", 15)),
    "BH": base("BHD", "en-US", "VAT No.", ("VAT", 10)),
    "OM": base("OMR", "en-US", "VATIN", ("VAT", 5)),
    "QA": base("QAR", "en-US", "Tax ID", nil),
    // MOCI requires Arabic on invoices; English is printed next to it.
    "KW": base("KWD", "en-KW", "Tax card no.", nil, language: "ar-en"),
    "EG": base("EGP", "en-US", "Tax Reg. No.", ("VAT", 14)),
    "JO": base("JOD", "en-US", "Tax No.", ("GST", 16)),
    "MA": base("MAD", "fr-FR", "ICE", ("TVA", 20), language: "fr"),
    "TR": base("TRY", "tr-TR", "VKN", ("KDV", 20), dateFormat: "dd.MM.yyyy"),
    "PK": base("PKR", "en-US", "NTN", ("GST", 18)),
    "IN": base("INR", "en-IN", "GSTIN", ("GST", 18)),
    "SG": base("SGD", "en-SG", "GST Reg. No.", ("GST", 9)),
    "AU": base("AUD", "en-AU", "ABN", ("GST", 10)),
    "NZ": base("NZD", "en-NZ", "GST No.", ("GST", 15)),
    "ZA": base("ZAR", "en-ZA", "VAT No.", ("VAT", 15), dateFormat: "yyyy-MM-dd"),
    "NG": base("NGN", "en-NG", "TIN", ("VAT", 7.5)),
    "KE": base("KES", "en-US", "KRA PIN", ("VAT", 16)),
    "GH": base("GHS", "en-US", "TIN", ("VAT", 15)),
    "DE": base("EUR", "de-DE", "USt-IdNr.", ("MwSt.", 19), dateFormat: "dd.MM.yyyy", language: "de"),
    "AT": base("EUR", "de-AT", "UID", ("USt.", 20), dateFormat: "dd.MM.yyyy", language: "de"),
    "CH": base("CHF", "de-CH", "MWST-Nr.", ("MWST", 8.1), dateFormat: "dd.MM.yyyy", language: "de"),
    "FR": base("EUR", "fr-FR", "N° TVA", ("TVA", 20), language: "fr"),
    "BE": base("EUR", "fr-BE", "N° TVA", ("TVA", 21), language: "fr"),
    "LU": base("EUR", "fr-FR", "N° TVA", ("TVA", 17), language: "fr"),
    "ES": base("EUR", "es-ES", "NIF", ("IVA", 21), language: "es"),
    "MX": base("MXN", "es-MX", "RFC", ("IVA", 16), language: "es"),
    "PT": base("EUR", "pt-PT", "NIF", ("IVA", 23), language: "pt"),
    "BR": base("BRL", "pt-BR", "CNPJ", nil, language: "pt"),
    "IT": base("EUR", "it-IT", "P. IVA", ("IVA", 22), language: "it"),
    "NL": base("EUR", "nl-NL", "Btw-nr.", ("Btw", 21), dateFormat: "dd-MM-yyyy", language: "nl"),
    "SE": base("SEK", "sv-SE", "Momsreg.nr", ("Moms", 25), dateFormat: "yyyy-MM-dd"),
    "DK": base("DKK", "da-DK", "CVR", ("Moms", 25), dateFormat: "dd.MM.yyyy"),
    "NO": base("NOK", "nb-NO", "Org.nr.", ("MVA", 25), dateFormat: "dd.MM.yyyy"),
    "FI": base("EUR", "fi-FI", "ALV-nro", ("ALV", 25.5), dateFormat: "dd.MM.yyyy"),
    "PL": base("PLN", "pl-PL", "NIP", ("VAT", 23), dateFormat: "dd.MM.yyyy"),
  ]

  /// The defaults for a country; Kuwait's when the country is not known.
  public static func regionDefaults(_ country: String) -> RegionDefaults {
    defaults[country.uppercased()] ?? kuwait
  }

  private static let kuwait = base("KWD", "en-KW", "Tax card no.", nil, language: "ar-en")
}
