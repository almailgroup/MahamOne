"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { Check, Copy, Loader2, Mail, MessageCircle, Send, X } from "lucide-react";
import { toast } from "sonner";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Separator } from "@/components/ui/separator";
import {
  createTelegramLinkCode,
  unlinkTelegram,
  updateNotificationPreferences,
} from "@/lib/data/profile-actions";
import { cn } from "@/lib/utils";
import { MARK, useI18n } from "@/lib/i18n/client";
import type { NotificationPreferences } from "@/lib/supabase/database.types";

/**
 * Where task reminders are delivered.
 *
 * A channel with no credentials configured on the server is shown but
 * disabled, with the reason stated — otherwise someone switches it on, hears
 * nothing, and has no way to tell whether the fault is theirs.
 */
export function ReminderSettings({
  preferences,
  email,
  available,
  botUsername,
  devices,
  failures,
}: {
  preferences: NotificationPreferences;
  email: string;
  available: { email: boolean; telegram: boolean; whatsapp: boolean };
  botUsername: string | null;
  /**
   * The push devices block, passed in rather than rendered here: it is the
   * one channel that is not a field on this form — it is a permission the
   * browser grants, per device, and it saves itself.
   */
  devices?: React.ReactNode;
  /**
   * Reminders that could not be delivered. Above the channels rather than
   * below them: it is the reason somebody opened this page.
   */
  failures?: React.ReactNode;
}) {
  const router = useRouter();
  const { t, tm } = useI18n();
  const [saving, setSaving] = React.useState(false);
  const [linking, setLinking] = React.useState(false);
  const [code, setCode] = React.useState<string | null>(null);

  const [form, setForm] = React.useState({
    emailEnabled: preferences.email_enabled,
    telegramEnabled: preferences.telegram_enabled,
    whatsappEnabled: preferences.whatsapp_enabled,
    whatsappNumber: preferences.whatsapp_number ?? "",
    remindAssigned: preferences.remind_assigned,
    remindDueSoon: preferences.remind_due_soon,
    remindOverdue: preferences.remind_overdue,
    remindFollowUp: preferences.remind_follow_up,
    // Undefined until migration 37 has been run, and then left out of the
    // save rather than written to a column that is not there.
    morningSummary: preferences.morning_summary,
    dueSoonLeadHours: preferences.due_soon_lead_hours,
  });

  const set = <K extends keyof typeof form>(key: K, value: (typeof form)[K]) =>
    setForm((current) => ({ ...current, [key]: value }));

  async function save() {
    setSaving(true);
    const outcome = await updateNotificationPreferences(form);
    setSaving(false);

    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }
    toast.success(t("remind.saved"));
    router.refresh();
  }

  async function link() {
    setLinking(true);
    const outcome = await createTelegramLinkCode();
    setLinking(false);

    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }
    setCode(outcome.data.code);
  }

  async function unlink() {
    setLinking(true);
    const outcome = await unlinkTelegram();
    setLinking(false);

    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }
    setCode(null);
    set("telegramEnabled", false);
    toast.success(t("remind.telegramOff"));
    router.refresh();
  }

  const telegramLinked = Boolean(preferences.telegram_chat_id);

  return (
    <div className="flex flex-col gap-5">
      {failures}

      <Channel
        icon={<Mail />}
        title={t("auth.email")}
        detail={email}
        enabled={form.emailEnabled}
        available={available.email}
        unavailableReason={t("remind.noEmailProvider")}
        onToggle={(value) => set("emailEnabled", value)}
      />

      <Channel
        icon={<Send />}
        title={t("remind.telegram")}
        detail={telegramLinked ? t("remind.telegramConnected") : t("remind.notConnected")}
        enabled={form.telegramEnabled}
        available={available.telegram && telegramLinked}
        unavailableReason={
          !available.telegram ? t("remind.noTelegramBot") : t("remind.connectFirst")
        }
        onToggle={(value) => set("telegramEnabled", value)}
      >
        {available.telegram && (
          <div className="mt-2 flex flex-col gap-2">
            {telegramLinked ? (
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={unlink}
                disabled={linking}
                className="self-start"
              >
                {linking ? <Loader2 className="animate-spin" /> : <X />}
                {t("remind.disconnectTelegram")}
              </Button>
            ) : code ? (
              <div className="rounded-xl bg-muted p-3 text-sm">
                <p className="leading-relaxed">
                  {t("remind.openBot", { bot: MARK })
                    .split(MARK)
                    .map((part, index) =>
                      index === 0 ? (
                        <React.Fragment key={index}>
                          {part}
                          {botUsername ? (
                            <a
                              href={`https://t.me/${botUsername}?start=${code}`}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="font-medium underline underline-offset-4"
                            >
                              @{botUsername}
                            </a>
                          ) : (
                            t("remind.yourBot")
                          )}
                        </React.Fragment>
                      ) : (
                        part
                      ),
                    )}
                </p>
                <div className="mt-2 flex items-center gap-2">
                  <code className="rounded-md bg-background shadow-[var(--shadow-xs)] px-2 py-1 font-mono text-sm tracking-widest">
                    /start {code}
                  </code>
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon-sm"
                    onClick={() => {
                      navigator.clipboard?.writeText(`/start ${code}`);
                      toast.success(t("remind.copied"));
                    }}
                    aria-label={t("remind.copyCode")}
                  >
                    <Copy />
                  </Button>
                </div>
                <p className="mt-2 text-xs text-muted-foreground">
                  {t("remind.codeOnce")}
                </p>
              </div>
            ) : (
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={link}
                disabled={linking}
                className="self-start"
              >
                {linking && <Loader2 className="animate-spin" />}
                {t("remind.connectTelegram")}
              </Button>
            )}
          </div>
        )}
      </Channel>

      <Channel
        icon={<MessageCircle />}
        title={t("remind.whatsapp")}
        detail={preferences.whatsapp_number ?? t("remind.noNumber")}
        enabled={form.whatsappEnabled}
        available={available.whatsapp}
        unavailableReason={t("remind.noWhatsappProvider")}
        onToggle={(value) => set("whatsappEnabled", value)}
      >
        {available.whatsapp && (
          <div className="mt-2 flex flex-col gap-1.5">
            <Label htmlFor="whatsappNumber">{t("remind.whatsappNumber")}</Label>
            <Input
              id="whatsappNumber"
              value={form.whatsappNumber}
              onChange={(event) => set("whatsappNumber", event.target.value)}
              placeholder="+971501234567"
              className="max-w-xs"
            />
            <p className="text-xs text-muted-foreground">
              {t("remind.intlFormat")}
            </p>
          </div>
        )}
      </Channel>

      {devices}

      <Separator />

      <fieldset className="flex flex-col gap-3">
        <legend className="text-sm font-medium">{t("remind.when")}</legend>

        <Toggle
          id="remindAssigned"
          label={t("remind.assigned")}
          checked={form.remindAssigned}
          onChange={(v) => set("remindAssigned", v)}
        />
        <Toggle
          id="remindDueSoon"
          label={t("remind.dueSoon")}
          checked={form.remindDueSoon}
          onChange={(v) => set("remindDueSoon", v)}
        />
        <Toggle
          id="remindOverdue"
          label={t("remind.overdue")}
          checked={form.remindOverdue}
          onChange={(v) => set("remindOverdue", v)}
        />
        <Toggle
          id="remindFollowUp"
          label={t("remind.followUp")}
          checked={form.remindFollowUp}
          onChange={(v) => set("remindFollowUp", v)}
        />
        {form.morningSummary !== undefined && (
          <Toggle
            id="morningSummary"
            label={t("remind.summary")}
            checked={form.morningSummary}
            onChange={(v) => set("morningSummary", v)}
          />
        )}

        {form.remindDueSoon && (
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="lead">{t("remind.leadHours")}</Label>
            <Input
              id="lead"
              type="number"
              min={1}
              max={168}
              value={form.dueSoonLeadHours}
              onChange={(event) =>
                set("dueSoonLeadHours", Number(event.target.value))
              }
              className="max-w-[7rem]"
            />
          </div>
        )}
        <p className="text-xs leading-relaxed text-muted-foreground">{t("remind.officeHours")}</p>
      </fieldset>

      <div>
        <Button type="button" onClick={save} disabled={saving}>
          {saving && <Loader2 className="animate-spin" />}
          {t("remind.save")}
        </Button>
      </div>
    </div>
  );
}

function Channel({
  icon,
  title,
  detail,
  enabled,
  available,
  unavailableReason,
  onToggle,
  children,
}: {
  icon: React.ReactNode;
  title: string;
  detail: string;
  enabled: boolean;
  available: boolean;
  unavailableReason: string;
  onToggle: (value: boolean) => void;
  children?: React.ReactNode;
}) {
  const { t } = useI18n();
  return (
    <div
      className={cn(
        "rounded-2xl bg-foreground/[0.05] p-3",
        !available && "opacity-70",
      )}
    >
      <div className="flex items-start gap-3">
        <span className="mt-0.5 text-muted-foreground [&_svg]:size-4">
          {icon}
        </span>

        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <span className="text-sm font-medium">{title}</span>
            {enabled && available && (
              <Badge variant="secondary">
                <Check className="size-3" />
                {t("remind.on")}
              </Badge>
            )}
          </div>
          <p className="truncate text-xs text-muted-foreground">{detail}</p>
          {!available && (
            <p className="mt-1 text-xs text-muted-foreground">
              {unavailableReason}
            </p>
          )}
          {children}
        </div>

        <Checkbox
          checked={enabled && available}
          disabled={!available}
          onCheckedChange={(value) => onToggle(value === true)}
          aria-label={t("remind.channelLabel", { channel: title })}
        />
      </div>
    </div>
  );
}

function Toggle({
  id,
  label,
  checked,
  onChange,
}: {
  id: string;
  label: string;
  checked: boolean;
  onChange: (value: boolean) => void;
}) {
  return (
    <div className="flex items-center gap-2">
      <Checkbox
        id={id}
        checked={checked}
        onCheckedChange={(value) => onChange(value === true)}
      />
      <Label htmlFor={id} className="font-normal">
        {label}
      </Label>
    </div>
  );
}
