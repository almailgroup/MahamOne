import { isDueToday, isOverdue } from "@/lib/dates";
import { statusMeta } from "@/lib/constants";
import { createTranslator, type Translator } from "@/lib/i18n";
import type { AssistantAnswer, AssistantSnapshot, AssistantTask } from "@/lib/assistant/types";

/**
 * The assistant's placeholder brain.
 *
 * It answers the handful of tracking questions that can be resolved by
 * counting rows, and says plainly when a question needs the language model.
 * This is not a stand-in for Gemini — it is the floor: once the Cloudflare
 * Worker is wired up, everything here stays as the offline fallback for when
 * that call fails, so the panel is never simply dead.
 *
 * Pure, and free of server imports, so it runs in the action, in a test, or
 * inside the Worker itself. It answers in the asker's language: the intents
 * are matched against words from both, and every sentence comes from the
 * dictionary.
 *
 * The Arabic words below are Kuwaiti as well as standard, because that is how
 * the people using this write. Somebody typing "شنو المتأخر" and somebody
 * typing "ما هي المهام المتأخرة" are asking the same thing, and only one of
 * them was being understood.
 */

type Speaker = Pick<Translator, "t" | "tn" | "tag" | "timeZone">;
const english: Speaker = createTranslator("en");

function dueLabel(task: AssistantTask, { t, tag, timeZone }: Speaker): string {
  if (!task.dueAt) return t("brain.noDueDate");
  const due = new Date(task.dueAt);
  return t("brain.due", {
    date: due.toLocaleDateString(tag, { timeZone, day: "numeric", month: "short" }),
  });
}

/** "Ship the catalogue — In Progress, due 14 Sep (Gemellry)" */
function describe(task: AssistantTask, i18n: Speaker): string {
  const bits = [i18n.t(statusMeta(task.status).label), dueLabel(task, i18n)];
  if (task.project) bits.push(task.project);
  return `${task.title} — ${bits.join(", ")}`;
}

function list(tasks: AssistantTask[], i18n: Speaker, limit = 8): string {
  const shown = tasks.slice(0, limit).map((task) => `• ${describe(task, i18n)}`);
  if (tasks.length > limit) {
    shown.push(i18n.t("brain.andMore", { n: tasks.length - limit }));
  }
  return shown.join("\n");
}

const answer = (text: string): AssistantAnswer => ({ text, source: "local" });

/** Every word in one of these groups has to appear for the intent to match. */
const matches = (question: string, ...groups: string[][]) =>
  groups.some((group) => group.every((word) => question.includes(word)));

export function answerLocally(
  question: string,
  snapshot: AssistantSnapshot,
  i18n: Speaker = english,
  /**
   * Whether a language model is wired up at all.
   *
   * It changes only the two lines that explain themselves, and it matters:
   * once Gemini is connected, "my language model is not connected" sends
   * somebody off to re-check a configuration that was right all along. The
   * honest version of the same sentence is that it could not be reached.
   */
  modelConfigured = false,
): AssistantAnswer {
  const { t, tn } = i18n;
  const q = question.toLowerCase().trim();
  const { counts, tasks } = snapshot;
  const open = tasks.filter((task) => task.status !== "done");

  if (tasks.length === 0) {
    return answer(t("brain.noTasks"));
  }

  // Overdue ------------------------------------------------------------
  if (
    matches(
      q,
      ["overdue"],
      ["late"],
      ["past", "due"],
      ["behind"],
      ["متأخر"],
      ["تأخر"],
      ["فات"],
      ["متأخرة"],
      ["مأخر"],
      ["طفس"],
    )
  ) {
    const overdue = tasks.filter((task) => isOverdue(task.dueAt, task.status));
    if (overdue.length === 0) {
      return answer(t("brain.nothingOverdue"));
    }
    return answer(`${tn("brain.overdueList", overdue.length)}\n\n${list(overdue, i18n)}`);
  }

  // Due today ----------------------------------------------------------
  if (
    matches(
      q,
      ["due", "today"],
      ["today"],
      ["due", "now"],
      ["اليوم"],
      ["هاليوم"],
      ["هاللحين"],
    )
  ) {
    const today = open.filter((task) => isDueToday(task.dueAt, i18n.timeZone));
    // A task due at 09:00 this morning is both due today and overdue. It
    // belongs under today's heading, once — so the overdue section below
    // covers only the days already behind us.
    const todayIds = new Set(today.map((task) => task.id));
    const earlier = tasks.filter(
      (task) => isOverdue(task.dueAt, task.status) && !todayIds.has(task.id),
    );

    if (today.length === 0 && earlier.length === 0) {
      return answer(t("brain.nothingTodayOrOverdue"));
    }

    const parts: string[] = [
      today.length > 0
        ? `${t("brain.dueTodayHeading", { tasks: tn("count.tasks", today.length) })}\n\n${list(today, i18n)}`
        : t("brain.nothingToday"),
    ];
    if (earlier.length > 0) {
      parts.push(
        `\n${t("brain.overdueBefore", { tasks: tn("count.tasks", earlier.length) })}\n\n${list(earlier, i18n)}`,
      );
    }
    return answer(parts.join("\n"));
  }

  // Review queue -------------------------------------------------------
  if (
    matches(
      q,
      ["review"],
      ["waiting"],
      ["approve"],
      ["approval"],
      ["مراجعة"],
      ["اعتماد"],
      ["موافقة"],
      ["ينتظر"],
      ["مراجعه"],
      ["منتظر"],
    )
  ) {
    const inReview = tasks.filter((task) => task.status === "in_review");
    if (inReview.length === 0) {
      return answer(t("brain.nothingInReview"));
    }
    return answer(`${tn("brain.inReviewList", inReview.length)}\n\n${list(inReview, i18n)}`);
  }

  // Unassigned ---------------------------------------------------------
  if (
    matches(
      q,
      ["unassigned"],
      ["nobody"],
      ["no", "one"],
      ["not", "assigned"],
      ["غير مسند"],
      ["بدون مكلف"],
      ["لا أحد"],
      ["محد"],
      ["ماكو أحد"],
      ["ما عليه"],
    )
  ) {
    const unassigned = open.filter((task) => task.assignees.length === 0);
    if (unassigned.length === 0) {
      return answer(t("brain.everyoneAssigned"));
    }
    return answer(
      `${tn("brain.unassignedList", unassigned.length)}\n\n${list(unassigned, i18n)}`,
    );
  }

  // Follow-ups ---------------------------------------------------------
  if (
    matches(q, ["follow"], ["chase"], ["remind"], ["متابع"], ["تذكير"], ["تابع"])
  ) {
    const followUps = open
      .filter((task) => task.followUpAt !== null)
      .sort((a, b) => (a.followUpAt ?? "").localeCompare(b.followUpAt ?? ""));
    if (followUps.length === 0) {
      return answer(t("brain.noFollowUps"));
    }
    return answer(
      `${tn("brain.followUpList", followUps.length)}\n\n${list(followUps, i18n)}`,
    );
  }

  // What should I work on ----------------------------------------------
  if (
    matches(
      q,
      ["what", "next"],
      ["work", "on"],
      ["priorit"],
      ["my", "task"],
      ["assigned", "me"],
      ["start"],
      ["أعمل"],
      ["أبدأ"],
      ["أولوي"],
      ["مهامي"],
      ["تالي"],
      ["اشتغل"],
      ["وش أسوي"],
      ["شنو أسوي"],
      ["شسوي"],
      ["الجاي"],
    )
  ) {
    const weight = (task: AssistantTask) => {
      if (isOverdue(task.dueAt, task.status)) return 0;
      if (isDueToday(task.dueAt, i18n.timeZone)) return 1;
      if (task.priority === "urgent") return 2;
      if (task.priority === "high") return 3;
      return task.dueAt ? 4 : 5;
    };
    const ordered = [...open].sort(
      (a, b) =>
        weight(a) - weight(b) || (a.dueAt ?? "9999").localeCompare(b.dueAt ?? "9999"),
    );
    if (ordered.length === 0) {
      return answer(t("brain.nothingOpen"));
    }
    return answer(`${t("brain.workNext")}\n\n${list(ordered, i18n, 6)}`);
  }

  // Summary / counts ---------------------------------------------------
  if (
    matches(
      q,
      ["how", "many"],
      ["summary"],
      ["status"],
      ["overview"],
      ["progress"],
      ["count"],
      ["where", "we"],
      ["stand"],
      ["كم"],
      ["ملخص"],
      ["حالة"],
      ["نظرة"],
      ["تقدم"],
      ["عدد"],
      ["أين", "نحن"],
      ["چم"],
      ["شلون"],
      ["الوضع"],
      ["وين", "وصلنا"],
    )
  ) {
    const lines = [
      t("brain.summaryLine", { tasks: tn("count.tasks", counts.total), done: counts.done }),
      [
        `${t("status.todo")} ${counts.todo}`,
        `${t("status.in_progress")} ${counts.inProgress}`,
        `${t("status.in_review")} ${counts.inReview}`,
        `${t("status.done")} ${counts.done}`,
      ].join(" · "),
    ];
    if (counts.overdue > 0) lines.push(tn("brain.overdueCount", counts.overdue));
    if (counts.dueToday > 0) lines.push(tn("brain.dueTodayCount", counts.dueToday));
    if (counts.unassigned > 0) lines.push(tn("brain.noAssigneeCount", counts.unassigned));
    if (counts.noDueDate > 0) lines.push(tn("brain.noDueDateCount", counts.noDueDate));
    return answer(lines.join("\n"));
  }

  // Capabilities -------------------------------------------------------
  if (
    matches(
      q,
      ["help"],
      ["what", "can", "you"],
      ["who", "are", "you"],
      ["مساعدة"],
      ["ماذا", "تستطيع"],
      ["من", "أنت"],
      ["ساعدني"],
      ["شنو تسوي"],
      ["وش تسوي"],
      ["منو انت"],
    )
  ) {
    return answer(
      t(modelConfigured ? "brain.helpOffline" : "brain.help", {
        q1: t("assistant.starter.overdue"),
        q2: t("assistant.starter.today"),
        q3: t("assistant.starter.next"),
        q4: t("assistant.starter.review"),
        q5: t("assistant.starter.summary"),
      }),
    );
  }

  // Fallback -----------------------------------------------------------
  return answer(t(modelConfigured ? "brain.fallbackOffline" : "brain.fallback"));
}
