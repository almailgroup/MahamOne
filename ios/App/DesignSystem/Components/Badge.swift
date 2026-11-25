import SwiftUI

/// The badge colours of `src/lib/status.ts`.
enum StatusTone: String, Sendable, CaseIterable {
  case gray, slate, blue, amber, green, red, violet
}

/// A status's English label (an i18n key: show it with `t(meta.label)`) and tone.
struct StatusMeta: Hashable, Sendable {
  let label: String
  let tone: StatusTone

  /// A status this version doesn't know (saved by a newer one).
  static let unknown = StatusMeta(label: "Unknown status", tone: .gray)

  /// A document's status as shown (`displayStatus`: with "overdue",
  /// "expired" and "open"), from `STATUS_META`.
  static func document(_ status: String) -> StatusMeta {
    switch status {
    case "draft": StatusMeta(label: "Draft", tone: .gray)
    case "sent": StatusMeta(label: "Sent", tone: .blue)
    case "partial": StatusMeta(label: "Partially paid", tone: .amber)
    case "paid": StatusMeta(label: "Paid", tone: .green)
    case "void": StatusMeta(label: "Void", tone: .slate)
    case "overdue": StatusMeta(label: "Overdue", tone: .red)
    case "accepted": StatusMeta(label: "Accepted", tone: .green)
    case "declined": StatusMeta(label: "Declined", tone: .red)
    case "invoiced": StatusMeta(label: "Invoiced", tone: .violet)
    case "expired": StatusMeta(label: "Expired", tone: .amber)
    case "applied": StatusMeta(label: "Applied", tone: .green)
    case "open": StatusMeta(label: "Open", tone: .blue)
    case "converted": StatusMeta(label: "Converted", tone: .violet)
    case "confirmed": StatusMeta(label: "Confirmed", tone: .blue)
    case "partially_invoiced": StatusMeta(label: "Partially invoiced", tone: .amber)
    case "issued": StatusMeta(label: "Issued", tone: .blue)
    case "partially_billed": StatusMeta(label: "Partially billed", tone: .amber)
    case "billed": StatusMeta(label: "Billed", tone: .violet)
    case "delivered": StatusMeta(label: "Delivered", tone: .green)
    case "cancelled": StatusMeta(label: "Cancelled", tone: .slate)
    default: .unknown
    }
  }

  /// A sales order's delivery progress (not delivered when it has none).
  static func delivery(_ status: String?) -> StatusMeta {
    switch status ?? "not_delivered" {
    case "not_delivered": StatusMeta(label: "Not delivered", tone: .gray)
    case "partially_delivered": StatusMeta(label: "Partially delivered", tone: .amber)
    case "delivered": StatusMeta(label: "Delivered", tone: .green)
    default: .unknown
    }
  }

  /// A cheque's status; a cheque the company wrote is "Issued" while held.
  static func cheque(_ status: String, outgoing: Bool = false) -> StatusMeta {
    switch status {
    case "held": outgoing ? StatusMeta(label: "Issued", tone: .blue) : StatusMeta(label: "In hand", tone: .blue)
    case "deposited": StatusMeta(label: "Deposited", tone: .violet)
    case "cleared": StatusMeta(label: "Cleared", tone: .green)
    case "returned": StatusMeta(label: "Returned", tone: .red)
    case "cancelled": StatusMeta(label: "Cancelled", tone: .slate)
    default: .unknown
    }
  }

  /// A security cheque's status.
  static func securityCheque(_ status: String) -> StatusMeta {
    switch status {
    case "held": StatusMeta(label: "Held as security", tone: .amber)
    case "returned": StatusMeta(label: "Given back", tone: .slate)
    case "cashed": StatusMeta(label: "Cashed", tone: .green)
    default: .unknown
    }
  }
}

/// The web's `Badge`: fully rounded, 8×2pt padding, 12pt weight 500, a 1pt
/// ring inside, in one of the status tones.
struct Badge: View {
  let text: String
  var tone: StatusTone
  @Environment(\.palette) private var palette

  init(_ text: String, tone: StatusTone = .gray) {
    self.text = text
    self.tone = tone
  }

  /// A status badge (`StatusBadge` on the web): its translated label and tone.
  init(status: StatusMeta) {
    self.init(t(status.label), tone: status.tone)
  }

  var body: some View {
    Text(text)
      .font(.web(12, .medium))
      .lineLimit(1)
      .fixedSize()
      .frame(minHeight: 16)
      .foregroundStyle(colors.text)
      .padding(.horizontal, 8)
      .padding(.vertical, 2)
      .background(colors.fill, in: Capsule())
      .border(colors.ring, in: Capsule())
  }

  private var colors: (fill: Color, text: Color, ring: Color) {
    switch tone {
    case .gray: (palette.slate(100), palette.slate(700), palette.slate(500).opacity(0.1))
    case .slate: (palette.slate(200), palette.slate(700), palette.slate(500).opacity(0.2))
    case .blue: (palette[.blue(50)], palette[.blue(700)], palette[.blue(600)].opacity(0.15))
    case .amber: (palette[.amber(50)], palette[.amber(800)], palette[.amber(600)].opacity(0.2))
    case .green: (palette[.emerald(50)], palette[.emerald(700)], palette[.emerald(600)].opacity(0.2))
    case .red: (palette[.red(50)], palette[.red(700)], palette[.red(600)].opacity(0.15))
    case .violet: (palette[.violet(50)], palette[.violet(700)], palette[.violet(600)].opacity(0.15))
    }
  }
}

/// "Beta" or "View only" under an app: a small slate-100 pill, 11pt.
struct Pill: View {
  let text: String
  @Environment(\.palette) private var palette

  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text)
      .font(.web(11, .medium))
      .lineLimit(1)
      .fixedSize()
      .foregroundStyle(palette.slate(600))
      .padding(.horizontal, 6)
      .padding(.vertical, 1)
      .background(palette.slate(100), in: Capsule())
  }
}
