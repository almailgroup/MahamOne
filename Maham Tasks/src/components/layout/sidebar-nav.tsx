"use client";

import * as React from "react";
import Link, { useLinkStatus } from "next/link";
import { usePathname } from "next/navigation";
import {
  CalendarDays,
  ChartColumn,
  ClipboardList,
  Hash,
  LayoutDashboard,
  ListChecks,
  Plus,
  MessagesSquare,
  Send,
  Settings,
  Sparkles,
  Sunrise,
  Users,
} from "lucide-react";
import { Loader2 } from "lucide-react";

import { Button } from "@/components/ui/button";
import { ProjectSwitcher } from "@/components/layout/project-switcher";
import { SidebarClock } from "@/components/layout/sidebar-clock";
import { ProjectDialog } from "@/components/projects/project-dialog";
import { cn } from "@/lib/utils";
import type { Profile, Project } from "@/lib/supabase/database.types";
import { useI18n } from "@/lib/i18n/client";

/**
 * Sidebar contents, shared by the fixed desktop rail and the mobile drawer.
 */
export function SidebarNav({
  profile,
  projects,
  activeProjectId,
  unreadMessages = 0,
  onNavigate,
  onOpenAssistant,
}: {
  profile: Profile;
  projects: Project[];
  activeProjectId?: string;
  /** Private messages waiting; shown as a count beside the Messages item. */
  unreadMessages?: number;
  onNavigate?: () => void;
  /** Hands the rail over to the assistant; owned by AppShell, which resizes it. */
  onOpenAssistant: () => void;
}) {
  const pathname = usePathname();
  const { t } = useI18n();
  const [dialogOpen, setDialogOpen] = React.useState(false);

  // Admins and managers: they create projects and keep the workspace settings.
  const canManage = profile.role === "admin" || profile.role === "manager";

  // Derived from the route so the layout does not have to thread it down.
  const currentProjectId =
    activeProjectId ?? pathname.match(/^\/projects\/([^/]+)/)?.[1];
  const activeProject =
    projects.find((project) => project.id === currentProjectId) ?? null;

  return (
    <>
      <div className="flex h-full flex-col gap-4 p-3">
        <ProjectSwitcher
          projects={projects}
          activeProject={activeProject}
          canCreate={canManage}
          onCreate={() => setDialogOpen(true)}
        />

        <nav className="flex flex-col gap-0.5" aria-label={t("nav.tasks")}>
          <NavLink
            href="/dashboard"
            icon={<LayoutDashboard />}
            label={t("nav.dashboard")}
            active={pathname === "/dashboard"}
            onNavigate={onNavigate}
          />
          <NavLink
            href="/today"
            icon={<Sunrise />}
            label={t("nav.today")}
            active={pathname === "/today"}
            onNavigate={onNavigate}
          />
          <NavLink
            href="/calendar"
            icon={<CalendarDays />}
            label={t("nav.calendar")}
            active={pathname === "/calendar"}
            onNavigate={onNavigate}
          />
          <NavLink
            href="/my-list"
            icon={<ListChecks />}
            label={t("nav.myList")}
            active={pathname === "/my-list"}
            onNavigate={onNavigate}
          />
          <NavLink
            href="/general"
            icon={<ClipboardList />}
            label={t("nav.general")}
            active={pathname === "/general"}
            onNavigate={onNavigate}
          />
          <NavLink
            href="/team"
            icon={<Users />}
            label={t("nav.team")}
            active={pathname === "/team"}
            onNavigate={onNavigate}
          />
          <NavLink
            href="/chat"
            icon={<MessagesSquare />}
            label={t("nav.chat")}
            active={pathname === "/chat"}
            onNavigate={onNavigate}
          />
          <NavLink
            href="/messages"
            icon={<Send />}
            label={t("nav.messages")}
            active={pathname.startsWith("/messages")}
            badge={unreadMessages}
            onNavigate={onNavigate}
          />
          {canManage && (
            <NavLink
              href="/reports"
              icon={<ChartColumn />}
              label={t("nav.reports")}
              active={pathname === "/reports"}
              onNavigate={onNavigate}
            />
          )}
          {canManage && (
            <NavLink
              href="/settings"
              icon={<Settings />}
              label={t("nav.settings")}
              active={pathname === "/settings"}
              onNavigate={onNavigate}
            />
          )}
        </nav>

        <div className="flex min-h-0 flex-1 flex-col gap-1">
          <div className="flex items-center justify-between px-2 py-1">
            <span className="text-xs font-medium text-muted-foreground">
              {t("nav.projects")}
            </span>
            {canManage && (
              <Button
                variant="ghost"
                size="icon-sm"
                onClick={() => setDialogOpen(true)}
                aria-label={t("nav.newProject")}
              >
                <Plus />
              </Button>
            )}
          </div>

          <div className="scrollbar-thin flex min-h-0 flex-1 flex-col gap-0.5 overflow-y-auto">
            {projects.length === 0 ? (
              <p className="px-2 py-1.5 text-sm leading-relaxed text-muted-foreground">
                {canManage ? t("nav.createFirstProject") : t("nav.noProjects")}
              </p>
            ) : (
              projects.map((project) => (
                <NavLink
                  key={project.id}
                  href={`/projects/${project.id}`}
                  icon={<Hash />}
                  label={project.name}
                  active={project.id === currentProjectId}
                  onNavigate={onNavigate}
                />
              ))
            )}
          </div>
        </div>

        <div className="flex flex-col gap-1 pt-2">
          <button
            type="button"
            onClick={onOpenAssistant}
            data-assistant-launcher
            className={cn(
              "group/assistant lift flex items-center gap-2.5 rounded-2xl bg-card px-2.5 py-2.5 text-start shadow-[var(--shadow-xs)]",
              "hover:border-foreground/25 hover:bg-accent",
              "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-1 focus-visible:ring-offset-background",
            )}
          >
            <span
              aria-hidden
              className="flex size-6 shrink-0 items-center justify-center rounded-md bg-primary text-primary-foreground"
            >
              <Sparkles className="size-3.5" />
            </span>
            <span className="min-w-0 flex-1">
              <span className="block text-sm font-medium leading-tight">
                {t("nav.assistant")}
              </span>
              <span className="block truncate text-xs leading-tight text-muted-foreground">
                {t("nav.assistantHint")}
              </span>
            </span>
          </button>

          <SidebarClock />
        </div>
      </div>

      <ProjectDialog open={dialogOpen} onOpenChange={setDialogOpen} />
    </>
  );
}

function NavLink({
  href,
  icon,
  label,
  active,
  badge = 0,
  eager = true,
  onNavigate,
}: {
  href: string;
  icon: React.ReactNode;
  label: string;
  active?: boolean;
  /** A count worth interrupting for; nothing is drawn at zero. */
  badge?: number;
  /** Fetch the whole page ahead of the click, not just its skeleton. */
  eager?: boolean;
  onNavigate?: () => void;
}) {
  return (
    <Link
      href={href}
      onClick={onNavigate}
      // The whole page, not just its skeleton. Left to itself Next fetches a
      // dynamic route only as far as its loading.tsx, which is why the rail
      // used to answer a click instantly with a skeleton and then sit on it:
      // the data had not been asked for until the click.
      //
      // Every page view pays for this: eight nav links and one per project,
      // each a full render of the shell and that page. Dropping the projects
      // to Next's own prefetch cut a dashboard load from 79 queries to 55 —
      // and took clicking a project from 55ms to 1340, which is the lag this
      // eager prefetch was added to remove. The queries are the cheaper thing
      // to spend. `eager` stays for a caller that knows better.
      prefetch={eager ? true : undefined}
      aria-current={active ? "page" : undefined}
      className={cn(
        "chrome-touch relative flex items-center gap-2.5 rounded-xl px-2.5 py-2 text-sm transition-all duration-150",
        // This is the whole of the navigation inside the phone drawer, and it
        // was the shortest target left in the app at 36px.
        "pointer-coarse:min-h-11",
        "[&_svg]:size-4 [&_svg]:shrink-0",
        active
          // Inverted fill: the current page should be unmistakable at a glance,
          // which a hairline marker on the leading edge never was.
          ? "bg-primary font-semibold text-primary-foreground shadow-[var(--shadow-sm)] [&_svg]:text-primary-foreground"
          : "text-muted-foreground hover:bg-accent hover:text-foreground [&_svg]:text-muted-foreground",
      )}
    >
      <NavIcon>{icon}</NavIcon>
      <span className="truncate">{label}</span>
      {badge > 0 && (
        <span
          className={cn(
            "ms-auto flex min-w-5 shrink-0 items-center justify-center rounded-full px-1 text-[0.625rem] font-semibold tabular-nums",
            active
              ? "bg-primary-foreground text-primary"
              : "bg-primary text-primary-foreground",
          )}
        >
          {badge > 99 ? "99+" : badge}
        </span>
      )}
    </Link>
  );
}

/**
 * The item's own icon, or a spinner while its page is on its way.
 *
 * A prefetched page arrives in a few milliseconds and this never appears. It
 * is for the click that does wait — a cold route, a slow connection — where
 * the alternative is a rail that looks like it ignored you. It replaces the
 * icon rather than sitting beside it, so nothing moves.
 *
 * `useLinkStatus` only reports for the Link it is rendered inside, so the
 * spinner can never appear on an item that was not clicked.
 */
function NavIcon({ children }: { children: React.ReactNode }) {
  const { pending } = useLinkStatus();
  return pending ? <Loader2 className="animate-spin" /> : <>{children}</>;
}
