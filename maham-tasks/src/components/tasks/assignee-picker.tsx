"use client";

import * as React from "react";
import { Check, UserPlus } from "lucide-react";

import {
  Avatar,
  AvatarFallback,
  AvatarImage,
} from "@/components/ui/avatar";
import { initialsFrom } from "@/lib/initials";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";
import { useI18n } from "@/lib/i18n/client";
import type { Profile } from "@/lib/supabase/database.types";

/**
 * Multi-select assignee control. Selected ids are mirrored into hidden inputs
 * so the surrounding plain <form> submits them without extra wiring.
 */
export function AssigneePicker({
  team,
  value,
  onChange,
  name = "assigneeIds",
}: {
  team: Profile[];
  value: string[];
  onChange: (next: string[]) => void;
  name?: string;
}) {
  const { t, tn } = useI18n();
  const selected = new Set(value);

  function toggle(id: string) {
    const next = new Set(selected);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    onChange([...next]);
  }

  const chosen = team.filter((person) => selected.has(person.id));

  return (
    <div className="flex flex-col gap-2">
      {value.map((id) => (
        <input key={id} type="hidden" name={name} value={id} />
      ))}

      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button
            type="button"
            variant="outline"
            size="sm"
            className="justify-start gap-2 font-normal"
          >
            <UserPlus className="text-muted-foreground" />
            {chosen.length === 0
              ? t("filter.unassigned")
              : tn("assign.count", chosen.length)}
          </Button>
        </DropdownMenuTrigger>

        <DropdownMenuContent align="start" className="max-h-64 w-60 overflow-y-auto">
          <DropdownMenuLabel>{t("assign.to")}</DropdownMenuLabel>
          {team.map((person) => (
            <DropdownMenuItem
              key={person.id}
              // Keep the menu open so several people can be picked at once.
              onSelect={(event) => {
                event.preventDefault();
                toggle(person.id);
              }}
            >
              <Check
                className={cn(
                  "size-4",
                  selected.has(person.id) ? "opacity-100" : "opacity-0",
                )}
              />
              <Avatar className="size-5">
                {person.avatar_url && (
                  <AvatarImage src={person.avatar_url} alt="" />
                )}
                <AvatarFallback className="text-[9px]">
                  {initialsFrom(person.full_name, person.email)}
                </AvatarFallback>
              </Avatar>
              <span className="truncate">
                {person.full_name ?? person.email}
              </span>
            </DropdownMenuItem>
          ))}
        </DropdownMenuContent>
      </DropdownMenu>

      {chosen.length > 0 && (
        <div className="flex flex-wrap gap-1.5">
          {chosen.map((person) => (
            <button
              key={person.id}
              type="button"
              onClick={() => toggle(person.id)}
              // A chip is a tap target on a phone: tall enough for a thumb
              // there, and no larger than it needs to be under a mouse.
              className="inline-flex items-center gap-1.5 rounded-full bg-foreground/[0.05] px-2.5 py-0.5 text-xs transition-colors hover:bg-foreground/[0.09] pointer-coarse:min-h-9 pointer-coarse:px-2.5"
              aria-label={t("assign.remove", { name: person.full_name ?? person.email })}
            >
              <Avatar className="size-4">
                {person.avatar_url && (
                  <AvatarImage src={person.avatar_url} alt="" />
                )}
                <AvatarFallback className="text-[8px]">
                  {initialsFrom(person.full_name, person.email)}
                </AvatarFallback>
              </Avatar>
              <span className="max-w-[10rem] truncate">
                {person.full_name ?? person.email}
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
