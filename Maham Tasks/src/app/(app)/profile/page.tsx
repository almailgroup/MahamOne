import type { Metadata } from "next";

import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { UserCog } from "lucide-react";

import { PageHeader, PageShell } from "@/components/layout/page-shell";
import { ChangePassword } from "@/components/profile/change-password";
import { ProfileForm } from "@/components/profile/profile-form";
import { DeliveryFailures } from "@/components/profile/delivery-failures";
import { ErrorLog } from "@/components/profile/error-log";
import { PushDevices } from "@/components/profile/push-devices";
import { ReminderSettings } from "@/components/profile/reminder-settings";
import { TwoStepSettings } from "@/components/profile/two-step-settings";
import { roleMeta } from "@/lib/constants";
import { getI18n } from "@/lib/i18n/server";
import {
  getMyReminderFailures,
  getNotificationPreferences,
  getPushDevices,
  getRecentErrors,
  getTeamReminderFailures,
  requireProfile,
} from "@/lib/data/queries";
import { publicPushKey } from "@/lib/push/keys";
import { configuredChannels } from "@/lib/reminders/providers";

export async function generateMetadata(): Promise<Metadata> {
  const { t } = await getI18n();
  return { title: t("shell.profile") };
}

export default async function ProfilePage() {
  const { t } = await getI18n();
  const [profile, preferences, devices, mineFailed, pushKey] = await Promise.all([
    requireProfile(),
    getNotificationPreferences(),
    getPushDevices(),
    getMyReminderFailures(),
    // Null when there is no service-role key to reach the table with. The UI
    // then says push is unavailable rather than offering a switch that
    // cannot work.
    publicPushKey().catch(() => null),
  ]);
  const role = roleMeta(profile.role);

  // Read on the server: which channels actually have credentials. The UI shows
  // the rest disabled with the reason, rather than silently doing nothing.
  const available = configuredChannels();
  const botUsername = process.env.TELEGRAM_BOT_USERNAME ?? null;

  return (
    <PageShell width="narrow">
      <PageHeader
        title={t("shell.profile")}
        icon={<UserCog />}
        description={t("profile.description")}
        actions={
          <>
            {profile.job_title && (
              <Badge variant="secondary">{profile.job_title}</Badge>
            )}
            <Badge variant="outline">{t(role.label)}</Badge>
          </>
        }
      />

      <Card>
        <CardContent className="pt-4">
          <ProfileForm profile={profile} />
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t("auth.password")}</CardTitle>
        </CardHeader>
        <CardContent>
          <ChangePassword />
        </CardContent>
      </Card>

      <Card id="two-step" className="scroll-mt-24">
        <CardHeader>
          <CardTitle role="heading" aria-level={2}>{t("twoStep.title")}</CardTitle>
        </CardHeader>
        <CardContent>
          <TwoStepSettings isAdmin={profile.role === "admin"} />
        </CardContent>
      </Card>

      {preferences && (
        <Card id="reminders" className="scroll-mt-24">
          <CardHeader>
            <CardTitle>{t("profile.reminders")}</CardTitle>
          </CardHeader>
          <CardContent>
            <ReminderSettings
              preferences={preferences}
              email={profile.email}
              available={available}
              botUsername={botUsername}
              devices={<PushDevices devices={devices} publicKey={pushKey} />}
              failures={
                <>
                  {/* Admin only, and the function refuses anybody else
                      outright rather than returning an empty list. */}
                  {profile.role === "admin" && <ErrorLog errors={await getRecentErrors()} />}
                  <DeliveryFailures
                    mine={mineFailed}
                  // Only an admin is shown the team's; the function refuses
                  // anybody else outright rather than returning nothing.
                    team={profile.role === "admin" ? await getTeamReminderFailures() : []}
                  />
                </>
              }
            />
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader>
          <CardTitle>{t("profile.access")}</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-2 text-sm text-muted-foreground">
          <p>{t(role.description)}</p>
          <p>
            <span className="font-medium text-foreground">{t("position.label")}:</span>{" "}
            {profile.job_title ?? t("profile.notSet")}
          </p>
          <p>{t("profile.assignedByAdmin")}</p>
        </CardContent>
      </Card>
    </PageShell>
  );
}
