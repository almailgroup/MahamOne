"use client";

import * as React from "react";
import { Check, MoveRight } from "lucide-react";

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { statusMeta, TASK_STATUSES } from "@/lib/constants";
import { cn } from "@/lib/utils";
import { useI18n } from "@/lib/i18n/client";
import type { TaskStatus } from "@/lib/supabase/database.types";

/**
 * Move a task to another column without dragging it.
 *
 * Dragging is a fine desktop gesture and a poor phone one: the four columns
 * stack vertically there, so hauling a card from To Do to Done means a
 * long-press drag across two screens of scroll. This is the same operation as
 * one tap, and it is also simply faster on a desktop with a mouse.
 *
 * The review gate is enforced here the same way the board enforces it, so a
 * member is never offered a move the database is going to refuse.
 */
export function StatusMoveMenu({
  status,
  canComplete,
  onMove,
  className,
}: {
  status: TaskStatus;
  /** Whether the viewer may mark a task done or reopen a finished one. */
  canComplete: boolean;
  onMove: (next: TaskStatus) => void;
  className?: string;
}) {
  const { t } = useI18n();
  const current = t(statusMeta(status).label);

  const allowed = (next: TaskStatus) => {
    if (canComplete || next === status) return true;
    // Members move work forward to In Review; closing and reopening is not
    // theirs to do.
    return next !== "done" && status !== "done";
  };

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <button
          type="button"
          aria-label={t("task.statusMoveLabel", { status: current })}
          onClick={(event) => event.stopPropagation()}
          onPointerDown={(event) => event.stopPropagation()}
          className={cn(
            "press inline-flex items-center gap-1 rounded-full bg-card shadow-[var(--shadow-xs)] px-2.5 py-1 text-xs font-medium",
            "transition-colors hover:bg-accent",
            "pointer-coarse:min-h-11 pointer-coarse:px-3",
            className,
          )}
        >
          {current}
          <MoveRight className="size-3 text-muted-foreground" />
        </button>
      </DropdownMenuTrigger>

      <DropdownMenuContent align="start" onClick={(e) => e.stopPropagation()}>
        <DropdownMenuLabel>{t("task.moveTo")}</DropdownMenuLabel>
        {TASK_STATUSES.map((entry) => (
          <DropdownMenuItem
            key={entry.value}
            disabled={!allowed(entry.value)}
            onSelect={() => {
              if (entry.value !== status) onMove(entry.value);
            }}
          >
            <span className="flex size-4 items-center justify-center">
              {entry.value === status && <Check className="size-3.5" />}
            </span>
            {t(entry.label)}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
