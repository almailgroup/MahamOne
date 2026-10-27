import type { Metadata } from "next";

import { TodayView } from "@/components/dashboard/today-view";
import {
  getDoneToday,
  getFollowUps,
  getOpenTasks,
  getProjects,
  getTeam,
  requireProfile,
} from "@/lib/data/queries";
import { getI18n, getTimeZone } from "@/lib/i18n/server";

export async function generateMetadata(): Promise<Metadata> {
  const { t } = await getI18n();
  return { title: t("nav.today") };
}

export default async function TodayPage() {
  // Today is made of four questions about work that is not done — overdue,
  // due today, in progress, waiting on review — and a fifth about work that
  // is: what got finished. Asking for open work rather than for everything
  // means the page cannot silently lose an old overdue task to a row cap it
  // never mentioned; the fifth question needs its own read, because the
  // bounded one deliberately leaves out every row it is about.
  const timeZone = await getTimeZone();
  const [profile, open, doneToday, followUps, projects, team] = await Promise.all([
    requireProfile(),
    getOpenTasks(),
    getDoneToday(timeZone),
    getFollowUps(),
    getProjects(),
    getTeam(),
  ]);

  return (
    <TodayView
      tasks={open.tasks}
      doneToday={doneToday}
      followUps={followUps}
      projects={projects}
      team={team}
      profile={profile}
    />
  );
}
