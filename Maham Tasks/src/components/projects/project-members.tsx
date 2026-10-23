"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { Check, Loader2, UserMinus, Users } from "lucide-react";
import { toast } from "sonner";

import {
  Avatar,
  AvatarFallback,
  AvatarImage,
} from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { initialsFrom } from "@/lib/initials";
import {
  addProjectMember,
  removeProjectMember,
} from "@/lib/data/project-actions";
import { cn } from "@/lib/utils";
import { useI18n } from "@/lib/i18n/client";
import type { Profile } from "@/lib/supabase/database.types";

/**
 * Who is on this project.
 *
 * Membership is what makes a project visible at all, so removing someone here
 * takes the project out of their sidebar entirely. Anyone assigned a task in
 * the project is added automatically by a database trigger, so this is for
 * granting access ahead of — or without — assigning work.
 */
export function ProjectMembers({
  projectId,
  members,
  team,
  canManage,
}: {
  projectId: string;
  members: Profile[];
  team: Profile[];
  canManage: boolean;
}) {
  const router = useRouter();
  const { t, tn, tm } = useI18n();
  const [open, setOpen] = React.useState(false);
  const [pending, setPending] = React.useState<string | null>(null);

  const memberIds = new Set(members.map((m) => m.id));
  const candidates = team.filter((person) => !memberIds.has(person.id));

  async function add(person: Profile) {
    setPending(person.id);
    const outcome = await addProjectMember(projectId, person.id);
    setPending(null);

    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }
    toast.success(t("members.canSee", { name: person.full_name ?? person.email }));
    router.refresh();
  }

  async function remove(person: Profile) {
    setPending(person.id);
    const outcome = await removeProjectMember(projectId, person.id);
    setPending(null);

    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }
    toast.success(t("members.removed", { name: person.full_name ?? person.email }));
    router.refresh();
  }

  return (
    <>
      <Button
        variant="outline"
        size="sm"
        onClick={() => setOpen(true)}
        className="gap-2 font-normal"
      >
        <Users />
        {tn("count.members", members.length)}
      </Button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>{t("members.title")}</DialogTitle>
            <DialogDescription>
              {t("members.onlyThese")}{" "}
              {canManage ? t("members.autoAdded") : t("members.askManager")}
            </DialogDescription>
          </DialogHeader>

          {members.length === 0 && (
            <p className="rounded-2xl bg-foreground/[0.05] px-3 py-4 text-center text-sm text-muted-foreground">
              {t("members.nobody")}
            </p>
          )}

          <ul className="flex flex-col gap-1">
            {members.map((person) => (
              <li
                key={person.id}
                className="flex items-center gap-2.5 rounded-md px-1 py-1.5"
              >
                <Avatar className="size-7">
                  {person.avatar_url && (
                    <AvatarImage src={person.avatar_url} alt="" />
                  )}
                  <AvatarFallback className="text-[10px]">
                    {initialsFrom(person.full_name, person.email)}
                  </AvatarFallback>
                </Avatar>

                <span className="min-w-0 flex-1">
                  <span className="block truncate text-sm font-medium">
                    {person.full_name ?? person.email}
                  </span>
                  <span className="block truncate text-xs text-muted-foreground">
                    {person.job_title ?? person.email}
                  </span>
                </span>

                {canManage && (
                  <Button
                    variant="ghost"
                    size="icon-sm"
                    onClick={() => remove(person)}
                    disabled={pending === person.id}
                    aria-label={t("assign.remove", { name: person.full_name ?? person.email })}
                  >
                    {pending === person.id ? (
                      <Loader2 className="animate-spin" />
                    ) : (
                      <UserMinus />
                    )}
                  </Button>
                )}
              </li>
            ))}
          </ul>

          {canManage && (
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="outline" size="sm" disabled={candidates.length === 0}>
                  <Users />
                  {candidates.length === 0
                    ? t("members.everyone")
                    : t("members.addSomeone")}
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent
                align="start"
                className="max-h-64 w-64 overflow-y-auto"
              >
                <DropdownMenuLabel>{t("members.addTo")}</DropdownMenuLabel>
                {candidates.map((person) => (
                  <DropdownMenuItem
                    key={person.id}
                    onSelect={(event) => {
                      event.preventDefault();
                      add(person);
                    }}
                  >
                    <Check className={cn("size-4 opacity-0")} />
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
          )}
        </DialogContent>
      </Dialog>
    </>
  );
}
