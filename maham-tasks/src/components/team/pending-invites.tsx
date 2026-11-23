"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { Loader2, MailPlus } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { withdrawInvite } from "@/lib/data/team-actions";
import { roleMeta } from "@/lib/constants";
import { useI18n } from "@/lib/i18n/client";
import type { UserRole } from "@/lib/supabase/database.types";

export type PendingInvite = {
  email: string;
  full_name: string | null;
  role: UserRole;
  expires_at: string;
};

/**
 * Admin-only: invites nobody has accepted yet, with the day each lapses, and
 * a way to take one back. An invite is accepted by signing in here with that
 * email (see team-actions.ts).
 */
export function PendingInvites({ invites }: { invites: PendingInvite[] }) {
  const router = useRouter();
  const i18n = useI18n();
  const { t, tm } = i18n;
  const day = (iso: string) =>
    new Date(iso).toLocaleDateString(i18n.tag, {
      day: "numeric",
      month: "short",
      year: "numeric",
      timeZone: i18n.timeZone,
    });
  const [busy, setBusy] = React.useState<string | null>(null);

  if (invites.length === 0) return null;

  async function withdraw(email: string) {
    setBusy(email);
    const outcome = await withdrawInvite(email);
    setBusy(null);
    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }
    toast.success(t("team.withdrawn", { email }));
    router.refresh();
  }

  return (
    <Card className="flex flex-col gap-1 p-1 sm:p-1.5">
      <h2 className="flex items-center gap-2 px-2.5 pt-2.5 text-sm font-semibold text-slate-900 sm:px-3.5">
        <MailPlus className="size-4 text-slate-500" aria-hidden />
        {t("team.invitedList")}
      </h2>
      {invites.map((invite) => (
        <div
          key={invite.email}
          className="flex flex-wrap items-center justify-between gap-x-3 gap-y-2 rounded-lg px-2.5 py-3 sm:p-3.5"
        >
          <div className="min-w-0">
            <p className="truncate text-sm font-medium text-slate-900">{invite.full_name ?? invite.email}</p>
            <p className="truncate text-xs text-muted-foreground">
              {invite.email} · {t(roleMeta(invite.role).label)} ·{" "}
              {t("team.inviteOpenUntil", { date: day(invite.expires_at) })}
            </p>
          </div>
          <Button
            variant="outline"
            size="sm"
            disabled={busy !== null}
            onClick={() => void withdraw(invite.email)}
          >
            {busy === invite.email && <Loader2 className="animate-spin" />}
            {t("team.withdraw")}
          </Button>
        </div>
      ))}
    </Card>
  );
}
