"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { Check, Loader2, Plus, Tag } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { LABEL_DOT, useLabels } from "@/components/labels/labels-provider";
import { createLabel } from "@/lib/data/label-actions";
import { cn } from "@/lib/utils";
import { useI18n } from "@/lib/i18n/client";
import type { Label } from "@/lib/supabase/database.types";

/**
 * Labels on a task, chosen like assignees: a menu that stays open while
 * several are ticked, and the chosen ones as chips that come off on a tap.
 *
 * The ids go out as hidden inputs beside a `labelsField` marker, so the save
 * can tell "no labels" from "this form does not set labels".
 */
export function LabelPicker({
  value,
  onChange,
}: {
  value: string[];
  onChange: (next: string[]) => void;
}) {
  const router = useRouter();
  const { t, tn, tm } = useI18n();
  const known = useLabels();
  // A label made here exists before the page has been refreshed to say so.
  const [made, setMade] = React.useState<Label[]>([]);
  const [naming, setNaming] = React.useState(false);
  const [name, setName] = React.useState("");
  const [pending, setPending] = React.useState(false);

  const all = React.useMemo(() => {
    const byId = new Map([...known, ...made].map((label) => [label.id, label]));
    return [...byId.values()].sort((a, b) => a.name.localeCompare(b.name));
  }, [known, made]);

  const selected = new Set(value);
  const chosen = all.filter((label) => selected.has(label.id));

  function toggle(id: string) {
    const next = new Set(selected);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    onChange([...next]);
  }

  async function create() {
    const trimmed = name.trim();
    if (!trimmed) return;
    // Typing a label that already exists picks it rather than failing.
    const existing = all.find((label) => label.name.toLowerCase() === trimmed.toLowerCase());
    if (existing) {
      if (!selected.has(existing.id)) toggle(existing.id);
      setName("");
      setNaming(false);
      return;
    }

    setPending(true);
    const outcome = await createLabel({ name: trimmed });
    setPending(false);
    if (!outcome.ok) {
      toast.error(tm(Object.values(outcome.fieldErrors ?? {})[0] ?? outcome.error));
      return;
    }
    setMade((current) => [...current, outcome.data]);
    onChange([...value, outcome.data.id]);
    setName("");
    setNaming(false);
    router.refresh();
  }

  return (
    <div className="flex flex-col gap-2">
      <input type="hidden" name="labelsField" value="1" />
      {value.map((id) => (
        <input key={id} type="hidden" name="labelIds" value={id} />
      ))}

      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button type="button" variant="outline" size="sm" className="justify-start gap-2 font-normal">
            <Tag className="text-muted-foreground" />
            {chosen.length === 0 ? t("label.none") : tn("label.count", chosen.length)}
          </Button>
        </DropdownMenuTrigger>

        <DropdownMenuContent align="start" className="max-h-72 w-60 overflow-y-auto">
          <DropdownMenuLabel>{t("label.title")}</DropdownMenuLabel>
          {all.length === 0 && (
            <p className="px-2.5 py-1.5 text-xs text-muted-foreground">{t("label.empty")}</p>
          )}
          {all.map((label) => (
            <DropdownMenuItem
              key={label.id}
              onSelect={(event) => {
                event.preventDefault();
                toggle(label.id);
              }}
            >
              <Check className={cn("size-4", selected.has(label.id) ? "opacity-100" : "opacity-0")} />
              <span aria-hidden className={cn("size-2 shrink-0 rounded-full", LABEL_DOT[label.colour])} />
              <span className="truncate">{label.name}</span>
            </DropdownMenuItem>
          ))}
          <DropdownMenuSeparator />
          <DropdownMenuItem onSelect={() => setNaming(true)}>
            <Plus className="size-4" />
            {t("label.new")}
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      {naming && (
        <div className="flex items-center gap-2">
          <Input
            value={name}
            onChange={(event) => setName(event.target.value)}
            onKeyDown={(event) => {
              // Enter would submit the whole task form.
              if (event.key === "Enter") {
                event.preventDefault();
                void create();
              }
              if (event.key === "Escape") {
                event.stopPropagation();
                setNaming(false);
              }
            }}
            placeholder={t("label.namePlaceholder")}
            aria-label={t("label.name")}
            maxLength={30}
            autoFocus
            className="h-9"
          />
          <Button type="button" size="sm" onClick={create} disabled={pending || !name.trim()}>
            {pending ? <Loader2 className="animate-spin" /> : <Plus />}
            {t("label.add")}
          </Button>
        </div>
      )}

      {chosen.length > 0 && (
        <div className="flex flex-wrap gap-1.5">
          {chosen.map((label) => (
            <button
              key={label.id}
              type="button"
              onClick={() => toggle(label.id)}
              className="inline-flex items-center gap-1.5 rounded-full bg-foreground/[0.05] px-2.5 py-0.5 text-xs transition-colors hover:bg-foreground/[0.09] pointer-coarse:min-h-9"
              aria-label={t("label.remove", { name: label.name })}
            >
              <span aria-hidden className={cn("size-1.5 rounded-full", LABEL_DOT[label.colour])} />
              <span className="max-w-[10rem] truncate">{label.name}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
