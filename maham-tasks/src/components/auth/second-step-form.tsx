"use client";

import * as React from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Loader2 } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { CodeInput } from "@/components/auth/code-input";
import { FormError } from "@/components/auth/field-error";
import { createClient } from "@/lib/supabase/client";
import { safeNext } from "@/lib/supabase/second-step";
import { useI18n } from "@/lib/i18n/client";

/**
 * The six digits from the authenticator app.
 *
 * Sent as soon as the sixth is typed — or pasted, or filled in by the phone
 * from its own Passwords app — since there is nothing else on the form.
 */
export function SecondStepForm() {
  const router = useRouter();
  const { t } = useI18n();
  const next = safeNext(useSearchParams().get("next"));

  const [factorId, setFactorId] = React.useState<string | null>(null);
  const [code, setCode] = React.useState("");
  const [pending, setPending] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  React.useEffect(() => {
    let cancelled = false;
    createClient()
      .auth.mfa.listFactors()
      .then(({ data, error: listError }) => {
        if (cancelled) return;
        // No session: the password half has expired or never happened.
        if (listError || !data) {
          router.replace(`/login?next=${encodeURIComponent(next)}`);
          return;
        }
        // Nothing to ask for: somebody came here by hand.
        const factor = data.totp[0];
        if (!factor) {
          router.replace(next);
          return;
        }
        setFactorId(factor.id);
      });
    return () => {
      cancelled = true;
    };
  }, [next, router]);

  const verify = React.useCallback(
    async (digits: string) => {
      if (!factorId || digits.length !== 6) return;
      setPending(true);
      setError(null);

      const { error: verifyError } = await createClient().auth.mfa.challengeAndVerify({
        factorId,
        code: digits,
      });

      if (verifyError) {
        setError(verifyError.status === 429 ? "auth.twoStep.tooMany" : "auth.twoStep.wrongCode");
        setCode("");
        setPending(false);
        return;
      }

      // The client has the new token in its cookie; the middleware sees it
      // on the next request.
      router.replace(next);
      router.refresh();
    },
    [factorId, next, router],
  );

  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        void verify(code);
      }}
      className="flex flex-col gap-4"
      noValidate
    >
      <FormError message={error} />

      <div className="flex flex-col gap-1.5">
        <Label htmlFor="code">{t("auth.twoStep.code")}</Label>
        <CodeInput
          id="code"
          value={code}
          disabled={!factorId || pending}
          onChange={(digits) => {
            setCode(digits);
            if (digits.length === 6) void verify(digits);
          }}
        />
      </div>

      <Button type="submit" disabled={!factorId || pending || code.length !== 6}>
        {pending && <Loader2 className="animate-spin" />}
        {t("auth.twoStep.confirm")}
      </Button>

      <p className="text-center text-sm text-muted-foreground">
        {t("auth.twoStep.lostPhone")}{" "}
        <Link
          href="/auth/signout"
          prefetch={false}
          className="font-medium text-foreground underline-offset-4 hover:underline pointer-coarse:inline-flex pointer-coarse:min-h-11 pointer-coarse:items-center pointer-coarse:px-2"
        >
          {t("auth.twoStep.signOut")}
        </Link>
      </p>
    </form>
  );
}
