"use client";

import * as React from "react";
import { toast } from "sonner";

import { Skeleton } from "@/components/ui/skeleton";
import { ActivityLog } from "@/components/tasks/activity-log";
import { createClient } from "@/lib/supabase/client";
import { useI18n } from "@/lib/i18n/client";
import type { TaskActivityWithActor } from "@/lib/supabase/database.types";

/**
 * Audit trail for one task, newest first.
 *
 * Loaded on demand when the Activity tab is opened, then kept live so changes
 * another person makes while the modal is open appear without a refresh.
 */
export function TaskActivityFeed({ taskId }: { taskId: string }) {
  const supabase = React.useMemo(() => createClient(), []);
  const { t } = useI18n();
  const [entries, setEntries] = React.useState<TaskActivityWithActor[] | null>(
    null,
  );

  React.useEffect(() => {
    let active = true;

    async function load() {
      const { data, error } = await supabase
        .from("task_activity")
        .select("*, actor:profiles(*)")
        .eq("task_id", taskId)
        .order("created_at", { ascending: false })
        .limit(100);

      if (!active) return;
      if (error) {
        toast.error(t("activity.loadFailed"));
        setEntries([]);
        return;
      }
      setEntries((data ?? []) as unknown as TaskActivityWithActor[]);
    }

    load();

    // New rows arrive without the joined actor, so refetch to resolve it.
    const channel = supabase
      .channel(`activity:${taskId}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "task_activity",
          filter: `task_id=eq.${taskId}`,
        },
        () => {
          load();
        },
      )
      .subscribe();

    return () => {
      active = false;
      supabase.removeChannel(channel);
    };
  }, [supabase, taskId, t]);

  if (entries === null) {
    return (
      <div className="flex flex-col gap-2">
        <Skeleton className="h-5 w-3/4" />
        <Skeleton className="h-5 w-1/2" />
        <Skeleton className="h-5 w-2/3" />
      </div>
    );
  }

  return (
    <div className="scrollbar-thin max-h-64 overflow-y-auto pe-1">
      <ActivityLog entries={entries} />
    </div>
  );
}
