"use client";

import * as React from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import {
  ArrowRight,
  ChartColumn,
  Check,
  Compass,
  FolderPlus,
  Hand,
  KeyRound,
  Search,
  Send,
  Smartphone,
  Sun,
  Users,
  X,
} from "lucide-react";

import { Button } from "@/components/ui/button";
import { guideFor, type GuideFacts, type GuideStep } from "@/lib/guide";
import { useI18n } from "@/lib/i18n/client";
import type { TranslationKey } from "@/lib/i18n";
import type { UserRole } from "@/lib/supabase/database.types";
import { cn } from "@/lib/utils";

const ICON: Record<GuideStep, React.ComponentType<{ className?: string }>> = {
  home: Smartphone,
  telegram: Send,
  twoStep: KeyRound,
  team: Users,
  holidays: Sun,
  project: FolderPlus,
  flow: Hand,
  reports: ChartColumn,
  search: Search,
};

/** Where a step's button goes. The ones without are done where you are. */
const HREF: Partial<Record<GuideStep, string>> = {
  telegram: "/profile#reminders",
  twoStep: "/profile#two-step",
  team: "/team",
  holidays: "/settings",
  flow: "/tasks?filter=pending",
  reports: "/reports",
};

/** Per person, per device: a phone and a desk each show it once. */
const hiddenKey = (me: string) => `almail-guide-hidden:${me}`;
const tickedKey = (me: string) => `almail-guide-ticked:${me}`;

function readTicked(me: string): Set<string> {
  try {
    const raw = window.localStorage.getItem(tickedKey(me));
    const parsed: unknown = raw ? JSON.parse(raw) : [];
    return new Set(Array.isArray(parsed) ? parsed.map(String) : []);
  } catch {
    return new Set();
  }
}

function store(key: string, value: string | null) {
  try {
    if (value === null) window.localStorage.removeItem(key);
    else window.localStorage.setItem(key, value);
  } catch {
    // Private browsing with storage blocked: the guide simply comes back.
  }
}

/**
 * Getting started: the few things worth doing in the first week, as a
 * checklist at the top of the dashboard until they are done or it is put
 * away. Search has "Getting started" to bring it back.
 */
export function GettingStarted({
  me,
  role,
  facts,
}: {
  me: string;
  role: UserRole;
  facts: GuideFacts;
}) {
  const { t } = useI18n();
  const params = useSearchParams();
  const asked = params.get("guide") === "1";

  // Nothing until the browser has said what it knows, so the server's page
  // and the first paint agree.
  const [ready, setReady] = React.useState(false);
  const [hidden, setHidden] = React.useState(false);
  const [installed, setInstalled] = React.useState(false);
  const [ticked, setTicked] = React.useState<Set<string>>(new Set());

  React.useEffect(() => {
    if (asked) store(hiddenKey(me), null);
    let wasHidden = false;
    try {
      wasHidden = !asked && window.localStorage.getItem(hiddenKey(me)) === "1";
    } catch {
      // As above.
    }
    setHidden(wasHidden);
    setTicked(readTicked(me));
    setInstalled(
      window.matchMedia("(display-mode: standalone)").matches ||
        (navigator as Navigator & { standalone?: boolean }).standalone === true,
    );
    setReady(true);
  }, [me, asked]);

  if (!ready || hidden) return null;

  const items = guideFor(role, facts, { installed, ticked });
  const done = items.filter((item) => item.done).length;
  if (done === items.length && !asked) return null;

  const tick = (step: GuideStep) => {
    const next = new Set(ticked).add(step);
    setTicked(next);
    store(tickedKey(me), JSON.stringify([...next]));
  };

  const hide = () => {
    store(hiddenKey(me), "1");
    setHidden(true);
  };

  const openSearch = () => {
    tick("search");
    // The palette answers to its own shortcut from anywhere.
    window.dispatchEvent(new KeyboardEvent("keydown", { key: "k", metaKey: true, bubbles: true }));
  };

  return (
    <section
      aria-label={t("guide.title")}
      className="flex flex-col gap-4 rounded-[1.75rem] bg-card p-5 shadow-[var(--shadow-sm)]"
    >
      <div className="flex items-start gap-3">
        <span
          aria-hidden
          className="flex size-10 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary [&_svg]:size-5"
        >
          <Compass />
        </span>
        <div className="min-w-0 flex-1">
          <h2 className="text-[0.9375rem] font-semibold">{t("guide.title")}</h2>
          <p className="mt-0.5 text-xs text-muted-foreground">{t(`guide.intro.${role}` as TranslationKey)}</p>
        </div>
        <Button
          variant="ghost"
          size="icon-sm"
          onClick={hide}
          aria-label={t("guide.hide")}
          title={t("guide.hide")}
          className="-me-1.5 -mt-1 shrink-0 text-muted-foreground"
        >
          <X />
        </Button>
      </div>

      <div className="flex flex-col gap-1.5">
        <div
          role="meter"
          aria-valuemin={0}
          aria-valuemax={items.length}
          aria-valuenow={done}
          aria-label={t("guide.progress", { done, total: items.length })}
          className="h-2 overflow-hidden rounded-full bg-foreground/[0.07]"
        >
          <div
            className="h-full rounded-full bg-primary transition-[width] duration-500"
            style={{ width: `${(done / items.length) * 100}%` }}
          />
        </div>
        <p className="text-xs tabular-nums text-muted-foreground">
          {t("guide.progress", { done, total: items.length })}
        </p>
      </div>

      <ol className="grid gap-2 lg:grid-cols-2">
        {items.map(({ step, done: isDone }) => {
          const Icon = ICON[step];
          const href = HREF[step];
          const action = isDone ? null : step === "search" ? (
            <Button size="sm" variant="outline" onClick={openSearch}>
              {t("guide.search.action")}
            </Button>
          ) : href ? (
            <Button size="sm" variant="outline" asChild>
              <Link href={href} onClick={() => tick(step)}>
                {t(`guide.${step}.action` as TranslationKey)}
                <ArrowRight className="rtl:rotate-180" />
              </Link>
            </Button>
          ) : null;

          return (
            <li
              key={step}
              className={cn(
                "flex items-start gap-3 rounded-[1.25rem] px-3.5 py-3",
                isDone ? "bg-foreground/[0.025]" : "bg-foreground/[0.045]",
              )}
            >
              <span
                className={cn(
                  "mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-full [&_svg]:size-3.5",
                  isDone ? "bg-primary text-primary-foreground" : "bg-card text-muted-foreground shadow-[var(--shadow-xs)]",
                )}
              >
                {isDone ? <Check strokeWidth={3} aria-hidden /> : <Icon aria-hidden />}
                <span className="sr-only">{isDone ? t("guide.done") : t("guide.toDo")}</span>
              </span>
              <div className="min-w-0 flex-1">
                <p className={cn("text-sm font-semibold leading-snug", isDone && "text-muted-foreground")}>
                  {t(`guide.${step}.title` as TranslationKey)}
                </p>
                {!isDone && (
                  <p className="mt-0.5 text-xs leading-relaxed text-muted-foreground">
                    {t(`guide.${step}.body` as TranslationKey)}
                  </p>
                )}
                {action && <div className="mt-2">{action}</div>}
              </div>
            </li>
          );
        })}
      </ol>
    </section>
  );
}
