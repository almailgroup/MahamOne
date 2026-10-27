import { describe, expect, it } from "vitest";

import {
  changesFor,
  dropChange,
  isNetworkFailure,
  keepChange,
  OUTBOX_KEY,
  readOutbox,
  withPending,
} from "@/lib/outbox";

function memory() {
  const data = new Map<string, string>();
  return {
    getItem: (key: string) => data.get(key) ?? null,
    setItem: (key: string, value: string) => void data.set(key, value),
    raw: () => data.get(OUTBOX_KEY),
  };
}

const at = (minute: number) => new Date(Date.UTC(2026, 9, 17, 9, minute));

describe("the outbox", () => {
  it("keeps changes in the order they were made, per person", () => {
    const store = memory();
    keepChange({ kind: "comment", taskId: "t1", content: "first", owner: "sara" }, { store, now: at(1), id: "a" });
    keepChange({ kind: "comment", taskId: "t1", content: "theirs", owner: "omar" }, { store, now: at(2), id: "b" });
    keepChange({ kind: "comment", taskId: "t1", content: "second", owner: "sara" }, { store, now: at(3), id: "c" });

    expect(changesFor("sara", readOutbox(store)).map((item) => item.id)).toEqual(["a", "c"]);
    expect(changesFor("omar", readOutbox(store)).map((item) => item.id)).toEqual(["b"]);
  });

  it("sends a task moved three times once, where it ended up", () => {
    const store = memory();
    const move = { kind: "move", taskId: "t1", projectId: null, position: 1, title: "T", owner: "sara" } as const;
    keepChange({ ...move, status: "in_progress" }, { store, now: at(1), id: "a" });
    keepChange({ kind: "status", taskId: "t1", projectId: null, status: "in_review", title: "T", owner: "sara" }, { store, now: at(2), id: "b" });
    keepChange({ ...move, status: "done" }, { store, now: at(3), id: "c" });

    const kept = readOutbox(store);
    expect(kept).toHaveLength(1);
    expect(kept[0]).toMatchObject({ id: "c", status: "done" });
  });

  it("keeps a step as it was left, and every comment", () => {
    const store = memory();
    keepChange({ kind: "checklist", taskId: "t1", itemId: "s1", done: true, owner: "sara" }, { store, id: "a" });
    keepChange({ kind: "checklist", taskId: "t1", itemId: "s1", done: false, owner: "sara" }, { store, id: "b" });
    keepChange({ kind: "comment", taskId: "t1", content: "one", owner: "sara" }, { store, id: "c" });
    keepChange({ kind: "comment", taskId: "t1", content: "two", owner: "sara" }, { store, id: "d" });
    expect(readOutbox(store).map((item) => item.id)).toEqual(["b", "c", "d"]);
  });

  it("does not merge one person's change into another's", () => {
    const store = memory();
    const move = { kind: "move", taskId: "t1", projectId: null, position: 1, title: "T", status: "done" } as const;
    keepChange({ ...move, owner: "sara" }, { store, id: "a" });
    keepChange({ ...move, owner: "omar" }, { store, id: "b" });
    expect(readOutbox(store)).toHaveLength(2);
  });

  it("forgets a change once it is sent", () => {
    const store = memory();
    keepChange({ kind: "comment", taskId: "t1", content: "x", owner: "sara" }, { store, id: "a" });
    dropChange("a", store);
    expect(readOutbox(store)).toEqual([]);
  });

  it("survives a corrupted store", () => {
    const store = memory();
    store.setItem(OUTBOX_KEY, "{not json");
    expect(readOutbox(store)).toEqual([]);
  });
});

describe("tasks with unsent changes", () => {
  const tasks = [
    { id: "t1", status: "todo" as const, due_at: null },
    { id: "t2", status: "todo" as const, due_at: null },
  ];

  it("show where they were moved and when they are now due", () => {
    const shown = withPending(tasks, [
      { id: "a", at: "", owner: "sara", kind: "move", taskId: "t1", projectId: null, status: "done", position: 1, title: "" },
      { id: "b", at: "", owner: "sara", kind: "reschedule", taskId: "t1", projectId: null, dueAt: "2026-10-18T14:00:00Z", title: "" },
    ]);
    expect(shown[0]).toMatchObject({ status: "done", due_at: "2026-10-18T14:00:00Z", unsent: true });
    expect(shown[1]).toEqual(tasks[1]);
  });
});

describe("telling no connection from a refusal", () => {
  it("knows each browser's way of saying it", () => {
    expect(isNetworkFailure(new TypeError("Failed to fetch"), true)).toBe(true);
    expect(isNetworkFailure(new TypeError("Load failed"), true)).toBe(true);
    expect(isNetworkFailure(new TypeError("NetworkError when attempting to fetch resource."), true)).toBe(true);
    expect(isNetworkFailure(new Error("Only a manager or admin can mark a task done."), true)).toBe(false);
  });

  it("believes the browser when it says it is offline", () => {
    expect(isNetworkFailure(new Error("anything"), false)).toBe(true);
  });
});
