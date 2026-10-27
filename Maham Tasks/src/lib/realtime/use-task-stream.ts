"use client";

import * as React from "react";
import { useRouter } from "next/navigation";

import { createClient } from "@/lib/supabase/client";
import type { Task, TaskWithAssignees } from "@/lib/supabase/database.types";

/**
 * A task row from Postgres, folded onto the one already on screen.
 *
 * Realtime sends the table's own columns and nothing else: no assignees,
 * and — since checklists and labels arrived — no step count or labels either. Both are joined in by
 * the server query, so a merge that takes the row wholesale drops them. The
 * assignees were carried across from the first day; the checklist was not,
 * and `undefined` reaching ChecklistProgressBadge is a thrown TypeError and
 * an error boundary over the whole board.
 *
 * Everything joined on stays; everything the row owns is replaced.
 */
export function mergeTaskUpdate(
  previous: TaskWithAssignees,
  row: Task,
): TaskWithAssignees {
  return {
    ...row,
    assignees: previous.assignees,
    checklist: previous.checklist,
    labelIds: previous.labelIds,
    waitingOn: previous.waitingOn,
  };
}

/**
 * Keeps a task list live, for one project or for the general list.
 *
 * Status and priority edits are applied straight to local state so the board
 * reacts immediately. Anything touching the assignee set asks the server to
 * re-render instead, because a task_assignments payload carries only ids and
 * resolving them here would cost a round trip per event. Those refreshes are
 * debounced so a burst of changes collapses into one refetch.
 *
 * Realtime filters support `eq` but not `is null`, so the general list cannot
 * be filtered server-side. It subscribes to every task and discards the ones
 * belonging to a project.
 */
export function useTaskStream({
  projectId,
  initial,
}: {
  /** A project id, or null for the general (project-less) list. */
  projectId: string | null;
  initial: TaskWithAssignees[];
}): TaskWithAssignees[] {
  const router = useRouter();
  const supabase = React.useMemo(() => createClient(), []);
  const [tasks, setTasks] = React.useState(initial);
  const refreshTimer = React.useRef<ReturnType<typeof setTimeout> | null>(null);

  React.useEffect(() => setTasks(initial), [initial]);

  const scheduleRefresh = React.useCallback(() => {
    if (refreshTimer.current) clearTimeout(refreshTimer.current);
    refreshTimer.current = setTimeout(() => router.refresh(), 400);
  }, [router]);

  /** Does this row belong to the list being displayed? */
  const belongsHere = React.useCallback(
    (row: { project_id: string | null }) => row.project_id === projectId,
    [projectId],
  );

  React.useEffect(() => {
    const scope = projectId
      ? { filter: `project_id=eq.${projectId}` }
      : {};
    const channelName = projectId ? `tasks:project:${projectId}` : "tasks:general";

    const channel = supabase
      .channel(channelName)
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "tasks", ...scope },
        (payload) => {
          const row = payload.new as Task;

          // Trashed, not moved: a soft delete arrives as an update with
          // deleted_at set. It leaves the board the way a hard delete would.
          if (row.deleted_at) {
            setTasks((current) => current.filter((task) => task.id !== row.id));
            return;
          }

          if (!belongsHere(row)) {
            // A task moved into or out of this list; only a refetch can say
            // which, and it needs its assignees resolved anyway.
            scheduleRefresh();
            return;
          }

          setTasks((current) => {
            const index = current.findIndex((task) => task.id === row.id);
            if (index === -1) {
              scheduleRefresh();
              return current;
            }
            const next = [...current];
            // Keep what the payload does not carry: the assignees and the
            // checklist counts, both of which are joined in by the query.
            next[index] = mergeTaskUpdate(current[index], row);
            return next;
          });
        },
      )
      .on(
        "postgres_changes",
        { event: "DELETE", schema: "public", table: "tasks", ...scope },
        (payload) => {
          const removed = payload.old as { id?: string };
          if (!removed.id) return;
          setTasks((current) => current.filter((task) => task.id !== removed.id));
        },
      )
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "tasks", ...scope },
        // A new task needs its assignees resolved, so refetch.
        scheduleRefresh,
      )
      .on(
        "postgres_changes",
        // task_assignments carries no project_id to scope on, so this fires for
        // every assignment change; the debounce keeps that cheap.
        { event: "*", schema: "public", table: "task_assignments" },
        scheduleRefresh,
      )
      .subscribe();

    return () => {
      if (refreshTimer.current) clearTimeout(refreshTimer.current);
      supabase.removeChannel(channel);
    };
  }, [supabase, projectId, scheduleRefresh, belongsHere]);

  return tasks;
}
