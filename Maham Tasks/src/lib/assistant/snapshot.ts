import "server-only";

import {
  getOpenTasks,
  getTaskCounts,
  getProjects,
  getTeam,
  requireProfile,
} from "@/lib/data/queries";
import { getLocale, getTimeZone } from "@/lib/i18n/server";
import type { AssistantSnapshot, AssistantTask } from "@/lib/assistant/types";

/**
 * Gather what the assistant is allowed to know about the caller's work.
 *
 * Every read goes through the normal RLS-scoped queries, so the snapshot is
 * already the caller's own view of the board: a member sees only the tasks
 * assigned to them, a manager sees the projects they belong to. The assistant
 * needs no permission logic of its own, and nothing it says can be broader
 * than what that person could already open in the UI.
 *
 * Counts come from the same `summarise` the dashboard cards use, so the
 * assistant and the dashboard can never disagree about how many are overdue.
 */
export async function buildSnapshot(): Promise<AssistantSnapshot> {
  /**
   * The figures come from the database, the board from the open work.
   *
   * Counting in TypeScript over whatever rows arrived meant the assistant
   * could state a total that was a row cap rather than a fact — and state it
   * with complete confidence, which is the worst way for a number to be
   * wrong. The counts are now the same ones the dashboard tiles show.
   *
   * What the model reads is the open work: closed tasks answer no question
   * anybody asks an assistant beyond "how many", and that is a count.
   */
  const [profile, open, metrics, projects, team, locale, timeZone] = await Promise.all([
    requireProfile(),
    getOpenTasks(),
    getTaskCounts(),
    getProjects(),
    getTeam(),
    getLocale(),
    getTimeZone(),
  ]);

  const projectName = new Map(projects.map((project) => [project.id, project.name]));

  const flattened: AssistantTask[] = open.tasks.map((task) => ({
    id: task.id,
    title: task.title,
    status: task.status,
    priority: task.priority,
    project: task.project_id ? (projectName.get(task.project_id) ?? null) : null,
    dueAt: task.due_at,
    followUpAt: task.follow_up_at,
    assignees: task.assignees.map((person) => person.full_name ?? person.email),
    createdAt: task.created_at,
  }));

  return {
    viewer: {
      name: profile.full_name ?? profile.email,
      role: profile.role,
      // The same rule the New task button uses. Told to the model so it can
      // say no itself rather than proposing something the database refuses.
      canManage: profile.role === "admin" || profile.role === "manager",
    },
    projects: projects.map((project) => ({ id: project.id, name: project.name })),
    team: team.map((person) => ({
      id: person.id,
      name: person.full_name ?? person.email,
    })),
    locale,
    timeZone,
    takenAt: new Date().toISOString(),
    tasks: flattened,
    counts: {
      total: metrics.total,
      todo: metrics.todo,
      inProgress: metrics.inProgress,
      inReview: metrics.inReview,
      done: metrics.done,
      overdue: metrics.overdue,
      dueToday: metrics.dueToday,
      // Counted over the open work that was fetched, which is what these two
      // are about — nobody asks how many closed tasks had no due date.
      unassigned: open.tasks.filter((task) => task.assignees.length === 0).length,
      noDueDate: open.tasks.filter((task) => task.due_at === null).length,
    },
  };
}
