import Foundation
import Testing

@testable import MahamKit

/// src/cloud/letter-roles.test.ts: employee letters, as records_guard and
/// can_delete_record decide them on the device.
@Suite("Letter roles")
struct LetterRolesTests {
  static let draft: JSONValue = ["id": "let-1", "status": "draft", "number": "", "body": "Text"]
  static let issued = draft.with(["status": "issued", "number": "HR-2026-0001", "body": "Done"])

  @Test("issue for the owner, admins and approvers; everyone on a company kept here")
  func issuers() {
    #expect(Roles.issuesLetters(.owner, false))
    #expect(Roles.issuesLetters(.admin, false))
    #expect(Roles.issuesLetters(.accountant, true))
    #expect(!Roles.issuesLetters(.accountant, false))
    #expect(!Roles.issuesLetters(.staff, true))
    #expect(Roles.issuesLetters(nil, nil))
    #expect(Roles.switchesLetters(.admin))
    #expect(!Roles.switchesLetters(.accountant))
    #expect(Roles.lettersSwitchedOn(["letters": true]))
    #expect(!Roles.lettersSwitchedOn(["letters": "true"]))
    #expect(!Roles.lettersSwitchedOn(nil))
  }

  @Test("refuse what records_guard refuses")
  func refusals() {
    let draft = Self.draft
    let issued = Self.issued
    // Anyone who may write letters drafts.
    #expect(Roles.letterWriteRefusal(nil, draft, issuer: false) == nil)
    #expect(Roles.letterWriteRefusal(draft, draft.with(["body": "Other"]), issuer: false) == nil)
    // Only issuers issue, change or void.
    #expect(Roles.letterWriteRefusal(draft, issued, issuer: false) == .issuer)
    #expect(Roles.letterWriteRefusal(nil, issued, issuer: false) == .issuer)
    #expect(Roles.letterWriteRefusal(issued, issued.with(["body": "Other"]), issuer: false) == .issuer)
    #expect(Roles.letterWriteRefusal(issued, issued.with(["status": "void"]), issuer: false) == .issuer)
    #expect(Roles.letterWriteRefusal(draft, issued, issuer: true) == nil)
    // Marking it printed, or sending it again as it is, is anyone's.
    #expect(
      Roles.letterWriteRefusal(issued, issued.with(["printedAt": "now", "updatedAt": "x"]), issuer: false) == nil)
    #expect(Roles.letterWriteRefusal(issued, issued, issuer: false) == nil)
    // Never back to a draft, not even for the owner.
    #expect(Roles.letterWriteRefusal(issued, draft, issuer: true) == .issued)
    #expect(Roles.letterWriteRefusal(issued.with(["status": "void"]), draft, issuer: true) == .issued)
    #expect(Roles.letterWriteRefusal(issued, nil, issuer: false) == nil)
  }

  @Test("keep issued and void letters, and drop nulls and print marks from what they say")
  func kept() {
    #expect(!Roles.letterKept(Self.draft))
    #expect(Roles.letterKept(Self.issued))
    #expect(Roles.letterKept(Self.issued.with(["status": "void"])))
    #expect(!Roles.letterKept([:]))
    #expect(
      Roles.letterContent(Self.issued.with(["printedAt": "x", "updatedAt": "y", "voidReason": .null])) == Self.issued)
  }

  @Test("keep the switch for anyone but the owner and admins")
  func lettersSwitch() {
    #expect(
      Roles.keepLettersSwitch(.accountant, ["letters": true], ["reminderDays": []]) == [
        "reminderDays": [], "letters": true,
      ])
    #expect(Roles.keepLettersSwitch(.accountant, [:], ["letters": true]) == [:])
    #expect(Roles.keepLettersSwitch(.accountant, nil, ["letters": true]) == [:])
    #expect(Roles.keepLettersSwitch(.admin, ["letters": true], [:]) == [:])
  }

  @Test("keep an issued letter as issued and a void one void, as records_guard stores them")
  func issuedKept() {
    let draft = Self.draft
    let issued = Self.issued
    let voided = issued.with(["status": "void", "voidReason": "Wrong", "voidedOn": "2026-10-21"])
    // A copy that hasn't heard of the void, printed: still void, the print noted.
    #expect(
      Roles.keepIssuedLetter(voided, issued.with(["printedAt": "2026-10-22T08:00:00.000Z", "updatedAt": "u"]))
        == voided.with(["printedAt": "2026-10-22T08:00:00.000Z", "updatedAt": "u"]))
    // The later of two prints is kept.
    #expect(
      Roles.keepIssuedLetter(
        issued.with(["printedAt": "2026-10-22T09:00:00.000Z"]), issued.with(["printedAt": "2026-10-22T08:00:00.000Z"]))
        == issued.with(["printedAt": "2026-10-22T09:00:00.000Z"]))
    // Issued again elsewhere with another number: the first stays.
    #expect(Roles.keepIssuedLetter(issued, issued.with(["number": "HR-2026-0002", "body": "Other"])) == issued)
    // Voided, with why and when; voided again, the first void stays.
    #expect(
      Roles.keepIssuedLetter(
        issued,
        issued.with([
          "number": "HR-2026-0002", "status": "void", "voidReason": "Wrong", "voidedOn": "2026-10-21",
        ])) == voided)
    #expect(Roles.keepIssuedLetter(voided, voided.with(["voidReason": "Other"])) == voided)
    // Drafts and new letters pass as they are.
    #expect(Roles.keepIssuedLetter(draft, issued) == issued)
    #expect(Roles.keepIssuedLetter(nil, issued) == issued)
  }

  @Test("keep the People settings with the letters on from anyone but the owner and admins")
  func peopleSettings() {
    #expect(Roles.peopleSettingsKept(.accountant, ["letters": true]))
    #expect(!Roles.peopleSettingsKept(.accountant, ["reminderDays": []]))
    #expect(!Roles.peopleSettingsKept(.admin, ["letters": true]))
    #expect(!Roles.peopleSettingsKept(.owner, ["letters": true]))
    #expect(!Roles.peopleSettingsKept(nil, ["letters": true]))
  }
}
