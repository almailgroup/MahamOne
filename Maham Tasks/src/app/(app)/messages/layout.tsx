import type { Metadata } from "next";

import { MessagesShell } from "@/components/messages/messages-shell";
import { getConversations, getTeam, requireProfile } from "@/lib/data/queries";
import { getI18n } from "@/lib/i18n/server";

export async function generateMetadata(): Promise<Metadata> {
  const { t } = await getI18n();
  return { title: t("dm.title") };
}

/**
 * The conversation list stays; the thread beside it swaps.
 *
 * A layout rather than one page holding both, so navigating between threads
 * does not re-fetch the list, and so a link straight to `/messages/<id>` —
 * which is what a notification is — arrives with the list already there.
 */
export default async function MessagesLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const [profile, conversations, team] = await Promise.all([
    requireProfile(),
    getConversations(),
    getTeam(),
  ]);

  return (
    <MessagesShell conversations={conversations} team={team} profile={profile}>
      {children}
    </MessagesShell>
  );
}
