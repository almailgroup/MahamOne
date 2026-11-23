"use client";

import { ArrowDown, ArrowUp, ArrowUpDown } from "lucide-react";

import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { useI18n } from "@/lib/i18n/client";
import {
  TASK_SORT_LABELS,
  nextSort,
  type TaskSort,
  type TaskSortKey,
} from "@/lib/task-filters";
import { cn } from "@/lib/utils";

/**
 * Sorting a list on a phone, where there are no column headings to tap.
 *
 * It used to be a "Sort" button on a line of its own between the search and
 * the list — sixty pixels of a phone's height for one word. It is an icon
 * now, in the search row beside the count and the download: the arrow says
 * which way the list runs, and the button fills in while a sort is on, so the
 * state is there to see without the word.
 */
export function TaskSortMenu({
  sort,
  onSortChange,
  withProject = false,
  className,
}: {
  sort: TaskSort | null;
  onSortChange: (sort: TaskSort | null) => void;
  /** Offers sorting by project, on the lists that span more than one. */
  withProject?: boolean;
  className?: string;
}) {
  const { t } = useI18n();
  const Icon = !sort ? ArrowUpDown : sort.direction === "asc" ? ArrowUp : ArrowDown;
  const label = sort
    ? t("sort.current", {
        field: t(TASK_SORT_LABELS[sort.key]),
        direction: t(sort.direction === "asc" ? "sort.ascending" : "sort.descending"),
      })
    : t("sort.label");

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant={sort ? "secondary" : "ghost"}
          size="icon-sm"
          aria-label={label}
          title={label}
          className={cn(sort && "text-foreground", className)}
        >
          <Icon />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="min-w-44">
        {(Object.keys(TASK_SORT_LABELS) as TaskSortKey[])
          .filter((key) => key !== "project" || withProject)
          .map((key) => (
            <DropdownMenuItem key={key} onSelect={() => onSortChange(nextSort(sort, key))}>
              {t(TASK_SORT_LABELS[key])}
              {sort?.key === key && (
                <span className="ms-auto text-muted-foreground">
                  {sort.direction === "asc" ? "↑" : "↓"}
                </span>
              )}
            </DropdownMenuItem>
          ))}
        {sort && (
          <>
            <DropdownMenuSeparator />
            <DropdownMenuItem onSelect={() => onSortChange(null)}>
              {t("table.boardOrder")}
            </DropdownMenuItem>
          </>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
