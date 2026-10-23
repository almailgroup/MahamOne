import type { Metadata } from "next";
import { CloudOff } from "lucide-react";

import { RetryButton } from "@/components/offline/retry-button";
import { getI18n } from "@/lib/i18n/server";

export async function generateMetadata(): Promise<Metadata> {
  const { t } = await getI18n();
  return { title: t("offline.title") };
}

/**
 * What the app shows when there is no connection.
 *
 * Cached by the service worker at install, so it is the one page that is
 * there when nothing else is. It carries no data for that reason — a cache
 * is shared by everyone who uses the device, and this page is served to
 * whoever opens the app, signed in or not.
 */
export default async function OfflinePage() {
  const { t } = await getI18n();

  return (
    <main className="flex min-h-svh flex-col items-center justify-center gap-4 px-6 text-center">
      <span
        className="flex size-12 items-center justify-center rounded-full bg-muted text-muted-foreground [&_svg]:size-5"
        aria-hidden
      >
        <CloudOff />
      </span>
      <h1 className="text-lg font-semibold tracking-tight">{t("offline.heading")}</h1>
      <p className="max-w-sm text-sm text-muted-foreground">{t("offline.body")}</p>
      <RetryButton label={t("offline.retry")} />
    </main>
  );
}
