import { isDueToday, isOverdue } from "@/lib/dates";
import type { TranslationKey } from "@/lib/i18n";
import { TASK_PRIORITIES, TASK_STATUSES } from "@/lib/constants";
import type {
  TaskPriority,
  TaskStatus,
  TaskWithAssignees,
} from "@/lib/supabase/database.types";

/**
 * The buckets the dashboard links into.
 *
 * Defined once so a card's count and the page it opens can never disagree —
 * both sides run the same predicate over the same task list.
 */
export const TASK_FILTERS = [
  { value: "todo", label: "status.todo", blurb: "filter.todo.blurb" },
  { value: "pending", label: "filter.pending", blurb: "filter.pending.blurb" },
  { value: "in_progress", label: "status.in_progress", blurb: "filter.in_progress.blurb" },
  { value: "in_review", label: "status.in_review", blurb: "filter.in_review.blurb" },
  { value: "done", label: "filter.done", blurb: "filter.done.blurb" },
  { value: "due_today", label: "filter.dueToday", blurb: "filter.dueToday.blurb" },
  { value: "overdue", label: "meta.overdue", blurb: "filter.overdue.blurb" },
  { value: "all", label: "filter.all", blurb: "filter.all.blurb" },
] as const satisfies readonly { value: string; label: TranslationKey; blurb: TranslationKey }[];

export type TaskFilter = (typeof TASK_FILTERS)[number]["value"];

export function isTaskFilter(value: string | undefined): value is TaskFilter {
  return TASK_FILTERS.some((filter) => filter.value === value);
}

/** A dictionary key — render with `t(filterLabel(filter))`. */
export function filterLabel(filter: TaskFilter): TranslationKey {
  return TASK_FILTERS.find((f) => f.value === filter)?.label ?? "nav.tasks";
}

export function filterBlurb(filter: TaskFilter): TranslationKey | "" {
  return TASK_FILTERS.find((f) => f.value === filter)?.blurb ?? "";
}

export function applyTaskFilter(
  tasks: TaskWithAssignees[],
  filter: TaskFilter,
  /** The reader's zone: "due today" is a question about their day. */
  timeZone?: string,
): TaskWithAssignees[] {
  switch (filter) {
    case "todo":
      return tasks.filter((task) => task.status === "todo");
    case "pending":
      return tasks.filter((task) => task.status !== "done");
    case "in_progress":
      return tasks.filter((task) => task.status === "in_progress");
    case "in_review":
      return tasks.filter((task) => task.status === "in_review");
    case "done":
      return tasks.filter((task) => task.status === "done");
    case "due_today":
      return tasks.filter(
        (task) => task.status !== "done" && isDueToday(task.due_at, timeZone),
      );
    case "overdue":
      return tasks.filter((task) => isOverdue(task.due_at, task.status));
    case "all":
    default:
      return tasks;
  }
}

// ---------------------------------------------------------------------------
// The filter bar above every task list
//
// Both project boards and the general list had their own copy of this state,
// its predicate and its markup — and neither survived a reload, so a filtered
// view could not be linked to. One definition now, shared by the bar, the
// lists and the URL.
// ---------------------------------------------------------------------------

export type TaskListFilters = {
  query: string;
  status: TaskStatus | "all";
  priority: TaskPriority | "all";
  /** `all`, `unassigned`, or a profile id. */
  assignee: string;
  /** `all`, or a label id. */
  label: string;
};

export const EMPTY_FILTERS: TaskListFilters = {
  query: "",
  status: "all",
  priority: "all",
  assignee: "all",
  label: "all",
};

export function filtersActive(filters: TaskListFilters): boolean {
  return (
    filters.query.trim() !== "" ||
    filters.status !== "all" ||
    filters.priority !== "all" ||
    filters.assignee !== "all" ||
    filters.label !== "all"
  );
}

export function matchesFilters(
  task: TaskWithAssignees,
  filters: TaskListFilters,
): boolean {
  if (filters.status !== "all" && task.status !== filters.status) return false;
  if (filters.priority !== "all" && task.priority !== filters.priority) {
    return false;
  }

  if (filters.assignee === "unassigned") {
    if (task.assignees.length > 0) return false;
  } else if (filters.assignee !== "all") {
    if (!task.assignees.some((person) => person.id === filters.assignee)) {
      return false;
    }
  }

  if (filters.label !== "all" && !task.labelIds.includes(filters.label)) return false;

  const needle = filters.query.trim().toLowerCase();
  if (needle) {
    const haystack = `${task.title} ${task.description ?? ""}`.toLowerCase();
    if (!haystack.includes(needle)) return false;
  }

  return true;
}

/**
 * Filters as URL search parameters, leaving out anything at its default so a
 * plain view has a plain address. Other parameters on the URL are untouched.
 */
export function writeFiltersToParams(
  filters: TaskListFilters,
  params: URLSearchParams,
): URLSearchParams {
  const next = new URLSearchParams(params);
  const set = (key: string, value: string, empty: string) => {
    if (value === empty) next.delete(key);
    else next.set(key, value);
  };
  set("q", filters.query.trim(), "");
  set("status", filters.status, "all");
  set("priority", filters.priority, "all");
  set("assignee", filters.assignee, "all");
  set("label", filters.label, "all");
  return next;
}

/** Filters from a URL, ignoring anything that is not a real value. */
export function readFiltersFromParams(params: URLSearchParams): TaskListFilters {
  const status = params.get("status");
  const priority = params.get("priority");
  const assignee = params.get("assignee");
  const label = params.get("label");

  return {
    query: params.get("q") ?? "",
    status: isTaskStatus(status) ? status : "all",
    priority: isTaskPriority(priority) ? priority : "all",
    // A profile id is any non-empty value; an id that no longer matches
    // anyone simply matches no tasks, which the bar shows as such.
    assignee: assignee && assignee.trim() ? assignee : "all",
    // Likewise a label that has since been removed matches nothing.
    label: label && label.trim() ? label : "all",
  };
}

function isTaskStatus(value: string | null): value is TaskStatus {
  return TASK_STATUSES.some((status) => status.value === value);
}

function isTaskPriority(value: string | null): value is TaskPriority {
  return TASK_PRIORITIES.some((priority) => priority.value === value);
}

// ---------------------------------------------------------------------------
// Sorting a list
// ---------------------------------------------------------------------------

export type TaskSortKey = "title" | "status" | "priority" | "due" | "project";
export type TaskSort = { key: TaskSortKey; direction: "asc" | "desc" };

/** Dictionary keys — render with `t(TASK_SORT_LABELS[key])`. */
export const TASK_SORT_LABELS: Record<TaskSortKey, TranslationKey> = {
  title: "sort.title",
  status: "sort.status",
  priority: "sort.priority",
  due: "sort.due",
  project: "sort.project",
};

/**
 * What choosing a column does: sort by it, choose it again to flip, a third
 * time to go back to the board's order. The table's headings and the phone's
 * sort menu both go through this, so they cannot disagree.
 */
export function nextSort(current: TaskSort | null, key: TaskSortKey): TaskSort | null {
  if (current?.key !== key) return { key, direction: "asc" };
  if (current.direction === "asc") return { key, direction: "desc" };
  return null;
}

/**
 * A sorted copy. With no sort the list keeps the order it arrived in — the
 * board's own position order — which is the right default and is why "none"
 * is a state rather than a column.
 *
 * Tasks with no due date sort after every dated one in either direction: a
 * missing date is not "earliest" any more than it is "latest".
 */
export function sortTasks(
  tasks: TaskWithAssignees[],
  sort: TaskSort | null,
  projectName?: (projectId: string | null) => string,
): TaskWithAssignees[] {
  if (!sort) return tasks;

  const statusRank = new Map(TASK_STATUSES.map((s, index) => [s.value, index]));
  const priorityRank = new Map(TASK_PRIORITIES.map((p) => [p.value, p.weight]));

  const compare = (a: TaskWithAssignees, b: TaskWithAssignees): number => {
    switch (sort.key) {
      case "title":
        return a.title.localeCompare(b.title, undefined, { sensitivity: "base" });
      case "status":
        return (statusRank.get(a.status) ?? 0) - (statusRank.get(b.status) ?? 0);
      case "priority":
        return (priorityRank.get(a.priority) ?? 0) - (priorityRank.get(b.priority) ?? 0);
      case "project":
        return (projectName?.(a.project_id) ?? "").localeCompare(
          projectName?.(b.project_id) ?? "",
        );
      case "due": {
        if (!a.due_at && !b.due_at) return 0;
        if (!a.due_at) return 1;
        if (!b.due_at) return -1;
        return new Date(a.due_at).getTime() - new Date(b.due_at).getTime();
      }
    }
  };

  const direction = sort.direction === "asc" ? 1 : -1;

  return [...tasks].sort((a, b) => {
    // Undated rows stay at the bottom whichever way the dated ones go.
    if (sort.key === "due" && (!a.due_at || !b.due_at)) return compare(a, b);
    return compare(a, b) * direction;
  });
}
