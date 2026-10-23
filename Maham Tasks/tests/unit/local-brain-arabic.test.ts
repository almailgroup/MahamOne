/**
 * The fallback brain, asked in Kuwaiti Arabic.
 *
 * This is what answers when Gemini cannot be reached, so it is the floor
 * rather than the feature — but a floor that only understands Modern
 * Standard Arabic understands nobody in this office. Somebody typing
 * "شنو المتأخر" and somebody typing "ما هي المهام المتأخرة" are asking the
 * same question.
 */

import { describe, expect, test } from "vitest";

import { answerLocally } from "@/lib/assistant/local-brain";
import { createTranslator } from "@/lib/i18n";
import type { AssistantSnapshot } from "@/lib/assistant/types";

const arabic = createTranslator("ar");

const DAY = 86_400_000;
const iso = (offsetDays: number) =>
  new Date(Date.now() + offsetDays * DAY).toISOString();

const snapshot: AssistantSnapshot = {
  viewer: { name: "Admin", role: "admin", canManage: true },
  projects: [],
  team: [],
  locale: "ar",
  timeZone: "Asia/Kuwait",
  takenAt: new Date().toISOString(),
  tasks: [
    {
      id: "t1",
      title: "Ship the catalogue",
      status: "todo",
      priority: "high",
      project: null,
      dueAt: iso(-3),
      followUpAt: null,
      assignees: [],
      createdAt: iso(-20),
    },
    {
      id: "t2",
      title: "مراجعة العقد",
      status: "in_review",
      priority: "medium",
      project: null,
      dueAt: iso(5),
      followUpAt: null,
      assignees: ["Sara"],
      createdAt: iso(-10),
    },
  ],
  counts: {
    total: 2,
    todo: 1,
    inProgress: 0,
    inReview: 1,
    done: 0,
    overdue: 1,
    dueToday: 0,
    unassigned: 1,
    noDueDate: 0,
  },
};

/** The answer is in Arabic script, not a dictionary miss falling back to English. */
const isArabic = (text: string) => /[ء-ي]/.test(text);

describe("asking the fallback brain in Kuwaiti", () => {
  test("شنو المتأخر finds the overdue task", () => {
    const { text } = answerLocally("شنو المتأخر عندي؟", snapshot, arabic);
    expect(text).toContain("Ship the catalogue");
    expect(isArabic(text)).toBe(true);
  });

  test("standard Arabic for the same thing still works", () => {
    const { text } = answerLocally("ما هي المهام المتأخرة؟", snapshot, arabic);
    expect(text).toContain("Ship the catalogue");
  });

  test("چم and شلون reach the summary", () => {
    // Not by counting digits: Arabic has a dual, so two tasks is "مهمتان"
    // rather than "2 tasks", and the dictionary is right to say so.
    //
    // Nor by one status label — the "I cannot answer that" line lists the
    // questions it *can* take, which includes the one about review, so that
    // assertion passed whether or not the Kuwaiti word had matched. All four
    // labels on one line is the summary and nothing else.
    const labels = (["todo", "in_progress", "in_review", "done"] as const).map(
      (status) => arabic.t(`status.${status}`),
    );
    for (const question of ["چم مهمة عندنا؟", "شلون الوضع؟"]) {
      const { text } = answerLocally(question, snapshot, arabic);
      for (const label of labels) expect(text, `${question} → ${label}`).toContain(label);
      expect(isArabic(text), question).toBe(true);
    }
  });

  test("شنو أسوي reaches what to work on next", () => {
    const { text } = answerLocally("شنو أسوي الحين؟", snapshot, arabic);
    expect(text).toContain("Ship the catalogue");
  });

  test("a task titled in Arabic is listed under review, by its own title", () => {
    const { text } = answerLocally("شنو بانتظار المراجعة؟", snapshot, arabic);
    expect(text).toContain("مراجعة العقد");
  });

  test("an English question still gets the English answer", () => {
    const english = createTranslator("en");
    const { text } = answerLocally("what is overdue?", snapshot, english);
    expect(text).toContain("Ship the catalogue");
    expect(isArabic(text)).toBe(false);
  });
});
