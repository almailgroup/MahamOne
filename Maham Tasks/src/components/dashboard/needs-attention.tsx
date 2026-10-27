import Link from "next/link";
import { ArrowRight, Flag } from "lucide-react";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { StatusPill } from "@/components/projects/project-status";
import { relativeDay } from "@/lib/dates";
import { getI18n } from "@/lib/i18n/server";
import { needsAttention } from "@/lib/project-health";
import type { ProjectHealthRow } from "@/lib/supabase/database.types";

/**
 * The projects somebody should look at today, and nothing else.
 *
 * Off track, at risk, running late, or gone quiet with work still open —
 * each listed once, worst first, with every reason that applies and the last
 * thing its owner said. When nothing qualifies the block is not drawn at
 * all: a card of green ticks is a card nobody reads, and an empty page is
 * the good news.
 *
 * A failed read is the one exception. Hiding it would make a broken query
 * look exactly like a healthy portfolio, so it says so instead.
 */
export async function NeedsAttention({
  health,
}: {
  /** Null when project_health() could not be read. */
  health: ProjectHealthRow[] | null;
}) {
  const i18n = await getI18n();
  const { t, tn } = i18n;

  if (health === null) {
    return <p className="text-xs text-muted-foreground">{t("attention.unavailable")}</p>;
  }

  const items = needsAttention(health, Date.now());
  if (items.length === 0) return null;

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Flag className="size-4 text-warning" />
          {t("attention.title")}
        </CardTitle>
        <p className="text-xs text-muted-foreground">{t("attention.subtitle")}</p>
      </CardHeader>
      <CardContent className="flex flex-col gap-2">
        {items.map((item) => (
          <Link
            key={item.projectId}
            href={`/projects/${item.projectId}`}
            className="group flex flex-col gap-1.5 rounded-[1.25rem] bg-foreground/[0.05] px-3.5 py-2.5 transition-colors"
          >
            <span className="flex flex-wrap items-center gap-x-2 gap-y-1">
              <span className="text-sm font-medium">{item.name}</span>
              {item.reasons.map((reason) => {
                switch (reason.kind) {
                  case "status":
                    return <StatusPill key="status" status={reason.status} />;
                  case "overdue":
                    return (
                      <span key="overdue" className="text-xs font-medium text-warning">
                        {tn("attention.overdue", reason.count)}
                      </span>
                    );
                  case "silent": {
                    const weeks = reason.since
                      ? Math.floor((Date.now() - new Date(reason.since).getTime()) / (7 * 86_400_000))
                      : null;
                    return (
                      <span key="silent" className="text-xs text-muted-foreground">
                        {weeks === null
                          ? t("attention.never")
                          : tn("attention.silentWeeks", weeks)}
                      </span>
                    );
                  }
                }
              })}
              <ArrowRight className="ms-auto size-3.5 text-muted-foreground opacity-0 transition-opacity group-hover:opacity-100 rtl:-scale-x-100" />
            </span>
            {item.latestBody && (
              <span className="line-clamp-2 text-xs leading-relaxed text-muted-foreground">
                {item.latestBody}
                {item.latestAt && (
                  <>
                    {" — "}
                    {t("health.by", {
                      name: item.latestAuthor ?? "—",
                      when: relativeDay(item.latestAt, i18n),
                    })}
                  </>
                )}
              </span>
            )}
          </Link>
        ))}
      </CardContent>
    </Card>
  );
}
