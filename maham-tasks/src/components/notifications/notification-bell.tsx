"use client";

import * as React from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  AtSign,
  Bell,
  BellOff,
  CheckCheck,
  CircleCheck,
  Eye,
  LockOpen,
  MessageSquare,
  Send,
  UserMinus,
  UserPlus,
} from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Separator } from "@/components/ui/separator";
import {
  markAllNotificationsRead,
  markNotificationRead,
} from "@/lib/data/notification-actions";
import { createClient } from "@/lib/supabase/client";
import { cn } from "@/lib/utils";
import { useI18n } from "@/lib/i18n/client";
import type { Translator } from "@/lib/i18n";
import type {
  Notification,
  NotificationType,
  Profile,
} from "@/lib/supabase/database.types";

const ICONS: Record<NotificationType, React.ComponentType<{ className?: string }>> = {
  task_assigned: UserPlus,
  task_unassigned: UserMinus,
  task_commented: MessageSquare,
  task_mentioned: AtSign,
  task_review_requested: Eye,
  task_completed: CircleCheck,
  direct_message: Send,
  reminder_failed: BellOff,
  task_unblocked: LockOpen,
};

/**
 * Header bell with a live unread count.
 *
 * Seeded from the server render, then kept current over Realtime. Rows are
 * private to their recipient by RLS, so the subscription only ever delivers
 * this user's notifications.
 */
export function NotificationBell({
  profile,
  initialItems,
  initialUnread,
}: {
  profile: Profile;
  initialItems: Notification[];
  initialUnread: number;
}) {
  const router = useRouter();
  const { t, tag } = useI18n();
  const supabase = React.useMemo(() => createClient(), []);
  const [items, setItems] = React.useState(initialItems);

  // The list is capped at 30 rows, so the badge cannot be derived from it —
  // someone with more unread than that would be undercounted. Track the
  // server's exact count and adjust it as rows are read or arrive.
  const [unread, setUnread] = React.useState(initialUnread);

  /**
   * Which notifications this tab has already accounted for.
   *
   * A row can reach here twice — realtime redelivering it, or a server
   * refresh arriving with it already in the list — and the badge must not
   * count it again. A ref rather than state: this is bookkeeping, and it is
   * read at the moment an event lands rather than at render.
   */
  const seen = React.useRef(new Set(initialItems.map((n) => n.id)));

  React.useEffect(() => {
    setItems(initialItems);
    for (const item of initialItems) seen.current.add(item.id);
  }, [initialItems]);
  React.useEffect(() => setUnread(initialUnread), [initialUnread]);

  React.useEffect(() => {
    const channel = supabase
      .channel(`notifications:${profile.id}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "tasks",
          table: "notifications",
          filter: `user_id=eq.${profile.id}`,
        },
        (payload) => {
          const row = payload.new as Notification;

          // The duplicate check is made here, once, rather than inside the
          // updater. React may run a state updater more than once for a
          // single event — twice under Strict Mode, and again whenever it
          // rebases a queued update — so an updater that also bumps the
          // badge counted the same notification two and three times, and
          // the number beside the bell drifted above the list under it.
          if (seen.current.has(row.id)) return;
          seen.current.add(row.id);

          setItems((current) => [row, ...current].slice(0, 30));
          if (row.read_at === null) setUnread((count) => count + 1);
          toast(row.title, { description: row.body ?? undefined });
        },
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [supabase, profile.id]);

  async function onOpenItem(notification: Notification) {
    if (notification.read_at === null) {
      setItems((current) =>
        current.map((n) =>
          n.id === notification.id
            ? { ...n, read_at: new Date().toISOString() }
            : n,
        ),
      );
      setUnread((count) => Math.max(0, count - 1));
      await markNotificationRead(notification.id);
    }
    router.refresh();
  }

  async function onMarkAll() {
    const now = new Date().toISOString();
    setItems((current) =>
      current.map((n) => (n.read_at ? n : { ...n, read_at: now })),
    );
    setUnread(0);

    const outcome = await markAllNotificationsRead();
    if (!outcome.ok) {
      toast.error(outcome.error);
      router.refresh();
      return;
    }
    router.refresh();
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="ghost"
          size="icon"
          className="relative"
          aria-label={unread > 0 ? t("bell.labelUnread", { n: unread }) : t("bell.label")}
        >
          <Bell />
          {unread > 0 && (
            <span className="absolute -end-0.5 -top-0.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-red-solid px-1 text-[0.625rem] font-semibold leading-none text-white">
              {unread > 9 ? "9+" : unread}
            </span>
          )}
        </Button>
      </DropdownMenuTrigger>

      {/* Maham One's updates panel: a white menu with an edge, the title in
          its header and the rows under it. */}
      <DropdownMenuContent
        align="end"
        className="w-[24rem] max-w-[calc(100vw-1.5rem)] rounded-xl p-0"
      >
        <div className="flex min-h-12 items-center justify-between gap-3 px-4 py-2">
          <span className="text-sm font-semibold text-slate-900">
            {t("bell.label")}
          </span>
          {unread > 0 && (
            <Button
              type="button"
              variant="ghost"
              size="xs"
              onClick={onMarkAll}
              className="-me-2"
            >
              <CheckCheck />
              {t("bell.markAllRead")}
            </Button>
          )}
        </div>

        <Separator className="bg-slate-100" />

        {items.length === 0 ? (
          <p className="px-4 py-8 text-center text-sm text-slate-500">
            {t("bell.empty")}
          </p>
        ) : (
          <ul className="scrollbar-thin flex max-h-[60vh] flex-col gap-0.5 overflow-y-auto p-1.5">
            {items.map((notification) => {
              const Icon = ICONS[notification.type] ?? Bell;
              // A private message points at the conversation it came from;
              // everything else at whatever it is about.
              const href = notification.conversation_id
                ? `/messages/${notification.conversation_id}`
                : notification.project_id
                  ? `/projects/${notification.project_id}`
                  : notification.task_id
                    ? "/general"
                    : "/dashboard";

              return (
                <li key={notification.id}>
                  <Link
                    href={href}
                    onClick={() => onOpenItem(notification)}
                    className={cn(
                      "flex items-start gap-3 rounded-lg px-2.5 py-2 transition-colors hover:bg-slate-50 focus-visible:bg-slate-50",
                      notification.read_at === null && "bg-primary-50/50 hover:bg-primary-50",
                    )}
                  >
                    <Icon className="mt-0.5 size-4 shrink-0 text-slate-400" />
                    <span className="min-w-0 flex-1">
                      <span className="flex items-center gap-1.5">
                        <span className="truncate text-sm font-medium text-slate-900">
                          {notification.title}
                        </span>
                        {notification.read_at === null && (
                          <span
                            className="size-2 shrink-0 rounded-full bg-primary-500"
                            aria-hidden
                          />
                        )}
                      </span>
                      {notification.body && (
                        <span className="mt-0.5 block truncate text-xs text-slate-600">
                          {notification.body}
                        </span>
                      )}
                      <span className="mt-0.5 block text-xs text-slate-500">
                        {relativeTime(notification.created_at, t, tag)}
                      </span>
                    </span>
                  </Link>
                </li>
              );
            })}
          </ul>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

function relativeTime(
  iso: string,
  t: Translator["t"],
  tag: Translator["tag"],
): string {
  const minutes = Math.round((Date.now() - new Date(iso).getTime()) / 60000);
  if (minutes < 1) return t("common.justNow");
  if (minutes < 60) return t("common.minutesAgo", { n: minutes });
  if (minutes < 60 * 24) return t("common.hoursAgo", { n: Math.round(minutes / 60) });
  return new Date(iso).toLocaleDateString(tag, {
    day: "numeric",
    month: "short",
  });
}
