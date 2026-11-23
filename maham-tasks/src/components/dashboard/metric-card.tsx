import Link from "next/link";
import { ArrowRight } from "lucide-react";

import { cn } from "@/lib/utils";

/**
 * Metric tile. Emphasis is typographic — a large tabular figure over a small
 * muted label — so the row reads as data rather than decoration.
 */
export function MetricCard({
  label,
  value,
  hint,
  icon,
  emphasis,
  href,
}: {
  label: string;
  value: number | string;
  hint?: string;
  icon?: React.ReactNode;
  /** Tints the tile amber, for items that need attention. */
  emphasis?: boolean;
  /** Makes the whole tile a link to the matching task list. */
  href?: string;
}) {
  const className = cn(
    "group block rounded-xl border border-slate-200 bg-surface p-3.5 shadow-xs sm:p-5",
    emphasis && "border-warning-border bg-warning-surface",
    href && "lift focus-visible:outline-none",
  );

  const body = (
    <>
      <div className="flex items-center justify-between gap-2">
        <span
          className={cn(
            "text-xs font-medium sm:text-sm",
            emphasis ? "text-warning" : "text-slate-500",
          )}
        >
          {label}
        </span>
        {icon && (
          <span
            className={cn(
              // The icon in a small tinted tile of the theme's colour rather
              // than loose beside the label: a touch of colour on every tile.
              "flex size-7 items-center justify-center rounded-lg sm:size-8 [&_svg]:size-3.5 sm:[&_svg]:size-4",
              emphasis ? "bg-warning/15 text-warning" : "bg-primary-50 text-primary-600",
            )}
          >
            {icon}
          </span>
        )}
      </div>

      <p className="mt-1.5 text-2xl font-semibold tabular-nums leading-none tracking-tight text-slate-900 sm:mt-2.5">
        {value}
      </p>

      {/* The hint restates the label — "To Do / Not started" — which is worth
          the line on a desktop and is a third of the tile on a phone, where
          six of them were most of the first screen. */}
      {hint && (
        <p className="mt-1.5 hidden items-center gap-1 text-xs text-slate-500 sm:mt-2 sm:flex">
          {hint}
          {href && (
            <ArrowRight
              className="size-3 opacity-0 transition-opacity group-hover:opacity-100 rtl:-scale-x-100"
              aria-hidden
            />
          )}
        </p>
      )}
    </>
  );

  if (!href) return <div className={className}>{body}</div>;

  return (
    <Link href={href} className={className}>
      {body}
    </Link>
  );
}

/** Progress bar, as in Maham One: a slate track filled in the theme's colour. */
export function ProgressBar({
  value,
  label,
}: {
  value: number;
  label: string;
}) {
  const clamped = Math.min(100, Math.max(0, value));

  return (
    <div
      role="progressbar"
      aria-valuenow={clamped}
      aria-valuemin={0}
      aria-valuemax={100}
      aria-label={label}
      className="h-1.5 w-full overflow-hidden rounded-full bg-slate-100"
    >
      <div
        className="h-full rounded-full bg-primary-solid transition-[width] duration-300"
        style={{ width: `${clamped}%` }}
      />
    </div>
  );
}
