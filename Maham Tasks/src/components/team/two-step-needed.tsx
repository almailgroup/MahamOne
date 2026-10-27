import Link from "next/link";
import { ShieldCheck } from "lucide-react";

import { Button } from "@/components/ui/button";
import { getI18n } from "@/lib/i18n/server";

/**
 * Shown to an admin who has not signed in with an authenticator app: the
 * team's accounts wait for it, and this says so before a button is pressed
 * rather than after.
 */
export async function TwoStepNeeded() {
  const { t } = await getI18n();
  return (
    <div className="flex flex-col gap-3 rounded-[1.75rem] bg-card p-5 shadow-[var(--shadow-sm)] sm:flex-row sm:items-center sm:justify-between">
      <div className="flex items-start gap-3">
        <span className="flex size-9 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary">
          <ShieldCheck className="size-4.5" aria-hidden />
        </span>
        <div className="flex flex-col gap-0.5">
          <p className="text-sm font-semibold">{t("twoStep.neededTitle")}</p>
          <p className="text-sm leading-relaxed text-muted-foreground">{t("twoStep.neededBody")}</p>
        </div>
      </div>
      <Button asChild className="shrink-0 self-start sm:self-center">
        <Link href="/profile#two-step">{t("twoStep.setUp")}</Link>
      </Button>
    </div>
  );
}
