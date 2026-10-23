"use client";

import * as React from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { MessagesSquare, Plus } from "lucide-react";

import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/empty-state";
import { compactAge } from "@/lib/dates";
import { initialsFrom } from "@/lib/initials";
import { useI18n } from "@/lib/i18n/client";
import { useNow } from "@/lib/use-now";
import { cn } from "@/lib/utils";
import type { ConversationSummary, Profile } from "@/lib/supabase/database.types";

/**
 * Every private thread, most recent first.
 *
 * The unread count is the only thing here that is not simply a list: it is
 * what tells somebody a message arrived while they were on another page, and
 * it is per-thread because "you have messages" without saying from whom is a
 * worse answer than none.
 */
export function ConversationList({
  conversations,
  me,
  onNew,
}: {
  conversations: ConversationSummary[];
  me: Profile;
  onNew: () => void;
}) {
  const i18n = useI18n();
  const { t, tn } = i18n;
  const params = useParams<{ conversationId?: string }>();
  const active = params?.conversationId;
  const now = useNow();

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <header className="flex items-center justify-between gap-3 px-4 py-3">
        <h1 className="text-lg font-semibold tracking-tight">{t("dm.title")}</h1>
        <Button size="sm" onClick={onNew}>
          <Plus />
          {t("dm.new")}
        </Button>
      </header>

      {conversations.length === 0 ? (
        <div className="p-3">
          <EmptyState
            compact
            icon={<MessagesSquare />}
            title={t("dm.noConversations")}
            description={t("dm.startOne")}
            action={
              <Button size="sm" onClick={onNew}>
                <Plus />
                {t("dm.new")}
              </Button>
            }
          />
        </div>
      ) : (
        <ul className="stagger scrollbar-thin flex min-h-0 flex-1 flex-col gap-1 overflow-y-auto px-2 pb-2">
          {conversations.map((conversation) => {
            const name =
              conversation.other?.full_name ?? conversation.other?.email ?? "—";
            const mine = conversation.lastAuthorId === me.id;

            return (
              <li key={conversation.id}>
                <Link
                  href={`/messages/${conversation.id}`}
                  className={cn(
                    "chrome-touch flex items-center gap-3 rounded-2xl px-3 py-3 transition-colors",
                    "hover:bg-foreground/[0.05]",
                    conversation.id === active && "bg-primary/[0.09] shadow-[var(--shadow-xs)]",
                  )}
                >
                  <Avatar className="size-9 shrink-0">
                    <AvatarImage
                      src={conversation.other?.avatar_url ?? undefined}
                      alt=""
                    />
                    <AvatarFallback className="text-xs">
                      {initialsFrom(
                        conversation.other?.full_name,
                        conversation.other?.email,
                      )}
                    </AvatarFallback>
                  </Avatar>

                  <span className="min-w-0 flex-1">
                    <span className="flex items-baseline gap-2">
                      <span className="min-w-0 flex-1 truncate text-sm font-medium">
                        {name}
                      </span>
                      <span className="shrink-0 text-[0.6875rem] tabular-nums text-muted-foreground">
                        {now === null
                          ? ""
                          : compactAge(conversation.lastMessageAt, now, i18n)}
                      </span>
                    </span>
                    <span
                      className={cn(
                        "mt-0.5 block truncate text-xs",
                        conversation.unread > 0
                          ? "font-medium text-foreground"
                          : "text-muted-foreground",
                      )}
                    >
                      {conversation.lastMessage
                        ? `${mine ? `${t("dm.you")}: ` : ""}${conversation.lastMessage}`
                        : t("dm.draft")}
                    </span>
                  </span>

                  {conversation.unread > 0 && (
                    <span
                      className="flex size-5 shrink-0 items-center justify-center rounded-full bg-primary text-[0.625rem] font-semibold tabular-nums text-primary-foreground"
                      aria-label={tn("dm.unread", conversation.unread)}
                    >
                      {conversation.unread > 9 ? "9+" : conversation.unread}
                    </span>
                  )}
                </Link>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
