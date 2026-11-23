import type { Metadata } from "next";
import Link from "next/link";
import {
  ArrowRight,
  CalendarClock,
  CircleAlert,
  CircleCheck,
  CircleDashed,
  CircleDot,
  Eye,
  FolderOpen,
} from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { PageHeader, PageShell } from "@/components/layout/page-shell";
import { EmptyState } from "@/components/ui/empty-state";
import { MetricCard, ProgressBar } from "@/components/dashboard/metric-card";
import { WorkloadCard } from "@/components/dashboard/workload-card";
import { NeedsAttention } from "@/components/dashboard/needs-attention";
import { GettingStarted } from "@/components/dashboard/getting-started";
import {
  AssigneeStack,
  DueDate,
  PriorityIndicator,
  StatusBadge,
} from "@/components/tasks/task-meta";
import {
  getHolidays,
  getMyOpenTasks,
  getNotificationPreferences,
  getOverdueTasks,
  getProjectHealth,
  getProjects,
  getTaskCounts,
  getTeam,
  getWorkload,
  requireProfile,
} from "@/lib/data/queries";
import { signedInWithSecondStep } from "@/lib/auth/second-step";
import { createClient } from "@/lib/supabase/server";
import type { GuideFacts } from "@/lib/guide";
import type { TaskWithAssignees } from "@/lib/supabase/database.types";
import { getI18n } from "@/lib/i18n/server";

export async function generateMetadata(): Promise<Metadata> {
  const { t } = await getI18n();
  return { title: t("nav.dashboard") };
}

export default async function DashboardPage() {
  // Five bounded reads instead of "fetch every task, then reduce it here".
  // The counts and the workload are aggregated in Postgres; the two lists ask
  // for the six rows they show rather than everything and a slice.
  const [profile, metrics, workload, myTasks, attention, projects, health, preferences, holidays] =
    await Promise.all([
      requireProfile(),
      getTaskCounts(),
      getWorkload(),
      getMyOpenTasks(6),
      getOverdueTasks(6),
      getProjects(),
      getProjectHealth(),
      getNotificationPreferences(),
      getHolidays(),
    ]);

  // Reporting on projects is a manager's and an admin's job; a member's
  // dashboard is about their own work.
  const reportsOnProjects = profile.role === "admin" || profile.role === "manager";

  const { t, tn } = await getI18n();
  const firstName = profile.full_name?.split(" ")[0];

  // What the getting-started guide can tick on its own. The team and the
  // second step only matter to an admin's list, so only an admin asks.
  const isAdmin = profile.role === "admin";
  const [team, twoStep] = isAdmin
    ? await Promise.all([getTeam(), createClient().then(signedInWithSecondStep)])
    : [[], false];
  const facts: GuideFacts = {
    telegramLinked: Boolean(preferences?.telegram_chat_id),
    twoStep,
    holidays: holidays.length,
    teamSize: team.length,
    projects: projects.length,
  };

  return (
    <PageShell>
      <PageHeader
        title={firstName ? t("dash.welcome", { name: firstName }) : t("nav.dashboard")}
        description={
          <>
            {tn("count.projects", projects.length)} ·{" "}
            {t("dash.youCanSee", { tasks: tn("count.tasks", metrics.total) })}
          </>
        }
      />

      <GettingStarted me={profile.id} role={profile.role} facts={facts} />

      {projects.length === 0 ? (
        <NoProjects canCreate={profile.role !== "member"} />
      ) : (
        <>
          {/* First, because it is the one thing on this page that says what
              to do about something rather than how many of it there are. */}
          {reportsOnProjects && <NeedsAttention health={health} />}

          {/* Every tile opens the matching list; counts and list share one
              set of predicates in lib/task-filters, so they cannot disagree. */}
          {/* Two up on a phone: six full-width tiles meant six screens of
              scrolling before the first list came into view. */}
          <section className="stagger grid grid-cols-2 gap-2.5 sm:gap-3 lg:grid-cols-3 xl:grid-cols-6">
            <MetricCard
              label={t("status.todo")}
              value={metrics.todo}
              hint={t("dash.notStarted")}
              icon={<CircleDashed />}
              href="/tasks?filter=todo"
            />
            <MetricCard
              label={t("filter.pending")}
              value={metrics.pending}
              hint={t("dash.notYetDone")}
              icon={<CircleDot />}
              href="/tasks?filter=pending"
            />
            <MetricCard
              label={t("status.in_review")}
              value={metrics.inReview}
              hint={t("dash.awaitingReview")}
              icon={<Eye />}
              href="/tasks?filter=in_review"
            />
            <MetricCard
              label={t("filter.done")}
              value={metrics.done}
              hint={t("dash.percentOfAll", { n: metrics.completionRate })}
              icon={<CircleCheck />}
              href="/tasks?filter=done"
            />
            <MetricCard
              label={t("filter.dueToday")}
              value={metrics.dueToday}
              hint={t("dash.dueBeforeMidnight")}
              icon={<CalendarClock />}
              href="/tasks?filter=due_today"
            />
            <MetricCard
              label={t("meta.overdue")}
              value={metrics.overdue}
              hint={metrics.overdue === 0 ? t("dash.allClear") : t("dash.pastDue")}
              icon={<CircleAlert />}
              emphasis={metrics.overdue > 0}
              href="/tasks?filter=overdue"
            />
          </section>

          <p className="-mt-1 text-xs text-muted-foreground">
            {t("dash.inProgressNote", { n: metrics.inProgress })}
          </p>

          {/* A card that summarises a list should open that list. This one
              is about every task there is. */}
          <Card className="lift transition-colors">
            <Link href="/tasks?filter=all" className="block focus-visible:outline-none">
              <CardHeader>
                <CardTitle className="flex items-center justify-between gap-2">
                  {t("dash.overallProgress")}
                  <ArrowRight className="size-3.5 text-muted-foreground rtl:-scale-x-100" />
                </CardTitle>
              </CardHeader>
              <CardContent className="flex flex-col gap-2">
                <ProgressBar
                  value={metrics.completionRate}
                  label={t("dash.overallCompletion")}
                />
                <p className="text-xs text-muted-foreground">
                  {t("dash.completeOf", { done: metrics.done, total: metrics.total })}
                </p>
              </CardContent>
            </Link>
          </Card>

          <div className="grid grid-cols-1 gap-3 lg:grid-cols-2">
            <TaskListCard
              title={t("dash.assignedToYou")}
              tasks={myTasks}
              empty={t("dash.nothingAssigned")}
              href="/my-list"
              seeAll={t("card.seeAll")}
            />
            <TaskListCard
              title={t("dash.needsAttention")}
              tasks={attention}
              empty={t("dash.noOverdue")}
              href="/tasks?filter=overdue"
              seeAll={t("card.seeAll")}
            />
          </div>

          <WorkloadCard workload={workload} me={profile} />
        </>
      )}
    </PageShell>
  );
}

function TaskListCard({
  title,
  tasks,
  empty,
  href,
  seeAll,
}: {
  title: string;
  tasks: TaskWithAssignees[];
  empty: string;
  /** Where the whole of this list lives; the heading links to it. */
  href: string;
  seeAll: string;
}) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center justify-between gap-2">
          {title}
          {/* Six rows of what may be forty. The way to the rest should not be
              somewhere else on the page. */}
          <Link
            href={href}
            className="flex items-center gap-1 text-xs font-normal text-muted-foreground transition-colors hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          >
            {seeAll}
            <ArrowRight className="size-3 rtl:-scale-x-100" />
          </Link>
        </CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-2">
        {tasks.length === 0 ? (
          <p className="text-sm text-muted-foreground">{empty}</p>
        ) : (
          tasks.map((task) => (
            <Link
              key={task.id}
              href={taskHref(task)}
              // Title and meta share a line once there is room for both. On a
              // phone there is not: the meta cluster used to be `shrink-0`,
              // which pushed the card 175px past the edge of the screen and
              // left Safari shrinking the whole page to fit.
              className="flex flex-col gap-1.5 rounded-[1.25rem] bg-foreground/[0.05] px-3.5 py-2.5 transition-colors sm:flex-row sm:items-center sm:justify-between sm:gap-3"
            >
              <span className="flex min-w-0 items-center gap-2">
                <PriorityIndicator priority={task.priority} />
                <span className="truncate text-sm">{task.title}</span>
              </span>
              <span className="flex flex-wrap items-center gap-x-2 gap-y-1 ps-5 sm:shrink-0 sm:ps-0">
                <DueDate dueAt={task.due_at} status={task.status} />
                <StatusBadge status={task.status} />
                <AssigneeStack assignees={task.assignees} max={2} />
              </span>
            </Link>
          ))
        )}
      </CardContent>
    </Card>
  );
}

/** Where a task lives: its project board, or the general list. */
function taskHref(task: { project_id: string | null }) {
  return task.project_id ? `/projects/${task.project_id}` : "/general";
}

async function NoProjects({ canCreate }: { canCreate: boolean }) {
  const { t } = await getI18n();
  return (
    <EmptyState
      icon={<FolderOpen />}
      title={t("dash.empty.title")}
      description={canCreate ? t("dash.empty.create") : t("dash.empty.wait")}
      action={
        canCreate ? (
          <Button variant="outline" size="sm" asChild>
            <Link href="/general">{t("dash.empty.goGeneral")}</Link>
          </Button>
        ) : undefined
      }
    />
  );
}
