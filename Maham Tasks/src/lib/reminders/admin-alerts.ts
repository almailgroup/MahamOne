import "server-only";

import type { createAdminClient } from "@/lib/supabase/admin";
import { isMissingFunction } from "@/lib/supabase/missing";
import { COMPANY_TIME_ZONE } from "@/lib/work-week";

/**
 * A note to the admins on Telegram when something has gone wrong: how many
 * faults, on which pages, and how many reminders could not be delivered,
 * since the last note — with a link to the details in the portal.
 *
 * Sent from the scheduled run, with the service key, so it keeps office
 * hours like everything else that reaches a person. Counts and page paths
 * only: a fault's own text can carry a fragment of what it failed on, and
 * stays in the portal (admin_alert_digest, migration 45).
 */

type Admin = ReturnType<typeof createAdminClient>;

export type AlertDigest = {
  since: string;
  faults: number;
  pages: { source: "browser" | "server"; page: string; count: number }[];
  failedReminders: number;
  recipients: string[];
};

function plural(n: number, one: string, many: string) {
  return `${n} ${n === 1 ? one : many}`;
}

/** The note, in English then Arabic, or null when there is nothing new. */
export function alertText(digest: AlertDigest, site: string): string | null {
  if (digest.faults === 0 && digest.failedReminders === 0) return null;

  const since = new Date(digest.since).toLocaleString("en-GB", {
    timeZone: COMPANY_TIME_ZONE,
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
  });

  const english = [`Maham Tasks — something needs a look (since ${since}).`];
  const arabic = ["مهام تاسكس — هناك ما يحتاج إلى نظرة."];

  if (digest.faults > 0) {
    english.push(`${plural(digest.faults, "fault", "faults")}:`);
    for (const { page, count, source } of digest.pages) {
      english.push(`• ${page} — ${count} ${source === "server" ? "on the server" : "in the browser"}`);
    }
    arabic.push(`أعطال: ${digest.faults}`);
  }
  if (digest.failedReminders > 0) {
    english.push(
      `${plural(digest.failedReminders, "reminder", "reminders")} could not be delivered.`,
    );
    arabic.push(`تذكيرات تعذّر إيصالها: ${digest.failedReminders}`);
  }

  const link = site ? `\n\n${site}/profile#reminders` : "";
  return `${english.join("\n")}\n\n${arabic.join("\n")}${link}`;
}

/**
 * Tell the admins, if there is anything to tell and anyone to tell it to.
 * Returns how many were reached; a note is only recorded as sent when it
 * reached somebody, so one that could not go is tried again next run.
 */
export async function alertAdmins(supabase: Admin, now: Date = new Date()): Promise<number> {
  const token = process.env.TELEGRAM_BOT_TOKEN;
  if (!token) return 0;

  const { data, error } = await supabase.rpc("admin_alert_digest", { as_of: now.toISOString() });
  if (error) {
    // Before migration 45 there is no such function; that is not news.
    if (!isMissingFunction(error)) console.error(`[alerts] admin_alert_digest: ${error.message}`);
    return 0;
  }

  const digest = data as AlertDigest | null;
  if (!digest || digest.recipients.length === 0) return 0;
  const text = alertText(digest, process.env.NEXT_PUBLIC_SITE_URL ?? "");
  if (!text) return 0;

  const results = await Promise.all(
    digest.recipients.map(async (chat) => {
      try {
        const response = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ chat_id: chat, text, disable_web_page_preview: true }),
        });
        return response.ok;
      } catch {
        return false;
      }
    }),
  );
  const reached = results.filter(Boolean).length;

  if (reached > 0) {
    const { error: recordError } = await supabase.from("admin_alerts").insert({
      sent_at: now.toISOString(),
      faults: digest.faults,
      failures: digest.failedReminders,
      reached,
    });
    if (recordError) console.error(`[alerts] admin_alerts: ${recordError.message}`);
  }
  return reached;
}
