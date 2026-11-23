"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { CalendarOff, Loader2, Plus, Trash2 } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import type { Holiday } from "@/components/work-calendar/holidays-provider";
import {
  addFixedNationalHolidays,
  addHoliday,
  removeHoliday,
} from "@/lib/data/holiday-actions";
import { useI18n } from "@/lib/i18n/client";

/** Consecutive days under one name, as people think of them: "Eid al-Fitr, 3 days". */
type Run = { name: string; from: string; to: string; days: number };

function runsOf(holidays: Holiday[]): Run[] {
  const runs: Run[] = [];
  for (const { day, name } of [...holidays].sort((a, b) => a.day.localeCompare(b.day))) {
    const last = runs[runs.length - 1];
    const dayBefore = new Date(`${day}T00:00:00Z`);
    dayBefore.setUTCDate(dayBefore.getUTCDate() - 1);
    if (last && last.name === name && last.to === dayBefore.toISOString().slice(0, 10)) {
      last.to = day;
      last.days += 1;
    } else {
      runs.push({ name, from: day, to: day, days: 1 });
    }
  }
  return runs;
}

/**
 * The company's holidays: the days, besides Friday and Saturday, the office
 * is closed. Date shortcuts step over them, the calendar marks them, and no
 * reminders or morning summaries go out on them.
 */
export function HolidaySettings({
  holidays,
  canEdit,
}: {
  holidays: Holiday[];
  canEdit: boolean;
}) {
  const router = useRouter();
  const i18n = useI18n();
  const { t, tn, tm, tag } = i18n;
  const [name, setName] = React.useState("");
  const [from, setFrom] = React.useState("");
  const [to, setTo] = React.useState("");
  const [pending, startTransition] = React.useTransition();

  const today = new Date().toISOString().slice(0, 10);
  const upcoming = runsOf(holidays).filter((run) => run.to >= today);
  // The next year whose fixed days are still ahead: this one until Liberation
  // Day has passed, then the next.
  const fixedYear =
    today <= `${today.slice(0, 4)}-02-26` ? Number(today.slice(0, 4)) : Number(today.slice(0, 4)) + 1;

  const format = (iso: string) =>
    new Date(`${iso}T12:00:00Z`).toLocaleDateString(tag, {
      weekday: "short",
      day: "numeric",
      month: "short",
      year: "numeric",
      timeZone: "UTC",
    });

  const add = (event: React.FormEvent) => {
    event.preventDefault();
    startTransition(async () => {
      const outcome = await addHoliday({ name, from, to });
      if (!outcome.ok) {
        toast.error(tm(Object.values(outcome.fieldErrors ?? {})[0] ?? outcome.error));
        return;
      }
      toast.success(t("holiday.added"));
      setName("");
      setFrom("");
      setTo("");
      router.refresh();
    });
  };

  const addFixed = () =>
    startTransition(async () => {
      const outcome = await addFixedNationalHolidays(fixedYear, {
        newYear: t("holiday.newYear"),
        national: t("holiday.national"),
        liberation: t("holiday.liberation"),
      });
      if (!outcome.ok) {
        toast.error(tm(outcome.error));
        return;
      }
      toast.success(t("holiday.added"));
      router.refresh();
    });

  const remove = (run: Run) =>
    startTransition(async () => {
      const outcome = await removeHoliday({ from: run.from, to: run.to });
      if (!outcome.ok) {
        toast.error(tm(outcome.error));
        return;
      }
      toast.success(t("holiday.removed"));
      router.refresh();
    });

  return (
    <Card>
      <CardHeader>
        <CardTitle role="heading" aria-level={2} className="flex items-center gap-2">
          <CalendarOff className="size-4 text-muted-foreground" aria-hidden />
          {t("holiday.title")}
        </CardTitle>
        <CardDescription>{t("holiday.description")}</CardDescription>
      </CardHeader>

      <CardContent className="flex flex-col gap-5">
        {upcoming.length === 0 ? (
          <p className="rounded-[1.25rem] bg-foreground/[0.04] px-4 py-3 text-sm text-muted-foreground">
            {t("holiday.none")}
          </p>
        ) : (
          <ul className="flex flex-col gap-1.5" aria-label={t("holiday.title")}>
            {upcoming.map((run) => (
              <li
                key={run.from}
                className="flex items-center justify-between gap-3 rounded-[1.25rem] bg-foreground/[0.04] px-4 py-2.5"
              >
                <span className="min-w-0">
                  <span className="block truncate text-sm font-medium">{run.name}</span>
                  <span className="block text-xs text-muted-foreground">
                    {run.days === 1 ? format(run.from) : `${format(run.from)} – ${format(run.to)}`}
                    {" · "}
                    {tn("holiday.days", run.days)}
                  </span>
                </span>
                {canEdit && (
                  <Button
                    variant="ghost"
                    size="icon-sm"
                    onClick={() => remove(run)}
                    disabled={pending}
                    aria-label={t("holiday.remove", { name: run.name })}
                    title={t("holiday.remove", { name: run.name })}
                  >
                    <Trash2 />
                  </Button>
                )}
              </li>
            ))}
          </ul>
        )}

        {canEdit ? (
          <>
            <form onSubmit={add} className="flex flex-col gap-3">
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="holiday-name">{t("holiday.name")}</Label>
                <Input
                  id="holiday-name"
                  value={name}
                  onChange={(event) => setName(event.target.value)}
                  placeholder={t("holiday.namePlaceholder")}
                  maxLength={80}
                  required
                />
              </div>
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <div className="flex flex-col gap-1.5">
                  <Label htmlFor="holiday-from">{t("holiday.from")}</Label>
                  <Input
                    id="holiday-from"
                    type="date"
                    value={from}
                    onChange={(event) => setFrom(event.target.value)}
                    required
                  />
                </div>
                <div className="flex flex-col gap-1.5">
                  <Label htmlFor="holiday-to">{t("holiday.to")}</Label>
                  <Input
                    id="holiday-to"
                    type="date"
                    value={to}
                    min={from || undefined}
                    onChange={(event) => setTo(event.target.value)}
                  />
                </div>
              </div>
              <div>
                <Button type="submit" disabled={pending || !name.trim() || !from}>
                  {pending ? <Loader2 className="animate-spin" /> : <Plus />}
                  {t("holiday.add")}
                </Button>
              </div>
            </form>

            <div className="flex flex-col gap-2 rounded-[1.25rem] bg-foreground/[0.04] px-4 py-3">
              <p className="text-xs leading-relaxed text-muted-foreground">
                {t("holiday.islamicNote")}
              </p>
              <div>
                <Button variant="outline" size="sm" onClick={addFixed} disabled={pending}>
                  {t("holiday.addFixed", { year: fixedYear })}
                </Button>
              </div>
            </div>
          </>
        ) : (
          <p className="text-xs text-muted-foreground">{t("holiday.readOnly")}</p>
        )}
      </CardContent>
    </Card>
  );
}
