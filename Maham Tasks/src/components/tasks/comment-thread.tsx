"use client";

import * as React from "react";
import { CloudUpload, Loader2, Send, Trash2 } from "lucide-react";
import { toast } from "sonner";

import {
  Avatar,
  AvatarFallback,
  AvatarImage,
} from "@/components/ui/avatar";
import { initialsFrom } from "@/lib/initials";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { MentionTextarea } from "@/components/tasks/mention-textarea";
import { ReactionChips, ReactionPicker } from "@/components/tasks/comment-reactions";
import { deleteComment } from "@/lib/data/comment-actions";
import { useOutbox } from "@/components/offline/outbox-provider";
import type { OutboxItem } from "@/lib/outbox";
import { MentionText } from "@/lib/mentions";
import { createClient } from "@/lib/supabase/client";
import { useI18n } from "@/lib/i18n/client";
import type { Translator } from "@/lib/i18n";
import type { ReactionRow } from "@/lib/reactions";
import type {
  CommentWithAuthor,
  Profile,
} from "@/lib/supabase/database.types";

/**
 * Live comment thread.
 *
 * The initial page is fetched on mount, then a Realtime channel keeps it in
 * sync. Realtime enforces RLS on every change it forwards, so a subscriber only
 * ever receives rows they are allowed to read.
 */
export function CommentThread({
  taskId,
  team,
  currentProfile,
}: {
  taskId: string;
  team: Profile[];
  currentProfile: Profile;
}) {
  const supabase = React.useMemo(() => createClient(), []);
  const { t, tm, tag } = useI18n();
  const { send: sendChange, pending } = useOutbox();
  // Written with no signal, and on their way once there is one.
  const unsent = pending.filter(
    (item): item is Extract<OutboxItem, { kind: "comment" }> =>
      item.kind === "comment" && item.taskId === taskId,
  );

  // Comments are append-only for members: deleting one — their own included —
  // is a manager action, so the control is not offered.
  const canModerate =
    currentProfile.role === "admin" || currentProfile.role === "manager";

  const [comments, setComments] = React.useState<CommentWithAuthor[] | null>(
    null,
  );
  /**
   * Whether the thread could be read at all. A failed load used to set the
   * list to [] — which renders as "No comments yet. Start the discussion." on
   * a task that may have twenty, inviting somebody to repeat what was said.
   */
  const [loadFailed, setLoadFailed] = React.useState(false);
  const [draft, setDraft] = React.useState("");
  const [sending, setSending] = React.useState(false);
  const endRef = React.useRef<HTMLDivElement>(null);

  // Author lookup for realtime rows, which arrive without the joined profile.
  const teamById = React.useMemo(() => {
    const map = new Map<string, Profile>();
    for (const person of team) map.set(person.id, person);
    return map;
  }, [team]);

  React.useEffect(() => {
    let active = true;

    async function load() {
      const { data, error } = await supabase
        .from("comments")
        // Named, because reactions are a second road from a comment to a
        // profile, and a bare profiles(*) asks PostgREST to pick one. It refuses
        // rather than guesses, and the thread comes back empty.
        .select("*, author:profiles!comments_user_id_fkey(*), reactions:comment_reactions(emoji, user_id)")
        .eq("task_id", taskId)
        .order("created_at", { ascending: true });

      if (!active) return;
      if (error) {
        setLoadFailed(true);
        setComments([]);
        return;
      }
      setLoadFailed(false);
      setComments((data ?? []) as unknown as CommentWithAuthor[]);
    }

    load();

    const channel = supabase
      .channel(`comments:${taskId}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "comments",
          filter: `task_id=eq.${taskId}`,
        },
        (payload) => {
          const row = payload.new as CommentWithAuthor;
          setComments((current) => {
            if (!current) return current;
            // The optimistic insert from this tab may already be present.
            if (current.some((comment) => comment.id === row.id)) return current;
            return [
              ...current,
              {
                ...row,
                author: teamById.get(row.user_id ?? "") ?? null,
                // A new comment has none yet, and the broadcast carries the
                // comments row alone. Left off, the chips read `.length` of
                // undefined — the same shape of crash the board had when
                // checklists arrived and the task merge did not carry them.
                reactions: [],
              },
            ];
          });
        },
      )
      .on(
        "postgres_changes",
        {
          event: "DELETE",
          schema: "public",
          table: "comments",
          filter: `task_id=eq.${taskId}`,
        },
        (payload) => {
          const removed = payload.old as { id?: string };
          if (!removed.id) return;
          setComments((current) =>
            current
              ? current.filter((comment) => comment.id !== removed.id)
              : current,
          );
        },
      )
      .subscribe();

    return () => {
      active = false;
      supabase.removeChannel(channel);
    };
  }, [supabase, taskId, teamById, t]);

  /** How many comments were here last time, so growth can be told from arrival. */
  const seen = React.useRef<number | null>(null);

  // Keep the newest comment in view as the thread grows.
  //
  // Only as it *grows*. The first load is not growth — it is the thread
  // arriving — and scrolling to it took the whole task dialog with it: the
  // nearest scrollable ancestor is the dialog, so opening a task scrolled it
  // three hundred pixels down, past the title of the task you had just
  // tapped, to a comment box you had not asked for.
  React.useEffect(() => {
    const count = comments?.length ?? null;
    if (count === null) return;
    if (seen.current !== null && count > seen.current) {
      endRef.current?.scrollIntoView({ block: "nearest" });
    }
    seen.current = count;
  }, [comments?.length]);

  /** A comment's reactions, replaced in place after a tap. */
  const setReactions = React.useCallback((commentId: string, rows: ReactionRow[]) => {
    setComments((current) =>
      current
        ? current.map((comment) =>
            comment.id === commentId ? { ...comment, reactions: rows } : comment,
          )
        : current,
    );
  }, []);

  async function send() {
    const content = draft.trim();
    if (!content || sending) return;

    setSending(true);
    const outcome = await sendChange({ kind: "comment", taskId, content });
    setSending(false);

    if (outcome === "kept") {
      setDraft("");
      toast(t("outbox.kept"));
      return;
    }
    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }

    // Realtime delivers the row; clear the draft and let it arrive.
    setDraft("");
  }

  async function remove(commentId: string) {
    const outcome = await deleteComment(commentId);
    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }
    setComments((current) =>
      current ? current.filter((comment) => comment.id !== commentId) : current,
    );
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="scrollbar-thin flex max-h-64 flex-col gap-3 overflow-y-auto pe-1">
        {comments === null ? (
          <div className="flex flex-col gap-2">
            <Skeleton className="h-10 w-full" />
            <Skeleton className="h-10 w-3/4" />
          </div>
        ) : loadFailed && comments.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            {t("comment.loadFailed")}
          </p>
        ) : comments.length === 0 && unsent.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            {t("comment.empty")}
          </p>
        ) : (
          comments.map((comment) => {
            const author = comment.author;

            return (
              <div key={comment.id} className="group/comment flex items-start gap-2">
                <Avatar className="mt-0.5 size-6">
                  {author?.avatar_url && (
                    <AvatarImage src={author.avatar_url} alt="" />
                  )}
                  <AvatarFallback className="text-[9px]">
                    {initialsFrom(author?.full_name, author?.email)}
                  </AvatarFallback>
                </Avatar>

                <div className="min-w-0 flex-1">
                  <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
                    <span className="font-medium text-foreground">
                      {author?.full_name ?? author?.email ?? t("comment.unknownUser")}
                    </span>
                    <span>{formatTime(comment.created_at, t, tag)}</span>
                  </p>
                  <div className="mt-0.5 text-sm leading-relaxed">
                    <MentionText content={comment.content} team={team} />
                  </div>
                  <ReactionChips
                    commentId={comment.id}
                    rows={comment.reactions ?? []}
                    me={currentProfile}
                    teamById={teamById}
                    onChange={(rows) => setReactions(comment.id, rows)}
                  />
                </div>

                {/* With the comment's other controls, and out of the way
                    until wanted — except on touch, where there is no hover
                    to bring it out. */}
                <ReactionPicker
                  commentId={comment.id}
                  rows={comment.reactions ?? []}
                  me={currentProfile}
                  onChange={(rows) => setReactions(comment.id, rows)}
                  className="opacity-0 transition-opacity focus-visible:opacity-100 group-hover/comment:opacity-100 data-[state=open]:opacity-100 pointer-coarse:opacity-100"
                />

                {canModerate && (
                  <Button
                    variant="ghost"
                    size="icon-sm"
                    onClick={() => remove(comment.id)}
                    aria-label={t("comment.delete")}
                  >
                    <Trash2 />
                  </Button>
                )}
              </div>
            );
          })
        )}
        {unsent.map((item) => (
          <div key={item.id} className="flex items-start gap-2 opacity-75">
            <Avatar className="mt-0.5 size-6">
              <AvatarFallback className="text-[9px]">
                {initialsFrom(currentProfile.full_name, currentProfile.email)}
              </AvatarFallback>
            </Avatar>
            <div className="min-w-0 flex-1">
              <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
                <span className="font-medium text-foreground">
                  {currentProfile.full_name ?? currentProfile.email}
                </span>
                <span className="inline-flex items-center gap-1">
                  <CloudUpload className="size-3" aria-hidden />
                  {t("outbox.waiting")}
                </span>
              </p>
              <div className="mt-0.5 text-sm leading-relaxed">
                <MentionText content={item.content} team={team} />
              </div>
            </div>
          </div>
        ))}
        <div ref={endRef} />
      </div>

      <div className="flex flex-col gap-1.5">
        <MentionTextarea
          value={draft}
          onChange={setDraft}
          team={team}
          onSubmit={send}
          rows={2}
          maxLength={5000}
          placeholder={t("comment.placeholder")}
          aria-label={t("comment.new")}
        />
        <div className="flex items-center justify-between gap-2">
          <p className="text-xs text-muted-foreground">
            {t("comment.hint")}
          </p>
          <Button size="sm" onClick={send} disabled={sending || !draft.trim()}>
            {sending ? <Loader2 className="animate-spin" /> : <Send />}
            {t("comment.send")}
          </Button>
        </div>
      </div>
    </div>
  );
}

function formatTime(iso: string, t: Translator["t"], tag: Translator["tag"]): string {
  const then = new Date(iso);
  const minutes = Math.round((Date.now() - then.getTime()) / 60000);

  if (minutes < 1) return t("common.justNow");
  if (minutes < 60) return t("common.minutesAgo", { n: minutes });
  if (minutes < 60 * 24) return t("common.hoursAgo", { n: Math.round(minutes / 60) });

  return then.toLocaleDateString(tag, { day: "numeric", month: "short" });
}
