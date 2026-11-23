import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { Settings } from "lucide-react";

import { PageHeader, PageShell } from "@/components/layout/page-shell";
import { HolidaySettings } from "@/components/settings/holiday-settings";
import { LabelSettings } from "@/components/settings/label-settings";
import { TemplateSettings } from "@/components/settings/template-settings";
import { listTemplates } from "@/lib/data/template-actions";
import { getHolidays, getLabels, requireProfile } from "@/lib/data/queries";
import { getI18n } from "@/lib/i18n/server";

export async function generateMetadata(): Promise<Metadata> {
  const { t } = await getI18n();
  return { title: t("settings.title") };
}

/**
 * Workspace settings: the things that are the same for everybody.
 *
 * For admins and managers. Each section says what it is and who may change
 * it; row-level security is what actually decides.
 */
export default async function SettingsPage() {
  const { t } = await getI18n();
  const [profile, holidays, labels, templates] = await Promise.all([
    requireProfile(),
    getHolidays(),
    getLabels(),
    listTemplates(),
  ]);
  if (profile.role === "member") redirect("/dashboard");

  return (
    <PageShell width="narrow">
      <PageHeader
        title={t("settings.title")}
        icon={<Settings />}
        description={t("settings.description")}
      />
      <div className="stagger flex flex-col gap-4">
        <HolidaySettings holidays={holidays} canEdit={profile.role === "admin"} />
        <LabelSettings labels={labels} />
        <TemplateSettings templates={templates} />
      </div>
    </PageShell>
  );
}
