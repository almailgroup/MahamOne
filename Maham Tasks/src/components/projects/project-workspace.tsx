"use client";

import * as React from "react";
import { useRouter, useSearchParams } from "next/navigation";
import {
  ChartNoAxesGantt,
  Columns3,
  Hash,
  List,
  MoreHorizontal,
  Pencil,
  Plus,
  Archive,
  Trash2,
} from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { ProjectDialog } from "@/components/projects/project-dialog";
import { ProjectMembers } from "@/components/projects/project-members";
import { ProjectPulse } from "@/components/projects/project-pulse";
import { ProjectStatus } from "@/components/projects/project-status";
import { ProjectTimeline } from "@/components/projects/project-timeline";
import { PageHeader, PageShell } from "@/components/layout/page-shell";
import { KanbanBoard } from "@/components/tasks/kanban-board";
import { TaskDialog } from "@/components/tasks/task-dialog";
import { QuickAddTask } from "@/components/tasks/quick-add-task";
import { TaskFilterBar } from "@/components/tasks/task-filter-bar";
import { TaskSortMenu } from "@/components/tasks/task-sort-menu";
import { TaskTable } from "@/components/tasks/task-table";
import { useTaskStream } from "@/lib/realtime/use-task-stream";
import { deleteProject, setProjectArchived } from "@/lib/data/project-actions";
import { csvFilename, tasksToCsv } from "@/lib/csv";
import { downloadText } from "@/lib/download";
import { matchesFilters, type TaskSort } from "@/lib/task-filters";
import { useTaskFilters } from "@/lib/use-task-filters";
import { Emphasised, MARK, useI18n } from "@/lib/i18n/client";
import type {
  Profile,
  Project,
  ProjectMilestone,
  TaskStatus,
  TaskWithAssignees,
  ProjectStatusUpdateWithAuthor,
} from "@/lib/supabase/database.types";

type View = "board" | "list" | "timeline";

/**
 * Project workspace: view switcher, filters, and the Kanban/list views.
 *
 * Filtering is client-side. The project task set is small enough that round
 * tripping every keystroke would be slower and less pleasant than filtering
 * the list already in memory.
 */
export function ProjectWorkspace({
  project,
  tasks,
  team,
  members,
  statusUpdates,
  milestones,
  profile,
}: {
  project: Project;
  tasks: TaskWithAssignees[];
  team: Profile[];
  members: Profile[];
  /** Null when they could not be read; [] when nobody has posted one. */
  statusUpdates: ProjectStatusUpdateWithAuthor[] | null;
  /** Null until milestones exist in the database (migration 44). */
  milestones: ProjectMilestone[] | null;
  profile: Profile;
}) {
  const router = useRouter();
  const { t, tn, tm } = useI18n();

  // Keeps the board in sync when teammates change tasks elsewhere.
  const liveTasks = useTaskStream({ projectId: project.id, initial: tasks });

  const [view, setView] = React.useState<View>("board");
  const { filters, update: updateFilters, clear: clearFilters } = useTaskFilters();

  // The list's order. Held here, not in the list, because on a phone the
  // control for it sits in the filter bar's search row.
  const [sort, setSort] = React.useState<TaskSort | null>(null);
  const [taskDialogOpen, setTaskDialogOpen] = React.useState(false);
  const [activeTask, setActiveTask] = React.useState<TaskWithAssignees | null>(
    null,
  );
  const [newTaskStatus, setNewTaskStatus] = React.useState<TaskStatus>("todo");
  const [newTaskMilestone, setNewTaskMilestone] = React.useState<string | null>(null);
  const [projectDialogOpen, setProjectDialogOpen] = React.useState(false);
  const [confirmDelete, setConfirmDelete] = React.useState(false);

  const canManageProject =
    profile.role === "admin" ||
    (profile.role === "manager" && project.created_by === profile.id);
  const canComplete = profile.role === "admin" || profile.role === "manager";
  // Members no longer create or delete tasks; they work the ones assigned to
  // them. Hiding the control states that instead of letting the save fail.
  const canCreate = canComplete;

  const filtered = React.useMemo(
    () => liveTasks.filter((task) => matchesFilters(task, filters)),
    [liveTasks, filters],
  );

  function openTask(task: TaskWithAssignees) {
    setActiveTask(task);
    setTaskDialogOpen(true);
  }

  function createTask(columnStatus: TaskStatus, milestoneId: string | null = null) {
    setActiveTask(null);
    setNewTaskStatus(columnStatus);
    setNewTaskMilestone(milestoneId);
    setTaskDialogOpen(true);
  }

  // ?new=1 opens the New task dialog. Gives the command palette and the `n`
  // shortcut a target that is also a plain, shareable link.
  const searchParams = useSearchParams();
  React.useEffect(() => {
    if (searchParams.get("new") === "1") createTask("todo");
    // Keyed on the params only: re-running when createTask changes identity
    // would reopen the dialog every render after it had been closed.
  }, [searchParams]);

  /**
   * Put the project away, or bring it back.
   *
   * Refused by the database while anything in it is still open, and the
   * refusal says how many — which is the useful half of "no".
   */
  async function onArchive(archived: boolean) {
    const outcome = await setProjectArchived(project.id, archived);
    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }
    toast.success(t(archived ? "project.archived" : "project.restored"));
    router.refresh();
  }

  async function onDeleteProject() {
    const outcome = await deleteProject(project.id);
    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }
    toast.success(t("project.deleted"));
    router.push("/dashboard");
    router.refresh();
  }

  return (
    <PageShell>
      {/* An archived project is still readable, and should say what it is
          the moment somebody arrives on it from a link or a search. */}
      {project.archived_at && (
        <p className="flex items-start gap-2 rounded-2xl bg-muted px-3 py-2 text-xs text-muted-foreground">
          <Archive className="mt-0.5 size-3.5 shrink-0" />
          {t("project.archivedNote")}
        </p>
      )}

      <PageHeader
        title={project.name}
        icon={<Hash />}
        description={project.description ?? undefined}
        actions={
          <>
            <ProjectMembers
              projectId={project.id}
              members={members}
              team={team}
              canManage={profile.role === "admin" || profile.role === "manager"}
            />
            {canCreate && (
              <Button size="sm" onClick={() => createTask("todo")}>
                <Plus />
                {t("palette.newTask")}
              </Button>
            )}

            {canManageProject && (
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button
                    variant="outline"
                    size="icon"
                    aria-label={t("project.actions")}
                  >
                    <MoreHorizontal />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end">
                  <DropdownMenuItem onSelect={() => setProjectDialogOpen(true)}>
                    <Pencil />
                    {t("project.edit")}
                  </DropdownMenuItem>
                  {/* Archiving before deleting, and separated from it: one
                      of these is reversible and the other is not. */}
                  <DropdownMenuItem onSelect={() => onArchive(!project.archived_at)}>
                    <Archive />
                    {t(project.archived_at ? "project.restore" : "project.archive")}
                  </DropdownMenuItem>
                  <DropdownMenuSeparator />
                  <DropdownMenuItem onSelect={() => setConfirmDelete(true)}>
                    <Trash2 />
                    {t("project.delete")}
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            )}
          </>
        }
      />

      {/* What the person running it says, then what the board says. The two
          disagreeing is worth seeing, so they sit together. */}
      <ProjectStatus
        projectId={project.id}
        updates={statusUpdates}
        canPost={canComplete && !project.archived_at}
        meId={profile.id}
        isAdmin={profile.role === "admin"}
      />
      <ProjectPulse tasks={liveTasks} />

      <TaskFilterBar
        filters={filters}
        onChange={updateFilters}
        onClear={clearFilters}
        team={team}
        shown={filtered.length}
        total={liveTasks.length}
        actions={
          view === "list" && (
            <TaskSortMenu sort={sort} onSortChange={setSort} className="md:hidden" />
          )
        }
        onExport={() =>
          downloadText(csvFilename(project.name), tasksToCsv(filtered, undefined, t))
        }
      >
        <Tabs value={view} onValueChange={(value) => setView(value as View)}>
          <TabsList>
            <TabsTrigger value="board">
              <Columns3 />
              {t("view.board")}
            </TabsTrigger>
            <TabsTrigger value="list">
              <List />
              {t("view.list")}
            </TabsTrigger>
            <TabsTrigger value="timeline">
              <ChartNoAxesGantt />
              {t("view.timeline")}
            </TabsTrigger>
          </TabsList>
        </Tabs>
      </TaskFilterBar>

      {view === "timeline" ? (
        <ProjectTimeline
          projectId={project.id}
          milestones={milestones}
          tasks={filtered}
          allTasks={liveTasks}
          canPlan={canComplete && !project.archived_at}
          onOpenTask={openTask}
          onCreateTask={(milestoneId) => createTask("todo", milestoneId)}
        />
      ) : view === "board" ? (
        <KanbanBoard
          tasks={filtered}
          projectId={project.id}
          canComplete={canComplete}
          canCreate={canCreate}
          onOpenTask={openTask}
          onCreateTask={createTask}
        />
      ) : (
        <div className="flex flex-col gap-2">
          {canCreate && <QuickAddTask projectId={project.id} />}
          <TaskTable
            tasks={filtered}
            onOpenTask={openTask}
            projectId={project.id}
            canComplete={canComplete}
            canDelete={canComplete}
            canReschedule={canComplete}
            sort={sort}
            onSortChange={setSort}
          />
        </div>
      )}

      <TaskDialog
        open={taskDialogOpen}
        onOpenChange={setTaskDialogOpen}
        task={activeTask}
        projectId={project.id}
        team={team}
        currentProfile={profile}
        defaultStatus={newTaskStatus}
        defaultMilestoneId={newTaskMilestone}
      />

      <ProjectDialog
        open={projectDialogOpen}
        onOpenChange={setProjectDialogOpen}
        project={project}
      />

      <ConfirmDialog
        open={confirmDelete}
        onOpenChange={setConfirmDelete}
        title={t("project.deleteTitle")}
        description={
          <Emphasised
            sentence={t("project.deleteBody", {
              name: MARK,
              tasks: tn("count.tasks", liveTasks.length),
            })}
          >
            {project.name}
          </Emphasised>
        }
        confirmLabel={t("project.delete")}
        onConfirm={async () => {
          await onDeleteProject();
          setConfirmDelete(false);
        }}
      />
    </PageShell>
  );
}
