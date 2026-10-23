import type { TaskStatus } from "@/lib/supabase/database.types";

/**
 * Changes made with no connection, kept on this device until there is one.
 *
 * Only the things people do on the move are kept: moving a task along,
 * putting it off, ticking a step, and saying something on it. Each records
 * who made it, so a phone handed to somebody else never sends one person's
 * change as another's; it waits for its owner to sign in again.
 *
 * Kept in localStorage: small, synchronous, there on an iPhone home-screen
 * app, and it survives the app being closed with no signal.
 */

type Base = { id: string; at: string; owner: string };

export type OutboxChange =
  | { kind: "move"; taskId: string; projectId: string | null; status: TaskStatus; position: number; title: string }
  | { kind: "status"; taskId: string; projectId: string | null; status: TaskStatus; title: string }
  | { kind: "reschedule"; taskId: string; projectId: string | null; dueAt: string | null; title: string }
  | { kind: "checklist"; taskId: string; itemId: string; done: boolean }
  | { kind: "comment"; taskId: string; content: string };

export type OutboxItem = Base & OutboxChange;

export const OUTBOX_KEY = "almail-outbox-v1";
/** Fired on window whenever this tab changes the outbox. */
export const OUTBOX_EVENT = "almail-outbox";

type Store = Pick<Storage, "getItem" | "setItem">;

function storage(): Store | null {
  try {
    return typeof window === "undefined" ? null : window.localStorage;
  } catch {
    return null;
  }
}

export function readOutbox(store: Store | null = storage()): OutboxItem[] {
  try {
    const raw = store?.getItem(OUTBOX_KEY);
    const parsed: unknown = raw ? JSON.parse(raw) : [];
    return Array.isArray(parsed) ? (parsed as OutboxItem[]) : [];
  } catch {
    return [];
  }
}

function writeOutbox(items: OutboxItem[], store: Store | null = storage()) {
  try {
    store?.setItem(OUTBOX_KEY, JSON.stringify(items));
  } catch {
    // Full or blocked: the change is lost, which the caller has already
    // been told is possible by the offline bar. Nothing better to do here.
  }
  if (typeof window !== "undefined") window.dispatchEvent(new Event(OUTBOX_EVENT));
}

/**
 * The same change twice is one change: a task moved three times offline is
 * sent once, where it ended up; a step ticked and unticked, once, as it was
 * left. Comments are each their own.
 */
function sameTarget(a: OutboxItem, b: OutboxChange & { owner: string }): boolean {
  if (a.owner !== b.owner) return false;
  if ((a.kind === "move" || a.kind === "status") && (b.kind === "move" || b.kind === "status")) {
    return a.taskId === b.taskId;
  }
  if (a.kind === "reschedule" && b.kind === "reschedule") return a.taskId === b.taskId;
  if (a.kind === "checklist" && b.kind === "checklist") return a.itemId === b.itemId;
  return false;
}

export function keepChange(
  change: OutboxChange & { owner: string },
  { store = storage(), now = new Date(), id = randomId() }: { store?: Store | null; now?: Date; id?: string } = {},
): OutboxItem {
  const item = { ...change, id, at: now.toISOString() } as OutboxItem;
  const rest = readOutbox(store).filter((existing) => !sameTarget(existing, change));
  writeOutbox([...rest, item], store);
  return item;
}

export function dropChange(id: string, store: Store | null = storage()) {
  writeOutbox(
    readOutbox(store).filter((item) => item.id !== id),
    store,
  );
}

/** One person's changes, oldest first: the order they were made. */
export function changesFor(owner: string, items: OutboxItem[]): OutboxItem[] {
  return items.filter((item) => item.owner === owner).sort((a, b) => a.at.localeCompare(b.at));
}

/**
 * What a task looks like with this person's unsent changes applied, so a
 * card shows where it was moved to rather than springing back.
 */
export function withPending<T extends { id: string; status: TaskStatus; due_at: string | null }>(
  tasks: T[],
  pending: OutboxItem[],
): (T & { unsent?: true })[] {
  if (pending.length === 0) return tasks;
  return tasks.map((task) => {
    let next: T & { unsent?: true } = task;
    for (const item of pending) {
      if (!("taskId" in item) || item.taskId !== task.id) continue;
      if (item.kind === "move" || item.kind === "status") next = { ...next, status: item.status, unsent: true };
      if (item.kind === "reschedule") next = { ...next, due_at: item.dueAt, unsent: true };
    }
    return next;
  });
}

/**
 * Whether a failed call failed for want of a connection, rather than being
 * refused. Browsers word it differently — "Failed to fetch", Safari's "Load
 * failed", "NetworkError" — and `navigator.onLine` is believable only when
 * it says false.
 */
export function isNetworkFailure(error: unknown, online: boolean = typeof navigator === "undefined" || navigator.onLine): boolean {
  if (!online) return true;
  const message = error instanceof Error ? error.message : String(error ?? "");
  return /failed to fetch|load failed|networkerror|network request failed|fetch failed/i.test(message);
}

function randomId(): string {
  try {
    return crypto.randomUUID();
  } catch {
    return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
  }
}
