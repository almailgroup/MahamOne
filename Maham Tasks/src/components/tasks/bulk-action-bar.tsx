"use client";

import * as React from "react";
import { Loader2, Trash2, X } from "lucide-react";

import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { TASK_STATUSES } from "@/lib/constants";
import { useI18n } from "@/lib/i18n/client";
import type { TaskStatus } from "@/lib/supabase/database.types";

/**
 * What to do with the tasks someone has ticked.
 *
 * Docked to the bottom of the viewport rather than pinned above the list:
 * a selection is usually made by scrolling down through rows, and an action
 * bar that scrolled away with the header would be gone by the time it was
 * wanted. Sits above the home indicator on a phone.
 */
export function BulkActionBar({
  count,
  canComplete,
  onMove,
  onDelete,
  onClear,
}: {
  count: number;
  canComplete: boolean;
  onMove: (status: TaskStatus) => Promise<void>;
  onDelete: () => Promise<void>;
  onClear: () => void;
}) {
  const { t, tn } = useI18n();
  const [busy, setBusy] = React.useState(false);

  if (count === 0) return null;

  const run = async (work: () => Promise<void>) => {
    setBusy(true);
    await work();
    setBusy(false);
  };

  return (
    <>
      <div
        role="status"
        // Rides above the phone navigation bar rather than on top of it; on a
        // desktop, where there is no such bar, it sits at the bottom as before.
        className="pointer-events-none fixed inset-x-0 bottom-0 z-40 flex justify-center px-4 pb-[calc(var(--nav-space)+var(--safe-bottom))] lg:pb-[max(1rem,env(safe-area-inset-bottom))]"
      >
        <div className="animate-rise pointer-events-auto flex flex-wrap items-center gap-2 rounded-3xl bg-popover p-2 shadow-[var(--shadow-lg)]">
          <span className="px-2 text-sm font-medium tabular-nums">
            {tn("count.selected", count)}
          </span>

          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="outline" size="sm" disabled={busy}>
                {busy && <Loader2 className="animate-spin" />}
                {t("task.moveTo")}
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="center" side="top">
              <DropdownMenuLabel>{t("task.moveTo")}</DropdownMenuLabel>
              {TASK_STATUSES.map((status) => (
                <DropdownMenuItem
                  key={status.value}
                  // The database refuses this for a member anyway; not
                  // offering it is better than letting them try and fail.
                  disabled={status.value === "done" && !canComplete}
                  onSelect={() => void run(() => onMove(status.value))}
                >
                  {t(status.label)}
                </DropdownMenuItem>
              ))}
            </DropdownMenuContent>
          </DropdownMenu>

          <Button
            variant="outline"
            size="sm"
            disabled={busy}
            onClick={() => void run(onDelete)}
          >
            <Trash2 />
            {t("common.delete")}
          </Button>

          <Button
            variant="ghost"
            size="icon-sm"
            onClick={onClear}
            aria-label={t("bulk.clearSelection")}
          >
            <X />
          </Button>
        </div>
      </div>

    </>
  );
}
