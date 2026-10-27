import Link from "next/link";

import { ThemeToggle } from "@/components/theme/theme-toggle";
import { LanguageSelector } from "@/components/layout/language-selector";
import { getI18n } from "@/lib/i18n/server";

/** Centred, chrome-free shell for the sign-in and registration screens. */
export default async function AuthLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const { t } = await getI18n();
  return (
    <div className="flex min-h-svh flex-col bg-background">
      <header className="flex h-14 items-center justify-between px-4 sm:px-6">
        <Link href="/" className="flex items-center gap-2.5 pointer-coarse:min-h-11">
          <div className="flex size-6 items-center justify-center rounded bg-primary text-[10px] font-bold text-primary-foreground">
            A
          </div>
          <span className="text-sm font-medium tracking-tight">{t("shell.brand")}</span>
        </Link>
        <div className="flex items-center gap-1">
          <LanguageSelector />
          <ThemeToggle />
        </div>
      </header>

      <main className="flex flex-1 items-center justify-center px-4 pb-16">
        <div className="w-full max-w-sm">{children}</div>
      </main>
    </div>
  );
}
