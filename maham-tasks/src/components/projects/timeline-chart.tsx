"use client";

import * as React from "react";
import { Check } from "lucide-react";

import { LegendKey } from "@/components/reports/chart-card";
import { formatDateTime } from "@/lib/dates";
import { useI18n } from "@/lib/i18n/client";
import type { TimelineLayout, TimelineLane, TimelinePoint } from "@/lib/timeline";
import type { TaskWithAssignees } from "@/lib/supabase/database.types";
import { cn } from "@/lib/utils";

/** Enough room per week, or per month, for its label and a few dots. */
const WEEK_PX = 68;
const MONTH_PX = 104;

/**
 * The project's milestones on one time axis, with the dated work under each.
 *
 * A lane per milestone: a soft bar from its earliest task to its date, a dot
 * for each task where it falls due, and the milestone itself at the end. It
 * reads in the page's direction, so in Arabic time runs right to left. The
 * cards below it say everything again in words, so nothing here is only
 * readable by position or colour.
 */
export function TimelineChart({
  layout,
  onOpenTask,
  onShowMilestone,
}: {
  layout: TimelineLayout<TaskWithAssignees>;
  onOpenTask: (task: TaskWithAssignees) => void;
  onShowMilestone: (id: string) => void;
}) {
  const { t, tag, timeZone } = useI18n();
  const scroller = React.useRef<HTMLDivElement>(null);
  const plot = React.useRef<HTMLDivElement>(null);
  const [width, setWidth] = React.useState(0);

  React.useEffect(() => {
    const element = plot.current;
    if (!element) return;
    const observer = new ResizeObserver(([entry]) => setWidth(entry.contentRect.width));
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  // A date label runs on from its tick; the Today pill sits centred on its
  // day. Any label the pill would cover is left out rather than half shown.
  const underToday = (fraction: number) => {
    const gap = (fraction - layout.today) * width;
    return width > 0 && gap > -66 && gap < 28;
  };

  const minWidth =
    layout.grain === "week"
      ? (layout.days / 7) * WEEK_PX
      : (layout.days / 30.4) * MONTH_PX;

  // Open on today rather than on the far past: a week of context behind it.
  React.useEffect(() => {
    const element = scroller.current;
    if (!element || element.scrollWidth <= element.clientWidth) return;
    const offset = Math.max(0, layout.today * element.scrollWidth - (layout.grain === "week" ? WEEK_PX : MONTH_PX));
    const rtl = getComputedStyle(element).direction === "rtl";
    element.scrollLeft = rtl ? -offset : offset;
  }, [layout.today, layout.grain]);

  const tickLabel = (day: string) =>
    new Date(`${day}T12:00:00Z`).toLocaleDateString(tag, {
      timeZone: "UTC",
      ...(layout.grain === "week" ? { day: "numeric", month: "short" } : { month: "short" }),
    });
  const dayLabel = (day: string) =>
    new Date(`${day}T12:00:00Z`).toLocaleDateString(tag, {
      timeZone: "UTC",
      weekday: "short",
      day: "numeric",
      month: "short",
    });

  const at = (fraction: number) => ({ insetInlineStart: `${fraction * 100}%` });

  return (
    <section
      className="flex flex-col gap-4 rounded-xl border border-slate-200 bg-surface p-4 shadow-xs sm:p-5"
      aria-label={t("timeline.title")}
    >
      <div className="flex flex-wrap items-start justify-between gap-x-4 gap-y-2">
        <div className="min-w-0">
          <h2 className="text-base font-semibold text-slate-900">{t("timeline.title")}</h2>
          <p className="mt-0.5 text-sm text-slate-500">
            {t("timeline.range", { from: dayLabel(layout.first), to: dayLabel(layout.last) })}
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-x-4 gap-y-1.5">
          <LegendKey swatch="size-3 rounded-full bg-primary-solid" label={t("timeline.legendMilestone")} />
          <LegendKey swatch="size-2.5 rounded-full bg-primary-400" label={t("timeline.legendTask")} />
          <LegendKey swatch="size-2.5 rounded-full bg-warning-marker" label={t("timeline.legendLate")} />
        </div>
      </div>

      <div ref={scroller} className="-mx-4 overflow-x-auto px-4 pb-1 [scrollbar-width:thin] sm:-mx-5 sm:px-5">
        <div ref={plot} className="relative" style={{ minWidth: `${Math.ceil(minWidth)}px` }}>
          {/* Today: a soft column the height of the chart, not a rule. */}
          <div
            aria-hidden
            className="pointer-events-none absolute inset-y-0 z-0 w-7 -translate-x-1/2 rounded-full bg-primary/[0.07] rtl:translate-x-1/2"
            style={at(layout.today)}
          />

          <div className="relative h-7" aria-hidden>
            {layout.ticks.filter((tick) => !underToday(tick.at)).map((tick) => (
              <span
                key={tick.day}
                className="absolute top-1 whitespace-nowrap text-[0.6875rem] tabular-nums text-slate-500"
                style={at(tick.at)}
              >
                {tickLabel(tick.day)}
              </span>
            ))}
            <span
              className="absolute top-0 z-10 -translate-x-1/2 rounded-full bg-primary-solid px-2 py-0.5 text-[0.6875rem] font-semibold text-on-primary shadow-xs rtl:translate-x-1/2"
              style={at(layout.today)}
            >
              {t("timeline.today")}
            </span>
          </div>

          <ol className="relative flex flex-col gap-3">
            {layout.lanes.map((lane) => (
              <Lane
                key={lane.milestone?.id ?? "loose"}
                lane={lane}
                at={at}
                dayLabel={dayLabel}
                dueLabel={(iso) => formatDateTime(iso, tag, timeZone)}
                onOpenTask={onOpenTask}
                onShowMilestone={onShowMilestone}
              />
            ))}
          </ol>
        </div>
      </div>
    </section>
  );
}

function Lane({
  lane,
  at,
  dayLabel,
  dueLabel,
  onOpenTask,
  onShowMilestone,
}: {
  lane: TimelineLane<TaskWithAssignees>;
  at: (fraction: number) => React.CSSProperties;
  dayLabel: (day: string) => string;
  dueLabel: (iso: string) => string;
  onOpenTask: (task: TaskWithAssignees) => void;
  onShowMilestone: (id: string) => void;
}) {
  const { t } = useI18n();
  const { milestone } = lane;
  const late = lane.state === "late";
  const reached = lane.state === "reached";
  const name = milestone?.title ?? t("timeline.loose");

  return (
    <li className="flex flex-col gap-1">
      {/* Held at the start edge while the chart scrolls under it. */}
      <span className="sticky start-0 flex w-fit max-w-[16rem] items-center gap-1.5 text-xs">
        <span className="truncate font-medium text-slate-700">{name}</span>
        {milestone && (
          <span className={cn("shrink-0 tabular-nums", late ? "font-semibold text-warning" : "text-slate-500")}>
            {dayLabel(milestone.due_on)}
          </span>
        )}
      </span>

      {/* Translucent slate, so the Today column behind the lanes shows through. */}
      <div className="relative h-8 rounded-full bg-slate-100/70">
        {lane.to > lane.from && (
          <span
            aria-hidden
            className={cn(
              "absolute top-1/2 h-2.5 -translate-y-1/2 rounded-full",
              milestone ? "bg-slate-300/70" : "bg-slate-200/70",
            )}
            style={{ ...at(lane.from), width: `${(lane.to - lane.from) * 100}%` }}
          />
        )}

        {lane.points.map((point) => (
          <TaskDot key={point.task.id} point={point} at={at} dueLabel={dueLabel} onOpen={onOpenTask} />
        ))}

        {milestone && (
          <button
            type="button"
            onClick={() => onShowMilestone(milestone.id)}
            aria-label={t(
              reached ? "timeline.milestoneReached" : late ? "timeline.milestoneLate" : "timeline.milestoneDue",
              { title: milestone.title, date: dayLabel(milestone.due_on) },
            )}
            className="group absolute top-1/2 z-20 flex size-8 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full rtl:translate-x-1/2"
            style={at(lane.to)}
          >
            <span
              className={cn(
                "flex size-4 items-center justify-center rounded-full text-on-primary ring-4 transition-transform group-hover:scale-125 group-focus-visible:scale-125",
                late ? "bg-warning-marker ring-warning-marker/20" : "bg-primary-solid ring-primary-500/20",
              )}
            >
              {reached && <Check className="size-2.5" strokeWidth={3.5} />}
            </span>
            <Tip at={lane.to}>
              <span className="block font-semibold text-slate-900">{milestone.title}</span>
              <span className="block text-slate-500">{dayLabel(milestone.due_on)}</span>
            </Tip>
          </button>
        )}
      </div>
    </li>
  );
}

function TaskDot({
  point,
  at,
  dueLabel,
  onOpen,
}: {
  point: TimelinePoint<TaskWithAssignees>;
  at: (fraction: number) => React.CSSProperties;
  dueLabel: (iso: string) => string;
  onOpen: (task: TaskWithAssignees) => void;
}) {
  const { t } = useI18n();
  const { task } = point;
  const done = task.status === "done";
  const due = dueLabel(task.due_at as string);

  return (
    <button
      type="button"
      onClick={() => onOpen(task)}
      aria-label={t(point.overdue ? "timeline.taskLate" : done ? "timeline.taskDone" : "timeline.taskDue", {
        title: task.title,
        date: due,
      })}
      // The hit area is the lane's height; the dot inside it is small.
      className="group absolute top-1/2 z-10 flex size-7 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full rtl:translate-x-1/2"
      style={at(point.at)}
    >
      <span
        className={cn(
          "size-2.5 rounded-full ring-2 ring-surface transition-transform group-hover:scale-150 group-focus-visible:scale-150",
          point.overdue ? "bg-warning-marker" : done ? "bg-primary-200" : "bg-primary-400",
        )}
      />
      <Tip at={point.at}>
        <span className="block font-semibold text-slate-900">{task.title}</span>
        <span className={cn("block", point.overdue ? "font-semibold text-warning" : "text-slate-500")}>
          {due}
        </span>
      </Tip>
    </button>
  );
}

/** A tooltip over a mark, kept inside the chart at either end. */
function Tip({ at, children }: { at: number; children: React.ReactNode }) {
  return (
    <span
      role="presentation"
      className={cn(
        "pointer-events-none absolute bottom-full z-30 mb-1 hidden w-max max-w-56 rounded-lg border border-slate-200 bg-surface px-3 py-2 text-start text-xs shadow-lg group-hover:block group-focus-visible:block",
        at < 0.2 ? "start-0" : at > 0.8 ? "end-0" : "start-1/2 -translate-x-1/2 rtl:translate-x-1/2",
      )}
    >
      {children}
    </span>
  );
}
