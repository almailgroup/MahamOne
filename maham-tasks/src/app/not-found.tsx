import Link from "next/link";

import { Button } from "@/components/ui/button";
import { getI18n } from "@/lib/i18n/server";

export default async function NotFound() {
  const { t } = await getI18n();

  return (
    <div className="flex min-h-svh items-center justify-center bg-background px-4">
      <div className="w-full max-w-sm rounded-3xl bg-card p-6 text-center shadow-[var(--shadow-md)]">
        <p className="font-mono text-xs text-muted-foreground">404</p>
        <h1 className="mt-1 text-base font-semibold tracking-tight">
          {t("notFound.title")}
        </h1>
        <p className="mt-1.5 text-sm leading-relaxed text-muted-foreground">
          {t("notFound.body")}
        </p>
        <Button variant="outline" size="sm" className="mt-4" asChild>
          <Link href="/dashboard">{t("notFound.back")}</Link>
        </Button>
      </div>
    </div>
  );
}
