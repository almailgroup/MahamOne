"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { Loader2 } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { FieldError, FormError } from "@/components/auth/field-error";
import { createProject, updateProject } from "@/lib/data/project-actions";
import { useI18n } from "@/lib/i18n/client";
import type { ActionResult } from "@/lib/action-result";
import type { Project } from "@/lib/supabase/database.types";

/**
 * Create/edit dialog for a project. Passing `project` switches it to edit mode.
 */
export function ProjectDialog({
  open,
  onOpenChange,
  project,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  project?: Project | null;
}) {
  const router = useRouter();
  const { t } = useI18n();
  const editing = Boolean(project);

  const [pending, setPending] = React.useState(false);
  const [result, setResult] = React.useState<ActionResult<{
    id: string;
  }> | null>(null);

  // Clear stale validation errors whenever the dialog is reopened.
  React.useEffect(() => {
    if (open) setResult(null);
  }, [open]);

  async function onSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPending(true);
    setResult(null);

    const formData = new FormData(event.currentTarget);
    const outcome = project
      ? await updateProject(project.id, null, formData)
      : await createProject(null, formData);

    setPending(false);

    if (!outcome.ok) {
      setResult(outcome);
      return;
    }

    toast.success(editing ? t("project.updated") : t("project.created"));
    onOpenChange(false);
    router.push(`/projects/${outcome.data.id}`);
    router.refresh();
  }

  const errors = result?.ok === false ? result.fieldErrors : undefined;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>{editing ? t("project.edit") : t("nav.newProject")}</DialogTitle>
          <DialogDescription>
            {editing ? t("project.editDesc") : t("project.newDesc")}
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={onSubmit} className="flex flex-col gap-4" noValidate>
          <FormError message={result?.ok === false ? result.error : null} />

          <div className="flex flex-col gap-1.5">
            <Label htmlFor="name">{t("project.name")}</Label>
            <Input
              id="name"
              name="name"
              defaultValue={project?.name ?? ""}
              placeholder={t("project.namePlaceholder")}
              maxLength={120}
              required
              autoFocus
              aria-invalid={Boolean(errors?.name)}
            />
            <FieldError message={errors?.name} />
          </div>

          <div className="flex flex-col gap-1.5">
            <Label htmlFor="description">{t("task.description")}</Label>
            <Textarea
              id="description"
              name="description"
              defaultValue={project?.description ?? ""}
              placeholder={t("project.descPlaceholder")}
              maxLength={2000}
              rows={3}
              aria-invalid={Boolean(errors?.description)}
            />
            <FieldError message={errors?.description} />
          </div>

          <DialogFooter>
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
              {editing ? t("task.saveChanges") : t("project.create")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
