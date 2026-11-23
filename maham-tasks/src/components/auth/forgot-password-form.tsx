"use client";

import * as React from "react";
import Link from "next/link";
import { ArrowLeft, Loader2, MailCheck } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { FieldError, FormError } from "@/components/auth/field-error";
import { requestPasswordReset } from "@/lib/auth/actions";
import { Emphasised, MARK, useI18n } from "@/lib/i18n/client";
import type { ActionResult } from "@/lib/action-result";

export function ForgotPasswordForm() {
  const { t } = useI18n();
  const [pending, setPending] = React.useState(false);
  const [result, setResult] = React.useState<ActionResult<{
    sentTo: string;
  }> | null>(null);

  async function onSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPending(true);
    setResult(null);
    setResult(await requestPasswordReset(null, new FormData(event.currentTarget)));
    setPending(false);
  }

  // Deliberately the same screen whether or not that address has an account.
  if (result?.ok) {
    return (
      <div className="flex flex-col gap-4">
        <div className="flex flex-col items-center gap-3 rounded-2xl bg-muted/50 px-4 py-6 text-center">
          <span className="flex size-11 items-center justify-center rounded-full bg-card shadow-[var(--shadow-xs)]">
            <MailCheck className="size-5" />
          </span>
          <div className="flex flex-col gap-1">
            <p className="font-medium">{t("auth.checkEmail")}</p>
            <p className="text-sm leading-relaxed text-muted-foreground">
              <Emphasised sentence={t("auth.resetSent", { email: MARK })}>
                {result.data.sentTo}
              </Emphasised>
            </p>
          </div>
        </div>

        <Button asChild variant="outline">
          <Link href="/login">
            <ArrowLeft className="rtl:-scale-x-100" />
            {t("auth.backToSignIn")}
          </Link>
        </Button>
      </div>
    );
  }

  const errors = result?.ok === false ? result.fieldErrors : undefined;

  return (
    <form onSubmit={onSubmit} className="flex flex-col gap-4" noValidate>
      <FormError message={result?.ok === false ? result.error : null} />

      <div className="flex flex-col gap-1.5">
        <Label htmlFor="email">{t("auth.email")}</Label>
        <Input
          id="email"
          name="email"
          type="email"
          autoComplete="email"
          placeholder={t("auth.emailPlaceholder")}
          required
          autoFocus
          aria-invalid={Boolean(errors?.email)}
        />
        <FieldError message={errors?.email} />
      </div>

      <Button type="submit" disabled={pending} className="mt-1">
        {pending && <Loader2 className="animate-spin" />}
        {pending ? t("auth.sending") : t("auth.emailMeLink")}
      </Button>

      <Button asChild variant="ghost" size="sm">
        <Link href="/login">
          <ArrowLeft className="rtl:-scale-x-100" />
          {t("auth.backToSignIn")}
        </Link>
      </Button>
    </form>
  );
}

