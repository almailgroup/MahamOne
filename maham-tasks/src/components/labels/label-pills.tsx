"use client";

import { cn } from "@/lib/utils";
import { LABEL_DOT, useLabelsFor } from "@/components/labels/labels-provider";

/**
 * A task's labels: soft pills, each with its colour as a dot rather than a
 * fill, so a row of them stays quiet beside the title.
 */
export function LabelPills({
  ids,
  max = 3,
  className,
}: {
  ids: readonly string[];
  /** More than this collapse into "+n". */
  max?: number;
  className?: string;
}) {
  const labels = useLabelsFor(ids);
  if (labels.length === 0) return null;

  const shown = labels.slice(0, max);
  const rest = labels.length - shown.length;

  return (
    <span className={cn("flex flex-wrap items-center gap-1", className)}>
      {shown.map((label) => (
        <span
          key={label.id}
          className="inline-flex max-w-[9rem] items-center gap-1.5 rounded-full bg-slate-100 px-2.5 py-0.5 text-[0.6875rem] font-medium text-slate-700 ring-1 ring-inset ring-slate-500/10"
        >
          <span aria-hidden className={cn("size-1.5 shrink-0 rounded-full", LABEL_DOT[label.colour])} />
          <span className="truncate">{label.name}</span>
        </span>
      ))}
      {rest > 0 && (
        <span className="rounded-full bg-slate-100 px-2 py-0.5 text-[0.6875rem] font-medium tabular-nums text-slate-500 ring-1 ring-inset ring-slate-500/10">
          +{rest}
        </span>
      )}
    </span>
  );
}
