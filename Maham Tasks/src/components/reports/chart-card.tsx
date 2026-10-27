"use client";

import * as React from "react";
import { ChartColumn, Table2 } from "lucide-react";

import { Button } from "@/components/ui/button";
import { useI18n } from "@/lib/i18n/client";
import { cn } from "@/lib/utils";

/** One key in a legend: the mark's shape and colour, beside its name. */
export function LegendKey({
  swatch,
  label,
  icon,
}: {
  /** Classes giving the swatch its fill. */
  swatch: string;
  label: string;
  /** A status shown with an icon as well as a colour. */
  icon?: React.ReactNode;
}) {
  return (
    <span className="inline-flex items-center gap-1.5 text-xs text-muted-foreground">
      <span aria-hidden className={cn("h-2.5 w-3.5 rounded-[3px]", swatch)} />
      {icon}
      {label}
    </span>
  );
}

/**
 * A chart in a card, with its legend, and a table of the same numbers one
 * tap away — so nothing is only readable by colour or by hovering.
 */
export function ChartCard({
  title,
  subtitle,
  legend,
  table,
  children,
}: {
  title: string;
  subtitle?: string;
  legend?: React.ReactNode;
  table?: React.ReactNode;
  children: React.ReactNode;
}) {
  const { t } = useI18n();
  const [asTable, setAsTable] = React.useState(false);

  return (
    <section className="flex flex-col gap-4 rounded-[1.75rem] bg-card p-5 shadow-[var(--shadow-sm)]" aria-label={title}>
      {/* The table switch stays at the top corner, however long the
          subtitle runs; it wrapped under the title on a phone. */}
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0 flex-1">
          <h2 className="text-[0.9375rem] font-semibold">{title}</h2>
          {subtitle && <p className="mt-0.5 text-xs text-muted-foreground">{subtitle}</p>}
        </div>
        {table && (
          <Button
            type="button"
            variant="ghost"
            size="sm"
            onClick={() => setAsTable((current) => !current)}
            aria-pressed={asTable}
            className="-me-2 -mt-1 shrink-0 text-muted-foreground"
          >
            {asTable ? <ChartColumn /> : <Table2 />}
            {asTable ? t("reports.showChart") : t("reports.showTable")}
          </Button>
        )}
      </div>
      {legend && !asTable && <div className="flex flex-wrap gap-x-4 gap-y-1.5">{legend}</div>}
      {asTable ? table : children}
    </section>
  );
}

/** The table behind a chart: plain rows, numbers aligned. */
export function ChartTable({ head, rows }: { head: string[]; rows: (string | number)[][] }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="text-xs text-muted-foreground">
            {head.map((cell, index) => (
              <th key={cell} className={cn("px-2 py-1.5 font-medium", index === 0 ? "text-start" : "text-end")}>
                {cell}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, index) => (
            <tr key={index} className="odd:bg-foreground/[0.03]">
              {row.map((cell, column) => (
                <td
                  key={column}
                  className={cn(
                    "px-2 py-1.5",
                    column === 0 ? "rounded-s-xl text-start" : "text-end tabular-nums",
                    column === row.length - 1 && "rounded-e-xl",
                  )}
                >
                  {cell}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
