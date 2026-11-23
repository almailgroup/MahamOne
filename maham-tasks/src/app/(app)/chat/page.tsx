import type { Metadata } from "next";
import { MessagesSquare } from "lucide-react";

import { PageHeader, PageShell } from "@/components/layout/page-shell";
import { TeamChat } from "@/components/chat/team-chat";
import { getI18n } from "@/lib/i18n/server";
import { getTeam, getTeamMessages, requireProfile } from "@/lib/data/queries";
import { cn } from "@/lib/utils";

export async function generateMetadata(): Promise<Metadata> {
  const { t } = await getI18n();
  return { title: t("nav.chat") };
}

export default async function ChatPage() {
  const { t } = await getI18n();
  const [profile, team, messages] = await Promise.all([
    requireProfile(),
    getTeam(),
    getTeamMessages(),
  ]);

  return (
    <PageShell
      /* The room is exactly as tall as the screen leaves it, so the composer
         stays put and the messages are the only thing that scrolls. What is
         subtracted is what the shell itself puts around the page — the header
         at the top, and below `lg` the navigation bar and the home indicator
         at the bottom. Everything inside is flexbox's arithmetic rather than a
         guess at how tall a wrapped heading turns out to be. */
      className={cn(
        "h-[calc(100svh-3.5rem-var(--nav-space)-var(--safe-top)-var(--safe-bottom))]",
        "lg:h-[calc(100svh-3.5rem-var(--panel-gap))]",
      )}
    >
      <PageHeader
        title={t("nav.chat")}
        description={t("chat.subtitle")}
        icon={<MessagesSquare />}
      />
      <TeamChat profile={profile} team={team} initial={messages} />
    </PageShell>
  );
}
