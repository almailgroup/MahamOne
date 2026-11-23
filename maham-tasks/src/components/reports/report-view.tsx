"use client";

import Link from "next/link";
import { ArrowDownRight, ArrowUpRight, Clock, Minus } from "lucide-react";

import { ChartCard, ChartTable, LegendKey } from "@/components/reports/chart-card";
import { PeopleChart } from "@/components/reports/people-chart";
import { WeekChart } from "@/components/reports/week-chart";
import {
  onTimeRate,
  REPORT_PERIODS,
  type ReportPeriod,
  type ReportRange,
  type WorkReport,
} from "@/lib/report";
import { useI18n } from "@/lib/i18n/client";
import type { TranslationKey } from "@/lib/i18n";
import { cn } from "@/lib/utils";

const PERIOD_LABEL: Record<ReportPeriod, TranslationKey> = {
  "4w": "reports.period.4w",
  "12w": "reports.period.12w",
  year: "reports.period.year",
};

/** "+3 on the 4 weeks before" — the comparison, said for each period. */
const CHANGE: Record<ReportPeriod, TranslationKey> = {
  "4w": "reports.change.4w",
  "12w": "reports.change.12w",
  year: "reports.change.year",
};

/** A headline number, and how it moved against the period before. */
function Tile({
  label,
  value,
  change,
  icon,
}: {
  label: string;
  value: string;
  /** Signed text for the change, or null when there is nothing to compare. */
  change?: { amount: number; text: string } | null;
  icon?: React.ReactNode;
}) {
  const Arrow = !change || change.amount === 0 ? Minus : change.amount > 0 ? ArrowUpRight : ArrowDownRight;
  return (
    <div className="flex flex-col gap-1 rounded-[1.75rem] bg-card p-5 shadow-[var(--shadow-sm)]">
      <span className="flex items-center gap-1.5 text-xs font-medium text-muted-foreground">
        {icon}
        {label}
      </span>
      <span className="text-3xl font-semibold tracking-tight">{value}</span>
      {change && (
        <span className="flex items-center gap-1 text-xs text-muted-foreground">
          <Arrow className="size-3.5" aria-hidden />
          {change.text}
        </span>
      )}
    </div>
  );
}

/**
 * The Reports page: one row of periods, four headline numbers, then the
 * period by week (or month), open work by person, and each project.
 */
export function ReportView({ report, range }: { report: WorkReport | null; range: ReportRange }) {
  const { t, tag } = useI18n();

  const periods = (
    <nav className="chip-strip -mx-4 px-4 sm:mx-0 sm:px-0" aria-label={t("reports.period")}>
      {REPORT_PERIODS.map((period) => (
        <Link
          key={period}
          href={`/reports?period=${period}`}
          aria-current={period === range.period ? "page" : undefined}
          className={cn(
            "press inline-flex items-center rounded-full px-3.5 py-1.5 text-xs transition-colors pointer-coarse:min-h-11",
            period === range.period
              ? "bg-primary text-primary-foreground"
              : "bg-foreground/[0.06] text-muted-foreground hover:bg-accent hover:text-foreground",
          )}
        >
          {t(PERIOD_LABEL[period])}
        </Link>
      ))}
    </nav>
  );

  if (!report) {
    return (
      <>
        {periods}
        <p className="rounded-[1.75rem] bg-card p-5 text-sm text-muted-foreground shadow-[var(--shadow-sm)]">
          {t("reports.notYet")}
        </p>
      </>
    );
  }

  // A true minus sign for a fall: the hyphen is too short beside a plus.
  const delta = (now: number, then: number, unit = "") => {
    const amount = now - then;
    const sign = amount > 0 ? "+" : amount < 0 ? "−" : "";
    return {
      amount,
      text: t(CHANGE[range.period], { change: `${sign}${Math.abs(amount).toLocaleString(tag)}${unit}` }),
    };
  };
  const rate = onTimeRate(report.onTime, report.withDue);
  const rateBefore = onTimeRate(report.onTimeBefore, report.withDueBefore);
  const bucketName = (starts: string) =>
    new Date(`${starts}T12:00:00Z`).toLocaleDateString(tag, {
      timeZone: "UTC",
      ...(range.grain === "month" ? { month: "long" } : { day: "numeric", month: "short" }),
    });

  return (
    <>
      {periods}

      <div className="stagger grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Tile
          label={t("reports.finished")}
          value={report.finished.toLocaleString(tag)}
          change={delta(report.finished, report.finishedBefore)}
        />
        <Tile
          label={t("reports.added")}
          value={report.added.toLocaleString(tag)}
          change={delta(report.added, report.addedBefore)}
        />
        <Tile
          label={t("reports.onTime")}
          value={rate === null ? "—" : `${rate}%`}
          change={rate !== null && rateBefore !== null ? delta(rate, rateBefore, t("reports.points")) : null}
        />
        <Tile
          label={t("reports.overdueNow")}
          value={report.overdueNow.toLocaleString(tag)}
          icon={report.overdueNow > 0 ? <Clock className="size-3.5 text-warning" aria-hidden /> : undefined}
        />
      </div>

      <ChartCard
        title={t(range.grain === "month" ? "reports.byMonth" : "reports.byWeek")}
        subtitle={t("reports.byWeekHint")}
        legend={
          <>
            <LegendKey swatch="bg-primary" label={t("reports.finished")} />
            <LegendKey swatch="bg-[color-mix(in_srgb,var(--foreground)_28%,var(--card))]" label={t("reports.added")} />
          </>
        }
        table={
          <ChartTable
            head={[t(range.grain === "month" ? "reports.month" : "reports.week"), t("reports.finished"), t("reports.added")]}
            rows={report.buckets.map((b) => [bucketName(b.starts), b.finished, b.added])}
          />
        }
      >
        <WeekChart buckets={report.buckets} grain={range.grain} />
      </ChartCard>

      <div className="grid gap-4 lg:grid-cols-2">
        <ChartCard
          title={t("reports.byPerson")}
          subtitle={t("reports.byPersonHint")}
          legend={
            <>
              <LegendKey swatch="bg-foreground" label={t("reports.onTrack")} />
              <LegendKey
                swatch="bg-warning"
                icon={<Clock className="size-3 text-warning" aria-hidden />}
                label={t("reports.overdue")}
              />
            </>
          }
          table={
            <ChartTable
              head={[t("reports.person"), t("reports.open"), t("reports.overdue")]}
              rows={report.people.map((person) => [person.name, person.open, person.overdue])}
            />
          }
        >
          <PeopleChart people={report.people} />
        </ChartCard>

        <ChartCard title={t("reports.byProject")} subtitle={t("reports.byProjectHint")}>
          {report.projects.length === 0 ? (
            <p className="text-sm text-muted-foreground">{t("reports.noProjects")}</p>
          ) : (
            <ul className="flex flex-col gap-3.5">
              {report.projects.map((project) => {
                const share = project.total === 0 ? 0 : Math.round((project.done / project.total) * 100);
                return (
                  <li key={project.id} className="flex flex-col gap-1.5">
                    <div className="flex items-baseline justify-between gap-3">
                      <Link href={`/projects/${project.id}`} className="truncate text-sm font-medium hover:underline">
                        {project.name}
                      </Link>
                      <span className="shrink-0 text-xs tabular-nums text-muted-foreground">
                        {t("reports.doneOf", { done: project.done, total: project.total })}
                        {project.overdue > 0 && (
                          <span className="ms-2 inline-flex items-center gap-1 text-foreground">
                            <Clock className="size-3 text-warning" aria-hidden />
                            {t("reports.overdueCount", { n: project.overdue })}
                          </span>
                        )}
                      </span>
                    </div>
                    <div
                      role="meter"
                      aria-valuemin={0}
                      aria-valuemax={100}
                      aria-valuenow={share}
                      aria-label={project.name}
                      className="h-2 overflow-hidden rounded-full bg-primary/15"
                    >
                      <div className="h-full rounded-full bg-primary" style={{ width: `${share}%` }} />
                    </div>
                  </li>
                );
              })}
            </ul>
          )}
        </ChartCard>
      </div>
    </>
  );
}
