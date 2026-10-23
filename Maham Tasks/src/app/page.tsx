import Link from "next/link";
import { redirect } from "next/navigation";
import { ArrowRight, CircleCheck, CircleDashed } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { ThemeToggle } from "@/components/theme/theme-toggle";
import { LanguageSelector } from "@/components/layout/language-selector";
import { createClient } from "@/lib/supabase/server";
import { isSupabaseConfigured } from "@/lib/supabase/env";
import { TASK_PRIORITIES, TASK_STATUSES } from "@/lib/constants";
import { getI18n } from "@/lib/i18n/server";

/**
 * Public entry point. Signed-in visitors go straight to their dashboard;
 * everyone else gets a short overview plus the setup checklist, which doubles
 * as a live check that the design tokens and fonts are wired up.
 */
export default async function Home() {
  const configured = isSupabaseConfigured();
  const { t } = await getI18n();

  if (configured) {
    const supabase = await createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (user) redirect("/dashboard");
  }

  return (
    <div className="min-h-svh bg-background">
      <header className="sticky top-0 z-40 bg-background/80 backdrop-blur">
        <div className="mx-auto flex h-14 w-full max-w-5xl items-center justify-between px-4 sm:px-6">
          <div className="flex items-center gap-2.5">
            <div className="flex size-6 items-center justify-center rounded bg-primary text-[10px] font-bold text-primary-foreground">
              A
            </div>
            <span className="text-sm font-medium tracking-tight">
              {t("shell.brand")}
            </span>
            <Badge variant="muted" className="hidden sm:inline-flex">
              {t("shell.tagline")}
            </Badge>
          </div>
          <div className="flex items-center gap-1">
            <LanguageSelector />
            <ThemeToggle />
            <Button size="sm" variant="outline" asChild>
              <Link href="/login">
                {t("auth.signIn")}
                <ArrowRight className="rtl:-scale-x-100" />
              </Link>
            </Button>
          </div>
        </div>
      </header>

      <main className="mx-auto w-full max-w-5xl px-4 py-12 sm:px-6 sm:py-16">
        <div className="max-w-2xl">
          <h1 className="text-3xl font-semibold tracking-tight sm:text-4xl">
            {t("landing.title")}
          </h1>
          <p className="mt-3 text-base leading-relaxed text-muted-foreground">
            {t("landing.blurb")}
          </p>
          <div className="mt-6 flex flex-wrap gap-2">
            <Button asChild>
              <Link href="/login">
                {t("auth.signIn")}
                <ArrowRight className="rtl:-scale-x-100" />
              </Link>
            </Button>
          </div>
        </div>

        <Separator className="my-10" />

        <section className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <Card>
            <CardHeader>
              <CardTitle>{t("landing.taskStatus")}</CardTitle>
            </CardHeader>
            <CardContent className="flex flex-wrap gap-1.5">
              {TASK_STATUSES.map((status) => (
                <Badge key={status.value} variant={status.variant}>
                  {t(status.label)}
                </Badge>
              ))}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>{t("landing.priorityScale")}</CardTitle>
            </CardHeader>
            <CardContent className="flex flex-col gap-2">
              {TASK_PRIORITIES.map((priority) => (
                <div
                  key={priority.value}
                  className="flex items-center justify-between text-sm"
                >
                  <span className="text-muted-foreground">{t(priority.label)}</span>
                  <span className="flex gap-0.5" aria-hidden>
                    {[1, 2, 3, 4].map((bar) => (
                      <span
                        key={bar}
                        className={
                          bar <= priority.weight
                            ? "h-3 w-1 rounded-[1px] bg-foreground"
                            : "h-3 w-1 rounded-[1px] bg-border"
                        }
                      />
                    ))}
                  </span>
                </div>
              ))}
            </CardContent>
          </Card>
        </section>

        {!configured && (
          <section className="mt-4">
            <Card>
              <CardHeader>
                <CardTitle>{t("landing.setup")}</CardTitle>
              </CardHeader>
              <CardContent className="flex flex-col gap-2 text-sm">
                <SetupRow done label={t("landing.setup.stack")} />
                <SetupRow done label={t("landing.setup.type")} />
                <SetupRow done label={t("landing.setup.ui")} />
                <SetupRow label={t("landing.setup.env")} />
              </CardContent>
            </Card>
          </section>
        )}
      </main>
    </div>
  );
}

function SetupRow({ done, label }: { done?: boolean; label: string }) {
  return (
    <div className="flex items-center gap-2">
      {done ? (
        <CircleCheck className="size-4 shrink-0 text-foreground" />
      ) : (
        <CircleDashed className="size-4 shrink-0 text-muted-foreground" />
      )}
      <span className={done ? "text-foreground" : "text-muted-foreground"}>
        {label}
      </span>
    </div>
  );
}
