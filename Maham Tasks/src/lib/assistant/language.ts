/**
 * Which language the assistant should answer a question in.
 *
 * The app's own language is a setting somebody chose once; the language of
 * the question is what they are speaking right now. Somebody running the
 * English interface who types in Arabic is speaking Arabic, and being
 * answered in English is the assistant not listening.
 *
 * Pure, so the same rule can be applied in the server action, in a test, and
 * anywhere else a turn is handled.
 */

/**
 * Arabic letters. Deliberately not the Arabic-Indic digits ٠-٩: a digit is a
 * digit, and somebody typing "٣؟" has not written a word in any language.
 */
const ARABIC = /[ء-يٮ-ۓۺ-ۿ]/;
const LATIN = /[A-Za-z]/;
const ARABIC_G = new RegExp(ARABIC.source, "g");
const LATIN_G = new RegExp(LATIN.source, "g");

/** How much of a question is written in Arabic, from 0 to 1. Letters only. */
export function arabicShare(text: string): number {
  const arabic = (text.match(ARABIC_G) ?? []).length;
  const latin = (text.match(LATIN_G) ?? []).length;
  const letters = arabic + latin;
  return letters === 0 ? 0 : arabic / letters;
}

/**
 * The language to reply in.
 *
 * Decided by the script the question *starts* in, not by counting letters.
 * A board in this workspace is bilingual — Arabic questions about tasks
 * titled in English, English questions about projects named in Arabic — and
 * those two are mirror images of each other, around a third of one script
 * and two thirds of the other. No ratio separates them. Which script somebody
 * opened their sentence in does, because that is the language they are
 * speaking; the other one is a name they are quoting.
 *
 * With no letters at all — "3?" — there is nothing to go on, so the interface
 * language stands.
 *
 * Known limit: a question that opens by quoting a name in the other script,
 * "Ship the catalogue شنو حالته؟", is read as the script of the name. Rare
 * enough to be worth the simplicity, and never wrong about a question written
 * wholly in one language.
 */
export function answerLanguage(
  question: string,
  uiLocale: "en" | "ar",
): "en" | "ar" {
  for (const character of question) {
    if (ARABIC.test(character)) return "ar";
    if (LATIN.test(character)) return "en";
  }
  return uiLocale;
}
