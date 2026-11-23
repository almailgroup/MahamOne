"use client";

import * as React from "react";
import { useSearchParams } from "next/navigation";
import {
  ClipboardList,
  Columns3,
  List,
  PhoneCall,
  Plus,
} from "lucide-react";

import { Button } from "@/components/ui/button";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { KanbanBoard } from "@/components/tasks/kanban-board";
import { QuickAddTask } from "@/components/tasks/quick-add-task";
import { TaskDialog } from "@/components/tasks/task-dialog";
import { TaskFilterBar } from "@/components/tasks/task-filter-bar";
import { TaskSortMenu } from "@/components/tasks/task-sort-menu";
import { TaskTable } from "@/components/tasks/task-table";
import { FollowUpList } from "@/components/tasks/follow-up-list";
import { PageHeader, PageShell } from "@/components/layout/page-shell";
import { useTaskStream } from "@/lib/realtime/use-task-stream";
import { csvFilename, tasksToCsv } from "@/lib/csv";
import { downloadText } from "@/lib/download";
import { matchesFilters, type TaskSort } from "@/lib/task-filters";
import { useTaskFilters } from "@/lib/use-task-filters";
import { useI18n } from "@/lib/i18n/client";
import type {
  Profile,
  TaskStatus,
  TaskWithAssignees,
} from "@/lib/supabase/database.types";

/**
 * General tasks: work assigned to people that belongs to no project.
 *
 * Only managers and admins can create one — enforced by RLS, mirrored here by
 * hiding the button rather than letting the save fail.
 */
export function GeneralTasks({
  tasks,
  followUps,
  team,
  profile,
}: {
  tasks: TaskWithAssignees[];
  followUps: TaskWithAssignees[];
  team: Profile[];
  profile: Profile;
}) {
  const { t } = useI18n();
  const liveTasks = useTaskStream({ projectId: null, initial: tasks });

  const [view, setView] = React.useState<"board" | "list" | "followups">(
    "board",
  );
  const { filters, update: updateFilters, clear: clearFilters } = useTaskFilters();

  // The list's order. Held here, not in the list, because on a phone the
  // control for it sits in the filter bar's search row.
  const [sort, setSort] = React.useState<TaskSort | null>(null);
  const [dialogOpen, setDialogOpen] = React.useState(false);
  const [activeTask, setActiveTask] = React.useState<TaskWithAssignees | null>(
    null,
  );
  const [newStatus, setNewStatus] = React.useState<TaskStatus>("todo");

  const canManage = profile.role === "admin" || profile.role === "manager";

  const filtered = React.useMemo(
    () => liveTasks.filter((task) => matchesFilters(task, filters)),
    [liveTasks, filters],
  );

  function openTask(task: TaskWithAssignees) {
    setActiveTask(task);
    setDialogOpen(true);
  }

  function createTask(columnStatus: TaskStatus) {
    setActiveTask(null);
    setNewStatus(columnStatus);
    setDialogOpen(true);
  }

  // ?new=1 opens the New task dialog. Gives the command palette and the `n`
  // shortcut a target that is also a plain, shareable link.
  const searchParams = useSearchParams();
  React.useEffect(() => {
    if (searchParams.get("new") === "1") createTask("todo");
    // Keyed on the params only: re-running when createTask changes identity
    // would reopen the dialog every render after it had been closed.
  }, [searchParams]);

  return (
    <PageShell>
      <PageHeader
        title={t("nav.general")}
        icon={<ClipboardList />}
        description={canManage ? t("general.descManager") : t("general.descMember")}
        actions={
          canManage ? (
            <Button size="sm" onClick={() => createTask("todo")}>
              <Plus />
              {t("general.new")}
            </Button>
          ) : undefined
        }
      />

      <TaskFilterBar
        filters={filters}
        onChange={updateFilters}
        onClear={clearFilters}
        team={team}
        shown={filtered.length}
        total={liveTasks.length}
        searchLabel={t("general.search")}
        actions={
          view === "list" && (
            <TaskSortMenu sort={sort} onSortChange={setSort} className="md:hidden" />
          )
        }
        onExport={() =>
          downloadText(csvFilename("general tasks"), tasksToCsv(filtered, undefined, t))
        }
      >
        <Tabs
          value={view}
          onValueChange={(value) =>
            setView(value as "board" | "list" | "followups")
          }
        >
          <TabsList>
            <TabsTrigger value="board">
              <Columns3 />
              {t("view.board")}
            </TabsTrigger>
            <TabsTrigger value="list">
              <List />
              {t("view.list")}
            </TabsTrigger>
            <TabsTrigger value="followups">
              <PhoneCall />
              {t("view.followUps")}
              {followUps.length > 0 && (
                <span className="ms-0.5 tabular-nums opacity-70">
                  {followUps.length}
                </span>
              )}
            </TabsTrigger>
          </TabsList>
        </Tabs>
      </TaskFilterBar>

      {view === "followups" ? (
        <FollowUpList
          tasks={followUps}
          canManage={canManage}
          onOpenTask={openTask}
        />
      ) : view === "board" ? (
        <KanbanBoard
          tasks={filtered}
          projectId={null}
          canComplete={canManage}
          canCreate={canManage}
          onOpenTask={openTask}
          onCreateTask={createTask}
        />
      ) : (
        <div className="flex flex-col gap-2">
          {canManage && <QuickAddTask projectId={null} />}
          {/* The same powers as the project list: without these, a manager
              on the general list had no selection, no bulk moves and no
              reschedule menu — for no reason but that they were never passed. */}
          <TaskTable
            tasks={filtered}
            onOpenTask={openTask}
            canComplete={canManage}
            canDelete={canManage}
            canReschedule={canManage}
            sort={sort}
            onSortChange={setSort}
          />
        </div>
      )}

      <TaskDialog
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        task={activeTask}
        projectId={null}
        team={team}
        currentProfile={profile}
        defaultStatus={newStatus}
      />
    </PageShell>
  );
}
