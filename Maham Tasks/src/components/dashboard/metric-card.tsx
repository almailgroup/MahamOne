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
    "group block rounded-[1.5rem] bg-card p-3.5 shadow-[var(--shadow-sm)] sm:rounded-3xl sm:p-5",
    emphasis && "bg-warning-surface",
    href && "lift focus-visible:outline-none",
  );

  const body = (
    <>
      <div className="flex items-center justify-between gap-2">
        <span
          className={cn(
            "text-xs font-medium sm:text-[0.8125rem]",
            emphasis ? "text-warning" : "text-muted-foreground",
          )}
        >
          {label}
        </span>
        {icon && (
          <span
            className={cn(
              // The icon in a small tinted bubble of the theme's colour
              // rather than loose beside the label: a touch of colour on
              // every tile, and it swells a little when the tile is hovered.
              "flex size-7 items-center justify-center rounded-full transition-transform duration-300 ease-[var(--ease-spring)] group-hover:scale-110 sm:size-8 [&_svg]:size-3.5 sm:[&_svg]:size-4",
              emphasis ? "bg-warning/15 text-warning" : "bg-primary/10 text-primary",
            )}
          >
            {icon}
          </span>
        )}
      </div>

      <p className="mt-1.5 text-[1.625rem] font-bold tabular-nums leading-none tracking-[-0.02em] sm:mt-3 sm:text-[2rem]">
        {value}
      </p>

      {/* The hint restates the label — "To Do / Not started" — which is worth
          the line on a desktop and is a third of the tile on a phone, where
          six of them were most of the first screen. */}
      {hint && (
        <p className="mt-1.5 hidden items-center gap-1 text-xs text-muted-foreground sm:mt-2 sm:flex">
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

/** Colourless progress bar: filled portion in the foreground tone. */
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
      className="h-1.5 w-full overflow-hidden rounded-full bg-muted"
    >
      <div
        className="h-full rounded-full bg-foreground transition-[width] duration-300"
        style={{ width: `${clamped}%` }}
      />
    </div>
  );
}
