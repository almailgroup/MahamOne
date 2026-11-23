"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { BookmarkPlus, Loader2, Trash2 } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Separator } from "@/components/ui/separator";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";
import { FieldError, FormError } from "@/components/auth/field-error";
import { AssigneePicker } from "@/components/tasks/assignee-picker";
import { LabelPicker } from "@/components/labels/label-picker";
import { WaitingPanel } from "@/components/tasks/waiting-panel";
import { listTemplates, saveTaskAsTemplate } from "@/lib/data/template-actions";
import { listMilestones } from "@/lib/data/milestone-actions";
import { addWorkingDays, onOrAfterWorkingDay } from "@/lib/work-week";
import { LabelPills } from "@/components/labels/label-pills";
import { TaskProvenance } from "@/components/tasks/task-meta";
import { isoFromLocalInput, quickDateOptions, toLocalInput } from "@/lib/dates";
import { AttachmentPanel } from "@/components/tasks/attachment-panel";
import { ChecklistPanel } from "@/components/tasks/checklist-panel";
import { FollowUpPanel } from "@/components/tasks/follow-up-panel";
import { TaskDetailReadonly } from "@/components/tasks/task-detail-readonly";
import { CommentThread } from "@/components/tasks/comment-thread";
import { TaskActivityFeed } from "@/components/tasks/task-activity-feed";
import {
  createTask,
  deleteTask,
  restoreTask,
  updateTask,
} from "@/lib/data/task-actions";
import { REPEAT_UNITS, TASK_PRIORITIES, TASK_STATUSES } from "@/lib/constants";
import { useHolidaySet } from "@/components/work-calendar/holidays-provider";
import { useI18n } from "@/lib/i18n/client";
import type { ActionResult } from "@/lib/action-result";
import type { TranslationKey } from "@/lib/i18n";
import type {
  Profile,
  ProjectMilestone,
  RepeatUnit,
  TaskStatus,
  TaskTemplate,
  TaskWithAssignees,
} from "@/lib/supabase/database.types";

/** What the select holds: a unit, or the absence of one. */
type RepeatChoice = RepeatUnit | "none";

/**
 * Task detail modal. Doubles as the create form when `task` is null.
 *
 * Comments and activity are loaded and streamed client-side (see
 * CommentThread), so the thread stays live while the modal is open.
 */
export function TaskDialog({
  open,
  onOpenChange,
  task,
  projectId,
  team,
  currentProfile,
  defaultStatus = "todo",
  defaultMilestoneId = null,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  task: TaskWithAssignees | null;
  projectId: string | null;
  team: Profile[];
  currentProfile: Profile;
  defaultStatus?: TaskStatus;
  /** A new task started from a milestone on the timeline goes under it. */
  defaultMilestoneId?: string | null;
}) {
  const router = useRouter();
  const i18n = useI18n();
  const holidays = useHolidaySet();
  const { t, tn, tm } = i18n;
  const editing = Boolean(task);
  const canComplete =
    currentProfile.role === "admin" || currentProfile.role === "manager";
  // Title, description, priority, due date and assignees belong to whoever
  // plans the work. Members see them, they do not set them.
  const canEditDetails = canComplete;

  /** The dialog itself, so focus can land on it rather than on a field. */
  const contentRef = React.useRef<HTMLDivElement>(null);
  // Seeded by the effect below rather than here: this component stays mounted
  // between tasks — only the dialog's contents unmount — so an initial value
  // would be whatever the first task opened had.
  const [repeatEvery, setRepeatEvery] = React.useState<RepeatChoice>("none");
  const [pending, setPending] = React.useState(false);
  const [deleting, setDeleting] = React.useState(false);
  const [result, setResult] = React.useState<ActionResult<{
    id: string;
  }> | null>(null);
  const [assigneeIds, setAssigneeIds] = React.useState<string[]>([]);
  const [labelIds, setLabelIds] = React.useState<string[]>([]);
  // Starting a new task from a template: the list, and the one chosen.
  const [templates, setTemplates] = React.useState<TaskTemplate[]>([]);
  const [template, setTemplate] = React.useState<TaskTemplate | null>(null);
  const [savingTemplate, setSavingTemplate] = React.useState(false);
  // The project's milestones, for a planner to put the task under one.
  const [milestones, setMilestones] = React.useState<ProjectMilestone[]>([]);
  const [milestoneId, setMilestoneId] = React.useState("none");

  // The date field is uncontrolled — its own picker manages it — so a preset
  // writes straight into it, in the viewer's own wall-clock time.
  const dueRef = React.useRef<HTMLInputElement>(null);
  const setDue = (iso: string | null) => {
    if (dueRef.current) dueRef.current.value = toLocalInput(iso);
  };

  // Re-seed local state each time the dialog opens or switches task.
  React.useEffect(() => {
    if (!open) return;
    setResult(null);
    setAssigneeIds(task?.assignees.map((person) => person.id) ?? []);
    setLabelIds(task?.labelIds ?? []);
    setTemplate(null);
    setRepeatEvery(task?.repeat_every ?? "none");
    setMilestoneId(task?.milestone_id ?? defaultMilestoneId ?? "none");
  }, [open, task, defaultMilestoneId]);

  // Only a planner sets it, and only a project has any.
  React.useEffect(() => {
    if (!open || !canEditDetails || !projectId) {
      setMilestones([]);
      return;
    }
    let current = true;
    listMilestones(projectId)
      .then((found) => current && setMilestones(found.milestones))
      .catch(() => undefined);
    return () => {
      current = false;
    };
  }, [open, canEditDetails, projectId]);

  // Reached milestones are history: not offered, unless it is this task's.
  const offeredMilestones = milestones.filter(
    (milestone) => !milestone.done_at || milestone.id === milestoneId,
  );

  // Asked for when a new task is started, not carried on every page.
  React.useEffect(() => {
    if (!open || task) return;
    let current = true;
    listTemplates()
      .then((found) => current && setTemplates(found))
      .catch(() => undefined);
    return () => {
      current = false;
    };
  }, [open, task]);

  /** A template's usual due date: so many working days from today, at five. */
  const templateDue = (days: number | null) => {
    if (days === null) return null;
    const today = new Date();
    const day = days === 0 ? onOrAfterWorkingDay(today, holidays) : addWorkingDays(today, days, holidays);
    day.setHours(17, 0, 0, 0);
    return day.toISOString();
  };

  function chooseTemplate(id: string) {
    const chosen = templates.find((one) => one.id === id) ?? null;
    setTemplate(chosen);
    if (chosen) setLabelIds(chosen.label_ids);
  }

  async function saveAsTemplate() {
    if (!task) return;
    setSavingTemplate(true);
    const outcome = await saveTaskAsTemplate(task.id);
    setSavingTemplate(false);
    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }
    toast.success(t("template.saved", { name: outcome.data.name }));
  }

  async function onSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPending(true);
    setResult(null);

    const formData = new FormData(event.currentTarget);

    // The date input hands over wall-clock time with no offset. Resolve it to
    // an absolute instant here, where the viewer's timezone is known — the
    // server would read it as its own, which is UTC.
    const localDue = String(formData.get("dueAt") ?? "");
    formData.set("dueAt", localDue ? (isoFromLocalInput(localDue) ?? "") : "");
    let outcome: ActionResult<{ id: string }>;
    try {
      outcome = task
        ? await updateTask(task.id, projectId, null, formData)
        : await createTask(projectId, null, formData);
    } catch {
      // No connection: the form is not kept for later (see lib/outbox), so
      // say so, and leave everything typed where it is.
      outcome = { ok: false, error: "offline.needsConnection" };
      // The form's own message is at its top, far above a phone's Save.
      toast.error(t("offline.needsConnection"));
    }

    setPending(false);

    if (!outcome.ok) {
      setResult(outcome);
      return;
    }

    toast.success(editing ? t("task.updated") : t("task.created"));
    onOpenChange(false);
    router.refresh();
  }

  async function onDelete() {
    if (!task) return;
    setDeleting(true);
    const outcome = await deleteTask(task.id, projectId);
    setDeleting(false);

    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }

    // Immediate, and undoable for ten seconds — rather than a question first.
    // A confirmation nobody reads protects nothing; a bin does.
    const { id, title } = task;
    toast.success(t("task.deletedToast"), {
      description: title,
      duration: 10_000,
      action: {
        label: t("common.undo"),
        onClick: async () => {
          const restored = await restoreTask(id, projectId);
          if (!restored.ok) {
            toast.error(tm(restored.error));
            return;
          }
          toast.success(t("task.restored"));
          router.refresh();
        },
      },
    });
    onOpenChange(false);
    router.refresh();
  }

  const errors = result?.ok === false ? result.fieldErrors : undefined;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        ref={contentRef}
        className="max-w-2xl"
        /*
         * Radix focuses the first field on open, and the browser scrolls it
         * into view. In a dialog this tall that left it opening 318 pixels
         * down with the task's own title off the top of the screen — you
         * tapped a task and could not see which one. It also raised the
         * keyboard over half a phone, for a field nobody opening a task to
         * read it wants.
         *
         * Focus goes to the dialog itself instead, which is what a screen
         * reader should announce anyway, and it opens where it starts.
         */
        onOpenAutoFocus={(event) => {
          event.preventDefault();
          contentRef.current?.focus();
        }}
      >
        <DialogHeader>
          <DialogTitle>{editing ? t("task.title") : t("palette.newTask")}</DialogTitle>
          <DialogDescription>
            {!editing
              ? t("task.addToProject")
              : canEditDetails
                ? t("task.updateDetails")
                : t("task.updateProgress")}
          </DialogDescription>
        </DialogHeader>

        {/* Above the branch, so a member sees the same provenance a manager
            does — the read-only view is a different editor, not less detail. */}
        {task && (
          <TaskProvenance
            createdAt={task.created_at}
            creator={team.find((person) => person.id === task.created_by) ?? null}
          />
        )}

        {canEditDetails || !task ? (
          <form
            // A template fills the fields, and they are uncontrolled: a fresh
            // form is the simple way to give them their new starting values.
            key={template?.id ?? "blank"}
            onSubmit={onSubmit}
            className="flex flex-col gap-4"
            noValidate
          >
            <FormError message={result?.ok === false ? result.error : null} />

            {!task && templates.length > 0 && (
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="template">{t("template.startFrom")}</Label>
                <Select value={template?.id ?? "none"} onValueChange={chooseTemplate}>
                  <SelectTrigger id="template">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="none">{t("template.blank")}</SelectItem>
                    {templates.map((one) => (
                      <SelectItem key={one.id} value={one.id}>
                        {one.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                {template && template.steps.length > 0 && (
                  <p className="text-xs text-muted-foreground">
                    {tn("template.bringsSteps", template.steps.length)}
                  </p>
                )}
                {template?.steps.map((step, index) => (
                  <input key={index} type="hidden" name="steps" value={step} />
                ))}
              </div>
            )}

            <div className="flex flex-col gap-1.5">
              <Label htmlFor="title">{t("task.fieldTitle")}</Label>
              <Input
                id="title"
                name="title"
                defaultValue={task?.title ?? template?.title ?? ""}
                placeholder={t("task.titlePlaceholder")}
                maxLength={200}
                required
                autoFocus={!editing}
                aria-invalid={Boolean(errors?.title)}
              />
              <FieldError message={errors?.title} />
            </div>

            <div className="flex flex-col gap-1.5">
              <Label htmlFor="description">{t("task.description")}</Label>
              <Textarea
                id="description"
                name="description"
                defaultValue={task?.description ?? template?.description ?? ""}
                placeholder={t("task.descriptionPlaceholder")}
                rows={3}
                maxLength={20000}
                aria-invalid={Boolean(errors?.description)}
              />
              <FieldError message={errors?.description} />
            </div>

            {/* Four tracks, with the due date spanning two: a datetime-local
                input needs ~210px of content box and one third of this dialog
                gives it 197px, which pushed the native calendar button out
                past the field's own border. */}
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-4">
              <div className="flex min-w-0 flex-col gap-1.5">
                <Label htmlFor="status">{t("sort.status")}</Label>
                <Select
                  name="status"
                  defaultValue={task?.status ?? defaultStatus}
                >
                  <SelectTrigger id="status">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {TASK_STATUSES.map((status) => (
                      <SelectItem
                        key={status.value}
                        value={status.value}
                        // Only managers and admins close a task. Disabling the
                        // option states the rule instead of letting the save fail.
                        disabled={status.value === "done" && !canComplete}
                      >
                        {t(status.label)}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                {!canComplete && (
                  <p className="text-xs text-muted-foreground">
                    {t("task.reviewHint")}
                  </p>
                )}
              </div>

              <div className="flex min-w-0 flex-col gap-1.5">
                <Label htmlFor="priority">{t("sort.priority")}</Label>
                <Select name="priority" defaultValue={task?.priority ?? template?.priority ?? "medium"}>
                  <SelectTrigger id="priority">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {TASK_PRIORITIES.map((priority) => (
                      <SelectItem key={priority.value} value={priority.value}>
                        {t(priority.label)}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              <div className="flex min-w-0 flex-col gap-1.5 sm:col-span-2">
                <Label htmlFor="dueAt">{t("task.dueDateTime")}</Label>
                <Input
                  ref={dueRef}
                  id="dueAt"
                  name="dueAt"
                  type="datetime-local"
                  // Shown in the viewer timezone; the action converts it back
                  // to an absolute instant on save.
                  defaultValue={toLocalInput(
                    task ? task.due_at : templateDue(template?.due_in_working_days ?? null),
                  )}
                  aria-invalid={Boolean(errors?.dueAt)}
                />
                {/* The dates people actually pick, one tap each. The native
                    picker is still there for anything else — but "tomorrow
                    evening" should not take five taps through a calendar. */}
                {canEditDetails && (
                  <div className="chip-strip" aria-label={t("task.quickDates")}>
                    {quickDateOptions(i18n, holidays).map((option) => (
                      <button
                        key={option.key}
                        type="button"
                        onClick={() => setDue(option.value())}
                        className="rounded-full bg-foreground/[0.05] px-2.5 py-1 text-xs text-muted-foreground transition-colors hover:bg-foreground/[0.09] hover:text-foreground pointer-coarse:min-h-11"
                      >
                        {option.label}
                      </button>
                    ))}
                    <button
                      type="button"
                      onClick={() => setDue(null)}
                      className="rounded-full px-2.5 py-1 text-xs text-muted-foreground transition-colors hover:text-foreground pointer-coarse:min-h-11 pointer-coarse:px-3"
                    >
                      {t("task.noDate")}
                    </button>
                  </div>
                )}
                <FieldError message={errors?.dueAt} />
              </div>
            </div>

            {/* Recurrence.
                Every month the same freight reconciliation was retyped from
                memory, which is both a chore and a way to forget one. The
                rule sits on the task rather than in a series of its own:
                closing this one opens the next, so there is only ever one
                open copy and the closed ones are the history.

                The interval only appears once something is chosen — an
                "every 1" beside a "Does not repeat" is a question nobody
                asked. */}
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="repeatEvery">{t("task.repeats")}</Label>
              <div className="flex flex-wrap items-center gap-2">
                <Select
                  name="repeatEvery"
                  value={repeatEvery}
                  onValueChange={(value) => setRepeatEvery(value as RepeatChoice)}
                >
                  <SelectTrigger id="repeatEvery" className="w-auto min-w-44">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="none">{t("task.repeatNever")}</SelectItem>
                    {REPEAT_UNITS.map((unit) => (
                      <SelectItem key={unit} value={unit}>
                        {t(`task.repeat.${unit}` as TranslationKey)}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>

                {repeatEvery !== "none" && (
                  <label className="flex items-center gap-2 text-sm text-muted-foreground">
                    {t("task.repeatEveryN")}
                    <Input
                      id="repeatInterval"
                      name="repeatInterval"
                      type="number"
                      min={1}
                      max={365}
                      defaultValue={task?.repeat_interval ?? 1}
                      className="w-20"
                      aria-invalid={Boolean(errors?.repeatInterval)}
                    />
                    {t(`task.repeatUnit.${repeatEvery}` as TranslationKey)}
                  </label>
                )}
              </div>
              {repeatEvery !== "none" && (
                <p className="text-xs text-muted-foreground">{t("task.repeatHint")}</p>
              )}
              <FieldError message={errors?.repeatEvery ?? errors?.repeatInterval} />
            </div>

            <div className="flex flex-col gap-1.5">
              {/* The picker leads with hidden form inputs, so the stylesheet's
                  label rule cannot see its button; indented by hand to the
                  same 16px, over the button's icon. */}
              <Label className="ps-4">{t("table.assignees")}</Label>
              <AssigneePicker
                team={team}
                value={assigneeIds}
                onChange={setAssigneeIds}
              />
            </div>

            {/* Planning, like the assignees: a member creating a task does
                not label it, and the database would refuse if they tried. */}
            {canEditDetails && (
              <div className="flex flex-col gap-1.5">
                <Label className="ps-4">{t("label.title")}</Label>
                <LabelPicker value={labelIds} onChange={setLabelIds} />
              </div>
            )}

            {canEditDetails && offeredMilestones.length > 0 && (
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="milestoneId">{t("milestone.field")}</Label>
                <input type="hidden" name="milestoneField" value="1" />
                <Select name="milestoneId" value={milestoneId} onValueChange={setMilestoneId}>
                  <SelectTrigger id="milestoneId">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="none">{t("milestone.none")}</SelectItem>
                    {offeredMilestones.map((milestone) => (
                      <SelectItem key={milestone.id} value={milestone.id}>
                        {t("milestone.option", {
                          title: milestone.title,
                          date: new Date(`${milestone.due_on}T12:00:00Z`).toLocaleDateString(i18n.tag, {
                            timeZone: "UTC",
                            day: "numeric",
                            month: "short",
                          }),
                        })}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            )}

            {/* Pinned to the foot of the dialog while the fields are on
                screen. The form is tall enough on a phone that Save sat some
                seven hundred pixels down, and the way you found it was to
                scroll looking for it. */}
            <div className="sticky bottom-0 z-10 -mx-5 mt-1 flex flex-wrap items-center justify-between gap-2 bg-popover px-5 py-3">
              {editing ? (
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={onDelete}
                  disabled={deleting || pending}
                >
                  {deleting ? <Loader2 className="animate-spin" /> : <Trash2 />}
                  {t("common.delete")}
                </Button>
              ) : (
                <span />
              )}

              <div className="flex gap-2">
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => onOpenChange(false)}
                  disabled={pending}
                >
                  {t("common.cancel")}
                </Button>
                <Button type="submit" disabled={pending}>
                  {pending && <Loader2 className="animate-spin" />}
                  {editing ? t("task.saveChanges") : t("task.create")}
                </Button>
              </div>
            </div>
          </form>
        ) : (
          <>
            <LabelPills ids={task.labelIds} max={8} />
            <TaskDetailReadonly
              task={task}
              projectId={projectId}
              canComplete={canComplete}
              onSaved={() => onOpenChange(false)}
            />
          </>
        )}

        {task && (
          <>
            {/* The steps inside the task, above the follow-up: one is what
                the work is made of, the other is when to chase it. */}
            <ChecklistPanel taskId={task.id} canEdit={canEditDetails} />

            {canEditDetails && (
              <div>
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  onClick={saveAsTemplate}
                  disabled={savingTemplate}
                  className="text-muted-foreground"
                >
                  {savingTemplate ? <Loader2 className="animate-spin" /> : <BookmarkPlus />}
                  {t("template.saveAs")}
                </Button>
              </div>
            )}

            <WaitingPanel
              taskId={task.id}
              canEdit={canEditDetails}
              onOpenTask={(id) => {
                onOpenChange(false);
                router.push(`/tasks?filter=all&task=${id}`);
              }}
            />

            <FollowUpPanel task={task} canManage={canEditDetails} />
            <Separator />
            <Tabs defaultValue="comments">
              <TabsList>
                <TabsTrigger value="comments">{t("task.comments")}</TabsTrigger>
                <TabsTrigger value="files">{t("task.files")}</TabsTrigger>
                <TabsTrigger value="activity">{t("task.activity")}</TabsTrigger>
              </TabsList>

              <TabsContent value="comments">
                <CommentThread
                  taskId={task.id}
                  team={team}
                  currentProfile={currentProfile}
                />
              </TabsContent>

              <TabsContent value="files">
                <AttachmentPanel
                  taskId={task.id}
                  currentProfile={currentProfile}
                />
              </TabsContent>

              <TabsContent value="activity">
                <TaskActivityFeed taskId={task.id} />
              </TabsContent>
            </Tabs>
          </>
        )}
      </DialogContent>

    </Dialog>
  );
}
