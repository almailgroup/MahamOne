"use client";

import { cn } from "@/lib/utils";
import { useI18n } from "@/lib/i18n/client";

/**
 * How sound the password is, in four honest steps.
 *
 * Deliberately not a percentage or a "strength score": those imply a precision
 * nobody has, and they reward `P@ssw0rd!` for having a symbol in it. This
 * counts length first — the thing that actually matters — and treats variety
 * as a secondary bonus. It never blocks anything; the minimum is enforced by
 * the schema on the server.
 */
const LABELS = [
  "auth.strength.tooShort",
  "auth.strength.weak",
  "auth.strength.good",
  "auth.strength.strong",
] as const;

export function strengthOf(value: string): number {
  if (value.length < 8) return 0;

  let score = 1;
  if (value.length >= 12) score += 1;
  if (value.length >= 16) score += 1;

  const variety = [/[a-z]/, /[A-Z]/, /\d/, /[^\w]/].filter((re) =>
    re.test(value),
  ).length;
  if (variety >= 3 && score < 3) score += 1;

  return Math.min(score, 3);
}

export function PasswordMeter({ value }: { value: string }) {
  const { t } = useI18n();
  if (!value) {
    return (
      <p className="text-xs text-muted-foreground">
        {t("auth.passwordHint")}
      </p>
    );
  }

  const score = strengthOf(value);

  return (
    <div className="flex items-center gap-2">
      <span className="flex flex-1 gap-1" aria-hidden>
        {[0, 1, 2, 3].map((step) => (
          <span
            key={step}
            className={cn(
              "h-1 flex-1 rounded-full transition-colors",
              step <= score
                ? score === 0
                  ? "bg-warning"
                  : "bg-foreground"
                : "bg-border",
            )}
          />
        ))}
      </span>
      <span
        className={cn(
          "w-16 shrink-0 text-end text-xs",
          score === 0 ? "font-medium text-warning" : "text-muted-foreground",
        )}
      >
        {t(LABELS[score])}
      </span>
    </div>
  );
}
