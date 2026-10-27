"use server";

import { createClient } from "@/lib/supabase/server";
import { isSearchable, likeFilterValue, likePattern } from "@/lib/search";
import { searchTasks, type TaskSearchHit } from "@/lib/data/task-actions";

/**
 * Searching everything a person can see, from the command palette.
 *
 * Task titles were all it searched, so a decision made in a comment, a file
 * somebody attached, or something said in the team room could only be found
 * by remembering where it was. Each kind is its own small query, all at
 * once, five apiece; row-level security decides what each person may find,
 * exactly as it decides what they may read, so nothing here checks a role.
 */

export type SearchKind = "comment" | "file" | "chat" | "message" | "note";

export type SearchHit = {
  kind: SearchKind;
  id: string;
  /** What matched, or the thing it is in. */
  label: string;
  /** Where it is, and a little of what was said around the match. */
  hint: string;
  href: string;
};

export type SearchResults = { tasks: TaskSearchHit[]; more: SearchHit[] };

const EACH = 5;

/** Some of the text either side of the match, on one line. */
function around(text: string, needle: string, width = 70): string {
  const flat = text.replace(/\s+/g, " ").trim();
  const at = flat.toLowerCase().indexOf(needle.toLowerCase());
  if (at < 0 || flat.length <= width) return flat.slice(0, width);
  const start = Math.max(0, at - Math.floor((width - needle.length) / 2));
  const end = Math.min(flat.length, start + width);
  return `${start > 0 ? "…" : ""}${flat.slice(start, end)}${end < flat.length ? "…" : ""}`;
}

type Named = { title?: string | null; full_name?: string | null; email?: string | null } | null;

export async function searchEverything(term: string): Promise<SearchResults> {
  const needle = term.trim();
  if (!isSearchable(needle)) return { tasks: [], more: [] };

  const supabase = await createClient();
  const pattern = likePattern(needle);

  const [tasks, comments, files, chat, messages, notes] = await Promise.all([
    searchTasks(needle),
    supabase
      .from("comments")
      .select("id, content, task_id, task:tasks(title)")
      .ilike("content", pattern)
      .order("created_at", { ascending: false })
      .limit(EACH),
    supabase
      .from("task_attachments")
      .select("id, name, task_id, task:tasks(title)")
      .ilike("name", pattern)
      .order("created_at", { ascending: false })
      .limit(EACH),
    supabase
      .from("team_messages")
      .select("id, body, author:profiles(full_name, email)")
      .ilike("body", pattern)
      .order("created_at", { ascending: false })
      .limit(EACH),
    supabase
      .from("direct_messages")
      .select("id, body, conversation_id, author:profiles(full_name, email)")
      .ilike("body", pattern)
      .order("created_at", { ascending: false })
      .limit(EACH),
    supabase
      .from("personal_notes")
      .select("id, title, body")
      .or(`title.ilike.${likeFilterValue(needle)},body.ilike.${likeFilterValue(needle)}`)
      .order("updated_at", { ascending: false })
      .limit(EACH),
  ]);

  // One kind failing is no reason to show nothing of the others.
  const rows = <T,>(result: { data: T[] | null; error: unknown }) =>
    result.error ? [] : (result.data ?? []);
  const name = (who: unknown) =>
    (who as Named)?.full_name ?? (who as Named)?.email ?? "";
  const taskTitle = (task: unknown) => (task as Named)?.title ?? "";

  const more: SearchHit[] = [
    ...rows(comments).map((row) => ({
      kind: "comment" as const,
      id: row.id,
      label: around(row.content, needle),
      hint: taskTitle(row.task),
      href: `/tasks?filter=all&task=${row.task_id}`,
    })),
    ...rows(files).map((row) => ({
      kind: "file" as const,
      id: row.id,
      label: row.name,
      hint: taskTitle(row.task),
      href: `/tasks?filter=all&task=${row.task_id}`,
    })),
    ...rows(chat).map((row) => ({
      kind: "chat" as const,
      id: row.id,
      label: around(row.body, needle),
      hint: name(row.author),
      href: "/chat",
    })),
    ...rows(messages).map((row) => ({
      kind: "message" as const,
      id: row.id,
      label: around(row.body, needle),
      hint: name(row.author),
      href: `/messages/${row.conversation_id}`,
    })),
    ...rows(notes).map((row) => ({
      kind: "note" as const,
      id: row.id,
      label: row.title.trim() || around(row.body, needle),
      hint: row.title.trim() ? around(row.body, needle) : "",
      href: "/my-list",
    })),
  ];

  return { tasks, more };
}
