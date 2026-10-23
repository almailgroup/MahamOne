"use client";

import * as React from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { X } from "lucide-react";

import { Button } from "@/components/ui/button";
import { BottomNav } from "@/components/layout/bottom-nav";
import { SidebarNav } from "@/components/layout/sidebar-nav";
import { UserMenu } from "@/components/layout/user-menu";
import { NotificationBell } from "@/components/notifications/notification-bell";
import {
  CommandHint,
  CommandPalette,
} from "@/components/layout/command-palette";
import { SidebarResizer } from "@/components/layout/sidebar-resizer";
import { AssistantPanel } from "@/components/assistant/assistant-panel";
import { useAssistant } from "@/components/assistant/use-assistant";
import {
  SIDEBAR_CHAT_DEFAULT,
  SIDEBAR_DEFAULT,
  SIDEBAR_STORAGE_KEY,
  clampSidebarWidth,
  sidebarBounds,
} from "@/lib/sidebar";
import { ThemeToggle } from "@/components/theme/theme-toggle";
import { cn } from "@/lib/utils";
import { useScrollLock } from "@/lib/use-scroll-lock";
import { useI18n } from "@/lib/i18n/client";
import { LanguageSelector } from "@/components/layout/language-selector";
import type {
  Notification,
  Profile,
  Project,
} from "@/lib/supabase/database.types";

/**
 * Authenticated chrome: a fixed sidebar on desktop, an overlay drawer below
 * `lg`, and a slim sticky header. Kept compact — 56px header, 15rem rail — so
 * the task views get as much of the viewport as possible.
 */
export function AppShell({
  profile,
  projects,
  notifications,
  unreadCount,
  unreadMessages,
  activeProjectId,
  children,
}: {
  profile: Profile;
  projects: Project[];
  notifications: Notification[];
  unreadCount: number;
  /** Private messages waiting, for the badge on the Messages item. */
  unreadMessages: number;
  activeProjectId?: string;
  children: React.ReactNode;
}) {
  const pathname = usePathname();
  const { t } = useI18n();
  const [drawerOpen, setDrawerOpen] = React.useState(false);

  // The drawer covers the page; the page should not move under it.
  const leavingPage = React.useRef(false);
  useScrollLock(drawerOpen, leavingPage);

  /** Closing because a destination was tapped, rather than dismissed. */
  const followLink = React.useCallback(() => {
    leavingPage.current = true;
    setDrawerOpen(false);
  }, []);

  // Two independent widths, picked by what the rail is currently showing.
  // Modelling it as one width plus a saved copy meant a commit had to guess
  // which one it belonged to, and the width the assistant was dragged to was
  // thrown away on every close.
  //
  // Both are server-rendered at their defaults; the inline script in the
  // layout has already painted the stored navigation width, so adopting it
  // below syncs React's copy rather than causing a visible jump.
  const [navWidth, setNavWidth] = React.useState(SIDEBAR_DEFAULT);
  const [chatWidth, setChatWidth] = React.useState(SIDEBAR_CHAT_DEFAULT);
  const [adopted, setAdopted] = React.useState(false);

  // The assistant takes over the rail rather than opening over the board, so you
  // can read a task while asking about it. One flag drives both the rail and
  // the drawer: a second flag for the drawer drifted out of sync with this one
  // and left the hamburger reopening into the assistant.
  const [assistantOpen, setAssistantOpen] = React.useState(false);
  const assistant = useAssistant();

  // Width changes are animated only while opening or closing the assistant —
  // a transition left on during a resize drag trails the pointer by a frame.
  const [animating, setAnimating] = React.useState(false);

  const [viewportWidth, setViewportWidth] = React.useState(0);
  React.useEffect(() => {
    const measure = () => setViewportWidth(window.innerWidth);
    measure();
    window.addEventListener("resize", measure);
    return () => window.removeEventListener("resize", measure);
  }, []);

  /**
   * What the resizer may do right now. The assistant gets a wider ceiling than
   * navigation, but never more than a certain share of the window: at the `lg`
   * breakpoint the flat 640px maximum left the board narrower than the mobile
   * drawer.
   */
  const bounds = React.useMemo(() => {
    const base = sidebarBounds(assistantOpen ? "chat" : "nav");
    if (!assistantOpen || viewportWidth === 0) return base;
    const max = Math.max(
      base.min,
      Math.min(base.max, Math.round(viewportWidth * 0.45)),
    );
    return { min: base.min, max, preferred: Math.min(base.preferred, max) };
  }, [assistantOpen, viewportWidth]);

  const sidebarWidth = assistantOpen
    ? Math.min(chatWidth, bounds.max)
    : navWidth;

  React.useEffect(() => {
    try {
      const stored = window.localStorage.getItem(SIDEBAR_STORAGE_KEY);
      if (stored) setNavWidth(clampSidebarWidth(Number(stored)));
    } catch {
      // Private browsing or blocked storage: the default is fine.
    }
    setAdopted(true);
  }, []);

  // Drive both the rail and the content offset from one custom property, so
  // they cannot drift apart. Held back until the stored width has been
  // adopted: writing the default here first would paint over the value the
  // layout's inline script exists to set.
  React.useEffect(() => {
    if (!adopted) return;
    document.documentElement.style.setProperty(
      "--sidebar-width",
      `${sidebarWidth}px`,
    );
  }, [adopted, sidebarWidth]);

  const setSidebarWidth = React.useCallback(
    (value: number) => {
      if (assistantOpen) setChatWidth(clampSidebarWidth(value, "chat"));
      else setNavWidth(clampSidebarWidth(value));
    },
    [assistantOpen],
  );

  const persistWidth = React.useCallback(
    (value: number) => {
      // Only navigation widths are remembered. Clamped on the way in: a drag
      // that starts in chat mode and ends after the mode flipped would
      // otherwise store a width navigation can never use.
      if (assistantOpen) {
        setChatWidth(clampSidebarWidth(value, "chat"));
        return;
      }
      const width = clampSidebarWidth(value);
      setNavWidth(width);
      try {
        window.localStorage.setItem(SIDEBAR_STORAGE_KEY, String(width));
      } catch {
        // Not being able to remember the width is not worth surfacing.
      }
    },
    [assistantOpen],
  );

  const openAssistant = React.useCallback(() => {
    setAssistantOpen(true);
    setAnimating(true);
  }, []);

  const closeAssistant = React.useCallback(() => {
    setAssistantOpen(false);
    setAnimating(true);
    // Hand focus back to the launcher; it is about to be shown again, and the
    // element that had focus is about to be display:none.
    requestAnimationFrame(() => {
      document
        .querySelectorAll<HTMLButtonElement>("[data-assistant-launcher]")
        .forEach((button) => {
          if (button.offsetParent !== null) button.focus();
        });
    });
  }, []);

  // Deliberately not keyed on the width: a resize drag changes it every few
  // milliseconds, which would re-arm this timer for the whole drag and leave
  // the transition applied — the exact thing it is meant to avoid.
  React.useEffect(() => {
    if (!animating) return;
    const timer = setTimeout(() => setAnimating(false), 240);
    return () => clearTimeout(timer);
  }, [animating]);

  // Close the mobile drawer whenever the route changes.
  React.useEffect(() => {
    setDrawerOpen(false);
  }, [pathname]);

  // Escape closes the drawer, and hands the rail back from the assistant —
  // matching the dialog behaviour elsewhere.
  React.useEffect(() => {
    if (!drawerOpen && !assistantOpen) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      // A Radix layer that handled this keystroke marks it handled. Without
      // this check, dismissing the command palette or any dialog also
      // collapsed the assistant out of the rail behind it.
      if (event.defaultPrevented) return;
      if (drawerOpen) setDrawerOpen(false);
      else closeAssistant();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [drawerOpen, assistantOpen, closeAssistant]);

  return (
    // On a wide screen the sidebar and header are one frame, and the page is
    // a rounded panel set inside it. Tone and shape separate them; there are
    // no lines between the parts of the chrome any more.
    <div className="min-h-svh bg-background lg:bg-chrome">
      {/*
       * Without this, reaching the page content by keyboard meant tabbing
       * through the project switcher, five nav links, every project, the
       * assistant and the clock — on every page. Visually hidden until it
       * takes focus, which is the only time it is useful.
       */}
      <a
        href="#content"
        className={cn(
          "sr-only z-50 rounded-xl bg-primary px-4 py-2.5 text-sm font-medium text-primary-foreground shadow-[var(--shadow-lg)]",
          "focus:not-sr-only focus:fixed focus:start-4 focus:top-4",
        )}
      >
        {t("shell.skip")}
      </a>
      {/* Desktop rail */}
      <aside
        style={{ width: "var(--sidebar-width)" }}
        className={cn(
          "fixed inset-y-0 start-0 z-30 hidden bg-chrome lg:block",
          // Only ever on screen above `lg`, where a notch is not in play, but
          // a cover viewport applies to tablets too.
          "pt-[var(--safe-top)] pb-[var(--safe-bottom)]",
          animating && "transition-[width] duration-200 ease-out",
        )}
      >
        <div className="flex h-14 items-center gap-2.5 px-4">
          <Link
            href="/today"
            className="group flex items-center gap-2.5 rounded-full transition-opacity hover:opacity-80"
          >
            <span className="flex size-7 items-center justify-center rounded-full bg-primary text-[11px] font-bold text-primary-foreground">
              A
            </span>
            <span className="flex flex-col leading-none">
              <span className="text-sm font-semibold tracking-tight">
                {t("shell.brand")}
              </span>
              <span className="mt-0.5 text-[10px] text-muted-foreground">
                {t("shell.tagline")}
              </span>
            </span>
          </Link>
        </div>
        <div className="h-[calc(100svh-3.5rem)]">
          {/* Both are mounted and one is hidden: the navigation keeps its
              scroll position, and the conversation survives a close. */}
          <div className={cn("h-full", assistantOpen && "hidden")}>
            <SidebarNav
              profile={profile}
              projects={projects}
              activeProjectId={activeProjectId}
              unreadMessages={unreadMessages}
              onOpenAssistant={openAssistant}
            />
          </div>
          <div className={cn("h-full", !assistantOpen && "hidden")}>
            <AssistantPanel assistant={assistant} active={assistantOpen} onClose={closeAssistant} />
          </div>
        </div>

        <SidebarResizer
          width={sidebarWidth}
          bounds={bounds}
          onChange={setSidebarWidth}
          onCommit={persistWidth}
        />
      </aside>

      {/* Mobile drawer */}
      {drawerOpen && (
        <div className="fixed inset-0 z-50 lg:hidden">
          <button
            type="button"
            aria-label={t("shell.closeNavigation")}
            className="absolute inset-0 bg-black/60 backdrop-blur-[2px]"
            onClick={() => setDrawerOpen(false)}
          />
          <aside
            className={cn(
              // Rounded on its open edge, and no line along it: the scrim
              // behind is what says it sits over the page.
              "absolute inset-y-0 start-0 flex max-w-[92vw] flex-col overflow-hidden rounded-e-3xl bg-chrome shadow-[var(--shadow-lg)]",
              // Its foot holds the clock and the assistant launcher, and it
              // runs to the bottom of the screen: without this the home
              // indicator crosses them.
              "pb-[var(--safe-bottom)]",
              "transition-[width] duration-200 ease-out",
              assistantOpen ? "w-[22rem]" : "w-72",
            )}
          >
            {/* The drawer is `inset-y-0`, so with a cover viewport its own
                header sits under the status bar. It carries the notch the same
                way the page header does. */}
            <div className="flex h-[calc(3.5rem+var(--safe-top))] items-center justify-between px-4 pt-[var(--safe-top)]">
              <span className="text-sm font-medium tracking-tight">
                {t("shell.brand")}
              </span>
              <Button
                variant="ghost"
                size="icon-sm"
                onClick={() => setDrawerOpen(false)}
                aria-label={t("shell.closeNavigation")}
              >
                <X />
              </Button>
            </div>
            <div className="min-h-0 flex-1">
              <div className={cn("h-full", assistantOpen && "hidden")}>
                <SidebarNav
                  profile={profile}
                  projects={projects}
                  activeProjectId={activeProjectId}
                  unreadMessages={unreadMessages}
                  onNavigate={followLink}
                  onOpenAssistant={openAssistant}
                />
              </div>
              <div className={cn("h-full", !assistantOpen && "hidden")}>
                <AssistantPanel
                  assistant={assistant}
                  active={assistantOpen}
                  onClose={closeAssistant}
                />
              </div>
            </div>
          </aside>
        </div>
      )}

      <div
        className={cn(
          "lg:ps-[var(--sidebar-width)]",
          animating && "transition-[padding] duration-200 ease-out",
        )}
      >
        {/* `pt` and `h-auto`, not a taller box: with a cover viewport the status
            bar overlaps the top of the page, so the header carries the notch
            as padding and keeps its own 3.5rem of content below it. */}
        <header className="sticky top-0 z-20 flex h-[calc(3.5rem+var(--safe-top))] items-center justify-between gap-3 bg-chrome/80 px-4 pt-[var(--safe-top)] backdrop-blur-md supports-[backdrop-filter]:bg-chrome/70 sm:px-6">
          <div className="flex min-w-0 items-center gap-2">
            <CommandHint />
          </div>

          <div className="flex items-center gap-1">
            <LanguageSelector />
            <NotificationBell
              profile={profile}
              initialItems={notifications}
              initialUnread={unreadCount}
            />
            <ThemeToggle />
            <UserMenu profile={profile} />
          </div>
        </header>

        {/* Bottom padding clears the navigation bar on a phone, so the last
            card in a list is not sitting underneath it. */}
        <main
          id="content"
          tabIndex={-1}
          className={cn(
            "ambient min-h-[calc(100svh-3.5rem-var(--panel-gap))] pb-[calc(var(--nav-space)+var(--safe-bottom))] focus:outline-none lg:pb-0",
            // The panel. `clip` rather than `hidden` keeps its corners clean
            // without making it a scroll container, which would strand
            // anything sticky inside it.
            "lg:me-[var(--panel-gap)] lg:mb-[var(--panel-gap)] lg:overflow-clip lg:rounded-3xl lg:bg-background lg:shadow-[var(--shadow-xs)]",
          )}
        >
          {children}
        </main>
      </div>

      <BottomNav onOpenMore={() => setDrawerOpen(true)} />

      <CommandPalette
        projects={projects}
        canManage={profile.role === "admin" || profile.role === "manager"}
      />
    </div>
  );
}
