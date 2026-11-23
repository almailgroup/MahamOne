"use client";

import * as React from "react";
import { CheckCircle2, Loader2 } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { PasswordInput } from "@/components/auth/password-input";
import { PasswordMeter } from "@/components/auth/password-meter";
import { FieldError, FormError } from "@/components/auth/field-error";
import { changeOwnPassword } from "@/lib/auth/actions";
import { useI18n } from "@/lib/i18n/client";
import type { ActionResult } from "@/lib/action-result";

/**
 * Change your own password without leaving the app.
 *
 * The only other route to a new password was the emailed reset link, which is
 * a strange thing to need when you are already signed in — and useless for
 * somebody an admin set up with a one-time password, who has every reason to
 * change it and no reason to go looking in their inbox.
 */
export function ChangePassword() {
  const { t } = useI18n();
  const [open, setOpen] = React.useState(false);
  const [password, setPassword] = React.useState("");
  const [pending, setPending] = React.useState(false);
  const [result, setResult] = React.useState<ActionResult<void> | null>(null);
  const formRef = React.useRef<HTMLFormElement>(null);

  async function onSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPending(true);
    setResult(null);

    const outcome = await changeOwnPassword(null, new FormData(event.currentTarget));
    setResult(outcome);
    setPending(false);

    if (outcome.ok) {
      formRef.current?.reset();
      setPassword("");
      setOpen(false);
      toast.success(t("auth.passwordChanged"));
    }
  }

  if (!open) {
    return (
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-sm text-muted-foreground">
          {result?.ok ? (
            <span className="inline-flex items-center gap-1.5 text-foreground">
              <CheckCircle2 className="size-4" />
              {t("password.wasChanged")}
            </span>
          ) : (
            t("password.chooseNew")
          )}
        </p>
        <Button variant="outline" size="sm" onClick={() => setOpen(true)}>
          {t("password.change")}
        </Button>
      </div>
    );
  }

  const errors = result?.ok === false ? result.fieldErrors : undefined;

  return (
    <form
      ref={formRef}
      onSubmit={onSubmit}
      className="flex flex-col gap-4"
      noValidate
    >
      <FormError message={result?.ok === false ? result.error : null} />

      <div className="flex flex-col gap-1.5">
        <Label htmlFor="currentPassword">{t("password.current")}</Label>
        <PasswordInput
          id="currentPassword"
          name="currentPassword"
          autoComplete="current-password"
          required
          autoFocus
          invalid={Boolean(errors?.currentPassword)}
        />
        <FieldError message={errors?.currentPassword} />
      </div>

      <div className="flex flex-col gap-1.5">
        <Label htmlFor="newPassword">{t("auth.newPassword")}</Label>
        <PasswordInput
          id="newPassword"
          name="password"
          autoComplete="new-password"
          required
          value={password}
          onChange={(event) => setPassword(event.target.value)}
          invalid={Boolean(errors?.password)}
        />
        <PasswordMeter value={password} />
        <FieldError message={errors?.password} />
      </div>

      <div className="flex flex-col gap-1.5">
        <Label htmlFor="confirmPassword">{t("auth.confirmNewPassword")}</Label>
        <PasswordInput
          id="confirmPassword"
          name="confirm"
          autoComplete="new-password"
          required
          invalid={Boolean(errors?.confirm)}
        />
        <FieldError message={errors?.confirm} />
      </div>

      <div className="flex justify-end gap-2">
        <Button
          type="button"
          variant="outline"
          size="sm"
          onClick={() => {
            setOpen(false);
            setResult(null);
            setPassword("");
          }}
        >
          {t("common.cancel")}
        </Button>
        <Button type="submit" size="sm" disabled={pending}>
          {pending && <Loader2 className="animate-spin" />}
          {pending ? t("auth.saving") : t("password.save")}
        </Button>
      </div>
    </form>
  );
}
