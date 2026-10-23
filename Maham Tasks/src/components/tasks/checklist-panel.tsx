"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { ListChecks, Loader2, Plus, X } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import {
  addChecklistItem,
  listChecklistItems,
  removeChecklistItem,
} from "@/lib/data/checklist-actions";
import { useOutbox } from "@/components/offline/outbox-provider";
import { useI18n } from "@/lib/i18n/client";
import { cn } from "@/lib/utils";
import type { ChecklistItem } from "@/lib/supabase/database.types";

/**
 * The small steps inside a task.
 *
 * "Meet with Kuwait banks" has five documents to bring; they used to go into
 * the description as prose, where nothing can be ticked off and nobody can
 * see how far along it is.
 *
 * Ticking is optimistic — a box that waits half a second to darken feels
 * broken, and the failure it is guarding against is somebody without
 * permission, which the dialog would not have opened for. A refusal puts the
 * box back and says why.
 */
export function ChecklistPanel({
  taskId,
  canEdit,
}: {
  taskId: string;
  /** Whoever cannot plan the steps can still tick them off. */
  canEdit: boolean;
}) {
  const router = useRouter();
  const { t, tm } = useI18n();
  const { send } = useOutbox();
  const [items, setItems] = React.useState<ChecklistItem[]>([]);
  const [adding, setAdding] = React.useState("");
  const [busy, setBusy] = React.useState(false);

  // Fetched when the dialog opens rather than carried on every task in every
  // list: a board needs the counts, which ride along already, not the text.
  React.useEffect(() => {
    let current = true;
    listChecklistItems(taskId)
      .then((found) => {
        if (current) setItems(found);
      })
      .catch((error) => {
        // Say so. Left uncaught this rejected quietly and the panel showed
        // an empty list, which is indistinguishable from a task that has no
        // steps — and somebody would then add the ones already there.
        console.error("[checklist] load:", error);
        if (current) toast.error(tm("common.somethingWrong"));
      });
    return () => {
      current = false;
    };
  }, [taskId, tm]);

  const done = items.filter((item) => item.done).length;

  async function toggle(item: ChecklistItem) {
    const next = !item.done;
    setItems((current) =>
      current.map((one) => (one.id === item.id ? { ...one, done: next } : one)),
    );

    const outcome = await send({ kind: "checklist", taskId, itemId: item.id, done: next });
    // Kept for later: the tick stays.
    if (outcome === "kept") return;
    if (!outcome.ok) {
      setItems((current) =>
        current.map((one) => (one.id === item.id ? { ...one, done: item.done } : one)),
      );
      toast.error(tm(outcome.error));
      return;
    }
    router.refresh();
  }

  async function add(event: React.FormEvent) {
    event.preventDefault();
    const content = adding.trim();
    if (!content) return;

    setBusy(true);
    const outcome = await addChecklistItem(taskId, content);
    setBusy(false);

    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }

    setItems((current) => [...current, outcome.data]);
    setAdding("");
    router.refresh();
  }

  async function remove(item: ChecklistItem) {
    const kept = items;
    setItems((current) => current.filter((one) => one.id !== item.id));

    const outcome = await removeChecklistItem(item.id);
    if (!outcome.ok) {
      setItems(kept);
      toast.error(tm(outcome.error));
      return;
    }
    router.refresh();
  }

  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-center gap-2">
        <span className="text-muted-foreground [&_svg]:size-4">
          <ListChecks />
        </span>
        <span className="text-sm font-medium">{t("checklist.title")}</span>
        {items.length > 0 && (
          <span className="text-xs tabular-nums text-muted-foreground">
            {t("checklist.progress", { done, total: items.length })}
          </span>
        )}
      </div>

      {items.length > 0 && (
        <ul className="flex flex-col gap-0.5">
          {items.map((item) => (
            <li key={item.id} className="group flex items-center gap-2 rounded-md px-1 py-0.5">
              <Checkbox
                id={`step-${item.id}`}
                checked={item.done}
                onCheckedChange={() => toggle(item)}
                aria-label={item.content}
              />
              <label
                htmlFor={`step-${item.id}`}
                className={cn(
                  "min-w-0 flex-1 cursor-pointer text-sm leading-snug",
                  item.done && "text-muted-foreground line-through",
                )}
              >
                {item.content}
              </label>
              {canEdit && (
              <Button
                type="button"
                variant="ghost"
                size="icon-sm"
                onClick={() => remove(item)}
                aria-label={t("checklist.remove", { step: item.content })}
                // Always there on touch, where there is no hover to reveal it.
                className="opacity-0 transition-opacity focus-visible:opacity-100 group-hover:opacity-100 pointer-coarse:opacity-100"
              >
                <X />
              </Button>
              )}
            </li>
          ))}
        </ul>
      )}

      {/* Adding a step is planning; ticking one off is not. Somebody who
          cannot do the first can still do the second. */}
      {canEdit && (
      <form onSubmit={add} className="flex items-center gap-2">
        <Input
          value={adding}
          onChange={(event) => setAdding(event.target.value)}
          placeholder={t("checklist.add")}
          maxLength={500}
          className="h-9"
          aria-label={t("checklist.add")}
        />
        <Button type="submit" variant="outline" size="sm" disabled={busy || !adding.trim()}>
          {busy ? <Loader2 className="animate-spin" /> : <Plus />}
          {t("checklist.addButton")}
        </Button>
      </form>
      )}

      {!canEdit && items.length === 0 && (
        <p className="text-xs text-muted-foreground">{t("checklist.none")}</p>
      )}
    </div>
  );
}
