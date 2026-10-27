"use client";

import * as React from "react";
import {
  Check,
  ChevronLeft,
  MoreHorizontal,
  Pin,
  PinOff,
  Plus,
  Trash2,
} from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  addNoteItem,
  clearDoneItems,
  deleteNoteItem,
  saveNote,
  updateNoteItem,
} from "@/lib/data/note-actions";
import { ShareNoteDialog } from "@/components/notes/share-note-dialog";
import { useNoteStream } from "@/lib/realtime/use-note-stream";
import { cn } from "@/lib/utils";
import { useI18n } from "@/lib/i18n/client";
import type {
  NoteWithItems,
  PersonalNoteItem,
  Profile,
} from "@/lib/supabase/database.types";

/** How long to wait after the last keystroke before writing. */
const SAVE_DELAY = 700;

/**
 * One note: a title, a checklist, and room for anything else.
 *
 * Text saves itself on a debounce rather than behind a Save button — the
 * thing being written is a list of errands, and nobody should lose one to a
 * forgotten click. Ticking a box writes immediately and optimistically,
 * because that tap has to feel instant on a phone.
 */
export function NoteEditor({
  note,
  profile,
  team,
  onBack,
  onPatch,
  onTogglePin,
  onRequestDelete,
  onLeft,
}: {
  note: NoteWithItems;
  profile: Profile;
  team: Profile[];
  onBack: () => void;
  onPatch: (patch: Partial<NoteWithItems>) => void;
  onTogglePin: () => void;
  onRequestDelete: () => void;
  /** After leaving a list shared with you, it is no longer on your page. */
  onLeft: () => void;
}) {
  const { t, tm } = useI18n();
  const [title, setTitle] = React.useState(note.title);
  const [body, setBody] = React.useState(note.body);
  const [status, setStatus] = React.useState<"idle" | "saving" | "saved">("idle");
  const [adding, setAdding] = React.useState(false);

  // Which item to put the cursor in once it has been rendered.
  const focusNext = React.useRef<string | null>(null);
  const itemRefs = React.useRef(new Map<string, HTMLInputElement>());

  const items = note.items;
  const remaining = items.filter((item) => !item.done).length;

  const itemsRef = React.useRef(items);
  itemsRef.current = items;

  React.useEffect(() => {
    const id = focusNext.current;
    if (!id) return;
    const input = itemRefs.current.get(id);
    if (input) {
      input.focus();
      focusNext.current = null;
    }
  }, [items]);

  // --- Title and body: debounced auto-save ---------------------------------
  const dirty = title !== note.title || body !== note.body;
  const dirtyRef = React.useRef(dirty);
  dirtyRef.current = dirty;

  React.useEffect(() => {
    if (!dirty) return;
    setStatus("saving");

    const timer = setTimeout(async () => {
      const outcome = await saveNote(note.id, { title, body });
      if (!outcome.ok) {
        setStatus("idle");
        toast.error(tm(outcome.error));
        return;
      }
      onPatch({ title, body, updated_at: outcome.data.updatedAt });
      setStatus("saved");
    }, SAVE_DELAY);

    return () => clearTimeout(timer);
    // onPatch is stable enough for this; re-running on it would restart the
    // timer on every parent render and never let a save land.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [title, body, dirty, note.id]);

  // Nothing is lost if the tab closes mid-debounce — but say so honestly:
  // the last few hundred milliseconds of typing can be.
  React.useEffect(() => {
    if (status !== "saved") return;
    const timer = setTimeout(() => setStatus("idle"), 1600);
    return () => clearTimeout(timer);
  }, [status]);

  // --- Checklist -----------------------------------------------------------
  function patchItems(next: PersonalNoteItem[]) {
    onPatch({ items: next });
  }

  // --- What the other people on this list are doing -------------------------
  const shared = note.mine ? note.collaborators.length > 0 : true;

  const applyItem = React.useCallback(
    ({
      type,
      item,
    }: {
      type: "INSERT" | "UPDATE" | "DELETE";
      item: PersonalNoteItem;
    }) => {
      onPatch({
        items: (() => {
          const current = itemsRef.current;

          if (type === "DELETE") {
            return current.filter((row) => row.id !== item.id);
          }

          // The line being typed in right now belongs to whoever is typing.
          // Their own save will land in a moment; overwriting it mid-word
          // would eat the characters between the two.
          if (document.activeElement === itemRefs.current.get(item.id)) {
            return current;
          }

          const known = current.some((row) => row.id === item.id);
          const next = known
            ? current.map((row) => (row.id === item.id ? item : row))
            : [...current, item];

          return next.sort((a, b) => a.position - b.position);
        })(),
      });
    },
    [onPatch],
  );

  const applyNote = React.useCallback(
    (remote: { title: string; body: string; pinned: boolean; updated_at: string }) => {
      // Only when there is nothing of ours to lose. Someone mid-sentence keeps
      // what they are writing; their save will win, and the other side will
      // get it through this same channel.
      if (dirtyRef.current) return;
      setTitle(remote.title);
      setBody(remote.body);
      onPatch({
        title: remote.title,
        body: remote.body,
        pinned: remote.pinned,
        updated_at: remote.updated_at,
      });
    },
    [onPatch],
  );

  useNoteStream({
    noteId: note.id,
    enabled: shared,
    onItem: applyItem,
    onNote: applyNote,
  });

  async function toggleItem(item: PersonalNoteItem) {
    const done = !item.done;
    patchItems(
      items.map((row) => (row.id === item.id ? { ...row, done } : row)),
    );

    const outcome = await updateNoteItem(item.id, { done });
    if (!outcome.ok) {
      patchItems(items);
      toast.error(tm(outcome.error));
    }
  }

  function setItemContent(itemId: string, content: string) {
    patchItems(
      items.map((row) => (row.id === itemId ? { ...row, content } : row)),
    );
  }

  async function commitItem(item: PersonalNoteItem, content: string) {
    if (content === item.content) return;
    const outcome = await updateNoteItem(item.id, { content });
    if (!outcome.ok) toast.error(tm(outcome.error));
  }

  async function addItem() {
    if (adding) return;
    setAdding(true);
    const outcome = await addNoteItem(note.id, "");
    setAdding(false);

    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }
    focusNext.current = outcome.data.id;
    patchItems([...items, outcome.data]);
  }

  async function removeItem(item: PersonalNoteItem) {
    const previous = items;
    const index = items.findIndex((row) => row.id === item.id);
    patchItems(items.filter((row) => row.id !== item.id));

    // Carry the cursor to the line above, the way a text editor would.
    const above = previous[index - 1];
    if (above) itemRefs.current.get(above.id)?.focus();

    const outcome = await deleteNoteItem(item.id);
    if (!outcome.ok) {
      patchItems(previous);
      toast.error(tm(outcome.error));
    }
  }

  async function onClearDone() {
    const previous = items;
    patchItems(items.filter((item) => !item.done));

    const outcome = await clearDoneItems(note.id);
    if (!outcome.ok) {
      patchItems(previous);
      toast.error(tm(outcome.error));
    }
  }

  const doneCount = items.length - remaining;

  return (
    <div className="flex h-full min-h-0 flex-col">
      <header className="flex items-center gap-1 px-2 py-2 sm:px-3">
        <Button
          variant="ghost"
          size="sm"
          onClick={onBack}
          className="lg:hidden"
          aria-label={t("notes.back")}
        >
          <ChevronLeft className="rtl:-scale-x-100" />
          {t("notes.notes")}
        </Button>

        <span className="min-w-0 flex-1 truncate px-2 text-xs text-muted-foreground">
          {status === "saving"
            ? t("notes.saving")
            : status === "saved"
              ? t("notes.saved")
              : items.length > 0
                ? t("common.doneOf", { done: doneCount, total: items.length })
                : ""}
        </span>

        <ShareNoteDialog
          note={note}
          team={team}
          profile={profile}
          onLeft={onLeft}
        />

        <Button
          variant="ghost"
          size="icon-sm"
          onClick={onTogglePin}
          aria-label={note.pinned ? t("notes.unpin") : t("notes.pin")}
          title={note.pinned ? t("notes.unpinShort") : t("notes.pinShort")}
        >
          {note.pinned ? <PinOff /> : <Pin />}
        </Button>

        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="icon-sm" aria-label={t("notes.actions")}>
              <MoreHorizontal />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem
              onSelect={onClearDone}
              disabled={doneCount === 0}
            >
              <Check />
              {t("notes.clearTicked")}
            </DropdownMenuItem>
            <DropdownMenuSeparator />
            {/* Deleting somebody else's list is not collaboration — the
                database refuses it too. Leaving is in the share dialog. */}
            <DropdownMenuItem onSelect={onRequestDelete} disabled={!note.mine}>
              <Trash2 />
              {note.mine ? t("notes.delete") : t("notes.onlyOwnerDeletes")}
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </header>

      <div className="scrollbar-thin min-h-0 flex-1 overflow-y-auto px-4 py-4 sm:px-6 sm:py-5">
        <div className="mx-auto flex min-h-full w-full max-w-2xl flex-col gap-4">
          <input
            value={title}
            onChange={(event) => setTitle(event.target.value)}
            placeholder={t("notes.titlePlaceholder")}
            maxLength={200}
            aria-label={t("notes.titleLabel")}
            /* A raised card rather than bare text, because without a shape
               there was nothing on screen to say this was a place you could
               type: the title and the body read as printed text, and the empty
               half of the pane read as nothing at all. Focus rings it softly,
               like every other field. */
            className={cn(
              "w-full rounded-[1.25rem] bg-card px-4 py-2.5 text-xl font-semibold tracking-tight shadow-[var(--shadow-xs)]",
              "transition-shadow duration-200",
              "placeholder:font-normal placeholder:text-muted-foreground",
              "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/60 focus-visible:ring-offset-0",
            )}
          />

          <ul className="flex flex-col">
            {items.map((item) => (
              <li key={item.id} className="group/line flex items-start gap-3 py-1.5">
                <button
                  type="button"
                  onClick={() => toggleItem(item)}
                  aria-pressed={item.done}
                  aria-label={
                    item.done
                      ? t("notes.markNotDone", { line: item.content || t("notes.thisLine") })
                      : t("notes.markDone", { line: item.content || t("notes.thisLine") })
                  }
                  className={cn(
                    // A generous hit box around a small circle: the tick is
                    // the most-tapped thing on this page.
                    "press mt-0.5 flex size-6 shrink-0 items-center justify-center rounded-full border-2 transition-all duration-150",
                    "pointer-coarse:size-7",
                    item.done
                      ? "bg-foreground text-background"
                      : "border-input",
                  )}
                >
                  {item.done && <Check className="size-3.5 animate-pop" />}
                </button>

                <input
                  ref={(node) => {
                    if (node) itemRefs.current.set(item.id, node);
                    else itemRefs.current.delete(item.id);
                  }}
                  value={item.content}
                  onChange={(event) =>
                    setItemContent(item.id, event.target.value)
                  }
                  onBlur={(event) => commitItem(item, event.target.value)}
                  onKeyDown={(event) => {
                    if (event.key === "Enter") {
                      event.preventDefault();
                      void commitItem(item, item.content);
                      void addItem();
                    }
                    // Backspace on an empty line removes it, as in a list editor.
                    if (
                      event.key === "Backspace" &&
                      item.content === "" &&
                      items.length > 1
                    ) {
                      event.preventDefault();
                      void removeItem(item);
                    }
                  }}
                  placeholder={t("notes.linePlaceholder")}
                  maxLength={1000}
                  className={cn(
                    "min-h-7 w-full bg-transparent py-0.5 text-[0.9375rem] leading-relaxed outline-none",
                    // A line of a list: the caret is the focus. The global
                    // ring drew a square frame round it.
                    "focus-visible:ring-0 focus-visible:ring-offset-0",
                    "placeholder:text-muted-foreground",
                    item.done && "text-muted-foreground line-through",
                  )}
                />

                <button
                  type="button"
                  onClick={() => removeItem(item)}
                  aria-label={t("notes.removeLine", { line: item.content || t("notes.thisLine") })}
                  className={cn(
                    "mt-0.5 flex size-6 shrink-0 items-center justify-center rounded-md text-muted-foreground transition-colors",
                    "hover:bg-accent hover:text-foreground",
                    // Quiet until you reach for it with a mouse; always there
                    // on touch, where there is no hover to reveal it.
                    "opacity-0 focus-visible:opacity-100 group-hover/line:opacity-100",
                    "pointer-coarse:size-8 pointer-coarse:opacity-100",
                  )}
                >
                  <Trash2 className="size-3.5" />
                </button>
              </li>
            ))}
          </ul>

          <button
            type="button"
            onClick={addItem}
            disabled={adding}
            className={cn(
              "-mt-1 flex items-center gap-3 rounded-md py-1.5 text-start text-[0.9375rem] text-muted-foreground transition-colors",
              "hover:text-foreground disabled:opacity-50",
            )}
          >
            <span className="flex size-6 shrink-0 items-center justify-center rounded-full bg-foreground/[0.05] pointer-coarse:size-7">
              <Plus className="size-3.5" />
            </span>
            {t("notes.addTodo")}
          </button>

          <textarea
            value={body}
            onChange={(event) => setBody(event.target.value)}
            placeholder={t("notes.bodyPlaceholder")}
            maxLength={20000}
            aria-label={t("notes.bodyLabel")}
            rows={6}
            /* `flex-1` so the field is the rest of the pane rather than a
               short box with dead space under it — the part you write in
               should be the part that is enclosed. */
            className={cn(
              "min-h-40 w-full flex-1 resize-none rounded-[1.25rem] bg-card px-4 py-3 text-[0.9375rem] leading-relaxed shadow-[var(--shadow-xs)]",
              "transition-shadow duration-200",
              "placeholder:text-muted-foreground",
              "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/60 focus-visible:ring-offset-0",
            )}
          />
        </div>
      </div>
    </div>
  );
}
