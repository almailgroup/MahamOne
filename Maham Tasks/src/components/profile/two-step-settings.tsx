"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { Check, Copy, Loader2, ShieldCheck, Smartphone } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { Label } from "@/components/ui/label";
import { CodeInput } from "@/components/auth/code-input";
import { FormError } from "@/components/auth/field-error";
import { createClient } from "@/lib/supabase/client";
import { qrSource } from "@/lib/supabase/second-step";
import { useI18n } from "@/lib/i18n/client";

type State =
  | { kind: "loading" }
  | { kind: "off" }
  | { kind: "setting-up"; factorId: string; qr: string; secret: string; uri: string }
  | { kind: "on"; factorId: string };

/**
 * Two-step sign-in: an authenticator app asked for a code after the password.
 *
 * Everything here talks to Supabase Auth from the browser, as the person
 * themselves — there is nothing for a server to add, and the factor is
 * theirs. Admins need it before they can add people or change roles.
 */
export function TwoStepSettings({ isAdmin }: { isAdmin: boolean }) {
  const router = useRouter();
  const { t } = useI18n();
  const [state, setState] = React.useState<State>({ kind: "loading" });
  const [code, setCode] = React.useState("");
  const [pending, setPending] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);
  const [copied, setCopied] = React.useState(false);
  const [confirmOff, setConfirmOff] = React.useState(false);

  const load = React.useCallback(async () => {
    const { data } = await createClient().auth.mfa.listFactors();
    const factor = data?.totp[0];
    setState(factor ? { kind: "on", factorId: factor.id } : { kind: "off" });
  }, []);

  React.useEffect(() => {
    void load();
  }, [load]);

  async function start() {
    setPending(true);
    setError(null);
    const supabase = createClient();

    // A set-up that was started and never finished leaves an unconfirmed
    // factor behind, and a second one under the same name is refused.
    const { data: existing } = await supabase.auth.mfa.listFactors();
    for (const factor of existing?.all ?? []) {
      if (factor.factor_type === "totp" && factor.status === "unverified") {
        await supabase.auth.mfa.unenroll({ factorId: factor.id });
      }
    }

    const { data, error: enrollError } = await supabase.auth.mfa.enroll({
      factorType: "totp",
      friendlyName: "Authenticator app",
      issuer: "Almailgroup",
    });
    setPending(false);

    if (enrollError || !data) {
      setError("twoStep.couldNotStart");
      return;
    }
    setCode("");
    setState({
      kind: "setting-up",
      factorId: data.id,
      qr: data.totp.qr_code,
      secret: data.totp.secret,
      uri: data.totp.uri,
    });
  }

  async function confirm(digits: string) {
    if (state.kind !== "setting-up" || digits.length !== 6) return;
    setPending(true);
    setError(null);

    const { error: verifyError } = await createClient().auth.mfa.challengeAndVerify({
      factorId: state.factorId,
      code: digits,
    });
    setPending(false);

    if (verifyError) {
      setError("auth.twoStep.wrongCode");
      setCode("");
      return;
    }
    toast.success(t("twoStep.turnedOn"));
    setState({ kind: "on", factorId: state.factorId });
    router.refresh();
  }

  async function cancel() {
    if (state.kind !== "setting-up") return;
    await createClient().auth.mfa.unenroll({ factorId: state.factorId });
    setError(null);
    setState({ kind: "off" });
  }

  async function turnOff() {
    if (state.kind !== "on") return;
    const { error: offError } = await createClient().auth.mfa.unenroll({
      factorId: state.factorId,
    });
    if (offError) {
      toast.error(t("twoStep.couldNotTurnOff"));
      return;
    }
    // The token still says aal2 until it is refreshed; refreshing now means
    // the next page sees the account as it is.
    await createClient().auth.refreshSession();
    toast.success(t("twoStep.turnedOff"));
    setState({ kind: "off" });
    router.refresh();
  }

  async function copySecret(secret: string) {
    try {
      await navigator.clipboard.writeText(secret);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      // The key is on screen to be typed; a refused clipboard costs nothing.
    }
  }

  if (state.kind === "loading") {
    return (
      <div className="flex items-center gap-2 text-sm text-muted-foreground">
        <Loader2 className="size-4 animate-spin" aria-hidden />
        {t("twoStep.checking")}
      </div>
    );
  }

  if (state.kind === "on") {
    return (
      <div className="flex flex-col gap-4">
        <div className="flex items-start gap-3 rounded-[1.25rem] bg-foreground/[0.04] px-4 py-3">
          <ShieldCheck className="mt-0.5 size-5 shrink-0" aria-hidden />
          <div className="flex flex-col gap-0.5">
            <p className="text-sm font-semibold">{t("twoStep.isOn")}</p>
            <p className="text-xs leading-relaxed text-muted-foreground">{t("twoStep.isOnHint")}</p>
          </div>
        </div>
        <div>
          <Button variant="outline" size="sm" onClick={() => setConfirmOff(true)}>
            {t("twoStep.turnOff")}
          </Button>
        </div>
        <ConfirmDialog
          open={confirmOff}
          onOpenChange={setConfirmOff}
          title={t("twoStep.turnOffTitle")}
          description={isAdmin ? t("twoStep.turnOffAdmin") : t("twoStep.turnOffMember")}
          confirmLabel={t("twoStep.turnOff")}
          onConfirm={turnOff}
        />
      </div>
    );
  }

  if (state.kind === "off") {
    return (
      <div className="flex flex-col gap-4">
        <p className="text-sm leading-relaxed text-muted-foreground">
          {isAdmin ? t("twoStep.offAdmin") : t("twoStep.offMember")}
        </p>
        <FormError message={error} />
        <div>
          <Button onClick={start} disabled={pending}>
            {pending ? <Loader2 className="animate-spin" /> : <ShieldCheck />}
            {t("twoStep.setUp")}
          </Button>
        </div>
      </div>
    );
  }

  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        void confirm(code);
      }}
      className="flex flex-col gap-5"
      noValidate
    >
      <ol className="flex flex-col gap-1.5 ps-4 text-sm leading-relaxed text-muted-foreground [list-style:decimal]">
        <li>{t("twoStep.step1")}</li>
        <li>{t("twoStep.step2")}</li>
        <li>{t("twoStep.step3")}</li>
      </ol>

      <div className="flex flex-col items-center gap-3 rounded-[1.75rem] bg-foreground/[0.04] p-5 sm:flex-row sm:items-center sm:gap-5">
        {/* eslint-disable-next-line @next/next/no-img-element -- a data URL from Supabase, nothing to optimise */}
        <img
          src={qrSource(state.qr)}
          alt={t("twoStep.qrAlt")}
          className="size-40 shrink-0 rounded-2xl bg-white p-2.5 shadow-[var(--shadow-xs)]"
        />
        <div className="flex min-w-0 flex-col items-center gap-2 sm:items-start">
          {/* On a phone the QR code is on the very screen that would have to
              scan it; the link hands the key straight to the phone's own
              authenticator instead. */}
          <Button
            asChild
            variant="secondary"
            size="sm"
            className="hidden max-sm:inline-flex pointer-coarse:inline-flex"
          >
            <a href={state.uri}>
              <Smartphone />
              {t("twoStep.addToPhone")}
            </a>
          </Button>
          <span className="text-xs text-muted-foreground">{t("twoStep.orKey")}</span>
          <button
            type="button"
            onClick={() => copySecret(state.secret)}
            className="flex max-w-full items-center gap-2 rounded-full bg-background px-3.5 py-1.5 font-mono text-xs font-semibold tracking-wider shadow-[var(--shadow-xs)] transition-colors hover:bg-accent"
            aria-label={t("twoStep.copyKey")}
            dir="ltr"
          >
            <span className="truncate">{state.secret}</span>
            {copied ? <Check className="size-3.5 shrink-0" /> : <Copy className="size-3.5 shrink-0" />}
          </button>
        </div>
      </div>

      <FormError message={error} />

      <div className="flex flex-col gap-1.5">
        <Label htmlFor="setup-code">{t("auth.twoStep.code")}</Label>
        <CodeInput
          id="setup-code"
          value={code}
          disabled={pending}
          className="sm:max-w-[16rem]"
          onChange={(digits) => {
            setCode(digits);
            if (digits.length === 6) void confirm(digits);
          }}
        />
      </div>

      <div className="flex flex-wrap gap-2">
        <Button type="submit" disabled={pending || code.length !== 6}>
          {pending && <Loader2 className="animate-spin" />}
          {t("twoStep.finish")}
        </Button>
        <Button type="button" variant="ghost" onClick={cancel} disabled={pending}>
          {t("twoStep.cancel")}
        </Button>
      </div>
    </form>
  );
}
