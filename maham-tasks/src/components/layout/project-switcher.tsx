"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { Check, ChevronsUpDown, FolderPlus, Layers } from "lucide-react";

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";
import { useI18n } from "@/lib/i18n/client";
import type { Project } from "@/lib/supabase/database.types";

/**
 * Workspace switcher. Shows the active project and navigates between them;
 * "New project" is only offered to roles that RLS will actually permit.
 */
export function ProjectSwitcher({
  projects,
  activeProject,
  canCreate,
  onCreate,
}: {
  projects: Project[];
  activeProject?: Project | null;
  canCreate: boolean;
  onCreate?: () => void;
}) {
  const router = useRouter();
  const { t } = useI18n();

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        {/* Maham One's company switcher, for projects. */}
        <button
          type="button"
          className="flex w-full items-center gap-3 rounded-2xl bg-surface p-2 text-start shadow-xs ring-1 ring-slate-900/5 transition-shadow hover:shadow-sm pointer-coarse:min-h-12"
        >
          <span className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-slate-100 text-slate-500">
            <Layers className="size-4" />
          </span>
          <span className="min-w-0 flex-1 truncate text-sm font-semibold text-slate-900">
            {activeProject?.name ?? t("nav.selectProject")}
          </span>
          <ChevronsUpDown className="size-4 shrink-0 text-slate-400" />
        </button>
      </DropdownMenuTrigger>

      <DropdownMenuContent align="start" className="w-[15rem]">
        <DropdownMenuLabel>{t("nav.projects")}</DropdownMenuLabel>

        {projects.length === 0 && (
          <p className="px-2 py-1.5 text-sm text-muted-foreground">
            {t("nav.noProjects")}
          </p>
        )}

        {projects.map((project) => (
          <DropdownMenuItem
            key={project.id}
            onSelect={() => router.push(`/projects/${project.id}`)}
          >
            <Check
              className={cn(
                "size-4",
                project.id === activeProject?.id ? "opacity-100" : "opacity-0",
              )}
            />
            <span className="truncate">{project.name}</span>
          </DropdownMenuItem>
        ))}

        {canCreate && onCreate && (
          <>
            <DropdownMenuSeparator />
            <DropdownMenuItem onSelect={() => onCreate()}>
              <FolderPlus />
              {t("nav.newProject")}
            </DropdownMenuItem>
          </>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
