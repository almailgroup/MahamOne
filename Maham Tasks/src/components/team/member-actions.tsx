"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { KeyRound, Loader2, MoreHorizontal, ShieldOff } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
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
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { OneTimePassword } from "@/components/team/one-time-password";
import { removeMemberTwoStep, resetMemberPassword } from "@/lib/data/team-actions";
import { useI18n } from "@/lib/i18n/client";

/**
 * Per-member admin actions: issue a new password, or remove a lost phone's
 * two-step sign-in.
 *
 * Somebody locked out has two other routes, and both can fail them — the
 * emailed reset link depends on the mail quota and on their still having the
 * inbox, and waiting for either helps nobody who needs to work today. An admin
 * can hand them a new password the same way they handed them the first one.
 *
 * It is temporary by construction: the account is flagged, so their next sign
 * in asks them to choose their own, and the admin never learns what it becomes.
 */
export function MemberActions({
  userId,
  name,
  configured,
}: {
  userId: string;
  /** Shown in the confirmation, so nobody resets the wrong person. */
  name: string;
  /** Whether the server has the key these actions need. */
  configured: boolean;
}) {
  const router = useRouter();
  const { t, tm } = useI18n();
  const [confirming, setConfirming] = React.useState(false);
  const [confirmingTwoStep, setConfirmingTwoStep] = React.useState(false);
  const [pending, setPending] = React.useState(false);
  const [issued, setIssued] = React.useState<{
    email: string;
    password: string;
  } | null>(null);

  async function reset() {
    setPending(true);
    const outcome = await resetMemberPassword(userId);
    setPending(false);
    setConfirming(false);

    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }

    setIssued(outcome.data);
    router.refresh();
  }

  async function removeTwoStep() {
    setPending(true);
    const outcome = await removeMemberTwoStep(userId);
    setPending(false);
    setConfirmingTwoStep(false);

    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }
    toast.success(
      outcome.data.removed > 0
        ? t("team.twoStepRemoved", { name })
        : t("team.twoStepNone", { name }),
    );
    router.refresh();
  }

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button
            variant="ghost"
            size="icon-sm"
            aria-label={t("team.actionsFor", { name })}
            disabled={pending}
          >
            {pending ? <Loader2 className="animate-spin" /> : <MoreHorizontal />}
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem
            disabled={!configured}
            onSelect={(event) => {
              event.preventDefault();
              setConfirming(true);
            }}
          >
            <KeyRound />
            {t("team.resetPassword")}
          </DropdownMenuItem>
          <DropdownMenuItem
            disabled={!configured}
            onSelect={(event) => {
              event.preventDefault();
              setConfirmingTwoStep(true);
            }}
          >
            <ShieldOff />
            {t("team.removeTwoStep")}
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      <ConfirmDialog
        open={confirming}
        onOpenChange={setConfirming}
        title={t("team.resetTitle")}
        description={t("team.resetBody", { name })}
        confirmLabel={t("team.resetPassword")}
        onConfirm={reset}
      />

      <ConfirmDialog
        open={confirmingTwoStep}
        onOpenChange={setConfirmingTwoStep}
        title={t("team.removeTwoStepTitle")}
        description={t("team.removeTwoStepBody", { name })}
        confirmLabel={t("team.removeTwoStep")}
        onConfirm={removeTwoStep}
      />

      <Dialog
        open={issued !== null}
        onOpenChange={(open) => {
          if (!open) setIssued(null);
        }}
      >
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>{t("team.newPasswordFor", { name })}</DialogTitle>
            <DialogDescription>{t("team.nothingEmailed")}</DialogDescription>
          </DialogHeader>

          {issued && (
            <OneTimePassword email={issued.email} password={issued.password} />
          )}

          <div className="flex justify-end">
            <Button size="sm" onClick={() => setIssued(null)}>
              {t("common.done")}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </>
  );
}
