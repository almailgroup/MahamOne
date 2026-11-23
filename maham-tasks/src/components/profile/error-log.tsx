import { Bug } from "lucide-react";

import { formatDateTime } from "@/lib/dates";
import { getI18n } from "@/lib/i18n/server";
import type { AppError } from "@/lib/supabase/database.types";

/**
 * What has gone wrong in the deployed app, for the person who can act on it.
 *
 * Nothing used to capture this. A page that threw on somebody's phone left a
 * line in a log nobody reads, and a fault was discovered by somebody
 * mentioning it — or not mentioning it, and working around it for a month.
 *
 * Grouped by message and route, newest first, with how many times each has
 * happened. Monochrome: a fault three days ago that nobody noticed is not an
 * emergency, and amber in this app means late work.
 */
export async function ErrorLog({ errors }: { errors: AppError[] }) {
  const { t, tm, tag, timeZone } = await getI18n();
  if (errors.length === 0) return null;

  return (
    <div className="flex flex-col gap-2 rounded-2xl bg-foreground/[0.05] p-3">
      <div className="flex items-start gap-3">
        <span className="mt-0.5 text-muted-foreground [&_svg]:size-4">
          <Bug />
        </span>
        <div className="flex min-w-0 flex-1 flex-col gap-2">
          <div>
            <p className="text-sm font-medium">{t("errors.title")}</p>
            <p className="text-xs text-muted-foreground">{t("errors.subtitle")}</p>
          </div>

          <ul className="flex flex-col gap-1.5">
            {errors.slice(0, 10).map((entry, index) => (
              <li
                key={`${entry.message}-${entry.route}-${index}`}
                className="flex flex-col gap-0.5 rounded-md bg-muted/50 px-2.5 py-1.5"
              >
                <span className="flex items-baseline justify-between gap-2">
                  {/* `tm`, because a recorded fault is either a key this
                      app chose or the message an exception carried. The
                      first is translated, the second passes through. */}
                  <span className="min-w-0 truncate text-xs font-medium">
                    {tm(entry.message)}
                  </span>
                  {entry.seen > 1 && (
                    <span className="shrink-0 text-[0.6875rem] tabular-nums text-muted-foreground">
                      {t("errors.times", { n: entry.seen })}
                    </span>
                  )}
                </span>
                <span className="truncate text-[0.6875rem] text-muted-foreground">
                  {entry.route ?? "—"}
                  {" · "}
                  {t(entry.source === "browser" ? "errors.browser" : "errors.server")}
                  {" · "}
                  {formatDateTime(entry.occurred_at, tag, timeZone)}
                  {entry.person && ` · ${entry.person}`}
                </span>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </div>
  );
}
