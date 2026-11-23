"use client";

import Link from "next/link";
import { Plus, Users } from "lucide-react";

import {
  Avatar,
  AvatarFallback,
  AvatarImage,
} from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/empty-state";
import { initialsFrom } from "@/lib/initials";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { ProgressBar } from "@/components/dashboard/metric-card";
import { useI18n } from "@/lib/i18n/client";
import { PersonMenu } from "@/components/people/person-menu";
import type { Workload } from "@/lib/metrics";
import type { Profile } from "@/lib/supabase/database.types";

/**
 * Per-person workload, sized relative to the busiest member.
 *
 * Each row is a person, so each row opens what clicking a person opens
 * anywhere else in the app. It used to be the one card on the dashboard made
 * entirely of faces and names that answered nothing.
 */
export function WorkloadCard({
  workload,
  me,
}: {
  workload: Workload[];
  /** Who is looking, so a row does not offer to message them themselves. */
  me: Profile;
}) {
  const { t } = useI18n();
  const busiest = Math.max(1, ...workload.map((entry) => entry.open));

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("dash.workload")}</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {workload.length === 0 ? (
          // Nothing assigned is the one state this card cannot illustrate,
          // and a line of grey text about it is a dead end on the page people
          // open first. The way out of it is the work itself.
          <EmptyState
            compact
            icon={<Users />}
            title={t("dash.noAssigned")}
            description={t("dash.noAssignedHint")}
            action={
              <Button asChild size="sm" variant="outline">
                <Link href="/general?new=1">
                  <Plus />
                  {t("palette.newTask")}
                </Link>
              </Button>
            }
          />
        ) : (
          workload.map(({ profile, open, done, overdue }) => (
            <PersonMenu key={profile.id} person={profile} me={me}>
              <button
                type="button"
                className="flex w-full items-center gap-3 rounded-lg p-1 text-start transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              >
              <Avatar className="size-7">
                {profile.avatar_url && (
                  <AvatarImage src={profile.avatar_url} alt="" />
                )}
                <AvatarFallback className="text-[10px]">
                  {initialsFrom(profile.full_name, profile.email)}
                </AvatarFallback>
              </Avatar>

              <div className="min-w-0 flex-1">
                <div className="flex items-baseline justify-between gap-2">
                  <span className="truncate text-sm font-medium">
                    {profile.full_name ?? profile.email}
                  </span>
                  <span className="shrink-0 text-xs tabular-nums text-muted-foreground">
                    {t("dash.open", { n: open })}
                    {overdue > 0 && (
                      <span className="ms-1.5 font-medium text-foreground">
                        {t("dash.overdueCount", { n: overdue })}
                      </span>
                    )}
                  </span>
                </div>
                <div className="mt-1.5">
                  <ProgressBar
                    value={(open / busiest) * 100}
                    label={t("dash.openTasksLabel", { name: profile.full_name ?? profile.email, n: open })}
                  />
                </div>
                <p className="mt-1 text-xs text-muted-foreground">
                  {t("dash.completedCount", { n: done })}
                </p>
              </div>
              </button>
            </PersonMenu>
          ))
        )}
      </CardContent>
    </Card>
  );
}
