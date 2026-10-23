"use client";

import * as React from "react";
import { Check, Copy } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { useI18n } from "@/lib/i18n/client";

/**
 * The credentials an admin has to pass on, shown once.
 *
 * Used both when an account is created and when its password is reset, so the
 * two read identically — including the part that matters most, which is that
 * this is the only time the password appears.
 */
export function OneTimePassword({
  email,
  password,
}: {
  email: string;
  password: string;
}) {
  const { t } = useI18n();
  const [copied, setCopied] = React.useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(password);
      setCopied(true);
      toast.success(t("otp.copied"));
    } catch {
      // Clipboard access can be refused; the password is on screen anyway.
      toast.error(t("otp.copyFailed"));
    }
  }

  return (
    <>
      <dl className="flex flex-col gap-3 rounded-2xl bg-muted/40 p-3.5">
        <div className="flex flex-col gap-0.5">
          <dt className="text-xs text-muted-foreground">{t("auth.email")}</dt>
          <dd className="break-all font-mono text-sm">{email}</dd>
        </div>
        <div className="flex flex-col gap-0.5">
          <dt className="text-xs text-muted-foreground">{t("otp.label")}</dt>
          <dd className="flex items-center gap-2">
            <span className="min-w-0 flex-1 break-all font-mono text-sm">
              {password}
            </span>
            <Button
              type="button"
              variant="outline"
              size="icon-sm"
              onClick={copy}
              aria-label={t("otp.copy")}
            >
              {copied ? <Check /> : <Copy />}
            </Button>
          </dd>
        </div>
      </dl>

      <p className="text-xs leading-relaxed text-muted-foreground">
        {t("otp.onlyTime")}
      </p>
    </>
  );
}
