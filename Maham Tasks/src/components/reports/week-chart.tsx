"use client";

import * as React from "react";

import { niceMax, type ReportBucket } from "@/lib/report";
import { useI18n } from "@/lib/i18n/client";

/** Finished: the theme's accent. Added: a grey for context. Validated together. */
export const FINISHED_FILL = "var(--primary)";
export const ADDED_FILL = "color-mix(in srgb, var(--foreground) 28%, var(--card))";
const GRID = "color-mix(in srgb, var(--foreground) 10%, var(--card))";

const PLOT = 200;
const TOP = 18;
const AXIS = 26;
const LEFT = 34;

/** A column with a 4px rounded top and a square foot on the baseline. */
function column(x: number, width: number, top: number, bottom: number) {
  const r = Math.min(4, width / 2, bottom - top);
  return `M${x},${bottom}V${top + r}Q${x},${top} ${x + r},${top}H${x + width - r}Q${x + width},${top} ${x + width},${top + r}V${bottom}Z`;
}

/**
 * Finished and added, period by period: two thin columns per week (or
 * month), the finished one in the accent because it is the story, the added
 * one in grey beside it for scale. One axis — both are counts of tasks.
 */
export function WeekChart({
  buckets,
  grain,
}: {
  buckets: ReportBucket[];
  grain: "week" | "month";
}) {
  const { t, tag } = useI18n();
  const box = React.useRef<HTMLDivElement>(null);
  const [width, setWidth] = React.useState(640);
  const [active, setActive] = React.useState<number | null>(null);

  React.useEffect(() => {
    const element = box.current;
    if (!element) return;
    const observer = new ResizeObserver(([entry]) => setWidth(Math.round(entry.contentRect.width)));
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  const max = niceMax(Math.max(0, ...buckets.flatMap((b) => [b.added, b.finished])));
  const ticks = [0, max / 2, max].filter((tick) => Number.isInteger(tick));
  const band = buckets.length > 0 ? (width - LEFT) / buckets.length : 0;
  const bar = Math.max(3, Math.min(24, (band - 8) / 2));
  const y = (value: number) => TOP + PLOT - (value / max) * PLOT;
  // Labels about 48px wide: skip some when the bands are narrower.
  const every = Math.max(1, Math.ceil(48 / Math.max(band, 1)));

  const name = (starts: string) =>
    new Date(`${starts}T12:00:00Z`).toLocaleDateString(tag, {
      timeZone: "UTC",
      ...(grain === "month" ? { month: "short" } : { day: "numeric", month: "short" }),
    });
  const describe = (b: ReportBucket) =>
    t(grain === "month" ? "reports.monthOf" : "reports.weekOf", { date: name(b.starts) });

  const last = buckets.length - 1;
  const shown = active !== null ? buckets[active] : null;

  return (
    // Time runs left to right in either language, as on any calendar strip.
    <div ref={box} className="relative" dir="ltr">
      <svg width={width} height={TOP + PLOT + AXIS} className="block overflow-visible" data-chart="periods">
        {ticks.map((tick) => (
          <g key={tick}>
            <line x1={LEFT} x2={width} y1={y(tick)} y2={y(tick)} stroke={GRID} strokeWidth={1} />
            <text
              x={LEFT - 8}
              y={y(tick)}
              dy="0.32em"
              textAnchor="end"
              className="fill-muted-foreground text-[10px] tabular-nums"
            >
              {tick}
            </text>
          </g>
        ))}

        {buckets.map((b, index) => {
          const middle = LEFT + band * index + band / 2;
          return (
            <g key={b.starts}>
              {active === index && (
                <rect
                  x={LEFT + band * index + 1}
                  y={TOP - 6}
                  width={Math.max(0, band - 2)}
                  height={PLOT + 6}
                  rx={8}
                  className="fill-foreground/[0.04]"
                />
              )}
              {b.finished > 0 && (
                <path d={column(middle - 1 - bar, bar, y(b.finished), TOP + PLOT)} fill={FINISHED_FILL} />
              )}
              {b.added > 0 && <path d={column(middle + 1, bar, y(b.added), TOP + PLOT)} fill={ADDED_FILL} />}
              {index % every === 0 && (
                <text
                  x={middle}
                  y={TOP + PLOT + 17}
                  textAnchor="middle"
                  className="fill-muted-foreground text-[10px]"
                >
                  {name(b.starts)}
                </text>
              )}
            </g>
          );
        })}

        {/* The latest period's finished count, on its cap: the one number
            the chart is asked about first. */}
        {last >= 0 && buckets[last].finished > 0 && (
          <text
            x={LEFT + band * last + band / 2 - 1 - bar / 2}
            y={y(buckets[last].finished) - 6}
            textAnchor="middle"
            className="fill-foreground text-[11px] font-semibold tabular-nums"
          >
            {buckets[last].finished}
          </text>
        )}

        {/* Each period's whole band answers the pointer and the keyboard,
            not only its two thin columns. */}
        {buckets.map((b, index) => (
          <rect
            key={`hit-${b.starts}`}
            x={LEFT + band * index}
            y={TOP - 6}
            width={band}
            height={PLOT + 6}
            fill="transparent"
            tabIndex={0}
            role="img"
            aria-label={`${describe(b)}: ${t("reports.finishedCount", { n: b.finished })}, ${t("reports.addedCount", { n: b.added })}`}
            onPointerEnter={() => setActive(index)}
            onPointerLeave={() => setActive(null)}
            onFocus={() => setActive(index)}
            onBlur={() => setActive(null)}
            className="outline-none"
          />
        ))}
      </svg>

      {shown && active !== null && (
        <div
          role="presentation"
          className="pointer-events-none absolute top-0 z-10 min-w-36 -translate-x-1/2 rounded-2xl bg-popover px-3 py-2 text-xs shadow-[var(--shadow-md)]"
          style={{
            left: Math.min(Math.max(LEFT + band * active + band / 2, 80), width - 80),
          }}
        >
          <p className="mb-1 text-muted-foreground">{describe(shown)}</p>
          <p className="flex items-center gap-2">
            <span aria-hidden className="h-0.5 w-3 rounded-full" style={{ background: FINISHED_FILL }} />
            <span className="font-semibold tabular-nums">{shown.finished}</span>
            <span className="text-muted-foreground">{t("reports.finished")}</span>
          </p>
          <p className="flex items-center gap-2">
            <span aria-hidden className="h-0.5 w-3 rounded-full" style={{ background: ADDED_FILL }} />
            <span className="font-semibold tabular-nums">{shown.added}</span>
            <span className="text-muted-foreground">{t("reports.added")}</span>
          </p>
        </div>
      )}
    </div>
  );
}
