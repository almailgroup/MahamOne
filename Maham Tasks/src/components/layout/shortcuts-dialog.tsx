"use client";

import * as React from "react";

import { useI18n } from "@/lib/i18n/client";

import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";

/**
 * The keyboard shortcuts, in one place, on `?`.
 *
 * Each of these existed already and none of them was written down anywhere a
 * person would find it. A shortcut nobody knows about is decoration.
 */
const GROUPS = [
  {
    title: "shortcuts.anywhere",
    rows: [
      { keys: ["⌘", "K"], does: "shortcuts.search" },
      { keys: ["N"], does: "shortcuts.newTask" },
      { keys: ["/"], does: "shortcuts.focusSearch" },
      { keys: ["?"], does: "shortcuts.thisList" },
      { keys: ["Esc"], does: "shortcuts.escape" },
    ],
  },
  {
    title: "shortcuts.board",
    rows: [
      { keys: ["Space"], does: "shortcuts.pickUp" },
      { keys: ["↑", "↓", "←", "→"], does: "shortcuts.moveCard" },
    ],
  },
  {
    title: "shortcuts.note",
    rows: [
      { keys: ["Enter"], does: "shortcuts.nextLine" },
      { keys: ["Backspace"], does: "shortcuts.removeLine" },
    ],
  },
] as const;

export function ShortcutsDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const { t } = useI18n();
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>{t("shortcuts.title")}</DialogTitle>
          <DialogDescription>{t("shortcuts.description")}</DialogDescription>
        </DialogHeader>

        <div className="flex flex-col gap-4">
          {GROUPS.map((group) => (
            <section key={group.title}>
              <h3 className="mb-1.5 text-xs font-medium text-muted-foreground">
                {t(group.title)}
              </h3>
              <dl className="flex flex-col gap-1">
                {group.rows.map((row) => (
                  <div
                    key={row.does}
                    className="flex items-center justify-between gap-3 rounded-2xl bg-foreground/[0.04] px-3 py-2"
                  >
                    <dt className="text-sm">{t(row.does)}</dt>
                    <dd className="flex shrink-0 gap-1">
                      {row.keys.map((key) => (
                        <kbd
                          key={key}
                          className="min-w-6 rounded-md bg-card px-1.5 shadow-[var(--shadow-xs)] py-0.5 text-center font-mono text-[11px] leading-4"
                        >
                          {key}
                        </kbd>
                      ))}
                    </dd>
                  </div>
                ))}
              </dl>
            </section>
          ))}
        </div>
      </DialogContent>
    </Dialog>
  );
}
