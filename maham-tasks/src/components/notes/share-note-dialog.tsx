"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { Check, Loader2, LogOut, UserMinus, UserPlus, Users } from "lucide-react";
import { toast } from "sonner";

import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
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
import { shareNote, unshareNote } from "@/lib/data/note-actions";
import { cn } from "@/lib/utils";
import { useI18n } from "@/lib/i18n/client";
import type { NoteWithItems, Profile } from "@/lib/supabase/database.types";

/**
 * Who else is on this list.
 *
 * A list nobody has been invited to stays as private as it ever was — there is
 * no manager or admin override on these rows. Sharing is per list and per
 * person, and the owner can take it back.
 *
 * Collaborators get the list itself: they can write in it, add lines, tick
 * them off and remove them. They cannot delete it, and cannot invite anybody
 * else. What they can do is leave.
 */
export function ShareNoteDialog({
  note,
  team,
  profile,
  onLeft,
}: {
  note: NoteWithItems;
  team: Profile[];
  profile: Profile;
  /** Called after leaving a shared list, which removes it from the page. */
  onLeft: () => void;
}) {
  const router = useRouter();
  const { t, tn, tm } = useI18n();
  const [open, setOpen] = React.useState(false);
  const [pending, setPending] = React.useState<string | null>(null);

  const collaborators = note.collaborators;
  const onIt = new Set([note.user_id, ...collaborators.map((p) => p.id)]);
  const candidates = team.filter((person) => !onIt.has(person.id));

  async function add(person: Profile) {
    setPending(person.id);
    const outcome = await shareNote(note.id, person.id);
    setPending(null);

    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }
    toast.success(t("share.canSee", { name: person.full_name ?? person.email }));
    router.refresh();
  }

  async function remove(person: Profile) {
    setPending(person.id);
    const outcome = await unshareNote(note.id, person.id);
    setPending(null);

    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }

    if (person.id === profile.id) {
      setOpen(false);
      onLeft();
      toast.success(t("share.left"));
    } else {
      toast.success(t("share.removed", { name: person.full_name ?? person.email }));
    }
    router.refresh();
  }

  const count = collaborators.length;

  return (
    <>
      <Button
        variant="ghost"
        size="icon-sm"
        onClick={() => setOpen(true)}
        aria-label={count === 0 ? t("share.this") : tn("share.sharedWith", count)}
        title={count === 0 ? t("share.short") : t("notes.sharedWith", { n: count })}
        className={cn(count > 0 && "text-foreground")}
      >
        <Users />
      </Button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>{t("share.this")}</DialogTitle>
            <DialogDescription>
              {note.mine
                ? t("share.ownerDesc")
                : t("share.guestDesc", {
                    name: note.owner?.full_name ?? note.owner?.email ?? t("common.someone"),
                  })}
            </DialogDescription>
          </DialogHeader>

          <ul className="flex flex-col gap-1">
            <Person
              person={note.owner}
              you={note.owner?.id === profile.id}
              badge={t("share.owner")}
            />
            {collaborators.map((person) => (
              <Person
                key={person.id}
                person={person}
                you={person.id === profile.id}
                action={
                  // The owner may remove anybody; everybody else, themselves.
                  note.mine || person.id === profile.id ? (
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      onClick={() => remove(person)}
                      disabled={pending === person.id}
                      aria-label={
                        person.id === profile.id
                          ? t("share.leave")
                          : t("assign.remove", { name: person.full_name ?? person.email })
                      }
                    >
                      {pending === person.id ? (
                        <Loader2 className="animate-spin" />
                      ) : person.id === profile.id ? (
                        <LogOut className="rtl:-scale-x-100" />
                      ) : (
                        <UserMinus />
                      )}
                    </Button>
                  ) : undefined
                }
              />
            ))}
          </ul>

          {note.mine && (
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button
                  variant="outline"
                  size="sm"
                  disabled={candidates.length === 0}
                >
                  <UserPlus />
                  {candidates.length === 0 ? t("share.everyoneOn") : t("members.addSomeone")}
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent
                align="start"
                className="max-h-64 w-64 overflow-y-auto"
              >
                <DropdownMenuLabel>{t("share.with")}</DropdownMenuLabel>
                {candidates.map((person) => (
                  <DropdownMenuItem
                    key={person.id}
                    onSelect={(event) => {
                      event.preventDefault();
                      add(person);
                    }}
                  >
                    <Check className="size-4 opacity-0" />
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

function Person({
  person,
  you,
  badge,
  action,
}: {
  person: Profile | null;
  you: boolean;
  badge?: string;
  action?: React.ReactNode;
}) {
  const { t } = useI18n();
  if (!person) return null;

  return (
    <li className="flex items-center gap-2.5 rounded-md px-1 py-1.5">
      <Avatar className="size-7">
        {person.avatar_url && <AvatarImage src={person.avatar_url} alt="" />}
        <AvatarFallback className="text-[10px]">
          {initialsFrom(person.full_name, person.email)}
        </AvatarFallback>
      </Avatar>

      <span className="min-w-0 flex-1">
        <span className="block truncate text-sm font-medium">
          {person.full_name ?? person.email}
          {you && (
            <span className="ms-1.5 text-xs font-normal text-muted-foreground">
              {t("common.you")}
            </span>
          )}
        </span>
        <span className="block truncate text-xs text-muted-foreground">
          {badge ?? person.email}
        </span>
      </span>

      {action}
    </li>
  );
}
