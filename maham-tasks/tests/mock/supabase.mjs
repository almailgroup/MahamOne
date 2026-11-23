/**
 * Enough Supabase to run the app without one.
 *
 * The end-to-end specs need a backend that answers like PostgREST and GoTrue
 * and keeps what it is told, so a spec can create a task and then find it on
 * the board. A real Supabase cannot do that job: it is shared, it is slow to
 * reset between specs, and pointing tests at the production project is the
 * one thing this repository must never do.
 *
 * What it is NOT: an authority. Row-level security lives in the migrations
 * and is verified against a real Postgres, never here — this server answers
 * every request as the signed-in user and enforces nothing. A spec that
 * passes here proves the interface works, not that the rules hold.
 *
 *   node tests/mock/supabase.mjs        # :54999, 5ms per call
 *   PORT=1234 LATENCY_MS=120 node …     # somewhere else, production-ish
 */
import { createServer } from "node:http";
import { randomUUID } from "node:crypto";

import { IDS, NOW, seed } from "./seed.mjs";

const PORT = Number(process.env.PORT ?? 54999);
const LATENCY = Number(process.env.LATENCY_MS ?? 5);

/**
 * Who a request is from.
 *
 * Sign-in hands back a token carrying the id of whoever's address was typed,
 * and every later request carries that token, so a spec signs in as a member
 * and is one — which is what makes a role-shaped check possible at all.
 */
const DEFAULT_USER = process.env.MOCK_USER_ID ?? IDS.admin;

function actor(request) {
  const header = request.headers.authorization ?? "";
  const token = header.replace(/^Bearer /i, "");
  const payload = token.split(".")[1];
  if (!payload) return DEFAULT_USER;
  try {
    const claims = JSON.parse(Buffer.from(payload, "base64url").toString());
    return typeof claims.sub === "string" ? claims.sub : DEFAULT_USER;
  } catch {
    return DEFAULT_USER;
  }
}

let db = seed();

/**
 * How rows reach each other, as PostgREST would know it from foreign keys:
 * table -> column -> the table it points at.
 */
const FK = {
  tasks: { project_id: "projects", created_by: "profiles", milestone_id: "project_milestones" },
  task_assignments: { task_id: "tasks", user_id: "profiles" },
  // `user_id`, as in the schema. This said `author_id` — a column comments
  // have never had — so every comment in the mock came back authorless.
  comments: { task_id: "tasks", user_id: "profiles" },
  comment_reactions: { comment_id: "comments", user_id: "profiles" },
  task_activity: { task_id: "tasks", actor_id: "profiles" },
  task_attachments: { task_id: "tasks", created_by: "profiles" },
  notifications: { user_id: "profiles", actor_id: "profiles", task_id: "tasks", conversation_id: "conversations" },
  project_members: { project_id: "projects", user_id: "profiles" },
  personal_notes: { user_id: "profiles" },
  personal_note_items: { note_id: "personal_notes" },
  personal_note_shares: { note_id: "personal_notes", user_id: "profiles" },
  team_messages: { author_id: "profiles" },
  direct_messages: { conversation_id: "conversations", author_id: "profiles" },
  conversation_participants: { conversation_id: "conversations", user_id: "profiles" },
  reminder_queue: { task_id: "tasks", user_id: "profiles" },
  app_errors: { user_id: "profiles" },
  task_checklist_items: { task_id: "tasks", created_by: "profiles" },
  push_subscriptions: { user_id: "profiles" },
  notification_preferences: { user_id: "profiles" },
  project_status_updates: { project_id: "projects", author_id: "profiles" },
  labels: { created_by: "profiles" },
  task_labels: { task_id: "tasks", label_id: "labels" },
  task_dependencies: { task_id: "tasks", blocked_by: "tasks", created_by: "profiles" },
  task_templates: { created_by: "profiles" },
  project_milestones: { project_id: "projects", created_by: "profiles" },
};

/**
 * Computed columns: Postgres functions on a row that PostgREST lets a select
 * name like a column. Same answers, worked out here.
 */
const COMPUTED = {
  tasks: {
    // public.waiting_on(tasks): open, unbinned tasks this one waits on.
    waiting_on: (row) =>
      (db.task_dependencies ?? []).filter((link) => {
        if (link.task_id !== row.id) return false;
        const blocker = db.tasks.find((task) => task.id === link.blocked_by);
        return blocker && blocker.status !== "done" && !blocker.deleted_at;
      }).length,
  },
};

// ---------------------------------------------------------------------------
// Reading
// ---------------------------------------------------------------------------

/** Split on commas that are not inside parentheses. */
function topLevelSplit(text) {
  const parts = [];
  let depth = 0;
  let current = "";
  for (const character of text) {
    if (character === "(") depth += 1;
    if (character === ")") depth -= 1;
    if (character === "," && depth === 0) {
      parts.push(current);
      current = "";
      continue;
    }
    current += character;
  }
  if (current.trim()) parts.push(current);
  return parts.map((part) => part.trim()).filter(Boolean);
}

/** `alias:table!hint(inner)` — everything but the table name is optional. */
function parseSelect(select) {
  const columns = [];
  const embeds = [];
  for (const part of topLevelSplit(select || "*")) {
    const open = part.indexOf("(");
    if (open === -1) {
      columns.push(part.trim());
      continue;
    }
    const head = part.slice(0, open);
    const inner = part.slice(open + 1, part.lastIndexOf(")"));
    const [aliasOrTable, rest] = head.includes(":")
      ? [head.slice(0, head.indexOf(":")), head.slice(head.indexOf(":") + 1)]
      : [null, head];
    const [table, ...hints] = rest.split("!");
    embeds.push({
      alias: (aliasOrTable ?? table).trim(),
      table: table.trim(),
      inner: hints.includes("inner"),
      fk: hints.find((hint) => hint !== "inner") ?? null,
      select: inner,
    });
  }
  return { columns, embeds };
}

/**
 * One embed, resolved.
 *
 * A parent that holds the key gets an object; a child that holds it gets an
 * array. `notifications` points at `profiles` twice, so an ambiguous pair is
 * decided by the `!constraint_name` hint the app already passes.
 */
function embed(parentTable, row, spec) {
  const target = spec.table;
  const outward = FK[parentTable] ?? {};

  const columnFor = (hint, map, table) => {
    const candidates = Object.entries(map).filter(([, points]) => points === table);
    if (candidates.length === 0) return null;
    if (hint) {
      const named = candidates.find(([column]) => hint.includes(column));
      if (named) return named[0];
    }
    return candidates[0][0];
  };

  const outwardColumn = columnFor(spec.fk, outward, target);
  if (outwardColumn) {
    const found = (db[target] ?? []).find((other) => other.id === row[outwardColumn]);
    return found ? shape(target, found, spec.select) : null;
  }

  const inward = FK[target] ?? {};
  const inwardColumn = columnFor(spec.fk, inward, parentTable);
  if (!inwardColumn) return null;
  return (db[target] ?? [])
    .filter((other) => other[inwardColumn] === row.id)
    .map((other) => shape(target, other, spec.select));
}

/** A row as the select asked for it, embeds and all. */
function shape(table, row, select) {
  const { columns, embeds } = parseSelect(select);
  const out = columns.includes("*") || columns.length === 0 ? { ...row } : {};
  for (const column of columns) {
    if (column === "*") continue;
    const computed = COMPUTED[table]?.[column];
    out[column] = computed ? computed(row) : row[column];
  }
  for (const spec of embeds) out[spec.alias] = embed(table, row, spec);
  return out;
}

const VALUE = (raw) => {
  if (raw === "null") return null;
  if (raw === "true") return true;
  if (raw === "false") return false;
  const unquoted = raw.replace(/^"|"$/g, "");
  return unquoted;
};

/** One `column=op.value` pair from the query string. */
function matches(row, column, expression) {
  const dot = expression.indexOf(".");
  const op = expression.slice(0, dot);
  const raw = expression.slice(dot + 1);
  const value = VALUE(raw);
  const actual = row[column];

  switch (op) {
    case "eq": return String(actual) === String(value);
    case "neq": return String(actual) !== String(value);
    case "gt": return actual > value;
    case "gte": return actual >= value;
    case "lt": return actual < value;
    case "lte": return actual <= value;
    case "is": return value === null ? actual === null || actual === undefined : actual === value;
    case "in": {
      const list = raw.replace(/^\(|\)$/g, "").split(",").map((item) => VALUE(item.trim()));
      return list.some((item) => String(item) === String(actual));
    }
    case "like":
    case "ilike": {
      // `%` in a query string, `*` inside an `or=(...)`: both are "anything".
      const pattern = String(value)
        .replace(/\\(.)/g, "$1")
        .replace(/[.+?^${}()|[\]\\]/g, "\\$&")
        .replace(/[%*]/g, ".*");
      return new RegExp(`^${pattern}$`, op === "ilike" ? "i" : "").test(String(actual ?? ""));
    }
    case "not": return !matches(row, column, raw);
    default: return true;
  }
}

const RESERVED = new Set(["select", "order", "limit", "offset", "on_conflict", "columns"]);

/** `or=(title.ilike."*x*",description.ilike."*x*")`: any one of them. */
function matchesAny(row, expression) {
  const inner = expression.replace(/^\(|\)$/g, "");
  const parts = [];
  let current = "";
  let quoted = false;
  for (let index = 0; index < inner.length; index += 1) {
    const character = inner[index];
    if (character === "\\") {
      current += character + (inner[index + 1] ?? "");
      index += 1;
      continue;
    }
    if (character === '"') quoted = !quoted;
    if (character === "," && !quoted) {
      parts.push(current);
      current = "";
      continue;
    }
    current += character;
  }
  if (current) parts.push(current);
  return parts.some((part) => {
    const dot = part.indexOf(".");
    return matches(row, part.slice(0, dot), part.slice(dot + 1));
  });
}

function filtered(table, params) {
  let rows = [...(db[table] ?? [])];

  for (const [column, expression] of params) {
    if (RESERVED.has(column)) continue;
    rows = rows.filter((row) =>
      column === "or" ? matchesAny(row, expression) : matches(row, column, expression),
    );
  }

  const order = params.get("order");
  if (order) {
    for (const clause of order.split(",").reverse()) {
      const [column, ...rest] = clause.split(".");
      const descending = rest.includes("desc");
      rows.sort((a, b) => {
        const left = a[column];
        const right = b[column];
        if (left === right) return 0;
        if (left === null || left === undefined) return 1;
        if (right === null || right === undefined) return -1;
        return (left > right ? 1 : -1) * (descending ? -1 : 1);
      });
    }
  }

  return rows;
}

// ---------------------------------------------------------------------------
// Functions the app calls by name
// ---------------------------------------------------------------------------

const isOverdue = (task) =>
  task.due_at !== null && task.status !== "done" && new Date(task.due_at) < new Date(NOW);

const sameDay = (iso) =>
  iso !== null && iso.slice(0, 10) === NOW.slice(0, 10);

const RPC = {
  /** public.portal_health: a database with every migration run. */
  portal_health() {
    return { database: "ok", time: new Date().toISOString(), schema: 46, missing: [] };
  },

  /**
   * public.work_report, roughly: finishing time is updated_at (the mock keeps
   * no activity log), days are UTC, and "overdue" is against the seeded NOW.
   * The real one is checked in supabase/tests/work-report.sql.
   */
  work_report({ first_day, last_day, grain = "week" }) {
    const live = db.tasks.filter((task) => !task.deleted_at);
    const day = (iso) => (iso ?? "").slice(0, 10);
    const shift = (iso, days) => {
      const date = new Date(`${iso}T12:00:00Z`);
      date.setUTCDate(date.getUTCDate() + days);
      return date.toISOString().slice(0, 10);
    };
    const length = (Date.parse(last_day) - Date.parse(first_day)) / 86_400_000 + 1;
    const before = shift(first_day, -length);
    const within = (iso, from, to) => day(iso) >= from && day(iso) <= to;
    const done = live.filter((task) => task.status === "done");
    const finishedIn = (from, to) => done.filter((task) => within(task.updated_at, from, to));
    const onTime = (list) => list.filter((task) => task.due_at && task.updated_at <= task.due_at).length;
    const late = (task) => task.status !== "done" && task.due_at && task.due_at < NOW;

    const buckets = [];
    let starts =
      grain === "month"
        ? `${first_day.slice(0, 7)}-01`
        : shift(first_day, -new Date(`${first_day}T12:00:00Z`).getUTCDay());
    while (starts <= last_day) {
      const next =
        grain === "month"
          ? new Date(Date.UTC(+starts.slice(0, 4), +starts.slice(5, 7), 1)).toISOString().slice(0, 10)
          : shift(starts, 7);
      const end = shift(next, -1);
      buckets.push({
        starts,
        added: live.filter((task) => within(task.created_at, starts, end)).length,
        finished: finishedIn(starts, end).length,
      });
      starts = next;
    }

    const people = db.profiles
      .map((person) => {
        const open = db.task_assignments
          .filter((a) => a.user_id === person.id)
          .map((a) => live.find((task) => task.id === a.task_id))
          .filter((task) => task && task.status !== "done");
        return { id: person.id, name: person.full_name ?? person.email, open: open.length, overdue: open.filter(late).length };
      })
      .filter((person) => person.open > 0)
      .sort((a, b) => b.open - a.open || a.name.localeCompare(b.name));

    const projects = db.projects
      .filter((project) => !project.archived_at)
      .map((project) => {
        const tasks = live.filter((task) => task.project_id === project.id);
        return {
          id: project.id,
          name: project.name,
          total: tasks.length,
          done: tasks.filter((task) => task.status === "done").length,
          overdue: tasks.filter(late).length,
        };
      })
      .sort((a, b) => a.name.localeCompare(b.name));

    const now = finishedIn(first_day, last_day);
    const then = finishedIn(before, shift(first_day, -1));
    return {
      finished: now.length,
      finishedBefore: then.length,
      added: live.filter((task) => within(task.created_at, first_day, last_day)).length,
      addedBefore: live.filter((task) => within(task.created_at, before, shift(first_day, -1))).length,
      onTime: onTime(now),
      withDue: now.filter((task) => task.due_at).length,
      onTimeBefore: onTime(then),
      withDueBefore: then.filter((task) => task.due_at).length,
      overdueNow: live.filter(late).length,
      buckets,
      people,
      projects,
    };
  },
  task_counts() {
    const live = db.tasks.filter((task) => !task.deleted_at);
    const count = (predicate) => live.filter(predicate).length;
    return [{
      total: live.length,
      done: count((t) => t.status === "done"),
      todo: count((t) => t.status === "todo"),
      in_progress: count((t) => t.status === "in_progress"),
      in_review: count((t) => t.status === "in_review"),
      overdue: count(isOverdue),
      due_today: count((t) => sameDay(t.due_at) && t.status !== "done"),
    }];
  },

  workload_counts() {
    const byUser = new Map();
    for (const assignment of db.task_assignments) {
      const task = db.tasks.find((row) => row.id === assignment.task_id && !row.deleted_at);
      if (!task) continue;
      const entry = byUser.get(assignment.user_id) ?? { user_id: assignment.user_id, open: 0, done: 0, overdue: 0 };
      if (task.status === "done") entry.done += 1;
      else entry.open += 1;
      if (isOverdue(task)) entry.overdue += 1;
      byUser.set(assignment.user_id, entry);
    }
    return [...byUser.values()];
  },

  my_conversations(_args, ME) {
    const mine = db.conversation_participants.filter((row) => row.user_id === ME);
    return mine.map((membership) => {
      const conversation = db.conversations.find((row) => row.id === membership.conversation_id);
      const others = db.conversation_participants.filter(
        (row) => row.conversation_id === membership.conversation_id && row.user_id !== ME,
      );
      const other = db.profiles.find((row) => row.id === others[0]?.user_id);
      const messages = db.direct_messages
        .filter((row) => row.conversation_id === membership.conversation_id)
        .sort((a, b) => (a.created_at < b.created_at ? 1 : -1));
      return {
        id: membership.conversation_id,
        last_message_at: conversation?.last_message_at ?? null,
        other_id: other?.id ?? null,
        other_name: other?.full_name ?? null,
        other_email: other?.email ?? null,
        other_avatar: other?.avatar_url ?? null,
        other_title: other?.job_title ?? null,
        last_message: messages[0]?.body ?? null,
        last_author_id: messages[0]?.author_id ?? null,
        unread: messages.filter(
          (row) => row.author_id !== ME && row.created_at > (membership.last_read_at ?? ""),
        ).length,
      };
    }).sort((a, b) => (a.last_message_at < b.last_message_at ? 1 : -1));
  },

  unread_direct_count(_args, ME) {
    return RPC.my_conversations(null, ME).reduce((sum, row) => sum + row.unread, 0);
  },

  start_direct_conversation({ other }, ME) {
    const [low, high] = [ME, other].sort();
    const existing = db.conversations.find(
      (row) => row.member_low === low && row.member_high === high,
    );
    if (existing) return existing.id;

    const id = randomUUID();
    db.conversations.push({ id, member_low: low, member_high: high, created_at: new Date().toISOString(), last_message_at: new Date().toISOString() });
    db.conversation_participants.push(
      { conversation_id: id, user_id: ME, last_read_at: new Date().toISOString() },
      { conversation_id: id, user_id: other, last_read_at: null },
    );
    return id;
  },

  trash_task({ task }) {
    const row = db.tasks.find((candidate) => candidate.id === task);
    if (row) row.deleted_at = new Date().toISOString();
    return row ? 1 : 0;
  },

  restore_task({ task }) {
    const row = db.tasks.find((candidate) => candidate.id === task);
    if (row) row.deleted_at = null;
    return row ? 1 : 0;
  },

  /**
   * Read from the queue, like the real ones — the shape is what the profile
   * page renders, and the message body is deliberately not in it.
   */
  my_reminder_failures(_args, ME) {
    return db.reminder_queue
      .filter((row) => row.status === "failed" && row.user_id === ME)
      .map((row) => ({
        channel: row.channel,
        kind: row.kind,
        attempts: row.attempts,
        last_error: row.last_error,
        failed_at: row.failed_at ?? row.created_at,
      }));
  },

  reminder_failures(_args, ME) {
    const me = db.profiles.find((row) => row.id === ME);
    // The real one raises for anybody else; the app treats an error as
    // "nothing to show", which is the same outcome.
    if (me?.role !== "admin") return [];

    return db.reminder_queue
      .filter((row) => row.status === "failed")
      .map((row) => {
        const person = db.profiles.find((profile) => profile.id === row.user_id);
        return {
          user_id: row.user_id,
          person: person?.full_name ?? person?.email ?? "?",
          channel: row.channel,
          kind: row.kind,
          attempts: row.attempts,
          last_error: row.last_error,
          failed_at: row.failed_at ?? row.created_at,
        };
      });
  },

  notify_reminder_failed: () => null,

  /** Grouped the way the real one groups: by message and route. */
  recent_errors(_args, ME) {
    const me = db.profiles.find((row) => row.id === ME);
    if (me?.role !== "admin") return [];

    const groups = new Map();
    for (const row of db.app_errors) {
      const key = `${row.source}|${row.message}|${row.route}`;
      const found = groups.get(key) ?? {
        occurred_at: row.occurred_at,
        person: db.profiles.find((p) => p.id === row.user_id)?.full_name ?? null,
        source: row.source,
        digest: row.digest ?? null,
        message: row.message,
        route: row.route,
        seen: 0,
      };
      found.seen += 1;
      if (row.occurred_at > found.occurred_at) found.occurred_at = row.occurred_at;
      groups.set(key, found);
    }
    return [...groups.values()].sort((a, b) => (a.occurred_at < b.occurred_at ? 1 : -1));
  },

  purge_old_errors: () => 0,

  /** Archiving, including the refusal that makes it worth having. */
  /**
   * Every live project's latest status and work counts. The real function is
   * `security invoker`; the mock enforces nothing, so it answers for all of
   * them — the specs that read it sign in as the admin, who sees all of them
   * anyway.
   */
  project_health() {
    const now = Date.now();
    return db.projects
      .filter((project) => !project.archived_at)
      .map((project) => {
        const latest = db.project_status_updates
          .filter((row) => row.project_id === project.id)
          .sort((a, b) => (a.created_at < b.created_at ? 1 : -1))[0];
        const author = latest && db.profiles.find((row) => row.id === latest.author_id);
        const work = db.tasks.filter((task) => task.project_id === project.id && !task.deleted_at);
        const open = work.filter((task) => task.status !== "done");
        return {
          project_id: project.id,
          name: project.name,
          latest_status: latest?.status ?? null,
          latest_body: latest?.body ?? null,
          latest_at: latest?.created_at ?? null,
          latest_author: author ? (author.full_name ?? author.email) : null,
          open_tasks: open.length,
          overdue_tasks: open.filter((task) => task.due_at && Date.parse(task.due_at) < now).length,
        };
      })
      .sort((a, b) => a.name.localeCompare(b.name));
  },

  set_project_archived({ project, archived }) {
    const row = db.projects.find((one) => one.id === project);
    if (!row) return null;

    if (archived) {
      const open = db.tasks.filter(
        (task) => task.project_id === project && !task.deleted_at && task.status !== "done",
      ).length;
      if (open > 0) {
        const error = new Error(`That project still has ${open} task(s) open.`);
        error.status = 400;
        throw error;
      }
    }

    row.archived_at = archived ? new Date().toISOString() : null;
    return null;
  },

  purge_trashed_tasks: () => 0,
  enqueue_task_reminders: () => 0,
  claim_reminders: () => [],
  claim_task_reminders: () => [],
};

// ---------------------------------------------------------------------------
// The wire
// ---------------------------------------------------------------------------

/** Every request, so a spec can count round trips. */
export const log = [];

const b64 = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
/**
 * `aal` is how the session was earned: aal1 with a password, aal2 once the
 * code from an authenticator app has been entered too.
 */
const jwt = (who, aal = "aal1") =>
  `${b64({ alg: "HS256", typ: "JWT" })}.${b64({
    aal,
    sub: who,
    aud: "authenticated",
    role: "authenticated",
    email: db.profiles.find((row) => row.id === who)?.email,
    session_id: randomUUID(),
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + 3600,
    user_metadata: {},
    app_metadata: {},
  })}.unsigned`;

/** Who each refresh token was issued to, and at which level. */
const refreshTokens = new Map();

/** The user as GoTrue describes them, factors included. */
const authUser = (id) => {
  const me = db.profiles.find((row) => row.id === id);
  return {
    id, aud: "authenticated", role: "authenticated", email: me?.email,
    user_metadata: {}, app_metadata: {}, created_at: "2026-01-01T00:00:00Z",
    factors: db.mfa_factors.filter((row) => row.user_id === id),
  };
};

const session = (id, aal) => {
  const refresh = randomUUID();
  refreshTokens.set(refresh, { id, aal });
  return {
    access_token: jwt(id, aal), token_type: "bearer", expires_in: 3600,
    expires_at: Math.floor(Date.now() / 1000) + 3600, refresh_token: refresh,
    user: authUser(id),
  };
};

/** Uploaded files, by "bucket/path". Gone when the mock restarts. */
const objects = new Map();

const readRaw = (request) =>
  new Promise((resolve) => {
    const chunks = [];
    request.on("data", (chunk) => chunks.push(chunk));
    request.on("end", () => resolve(Buffer.concat(chunks)));
  });

/** The file part of a multipart upload, as storage-js sends it from a browser. */
function filePart(body, contentType) {
  const boundary = /boundary=([^;]+)/.exec(contentType ?? "")?.[1];
  if (!boundary) return { bytes: body, type: contentType || "application/octet-stream" };
  const marker = Buffer.from(`--${boundary}`);
  let start = body.indexOf(marker);
  while (start !== -1) {
    const next = body.indexOf(marker, start + marker.length);
    if (next === -1) break;
    const part = body.subarray(start + marker.length + 2, next - 2);
    const split = part.indexOf("\r\n\r\n");
    const headers = part.subarray(0, split).toString();
    if (/filename=/i.test(headers)) {
      return {
        bytes: part.subarray(split + 4),
        type: /content-type:\s*([^\r\n]+)/i.exec(headers)?.[1] ?? "application/octet-stream",
      };
    }
    start = next;
  }
  return { bytes: Buffer.alloc(0), type: "application/octet-stream" };
}

const readBody = (request) =>
  new Promise((resolve) => {
    let text = "";
    request.on("data", (chunk) => (text += chunk));
    request.on("end", () => {
      try {
        resolve(text ? JSON.parse(text) : null);
      } catch {
        resolve(null);
      }
    });
  });

const defaults = (table, row) => ({
  id: randomUUID(),
  created_at: new Date().toISOString(),
  updated_at: new Date().toISOString(),
  ...(table === "tasks" ? { status: "todo", priority: "medium", deleted_at: null, position: 0, due_at: null, follow_up_at: null, description: null, milestone_id: null } : {}),
  ...(table === "project_milestones" ? { done_at: null, created_by: null } : {}),
  ...row,
});

const server = createServer(async (request, response) => {
  const at = performance.now();
  log.push({ at, method: request.method, url: request.url });
  if (process.env.MOCK_QUIET !== "1") {
    process.stdout.write(`${at.toFixed(0)}\t${request.method} ${request.url}\n`);
  }

  await new Promise((resume) => setTimeout(resume, LATENCY));

  const url = new URL(request.url, `http://localhost:${PORT}`);
  const prefer = request.headers.prefer ?? "";

  /**
   * Cross-origin, because the browser talks to this directly.
   *
   * Most reads go through the app's server, which is not a browser and does
   * not ask. A few do not: the comment thread and the attachment panel query
   * from the page itself, from the app's origin to this one. Without these
   * headers every one of those was refused before it reached a handler — so
   * no spec could ever see a comment, and none tried.
   */
  const CORS = {
    "access-control-allow-origin": request.headers.origin ?? "*",
    "access-control-allow-credentials": "true",
    "access-control-allow-headers": request.headers["access-control-request-headers"] ?? "*",
    "access-control-allow-methods": "GET, HEAD, POST, PATCH, DELETE, OPTIONS",
    "access-control-expose-headers": "content-range",
    vary: "origin",
  };

  const send = (payload, status = 200, headers = {}) => {
    response.writeHead(status, { "content-type": "application/json", ...CORS, ...headers });
    response.end(request.method === "HEAD" ? undefined : JSON.stringify(payload));
  };

  if (request.method === "OPTIONS") {
    response.writeHead(204, CORS);
    response.end();
    return;
  }

  // --- the harness's own door -------------------------------------------
  if (url.pathname === "/__reset") {
    db = seed();
    log.length = 0;
    return send({ ok: true });
  }
  if (url.pathname === "/__db") {
    return send(db);
  }
  // How many round trips a page cost, for measuring navigation.
  if (url.pathname === "/__log") {
    return send({ calls: log.length, last: log.slice(-40) });
  }

  // --- Storage -----------------------------------------------------------
  // Enough of it for attachments: upload, sign one or many, fetch, remove.
  // It checks nothing — who may read a file is the database's question, and
  // is tested against the real one in supabase/tests/attachment-files.sql.
  if (url.pathname.startsWith("/storage/v1/object/")) {
    const rest = decodeURIComponent(url.pathname.slice("/storage/v1/object/".length));

    if (rest.startsWith("sign/")) {
      const target = rest.slice("sign/".length);
      if (request.method === "GET") {
        const stored = objects.get(target);
        if (!stored) return send({ message: "Object not found" }, 404);
        response.writeHead(200, { "content-type": stored.type, ...CORS });
        return response.end(stored.bytes);
      }
      const body = (await readBody(request)) ?? {};
      const signed = (path) => `/object/sign/${path}?token=mock`;
      // Many at once: POST /object/sign/<bucket> with { paths }.
      if (Array.isArray(body.paths)) {
        return send(
          body.paths.map((path) => ({
            path,
            signedURL: objects.has(`${target}/${path}`) ? signed(`${target}/${path}`) : null,
            error: objects.has(`${target}/${path}`) ? null : "Object not found",
          })),
        );
      }
      return send({ signedURL: signed(target) });
    }

    if (request.method === "POST" || request.method === "PUT") {
      const { bytes, type } = filePart(await readRaw(request), request.headers["content-type"]);
      objects.set(rest, { bytes, type });
      return send({ Key: rest, Id: randomUUID() });
    }
    if (request.method === "DELETE") {
      const body = (await readBody(request)) ?? {};
      for (const prefix of body.prefixes ?? []) objects.delete(`${rest}/${prefix}`);
      return send([]);
    }
  }

  // --- GoTrue ------------------------------------------------------------
  if (url.pathname.startsWith("/auth/v1/user")) {
    return send(authUser(actor(request)));
  }
  if (url.pathname.startsWith("/auth/v1/token")) {
    const credentials = (await readBody(request)) ?? {};
    // A refresh keeps who it was and how they signed in; anything else is
    // a password, which is aal1 whoever it is.
    const kept = credentials.refresh_token && refreshTokens.get(credentials.refresh_token);
    const me =
      (kept && db.profiles.find((row) => row.id === kept.id)) ??
      db.profiles.find((row) => row.email === credentials.email) ??
      db.profiles.find((row) => row.id === DEFAULT_USER);
    return send(session(me.id, kept?.aal ?? "aal1"));
  }

  // Authenticator apps. Any code is "123456": the specs are about what the
  // app does with a right and a wrong one, not about TOTP.
  const factorPath = url.pathname.match(/^\/auth\/v1\/factors(?:\/([^/]+))?(?:\/(challenge|verify))?$/);
  if (factorPath) {
    const [, factorId, step] = factorPath;
    const id = actor(request);
    const factor = factorId && db.mfa_factors.find((row) => row.id === factorId && row.user_id === id);

    if (!factorId && request.method === "POST") {
      const body = (await readBody(request)) ?? {};
      if (db.mfa_factors.some((row) => row.user_id === id && row.friendly_name === body.friendly_name)) {
        return send({ code: "mfa_factor_name_conflict", msg: "A factor with that name already exists." }, 422);
      }
      const created = {
        id: randomUUID(), user_id: id, friendly_name: body.friendly_name ?? null,
        factor_type: "totp", status: "unverified",
        created_at: new Date().toISOString(), updated_at: new Date().toISOString(),
      };
      db.mfa_factors.push(created);
      return send({
        id: created.id, type: "totp", friendly_name: created.friendly_name,
        totp: {
          // Raw SVG, as GoTrue sends it — the client adds the data: prefix
          // itself, unencoded — with the "#" colours a real one has.
          qr_code: '<?xml version="1.0" encoding="UTF-8"?>\n<svg width="200" height="200" xmlns="http://www.w3.org/2000/svg"><rect x="0" y="0" width="200" height="200" style="fill:#ffffff" /><rect x="20" y="20" width="60" height="60" style="fill:#000000" /><rect x="120" y="120" width="60" height="60" style="fill:#000000" /></svg>',
          secret: "JBSWY3DPEHPK3PXP",
          uri: "otpauth://totp/Almailgroup:test?secret=JBSWY3DPEHPK3PXP&issuer=Almailgroup",
        },
      });
    }
    if (!factor) return send({ code: "mfa_factor_not_found", msg: "Factor not found" }, 404);
    if (request.method === "DELETE") {
      db.mfa_factors = db.mfa_factors.filter((row) => row !== factor);
      return send({ id: factor.id });
    }
    if (step === "challenge") {
      return send({ id: randomUUID(), type: "totp", expires_at: Math.floor(Date.now() / 1000) + 300 });
    }
    if (step === "verify") {
      const body = (await readBody(request)) ?? {};
      if (body.code !== "123456") {
        return send({ code: "mfa_verification_failed", msg: "Invalid TOTP code entered" }, 422);
      }
      factor.status = "verified";
      return send(session(id, "aal2"));
    }
  }
  if (url.pathname.startsWith("/auth/v1/")) return send({});

  // --- PostgREST ---------------------------------------------------------
  if (url.pathname.startsWith("/rest/v1/rpc/")) {
    const name = url.pathname.replace("/rest/v1/rpc/", "");
    const handler = RPC[name];
    if (!handler) return send({ message: `no mock for rpc ${name}` }, 404);
    const args = (await readBody(request)) ?? {};
    try {
      return send(handler(args, actor(request)));
    } catch (thrown) {
      // A function that raises, as Postgres would: the app reads `message`.
      return send({ message: thrown.message, code: "P0001" }, thrown.status ?? 400);
    }
  }

  if (url.pathname.startsWith("/rest/v1/")) {
    const table = url.pathname.replace("/rest/v1/", "");
    if (!(table in db)) return send({ message: `no table ${table}` }, 404);

    const params = url.searchParams;
    const select = params.get("select") ?? "*";
    const wantsOne = (request.headers.accept ?? "").includes("vnd.pgrst.object");
    const wantsRows = prefer.includes("return=representation");
    const exactCount = prefer.includes("count=exact");

    if (request.method === "POST") {
      const payload = await readBody(request);
      const incoming = (Array.isArray(payload) ? payload : [payload]).map((row) => defaults(table, row));
      // An upsert names the columns that decide "the same row"; that row is
      // replaced, as merge-duplicates would, instead of pushed a second time.
      const conflict = params.get("on_conflict")?.split(",");
      if (conflict) {
        const same = (a, b) => conflict.every((column) => a[column] === b[column]);
        db[table] = db[table].filter((row) => !incoming.some((next) => same(row, next)));
      }
      db[table].push(...incoming);
      const shaped = incoming.map((row) => shape(table, row, select));
      return send(wantsOne ? shaped[0] : shaped, 201);
    }

    if (request.method === "PATCH") {
      const payload = (await readBody(request)) ?? {};
      const hits = filtered(table, params);
      for (const row of hits) Object.assign(row, payload, { updated_at: new Date().toISOString() });
      const shaped = hits.map((row) => shape(table, row, select));
      return send(wantsRows ? (wantsOne ? shaped[0] ?? null : shaped) : null, 200);
    }

    if (request.method === "DELETE") {
      const hits = filtered(table, params);
      db[table] = db[table].filter((row) => !hits.includes(row));
      const shaped = hits.map((row) => shape(table, row, select));
      return send(
        wantsRows ? (wantsOne ? shaped[0] ?? null : shaped) : null,
        200,
        exactCount ? { "content-range": `*/${hits.length}` } : {},
      );
    }

    // GET / HEAD
    let rows = filtered(table, params);
    const total = rows.length;
    const offset = Number(params.get("offset") ?? 0);
    const limit = params.get("limit");
    rows = rows.slice(offset, limit ? offset + Number(limit) : undefined);

    const shaped = rows
      .map((row) => shape(table, row, select))
      // `!inner` on an embed drops parents with nothing on the other side.
      .filter((row) =>
        parseSelect(select).embeds.every(
          (spec) => !spec.inner || (Array.isArray(row[spec.alias]) ? row[spec.alias].length > 0 : row[spec.alias] !== null),
        ),
      );

    return send(
      wantsOne ? shaped[0] ?? null : shaped,
      200,
      { "content-range": `${offset}-${Math.max(offset, offset + shaped.length - 1)}/${exactCount ? total : "*"}` },
    );
  }

  // Realtime is not mocked: the app retries a failed socket and carries on
  // with what the server rendered, which is what a spec should assert on.
  send({}, 404);
});

server.listen(PORT, () => {
  process.stderr.write(`mock supabase on :${PORT} — ${LATENCY}ms per call\n`);
});
