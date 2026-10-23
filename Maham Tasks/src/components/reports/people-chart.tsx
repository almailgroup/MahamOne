"use client";

import * as React from "react";

import type { ReportPerson } from "@/lib/report";
import { useI18n } from "@/lib/i18n/client";
import { cn } from "@/lib/utils";

/**
 * Open work by person: one thin bar each, on track in ink and overdue in
 * amber — the one colour this app keeps for late work — with the total at
 * the bar's end. Longest first.
 */
export function PeopleChart({ people }: { people: ReportPerson[] }) {
  const { t } = useI18n();
  const [active, setActive] = React.useState<string | null>(null);
  const longest = Math.max(1, ...people.map((person) => person.open));

  if (people.length === 0) {
    return <p className="text-sm text-muted-foreground">{t("reports.nobodyOpen")}</p>;
  }

  return (
    <ul className="flex flex-col gap-1">
      {people.map((person) => {
        const onTrack = person.open - person.overdue;
        const width = (value: number) => `${(value / longest) * 100}%`;
        const shown = active === person.id;
        return (
          <li
            key={person.id}
            tabIndex={0}
            aria-label={`${person.name}: ${t("reports.openCount", { n: person.open })}, ${t("reports.overdueCount", { n: person.overdue })}`}
            onPointerEnter={() => setActive(person.id)}
            onPointerLeave={() => setActive(null)}
            onFocus={() => setActive(person.id)}
            onBlur={() => setActive(null)}
            className={cn(
              "relative grid grid-cols-[minmax(0,7.5rem)_1fr] items-center gap-3 rounded-2xl px-2 py-1.5 outline-none transition-colors sm:grid-cols-[minmax(0,10rem)_1fr]",
              shown && "bg-foreground/[0.04]",
            )}
          >
            <span className="truncate text-sm">{person.name}</span>
            <span className="flex min-w-0 items-center gap-2">
              {/* The bar runs the way the page reads; its square foot is at
                  the start, its rounded end at the value. */}
              <span className="flex h-3 min-w-0 items-center" style={{ width: width(person.open) }}>
                {onTrack > 0 && (
                  <span
                    className={cn("h-full bg-foreground", person.overdue === 0 && "rounded-e-[4px]")}
                    style={{ width: `${(onTrack / person.open) * 100}%` }}
                  />
                )}
                {person.overdue > 0 && (
                  <span
                    // The 2px surface gap that separates the two segments.
                    className={cn("h-full rounded-e-[4px] bg-warning", onTrack > 0 && "ms-0.5")}
                    style={{ width: `${(person.overdue / person.open) * 100}%` }}
                  />
                )}
              </span>
              <span className="shrink-0 text-xs font-semibold tabular-nums">{person.open}</span>
            </span>

            {shown && (
              <span
                role="presentation"
                className="pointer-events-none absolute end-2 top-full z-10 mt-1 rounded-2xl bg-popover px-3 py-2 text-xs shadow-[var(--shadow-md)]"
              >
                <span className="flex items-center gap-2">
                  <span aria-hidden className="h-0.5 w-3 rounded-full bg-foreground" />
                  <span className="font-semibold tabular-nums">{onTrack}</span>
                  <span className="text-muted-foreground">{t("reports.onTrack")}</span>
                </span>
                <span className="flex items-center gap-2">
                  <span aria-hidden className="h-0.5 w-3 rounded-full bg-warning" />
                  <span className="font-semibold tabular-nums">{person.overdue}</span>
                  <span className="text-muted-foreground">{t("reports.overdue")}</span>
                </span>
              </span>
            )}
          </li>
        );
      })}
    </ul>
  );
}
