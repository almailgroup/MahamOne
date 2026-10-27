"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { Check, Loader2, Pencil, Plus, Tag, Trash2, X } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { Input } from "@/components/ui/input";
import { Label as FieldLabel } from "@/components/ui/label";
import { LABEL_COLOURS, LABEL_DOT } from "@/components/labels/labels-provider";
import { createLabel, deleteLabel, updateLabel } from "@/lib/data/label-actions";
import { cn } from "@/lib/utils";
import { useI18n } from "@/lib/i18n/client";
import type { Label, LabelColour } from "@/lib/supabase/database.types";

/** Six round swatches; the chosen one is ringed by space rather than a line. */
function ColourChoice({
  value,
  onChange,
}: {
  value: LabelColour;
  onChange: (colour: LabelColour) => void;
}) {
  const { t } = useI18n();
  return (
    <div className="flex items-center gap-1.5" role="radiogroup" aria-label={t("label.colour")}>
      {LABEL_COLOURS.map((colour) => (
        <button
          key={colour}
          type="button"
          role="radio"
          aria-checked={value === colour}
          aria-label={t(`label.colour.${colour}`)}
          onClick={() => onChange(colour)}
          className={cn(
            "flex size-7 items-center justify-center rounded-full transition-colors hover:bg-foreground/[0.06]",
            value === colour && "bg-foreground/[0.08]",
          )}
        >
          <span className={cn("size-3.5 rounded-full", LABEL_DOT[colour])} />
        </button>
      ))}
    </div>
  );
}

/**
 * The company's labels: what they are called and their colour. Kept by
 * admins and managers, who are the ones who put them on tasks.
 */
export function LabelSettings({ labels }: { labels: Label[] }) {
  const router = useRouter();
  const { t, tm } = useI18n();
  const [name, setName] = React.useState("");
  const [colour, setColour] = React.useState<LabelColour>("blue");
  const [editing, setEditing] = React.useState<{ id: string; name: string; colour: LabelColour } | null>(null);
  const [removing, setRemoving] = React.useState<Label | null>(null);
  const [pending, startTransition] = React.useTransition();

  const failed = (outcome: { error: string; fieldErrors?: Record<string, string> }) => {
    toast.error(tm(Object.values(outcome.fieldErrors ?? {})[0] ?? outcome.error));
  };

  const add = (event: React.FormEvent) => {
    event.preventDefault();
    startTransition(async () => {
      const outcome = await createLabel({ name, colour });
      if (!outcome.ok) return failed(outcome);
      toast.success(t("label.added"));
      setName("");
      router.refresh();
    });
  };

  const save = () =>
    startTransition(async () => {
      if (!editing) return;
      const outcome = await updateLabel(editing.id, { name: editing.name, colour: editing.colour });
      if (!outcome.ok) return failed(outcome);
      setEditing(null);
      router.refresh();
    });

  const remove = async () => {
    if (!removing) return;
    const outcome = await deleteLabel(removing.id);
    if (!outcome.ok) return failed(outcome);
    toast.success(t("label.removed", { name: removing.name }));
    setRemoving(null);
    router.refresh();
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle role="heading" aria-level={2} className="flex items-center gap-2">
          <Tag className="size-4 text-muted-foreground" aria-hidden />
          {t("label.settingsTitle")}
        </CardTitle>
        <CardDescription>{t("label.settingsDescription")}</CardDescription>
      </CardHeader>

      <CardContent className="flex flex-col gap-5">
        {labels.length === 0 ? (
          <p className="rounded-[1.25rem] bg-foreground/[0.04] px-4 py-3 text-sm text-muted-foreground">
            {t("label.emptySettings")}
          </p>
        ) : (
          <ul className="flex flex-col gap-1.5" aria-label={t("label.settingsTitle")}>
            {labels.map((label) =>
              editing?.id === label.id ? (
                <li
                  key={label.id}
                  className="flex flex-col gap-2.5 rounded-[1.25rem] bg-foreground/[0.04] px-4 py-3 sm:flex-row sm:items-center"
                >
                  <Input
                    value={editing.name}
                    onChange={(event) => setEditing({ ...editing, name: event.target.value })}
                    onKeyDown={(event) => {
                      if (event.key === "Enter") save();
                      if (event.key === "Escape") setEditing(null);
                    }}
                    aria-label={t("label.name")}
                    maxLength={30}
                    autoFocus
                    className="h-9 sm:flex-1"
                  />
                  <ColourChoice
                    value={editing.colour}
                    onChange={(next) => setEditing({ ...editing, colour: next })}
                  />
                  <div className="flex gap-1">
                    <Button size="icon-sm" onClick={save} disabled={pending} aria-label={t("common.save")}>
                      {pending ? <Loader2 className="animate-spin" /> : <Check />}
                    </Button>
                    <Button
                      size="icon-sm"
                      variant="ghost"
                      onClick={() => setEditing(null)}
                      aria-label={t("common.cancel")}
                    >
                      <X />
                    </Button>
                  </div>
                </li>
              ) : (
                <li
                  key={label.id}
                  className="flex items-center justify-between gap-3 rounded-[1.25rem] bg-foreground/[0.04] px-4 py-2.5"
                >
                  <span className="flex min-w-0 items-center gap-2.5">
                    <span aria-hidden className={cn("size-2.5 shrink-0 rounded-full", LABEL_DOT[label.colour])} />
                    <span className="truncate text-sm font-medium">{label.name}</span>
                  </span>
                  <span className="flex shrink-0 gap-0.5">
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      onClick={() => setEditing({ id: label.id, name: label.name, colour: label.colour })}
                      aria-label={t("label.edit", { name: label.name })}
                      title={t("label.edit", { name: label.name })}
                    >
                      <Pencil />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      onClick={() => setRemoving(label)}
                      aria-label={t("label.delete", { name: label.name })}
                      title={t("label.delete", { name: label.name })}
                    >
                      <Trash2 />
                    </Button>
                  </span>
                </li>
              ),
            )}
          </ul>
        )}

        <form onSubmit={add} className="flex flex-col gap-3">
          <div className="flex flex-col gap-1.5">
            <FieldLabel htmlFor="label-name">{t("label.newName")}</FieldLabel>
            <Input
              id="label-name"
              value={name}
              onChange={(event) => setName(event.target.value)}
              placeholder={t("label.namePlaceholder")}
              maxLength={30}
            />
          </div>
          <div className="flex flex-wrap items-center justify-between gap-3">
            <ColourChoice value={colour} onChange={setColour} />
            <Button type="submit" disabled={pending || !name.trim()}>
              {pending ? <Loader2 className="animate-spin" /> : <Plus />}
              {t("label.add")}
            </Button>
          </div>
        </form>
      </CardContent>

      <ConfirmDialog
        open={removing !== null}
        onOpenChange={(open) => !open && setRemoving(null)}
        title={t("label.deleteTitle")}
        description={t("label.deleteBody", { name: removing?.name ?? "" })}
        confirmLabel={t("common.delete")}
        onConfirm={remove}
      />
    </Card>
  );
}
