"use client";

import { CircleAlert } from "lucide-react";

import { useI18n } from "@/lib/i18n/client";

/**
 * Inline validation message rendered under a form field.
 *
 * Weighted, not muted: it was styled the same as a hint, so the one line on
 * the page that says something went wrong looked like the lines that do not.
 */
export function FieldError({ message }: { message?: string }) {
  const { tm } = useI18n();
  if (!message) return null;
  return (
    <p role="alert" className="flex items-start gap-1.5 text-xs font-medium text-foreground">
      <CircleAlert className="mt-px size-3.5 shrink-0" aria-hidden />
      {tm(message)}
    </p>
  );
}

/** Form-level error banner. Monochrome: emphasis comes from the border. */
export function FormError({ message }: { message?: string | null }) {
  const { tm } = useI18n();
  if (!message) return null;
  return (
    <div
      role="alert"
      className="flex items-start gap-2 rounded-2xl bg-muted px-3 py-2.5 text-sm font-medium text-foreground"
    >
      <CircleAlert className="mt-0.5 size-4 shrink-0" aria-hidden />
      <span>{tm(message)}</span>
    </div>
  );
}
