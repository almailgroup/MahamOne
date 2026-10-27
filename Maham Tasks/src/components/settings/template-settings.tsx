"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { Check, LayoutTemplate, Loader2, Pencil, Trash2, X } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { Input } from "@/components/ui/input";
import { deleteTemplate, updateTemplate } from "@/lib/data/template-actions";
import { useI18n } from "@/lib/i18n/client";
import type { TaskTemplate } from "@/lib/supabase/database.types";

/**
 * The company's task templates: what each is called and when it is usually
 * due. Made by saving a task as a template, from the task itself; kept here.
 */
export function TemplateSettings({ templates }: { templates: TaskTemplate[] }) {
  const router = useRouter();
  const { t, tn, tm } = useI18n();
  const [editing, setEditing] = React.useState<{ id: string; name: string; days: string } | null>(null);
  const [removing, setRemoving] = React.useState<TaskTemplate | null>(null);
  const [pending, startTransition] = React.useTransition();

  const save = () =>
    startTransition(async () => {
      if (!editing) return;
      const days = editing.days.trim() === "" ? null : Number(editing.days);
      const outcome = await updateTemplate(editing.id, { name: editing.name, dueInWorkingDays: days });
      if (!outcome.ok) {
        toast.error(tm(outcome.error));
        return;
      }
      setEditing(null);
      router.refresh();
    });

  const remove = async () => {
    if (!removing) return;
    const outcome = await deleteTemplate(removing.id);
    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }
    setRemoving(null);
    router.refresh();
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle role="heading" aria-level={2} className="flex items-center gap-2">
          <LayoutTemplate className="size-4 text-muted-foreground" aria-hidden />
          {t("template.settingsTitle")}
        </CardTitle>
        <CardDescription>{t("template.settingsDescription")}</CardDescription>
      </CardHeader>

      <CardContent>
        {templates.length === 0 ? (
          <p className="rounded-[1.25rem] bg-foreground/[0.04] px-4 py-3 text-sm text-muted-foreground">
            {t("template.none")}
          </p>
        ) : (
          <ul className="flex flex-col gap-1.5" aria-label={t("template.settingsTitle")}>
            {templates.map((template) =>
              editing?.id === template.id ? (
                <li
                  key={template.id}
                  className="flex flex-col gap-2.5 rounded-[1.25rem] bg-foreground/[0.04] px-4 py-3 sm:flex-row sm:items-center"
                >
                  <Input
                    value={editing.name}
                    onChange={(event) => setEditing({ ...editing, name: event.target.value })}
                    aria-label={t("template.name")}
                    maxLength={80}
                    autoFocus
                    className="h-9 sm:flex-1"
                  />
                  <label className="flex items-center gap-2 text-xs text-muted-foreground">
                    {t("template.dueAfter")}
                    <Input
                      type="number"
                      min={0}
                      max={365}
                      value={editing.days}
                      onChange={(event) => setEditing({ ...editing, days: event.target.value })}
                      className="h-9 w-20"
                    />
                    {t("template.workingDays")}
                  </label>
                  <div className="flex gap-1">
                    <Button size="icon-sm" onClick={save} disabled={pending} aria-label={t("common.save")}>
                      {pending ? <Loader2 className="animate-spin" /> : <Check />}
                    </Button>
                    <Button size="icon-sm" variant="ghost" onClick={() => setEditing(null)} aria-label={t("common.cancel")}>
                      <X />
                    </Button>
                  </div>
                </li>
              ) : (
                <li
                  key={template.id}
                  className="flex items-center justify-between gap-3 rounded-[1.25rem] bg-foreground/[0.04] px-4 py-2.5"
                >
                  <span className="min-w-0">
                    <span className="block truncate text-sm font-medium">{template.name}</span>
                    <span className="block text-xs text-muted-foreground">
                      {tn("template.steps", template.steps.length)}
                      {template.due_in_working_days !== null &&
                        ` · ${tn("template.dueIn", template.due_in_working_days)}`}
                    </span>
                  </span>
                  <span className="flex shrink-0 gap-0.5">
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      onClick={() =>
                        setEditing({
                          id: template.id,
                          name: template.name,
                          days: template.due_in_working_days?.toString() ?? "",
                        })
                      }
                      aria-label={t("template.edit", { name: template.name })}
                      title={t("template.edit", { name: template.name })}
                    >
                      <Pencil />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      onClick={() => setRemoving(template)}
                      aria-label={t("template.delete", { name: template.name })}
                      title={t("template.delete", { name: template.name })}
                    >
                      <Trash2 />
                    </Button>
                  </span>
                </li>
              ),
            )}
          </ul>
        )}
      </CardContent>

      <ConfirmDialog
        open={removing !== null}
        onOpenChange={(open) => !open && setRemoving(null)}
        title={t("template.deleteTitle")}
        description={t("template.deleteBody", { name: removing?.name ?? "" })}
        confirmLabel={t("common.delete")}
        onConfirm={remove}
      />
    </Card>
  );
}
