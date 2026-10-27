"use client";

import * as React from "react";
import Link from "next/link";
import { ChevronLeft, CornerDownLeft, Loader2, Lock, Trash2 } from "lucide-react";
import { toast } from "sonner";

import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { DaySeparator } from "@/components/chat/day-separator";
import { PersonMenu } from "@/components/people/person-menu";
import { continues, startsNewDay } from "@/lib/chat/grouping";
import { createClient } from "@/lib/supabase/client";
import {
  deleteDirectMessage,
  markConversationRead,
  sendDirectMessage,
} from "@/lib/data/dm-actions";
import { formatTimeOfDay } from "@/lib/dates";
import { initialsFrom } from "@/lib/initials";
import { useI18n } from "@/lib/i18n/client";
import { cn } from "@/lib/utils";
import type {
  DirectMessage,
  DirectMessageWithAuthor,
  Profile,
} from "@/lib/supabase/database.types";

/** After this long without a keystroke somebody has stopped typing. */
const TYPING_IDLE_MS = 2500;

/** Close enough to the bottom that a new message should still follow you. */
const PINNED_PX = 80;

const MAX_LENGTH = 4000;

const useBeforePaint =
  typeof window === "undefined" ? React.useEffect : React.useLayoutEffect;

/**
 * One private conversation.
 *
 * Bubbles rather than the flat list the team room uses: a room needs a name
 * on every message because anybody might have written it, and a conversation
 * between two people does not — which side it is on says who said it.
 *
 * The channel is per conversation, so a tab open on one thread is not told
 * about another. Row-level security applies to what realtime forwards, so
 * subscribing to somebody else's conversation id would deliver nothing.
 */
export function DirectThread({
  conversationId,
  me,
  partner,
  initial,
}: {
  conversationId: string;
  me: Profile;
  partner: Profile | null;
  initial: DirectMessageWithAuthor[];
}) {
  const supabase = React.useMemo(() => createClient(), []);
  const { t, tm, tag, timeZone } = useI18n();

  const [messages, setMessages] = React.useState(initial);
  const [draft, setDraft] = React.useState("");
  const [sending, setSending] = React.useState(false);
  const [partnerTyping, setPartnerTyping] = React.useState(false);

  const scrollerRef = React.useRef<HTMLDivElement>(null);
  const boxRef = React.useRef<HTMLTextAreaElement>(null);
  const channelRef = React.useRef<ReturnType<typeof supabase.channel> | null>(null);
  const idleRef = React.useRef<ReturnType<typeof setTimeout> | null>(null);
  const typingRef = React.useRef(false);
  const pinnedRef = React.useRef(true);

  const name = partner?.full_name ?? partner?.email ?? "—";

  React.useEffect(() => {
    setMessages(initial);
    pinnedRef.current = true;
  }, [initial, conversationId]);

  // Opening a thread is reading it. Done once per conversation rather than on
  // every message, so a long conversation is not a long series of writes.
  React.useEffect(() => {
    void markConversationRead(conversationId);
  }, [conversationId]);

  React.useEffect(() => {
    const channel = supabase.channel(`dm-${conversationId}`, {
      config: { presence: { key: me.id } },
    });
    channelRef.current = channel;

    channel
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "direct_messages",
          filter: `conversation_id=eq.${conversationId}`,
        },
        (payload) => {
          const row = payload.new as DirectMessage;
          setMessages((current) =>
            current.some((message) => message.id === row.id)
              ? current
              : [
                  ...current,
                  {
                    ...row,
                    author: row.author_id === me.id ? me : partner,
                  },
                ],
          );
          if (row.author_id !== me.id) void markConversationRead(conversationId);
        },
      )
      .on(
        "postgres_changes",
        {
          event: "DELETE",
          schema: "public",
          table: "direct_messages",
          filter: `conversation_id=eq.${conversationId}`,
        },
        (payload) => {
          const gone = payload.old as DirectMessage;
          setMessages((current) => current.filter((m) => m.id !== gone.id));
        },
      )
      .on("presence", { event: "sync" }, () => {
        const state = channel.presenceState<{ typing?: boolean }>();
        const theirs = Object.entries(state).filter(([id]) => id !== me.id);
        setPartnerTyping(
          theirs.some(([, entries]) => entries.some((entry) => entry.typing === true)),
        );
      })
      .subscribe(async (status) => {
        if (status === "SUBSCRIBED") await channel.track({ typing: false });
      });

    return () => {
      if (idleRef.current) clearTimeout(idleRef.current);
      channelRef.current = null;
      void supabase.removeChannel(channel);
    };
  }, [supabase, conversationId, me, partner]);

  const announceTyping = React.useCallback((typing: boolean) => {
    if (typingRef.current === typing) return;
    typingRef.current = typing;
    void channelRef.current?.track({ typing });
  }, []);

  const onDraftChange = (value: string) => {
    setDraft(value);
    announceTyping(value.trim().length > 0);
    if (idleRef.current) clearTimeout(idleRef.current);
    idleRef.current = setTimeout(() => announceTyping(false), TYPING_IDLE_MS);
  };

  React.useEffect(() => {
    const box = boxRef.current;
    if (!box) return;
    box.style.height = "auto";
    box.style.height = `${box.scrollHeight}px`;
  }, [draft]);

  useBeforePaint(() => {
    const scroller = scrollerRef.current;
    if (!scroller || !pinnedRef.current) return;
    scroller.scrollTop = scroller.scrollHeight;
  }, [messages, partnerTyping]);

  const onScroll = () => {
    const scroller = scrollerRef.current;
    if (!scroller) return;
    pinnedRef.current =
      scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight < PINNED_PX;
  };

  const send = async () => {
    const text = draft.trim();
    if (!text || sending) return;

    setSending(true);
    setDraft("");
    announceTyping(false);
    pinnedRef.current = true;
    const outcome = await sendDirectMessage(conversationId, text);
    setSending(false);

    if (!outcome.ok) {
      setDraft(text);
      toast.error(tm(outcome.error));
    } else {
      const row = outcome.data;
      setMessages((current) =>
        current.some((message) => message.id === row.id)
          ? current
          : [...current, { ...row, author: me }],
      );
    }
    boxRef.current?.focus();
  };

  const remove = async (id: string) => {
    const outcome = await deleteDirectMessage(id);
    if (!outcome.ok) toast.error(tm(outcome.error));
    else {
      setMessages((current) => current.filter((m) => m.id !== id));
      toast.success(t("dm.deleted"));
    }
  };

  const left = MAX_LENGTH - draft.length;

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <header className="flex items-center gap-2 px-2 py-2 sm:px-3">
        {/* One screen at a time on a phone; both panes from `lg`. */}
        <Button variant="ghost" size="icon-sm" asChild className="lg:hidden">
          <Link href="/messages" aria-label={t("dm.back")}>
            <ChevronLeft className="rtl:-scale-x-100" />
          </Link>
        </Button>

        {/* The person you are talking to, which is a person: their profile
            is one tap from the conversation rather than back on the team
            page. */}
        <PersonHeader person={partner} me={me}>
          <Avatar className="size-8 shrink-0">
            <AvatarImage src={partner?.avatar_url ?? undefined} alt="" />
            <AvatarFallback className="text-[0.6875rem]">
              {initialsFrom(partner?.full_name, partner?.email)}
            </AvatarFallback>
          </Avatar>

          <span className="min-w-0 flex-1 text-start">
            <span className="block truncate text-sm font-semibold leading-tight">
              {name}
            </span>
            <span className="block truncate text-[0.6875rem] leading-tight text-muted-foreground">
              {partnerTyping ? t("chat.typing") : (partner?.job_title ?? "")}
            </span>
          </span>
        </PersonHeader>

        {/* Said once, at the top, rather than on every message. */}
        <span
          className="flex shrink-0 items-center gap-1 text-[0.6875rem] text-muted-foreground"
          title={t("dm.subtitle")}
        >
          <Lock className="size-3" />
          <span className="hidden sm:inline">{t("dm.privateNote")}</span>
        </span>
      </header>

      <div
        ref={scrollerRef}
        onScroll={onScroll}
        role="log"
        aria-label={t("chat.transcript")}
        tabIndex={0}
        className="scrollbar-thin flex min-h-0 flex-1 flex-col overflow-y-auto px-3 py-2 focus-visible:outline-none sm:px-4"
      >
        {messages.length === 0 ? (
          <p className="m-auto max-w-xs text-center text-sm leading-relaxed text-muted-foreground">
            {t("dm.draft")}
          </p>
        ) : (
          messages.map((message, index) => {
            const previous = messages[index - 1];
            const newDay = startsNewDay(previous, message, timeZone);
            return (
              <React.Fragment key={message.id}>
                {newDay && <DaySeparator iso={message.created_at} />}
                <Bubble
                  message={message}
                  mine={message.author_id === me.id}
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

      <p
        aria-live="polite"
        className="flex h-4 items-center gap-1.5 px-4 text-xs text-muted-foreground"
      >
        {partnerTyping && (
          <>
            <span aria-hidden className="flex items-center gap-0.5">
              {[0, 1, 2].map((dot) => (
                <span
                  key={dot}
                  className="size-1 animate-pulse rounded-full bg-muted-foreground"
                  style={{ animationDelay: `${dot * 180}ms` }}
                />
              ))}
            </span>
            {t("chat.isTyping", { name: name.split(" ")[0] || name })}
          </>
        )}
      </p>

      <form
        className="px-3 pb-3 sm:px-4 sm:pb-4"
        onSubmit={(event) => {
          event.preventDefault();
          void send();
        }}
      >
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
            placeholder={t("dm.placeholder", { name: name.split(" ")[0] || name })}
            rows={1}
            maxLength={MAX_LENGTH}
            className={cn(
              "min-h-0 flex-1 resize-none overflow-y-auto rounded-none px-3 py-1.5 text-[0.9375rem] leading-6",
              // Bold, so a message being written is easy to read back.
              "font-semibold placeholder:font-semibold",
              "max-h-40 bg-transparent hover:bg-transparent focus-visible:bg-transparent",
              "shadow-none focus-visible:shadow-none",
              "focus-visible:ring-0 focus-visible:ring-offset-0",
            )}
            aria-label={t("dm.placeholder", { name })}
          />

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
  );
}

/**
 * The header block, as a menu trigger when there is somebody behind it.
 * A deleted account leaves the conversation; that stays text.
 */
function PersonHeader({
  person,
  me,
  children,
}: {
  person: Profile | null;
  me: Profile;
  children: React.ReactNode;
}) {
  const body = (
    <span className="flex min-w-0 flex-1 items-center gap-2">{children}</span>
  );
  if (!person) return body;
  return (
    <PersonMenu person={person} me={me}>
      <button
        type="button"
        className="flex min-w-0 flex-1 items-center gap-2 rounded-lg px-1 py-0.5 transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
      >
        {children}
      </button>
    </PersonMenu>
  );
}

/**
 * One message, on the side of whoever said it.
 *
 * Only your own carry a delete control: the policy allows an author and
 * nobody else, so offering it on theirs would be offering something the
 * database refuses.
 */
function Bubble({
  message,
  mine,
  grouped,
  onRemove,
  tag,
  timeZone,
}: {
  message: DirectMessageWithAuthor;
  mine: boolean;
  grouped: boolean;
  onRemove: () => void;
  tag: string;
  timeZone: string;
}) {
  const { t } = useI18n();

  return (
    <div
      className={cn(
        "group/bubble flex items-end gap-1.5",
        grouped ? "mt-0.5" : "mt-2 first:mt-0",
        mine ? "flex-row-reverse" : "flex-row",
      )}
    >
      <div
        className={cn(
          "max-w-[82%] rounded-[1.25rem] px-3.5 py-2 text-sm leading-relaxed sm:max-w-[70%]",
          mine
            ? "bg-primary text-primary-foreground"
            : "bg-card shadow-[var(--shadow-xs)]",
          // The corner nearest the speaker is clipped, which is what makes a
          // bubble point at whoever said it.
          mine ? "rounded-ee-md" : "rounded-es-md",
        )}
      >
        <p className="whitespace-pre-wrap break-words">{message.body}</p>
        <time
          dateTime={message.created_at}
          className={cn(
            "mt-0.5 block text-[0.625rem] tabular-nums",
            mine ? "text-primary-foreground/70" : "text-muted-foreground",
          )}
        >
          {formatTimeOfDay(message.created_at, tag, timeZone, { bare: true })}
        </time>
      </div>

      {mine && (
        <Button
          variant="ghost"
          size="icon-sm"
          onClick={onRemove}
          aria-label={t("chat.delete")}
          title={t("chat.delete")}
          className="shrink-0 opacity-0 transition-opacity focus-visible:opacity-100 group-hover/bubble:opacity-100 pointer-coarse:opacity-100"
        >
          <Trash2 />
        </Button>
      )}
    </div>
  );
}
