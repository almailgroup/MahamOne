import Charts
import MahamKit
import SwiftUI

/// What was invoiced in each of the last six months (drafts and void
/// invoices left out), by issue date. Touch a bar to read its month.
struct InvoicedByMonthChart: View {
  @Environment(AppModel.self) private var model
  @State private var selected: String?

  init() {}

  /// One month's bar.
  struct MonthTotal: Identifiable, Equatable {
    /// "2026-11".
    let id: String
    /// "Nov", under the bar.
    let label: String
    /// "November 2026", for the headline and VoiceOver.
    let title: String
    let total: Double
  }

  var body: some View {
    let business = model.business
    let months = Self.months(business.invoices, today: business.today)
    let picked = months.first { $0.label == selected }
    let sum = months.reduce(0.0) { $0 + $1.total }
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        if let picked {
          Text(picked.title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
          Text(business.format(picked.total))
            .font(.title3.weight(.bold))
            .monospacedDigit()
        } else {
          Text("Last 6 months")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
          Text(business.format(sum))
            .font(.title3.weight(.bold))
            .monospacedDigit()
        }
      }
      .accessibilityElement(children: .combine)

      if sum <= 0 {
        Text("Nothing invoiced in the last 6 months.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 80)
      } else {
        Chart(months) { month in
          BarMark(
            x: .value("Month", month.label),
            y: .value("Invoiced", month.total)
          )
          .foregroundStyle(Color.accentColor.gradient)
          .cornerRadius(6)
          .opacity(selected == nil || selected == month.label ? 1.0 : 0.4)
          .accessibilityLabel(Text(month.title))
          .accessibilityValue(Text(business.format(month.total)))
        }
        .chartYAxis {
          AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
              .foregroundStyle(Color.secondary.opacity(0.35))
            AxisValueLabel {
              if let amount = value.as(Double.self) {
                Text(amount, format: .number.notation(.compactName))
              }
            }
          }
        }
        .chartXAxis {
          AxisMarks { _ in
            AxisValueLabel()
          }
        }
        .chartXSelection(value: $selected)
        .frame(height: 190)
        .sensoryFeedback(Haptics.pick, trigger: selected)
      }
    }
  }

  /// The six months up to this one, oldest first.
  static func months(_ invoices: [SalesDocument], today: LocalDate) -> [MonthTotal] {
    var totals: [String: Double] = [:]
    for invoice in invoices where invoice.status != .draft && invoice.status != .void {
      guard let issued = invoice.issueDate else { continue }
      totals["\(issued.year)-\(issued.month)", default: 0] += invoice.totals.total
    }
    return (0..<6).reversed().map { back -> MonthTotal in
      var year = today.year
      var month = today.month - back
      while month < 1 {
        month += 12
        year -= 1
      }
      let key = "\(year)-\(month)"
      let start = LocalDate(year: year, month: month, day: 15).start(in: .current)
      return MonthTotal(
        id: key,
        label: start.formatted(.dateTime.month(.abbreviated)),
        title: start.formatted(.dateTime.month(.wide).year()),
        total: totals[key] ?? 0)
    }
  }
}
