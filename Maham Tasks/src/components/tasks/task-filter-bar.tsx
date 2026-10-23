"use client";

import * as React from "react";
import { Download, Search } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { TASK_PRIORITIES, TASK_STATUSES } from "@/lib/constants";
import { useI18n } from "@/lib/i18n/client";
import { filtersActive, type TaskListFilters } from "@/lib/task-filters";
import { LabelFilter } from "@/components/labels/label-filter";
import type {
  Profile,
  TaskPriority,
  TaskStatus,
} from "@/lib/supabase/database.types";

/**
 * The row of controls above a task list: search, status, priority, assignee,
 * and — once there are any — label.
 *
 * One component for every list. The project board and the general list each
 * had their own copy, which is how one of them ended up with a Clear button
 * and the other without.
 */
export function TaskFilterBar({
  filters,
  onChange,
  onClear,
  team,
  shown,
  total,
  onExport,
  searchLabel,
  children,
  actions,
}: {
  filters: TaskListFilters;
  onChange: (patch: Partial<TaskListFilters>) => void;
  onClear: () => void;
  team: Profile[];
  /** Rows on screen after filtering, and the number before it. */
  shown: number;
  total: number;
  /** Offered when there is something to download. */
  onExport?: () => void;
  searchLabel?: string;
  /** Whatever sits at the left of the bar — typically the view tabs. */
  children?: React.ReactNode;
  /** Small controls for the search row, beside the count — the phone's sort. */
  actions?: React.ReactNode;
}) {
  const { t } = useI18n();
  const active = filtersActive(filters);

  return (
    /*
     * Two rows on a phone, one wrapping row from `sm`.
     *
     * Four controls side by side wrapped to three lines at 390px, and the
     * result count took a fourth to itself with most of it empty. The search
     * and the count share the first row now and the narrowing controls scroll
     * along the second. `order` rather than a different tree, because the
     * desktop order — search, controls, count on the far right — is the one
     * the DOM already has and is worth keeping.
     */
    <div className="flex flex-wrap items-center gap-2">
      {children && <div className="basis-full sm:basis-auto">{children}</div>}

      <div className="relative order-1 min-w-[55%] flex-1 sm:order-none sm:min-w-[10rem] sm:max-w-xs">
        <Search className="pointer-events-none absolute start-2.5 top-1/2 size-3.5 -translate-y-1/2 text-muted-foreground" />
        <Input
          value={filters.query}
          onChange={(event) => onChange({ query: event.target.value })}
          placeholder={t("browser.searchTasks")}
          className="h-9 ps-8"
          aria-label={searchLabel ?? t("browser.searchTasks")}
        />
      </div>

      {/* The three narrowing controls travel together: one sideways row on a
          phone, and ordinary siblings of the bar again from `sm`. */}
      <div className="chip-strip order-3 basis-full -mx-4 px-4 scroll-px-4 sm:order-none sm:mx-0 sm:basis-auto sm:px-0 sm:flex sm:flex-wrap sm:items-center sm:gap-2">
        <Select
          value={filters.status}
          onValueChange={(value) => onChange({ status: value as TaskStatus | "all" })}
        >
          <SelectTrigger size="sm" className="w-[8.5rem]" aria-label={t("sort.status")}>
            <SelectValue placeholder={t("sort.status")} />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">{t("filter.allStatuses")}</SelectItem>
            {TASK_STATUSES.map((option) => (
              <SelectItem key={option.value} value={option.value}>
                {t(option.label)}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>

        <Select
          value={filters.priority}
          onValueChange={(value) =>
            onChange({ priority: value as TaskPriority | "all" })
          }
        >
          <SelectTrigger size="sm" className="w-[8.5rem]" aria-label={t("sort.priority")}>
            <SelectValue placeholder={t("sort.priority")} />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">{t("filter.allPriorities")}</SelectItem>
            {TASK_PRIORITIES.map((option) => (
              <SelectItem key={option.value} value={option.value}>
                {t(option.label)}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>

        <Select
          value={filters.assignee}
          onValueChange={(value) => onChange({ assignee: value })}
        >
          <SelectTrigger size="sm" className="w-[9.5rem]" aria-label={t("filter.assignee")}>
            <SelectValue placeholder={t("filter.assignee")} />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">{t("filter.anyone")}</SelectItem>
            <SelectItem value="unassigned">{t("filter.unassigned")}</SelectItem>
            {team.map((person) => (
              <SelectItem key={person.id} value={person.id}>
                {person.full_name ?? person.email}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>

        <LabelFilter value={filters.label} onChange={(label) => onChange({ label })} />

        {active && (
          <Button variant="ghost" size="sm" onClick={onClear}>
            {t("common.clear")}
          </Button>
        )}
      </div>

      <span className="order-2 flex shrink-0 items-center gap-2 text-xs text-muted-foreground sm:order-none sm:ms-auto">
        <span className="tabular-nums">
          {t("browser.countOf", { shown, total })}
        </span>
        {actions}
        {onExport && shown > 0 && (
          <Button
            variant="ghost"
            size="sm"
            onClick={onExport}
            aria-label={t("browser.exportLabel")}
            title={t("browser.exportTitle")}
          >
            <Download />
            <span className="hidden sm:inline">{t("common.export")}</span>
          </Button>
        )}
      </span>
    </div>
  );
}
