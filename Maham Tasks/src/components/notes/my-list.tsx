"use client";

import * as React from "react";
import { ListChecks, Pin, Plus, Search, Users } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { EmptyState } from "@/components/ui/empty-state";
import { Input } from "@/components/ui/input";
import { NoteEditor } from "@/components/notes/note-editor";
import {
  createNote,
  deleteNote,
  setNotePinned,
} from "@/lib/data/note-actions";
import { daysAgo } from "@/lib/dates";
import { cn } from "@/lib/utils";
import { useI18n } from "@/lib/i18n/client";
import type { Translator } from "@/lib/i18n";
import type { NoteWithItems, Profile } from "@/lib/supabase/database.types";

/**
 * My List — a private daily list, shaped like the Notes app on a phone.
 *
 * One screen at a time below `lg`: the list, then the note, with a back
 * button. Both panes side by side above it. The local copy is the source of
 * truth while the page is open — a personal list has no second editor to race
 * with, and re-syncing from the server mid-keystroke is what makes this kind
 * of page feel unreliable.
 */
export function MyList({
  initialNotes,
  profile,
  team,
}: {
  initialNotes: NoteWithItems[];
  /** Who is reading, so a list can say whether it is theirs. */
  profile: Profile;
  /** The directory the share picker offers. */
  team: Profile[];
}) {
  const { t, tm, tag, timeZone } = useI18n();
  const [notes, setNotes] = React.useState(initialNotes);
  const [activeId, setActiveId] = React.useState<string | null>(null);
  const [query, setQuery] = React.useState("");
  const [creating, setCreating] = React.useState(false);
  const [confirmDelete, setConfirmDelete] = React.useState<string | null>(null);

  const active = notes.find((note) => note.id === activeId) ?? null;

  // Two panes can show a note straight away; one pane must not. Opening the
  // page on a phone should land on the list, the way Notes does, rather than
  // dropping you inside whichever note happens to be first.
  //
  // Deciding this after mount rather than during render keeps the server and
  // the first client render identical.
  React.useEffect(() => {
    if (!window.matchMedia("(min-width: 1024px)").matches) return;
    setActiveId((current) => current ?? initialNotes[0]?.id ?? null);
  }, [initialNotes]);

  // Sharing changes who a list belongs to and who else is on it, and that is
  // the server's answer, not this component's. Text being typed is still the
  // local copy's business — the editor holds that until it saves.
  React.useEffect(() => {
    setNotes((current) =>
      initialNotes.map((fresh) => {
        const local = current.find((note) => note.id === fresh.id);
        return local ? { ...local, ...fresh, items: local.items } : fresh;
      }),
    );
  }, [initialNotes]);

  const visible = React.useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return notes;
    return notes.filter(
      (note) =>
        note.title.toLowerCase().includes(q) ||
        note.body.toLowerCase().includes(q) ||
        note.items.some((item) => item.content.toLowerCase().includes(q)),
    );
  }, [notes, query]);

  /** Patch one note in place, keeping pinned-first / newest-first order. */
  const patchNote = React.useCallback(
    (noteId: string, patch: Partial<NoteWithItems>) => {
      setNotes((current) =>
        current.map((note) =>
          note.id === noteId ? { ...note, ...patch } : note,
        ),
      );
    },
    [],
  );

  async function onCreate() {
    setCreating(true);
    const outcome = await createNote();
    setCreating(false);

    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }
    const note: NoteWithItems = {
      ...outcome.data,
      items: [],
      owner: profile,
      collaborators: [],
      mine: true,
    };
    setNotes((current) => [note, ...current]);
    setActiveId(note.id);
  }

  async function onDelete(noteId: string) {
    const previous = notes;
    setNotes((current) => current.filter((note) => note.id !== noteId));
    if (activeId === noteId) setActiveId(null);

    const outcome = await deleteNote(noteId);
    if (!outcome.ok) {
      setNotes(previous);
      toast.error(tm(outcome.error));
    }
  }

  async function onTogglePin(note: NoteWithItems) {
    const pinned = !note.pinned;
    patchNote(note.id, { pinned });

    const outcome = await setNotePinned(note.id, pinned);
    if (!outcome.ok) {
      patchNote(note.id, { pinned: !pinned });
      toast.error(tm(outcome.error));
    }
  }

  const pending = notes.find((n) => n.id === confirmDelete);

  return (
    <div
      className={cn(
        "flex flex-col lg:flex-row",
        // The pane is what the shell leaves, not the viewport less a header.
        // It used to subtract only the header, so on a phone it ran a whole
        // navigation bar past the bottom of the screen and the last lines of
        // a long note sat underneath it.
        "h-[calc(100svh-3.5rem-var(--nav-space)-var(--safe-top)-var(--safe-bottom))]",
        "lg:h-[calc(100svh-3.5rem-var(--panel-gap))]",
      )}
    >
      {/* ---- List ---------------------------------------------------- */}
      <section
        aria-label={t("notes.yours")}
        className={cn(
          "flex min-h-0 flex-col lg:w-80 lg:shrink-0 xl:w-96",
          // One screen at a time on a phone.
          active ? "hidden lg:flex" : "flex",
        )}
      >
        <header className="flex flex-col gap-3 px-4 py-3.5">
          <div className="flex items-center justify-between gap-3">
            <h1 className="text-lg font-semibold tracking-tight">{t("nav.myList")}</h1>
            <Button size="sm" onClick={onCreate} disabled={creating}>
              <Plus />
              {t("notes.new")}
            </Button>
          </div>

          <div className="relative">
            <Search className="pointer-events-none absolute start-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder={t("notes.search")}
              aria-label={t("notes.search")}
              className="ps-9"
            />
          </div>
        </header>

        <div className="scrollbar-thin min-h-0 flex-1 overflow-y-auto">
          {visible.length === 0 ? (
            <div className="p-3">
              <EmptyState
                compact
                icon={notes.length === 0 ? <ListChecks /> : <Search />}
                title={notes.length === 0 ? t("notes.none") : t("browser.noMatches")}
                description={
                  notes.length === 0
                    ? t("notes.startOne")
                    : t("palette.noMatch", { query: query.trim() })
                }
                action={
                  notes.length === 0 ? (
                    <Button size="sm" onClick={onCreate} disabled={creating}>
                      <Plus />
                      {t("notes.new")}
                    </Button>
                  ) : undefined
                }
              />
            </div>
          ) : (
            <ul className="flex flex-col gap-1 p-2">
              {visible.map((note) => (
                <li key={note.id}>
                  <button
                    type="button"
                    onClick={() => setActiveId(note.id)}
                    aria-current={note.id === activeId ? "true" : undefined}
                    className={cn(
                      "flex w-full flex-col gap-1 rounded-2xl px-3 py-3 text-start transition-colors",
                      note.id === activeId
                        ? "bg-primary/[0.09] shadow-[var(--shadow-xs)]"
                        : "hover:bg-foreground/[0.05]",
                    )}
                  >
                    <span className="flex items-center gap-1.5">
                      {note.pinned && (
                        <Pin className="size-3 shrink-0 text-muted-foreground" />
                      )}
                      <span className="min-w-0 flex-1 truncate text-[0.9375rem] font-medium">
                        {note.title.trim() || t("notes.new")}
                      </span>
                      {(!note.mine || note.collaborators.length > 0) && (
                        <Users
                          className="size-3 shrink-0 text-muted-foreground"
                          aria-label={
                            note.mine
                              ? t("notes.sharedWith", { n: note.collaborators.length })
                              : t("notes.sharedBy", { name: note.owner?.full_name ?? t("activity.someone") })
                          }
                        />
                      )}
                    </span>
                    <span className="flex items-center gap-2 text-xs text-muted-foreground">
                      <span className="shrink-0">{dayLabel(note.updated_at, t, tag, timeZone)}</span>
                      <span className="min-w-0 flex-1 truncate">
                        {note.mine
                          ? previewOf(note, t)
                          : `${note.owner?.full_name ?? t("notes.shared")} · ${previewOf(note, t)}`}
                      </span>
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      </section>

      {/* ---- Note ---------------------------------------------------- */}
      <section
        aria-label={t("notes.note")}
        className={cn(
          "min-h-0 flex-1 flex-col",
          active ? "flex" : "hidden lg:flex",
        )}
      >
        {active ? (
          <NoteEditor
            key={active.id}
            note={active}
            profile={profile}
            team={team}
            onBack={() => setActiveId(null)}
            onPatch={(patch: Partial<NoteWithItems>) =>
              patchNote(active.id, patch)
            }
            onTogglePin={() => onTogglePin(active)}
            onRequestDelete={() => setConfirmDelete(active.id)}
            onLeft={() => {
              setNotes((current) => current.filter((n) => n.id !== active.id));
              setActiveId(null);
            }}
          />
        ) : (
          <div className="flex h-full flex-col items-center justify-center gap-2 px-6 text-center">
            <ListChecks className="size-6 text-muted-foreground" />
            <p className="text-sm text-muted-foreground">
              {t("notes.pickOne")}
            </p>
          </div>
        )}
      </section>

      <ConfirmDialog
        open={confirmDelete !== null}
        onOpenChange={(open) => !open && setConfirmDelete(null)}
        title={t("notes.deleteTitle")}
        description={
          pending
            ? t("notes.deleteBody", { title: pending.title.trim() || t("notes.new") })
            : ""
        }
        confirmLabel={t("common.delete")}
        onConfirm={() => {
          if (confirmDelete) void onDelete(confirmDelete);
          setConfirmDelete(null);
        }}
      />
    </div>
  );
}

/** "Today", "Yesterday", or a short date — the Notes app's own shorthand. */
function dayLabel(
  iso: string,
  t: Translator["t"],
  tag: Translator["tag"],
  timeZone: Translator["timeZone"],
): string {
  const then = new Date(iso);
  const days = daysAgo(iso, timeZone);

  if (days === 0) {
    return then.toLocaleTimeString(tag, {
      timeZone,
      hour: "numeric",
      minute: "2-digit",
    });
  }
  if (days === 1) return t("gap.yesterday");
  return then.toLocaleDateString(tag, {
    timeZone,
    day: "numeric",
    month: "short",
  });
}

/** The line under the title: what is left to do, or the note's own text. */
function previewOf(note: NoteWithItems, t: Translator["t"]): string {
  const open = note.items.filter((item) => !item.done);
  if (note.items.length > 0) {
    const done = note.items.length - open.length;
    const next = open[0]?.content.trim();
    const progress = `${done}/${note.items.length}`;
    return next ? `${progress} · ${next}` : `${progress} · ${t("notes.allDone")}`;
  }
  return note.body.trim().split("\n")[0] || t("notes.noText");
}
