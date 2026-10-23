import "server-only";

import webpush from "web-push";

import { createAdminClient } from "@/lib/supabase/admin";
import { pushSubject, vapidKeys } from "@/lib/push/keys";
import type { DeliveryResult, QueuedReminder } from "./types";

/**
 * Delivery adapters.
 *
 * Each provider is behind one function with the same shape, so swapping
 * Resend for SES, or Twilio for Meta's Cloud API, means rewriting one function
 * and nothing else. A channel with no credentials configured reports a
 * non-retryable failure rather than throwing, so one unconfigured provider
 * cannot stop the rest of the queue from going out.
 */

const APP_NAME = "Almailgroup Task Portal";

function appUrl(): string {
  return process.env.NEXT_PUBLIC_SITE_URL ?? "";
}

/** Link back into the app, appended to every message. */
function appLink(): string {
  const base = appUrl();
  return base ? `\n\n${base}/today` : "";
}

// ---------------------------------------------------------------------------
// Email — Resend
// ---------------------------------------------------------------------------

async function sendEmail(reminder: QueuedReminder): Promise<DeliveryResult> {
  const apiKey = process.env.RESEND_API_KEY;
  const from = process.env.REMINDER_EMAIL_FROM;

  if (!apiKey || !from) {
    return {
      ok: false,
      error: "Email is not configured (RESEND_API_KEY / REMINDER_EMAIL_FROM).",
      retryable: false,
    };
  }

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: [reminder.recipient],
      subject: reminder.subject ?? APP_NAME,
      text: `${reminder.body}${appLink()}`,
    }),
  });

  if (response.ok) return { ok: true };

  const detail = await response.text().catch(() => "");
  return {
    ok: false,
    error: `Resend ${response.status}: ${detail.slice(0, 200)}`,
    // 429 and 5xx are worth another go; a 4xx means the request itself is wrong.
    retryable: response.status === 429 || response.status >= 500,
  };
}

// ---------------------------------------------------------------------------
// Telegram — Bot API
// ---------------------------------------------------------------------------

/**
 * Telegram's HTML mode needs exactly three characters escaped.
 *
 * The alternative — `parse_mode: "Markdown"` — is what this used to send,
 * and it made delivery depend on what somebody had called their task. A
 * title like "PO_2026_44" or "Invoice *final*" leaves the markup unbalanced,
 * Telegram answers 400 "can't parse entities", and a 400 is not retryable:
 * the reminder was marked failed and nobody was ever told about that task.
 * Markdown has no escape rule that survives arbitrary text; HTML has one,
 * and it is this function.
 */
function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

async function sendTelegram(reminder: QueuedReminder): Promise<DeliveryResult> {
  const token = process.env.TELEGRAM_BOT_TOKEN;

  if (!token) {
    return {
      ok: false,
      error: "Telegram is not configured (TELEGRAM_BOT_TOKEN).",
      retryable: false,
    };
  }

  const response = await fetch(
    `https://api.telegram.org/bot${token}/sendMessage`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: reminder.recipient,
        text: `<b>${escapeHtml(reminder.subject ?? APP_NAME)}</b>\n${escapeHtml(
          `${reminder.body}${appLink()}`,
        )}`,
        parse_mode: "HTML",
        disable_web_page_preview: true,
      }),
    },
  );

  const payload = (await response.json().catch(() => null)) as {
    ok?: boolean;
    description?: string;
  } | null;

  if (response.ok && payload?.ok) return { ok: true };

  const description = payload?.description ?? `HTTP ${response.status}`;
  return {
    ok: false,
    error: `Telegram: ${description}`.slice(0, 200),
    // "bot was blocked" / "chat not found" will never succeed on retry.
    retryable:
      response.status === 429 ||
      (response.status >= 500 && !/blocked|not found|deactivated/i.test(description)),
  };
}

// ---------------------------------------------------------------------------
// WhatsApp — Twilio
//
// Outside the 24-hour customer service window Meta only permits pre-approved
// template messages, so a plain body will be rejected until the recipient has
// messaged the number. See the README for what that means in practice.
// ---------------------------------------------------------------------------

async function sendWhatsApp(reminder: QueuedReminder): Promise<DeliveryResult> {
  const sid = process.env.TWILIO_ACCOUNT_SID;
  const token = process.env.TWILIO_AUTH_TOKEN;
  const from = process.env.TWILIO_WHATSAPP_FROM;

  if (!sid || !token || !from) {
    return {
      ok: false,
      error:
        "WhatsApp is not configured (TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN / TWILIO_WHATSAPP_FROM).",
      retryable: false,
    };
  }

  const contentSid = process.env.TWILIO_WHATSAPP_TEMPLATE_SID;

  const form = new URLSearchParams({
    From: `whatsapp:${from}`,
    To: `whatsapp:${reminder.recipient}`,
  });

  if (contentSid) {
    // Approved template: the body is passed as a variable rather than free text.
    form.set("ContentSid", contentSid);
    form.set(
      "ContentVariables",
      JSON.stringify({ 1: reminder.subject ?? APP_NAME, 2: reminder.body }),
    );
  } else {
    form.set("Body", `${reminder.subject ?? APP_NAME}\n${reminder.body}${appLink()}`);
  }

  const response = await fetch(
    `https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`,
    {
      method: "POST",
      headers: {
        Authorization: `Basic ${Buffer.from(`${sid}:${token}`).toString("base64")}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: form,
    },
  );

  if (response.ok) return { ok: true };

  const detail = await response.text().catch(() => "");
  return {
    ok: false,
    error: `Twilio ${response.status}: ${detail.slice(0, 200)}`,
    retryable: response.status === 429 || response.status >= 500,
  };
}

// ---------------------------------------------------------------------------

/**
 * A push to one device.
 *
 * The recipient here is not an address a person reads — it is the endpoint
 * the browser handed over when they agreed, and the payload is encrypted to
 * keys only that browser holds. The push service forwards an opaque blob and
 * cannot read it.
 *
 * 404 and 410 are the push service saying this device is gone: unsubscribed,
 * app deleted, browser data cleared. That is not a failure to retry, it is a
 * row to remove, which the dispatcher does on `gone`.
 */
async function sendPush(reminder: QueuedReminder): Promise<DeliveryResult> {
  const keys = await vapidKeys();
  if (!keys) {
    return { ok: false, error: "No push keys.", retryable: false };
  }
  // The keys belong to the device, not to the message, so they are looked up
  // rather than copied into every queued row. A row whose device has since
  // been removed is gone, not broken.
  const supabase = createAdminClient();
  const device = await supabase
    .from("push_subscriptions")
    .select("p256dh, auth")
    .eq("endpoint", reminder.recipient)
    .maybeSingle();

  if (!device.data) {
    return { ok: false, error: "gone", retryable: false, gone: true };
  }

  webpush.setVapidDetails(pushSubject(), keys.publicKey, keys.privateKey);

  try {
    await webpush.sendNotification(
      {
        endpoint: reminder.recipient,
        keys: { p256dh: device.data.p256dh, auth: device.data.auth },
      },
      JSON.stringify({
        title: reminder.subject ?? "Almailgroup",
        body: reminder.body,
        // Straight to the thing it is about, or to the day's work.
        url: reminder.task_id ? `/tasks?filter=all&task=${reminder.task_id}` : "/today",
        // One line per task in the shade rather than four.
        tag: reminder.task_id ?? "almail",
      }),
      { TTL: 60 * 60 * 12 },
    );
    return { ok: true };
  } catch (error) {
    const status = (error as { statusCode?: number }).statusCode;
    if (status === 404 || status === 410) {
      return { ok: false, error: "gone", retryable: false, gone: true };
    }
    return {
      ok: false,
      error: `Push ${status ?? "?"}: ${
        error instanceof Error ? error.message.slice(0, 160) : "failed"
      }`,
      retryable: status === undefined || status === 429 || status >= 500,
    };
  }
}

export async function deliver(reminder: QueuedReminder): Promise<DeliveryResult> {
  try {
    switch (reminder.channel) {
      case "email":
        return await sendEmail(reminder);
      case "telegram":
        return await sendTelegram(reminder);
      case "whatsapp":
        return await sendWhatsApp(reminder);
      case "push":
        return await sendPush(reminder);
      default:
        return { ok: false, error: "Unknown channel.", retryable: false };
    }
  } catch (error) {
    // A network-level throw is transient by nature.
    return {
      ok: false,
      error: error instanceof Error ? error.message.slice(0, 200) : "Send failed",
      retryable: true,
    };
  }
}

/** Which channels have credentials present. Surfaced in the preferences UI. */
export function configuredChannels() {
  return {
    email: Boolean(process.env.RESEND_API_KEY && process.env.REMINDER_EMAIL_FROM),
    telegram: Boolean(process.env.TELEGRAM_BOT_TOKEN),
    whatsapp: Boolean(
      process.env.TWILIO_ACCOUNT_SID &&
        process.env.TWILIO_AUTH_TOKEN &&
        process.env.TWILIO_WHATSAPP_FROM,
    ),
    // Nothing to configure: the keys are generated on first use and kept in
    // the database, so this channel is available wherever the app runs.
    push: true,
  };
}
