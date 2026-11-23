"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { CheckCircle2, Loader2 } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { PasswordInput } from "@/components/auth/password-input";
import { PasswordMeter } from "@/components/auth/password-meter";
import { FieldError, FormError } from "@/components/auth/field-error";
import { updatePassword } from "@/lib/auth/actions";
import { useI18n } from "@/lib/i18n/client";
import type { ActionResult } from "@/lib/action-result";

export function ResetPasswordForm() {
  const router = useRouter();
  const { t } = useI18n();
  const [password, setPassword] = React.useState("");
  const [pending, setPending] = React.useState(false);
  const [done, setDone] = React.useState(false);
  const [result, setResult] = React.useState<ActionResult<void> | null>(null);

  async function onSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPending(true);
    setResult(null);

    const outcome = await updatePassword(null, new FormData(event.currentTarget));
    setResult(outcome);

    if (outcome.ok) {
      // The recovery link already signed them in, so there is nowhere to send
      // them but in. Pause long enough to read the confirmation.
      setDone(true);
      setTimeout(() => {
        router.replace("/dashboard");
        router.refresh();
      }, 1200);
      return;
    }
    setPending(false);
  }

  if (done) {
    return (
      <div className="flex flex-col items-center gap-3 py-4 text-center">
        <span className="flex size-11 items-center justify-center rounded-full bg-muted">
          <CheckCircle2 className="size-5" />
        </span>
        <p className="font-medium">{t("auth.passwordChanged")}</p>
        <p className="text-sm text-muted-foreground">{t("auth.takingYou")}</p>
      </div>
    );
  }

  const errors = result?.ok === false ? result.fieldErrors : undefined;

  return (
    <form onSubmit={onSubmit} className="flex flex-col gap-4" noValidate>
      <FormError message={result?.ok === false ? result.error : null} />

      <div className="flex flex-col gap-1.5">
        <Label htmlFor="password">{t("auth.newPassword")}</Label>
        <PasswordInput
          id="password"
          name="password"
          autoComplete="new-password"
          required
          autoFocus
          value={password}
          onChange={(event) => setPassword(event.target.value)}
          invalid={Boolean(errors?.password)}
        />
        <PasswordMeter value={password} />
        <FieldError message={errors?.password} />
      </div>

      <div className="flex flex-col gap-1.5">
        <Label htmlFor="confirm">{t("auth.confirmNewPassword")}</Label>
        <PasswordInput
          id="confirm"
          name="confirm"
          autoComplete="new-password"
          required
          invalid={Boolean(errors?.confirm)}
        />
        <FieldError message={errors?.confirm} />
      </div>

      <Button type="submit" disabled={pending} className="mt-1">
        {pending && <Loader2 className="animate-spin" />}
        {pending ? t("auth.saving") : t("auth.setNewPassword")}
      </Button>
    </form>
  );
}
