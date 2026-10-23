"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { CalendarDays, ChevronLeft, ChevronRight } from "lucide-react";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { PageHeader, PageShell } from "@/components/layout/page-shell";
import { TaskDialog } from "@/components/tasks/task-dialog";
import { useHolidayNames } from "@/components/work-calendar/holidays-provider";
import { tasksForMonth } from "@/lib/data/calendar-actions";
import {
  AssigneeStack,
  DueDate,
  PriorityIndicator,
  StatusBadge,
  ChecklistProgressBadge,
  WaitingBadge,
  RepeatBadge,
} from "@/components/tasks/task-meta";
import { isOverdue } from "@/lib/dates";
import {
  addMonths,
  dayKey,
  dayKeyIn,
  isSameDay,
  monthGrid,
  monthParam,
  parseMonthParam,
  startOfDay,
  startOfMonth,
  todayIn,
  weekdayLabels,
} from "@/lib/calendar";
import { isoDay, isWeekend } from "@/lib/work-week";
import { useI18n } from "@/lib/i18n/client";
import { useNow } from "@/lib/use-now";
import { cn } from "@/lib/utils";
import type {
  Profile,
  Project,
  TaskWithAssignees,
} from "@/lib/supabase/database.types";

/**
 * A month of due dates.
 *
 * The board answers "what state is everything in"; the list answers "what
 * matches"; neither answers "what is landing next week". This does. Tasks sit
 * on the local day they are due, overdue ones are marked, and anything with
 * no date is counted at the top rather than silently left out.
 *
 * Every square answers a click, empty ones included: it opens that day in a
 * dialog, which lists what is due and says plainly when nothing is. A square
 * is too small to be the answer on its own — on a phone it fits a count and
 * nothing else, and on a desktop it fits three titles out of however many
 * there are.
 *
 * On a wide screen the titles inside a square are still their own buttons and
 * open the task directly, because that is the shorter path when you can
 * already see the one you want.
 */
export function CalendarView({
  tasks,
  month: initialMonth,
  partial,
  undated,
  projects,
  team,
  profile,
}: {
  /** The month the server rendered, and only that month. */
  tasks: TaskWithAssignees[];
  /** Which month those are, as `2026-09`. */
  month: string;
  /** True when that month holds more than one page can carry. */
  partial: boolean;
  /** How many tasks carry no due date at all, counted by the database. */
  undated: number;
  projects: Project[];
  team: Profile[];
  profile: Profile;
}) {
  const router = useRouter();
  const nowMs = useNow();
  const { t, tn, tag, timeZone } = useI18n();
  const weekdays = React.useMemo(() => weekdayLabels(tag, "short"), [tag]);
  const holidays = useHolidayNames();

  const [month, setMonth] = React.useState<Date>(
    () => parseMonthParam(initialMonth) ?? startOfMonth(todayIn(timeZone)),
  );

  /**
   * What each month holds, as it is asked for.
   *
   * The page arrives with one month. Turning to another fetches that one and
   * keeps it, so going back is free and no query ever asks for more than six
   * weeks of work however many years the portal has been running.
   */
  const [byMonth, setByMonth] = React.useState<
    Record<string, { tasks: TaskWithAssignees[]; truncated: boolean; failed?: boolean }>
  >(() => ({ [initialMonth]: { tasks, truncated: partial } }));
  const [loading, setLoading] = React.useState(false);

  // A new server render — a task saved, or a reload — replaces what it covers.
  React.useEffect(() => {
    setByMonth((current) => ({
      ...current,
      [initialMonth]: { tasks, truncated: partial },
    }));
  }, [initialMonth, tasks, partial]);

  const monthKey = monthParam(month);
  const shown = byMonth[monthKey];

  React.useEffect(() => {
    if (shown !== undefined) return;
    let current = true;
    setLoading(true);
    tasksForMonth(monthKey)
      .then((found) => {
        if (!current) return;
        setByMonth((all) => ({
          ...all,
          [monthKey]: { tasks: found.tasks, truncated: found.truncated },
        }));
      })
      .catch((error) => {
        // A month that could not be fetched is not an empty month. Left
        // uncaught this rejected silently, the grid drew nothing, and the
        // header said "0 due this month" — a confident lie about work that
        // is sitting there. It is recorded as failed so the header can say
        // so, and so the retry below has something to clear.
        console.error(`[calendar] ${monthKey}:`, error);
        if (!current) return;
        setByMonth((all) => ({
          ...all,
          [monthKey]: { tasks: [], truncated: false, failed: true },
        }));
      })
      .finally(() => {
        if (current) setLoading(false);
      });
    return () => {
      current = false;
    };
  }, [monthKey, shown]);
  // The day survives the close, so the dialog still has a date and a list to
  // draw while it animates out. The next open overwrites it.
  const [selectedDay, setSelectedDay] = React.useState<Date | null>(null);
  const [dayOpen, setDayOpen] = React.useState(false);
  const [activeTask, setActiveTask] = React.useState<TaskWithAssignees | null>(null);
  const [dialogOpen, setDialogOpen] = React.useState(false);

  const openDay = (day: Date) => {
    setSelectedDay(day);
    setDayOpen(true);
  };

  /** Forget a month that failed, which sends the effect above after it again. */
  const retryMonth = () => {
    setByMonth((all) => {
      const next = { ...all };
      delete next[monthKey];
      return next;
    });
  };

  /**
   * Turn to another month.
   *
   * The address is rewritten rather than navigated: a navigation would be a
   * server render and a skeleton flash for what reads as flipping a page.
   * The month's tasks are fetched beside it instead. The URL still carries
   * the month, so a reload or a shared link lands on the same one.
   */
  const goTo = (next: Date) => {
    setMonth(next);
    setDayOpen(false);
    const url = new URL(window.location.href);
    if (isSameDay(next, startOfMonth(todayIn(timeZone)))) url.searchParams.delete("month");
    else url.searchParams.set("month", monthParam(next));
    window.history.replaceState(window.history.state, "", url);
  };

  const projectName = React.useMemo(() => {
    const map = new Map(projects.map((p) => [p.id, p.name]));
    return (id: string | null) =>
      id ? (map.get(id) ?? t("common.project")) : t("common.general");
  }, [projects, t]);

  // Grouped by local day. Placement stays here because only the browser
  // knows which local day an instant falls on — a task due at 01:00 Tuesday
  // in Kuwait is still Monday in UTC.
  const byDay = React.useMemo(() => {
    const byDay = new Map<string, TaskWithAssignees[]>();
    for (const task of shown?.tasks ?? []) {
      if (!task.due_at) continue;
      const key = dayKeyIn(new Date(task.due_at), timeZone);
      byDay.set(key, [...(byDay.get(key) ?? []), task]);
    }
    for (const list of byDay.values()) {
      list.sort((a, b) => new Date(a.due_at!).getTime() - new Date(b.due_at!).getTime());
    }
    return byDay;
  }, [shown, timeZone]);

  const today = nowMs === null ? null : startOfDay(new Date(nowMs));
  const days = monthGrid(month);
  const inMonth = (day: Date) => day.getMonth() === month.getMonth();
  const dueThisMonth = days.filter(inMonth).reduce(
    (sum, day) => sum + (byDay.get(dayKey(day))?.length ?? 0),
    0,
  );

  const selectedTasks = selectedDay ? (byDay.get(dayKey(selectedDay)) ?? []) : [];
  const selectedHoliday = selectedDay ? holidays.get(isoDay(selectedDay)) : undefined;

  function openTask(task: TaskWithAssignees) {
    setDayOpen(false);
    setActiveTask(task);
    setDialogOpen(true);
  }

  return (
    <PageShell>
      <PageHeader
        title={t("nav.calendar")}
        icon={<CalendarDays />}
        description={
          <>
            {shown?.failed ? (
              <>
                {t("cal.monthFailed")}
                {" · "}
                <button
                  type="button"
                  onClick={retryMonth}
                  className="underline underline-offset-2 hover:text-foreground"
                >
                  {t("error.retry")}
                </button>
              </>
            ) : (
              <>
                {t("cal.dueThisMonth", { n: dueThisMonth })}
                {undated > 0 && ` · ${t("cal.noDate", { n: undated })}`}
                {shown?.truncated && ` · ${t("cal.partialMonth")}`}
              </>
            )}
          </>
        }
        actions={
          <div className="flex items-center gap-1">
            <Button
              variant="outline"
              size="icon-sm"
              onClick={() => goTo(addMonths(month, -1))}
              aria-label={t("cal.prevMonth")}
            >
              <ChevronLeft className="rtl:-scale-x-100" />
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={() => goTo(startOfMonth(todayIn(timeZone)))}
            >
              {t("nav.today")}
            </Button>
            <Button
              variant="outline"
              size="icon-sm"
              onClick={() => goTo(addMonths(month, 1))}
              aria-label={t("cal.nextMonth")}
            >
              <ChevronRight className="rtl:-scale-x-100" />
            </Button>
          </div>
        }
      />

      <h2 className="-mt-1 text-lg font-semibold tracking-tight" aria-live="polite">
        {month.toLocaleDateString(tag, { month: "long", year: "numeric" })}
      </h2>

      <div
        className={cn(
          "overflow-hidden rounded-3xl bg-card p-1.5 shadow-[var(--shadow-sm)] transition-opacity sm:p-2",
          // Dimmed rather than replaced: a skeleton here would throw the grid
          // away and put it back a moment later, which reads as the page
          // reloading rather than as a month arriving.
          loading && "opacity-60",
        )}
        aria-busy={loading}
      >
        <div className="grid grid-cols-7 text-center text-[0.6875rem] font-medium text-muted-foreground sm:text-xs">
          {weekdays.map((day) => (
            <div key={day} className="py-2">
              {day}
            </div>
          ))}
        </div>

        {/* Days are separate rounded cells with space between them, not
            squares in a ruled grid. */}
        <div className="grid grid-cols-7 gap-1 sm:gap-1.5" role="grid" aria-label={t("cal.gridLabel")}>
          {days.map((day) => {
            const key = dayKey(day);
            const list = byDay.get(key) ?? [];
            const isToday = today !== null && isSameDay(day, today);
            const selected = dayOpen && selectedDay !== null && isSameDay(day, selectedDay);
            // Friday and Saturday, the company's weekend (lib/work-week), and
            // the holidays an admin keeps in Settings: both are days off.
            const holiday = holidays.get(isoDay(day));
            const dayOff = isWeekend(day) || holiday !== undefined;
            const late = list.filter((task) => isOverdue(task.due_at, task.status)).length;

            return (
              <div
                key={key}
                role="gridcell"
                aria-selected={selected}
                className={cn(
                  "relative flex min-h-[4.25rem] flex-col rounded-[1rem] bg-foreground/[0.035] p-1 transition-colors sm:min-h-[6.5rem] sm:rounded-[1.25rem] sm:p-2",
                  "hover:bg-foreground/[0.06]",
                  !inMonth(day) && "bg-transparent text-muted-foreground",
                  dayOff && inMonth(day) && "bg-foreground/[0.055]",
                  isToday && "bg-primary/[0.07]",
                  selected && "bg-primary/[0.12] shadow-[var(--shadow-xs)]",
                )}
              >
                {/* The whole square is the control, laid underneath what it
                    holds so an empty corner answers a click too. The titles
                    below sit on top of it and keep their own. */}
                <button
                  type="button"
                  onClick={() => openDay(day)}
                  aria-label={[
                    t("cal.dayLabel", {
                      date: day.toLocaleDateString(tag, { weekday: "long", day: "numeric", month: "long" }),
                      n: list.length,
                    }),
                    holiday && t("cal.holiday", { name: holiday }),
                  ]
                    .filter(Boolean)
                    .join(", ")}
                  className="absolute inset-0 rounded-[inherit] transition-colors hover:bg-accent/60"
                />

                <span
                  className={cn(
                    // Centred, under its weekday heading: in the corner it sat in the
                    // curve, and out of line with the heading above it.
                    "pointer-events-none relative mb-0.5 flex size-6 items-center justify-center self-center rounded-full text-xs tabular-nums sm:size-7",
                    isToday && "bg-primary font-semibold text-primary-foreground",
                  )}
                >
                  {day.getDate()}
                </span>

                {/* A phone's square has no room for the name: a dot says "not
                    just a weekend", and tapping the day names it. */}
                {holiday && (
                  <span
                    aria-hidden
                    className="pointer-events-none relative mx-auto size-1.5 rounded-full bg-muted-foreground/60 sm:hidden"
                  />
                )}
                {holiday && (
                  <span
                    title={holiday}
                    className="pointer-events-none relative mb-0.5 hidden truncate px-1 text-center text-[0.6875rem] font-medium text-muted-foreground sm:block"
                  >
                    {holiday}
                  </span>
                )}

                {list.length > 0 && (
                  <span
                    className={cn(
                      "pointer-events-none relative mt-auto self-center rounded-full px-2 text-[0.6875rem] font-medium tabular-nums md:hidden",
                      late > 0 ? "bg-warning-surface text-warning" : "bg-muted text-foreground",
                    )}
                  >
                    {list.length}
                  </span>
                )}

                <ul className="relative hidden flex-col gap-0.5 md:flex">
                  {list.slice(0, 3).map((task) => (
                    <li key={task.id}>
                      <button
                        type="button"
                        onClick={() => openTask(task)}
                        title={task.title}
                        className={cn(
                          "w-full truncate rounded-full px-2.5 py-0.5 text-start text-xs transition-colors hover:bg-accent",
                          task.status === "done" && "text-muted-foreground line-through",
                          isOverdue(task.due_at, task.status) &&
                            "bg-warning-surface text-warning",
                        )}
                      >
                        {task.title}
                      </button>
                    </li>
                  ))}
                  {list.length > 3 && (
                    <li>
                      <button
                        type="button"
                        onClick={() => openDay(day)}
                        className="px-2.5 text-xs text-muted-foreground hover:text-foreground"
                      >
                        {t("cal.more", { n: list.length - 3 })}
                      </button>
                    </li>
                  )}
                </ul>
              </div>
            );
          })}
        </div>
      </div>

      {/* A day, opened. Empty days open too: "nothing due" is an answer, and
          a square that ignores the click looks broken. */}
      <Dialog
        open={dayOpen}
        onOpenChange={setDayOpen}
      >
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>
              {selectedDay?.toLocaleDateString(tag, {
                weekday: "long",
                day: "numeric",
                month: "long",
              })}
            </DialogTitle>
            <DialogDescription>
              {selectedHoliday && <>{t("cal.holiday", { name: selectedHoliday })} · </>}
              {selectedTasks.length === 0
                ? t("cal.nothingThatDay")
                : tn("count.tasks", selectedTasks.length)}
            </DialogDescription>
          </DialogHeader>

          {selectedTasks.length > 0 && (
            <ul className="flex flex-col gap-2">
              {selectedTasks.map((task) => (
                <li key={task.id}>
                  <button
                    type="button"
                    onClick={() => openTask(task)}
                    className="lift flex w-full flex-col gap-1.5 rounded-2xl bg-card p-3 text-start shadow-[var(--shadow-xs)] sm:flex-row sm:items-center sm:justify-between"
                  >
                    <span className="flex min-w-0 items-center gap-2">
                      <PriorityIndicator priority={task.priority} />
                      <span className="min-w-0">
                        <span className="block truncate text-sm font-medium">{task.title}</span>
                        <span className="block truncate text-xs text-muted-foreground">
                          {projectName(task.project_id)}
                        </span>
                      </span>
                    </span>
                    <span className="flex flex-wrap items-center gap-x-2 gap-y-1 ps-5 sm:shrink-0 sm:ps-0">
                      <DueDate dueAt={task.due_at} status={task.status} />
                  <RepeatBadge every={task.repeat_every} interval={task.repeat_interval} />
                  <ChecklistProgressBadge progress={task.checklist} />
                  <WaitingBadge count={task.waitingOn} status={task.status} />
                      <StatusBadge status={task.status} />
                      <AssigneeStack assignees={task.assignees} max={2} />
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </DialogContent>
      </Dialog>

      {activeTask && (
        <TaskDialog
          open={dialogOpen}
          onOpenChange={(open) => {
            setDialogOpen(open);
            if (!open) router.refresh();
          }}
          task={activeTask}
          projectId={activeTask.project_id}
          team={team}
          currentProfile={profile}
        />
      )}
    </PageShell>
  );
}
