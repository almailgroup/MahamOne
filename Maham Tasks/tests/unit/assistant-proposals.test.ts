/**
 * What the assistant proposes, and what the portal does with it.
 *
 * Two halves, and the split is the point. `previewOf` turns a proposal into
 * the words somebody reads before agreeing to it; `runAssistantAction` decides
 * whether it runs at all. Neither trusts the model: the first refuses to
 * describe what it cannot resolve, and the second refuses to run what it
 * cannot parse — so a confident but wrong tool call reaches the database in
 * neither case.
 */

import { beforeEach, describe, expect, test, vi } from "vitest";

import { previewOf } from "@/lib/assistant/preview";
import { createTranslator } from "@/lib/i18n";
import type { AssistantSnapshot } from "@/lib/assistant/types";

const TASK = "11111111-1111-4111-8111-111111111111";
const PROJECT = "22222222-2222-4222-8222-222222222222";
const PERSON = "33333333-3333-4333-8333-333333333333";

const snapshot: AssistantSnapshot = {
  viewer: { name: "Admin", role: "admin", canManage: true },
  projects: [{ id: PROJECT, name: "Freight" }],
  team: [{ id: PERSON, name: "Sara Khan" }],
  locale: "en",
  timeZone: "Asia/Dubai",
  takenAt: "2026-09-15T10:00:00.000Z",
  tasks: [
    {
      id: TASK,
      title: "Chase customs",
      status: "todo",
      priority: "high",
      project: "Freight",
      dueAt: "2026-09-14T13:00:00.000Z",
      followUpAt: null,
      assignees: ["Sara Khan"],
      createdAt: "2026-09-01T06:00:00.000Z",
    },
  ],
  counts: {
    total: 1, todo: 1, inProgress: 0, inReview: 0, done: 0,
    overdue: 1, dueToday: 0, unassigned: 0, noDueDate: 0,
  },
};

const en = createTranslator("en", "Asia/Dubai");
const ar = createTranslator("ar", "Asia/Dubai");

const rowFor = (
  preview: { rows: { label: string; value: string }[] },
  label: string,
) => preview.rows.find((row) => row.label === label)?.value;

describe("previewOf", () => {
  test("names what the model referred to by id", () => {
    const preview = previewOf(
      {
        name: "create_task",
        arguments: {
          title: "File the manifest",
          projectId: PROJECT,
          assigneeIds: [PERSON],
          dueAt: "2026-09-20T13:00:00.000Z",
        },
      },
      snapshot,
      en,
    );

    expect(preview).not.toBeNull();
    expect(rowFor(preview!, en.t("sort.project"))).toBe("Freight");
    expect(rowFor(preview!, en.t("table.assignees"))).toBe("Sara Khan");
    // 13:00 UTC is 5 in the afternoon where this is read. A card showing the
    // instant would be asking somebody to agree to a different time.
    expect(rowFor(preview!, en.t("meta.dueDate"))).toMatch(/5:00/);
  });

  test("a due date read in Arabic is still the reader's clock", () => {
    const preview = previewOf(
      { name: "reschedule_task", arguments: { taskId: TASK, dueAt: "2026-09-20T13:00:00.000Z" } },
      { ...snapshot, locale: "ar" },
      ar,
    );
    // Latin digits are pinned in localeTag, so the hour is comparable.
    expect(rowFor(preview!, ar.t("meta.dueDate"))).toMatch(/5:00/);
  });

  test("an unknown task cannot be described, so it is not offered", () => {
    expect(
      previewOf(
        { name: "set_task_status", arguments: { taskId: "not-a-task", status: "done" } },
        snapshot,
        en,
      ),
    ).toBeNull();
  });

  test("a tool this version does not have is not described either", () => {
    expect(
      previewOf({ name: "delete_everything", arguments: {} }, snapshot, en),
    ).toBeNull();
  });
});

// The Server Actions the proposal delegates to. Stubbed, because what is under
// test is what reaches them — not what they do, which is covered where they live.
const createTask = vi.fn(async () => ({ ok: true as const, data: { id: TASK } }));
const changeTaskStatus = vi.fn(async () => ({ ok: true as const, data: { status: "done" } }));
const rescheduleTask = vi.fn(async () => ({ ok: true as const, data: { dueAt: null } }));

vi.mock("@/lib/data/task-actions", () => ({
  createTask: (...args: unknown[]) => createTask(...(args as [])),
  changeTaskStatus: (...args: unknown[]) => changeTaskStatus(...(args as [])),
  rescheduleTask: (...args: unknown[]) => rescheduleTask(...(args as [])),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    from: () => ({
      select: () => ({
        eq: () => ({ maybeSingle: async () => ({ data: { project_id: PROJECT } }) }),
      }),
    }),
  }),
}));

const { runAssistantAction } = await import("@/lib/data/assistant-run");

describe("runAssistantAction", () => {
  beforeEach(() => {
    createTask.mockClear();
    changeTaskStatus.mockClear();
    rescheduleTask.mockClear();
  });

  test("a sound proposal goes to the same action a click would", async () => {
    const result = await runAssistantAction({
      name: "create_task",
      arguments: {
        title: "File the manifest",
        projectId: PROJECT,
        assigneeIds: [PERSON],
        dueAt: "2026-09-20T13:00:00.000Z",
        priority: "high",
      },
    });

    expect(result.ok).toBe(true);
    const [projectId, , form] = createTask.mock.calls[0] as unknown as [string, unknown, FormData];
    expect(projectId).toBe(PROJECT);
    expect(form.get("title")).toBe("File the manifest");
    expect(form.getAll("assigneeIds")).toEqual([PERSON]);
    expect(form.get("priority")).toBe("high");
    // Unsaid is not unset-in-the-model's-favour: the ordinary defaults apply.
    expect(form.get("status")).toBe("todo");
  });

  test("an id that is not an id never reaches a query", async () => {
    const result = await runAssistantAction({
      name: "set_task_status",
      arguments: { taskId: "'; drop table tasks; --", status: "done" },
    });

    expect(result).toEqual({ ok: false, error: "assistant.badProposal" });
    expect(changeTaskStatus).not.toHaveBeenCalled();
  });

  test("a status the board does not have is refused", async () => {
    const result = await runAssistantAction({
      name: "set_task_status",
      arguments: { taskId: TASK, status: "archived" },
    });

    expect(result).toEqual({ ok: false, error: "assistant.badProposal" });
    expect(changeTaskStatus).not.toHaveBeenCalled();
  });

  test("a title that is only whitespace is not a task", async () => {
    const result = await runAssistantAction({
      name: "create_task",
      arguments: { title: "   " },
    });

    expect(result).toEqual({ ok: false, error: "assistant.badProposal" });
    expect(createTask).not.toHaveBeenCalled();
  });

  test("clearing a due date is allowed; an unparseable one is not", async () => {
    expect(
      (await runAssistantAction({
        name: "reschedule_task",
        arguments: { taskId: TASK, dueAt: null },
      })).ok,
    ).toBe(true);
    expect(rescheduleTask.mock.calls[0]).toEqual([TASK, PROJECT, null]);

    expect(
      await runAssistantAction({
        name: "reschedule_task",
        arguments: { taskId: TASK, dueAt: "next tuesday" },
      }),
    ).toEqual({ ok: false, error: "assistant.badProposal" });
    expect(rescheduleTask).toHaveBeenCalledTimes(1);
  });

  test("a tool nobody declared runs nothing", async () => {
    const result = await runAssistantAction({ name: "delete_project", arguments: { id: PROJECT } });
    expect(result).toEqual({ ok: false, error: "assistant.unknownAction" });
    expect(createTask).not.toHaveBeenCalled();
    expect(changeTaskStatus).not.toHaveBeenCalled();
    expect(rescheduleTask).not.toHaveBeenCalled();
  });
});
