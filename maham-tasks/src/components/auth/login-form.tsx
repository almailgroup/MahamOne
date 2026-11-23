"use client";

import * as React from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Loader2 } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { PasswordInput } from "@/components/auth/password-input";
import { FieldError, FormError } from "@/components/auth/field-error";
import { signIn } from "@/lib/auth/actions";
import { useI18n } from "@/lib/i18n/client";
import type { ActionResult } from "@/lib/action-result";

export function LoginForm() {
  const router = useRouter();
  const { t } = useI18n();
  const searchParams = useSearchParams();
  const next = searchParams.get("next") ?? "/dashboard";
  const linkError = searchParams.get("error");

  const [pending, setPending] = React.useState(false);
  const [result, setResult] = React.useState<ActionResult<{
    redirectTo: string;
  }> | null>(null);

  async function onSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPending(true);
    setResult(null);

    const formData = new FormData(event.currentTarget);
    const outcome = await signIn(null, formData);

    if (outcome.ok) {
      // Navigate from the client so the refreshed session cookie is picked up.
      router.replace(outcome.data.redirectTo);
      router.refresh();
      return;
    }

    setResult(outcome);
    setPending(false);
  }

  const errors = result?.ok === false ? result.fieldErrors : undefined;

  return (
    <form onSubmit={onSubmit} className="flex flex-col gap-4" noValidate>
      <FormError message={result?.ok === false ? result.error : linkError} />

      <input type="hidden" name="next" value={next} />

      <div className="flex flex-col gap-1.5">
        <Label htmlFor="email">{t("auth.email")}</Label>
        <Input
          id="email"
          name="email"
          type="email"
          autoComplete="email"
          placeholder={t("auth.emailPlaceholder")}
          required
          aria-invalid={Boolean(errors?.email)}
        />
        <FieldError message={errors?.email} />
      </div>

      <div className="flex flex-col gap-1.5">
        <div className="flex items-baseline justify-between gap-2">
          <Label htmlFor="password">{t("auth.password")}</Label>
          <Link
            href="/forgot-password"
            // Negative margins keep the row the same height while the link
            // itself is a full-size tap target on a phone.
            className="-my-2.5 -me-1 inline-flex min-h-9 items-center px-1 text-xs font-medium text-muted-foreground underline-offset-4 hover:text-foreground hover:underline"
          >
            {t("auth.forgotPassword")}
          </Link>
        </div>
        <PasswordInput
          id="password"
          name="password"
          autoComplete="current-password"
          required
          invalid={Boolean(errors?.password)}
        />
        <FieldError message={errors?.password} />
      </div>

      <Button type="submit" disabled={pending} className="mt-1">
        {pending && <Loader2 className="animate-spin" />}
        {pending ? t("auth.signingIn") : t("auth.signIn")}
      </Button>
    </form>
  );
}
