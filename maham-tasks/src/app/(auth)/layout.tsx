import Link from "next/link";

import { ThemeToggle } from "@/components/theme/theme-toggle";
import { LanguageSelector } from "@/components/layout/language-selector";
import { MahamOneLogo } from "@/components/layout/maham-one-logo";
import { getI18n } from "@/lib/i18n/server";

/** Centred, chrome-free shell for the sign-in and registration screens. */
export default async function AuthLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const { t } = await getI18n();
  return (
    <div className="flex min-h-svh flex-col bg-gradient-to-b from-primary-50 via-surface to-page">
      <header className="mx-auto flex h-16 w-full max-w-5xl items-center justify-between gap-2 px-4 sm:px-6">
        <Link
          href="/"
          className="flex min-w-0 items-center gap-2.5 rounded-lg pointer-coarse:min-h-11"
        >
          <MahamOneLogo className="h-7 sm:h-8" />
          <span className="truncate border-s border-slate-200 ps-2.5 text-sm font-semibold text-slate-900">
            {t("shell.brand")}
          </span>
        </Link>
        <div className="flex items-center gap-1">
          <LanguageSelector />
          <ThemeToggle />
        </div>
      </header>

      <main className="flex flex-1 items-center justify-center px-4 pb-16">
        <div className="w-full max-w-md">{children}</div>
      </main>
    </div>
  );
}
