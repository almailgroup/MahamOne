"use client";

import * as React from "react";
import { useRouter, useSelectedLayoutSegment } from "next/navigation";
import { Search } from "lucide-react";
import { toast } from "sonner";

import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { ConversationList } from "@/components/messages/conversation-list";
import { startConversation } from "@/lib/data/dm-actions";
import { initialsFrom } from "@/lib/initials";
import { useI18n } from "@/lib/i18n/client";
import { cn } from "@/lib/utils";
import type { ConversationSummary, Profile } from "@/lib/supabase/database.types";

/**
 * Two panes from `lg`, one screen at a time below it.
 *
 * Which of the two a phone shows is decided by the route rather than by
 * state: `/messages` is the list, `/messages/<id>` is the thread. That is
 * what makes the back button, and the link in a notification, land where
 * somebody expects.
 */
export function MessagesShell({
  conversations,
  team,
  profile,
  children,
}: {
  conversations: ConversationSummary[];
  team: Profile[];
  profile: Profile;
  children: React.ReactNode;
}) {
  const segment = useSelectedLayoutSegment();
  const openThread = segment !== null && segment !== "__DEFAULT__";
  const [picking, setPicking] = React.useState(false);

  return (
    <div
      className={cn(
        "flex flex-col lg:flex-row",
        // What the shell leaves: the header, and on a phone the navigation
        // bar and the home indicator under it.
        "h-[calc(100svh-3.5rem-var(--nav-space)-var(--safe-top)-var(--safe-bottom))]",
        "lg:h-[calc(100svh-3.5rem-var(--panel-gap))]",
      )}
    >
      <section
        className={cn(
          "flex min-h-0 flex-col lg:w-80 lg:shrink-0 xl:w-96",
          openThread ? "hidden lg:flex" : "flex",
        )}
      >
        <ConversationList
          conversations={conversations}
          me={profile}
          onNew={() => setPicking(true)}
        />
      </section>

      <section
        className={cn(
          "min-h-0 flex-1 flex-col",
          openThread ? "flex" : "hidden lg:flex",
        )}
      >
        {children}
      </section>

      <PeoplePicker
        open={picking}
        onOpenChange={setPicking}
        team={team}
        me={profile}
      />
    </div>
  );
}

/**
 * Who to write to.
 *
 * Opening a conversation goes through the database function rather than an
 * insert here, so picking somebody you already have a thread with lands in
 * that thread instead of making a second one.
 */
function PeoplePicker({
  open,
  onOpenChange,
  team,
  me,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  team: Profile[];
  me: Profile;
}) {
  const { t, tm } = useI18n();
  const router = useRouter();
  const [query, setQuery] = React.useState("");
  const [opening, setOpening] = React.useState<string | null>(null);

  const people = React.useMemo(() => {
    const needle = query.trim().toLowerCase();
    return team
      .filter((person) => person.id !== me.id)
      .filter(
        (person) =>
          !needle ||
          (person.full_name ?? "").toLowerCase().includes(needle) ||
          person.email.toLowerCase().includes(needle) ||
          (person.job_title ?? "").toLowerCase().includes(needle),
      )
      .sort((a, b) =>
        (a.full_name ?? a.email).localeCompare(b.full_name ?? b.email),
      );
  }, [team, me.id, query]);

  async function pick(person: Profile) {
    if (opening) return;
    setOpening(person.id);
    const outcome = await startConversation(person.id);
    setOpening(null);

    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }
    onOpenChange(false);
    setQuery("");
    router.push(`/messages/${outcome.data}`);
    router.refresh();
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-sm gap-3">
        <DialogHeader>
          <DialogTitle>{t("dm.pickSomeone")}</DialogTitle>
          <DialogDescription>{t("dm.subtitle")}</DialogDescription>
        </DialogHeader>

        <div className="relative">
          <Search className="pointer-events-none absolute start-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder={t("dm.searchPeople")}
            aria-label={t("dm.searchPeople")}
            className="ps-9"
          />
        </div>

        {people.length === 0 ? (
          <p className="px-1 py-3 text-sm text-muted-foreground">
            {t("dm.noPeople")}
          </p>
        ) : (
          <ul className="scrollbar-thin -mx-1 flex max-h-72 flex-col gap-0.5 overflow-y-auto px-1">
            {people.map((person) => (
              <li key={person.id}>
                <button
                  type="button"
                  onClick={() => pick(person)}
                  disabled={opening !== null}
                  className={cn(
                    "flex w-full items-center gap-2.5 rounded-lg px-2 py-2 text-start transition-colors",
                    "hover:bg-accent disabled:opacity-50",
                    "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
                    "pointer-coarse:min-h-11",
                  )}
                >
                  <Avatar className="size-8 shrink-0">
                    <AvatarImage src={person.avatar_url ?? undefined} alt="" />
                    <AvatarFallback className="text-[0.625rem]">
                      {initialsFrom(person.full_name, person.email)}
                    </AvatarFallback>
                  </Avatar>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-sm font-medium leading-tight">
                      {person.full_name ?? person.email}
                    </span>
                    <span className="block truncate text-xs leading-tight text-muted-foreground">
                      {person.job_title ?? person.email}
                    </span>
                  </span>
                </button>
              </li>
            ))}
          </ul>
        )}
      </DialogContent>
    </Dialog>
  );
}
