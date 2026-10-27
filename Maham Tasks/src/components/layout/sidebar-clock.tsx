"use client";

import * as React from "react";
import {
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  ChevronsLeft,
  ChevronsRight,
  X,
} from "lucide-react";

import { Button } from "@/components/ui/button";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import {
  daysBetween,
  describeDayGap,
  describeDayGapDetail,
} from "@/lib/dates";
import {
  dayKey,
  isSameDay,
  monthGrid,
  startOfDay,
  weekdayLabels,
} from "@/lib/calendar";
import { useNow } from "@/lib/use-now";
import { cn } from "@/lib/utils";
import { useI18n } from "@/lib/i18n/client";

/** The formatters, built for the reader's language. */
function formatsFor(tag: string | undefined) {
  return {
    time: new Intl.DateTimeFormat(tag, {
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    }),
    /** No seconds here: the label is announced on focus, not read as a ticker. */
    labelTime: new Intl.DateTimeFormat(tag, { hour: "2-digit", minute: "2-digit" }),
    date: new Intl.DateTimeFormat(tag, { weekday: "short", day: "numeric", month: "short" }),
    month: new Intl.DateTimeFormat(tag, { month: "long", year: "numeric" }),
    fullDate: new Intl.DateTimeFormat(tag, {
      weekday: "long",
      day: "numeric",
      month: "long",
      year: "numeric",
    }),
    weekdays: weekdayLabels(tag, "long"),
    weekdayInitials: weekdayLabels(tag, "narrow"),
  };
}

/**
 * Live clock pinned to the foot of the sidebar, ticking to the second.
 * Clicking it opens a calendar on the current month with today marked.
 *
 * Nothing time-dependent renders until after mount: the server has no way to
 * know the viewer's clock or timezone, so rendering it during SSR would
 * guarantee a hydration mismatch.
 */
export function SidebarClock() {
  const i18n = useI18n();
  const { t, tag } = i18n;
  const formats = React.useMemo(() => formatsFor(tag), [tag]);
  const nowMs = useNow();
  const [open, setOpen] = React.useState(false);
  const [viewMonth, setViewMonth] = React.useState<Date | null>(null);
  const [selected, setSelected] = React.useState<Date | null>(null);
  /** The cell the arrow keys are on. Only one day is ever in the tab order. */
  const [focusedDay, setFocusedDay] = React.useState<Date | null>(null);

  const gridRef = React.useRef<HTMLDivElement>(null);
  const shouldRestoreFocus = React.useRef(false);

  // Opening lands on the selected date's month, or on this month when there
  // is no selection — what a date picker is expected to do.
  const handleOpenChange = (next: boolean) => {
    if (next) {
      const landing = selected ?? startOfDay(new Date());
      setViewMonth(landing);
      setFocusedDay(landing);
    }
    setOpen(next);
  };

  const today = nowMs === null ? null : new Date(nowMs);
  const month = viewMonth ?? today;
  const days = month ? monthGrid(month) : [];
  const viewingThisMonth =
    month != null &&
    today != null &&
    month.getMonth() === today.getMonth() &&
    month.getFullYear() === today.getFullYear();

  const shiftMonth = (delta: number) => {
    setViewMonth((current) => {
      const base = current ?? new Date();
      return new Date(base.getFullYear(), base.getMonth() + delta, 1);
    });
  };

  const shiftYear = (delta: number) => {
    setViewMonth((current) => {
      const base = current ?? new Date();
      return new Date(base.getFullYear() + delta, base.getMonth(), 1);
    });
  };

  const jumpToToday = () => {
    const now = startOfDay(new Date());
    setViewMonth(now);
    setFocusedDay(now);
  };

  /** Move the keyboard cursor, following it into the next month if needed. */
  const moveFocus = (deltaDays: number) => {
    setFocusedDay((current) => {
      const base = current ?? startOfDay(new Date());
      const next = new Date(base);
      next.setDate(base.getDate() + deltaDays);
      shouldRestoreFocus.current = true;
      setViewMonth(new Date(next.getFullYear(), next.getMonth(), 1));
      return next;
    });
  };

  // After an arrow key walks into another month the grid is rebuilt, so the
  // focused cell has to be found again once it exists.
  React.useEffect(() => {
    if (!shouldRestoreFocus.current || !focusedDay) return;
    shouldRestoreFocus.current = false;
    gridRef.current
      ?.querySelector<HTMLButtonElement>(`[data-day="${dayKey(focusedDay)}"]`)
      ?.focus();
  }, [focusedDay, month]);

  function onGridKeyDown(event: React.KeyboardEvent) {
    const moves: Record<string, number> = {
      ArrowLeft: -1,
      ArrowRight: 1,
      ArrowUp: -7,
      ArrowDown: 7,
    };

    if (event.key in moves) {
      event.preventDefault();
      moveFocus(moves[event.key]);
    } else if (event.key === "PageUp") {
      event.preventDefault();
      moveFocus(event.shiftKey ? -365 : -28);
    } else if (event.key === "PageDown") {
      event.preventDefault();
      moveFocus(event.shiftKey ? 365 : 28);
    } else if (event.key === "Home" || event.key === "End") {
      event.preventDefault();
      const base = focusedDay ?? startOfDay(new Date());
      // Monday-first, matching the grid.
      const weekday = (base.getDay() + 6) % 7;
      moveFocus(event.key === "Home" ? -weekday : 6 - weekday);
    }
  }

  const gap =
    selected && today ? daysBetween(today, selected) : null;
  const detail = gap === null ? null : describeDayGapDetail(gap, i18n);

  return (
    <Popover open={open} onOpenChange={handleOpenChange}>
      <PopoverTrigger
        className={cn(
          "flex w-full items-center gap-2.5 rounded-xl px-2.5 py-2 text-start transition-colors",
          "text-muted-foreground hover:bg-accent/60 hover:text-foreground",
          "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-1 focus-visible:ring-offset-background",
          "data-[state=open]:bg-accent data-[state=open]:text-accent-foreground",
        )}
        aria-label={
          today
            ? t("clock.openCalendarWith", {
                time: formats.labelTime.format(today),
                date: formats.fullDate.format(today),
              })
            : t("clock.openCalendar")
        }
      >
        <CalendarDays className="size-4 shrink-0" />
        <span className="min-w-0 flex-1">
          <span className="block text-sm font-medium tabular-nums leading-tight text-foreground">
            {today ? formats.time.format(today) : "--:--:--"}
          </span>
          <span className="block truncate text-xs leading-tight">
            {today ? formats.date.format(today) : " "}
          </span>
        </span>
      </PopoverTrigger>

      <PopoverContent side="top" align="start" className="w-[20rem]">
        <div className="mb-2 flex items-center justify-between gap-1">
          <p className="min-w-0 flex-1 truncate text-sm font-semibold text-foreground">
            {month ? formats.month.format(month) : ""}
          </p>
          <div className="flex shrink-0 items-center">
            <Button
              variant="ghost"
              size="icon-sm"
              onClick={() => shiftYear(-1)}
              aria-label={t("clock.prevYear")}
              title={t("clock.prevYear")}
            >
              <ChevronsLeft className="rtl:-scale-x-100" />
            </Button>
            <Button
              variant="ghost"
              size="icon-sm"
              onClick={() => shiftMonth(-1)}
              aria-label={t("cal.prevMonth")}
              title={t("cal.prevMonth")}
            >
              <ChevronLeft className="rtl:-scale-x-100" />
            </Button>
            <Button
              variant="ghost"
              size="icon-sm"
              onClick={() => shiftMonth(1)}
              aria-label={t("cal.nextMonth")}
              title={t("cal.nextMonth")}
            >
              <ChevronRight className="rtl:-scale-x-100" />
            </Button>
            <Button
              variant="ghost"
              size="icon-sm"
              onClick={() => shiftYear(1)}
              aria-label={t("clock.nextYear")}
              title={t("clock.nextYear")}
            >
              <ChevronsRight className="rtl:-scale-x-100" />
            </Button>
          </div>
        </div>

        {/* One roving tab stop: Tab reaches the grid, arrows move within it,
            which is how a date grid is expected to behave. */}
        <div
          ref={gridRef}
          role="grid"
          aria-label={t("clock.chooseDate")}
          onKeyDown={onGridKeyDown}
          className="grid grid-cols-7 gap-0.5"
        >
          {formats.weekdays.map((day, index) => (
            <div
              key={day}
              role="columnheader"
              aria-label={day}
              className="pb-1 text-center text-[0.6875rem] font-medium uppercase tracking-wide text-muted-foreground"
            >
              {formats.weekdayInitials[index]}
            </div>
          ))}

          {days.map((day) => {
            const inMonth = month != null && day.getMonth() === month.getMonth();
            const isToday = today != null && isSameDay(day, today);
            const isSelected = selected != null && isSameDay(day, selected);
            const isFocused = focusedDay != null && isSameDay(day, focusedDay);

            return (
              <button
                key={dayKey(day)}
                type="button"
                data-day={dayKey(day)}
                role="gridcell"
                aria-current={isToday ? "date" : undefined}
                aria-selected={isSelected}
                tabIndex={isFocused ? 0 : -1}
                aria-label={formats.fullDate.format(day)}
                onClick={() => {
                  setSelected(isSelected ? null : day);
                  setFocusedDay(day);
                }}
                className={cn(
                  "press flex h-9 items-center justify-center rounded-lg text-sm tabular-nums transition-colors pointer-coarse:h-10",
                  "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
                  inMonth ? "text-foreground" : "text-muted-foreground/50",
                  !isSelected && !isToday && "hover:bg-accent",
                  // Today is outlined, the selection is filled — so both can
                  // be seen at once, which is the whole point of the panel.
                  isToday && !isSelected && "font-semibold ring-1 ring-inset ring-foreground/40",
                  isSelected && "bg-primary font-semibold text-primary-foreground",
                )}
              >
                {day.getDate()}
              </button>
            );
          })}
        </div>

        {/* The answer to "how far away is that?" */}
        <div
          aria-live="polite"
          className={cn(
            "mt-3 rounded-xl px-3 py-2.5",
            selected
              ? "bg-muted/60"
              : "bg-foreground/[0.04]",
          )}
        >
          {selected && gap !== null ? (
            <>
              <p className="text-lg font-bold leading-tight tracking-tight">
                {describeDayGap(gap, i18n)}
              </p>
              <p className="mt-0.5 truncate text-xs text-muted-foreground">
                {formats.fullDate.format(selected)}
                {detail && ` · ${detail}`}
              </p>
            </>
          ) : (
            <p className="text-xs leading-relaxed text-muted-foreground">
              {t("clock.pickHint")}
            </p>
          )}
        </div>

        <div className="mt-2 flex items-center gap-2">
          <Button
            variant="outline"
            size="sm"
            className="flex-1"
            onClick={jumpToToday}
            disabled={viewingThisMonth && selected === null}
          >
            {t("nav.today")}
          </Button>
          {selected && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setSelected(null)}
              aria-label={t("clock.clearSelected")}
            >
              <X />
              {t("common.clear")}
            </Button>
          )}
        </div>
      </PopoverContent>
    </Popover>
  );
}
