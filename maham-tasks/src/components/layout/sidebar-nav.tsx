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
import { TASKS_TONE } from "@/components/layout/maham-one-logo";
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
      {/* Maham One's sidebar: a card to switch what you are in (there, the
          company; here, the project), the app open, then its pages as rows
          on the tinted backdrop, the current one a white pill. */}
      <div className="flex h-full flex-col gap-2 px-3 pt-1 pb-3">
        <div className="space-y-1.5">
          <ProjectSwitcher
            projects={projects}
            activeProject={activeProject}
            canCreate={canManage}
            onCreate={() => setDialogOpen(true)}
          />
          <Link
            href="/dashboard"
            onClick={onNavigate}
            className="flex items-center gap-2.5 rounded-xl px-2 py-1.5 transition-colors hover:bg-surface/70"
          >
            <span
              aria-hidden
              className={cn(
                "flex size-7 shrink-0 items-center justify-center rounded-lg [&_svg]:size-4",
                TASKS_TONE,
              )}
            >
              <ListChecks />
            </span>
            <span className="truncate text-sm font-semibold text-slate-800">
              {t("shell.brand")}
            </span>
          </Link>
        </div>

        {/* The pages and the projects scroll together, as Maham One's menu
            does, so a short screen still reaches every project. */}
        <div className="scrollbar-thin -mx-3 flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto overscroll-contain px-3 py-0.5">
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

          <div className="flex flex-col gap-1">
            <div className="flex items-center justify-between ps-3 pe-1 pt-2">
              <span className="text-xs font-semibold text-slate-500">
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

            <div className="flex flex-col gap-0.5">
              {projects.length === 0 ? (
                <p className="px-3 py-1.5 text-sm leading-relaxed text-slate-500">
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
        </div>

        <div className="flex flex-col gap-1 pt-2">
          <button
            type="button"
            onClick={onOpenAssistant}
            data-assistant-launcher
            className={cn(
              "group/assistant flex items-center gap-2.5 rounded-2xl bg-surface p-2 text-start shadow-xs ring-1 ring-slate-900/5 transition-shadow hover:shadow-sm",
            )}
          >
            <span
              aria-hidden
              className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-primary-50 text-primary-600"
            >
              <Sparkles className="size-4" />
            </span>
            <span className="min-w-0 flex-1">
              <span className="block text-sm font-semibold leading-tight text-slate-900">
                {t("nav.assistant")}
              </span>
              <span className="block truncate text-xs leading-tight text-slate-500">
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
        // Maham One's sidebar rows (its features/shell/sidebar.tsx): 44px on
        // touch, the current page a white pill in the main colour.
        "chrome-touch relative flex h-[2.125rem] w-full items-center gap-3 rounded-xl px-3 text-sm font-medium transition-colors",
        "pointer-coarse:h-11",
        "[&_svg]:size-[1.125rem] [&_svg]:shrink-0",
        active
          ? "bg-surface text-primary-700 shadow-xs ring-1 ring-slate-900/5 [&_svg]:text-primary-600"
          : "text-slate-700 hover:bg-surface/70 hover:text-slate-900 [&_svg]:text-slate-500 hover:[&_svg]:text-slate-600",
      )}
    >
      <NavIcon>{icon}</NavIcon>
      <span className="truncate">{label}</span>
      {badge > 0 && (
        <span
          className={cn(
            "ms-auto flex min-w-5 shrink-0 items-center justify-center rounded-full px-1 text-[0.625rem] font-semibold tabular-nums",
            active
              ? "bg-primary-100 text-primary-700"
              : "bg-primary-solid text-on-primary",
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
