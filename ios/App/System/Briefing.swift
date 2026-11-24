import MahamKit
import SwiftUI

#if canImport(FoundationModels)
  import FoundationModels
#endif

/// Your day in three or four sentences, written by Apple Intelligence, on
/// Home. It runs entirely on this device: the system's on-device language
/// model (FoundationModels) reads the tasks and figures below, and nothing
/// is sent to Maham One, to Apple or anywhere else. Employees' names are
/// never in the prompt. The day's briefing is kept on this iPhone so it
/// isn't written again on every visit; the refresh button writes a new one.
struct BriefingCard: View {
  @Environment(AppModel.self) private var model
  @AppStorage(Preferences.briefingKey) private var enabled = true
  @State private var text: String?
  @State private var isWriting = false
  @State private var failed = false

  var body: some View {
    if enabled {
      switch BriefingAvailability.current {
      case .available:
        card
      case .deviceNotEligible:
        note("Day briefings need a device that supports Apple Intelligence.")
      case .intelligenceOff:
        note("Turn on Apple Intelligence in Settings to get a short briefing of your day here.")
      case .notReady:
        note("Apple Intelligence is getting ready on this device. Your day briefing will be here soon.")
      case .unavailable:
        note("Day briefings aren't available on this device.")
      }
    }
  }

  // MARK: The card

  private var card: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Label {
          Text("Your day")
        } icon: {
          Image(systemName: "sparkles")
            .foregroundStyle(Color.purple)
            .symbolRenderingMode(.hierarchical)
        }
        .font(.headline)
        Spacer(minLength: 8)
        if text != nil, !isWriting {
          Button("Write again", systemImage: "arrow.clockwise") { write() }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(Color.purple)
        }
      }

      if isWriting {
        HStack(spacing: 10) {
          ProgressView()
          Text("Writing your briefing…")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
      } else if let text {
        Text(text)
          .font(.callout)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      } else {
        Group {
          if failed {
            Text("Apple Intelligence couldn't write a briefing just now.")
          } else {
            Text("A few sentences on what's late, what's due and how the company stands.")
          }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        Button {
          write()
        } label: {
          if failed {
            Label("Try again", systemImage: "arrow.clockwise")
          } else {
            Label("Summarize my day", systemImage: "sparkles")
          }
        }
        .buttonStyle(.glassProminent)
        .tint(Color.purple)
      }

      Text("Written on this iPhone by Apple Intelligence. Nothing leaves the device.")
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
    .glassCard(tint: Color.purple)
    .animation(.smooth, value: isWriting)
    .task(id: cacheKey) {
      text = BriefingCache.load(cacheKey)
      failed = false
    }
  }

  /// A quiet line instead of the card, when the model can't run here.
  private func note(_ message: LocalizedStringKey) -> some View {
    Label(message, systemImage: "sparkles")
      .font(.footnote)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 4)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: Writing

  /// Today's briefing for this account, in this language.
  private var cacheKey: String {
    BriefingCache.key(
      user: model.session?.user.id, language: BriefingPrompt.language, day: LocalDate(Date()))
  }

  private func write() {
    guard !isWriting else { return }
    let key = cacheKey
    let instructions = BriefingPrompt.instructions()
    let facts = BriefingPrompt.facts(model)
    isWriting = true
    failed = false
    Task {
      do {
        let answer = try await BriefingWriter.write(instructions: instructions, prompt: facts)
        text = answer
        BriefingCache.save(answer, key: key)
      } catch {
        failed = true
      }
      isWriting = false
    }
  }
}

// MARK: The model

/// Whether the on-device model can run, in the card's own words.
private enum BriefingAvailability {
  case available, deviceNotEligible, intelligenceOff, notReady, unavailable

  static var current: BriefingAvailability {
    #if canImport(FoundationModels)
      switch SystemLanguageModel.default.availability {
      case .available:
        return .available
      case .unavailable(.deviceNotEligible):
        return .deviceNotEligible
      case .unavailable(.appleIntelligenceNotEnabled):
        return .intelligenceOff
      case .unavailable(.modelNotReady):
        return .notReady
      case .unavailable:
        return .unavailable
      @unknown default:
        return .unavailable
      }
    #else
      return .unavailable
    #endif
  }
}

/// One answer from the on-device model, off the main thread. A new session
/// each time: a briefing needs no memory of the last one.
private enum BriefingWriter {
  struct Unavailable: Error {}

  static func write(instructions: String, prompt: String) async throws -> String {
    #if canImport(FoundationModels)
      let answer = try await Task.detached(priority: .userInitiated) { () async throws -> String in
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt)
        return response.content
      }.value
      let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { throw Unavailable() }
      return trimmed
    #else
      throw Unavailable()
    #endif
  }
}

/// What the model is told and given: the day's facts in plain English (the
/// model answers in the app's language), from the tasks you can see and the
/// company's totals. Counts and amounts only for the company: no employee,
/// client or document names.
@MainActor
private enum BriefingPrompt {
  /// "ar" when the app is in Arabic, else "en".
  static var language: String {
    (Bundle.main.preferredLocalizations.first ?? "en").hasPrefix("ar") ? "ar" : "en"
  }

  static func instructions() -> String {
    let answerIn = language == "ar" ? "Write in Modern Standard Arabic." : "Write in English."
    return """
      You write a short briefing of a person's working day for Maham One, a business app \
      with tasks, invoices and company documents.
      Use only the facts you are given. Never invent tasks, names, amounts, dates or advice \
      the facts don't support, and don't guess at anything missing.
      Write 3 or 4 short sentences of plain text: no greeting, no list, no headings, no markdown.
      Start with what is overdue, then what is due today, then how the company stands. \
      If there is nothing to do, say so kindly.
      Keep task titles exactly as given.
      \(answerIn)
      """
  }

  static func facts(_ model: AppModel, now: Date = Date()) -> String {
    var lines: [String] = ["Today is \(day(now)). The time now is \(time(now))."]

    let tasks = model.tasks
    if tasks.notInTasks {
      lines.append("The person is not in Maham Tasks, so there are no tasks.")
    } else {
      let plan = tasks.plan
      lines.append("Overdue tasks: \(plan.overdue.count).")
      lines += plan.overdue.prefix(8).map { line($0, overdue: true) }
      lines.append("Tasks still due today: \(plan.today.count).")
      lines += plan.today.prefix(8).map { line($0, overdue: false) }
      lines.append("Tasks finished today: \(plan.doneToday.count).")
      if let next = plan.upcoming.first, let due = next.dueAt {
        lines.append("The next task after today: \"\(next.title)\", due \(day(due)).")
      }
    }

    let business = model.business
    if business.company != nil {
      let summary = business.summary
      lines.append(
        "Open invoices: \(summary.openInvoices), with \(business.format(summary.receivable)) still to be paid.")
      lines.append(
        "Overdue invoices: \(summary.overdueInvoices), \(business.format(summary.overdueAmount)) in total.")
      lines.append(
        "Company documents and employee papers expired or expiring within 30 days: \(summary.expiringSoon.count).")
    }
    return lines.joined(separator: "\n")
  }

  /// `- "Title", due 3:00 PM, high priority`.
  private static func line(_ task: TaskItem, overdue: Bool) -> String {
    var parts = ["\"\(task.title)\""]
    if let due = task.dueAt {
      parts.append(overdue ? "was due \(day(due)) at \(time(due))" : "due at \(time(due))")
    }
    parts.append("\(task.priority.title.lowercased()) priority")
    return "- " + parts.joined(separator: ", ")
  }

  private static let english = Locale(identifier: "en_US")

  private static func day(_ date: Date) -> String {
    date.formatted(Date.FormatStyle(date: .complete, time: .omitted).locale(english))
  }

  private static func time(_ date: Date) -> String {
    date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(english))
  }
}

/// The day's briefing on this iPhone: one per account, language and day.
/// Older ones are removed when a new one is saved.
enum BriefingCache {
  private static let prefix = "dayBriefing."

  static func key(user: String?, language: String, day: LocalDate) -> String {
    "\(prefix)\(user ?? "anyone").\(language).\(day.description)"
  }

  static func load(_ key: String) -> String? {
    UserDefaults.standard.string(forKey: key)
  }

  static func save(_ text: String, key: String) {
    clear(keeping: key)
    UserDefaults.standard.set(text, forKey: key)
  }

  /// Every saved briefing (on signing out).
  static func clear() {
    clear(keeping: nil)
  }

  private static func clear(keeping key: String?) {
    let defaults = UserDefaults.standard
    for old in defaults.dictionaryRepresentation().keys where old.hasPrefix(prefix) && old != key {
      defaults.removeObject(forKey: old)
    }
  }
}
