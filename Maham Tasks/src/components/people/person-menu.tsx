"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { Loader2, Mail, MessageSquare, Copy, User } from "lucide-react";
import { toast } from "sonner";

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { PersonProfileDialog } from "@/components/people/person-profile-dialog";
import { startConversation } from "@/lib/data/dm-actions";
import { useI18n } from "@/lib/i18n/client";
import type { Profile } from "@/lib/supabase/database.types";

/**
 * What clicking on a person does, anywhere a person appears.
 *
 * A name and a face read as something you can act on, and until now almost
 * none of them were: the team list, the room's roster and the workload card
 * were all text you could click at without result. One menu behind all of
 * them, so the answer is the same wherever you found the person.
 *
 * `children` is the trigger — a whole row, an avatar, a name — so a caller
 * decides what the target is rather than having a button bolted beside it.
 */
export function PersonMenu({
  person,
  me,
  align = "start",
  extra,
  children,
}: {
  person: Profile;
  /** Who is looking, so the menu does not offer to message themselves. */
  me: Profile;
  align?: "start" | "end" | "center";
  /** Items belonging to the surface this menu was opened from. */
  extra?: React.ReactNode;
  children: React.ReactNode;
}) {
  const router = useRouter();
  const { t, tm } = useI18n();
  const [profileOpen, setProfileOpen] = React.useState(false);
  const [opening, setOpening] = React.useState(false);

  const name = person.full_name ?? person.email;
  const isMe = person.id === me.id;

  async function message() {
    if (opening) return;
    setOpening(true);
    const outcome = await startConversation(person.id);
    setOpening(false);

    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }
    router.push(`/messages/${outcome.data}`);
    router.refresh();
  }

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild aria-label={t("person.open", { name })}>
          {children}
        </DropdownMenuTrigger>
        <DropdownMenuContent align={align} className="w-56">
          <DropdownMenuItem onSelect={() => setProfileOpen(true)}>
            <User />
            {t("person.viewProfile")}
          </DropdownMenuItem>

          {/* Messaging yourself is not a conversation, and the database
              refuses it anyway — better not to offer it. */}
          {!isMe && (
            <DropdownMenuItem onSelect={() => void message()} disabled={opening}>
              {opening ? <Loader2 className="animate-spin" /> : <MessageSquare />}
              {t("person.messagePrivately")}
            </DropdownMenuItem>
          )}

          <DropdownMenuSeparator />

          <DropdownMenuItem
            onSelect={() => {
              void navigator.clipboard
                ?.writeText(person.email)
                .then(() => toast.success(t("person.emailCopied")))
                .catch(() => {});
            }}
          >
            <Copy />
            {t("person.copyEmail")}
          </DropdownMenuItem>
          <DropdownMenuItem asChild>
            <a href={`mailto:${person.email}`}>
              <Mail />
              {t("person.emailThem")}
            </a>
          </DropdownMenuItem>

          {extra && (
            <>
              <DropdownMenuSeparator />
              {extra}
            </>
          )}
        </DropdownMenuContent>
      </DropdownMenu>

      <PersonProfileDialog
        person={person}
        me={me}
        open={profileOpen}
        onOpenChange={setProfileOpen}
        onMessage={message}
      />
    </>
  );
}
