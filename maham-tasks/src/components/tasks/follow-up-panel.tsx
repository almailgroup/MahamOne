"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { Loader2, PhoneCall, X } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { setFollowUp } from "@/lib/data/task-actions";
import { useHolidaySet } from "@/components/work-calendar/holidays-provider";
import {
  isoFromLocalInput,
  quickDateOptions,
  relativeDay,
  toLocalInput,
} from "@/lib/dates";
import { formatDateTime } from "@/lib/dates";
import { useI18n } from "@/lib/i18n/client";
import type { TaskWithAssignees } from "@/lib/supabase/database.types";

/**
 * When to chase this task, and what to chase.
 *
 * Read-only for members: a follow-up is a planning decision, and the database
 * refuses the write anyway, so the form is simply not offered.
 */
export function FollowUpPanel({
  task,
  canManage,
}: {
  task: TaskWithAssignees;
  canManage: boolean;
}) {
  const router = useRouter();
  const i18n = useI18n();
  const { t, tm, tag, timeZone } = i18n;
  const holidays = useHolidaySet();
  const [editing, setEditing] = React.useState(false);
  const [when, setWhen] = React.useState(toLocalInput(task.follow_up_at));
  const [note, setNote] = React.useState(task.follow_up_note ?? "");
  const [pending, setPending] = React.useState(false);

  React.useEffect(() => {
    setWhen(toLocalInput(task.follow_up_at));
    setNote(task.follow_up_note ?? "");
  }, [task.follow_up_at, task.follow_up_note]);

  async function save() {
    if (!when) {
      toast.error(t("follow.pickDate"));
      return;
    }
    // Wall-clock in, absolute instant out — the server cannot do this
    // conversion, it does not know the viewer's timezone.
    const followUpAt = isoFromLocalInput(when);
    if (!followUpAt) {
      toast.error(t("follow.pickValid"));
      return;
    }

    setPending(true);
    const outcome = await setFollowUp(task.id, task.project_id, {
      followUpAt,
      note,
    });
    setPending(false);

    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }
    toast.success(t("follow.set"));
    setEditing(false);
    router.refresh();
  }

  async function clear() {
    setPending(true);
    const outcome = await setFollowUp(task.id, task.project_id, null);
    setPending(false);

    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }
    toast.success(t("follow.cleared"));
    setEditing(false);
    router.refresh();
  }

  if (!editing) {
    return (
      <div className="flex flex-wrap items-center gap-2 rounded-xl bg-foreground/[0.05] px-2.5 py-2">
        <PhoneCall className="size-3.5 shrink-0 text-muted-foreground" />

        {task.follow_up_at ? (
          <span className="min-w-0 flex-1">
            <span className="block text-sm">
              {t("follow.on", { when: relativeDay(task.follow_up_at, i18n) })}
              <span className="ms-1.5 text-xs text-muted-foreground">
                {formatDateTime(task.follow_up_at, tag, timeZone)}
              </span>
            </span>
            {task.follow_up_note && (
              <span className="block text-xs text-muted-foreground">
                {task.follow_up_note}
              </span>
            )}
          </span>
        ) : (
          <span className="flex-1 text-sm text-muted-foreground">
            {t("follow.none")}
          </span>
        )}

        {canManage && (
          <div className="flex gap-1">
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() => setEditing(true)}
            >
              {task.follow_up_at ? t("follow.change") : t("follow.setButton")}
            </Button>
            {task.follow_up_at && (
              <Button
                type="button"
                variant="ghost"
                size="icon-sm"
                onClick={clear}
                disabled={pending}
                aria-label={t("follow.clear")}
              >
                {pending ? <Loader2 className="animate-spin" /> : <X />}
              </Button>
            )}
          </div>
        )}
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-2.5 rounded-xl bg-foreground/[0.05] p-3">
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="followUpAt">{t("follow.onLabel")}</Label>
        <Input
          id="followUpAt"
          type="datetime-local"
          value={when}
          onChange={(event) => setWhen(event.target.value)}
          autoFocus
        />
        <div className="flex flex-wrap gap-1.5">
          {quickDateOptions(i18n, holidays, { hour: 9, includeToday: false }).map((option) => (
            <button
              key={option.label}
              type="button"
              onClick={() => setWhen(toLocalInput(option.value()))}
              className="rounded-full bg-foreground/[0.05] px-2 py-0.5 text-xs text-muted-foreground transition-colors hover:bg-foreground/[0.09] hover:text-foreground"
            >
              {option.label}
            </button>
          ))}
        </div>
      </div>

      <div className="flex flex-col gap-1.5">
        <Label htmlFor="followUpNote">{t("follow.what")}</Label>
        <Input
          id="followUpNote"
          value={note}
          onChange={(event) => setNote(event.target.value)}
          placeholder={t("follow.whatPlaceholder")}
          maxLength={500}
        />
      </div>

      <div className="flex justify-end gap-2">
        <Button
          type="button"
          variant="ghost"
          size="sm"
          onClick={() => setEditing(false)}
          disabled={pending}
        >
          {t("common.cancel")}
        </Button>
        <Button type="button" size="sm" onClick={save} disabled={pending}>
          {pending && <Loader2 className="animate-spin" />}
          {t("follow.save")}
        </Button>
      </div>
    </div>
  );
}
