/**
 * Which language the assistant answers in.
 *
 * The interface language is a setting somebody chose once. The language of
 * the question is what they are speaking now, and that is the one that should
 * decide — including for somebody running the English interface who types in
 * Arabic, which is the whole point of this.
 */

import { describe, expect, test } from "vitest";

import { answerLanguage, arabicShare } from "@/lib/assistant/language";

describe("answering in the language of the question", () => {
  test("Arabic in, Arabic out — even on the English interface", () => {
    expect(answerLanguage("شنو المهام المتأخرة؟", "en")).toBe("ar");
    expect(answerLanguage("كم مهمة عندي اليوم", "en")).toBe("ar");
  });

  test("English in, English out — even on the Arabic interface", () => {
    expect(answerLanguage("what is overdue?", "ar")).toBe("en");
    expect(answerLanguage("show me today's tasks", "ar")).toBe("en");
  });

  test("Arabic about an English task title is still Arabic", () => {
    // The board is bilingual: somebody asks in Arabic about a task called
    // "Ship the catalogue". Counting the title's letters as English would
    // answer them in the wrong language.
    expect(answerLanguage("شنو حالة Ship the catalogue؟", "en")).toBe("ar");
  });

  test("English about an Arabic project name is still English", () => {
    expect(answerLanguage("is مشروع الكويت done?", "en")).toBe("en");
  });

  test("a question with no letters falls back to the interface", () => {
    expect(answerLanguage("3?", "ar")).toBe("ar");
    expect(answerLanguage("3?", "en")).toBe("en");
    expect(answerLanguage("   ", "ar")).toBe("ar");
  });

  test("Arabic-Indic digits alone are not Arabic writing", () => {
    // ٣ is a digit. Somebody typing "٣؟" has not written a word.
    expect(arabicShare("٣")).toBe(0);
  });

  test("Kuwaiti spellings count as Arabic like any other", () => {
    for (const q of ["شنو عندي باجر؟", "شلون الوضع", "چم مهمة متأخرة"]) {
      expect(answerLanguage(q, "en"), q).toBe("ar");
    }
  });

  test("the share is letters only, so punctuation cannot tip it", () => {
    expect(arabicShare("!!! ??? ...")).toBe(0);
    expect(arabicShare("متأخر")).toBe(1);
  });
});
