import type { TranslationKey } from "@/lib/i18n";
import type { TaskPriority, TaskStatus, UserRole } from "@/lib/supabase/database.types";

/**
 * Single source of truth for task vocabulary.
 *
 * Statuses wear Maham One's badge colours, as its documents' statuses do:
 * grey to do, blue in progress, violet in review, green done. Priority is a
 * ramp of filled bars; amber stays for work that is late or urgent.
 */

export type StatusMeta = {
  value: TaskStatus;
  /** Dictionary key — render with `t(meta.label)`. */
  label: TranslationKey;
  /** Badge variant from `@/components/ui/badge`. */
  variant: "outline" | "blue" | "violet" | "green";
};

export const TASK_STATUSES: readonly StatusMeta[] = [
  { value: "todo", label: "status.todo", variant: "outline" },
  { value: "in_progress", label: "status.in_progress", variant: "blue" },
  { value: "in_review", label: "status.in_review", variant: "violet" },
  { value: "done", label: "status.done", variant: "green" },
] as const;

export type PriorityMeta = {
  value: TaskPriority;
  label: TranslationKey;
  /** Filled bars out of four — a colourless severity ramp. */
  weight: 1 | 2 | 3 | 4;
};

export const TASK_PRIORITIES: readonly PriorityMeta[] = [
  { value: "low", label: "priority.low", weight: 1 },
  { value: "medium", label: "priority.medium", weight: 2 },
  { value: "high", label: "priority.high", weight: 3 },
  { value: "urgent", label: "priority.urgent", weight: 4 },
] as const;

/**
 * The repeat units, in the order a person thinks of them.
 *
 * Deliberately short: a rule like "the first Monday of the month" wants a
 * calendar generator, and nobody has asked for one.
 */
export const REPEAT_UNITS = ["day", "week", "month", "year"] as const;

export type RoleMeta = {
  value: UserRole;
  label: TranslationKey;
  description: TranslationKey;
};

export const USER_ROLES: readonly RoleMeta[] = [
  {
    value: "admin",
    label: "role.admin",
    description: "role.admin.description",
  },
  {
    value: "manager",
    label: "role.manager",
    description: "role.manager.description",
  },
  {
    value: "member",
    label: "role.member",
    description: "role.member.description",
  },
] as const;

export const statusMeta = (status: TaskStatus): StatusMeta =>
  TASK_STATUSES.find((s) => s.value === status) ?? TASK_STATUSES[0];

export const priorityMeta = (priority: TaskPriority): PriorityMeta =>
  TASK_PRIORITIES.find((p) => p.value === priority) ?? TASK_PRIORITIES[0];

export const roleMeta = (role: UserRole): RoleMeta =>
  USER_ROLES.find((r) => r.value === role) ?? USER_ROLES[2];
