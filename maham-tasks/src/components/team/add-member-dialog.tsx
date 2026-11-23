"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { Loader2, UserPlus } from "lucide-react";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { FieldError, FormError } from "@/components/auth/field-error";
import { USER_ROLES } from "@/lib/constants";
import { useI18n } from "@/lib/i18n/client";
import { addTeamMember, type AddedTeammate } from "@/lib/data/team-actions";
import type { ActionResult } from "@/lib/action-result";

/**
 * Admin-only: invite somebody to Maham Tasks by their Maham One email.
 *
 * One account opens both apps. They are in once they sign in here with that
 * email (or create their Maham One account with it first), within 30 days;
 * nothing is created for them, and no password changes hands
 * (see team-actions.ts).
 */
export function AddMemberDialog() {
  const router = useRouter();
  const { t } = useI18n();
  const [open, setOpen] = React.useState(false);
  const [pending, setPending] = React.useState(false);
  const [result, setResult] = React.useState<ActionResult<AddedTeammate> | null>(null);

  function reset() {
    setResult(null);
    setPending(false);
  }

  async function onSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPending(true);
    setResult(null);

    const outcome = await addTeamMember(null, new FormData(event.currentTarget));
    setResult(outcome);
    setPending(false);

    if (outcome.ok) router.refresh();
  }

  const done = result?.ok ? result.data : null;
  const errors = result?.ok === false ? result.fieldErrors : undefined;

  return (
    <>
      {/* Right-aligned beside a page title on a desktop; on a phone it
          wraps to its own full-width line, where centring the button and
          its caption read as a mistake. */}
      <div className="flex w-full flex-col items-stretch gap-1 sm:w-auto sm:items-end">
        <Button
          size="sm"
          onClick={() => {
            reset();
            setOpen(true);
          }}
        >
          <UserPlus />
          {t("team.add")}
        </Button>
      </div>

      <Dialog
        open={open}
        onOpenChange={(next) => {
          setOpen(next);
          if (!next) reset();
        }}
      >
        <DialogContent className="max-w-md">
          {done ? (
            <>
              <DialogHeader>
                <DialogTitle>
                  {done.status === "already" ? t("team.already") : t("team.invited")}
                </DialogTitle>
                <DialogDescription>
                  {done.status === "already"
                    ? t("team.alreadyDesc", { email: done.email })
                    : t("team.invitedDesc", { email: done.email })}
                </DialogDescription>
              </DialogHeader>

              <div className="flex justify-end gap-2">
                <Button variant="outline" size="sm" onClick={reset}>
                  {t("team.addAnother")}
                </Button>
                <Button size="sm" onClick={() => setOpen(false)}>
                  {t("common.done")}
                </Button>
              </div>
            </>
          ) : (
            <form onSubmit={onSubmit} className="flex flex-col gap-4" noValidate>
              <DialogHeader>
                <DialogTitle>{t("team.addTitle")}</DialogTitle>
                <DialogDescription>{t("team.addDesc")}</DialogDescription>
              </DialogHeader>

              <FormError message={result?.ok === false ? result.error : null} />

              <div className="flex flex-col gap-1.5">
                <Label htmlFor="member-name">{t("auth.fullName")}</Label>
                <Input
                  id="member-name"
                  name="fullName"
                  autoComplete="off"
                  placeholder={t("team.namePlaceholder")}
                  required
                  aria-invalid={Boolean(errors?.fullName)}
                />
                <FieldError message={errors?.fullName} />
              </div>

              <div className="flex flex-col gap-1.5">
                <Label htmlFor="member-email">{t("auth.email")}</Label>
                <Input
                  id="member-email"
                  name="email"
                  type="email"
                  autoComplete="off"
                  placeholder={t("team.emailPlaceholder")}
                  required
                  aria-invalid={Boolean(errors?.email)}
                />
                <FieldError message={errors?.email} />
              </div>

              <div className="flex flex-col gap-1.5">
                <Label htmlFor="member-role">{t("team.role")}</Label>
                <Select name="role" defaultValue="member">
                  <SelectTrigger id="member-role">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {USER_ROLES.map((role) => (
                      <SelectItem key={role.value} value={role.value}>
                        {t(role.label)}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <FieldError message={errors?.role} />
              </div>

              <div className="flex justify-end gap-2">
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() => setOpen(false)}
                >
                  {t("common.cancel")}
                </Button>
                <Button type="submit" size="sm" disabled={pending}>
                  {pending && <Loader2 className="animate-spin" />}
                  {pending ? t("team.inviting") : t("team.invite")}
                </Button>
              </div>
            </form>
          )}
        </DialogContent>
      </Dialog>
    </>
  );
}
