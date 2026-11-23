import type { Metadata } from "next";

import { TaskBrowser } from "@/components/tasks/task-browser";
import { filterLabel, isTaskFilter, type TaskFilter } from "@/lib/task-filters";
import {
  getTaskCounts,
  getTasksForFilter,
  getProjects,
  getTeam,
  requireProfile,
} from "@/lib/data/queries";
import { getI18n, getTimeZone } from "@/lib/i18n/server";

type PageProps = { searchParams: Promise<{ filter?: string }> };

export async function generateMetadata({
  searchParams,
}: PageProps): Promise<Metadata> {
  const [{ filter }, { t }] = await Promise.all([searchParams, getI18n()]);
  return { title: t(isTaskFilter(filter) ? filterLabel(filter) : "nav.tasks") };
}

export default async function TasksPage({ searchParams }: PageProps) {
  const { filter: raw } = await searchParams;
  const filter: TaskFilter = isTaskFilter(raw) ? raw : "all";

  const timeZone = await getTimeZone();

  const [profile, page, metrics, projects, team] = await Promise.all([
    requireProfile(),
    getTasksForFilter(filter, timeZone),
    // The chips' numbers come from the same database function the dashboard
    // tiles use, so the two can never disagree — and so a chip is still
    // right when there are more tasks than one page can carry.
    getTaskCounts(),
    getProjects(),
    getTeam(),
  ]);

  const counts: Record<TaskFilter, number> = {
    todo: metrics.todo,
    pending: metrics.pending,
    in_progress: metrics.inProgress,
    in_review: metrics.inReview,
    done: metrics.done,
    due_today: metrics.dueToday,
    overdue: metrics.overdue,
    all: metrics.total,
  };

  return (
    <TaskBrowser
      tasks={page.tasks}
      filter={filter}
      counts={counts}
      total={page.total}
      truncated={page.truncated}
      projects={projects}
      team={team}
      profile={profile}
    />
  );
}
