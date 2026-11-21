"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { Loader2, MoreHorizontal, ShieldOff } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { removeMemberTwoStep } from "@/lib/data/team-actions";
import { useI18n } from "@/lib/i18n/client";

/**
 * Per-member admin action: remove a lost phone's two-step sign-in.
 *
 * There is no "reset password" here any more. The account is the person's
 * Maham One account too (payroll and all, for some), so nobody else sets its
 * password: somebody locked out uses "Forgot your password?" on the sign-in
 * page, and the link comes to them.
 */
export function MemberActions({
  userId,
  name,
}: {
  userId: string;
  /** Shown in the confirmation, so nobody acts on the wrong person. */
  name: string;
}) {
  const router = useRouter();
  const { t, tm } = useI18n();
  const [confirmingTwoStep, setConfirmingTwoStep] = React.useState(false);
  const [pending, setPending] = React.useState(false);

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
        open={confirmingTwoStep}
        onOpenChange={setConfirmingTwoStep}
        title={t("team.removeTwoStepTitle")}
        description={t("team.removeTwoStepBody", { name })}
        confirmLabel={t("team.removeTwoStep")}
        onConfirm={removeTwoStep}
      />
    </>
  );
}
