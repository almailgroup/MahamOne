"use client";

import { useI18n } from "@/lib/i18n/client";

/**
 * "Today", "Yesterday", or the day itself, between two days of messages.
 *
 * Sticky, so while you scroll through a long day the pill at the top keeps
 * telling you which one you are in. Shared by the team room and a private
 * thread: both are a list of messages in time order, and they should not
 * disagree about what to call a day.
 */
export function DaySeparator({ iso }: { iso: string }) {
  const { t, tag, timeZone } = useI18n();
  const dayNumber = (value: Date) =>
    new Intl.DateTimeFormat("en-CA", { timeZone }).format(value);

  const day = new Date(iso);
  const today = new Date();
  const yesterday = new Date(today);
  yesterday.setDate(today.getDate() - 1);

  const label =
    dayNumber(day) === dayNumber(today)
      ? t("chat.today")
      : dayNumber(day) === dayNumber(yesterday)
        ? t("chat.yesterday")
        : new Intl.DateTimeFormat(tag, {
            weekday: "long",
            day: "numeric",
            month: "long",
            timeZone,
          }).format(day);

  return (
    <div className="sticky top-0 z-10 my-2 flex items-center justify-center py-1">
      <span className="rounded-full bg-card px-2.5 py-0.5 text-[0.6875rem] font-medium text-muted-foreground shadow-[var(--shadow-xs)]">
        {label}
      </span>
    </div>
  );
}
