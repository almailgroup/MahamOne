"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { Check, ChevronsUpDown, FolderPlus, Layers } from "lucide-react";

import { Button } from "@/components/ui/button";
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
        <Button
          variant="outline"
          size="sm"
          className="w-full justify-between gap-2 font-normal"
        >
          <span className="flex min-w-0 items-center gap-2">
            <Layers className="size-3.5 shrink-0 text-muted-foreground" />
            <span className="truncate">
              {activeProject?.name ?? t("nav.selectProject")}
            </span>
          </span>
          <ChevronsUpDown className="size-3.5 shrink-0 text-muted-foreground" />
        </Button>
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
