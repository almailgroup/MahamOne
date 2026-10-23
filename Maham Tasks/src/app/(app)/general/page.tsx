import type { Metadata } from "next";

import { GeneralTasks } from "@/components/tasks/general-tasks";
import {
  getFollowUps,
  getGeneralTasks,
  getTeam,
  requireProfile,
} from "@/lib/data/queries";
import { getI18n } from "@/lib/i18n/server";

export async function generateMetadata(): Promise<Metadata> {
  const { t } = await getI18n();
  return { title: t("nav.general") };
}

export default async function GeneralTasksPage() {
  const [profile, tasks, followUps, team] = await Promise.all([
    requireProfile(),
    getGeneralTasks(),
    getFollowUps({ generalOnly: true }),
    getTeam(),
  ]);

  return (
    <GeneralTasks
      tasks={tasks}
      followUps={followUps}
      team={team}
      profile={profile}
    />
  );
}
