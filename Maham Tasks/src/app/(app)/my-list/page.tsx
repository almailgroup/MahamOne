import type { Metadata } from "next";

import { MyList } from "@/components/notes/my-list";
import { getMyNotes, getTeam, requireProfile } from "@/lib/data/queries";
import { getI18n } from "@/lib/i18n/server";

export async function generateMetadata(): Promise<Metadata> {
  const { t } = await getI18n();
  return { title: t("nav.myList") };
}

/**
 * A private daily list. Deliberately outside PageShell: the Notes-style
 * master/detail fills the viewport and manages its own scrolling, rather than
 * sitting in the centred column the task pages use.
 */
export default async function MyListPage() {
  const [profile, notes, team] = await Promise.all([
    requireProfile(),
    getMyNotes(),
    getTeam(),
  ]);

  return <MyList initialNotes={notes} profile={profile} team={team} />;
}
