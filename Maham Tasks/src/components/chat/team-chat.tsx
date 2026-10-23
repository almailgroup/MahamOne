"use client";

import * as React from "react";
import { CornerDownLeft, Loader2, Trash2, Users } from "lucide-react";
import { toast } from "sonner";

import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Textarea } from "@/components/ui/textarea";
import { createClient } from "@/lib/supabase/client";
import { deleteTeamMessage, sendTeamMessage } from "@/lib/data/chat-actions";
import { DaySeparator } from "@/components/chat/day-separator";
import { PersonMenu } from "@/components/people/person-menu";
import { continues, startsNewDay } from "@/lib/chat/grouping";
import { formatTimeOfDay } from "@/lib/dates";
import { initialsFrom } from "@/lib/initials";
import { useI18n } from "@/lib/i18n/client";
import { cn } from "@/lib/utils";
import type {
  Profile,
  TeamMessage,
  TeamMessageWithAuthor,
} from "@/lib/supabase/database.types";

/** After this long without a keystroke somebody has stopped typing. */
const TYPING_IDLE_MS = 2500;

/** Close enough to the bottom that a new message should still follow you. */
const PINNED_PX = 80;

/** The longest a message can be, matching the column's own check constraint. */
const MAX_LENGTH = 4000;

/**
 * Layout effects run before paint, which is what stops a long history from
 * flashing at the top before it jumps to the bottom. On the server there is no
 * paint and React warns about the hook, so there it is an ordinary effect.
 */
const useBeforePaint =
  typeof window === "undefined" ? React.useEffect : React.useLayoutEffect;

/**
 * The team room.
 *
 * Server-rendered with the last hundred messages so it reads before any
 * JavaScript runs, then kept live over a realtime channel. Row-level security
 * applies to what realtime forwards, so subscribing cannot show anything a
 * page load would have hidden.
 *
 * Who is here, and who is typing, both come from that channel's presence
 * rather than from the database. Neither is worth a row: they are true for a
 * few seconds and then they are not, and a table of them would be a table of
 * things that are already wrong.
 */
export function TeamChat({
  profile,
  team,
  initial,
}: {
  profile: Profile;
  team: Profile[];
  initial: TeamMessageWithAuthor[];
}) {
  const supabase = React.useMemo(() => createClient(), []);
  const { t, tn, tm, tag, timeZone } = useI18n();

  const [messages, setMessages] = React.useState(initial);
  const [draft, setDraft] = React.useState("");
  const [sending, setSending] = React.useState(false);
  const [rosterOpen, setRosterOpen] = React.useState(false);
  /** Who is connected, and which of them are mid-sentence. */
  const [here, setHere] = React.useState<Record<string, boolean>>({});

  const scrollerRef = React.useRef<HTMLDivElement>(null);
  const boxRef = React.useRef<HTMLTextAreaElement>(null);
  const channelRef = React.useRef<ReturnType<typeof supabase.channel> | null>(null);
  const idleRef = React.useRef<ReturnType<typeof setTimeout> | null>(null);
  const typingRef = React.useRef(false);
  /** Whether the reader is at the bottom and should be carried along. */
  const pinnedRef = React.useRef(true);

  const byId = React.useMemo(() => {
    const map = new Map<string, Profile>();
    for (const person of [...team, profile]) map.set(person.id, person);
    return map;
  }, [team, profile]);

  // Read by the realtime callbacks, which must not be a reason to tear the
  // channel down: `team` is a fresh array after every router.refresh(), and
  // resubscribing would drop this tab out of presence for a moment each time.
  const byIdRef = React.useRef(byId);
  React.useEffect(() => {
    byIdRef.current = byId;
  }, [byId]);

  React.useEffect(() => {
    const channel = supabase.channel("team-chat", {
      config: { presence: { key: profile.id } },
    });
    channelRef.current = channel;

    channel
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "team_messages" },
        (payload) => {
          const row = payload.new as TeamMessage;
          setMessages((current) =>
            current.some((message) => message.id === row.id)
              ? current
              : [
                  ...current,
                  { ...row, author: byIdRef.current.get(row.author_id) ?? null },
                ],
          );
        },
      )
      .on(
        "postgres_changes",
        { event: "DELETE", schema: "public", table: "team_messages" },
        (payload) => {
          const gone = payload.old as TeamMessage;
          setMessages((current) => current.filter((m) => m.id !== gone.id));
        },
      )
      .on("presence", { event: "sync" }, () => {
        const state = channel.presenceState<{ typing?: boolean }>();
        const next: Record<string, boolean> = {};
        for (const [id, entries] of Object.entries(state)) {
          // A person open in two tabs is here once, and is typing if either is.
          next[id] = entries.some((entry) => entry.typing === true);
        }
        setHere(next);
      })
      .subscribe(async (status) => {
        if (status === "SUBSCRIBED") await channel.track({ typing: false });
      });

    return () => {
      if (idleRef.current) clearTimeout(idleRef.current);
      channelRef.current = null;
      void supabase.removeChannel(channel);
    };
  }, [supabase, profile.id]);

  /** Say whether this person is mid-sentence, but only when it changes. */
  const announceTyping = React.useCallback((typing: boolean) => {
    if (typingRef.current === typing) return;
    typingRef.current = typing;
    void channelRef.current?.track({ typing });
  }, []);

  const onDraftChange = (value: string) => {
    setDraft(value);
    announceTyping(value.trim().length > 0);
    if (idleRef.current) clearTimeout(idleRef.current);
    // Stopping typing has no event of its own; it is only ever the absence of
    // one, so it has to be a timer.
    idleRef.current = setTimeout(() => announceTyping(false), TYPING_IDLE_MS);
  };

  // Grow the box with what is in it, up to the cap its own class sets.
  React.useEffect(() => {
    const box = boxRef.current;
    if (!box) return;
    box.style.height = "auto";
    box.style.height = `${box.scrollHeight}px`;
  }, [draft]);

  /**
   * Follow the conversation, unless the reader has gone back to look at
   * something. Nothing is more irritating in a chat than being dragged away
   * from what you were reading because somebody else said hello.
   */
  useBeforePaint(() => {
    const scroller = scrollerRef.current;
    if (!scroller || !pinnedRef.current) return;
    scroller.scrollTop = scroller.scrollHeight;
  }, [messages]);

  const onScroll = () => {
    const scroller = scrollerRef.current;
    if (!scroller) return;
    pinnedRef.current =
      scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight <
      PINNED_PX;
  };

  const send = async () => {
    const text = draft.trim();
    if (!text || sending) return;

    setSending(true);
    setDraft("");
    announceTyping(false);
    // Your own message always pulls you to the bottom; you just wrote it.
    pinnedRef.current = true;
    const outcome = await sendTeamMessage(text);
    setSending(false);

    if (!outcome.ok) {
      // Give them their words back rather than losing them to a failed send.
      setDraft(text);
      toast.error(tm(outcome.error));
    } else {
      const row = outcome.data;
      setMessages((current) =>
        current.some((message) => message.id === row.id)
          ? current
          : [...current, { ...row, author: profile }],
      );
    }
    boxRef.current?.focus();
  };

  const remove = async (id: string) => {
    const outcome = await deleteTeamMessage(id);
    if (!outcome.ok) toast.error(tm(outcome.error));
    else setMessages((current) => current.filter((m) => m.id !== id));
  };

  const typingNames = Object.entries(here)
    .filter(([id, typing]) => typing && id !== profile.id)
    .map(([id]) => firstName(byId.get(id)))
    .filter((name): name is string => Boolean(name));

  const left = MAX_LENGTH - draft.length;

  // Online first, then alphabetical: the column answers "who could see this
  // now", which the alphabet on its own never does.
  const people = React.useMemo(() => {
    const all = team.some((person) => person.id === profile.id)
      ? team
      : [...team, profile];
    return [...all].sort((a, b) => {
      const online = Number(b.id in here) - Number(a.id in here);
      if (online !== 0) return online;
      return (a.full_name ?? a.email).localeCompare(b.full_name ?? b.email);
    });
  }, [team, profile, here]);

  const onlineCount = people.filter((person) => person.id in here).length;

  return (
    <div className="flex min-h-0 flex-1 gap-4">
      <div className="flex min-w-0 flex-1 flex-col gap-2">
        {/* `log` is the role for a running transcript: a screen reader reads
            what arrives without being dragged to it, which is what `alert`
            or a bare live region would do on every message. */}
        <div
          ref={scrollerRef}
          onScroll={onScroll}
          role="log"
          aria-label={t("chat.transcript")}
          tabIndex={0}
          className="scrollbar-thin flex min-h-0 flex-1 flex-col overflow-y-auto rounded-3xl bg-card shadow-[var(--shadow-xs)] px-2 py-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background sm:px-3"
        >
          {messages.length === 0 ? (
            <p className="m-auto max-w-sm text-center text-sm leading-relaxed text-muted-foreground">
              {t("chat.empty")}
            </p>
          ) : (
            messages.map((message, index) => {
              const previous = messages[index - 1];
              const newDay = startsNewDay(previous, message, timeZone);
              return (
                <React.Fragment key={message.id}>
                  {newDay && <DaySeparator iso={message.created_at} />}
                  <Message
                    message={message}
                    me={profile}
                    mine={message.author_id === profile.id}
                    canRemove={
                      message.author_id === profile.id || profile.role === "admin"
                    }
                    grouped={!newDay && continues(previous, message)}
                    onRemove={() => remove(message.id)}
                    tag={tag}
                    timeZone={timeZone}
                  />
                </React.Fragment>
              );
            })
          )}
        </div>

        {/* Reserved height, so the composer does not jump up and down as
            people start and stop typing. */}
        <p
          aria-live="polite"
          className="flex h-4 items-center gap-1.5 px-2 text-xs text-muted-foreground"
        >
          {typingNames.length > 0 && (
            <>
              <TypingDots />
              {typingNames.length === 1
                ? t("chat.isTyping", { name: typingNames[0] })
                : typingNames.length === 2
                  ? t("chat.twoTyping", { a: typingNames[0], b: typingNames[1] })
                  : tn("chat.manyTyping", typingNames.length)}
            </>
          )}
        </p>

        <form
          onSubmit={(event) => {
            event.preventDefault();
            void send();
          }}
        >
          {/* One line, not a box with a toolbar under it.
              A message here is usually a sentence, and the field was three
              times taller than the sentence it was waiting for — the
              placeholder sat at the top of a large empty rectangle with the
              send button marooned in the far corner. Everything is on the same
              line now, and it grows downwards only when what is being written
              needs the room. `items-end` is what keeps the buttons at the foot
              of the field once it does. */}
          <div
            className={cn(
              "flex items-end gap-1 rounded-3xl bg-card p-1.5 shadow-[var(--shadow-xs)]",
              // Lit as one control when the caret is in it: a soft glow of the
              // theme's colour round the whole box, nothing inside it. A glow, not
              // a ring: these boxes hold the caret for long stretches (the
              // assistant focuses its own the moment it opens), and a ring read as
              // an outline round the box the whole time.
              "transition-shadow duration-200",
              "focus-within:shadow-[0_6px_24px_-6px_color-mix(in_oklab,var(--primary)_45%,transparent)]",
            )}
          >
            {/* The roster is a column of its own from `lg` up. Below that
                there is no room for two, so the same list opens over the
                conversation instead of squeezing it. */}
            <Button
              type="button"
              variant="ghost"
              size="icon-sm"
              className="shrink-0 lg:hidden"
              aria-label={t("chat.showMembers")}
              title={t("chat.showMembers")}
              onClick={() => setRosterOpen(true)}
            >
              <Users />
            </Button>

            <Textarea
              ref={boxRef}
              value={draft}
              onChange={(event) => onDraftChange(event.target.value)}
              onBlur={() => announceTyping(false)}
              onKeyDown={(event) => {
                if (event.key === "Enter" && !event.shiftKey) {
                  event.preventDefault();
                  void send();
                }
              }}
              placeholder={t("chat.placeholder")}
              rows={1}
              maxLength={MAX_LENGTH}
              className={cn(
                // 24px of line in 12px of padding is 36px, which is exactly
                // the height of the buttons beside it, so one line of text
                // sits on their centre line without being nudged there.
                "min-h-0 flex-1 resize-none overflow-y-auto rounded-none px-3 py-1.5 text-[0.9375rem] leading-6",
                // Bold, so a message being written is easy to read back.
                "font-semibold placeholder:font-semibold",
                "max-h-40 bg-transparent hover:bg-transparent focus-visible:bg-transparent",
                // The container carries the focus affordance. Without this the
                // global focus ring drew a second rounded box inside the first.
                "shadow-none focus-visible:shadow-none",
                "focus-visible:ring-0 focus-visible:ring-offset-0",
              )}
              aria-label={t("chat.placeholder")}
            />

            {/* Grouped, so the count is centred against the button rather than
                dropped to the foot of a field that has grown. */}
            <div className="flex shrink-0 items-center gap-1.5">
              {left <= 600 && (
                <span
                  className={cn(
                    "text-[0.6875rem] tabular-nums",
                    left <= 0 ? "text-warning" : "text-muted-foreground",
                  )}
                >
                  {left}
                </span>
              )}
              <Button
                type="submit"
                size="icon-sm"
                disabled={sending || !draft.trim()}
                aria-label={t("chat.send")}
              >
                {sending ? (
                  <Loader2 className="animate-spin" />
                ) : (
                  <CornerDownLeft className="rtl:-scale-x-100" />
                )}
              </Button>
            </div>
          </div>
        </form>
      </div>

      {/* On the trailing edge — the right in English, the left in Arabic,
          because that is the same side of the reading order rather than the
          same side of the screen. */}
      <aside
        aria-label={t("chat.members")}
        className="hidden w-60 shrink-0 flex-col rounded-3xl bg-card shadow-[var(--shadow-xs)] p-3 lg:flex"
      >
        <Roster people={people} me={profile} here={here} onlineCount={onlineCount} />
      </aside>

      <Dialog open={rosterOpen} onOpenChange={setRosterOpen}>
        <DialogContent className="max-w-sm gap-3">
          <DialogHeader>
            <DialogTitle className="flex items-baseline gap-2">
              {t("chat.members")}
              <span className="text-xs font-normal tabular-nums text-muted-foreground">
                {tn("chat.onlineCount", onlineCount)}
              </span>
            </DialogTitle>
          </DialogHeader>
          <Roster
            people={people}
            me={profile}
            here={here}
            onlineCount={onlineCount}
            heading={false}
          />
        </DialogContent>
      </Dialog>
    </div>
  );
}

/**
 * Who is in the room, online first.
 *
 * The point of the list is to answer "who could see this now", so presence
 * decides the order before the alphabet does. The ordering is worked out by
 * the room rather than here, because the dialog on a phone shows the same
 * list and the two must not disagree.
 */
function Roster({
  people,
  me,
  here,
  onlineCount,
  heading = true,
}: {
  people: Profile[];
  me: Profile;
  here: Record<string, boolean>;
  onlineCount: number;
  /** Off inside the dialog, which has a title of its own. */
  heading?: boolean;
}) {
  const { t, tn } = useI18n();

  return (
    <>
      {heading && (
        <div className="flex items-baseline justify-between px-1.5 pb-2">
          <span className="text-[0.6875rem] font-semibold uppercase tracking-wider text-muted-foreground">
            {t("chat.members")}
          </span>
          <span className="text-[0.6875rem] tabular-nums text-muted-foreground">
            {tn("chat.onlineCount", onlineCount)}
          </span>
        </div>
      )}

      <ul className="scrollbar-thin -mx-1 flex min-h-0 flex-1 flex-col gap-0.5 overflow-y-auto px-1">
        {people.map((person) => {
          const online = person.id in here;
          const typing = here[person.id] === true;
          const name = person.full_name ?? person.email;

          return (
            <li key={person.id}>
              {/* The roster is a list of people, so it answers the same way
                  every other list of people in the app now does. */}
              <PersonMenu person={person} me={me}>
                <button
                  type="button"
                  className="flex w-full items-center gap-2.5 rounded-lg px-1.5 py-1.5 text-start transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                >
                  <span className="relative shrink-0">
                    <Avatar className={cn("size-7", !online && "opacity-55")}>
                      <AvatarImage src={person.avatar_url ?? undefined} alt="" />
                      <AvatarFallback className="text-[0.625rem]">
                        {initialsFrom(person.full_name, person.email)}
                      </AvatarFallback>
                    </Avatar>
                    {/* Ringed in the card's own colour so the dot reads as
                        sitting on the avatar rather than behind it. Greyscale,
                        because in this palette the one colour means late work
                        and nothing else — being online is not an alarm. */}
                    <span
                      aria-hidden
                      className={cn(
                        "absolute -bottom-0.5 -end-0.5 size-2.5 rounded-full ring-2 ring-card",
                        online ? "bg-foreground" : "bg-muted-foreground/35",
                      )}
                    />
                  </span>

                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-[0.8125rem] font-medium leading-tight">
                      {name}
                      {person.id === me.id && (
                        <span className="font-normal text-muted-foreground">
                          {" · "}
                          {t("chat.you")}
                        </span>
                      )}
                    </span>
                    <span
                      className={cn(
                        "block truncate text-[0.6875rem] leading-tight",
                        typing ? "text-foreground" : "text-muted-foreground",
                      )}
                    >
                      {typing
                        ? t("chat.typing")
                        : (person.job_title ??
                          t(online ? "chat.online" : "chat.offline"))}
                    </span>
                  </span>
                </button>
              </PersonMenu>
            </li>
          );
        })}
      </ul>
    </>
  );
}

function TypingDots() {
  return (
    <span aria-hidden className="flex items-center gap-0.5">
      {[0, 1, 2].map((dot) => (
        <span
          key={dot}
          className="size-1 animate-pulse rounded-full bg-muted-foreground"
          style={{ animationDelay: `${dot * 180}ms` }}
        />
      ))}
    </span>
  );
}

function firstName(person: Profile | undefined): string | null {
  if (!person) return null;
  const name = person.full_name ?? person.email;
  return name.split(" ")[0] || name;
}

/**
 * Makes a face or a name open the person menu, when there is a person behind
 * it. A deleted account leaves its messages in the room; those stay text.
 */
function PersonFace({
  person,
  me,
  children,
}: {
  person: Profile | null;
  me: Profile;
  children: React.ReactNode;
}) {
  if (!person) return <>{children}</>;
  return (
    <PersonMenu person={person} me={me}>
      <button type="button" className="focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring rounded-md">
        {children}
      </button>
    </PersonMenu>
  );
}

function Message({
  message,
  me,
  mine,
  canRemove,
  grouped,
  onRemove,
  tag,
  timeZone,
}: {
  message: TeamMessageWithAuthor;
  /** Who is reading, so the menu knows whether this is them. */
  me: Profile;
  mine: boolean;
  canRemove: boolean;
  grouped: boolean;
  onRemove: () => void;
  tag: string;
  timeZone: string;
}) {
  const { t } = useI18n();
  const name = message.author?.full_name ?? message.author?.email ?? "—";
  const at = formatTimeOfDay(message.created_at, tag, timeZone);
  // The gutter is one avatar wide, which "8:05 AM" does not fit into; the
  // block this message continues already said which half of the day it is.
  const gutter = formatTimeOfDay(message.created_at, tag, timeZone, { bare: true });

  return (
    <div
      className={cn(
        "group/message flex gap-2.5 rounded-lg px-1.5 py-0.5 transition-colors hover:bg-accent/40",
        grouped ? "mt-px" : "mt-2 first:mt-0",
      )}
    >
      <div className="w-8 shrink-0">
        {grouped ? (
          // The timestamp takes the avatar's place on a run of messages, so
          // the column stays the same width and nothing steps sideways.
          <time
            dateTime={message.created_at}
            className="mt-0.5 block whitespace-nowrap text-end text-[0.625rem] leading-5 tabular-nums text-muted-foreground opacity-0 transition-opacity group-hover/message:opacity-100"
          >
            {gutter}
          </time>
        ) : (
          <PersonFace person={message.author} me={me}>
            <Avatar className="size-8">
              <AvatarImage src={message.author?.avatar_url ?? undefined} alt="" />
              <AvatarFallback className="text-[0.6875rem]">
                {initialsFrom(message.author?.full_name, message.author?.email)}
              </AvatarFallback>
            </Avatar>
          </PersonFace>
        )}
      </div>

      <div className="min-w-0 flex-1">
        {!grouped && (
          <div className="flex items-baseline gap-2">
            {/* Whoever said it is a person, and a person answers a click. */}
            <PersonFace person={message.author} me={me}>
              <span className="truncate text-sm font-semibold leading-5 hover:underline">
                {mine ? t("chat.you") : name}
              </span>
            </PersonFace>
            <time
              dateTime={message.created_at}
              className="shrink-0 text-[0.6875rem] text-muted-foreground"
            >
              {at}
            </time>
          </div>
        )}
        <p className="whitespace-pre-wrap break-words text-sm leading-relaxed">
          {message.body}
        </p>
      </div>

      {canRemove && (
        <Button
          variant="ghost"
          size="icon-sm"
          onClick={onRemove}
          aria-label={t("chat.delete")}
          title={t("chat.delete")}
          className="shrink-0 self-start opacity-0 transition-opacity focus-visible:opacity-100 group-hover/message:opacity-100 pointer-coarse:opacity-100"
        >
          <Trash2 />
        </Button>
      )}
    </div>
  );
}
