import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { ChartColumn } from "lucide-react";

import { PageHeader, PageShell } from "@/components/layout/page-shell";
import { ReportView } from "@/components/reports/report-view";
import { getWorkReport, requireProfile } from "@/lib/data/queries";
import { getI18n } from "@/lib/i18n/server";
import { isReportPeriod, reportRange } from "@/lib/report";

export async function generateMetadata(): Promise<Metadata> {
  const { t } = await getI18n();
  return { title: t("reports.title") };
}

/**
 * How the work is going: what was finished and added, how much on time,
 * who has what open, and where each project stands.
 *
 * For admins and managers, who plan the work. Everything is counted over
 * what the person asking can see.
 */
export default async function ReportsPage({
  searchParams,
}: {
  searchParams: Promise<{ period?: string }>;
}) {
  const { t } = await getI18n();
  const { period } = await searchParams;
  const range = reportRange(isReportPeriod(period) ? period : "4w");

  const [profile, report] = await Promise.all([
    requireProfile(),
    getWorkReport(range.first, range.last, range.grain),
  ]);
  if (profile.role === "member") redirect("/dashboard");

  return (
    <PageShell>
      <PageHeader title={t("reports.title")} icon={<ChartColumn />} description={t("reports.description")} />
      <ReportView report={report} range={range} />
    </PageShell>
  );
}
