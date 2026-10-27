"use client";

import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { MessageSquare } from "lucide-react";

import { roleMeta } from "@/lib/constants";
import { initialsFrom } from "@/lib/initials";
import { useI18n } from "@/lib/i18n/client";
import type { Profile } from "@/lib/supabase/database.types";

/**
 * Who somebody is, without leaving the page you found them on.
 *
 * Everything here is already public to the workspace — the team page lists
 * all of it — so this is a better view of what was on screen, not a new
 * disclosure. It reads from the profile it was handed rather than fetching,
 * because every caller already has one.
 */
export function PersonProfileDialog({
  person,
  me,
  open,
  onOpenChange,
  onMessage,
}: {
  person: Profile;
  me: Profile;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onMessage: () => void;
}) {
  const { t, tag, timeZone } = useI18n();
  const name = person.full_name ?? person.email;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          {/* The name is the title; it is shown large below, so here it is
              only for a screen reader announcing the dialog. */}
          <DialogTitle className="sr-only">{name}</DialogTitle>
        </DialogHeader>

        <div className="flex flex-col items-center gap-2 pt-1 text-center">
          <Avatar className="size-16">
            <AvatarImage src={person.avatar_url ?? undefined} alt="" />
            <AvatarFallback className="text-lg">
              {initialsFrom(person.full_name, person.email)}
            </AvatarFallback>
          </Avatar>
          <div>
            <p className="text-base font-semibold leading-tight">{name}</p>
            <p className="mt-0.5 text-xs text-muted-foreground">
              {person.job_title ?? t("person.noPosition")}
            </p>
          </div>
          <Badge variant="outline">{t(roleMeta(person.role).label)}</Badge>
        </div>

        <dl className="flex flex-col gap-2 rounded-2xl bg-card shadow-[var(--shadow-xs)] p-3 text-sm">
          <div className="flex items-baseline justify-between gap-3">
            <dt className="shrink-0 text-xs text-muted-foreground">
              {t("person.email")}
            </dt>
            <dd className="min-w-0 truncate text-end">
              <a
                href={`mailto:${person.email}`}
                className="underline-offset-4 hover:underline"
              >
                {person.email}
              </a>
            </dd>
          </div>
          <div className="flex items-baseline justify-between gap-3">
            <dt className="shrink-0 text-xs text-muted-foreground">
              {t("person.position")}
            </dt>
            <dd className="min-w-0 truncate text-end">
              {person.job_title ?? "—"}
            </dd>
          </div>
          <div className="flex items-baseline justify-between gap-3">
            <dt className="shrink-0 text-xs text-muted-foreground">
{t("person.joined")}
            </dt>
            <dd className="min-w-0 truncate text-end tabular-nums">
              {/* A day, not a moment: nobody wants to know somebody joined at
                  4:00 AM. */}
              {new Date(person.created_at).toLocaleDateString(tag, {
                timeZone,
                day: "numeric",
                month: "long",
                year: "numeric",
              })}
            </dd>
          </div>
        </dl>

        {person.id === me.id ? (
          <p className="text-center text-xs text-muted-foreground">
            {t("person.you")}
          </p>
        ) : (
          <Button
            onClick={() => {
              onOpenChange(false);
              onMessage();
            }}
          >
            <MessageSquare />
            {t("person.messagePrivately")}
          </Button>
        )}
      </DialogContent>
    </Dialog>
  );
}
