"use client";

import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { LABEL_DOT, useLabels } from "@/components/labels/labels-provider";
import { cn } from "@/lib/utils";
import { useI18n } from "@/lib/i18n/client";

/**
 * Narrow a list to one label: `all`, or a label id. Not shown until the
 * company has a label to narrow to.
 */
export function LabelFilter({
  value,
  onChange,
  className,
}: {
  value: string;
  onChange: (next: string) => void;
  className?: string;
}) {
  const { t } = useI18n();
  const labels = useLabels();
  if (labels.length === 0) return null;

  return (
    <Select value={value} onValueChange={onChange}>
      <SelectTrigger size="sm" className={cn("w-[9rem]", className)} aria-label={t("label.filter")}>
        <SelectValue placeholder={t("label.filter")} />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value="all">{t("label.any")}</SelectItem>
        {labels.map((label) => (
          <SelectItem key={label.id} value={label.id}>
            <span aria-hidden className={cn("size-2 shrink-0 rounded-full", LABEL_DOT[label.colour])} />
            {label.name}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
