import { AlertTriangle } from "lucide-react";

import { getI18n } from "@/lib/i18n/server";
import type { TranslationKey } from "@/lib/i18n";
import { formatDateTime } from "@/lib/dates";
import type {
  ReminderFailure,
  TeamReminderFailure,
} from "@/lib/supabase/database.types";

/**
 * Reminders that could not be delivered.
 *
 * A reminder that exhausted its attempts used to be marked failed in a table
 * nobody reads, while somebody waited to hear about work they never heard
 * about. The symptom was the portal seeming not to bother.
 *
 * Shown beside the channels themselves, because that is where the fix is: a
 * wrong number, a bot nobody started, a notification permission somebody
 * revoked. The channel is named for the same reason.
 *
 * Amber is right here, and is the one thing in this app it is reserved for
 * besides late work — this is the same kind of statement: something needed
 * attention and did not get it.
 */
/**
 * What each channel is called, reusing the labels the settings above use —
 * email has no key of its own there either, it is simply "Email".
 */
const CHANNEL: Record<string, TranslationKey> = {
  email: "auth.email",
  telegram: "remind.telegram",
  whatsapp: "remind.whatsapp",
  push: "remind.push",
};

export async function DeliveryFailures({
  mine,
  team,
}: {
  mine: ReminderFailure[];
  team: TeamReminderFailure[];
}) {
  const { t, tag, timeZone } = await getI18n();
  if (mine.length === 0 && team.length === 0) return null;

  return (
    <div className="flex flex-col gap-3 rounded-lg border border-warning-border bg-warning-surface p-3">
      <div className="flex items-start gap-3">
        <span className="mt-0.5 text-warning [&_svg]:size-4">
          <AlertTriangle />
        </span>
        <div className="flex min-w-0 flex-1 flex-col gap-2">
          <div>
            <p className="text-sm font-medium text-warning">{t("delivery.title")}</p>
            <p className="text-xs text-warning/80">{t("delivery.subtitle")}</p>
          </div>

          {mine.length > 0 && (
            <ul className="flex flex-col gap-1">
              {mine.map((failure, index) => (
                <li
                  key={`${failure.channel}-${failure.failed_at}-${index}`}
                  className="text-xs text-warning"
                >
                  <span className="font-medium">{t(CHANNEL[failure.channel])}</span>
                  {" · "}
                  {formatDateTime(failure.failed_at, tag, timeZone)}
                  {failure.last_error && (
                    <span className="text-warning/80"> — {failure.last_error}</span>
                  )}
                </li>
              ))}
            </ul>
          )}

          {team.length > 0 && (
            <div className="flex flex-col gap-1">
              <p className="text-xs font-medium text-warning">{t("delivery.acrossTeam")}</p>
              <ul className="flex flex-col gap-1">
                {team.slice(0, 8).map((failure, index) => (
                  <li
                    key={`${failure.user_id}-${failure.failed_at}-${index}`}
                    className="text-xs text-warning"
                  >
                    <span className="font-medium">{failure.person}</span>
                    {" · "}
                    {t(CHANNEL[failure.channel])}
                    {" · "}
                    {formatDateTime(failure.failed_at, tag, timeZone)}
                  </li>
                ))}
              </ul>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
