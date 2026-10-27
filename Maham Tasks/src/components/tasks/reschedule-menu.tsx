"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { CalendarClock, Loader2, X } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { rescheduleTask } from "@/lib/data/task-actions";
import {
  formatDateTime,
  quickDateOptions,
  relativeDay,
  toLocalInput,
} from "@/lib/dates";
import { useHolidaySet } from "@/components/work-calendar/holidays-provider";
import { useI18n } from "@/lib/i18n/client";
import type { TaskWithAssignees } from "@/lib/supabase/database.types";

/**
 * One-click rescheduling.
 *
 * Moving a due date is the commonest edit during a daily review, so it gets a
 * dedicated control instead of a trip through the full task form.
 */
export function RescheduleMenu({
  task,
  compact = false,
}: {
  task: TaskWithAssignees;
  /** Icon-only, for dense rows. */
  compact?: boolean;
}) {
  const router = useRouter();
  const i18n = useI18n();
  const holidays = useHolidaySet();
  const { t, tm, tag, timeZone } = i18n;
  const [pending, setPending] = React.useState(false);
  const [picking, setPicking] = React.useState(false);
  const [custom, setCustom] = React.useState("");

  async function apply(dueAt: string | null) {
    setPending(true);
    const outcome = await rescheduleTask(task.id, task.project_id, dueAt);
    setPending(false);

    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }

    toast.success(
      dueAt ? t("resched.movedTo", { when: formatDateTime(dueAt, tag, timeZone) }) : t("resched.cleared"),
    );
    setPicking(false);
    router.refresh();
  }

  if (picking) {
    return (
      <form
        onSubmit={(event) => {
          event.preventDefault();
          if (!custom) return;
          apply(new Date(custom).toISOString());
        }}
        className="flex items-center gap-1.5"
      >
        <Input
          type="datetime-local"
          value={custom}
          onChange={(event) => setCustom(event.target.value)}
          className="h-8 w-[13rem] text-xs"
          autoFocus
          aria-label={t("resched.newDue")}
        />
        <Button type="submit" size="sm" disabled={pending || !custom}>
          {pending && <Loader2 className="animate-spin" />}
          {t("resched.move")}
        </Button>
        <Button
          type="button"
          variant="ghost"
          size="icon-sm"
          onClick={() => setPicking(false)}
          aria-label={t("common.cancel")}
        >
          <X />
        </Button>
      </form>
    );
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="outline"
          size={compact ? "icon-sm" : "sm"}
          disabled={pending}
          aria-label={t("resched.label")}
          className={compact ? undefined : "gap-1.5 font-normal"}
        >
          {pending ? <Loader2 className="animate-spin" /> : <CalendarClock />}
          {!compact && (task.due_at ? relativeDay(task.due_at, i18n) : t("resched.noDueDate"))}
        </Button>
      </DropdownMenuTrigger>

      <DropdownMenuContent align="end" className="w-52">
        <DropdownMenuLabel>{t("resched.moveDueDate")}</DropdownMenuLabel>

        {quickDateOptions(i18n, holidays).map((option) => (
          <DropdownMenuItem
            key={option.key}
            onSelect={() => apply(option.value())}
          >
            {option.label}
          </DropdownMenuItem>
        ))}

        <DropdownMenuSeparator />

        <DropdownMenuItem
          onSelect={(event) => {
            event.preventDefault();
            setCustom(toLocalInput(task.due_at));
            setPicking(true);
          }}
        >
          {t("resched.pick")}
        </DropdownMenuItem>

        {task.due_at && (
          <DropdownMenuItem onSelect={() => apply(null)}>
            {t("resched.clear")}
          </DropdownMenuItem>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
