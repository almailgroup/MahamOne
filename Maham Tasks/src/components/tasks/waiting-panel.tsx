"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { CornerDownRight, Hourglass, Loader2, Search, X } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { StatusBadge } from "@/components/tasks/task-meta";
import {
  addTaskDependency,
  listTaskDependencies,
  removeTaskDependency,
  type TaskDependencies,
  type TaskRef,
} from "@/lib/data/dependency-actions";
import { searchTasks, type TaskSearchHit } from "@/lib/data/task-actions";
import { useI18n } from "@/lib/i18n/client";
import { cn } from "@/lib/utils";

/**
 * What a task waits on, and what is waiting on it.
 *
 * "Pay the deposit" cannot start until "Get the quote approved" is done.
 * Planners link the two here, by finding the other task by name; everybody
 * sees the links. Finishing the last thing a task waits on tells the people
 * on it that they can go ahead — the database does that, not this.
 */
export function WaitingPanel({
  taskId,
  canEdit,
  onOpenTask,
}: {
  taskId: string;
  canEdit: boolean;
  /** Follow a link to the other task, where the page can open one. */
  onOpenTask?: (id: string) => void;
}) {
  const router = useRouter();
  const { t, tm } = useI18n();
  const [links, setLinks] = React.useState<TaskDependencies | null>(null);
  const [query, setQuery] = React.useState("");
  const [hits, setHits] = React.useState<TaskSearchHit[]>([]);
  const [searching, setSearching] = React.useState(false);
  const [busy, setBusy] = React.useState(false);

  const load = React.useCallback(async () => {
    try {
      setLinks(await listTaskDependencies(taskId));
    } catch (error) {
      console.error("[waiting] load:", error);
      toast.error(tm("common.somethingWrong"));
    }
  }, [taskId, tm]);

  React.useEffect(() => {
    void load();
  }, [load]);

  // Search as the name is typed, a beat after the last key.
  React.useEffect(() => {
    const term = query.trim();
    if (term.length < 2) {
      setHits([]);
      return;
    }
    let current = true;
    setSearching(true);
    const timer = window.setTimeout(async () => {
      const found = await searchTasks(term).catch(() => []);
      if (!current) return;
      setHits(found);
      setSearching(false);
    }, 250);
    return () => {
      current = false;
      window.clearTimeout(timer);
    };
  }, [query]);

  if (!links || !links.available) return null;
  if (!canEdit && links.waitingOn.length === 0 && links.holdingUp.length === 0) return null;

  const linked = new Set(links.waitingOn.map((task) => task.id));
  const offered = hits.filter((hit) => hit.id !== taskId && !linked.has(hit.id));
  const open = links.waitingOn.filter((task) => task.status !== "done").length;

  async function add(hit: TaskSearchHit) {
    setBusy(true);
    const outcome = await addTaskDependency(taskId, hit.id);
    setBusy(false);
    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }
    setQuery("");
    setHits([]);
    await load();
    router.refresh();
  }

  async function remove(task: TaskRef) {
    const outcome = await removeTaskDependency(taskId, task.id);
    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }
    await load();
    router.refresh();
  }

  const row = (task: TaskRef, removable: boolean) => (
    <li key={task.id} className="group flex items-center gap-2 rounded-[1.25rem] bg-foreground/[0.04] py-1.5 pe-1.5 ps-3.5">
      <button
        type="button"
        onClick={() => onOpenTask?.(task.id)}
        disabled={!onOpenTask}
        className={cn(
          "min-w-0 flex-1 truncate text-start text-sm",
          task.status === "done" && "text-muted-foreground line-through",
          onOpenTask && "hover:underline",
        )}
      >
        {task.title}
      </button>
      <StatusBadge status={task.status} />
      {removable && (
        <Button
          type="button"
          variant="ghost"
          size="icon-sm"
          onClick={() => remove(task)}
          aria-label={t("dependency.remove", { title: task.title })}
          className="opacity-0 transition-opacity focus-visible:opacity-100 group-hover:opacity-100 pointer-coarse:opacity-100"
        >
          <X />
        </Button>
      )}
    </li>
  );

  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-center gap-2">
        <span className="text-muted-foreground [&_svg]:size-4">
          <Hourglass />
        </span>
        <span className="text-sm font-medium">{t("dependency.title")}</span>
        {links.waitingOn.length > 0 && (
          <span className="text-xs tabular-nums text-muted-foreground">
            {open === 0 ? t("dependency.allDone") : t("dependency.openCount", { n: open })}
          </span>
        )}
      </div>

      {links.waitingOn.length > 0 && (
        <ul className="flex flex-col gap-1">{links.waitingOn.map((task) => row(task, canEdit))}</ul>
      )}

      {canEdit && (
        <div className="relative">
          <Search className="pointer-events-none absolute start-3.5 top-1/2 size-3.5 -translate-y-1/2 text-muted-foreground" />
          <Input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            onKeyDown={(event) => {
              // Enter would submit the task form around this panel's dialog.
              if (event.key === "Enter") event.preventDefault();
            }}
            placeholder={t("dependency.find")}
            aria-label={t("dependency.find")}
            className="h-9 ps-9"
          />
          {(searching || busy) && (
            <Loader2 className="absolute end-3.5 top-1/2 size-3.5 -translate-y-1/2 animate-spin text-muted-foreground" />
          )}
        </div>
      )}

      {canEdit && offered.length > 0 && (
        <ul className="flex flex-col gap-0.5 rounded-[1.25rem] bg-popover p-1 shadow-[var(--shadow-md)]" aria-label={t("dependency.results")}>
          {offered.map((hit) => (
            <li key={hit.id}>
              <button
                type="button"
                onClick={() => add(hit)}
                disabled={busy}
                className="flex w-full items-center gap-2 rounded-2xl px-3 py-2 text-start text-sm transition-colors hover:bg-accent"
              >
                <span className="min-w-0 flex-1">
                  <span className="block truncate font-medium">{hit.title}</span>
                  <span className="block truncate text-xs text-muted-foreground">
                    {hit.projectName ?? t("common.general")}
                  </span>
                </span>
                <StatusBadge status={hit.status} />
              </button>
            </li>
          ))}
        </ul>
      )}

      {links.holdingUp.length > 0 && (
        <div className="flex flex-col gap-1">
          <p className="flex items-center gap-1.5 ps-1 text-xs text-muted-foreground">
            <CornerDownRight className="size-3.5" aria-hidden />
            {t("dependency.holdingUp")}
          </p>
          <ul className="flex flex-col gap-1">{links.holdingUp.map((task) => row(task, false))}</ul>
        </div>
      )}
    </div>
  );
}
