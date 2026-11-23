"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import {
  CalendarDays,
  ChartColumn,
  CheckSquare,
  ClipboardList,
  Compass,
  CornerDownLeft,
  Hash,
  Keyboard,
  LayoutDashboard,
  ListChecks,
  LogOut,
  MessageSquare,
  MessagesSquare,
  Moon,
  Paperclip,
  Plus,
  Search,
  Send,
  Settings,
  StickyNote,
  Sunrise,
  User,
  Users,
} from "lucide-react";
import { useTheme } from "next-themes";
import { modeOf } from "@/lib/themes";
import { toast } from "sonner";

import { createNote } from "@/lib/data/note-actions";
import { listPeople, startConversation, type PersonHit } from "@/lib/data/dm-actions";
import { searchEverything, type SearchKind, type SearchResults } from "@/lib/data/search-actions";
import { statusMeta } from "@/lib/constants";
import { isSearchable } from "@/lib/search";

import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogTitle,
} from "@/components/ui/dialog";
import { ShortcutsDialog } from "@/components/layout/shortcuts-dialog";
import { cn } from "@/lib/utils";
import type { Project } from "@/lib/supabase/database.types";
import { useI18n } from "@/lib/i18n/client";
import type { TranslationKey } from "@/lib/i18n";

/** How each kind of thing found in the workspace is shown. */
const FOUND: Record<SearchKind, { icon: Entry["icon"]; group: TranslationKey }> = {
  comment: { icon: MessageSquare, group: "palette.group.comments" },
  file: { icon: Paperclip, group: "palette.group.files" },
  chat: { icon: MessagesSquare, group: "palette.group.chat" },
  message: { icon: Send, group: "palette.group.messages" },
  note: { icon: StickyNote, group: "palette.group.notes" },
};

type Entry = {
  id: string;
  label: string;
  hint?: string;
  /** Where it goes, or `run` for something it does on the spot. */
  href?: string;
  run?: () => void | Promise<void>;
  icon: React.ComponentType<{ className?: string }>;
  group: string;
  /** Show the hint as a second line: where a found thing is, who said it. */
  detail?: boolean;
};

/**
 * Command palette, opened with Cmd/Ctrl+K.
 *
 * Once someone is on a dozen projects, the sidebar stops being a navigation
 * tool and becomes a list to scan. This makes every destination one search
 * away without taking hands off the keyboard.
 */
export function CommandPalette({
  projects,
  canManage = false,
}: {
  projects: Project[];
  /** Admins and managers: offered the pages only they have, like Settings. */
  canManage?: boolean;
}) {
  const router = useRouter();
  const { t, tm } = useI18n();
  const [open, setOpen] = React.useState(false);
  const [shortcutsOpen, setShortcutsOpen] = React.useState(false);
  const [query, setQuery] = React.useState("");
  const [active, setActive] = React.useState(0);
  const listRef = React.useRef<HTMLUListElement>(null);
  const inputRef = React.useRef<HTMLInputElement>(null);

  const { resolvedTheme, setTheme } = useTheme();

  /**
   * Everything matching what has been typed: tasks first, then comments,
   * files, the team room, private messages and notes.
   *
   * The palette knew every page in the app and none of its contents, so
   * finding a task meant remembering which project it was in, and finding
   * what was said about it meant remembering where it was said. Results come
   * from the server because no one page holds them, and they are debounced
   * so a fast typist sends one query rather than eight.
   */
  const [hits, setHits] = React.useState<SearchResults>({ tasks: [], more: [] });
  const [searching, setSearching] = React.useState(false);

  React.useEffect(() => {
    const needle = query.trim();
    if (!isSearchable(needle)) {
      setHits({ tasks: [], more: [] });
      setSearching(false);
      return;
    }

    setSearching(true);
    let current = true;
    const timer = setTimeout(async () => {
      const found = await searchEverything(needle).catch(() => ({ tasks: [], more: [] }));
      // The answer to an older keystroke must never overwrite a newer one.
      if (!current) return;
      setHits(found);
      setSearching(false);
    }, 200);

    return () => {
      current = false;
      clearTimeout(timer);
    };
  }, [query]);

  /**
   * Teammates, fetched the first time the palette opens rather than with the
   * page: the shell renders on every navigation and most of them never open
   * this. A handful of rows filter fine in the browser after that.
   */
  const [people, setPeople] = React.useState<PersonHit[]>([]);
  React.useEffect(() => {
    if (!open || people.length > 0) return;
    let current = true;
    listPeople()
      .then((found) => {
        if (current) setPeople(found);
      })
      // The list stays empty and the palette still finds pages and tasks.
      // Caught rather than left to reject: an unhandled rejection is noise
      // in the console of a page that is working, and the next open asks
      // again anyway.
      .catch((error) => console.error("[palette] people:", error));
    return () => {
      current = false;
    };
  }, [open, people.length]);

  /**
   * A person is a destination here, and the destination is the thread with
   * them: there is no page for a profile, and messaging is what you came to
   * the palette with their name for.
   */
  const messagePerson = React.useCallback(
    async (id: string) => {
      const outcome = await startConversation(id);
      if (!outcome.ok) {
        toast.error(tm(outcome.error));
        return;
      }
      router.push(`/messages/${outcome.data}`);
    },
    [router, tm],
  );

  const newNote = React.useCallback(async () => {
    const outcome = await createNote();
    if (!outcome.ok) {
      toast.error(outcome.error);
      return;
    }
    router.push("/my-list");
    router.refresh();
  }, [router]);

  const entries = React.useMemo<Entry[]>(
    () => [
      // Actions first: someone who opened this with a verb in mind should not
      // have to scroll past every page in the app to find it.
      { id: "new-task", label: t("palette.newTask"), href: "/general?new=1", icon: Plus, group: t("palette.group.actions"), hint: "n" },
      { id: "new-note", label: t("palette.newNote"), run: newNote, icon: StickyNote, group: t("palette.group.actions") },
      {
        id: "theme",
        // Whichever family the current theme is in — Midnight is dark too.
        label: modeOf(resolvedTheme) === "dark" ? t("shell.themeLight") : t("shell.themeDark"),
        run: () => setTheme(modeOf(resolvedTheme) === "dark" ? "light" : "dark"),
        icon: Moon,
        group: t("palette.group.actions"),
      },
      { id: "shortcuts", label: t("palette.shortcuts"), run: () => setShortcutsOpen(true), icon: Keyboard, group: t("palette.group.actions"), hint: "?" },
      { id: "guide", label: t("palette.guide"), href: "/dashboard?guide=1", icon: Compass, group: t("palette.group.actions") },
      { id: "signout", label: t("shell.signOut"), href: "/auth/signout", icon: LogOut, group: t("palette.group.actions") },
      { id: "today", label: t("nav.today"), href: "/today", icon: Sunrise, group: t("palette.group.goTo") },
      { id: "dashboard", label: t("nav.dashboard"), href: "/dashboard", icon: LayoutDashboard, group: t("palette.group.goTo") },
      { id: "calendar", label: t("nav.calendar"), href: "/calendar", icon: CalendarDays, group: t("palette.group.goTo") },
      { id: "general", label: t("nav.general"), href: "/general", icon: ClipboardList, group: t("palette.group.goTo") },
      { id: "my-list", label: t("nav.myList"), href: "/my-list", icon: ListChecks, group: t("palette.group.goTo") },
      { id: "tasks", label: t("palette.allTasks"), href: "/tasks?filter=all", icon: Search, group: t("palette.group.goTo") },
      { id: "team", label: t("nav.team"), href: "/team", icon: Users, group: t("palette.group.goTo") },
      { id: "chat", label: t("nav.chat"), href: "/chat", icon: MessagesSquare, group: t("palette.group.goTo") },
      { id: "messages", label: t("nav.messages"), href: "/messages", icon: Send, group: t("palette.group.goTo") },
      { id: "profile", label: t("shell.profile"), href: "/profile", icon: User, group: t("palette.group.goTo") },
      ...(canManage
        ? [
            { id: "reports", label: t("nav.reports"), href: "/reports", icon: ChartColumn, group: t("palette.group.goTo") },
            { id: "settings", label: t("nav.settings"), href: "/settings", icon: Settings, group: t("palette.group.goTo") },
          ]
        : []),
      { id: "overdue", label: t("palette.overdue"), href: "/tasks?filter=overdue", icon: Search, group: t("palette.group.filters") },
      { id: "due-today", label: t("palette.dueToday"), href: "/tasks?filter=due_today", icon: Search, group: t("palette.group.filters") },
      { id: "in-review", label: t("palette.inReview"), href: "/tasks?filter=in_review", icon: Search, group: t("palette.group.filters") },
      ...people.map((person) => ({
        id: `person-${person.id}`,
        label: person.full_name ?? person.email,
        hint: person.job_title ?? person.email,
        run: () => messagePerson(person.id),
        icon: MessageSquare,
        group: t("palette.group.people"),
      })),
      ...projects.map((project) => ({
        id: `project-${project.id}`,
        label: project.name,
        hint: project.description ?? undefined,
        href: `/projects/${project.id}`,
        icon: Hash,
        group: t("palette.group.projects"),
      })),
    ],
    [projects, people, messagePerson, resolvedTheme, setTheme, newNote, t, canManage],
  );

  const results = React.useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (!needle) return entries;

    const matches = entries.filter((entry) =>
      `${entry.label} ${entry.hint ?? ""}`.toLowerCase().includes(needle),
    );

    // Tasks lead: typing words rather than a page name means looking for
    // something in the workspace, not for a link to it.
    const taskEntries: Entry[] = hits.tasks.map((hit) => ({
      id: `task-${hit.id}`,
      label: hit.title,
      hint: [hit.projectName ?? t("palette.general"), t(statusMeta(hit.status).label)].join(" · "),
      href: `/tasks?filter=all&task=${hit.id}`,
      icon: CheckSquare,
      group: t("palette.group.tasks"),
      detail: true,
    }));

    // Eight is a list; more than that is a search, and the browser page can
    // show every match with the filters beside it.
    if (hits.tasks.length >= 8) {
      taskEntries.push({
        id: "search-all",
        label: t("palette.allMatching", { query: query.trim() }),
        href: `/tasks?filter=all&q=${encodeURIComponent(query.trim())}`,
        icon: Search,
        group: t("palette.group.tasks"),
      });
    }

    // Then what was said and attached, each kind under its own heading.
    const found: Entry[] = hits.more.map((hit) => ({
      id: `${hit.kind}-${hit.id}`,
      label: hit.label,
      hint: hit.hint,
      href: hit.href,
      icon: FOUND[hit.kind].icon,
      group: t(FOUND[hit.kind].group),
      detail: true,
    }));

    return [...taskEntries, ...found, ...matches];
  }, [entries, hits, query, t]);

  // Cmd/Ctrl+K toggles from anywhere, except while typing somewhere else.
  React.useEffect(() => {
    function onKey(event: KeyboardEvent) {
      if (event.key.toLowerCase() === "k" && (event.metaKey || event.ctrlKey)) {
        event.preventDefault();
        setOpen((current) => !current);
        return;
      }

      // Bare-letter shortcuts must never fire while someone is writing, or
      // typing "note" into a comment would open a dialog mid-sentence.
      const el = document.activeElement as HTMLElement | null;
      const typing =
        el instanceof HTMLInputElement ||
        el instanceof HTMLTextAreaElement ||
        el?.isContentEditable === true;
      if (typing || event.metaKey || event.ctrlKey || event.altKey) return;

      if (event.key === "n") {
        event.preventDefault();
        router.push("/general?new=1");
      } else if (event.key === "?") {
        event.preventDefault();
        setShortcutsOpen(true);
      } else if (event.key === "/") {
        // Focus whatever this page calls its search box.
        const search = document.querySelector<HTMLInputElement>(
          'input[type="search"], input[aria-label^="Search"]',
        );
        if (search) {
          event.preventDefault();
          search.focus();
          search.select();
        }
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [router]);

  React.useEffect(() => {
    if (open) {
      setQuery("");
      setActive(0);
      return;
    }
    // Radix keeps the dialog mounted through its exit animation, so without
    // this the palette's own input holds focus for the best part of a second
    // after it looks closed — long enough to swallow the next keystroke, and
    // the bare-letter shortcuts refuse to fire while a field has focus.
    inputRef.current?.blur();
  }, [open]);

  React.useEffect(() => setActive(0), [query]);

  // Keep the highlighted row in view when arrowing past the fold.
  React.useEffect(() => {
    listRef.current
      ?.querySelectorAll("[data-entry]")
      ?.[active]?.scrollIntoView({ block: "nearest" });
  }, [active]);

  function go(entry: Entry) {
    setOpen(false);
    if (entry.run) void entry.run();
    else if (entry.href) router.push(entry.href);
  }

  function onKeyDown(event: React.KeyboardEvent) {
    if (results.length === 0) return;

    if (event.key === "ArrowDown") {
      event.preventDefault();
      setActive((index) => (index + 1) % results.length);
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      setActive((index) => (index - 1 + results.length) % results.length);
    } else if (event.key === "Enter") {
      event.preventDefault();
      go(results[active]);
    }
  }

  let lastGroup = "";

  return (
    <>
    <ShortcutsDialog open={shortcutsOpen} onOpenChange={setShortcutsOpen} />
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent
        className="max-w-lg gap-0 overflow-hidden p-0"
        showCloseButton={false}
      >
        <DialogTitle className="sr-only">{t("palette.title")}</DialogTitle>
        <DialogDescription className="sr-only">{t("palette.description")}</DialogDescription>

        <div className="flex items-center gap-2.5 px-4 pt-1">
          <Search className="size-4 shrink-0 text-muted-foreground" />
          <input
            ref={inputRef}
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            onKeyDown={onKeyDown}
            placeholder={t("palette.placeholder")}
            // The caret shows where typing goes; the dialog is the focus. The
            // global ring drew a square frame here, against a round dialog.
            className="h-12 w-full bg-transparent text-[0.9375rem] outline-none focus-visible:ring-0 focus-visible:ring-offset-0 placeholder:text-muted-foreground"
            autoFocus
            aria-label={t("shell.search")}
          />
        </div>

        {results.length === 0 ? (
          <p className="px-3 py-8 text-center text-sm text-muted-foreground">
            {searching ? t("palette.searching") : t("palette.noMatch", { query })}
          </p>
        ) : (
          <ul
            ref={listRef}
            className="scrollbar-thin max-h-80 overflow-y-auto p-1.5"
            role="listbox"
          >
            {results.map((entry, index) => {
              const Icon = entry.icon;
              const showGroup = entry.group !== lastGroup;
              lastGroup = entry.group;

              return (
                <React.Fragment key={entry.id}>
                  {showGroup && (
                    <li className="px-2 pb-1 pt-2 text-xs font-medium text-muted-foreground">
                      {entry.group}
                    </li>
                  )}
                  <li data-entry>
                    <button
                      type="button"
                      role="option"
                      aria-selected={index === active}
                      onMouseEnter={() => setActive(index)}
                      onClick={() => go(entry)}
                      className={cn(
                        "flex w-full items-center gap-2.5 rounded-md px-2 py-2 text-start text-sm transition-colors",
                        index === active
                          ? "bg-accent text-accent-foreground"
                          : "text-foreground",
                      )}
                    >
                      <Icon className="size-4 shrink-0 text-muted-foreground" />
                      <span className="min-w-0 flex-1">
                        <span className="block truncate">{entry.label}</span>
                        {entry.detail && entry.hint && (
                          <span className="block truncate text-xs text-muted-foreground">
                            {entry.hint}
                          </span>
                        )}
                      </span>
                      {index === active && (
                        <CornerDownLeft className="size-3 shrink-0 text-muted-foreground rtl:-scale-x-100" />
                      )}
                    </button>
                  </li>
                </React.Fragment>
              );
            })}
          </ul>
        )}

        <div className="flex items-center justify-between px-5 pt-2 pb-3.5 text-xs text-muted-foreground">
          <span>
            <Kbd>↑</Kbd> <Kbd>↓</Kbd> {t("palette.move")} · <Kbd>↵</Kbd> {t("palette.open")}
          </span>
          <span>
            <Kbd>esc</Kbd> {t("palette.close")}
          </span>
        </div>
      </DialogContent>
    </Dialog>
    </>
  );
}

function Kbd({ children }: { children: React.ReactNode }) {
  return (
    <kbd className="rounded-md bg-muted px-1.5 font-mono text-[10px] leading-4">
      {children}
    </kbd>
  );
}

/** The header affordance that tells people the palette exists. */
export function CommandHint() {
  const { t } = useI18n();
  return (
    <button
      type="button"
      onClick={() =>
        window.dispatchEvent(
          new KeyboardEvent("keydown", { key: "k", metaKey: true }),
        )
      }
      aria-label={t("shell.search")}
      className="flex items-center gap-2 rounded-2xl bg-foreground/[0.05] px-2.5 py-1.5 text-xs text-muted-foreground transition-colors hover:bg-foreground/[0.09] hover:text-foreground pointer-coarse:min-h-11 pointer-coarse:min-w-11 pointer-coarse:justify-center pointer-coarse:px-3"
    >
      <Search className="size-4 sm:size-3.5" />
      <span className="hidden sm:inline">{t("shell.search")}</span>
      <kbd className="hidden rounded-md bg-muted px-1 font-mono text-[10px] leading-4 sm:inline">
        ⌘K
      </kbd>
    </button>
  );
}
