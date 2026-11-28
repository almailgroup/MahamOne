import MahamKit
import SwiftUI

// Templates (`src/apps/books/pages/templates.tsx`): the designs invoices,
// quotes and credit notes print with, their colour and layout, what every
// document prints, and the gallery of designs, whose thumbnails come with
// the app (Resources/Templates). The design of each type is chosen here,
// natively (SwTemplates); its colour and layout are shown as they are set.

/// A design of the gallery (`TEMPLATE_META`).
struct SuTemplate: Identifiable, Sendable {
  let id: String
  let name: String
  let description: String
  let tags: [String]

  static let all: [SuTemplate] = [
    SuTemplate(
      id: "modern", name: "Modern",
      description: "Crisp layout with an accent summary panel and a highlighted amount due.", tags: ["Popular", "Clean"]),
    SuTemplate(
      id: "minimal", name: "Minimal",
      description: "Quiet, typographic and spacious — hairline rules with a single touch of colour.",
      tags: ["Clean", "Monochrome"]),
    SuTemplate(
      id: "corporate", name: "Corporate",
      description: "Structured and businesslike, with a bold title block and boxed details.",
      tags: ["Business", "Structured"]),
    SuTemplate(
      id: "elegant", name: "Elegant",
      description: "Refined serif letterhead with fine double rules — ideal for premium services.",
      tags: ["Serif", "Premium"]),
    SuTemplate(
      id: "bold", name: "Bold",
      description: "Big, confident type with a dark summary band — makes the amount due impossible to miss.",
      tags: ["Striking", "Dark"]),
    SuTemplate(
      id: "classic", name: "Classic",
      description: "Traditional boxed layout with ruled tables — familiar to every accounts department.",
      tags: ["Traditional", "Structured"]),
    SuTemplate(
      id: "creative", name: "Creative",
      description: "Playful geometric accents and rounded cards — friendly but still professional.",
      tags: ["Colorful", "Friendly"]),
    SuTemplate(
      id: "compact", name: "Compact",
      description: "Dense, efficient layout that fits many line items per page — great for itemised services.",
      tags: ["Many items", "Efficient"]),
    SuTemplate(
      id: "gradient", name: "Gradient",
      description: "Vibrant gradient header in your brand colour, with the logo on a clean white card.",
      tags: ["Colorful", "Modern"]),
    SuTemplate(
      id: "mono", name: "Mono",
      description: "Technical look with a dark header, grid lines and monospaced figures.", tags: ["Technical", "Dark"]),
  ]

  static let defaultId = "modern"
}

/// The company's design of a type of document (`template-resolve.ts`).
struct SuDesign {
  let company: JSONValue?
  let type: String

  private var branding: JSONValue? { company?.obj("branding") }
  /// The type's own design; none for invoices, and for the others until they have one.
  private var own: JSONValue? { type == "invoice" ? nil : branding?.obj("byType")?.obj(type) }

  /// Quotes and credit notes print like invoices until they have a design of their own.
  var sameAsInvoices: Bool { type != "invoice" && own == nil }
  var templateId: String { own?.text("templateId") ?? branding?.text("templateId") ?? SuTemplate.defaultId }
  var accent: String { own?.text("accentColor") ?? branding?.text("accentColor") ?? "" }
  var layout: JSONValue? { own?.obj("layout") ?? branding?.obj("layout") }
}

/// `/templates`: the design of each type of document and the gallery.
struct SuTemplatesPage: View {
  @Environment(AppModel.self) private var model
  @State private var type = "invoice"
  @State private var language = ""

  var body: some View {
    let role = SuRole(model)
    let company = model.one.company
    WebPage(spacing: 24, refresh: { [model] in await model.one.sync() }) {
      PageHeader(
        t("Templates"),
        description: t(
          "Pick the look of your invoices, quotes and credit notes. You can also choose a template per document.")
      )
      .padding(.bottom, -24)
      if suLoading(model, empty: company == nil) {
        SuLoadingCard()
      } else {
        if role.role == .staff {
          SuNote(
            text: t("Owners, admins and accountants choose the design of documents. You can look at it."), icon: .lock)
        }
        VStack(alignment: .leading, spacing: 16) {
          Segmented(
            selection: $type,
            options: [
              SegmentOption("invoice", t("Invoices")), SegmentOption("quote", t("Quotes")),
              SegmentOption("credit", t("Credit notes")),
            ])
          SuDesignCard(design: SuDesign(company: company, type: type))
          SwSameAsInvoicesSwitch(type: type)
        }
        SuEveryDocumentCard(company: company)
        SuGallery(design: SuDesign(company: company, type: type), language: languageBinding(company))
      }
    }
  }

  /// The previews' language: the company's documents' first, until another is picked.
  private func languageBinding(_ company: JSONValue?) -> Binding<String> {
    let documents = company?.str("language") ?? ""
    let initial = documents == "ar" || documents == "ar-en" ? documents : "en"
    return Binding(
      get: { language.isEmpty ? initial : language },
      set: { language = $0 })
  }
}

/// A card of settings as the web lays them out: its title and description,
/// then label–value rows.
struct SuValuesCard: View {
  let title: String
  var description: String?
  let rows: [InfoRow]
  @Environment(\.palette) private var palette

  init(_ title: String, description: String? = nil, rows: [InfoRow]) {
    self.title = title
    self.description = description
    self.rows = rows
  }

  var body: some View {
    Card {
      CardHeader(title, description: description)
      VStack(spacing: 0) {
        ForEach(rows.indices, id: \.self) { index in
          line(rows[index], first: index == 0)
        }
      }
      .padding(.vertical, 4)
    }
  }

  private func line(_ item: InfoRow, first: Bool) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(item.label)
        .font(.web(14))
        .foregroundStyle(palette.slate(500))
      Spacer(minLength: 8)
      Text(item.value.isEmpty ? "—" : item.value)
        .font(.web(14, item.strong ? .semibold : .regular, tabular: item.tabular))
        .foregroundStyle(item.tone.map { palette.color($0) } ?? palette.slate(item.value.isEmpty ? 400 : 900))
        .multilineTextAlignment(.trailing)
        .textSelection(.enabled)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 11)
    .overlay(alignment: .top) {
      if !first { Rectangle().fill(palette.slate(100)).frame(height: 1) }
    }
  }
}

/// On or off, in words.
func suOnOff(_ on: Bool) -> String { on ? t("Switched on") : t("Switched off") }

/// The design of the type: same as invoices, colour, logo and layout.
private struct SuDesignCard: View {
  let design: SuDesign
  @Environment(\.palette) private var palette

  var body: some View {
    let kind = design.type
    let title = kind == "quote" ? t("Quote design") : kind == "credit" ? t("Credit note design") : t("Invoice design")
    let description =
      kind == "invoice"
      ? t(
        "Proformas, orders and delivery notes print like invoices, and so do quotes and credit notes until they have a design of their own."
      )
      : t(
        "Documents downloaded again later print with the design set here, unless they have a template or colour of their own."
      )
    SuValuesCard(title, description: description, rows: rows)
  }

  private var rows: [InfoRow] {
    let layout = design.layout
    var list: [InfoRow] = []
    if design.type != "invoice" {
      list.append(InfoRow(t("Same as invoices"), suOnOff(design.sameAsInvoices)))
    }
    let template = SuTemplate.all.first { $0.id == design.templateId }
    list.append(InfoRow(t("Template"), template.map { t($0.name) } ?? design.templateId))
    list.append(InfoRow(t("Brand colour"), design.accent))
    list.append(InfoRow(t("Logo size"), logoSize(layout?.text("logoSize"))))
    list.append(InfoRow(t("Logo position"), logoPosition(layout?.text("logoPosition"))))
    list.append(InfoRow(t("SKU column"), suOnOff(layout?.flag("showSku") ?? false)))
    list.append(InfoRow(t("Item pictures"), suOnOff(layout?.flag("showItemImages") ?? false)))
    if design.type != "credit" {
      list.append(InfoRow(t("Customer acceptance box"), suOnOff(layout?.flag("showAcceptance") ?? false)))
    }
    return list
  }

  private func logoSize(_ value: String?) -> String {
    switch value {
    case "small": t("Small")
    case "large": t("Large")
    default: t("Medium (as designed)")
    }
  }

  private func logoPosition(_ value: String?) -> String {
    switch value {
    case "start": t("On top, left")
    case "center": t("On top, centred")
    case "end": t("On top, right")
    default: t("Where the template puts it")
    }
  }
}

/// What every document prints: the font, the stamp, the amount in words,
/// the Hijri date and the QR code.
private struct SuEveryDocumentCard: View {
  let company: JSONValue?

  var body: some View {
    SuValuesCard(t("On every document"), rows: rows)
  }

  private var rows: [InfoRow] {
    let branding = company?.obj("branding")
    let defaults = company?.obj("defaults")
    let payment = company?.obj("payment")
    let qr = payment?.flag("showQrCode") ?? false
    return [
      InfoRow(t("Font"), font(branding?.text("fontId"))),
      InfoRow(t("Paid and void stamp"), suOnOff(branding?.flag("showStatusStamp") ?? false)),
      InfoRow(t("Amount in words"), suOnOff(amountInWords(defaults))),
      InfoRow(t("Hijri date"), suOnOff(defaults?.flag("showHijriDate") ?? false)),
      InfoRow(t("The QR code opens"), qr ? qrContent(defaults?.text("qrContent")) : ""),
      InfoRow(t("Print a QR code"), suOnOff(qr)),
    ]
  }

  /// Missing means on for Kuwaiti companies (`showsAmountInWords`).
  private func amountInWords(_ defaults: JSONValue?) -> Bool {
    if let own = defaults?["showAmountInWords"]?.bool { return own }
    let country = company?.obj("address")?.str("country") ?? ""
    return country == "KW" || (company?.str("currency") ?? "KWD") == "KWD"
  }

  private func font(_ id: String?) -> String {
    switch id {
    case "inter": t("Inter (modern sans)")
    case "manrope": t("Manrope (geometric sans)")
    case "plexsans": t("IBM Plex Sans (technical)")
    case "spacegrotesk": t("Space Grotesk (bold)")
    case "lora": t("Lora (classic serif)")
    default: t("Template default")
    }
  }

  private func qrContent(_ value: String?) -> String {
    value == "pay_page" ? t("The invoice’s pay page (with online payments)") : t("The payment link")
  }
}

/// The designs, each with its thumbnail in the language picked, the one in use marked.
private struct SuGallery: View {
  let design: SuDesign
  @Binding var language: String
  @Environment(\.palette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 12) {
        Text(t("Designs")).webText(.cardTitle)
        Spacer(minLength: 0)
      }
      Segmented(
        selection: $language,
        options: [SegmentOption("en", "English"), SegmentOption("ar", "العربية"), SegmentOption("ar-en", t("Bilingual"))],
        small: true)
      ForEach(SuTemplate.all) { template in
        SuTemplateCard(
          template: template, active: template.id == design.templateId, language: language, type: design.type)
      }
      Text(t("Thumbnails show sample data. Previews use your logo, colour and details."))
        .font(.web(14))
        .foregroundStyle(palette.slate(500))
    }
  }
}

private struct SuTemplateCard: View {
  let template: SuTemplate
  let active: Bool
  let language: String
  var type = "invoice"
  @Environment(\.palette) private var palette

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.lg, style: .continuous)
    Card {
      thumbnail
        .overlay(alignment: .bottom) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(t(template.name)).font(.web(16, .semibold)).foregroundStyle(palette.slate(900))
          Spacer(minLength: 0)
          if !active {
            SwUseTemplateButton(template: template, type: type)
          }
          if active {
            HStack(spacing: 4) {
              IconView(.circleCheck, size: 12)
              Text(t("Default"))
            }
            .font(.web(12, .medium))
            .foregroundStyle(palette[.blue(700)])
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(palette[.blue(50)], in: Capsule())
          }
        }
        Text(t(template.description)).font(.web(14)).foregroundStyle(palette.slate(500))
        FlowLayout(spacing: 4, lineSpacing: 4) {
          ForEach(template.tags, id: \.self) { tag in
            Text(t(tag))
              .font(.web(12))
              .foregroundStyle(palette.slate(600))
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(palette.slate(100), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
          }
        }
        .padding(.top, 8)
      }
      .padding(16)
    }
    .overlay {
      if active { shape.strokeBorder(palette.primary(500), lineWidth: 2) }
    }
  }

  /// The thumbnail the web keeps in `public/templates` (`modern-ar.jpg`), bundled with the app.
  private var thumbnail: some View {
    Group {
      if let image = SwTemplates.thumbnail(template.id, language: language) {
        Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
      } else {
        palette.slate(100)
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: 300, alignment: .top)
    .clipped()
    .background(palette.slate(100))
    .accessibilityLabel(Text(t("{name} invoice template", ["name": t(template.name)])))
  }

}
