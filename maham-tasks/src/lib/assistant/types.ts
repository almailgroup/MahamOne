/**
 * The AI assistant — shared types.
 *
 * Deliberately free of React and of Supabase: the same shapes travel from the
 * chat panel, through the Server Action, to the Cloudflare Worker that will
 * front Gemini. Keeping them in one plain module is what lets the Worker be
 * dropped in without touching the UI.
 */

import type { Locale } from "@/lib/i18n";
import type {
  TaskPriority,
  TaskStatus,
} from "@/lib/supabase/database.types";

export type AssistantRole = "user" | "assistant";


/** A task flattened to what the assistant needs to talk about it. */
export type AssistantTask = {
  id: string;
  title: string;
  status: TaskStatus;
  priority: TaskPriority;
  project: string | null;
  dueAt: string | null;
  followUpAt: string | null;
  assignees: string[];
  createdAt: string;
};

/**
 * Everything the assistant knows when it answers, gathered under the caller's own
 * permissions. A member's snapshot holds only the tasks assigned to them,
 * because row-level security already scopes the query that builds it — the
 * assistant inherits the permission model rather than re-implementing it.
 */
export type AssistantSnapshot = {
  /** Who is asking, so the answer can say "you" and mean it. */
  viewer: {
    name: string;
    role: string;
    /** Whether this person may create and change tasks at all. */
    canManage: boolean;
  };
  /** The projects a task can be filed under, by id, for proposing one. */
  projects: { id: string; name: string }[];
  /** Who a task can be assigned to, by id. */
  team: { id: string; name: string }[];
  /**
   * The interface language — a setting somebody chose once, not what they
   * have just typed. It decides the reply only when the question itself says
   * nothing: see `replyIn`.
   */
  locale: Locale;
  /**
   * The language to answer in, worked out from the question.
   *
   * The panel is read in Arabic as often as in English, and the two do not
   * follow the interface: somebody running it in English types a question in
   * Arabic and is owed an Arabic answer. Absent from a snapshot built for the
   * local brain, which is handed its translator directly.
   */
  replyIn?: Locale;
  /**
   * The reader's IANA zone. Without it "what is due today" is unanswerable
   * from a list of instants — the same task is today in Dubai and tomorrow
   * in London.
   */
  timeZone: string;
  /** ISO instant the snapshot was taken, for relative phrasing. */
  takenAt: string;
  tasks: AssistantTask[];
  counts: {
    total: number;
    todo: number;
    inProgress: number;
    inReview: number;
    done: number;
    overdue: number;
    dueToday: number;
    unassigned: number;
    noDueDate: number;
  };
};

/** What the chat panel sends. */
export type AssistantRequest = {
  /** Full turn history, oldest first, including the question just asked. */
  messages: AssistantMessage[];
};

/**
 * Something the assistant would like to do, if the person agrees.
 *
 * Deliberately loose on the wire: a language model can return anything, and
 * the portal validates every field against a schema before it goes near the
 * database. Nothing here is trusted — it is a proposal, not an instruction.
 */
export type AssistantAction = {
  name: string;
  arguments: Record<string, unknown>;
  /**
   * The same proposal in words, resolved against the snapshot before it
   * leaves the server. Display only — what actually runs is `arguments`,
   * re-validated at the point of use.
   */
  preview?: { heading: string; rows: { label: string; value: string }[] } | null;
};

export type AssistantMessage = {
  id: string;
  role: AssistantRole;
  text: string;
  /** ISO instant. Rendered in the viewer's timezone after hydration. */
  at: string;
  /** A change the assistant would like to make, awaiting a decision. */
  action?: AssistantAction | null;
  /**
   * What became of it. `undefined` means the question has not been put yet —
   * which is also every message that never carried a proposal.
   */
  outcome?: "done" | "dismissed";
};

/** What comes back. `source` says which brain answered. */
export type AssistantAnswer = {
  text: string;
  source: "gemini" | "local";
  /**
   * Present when the model wants to change something. Nothing has happened
   * yet: the panel shows it, the person confirms, and only then does the
   * portal run it — through the same Server Action the buttons use.
   */
  action?: AssistantAction | null;
};
