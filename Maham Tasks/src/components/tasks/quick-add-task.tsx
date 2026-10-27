"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { Loader2, Plus } from "lucide-react";
import { toast } from "sonner";

import { createTask } from "@/lib/data/task-actions";
import { cn } from "@/lib/utils";
import { useI18n } from "@/lib/i18n/client";
import type { TaskStatus } from "@/lib/supabase/database.types";

/**
 * Add a task by typing its title.
 *
 * Capturing "call the supplier back" meant opening a six-field dialog, which
 * is the right tool for planning a piece of work and the wrong one for
 * remembering something before it slips. Everything else about the task —
 * priority, dates, assignees — stays where it was, one click away in the
 * dialog, and defaults sensibly until then.
 *
 * The field stays open and focused after a save so several things can be
 * emptied out of someone's head in a row.
 */
export function QuickAddTask({
  projectId,
  status = "todo",
  label,
  className,
}: {
  projectId: string | null;
  /** Which column the task lands in. */
  status?: TaskStatus;
  label?: string;
  className?: string;
}) {
  const router = useRouter();
  const { t, tm } = useI18n();
  const text = label ?? t("quick.addTask");
  const [open, setOpen] = React.useState(false);
  const [title, setTitle] = React.useState("");
  const [saving, setSaving] = React.useState(false);
  const inputRef = React.useRef<HTMLInputElement>(null);

  async function save() {
    const trimmed = title.trim();
    if (!trimmed || saving) return;

    setSaving(true);
    const form = new FormData();
    form.set("title", trimmed);
    form.set("status", status);

    // Same action the dialog uses, so validation and permissions cannot drift
    // between the two ways of creating a task.
    const outcome = await createTask(projectId, null, form);
    setSaving(false);

    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }

    setTitle("");
    router.refresh();
    inputRef.current?.focus();
  }

  if (!open) {
    return (
      <button
        type="button"
        onClick={() => {
          setOpen(true);
          // The input does not exist yet; focus it once it does.
          requestAnimationFrame(() => inputRef.current?.focus());
        }}
        className={cn(
          "flex w-full items-center gap-2 rounded-[1.25rem] bg-foreground/[0.05] px-4 py-2.5 text-sm text-muted-foreground transition-colors",
          "hover:border-foreground/30 hover:bg-accent hover:text-foreground",
          "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background",
          "pointer-coarse:min-h-11",
          className,
        )}
      >
        <Plus className="size-4" aria-hidden />
        {text}
      </button>
    );
  }

  return (
    <div
      className={cn(
        "flex items-center gap-2 rounded-[1.25rem] bg-card px-4 py-1.5 shadow-[var(--shadow-xs)]",
        // The ring belongs to the box, not to the bare input inside it —
        // otherwise focus draws two outlines, one inside the other. The same
        // soft ring as every other field, not a hard one with a gap.
        "focus-within:ring-2 focus-within:ring-ring/60",
        className,
      )}
    >
      <input
        ref={inputRef}
        value={title}
        onChange={(event) => setTitle(event.target.value)}
        onKeyDown={(event) => {
          if (event.key === "Enter") {
            event.preventDefault();
            void save();
          } else if (event.key === "Escape") {
            event.preventDefault();
            setTitle("");
            setOpen(false);
          }
        }}
        onBlur={() => {
          // Leaving an empty field means "never mind"; leaving a filled one
          // mid-thought should not throw the text away.
          if (!title.trim() && !saving) setOpen(false);
        }}
        maxLength={200}
        placeholder={t("quick.placeholder")}
        aria-label={text}
        className="h-8 w-full min-w-0 bg-transparent text-sm outline-none focus-visible:ring-0 focus-visible:ring-offset-0 placeholder:text-muted-foreground"
      />
      {saving ? (
        <Loader2 className="size-4 shrink-0 animate-spin text-muted-foreground" aria-hidden />
      ) : (
        <kbd className="hidden shrink-0 rounded-md bg-muted px-1 font-mono text-[10px] leading-4 text-muted-foreground sm:inline">
          ↵
        </kbd>
      )}
    </div>
  );
}
