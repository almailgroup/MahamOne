"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";

import { setChecklistItemDone } from "@/lib/data/checklist-actions";
import { postComment } from "@/lib/data/comment-actions";
import { changeTaskStatus, moveTask, rescheduleTask } from "@/lib/data/task-actions";
import { useI18n } from "@/lib/i18n/client";
import type { ActionResult } from "@/lib/action-result";
import { useStoredOutbox } from "@/components/offline/use-stored-outbox";
import {
  changesFor,
  dropChange,
  isNetworkFailure,
  keepChange,
  readOutbox,
  type OutboxChange,
  type OutboxItem,
} from "@/lib/outbox";

/** Sent now, or kept on this device to send when the connection is back. */
export type Sent = ActionResult<unknown> | "kept";

type Outbox = {
  /** This person's unsent changes, oldest first. */
  pending: OutboxItem[];
  send: (change: OutboxChange) => Promise<Sent>;
};

const OutboxContext = React.createContext<Outbox | null>(null);

/** The call a kept change stands for. */
function deliver(item: OutboxItem): Promise<ActionResult<unknown>> {
  switch (item.kind) {
    case "move":
      return moveTask(item.taskId, item.projectId, item.status, item.position);
    case "status":
      return changeTaskStatus(item.taskId, item.projectId, item.status);
    case "reschedule":
      return rescheduleTask(item.taskId, item.projectId, item.dueAt);
    case "checklist":
      return setChecklistItemDone(item.itemId, item.done);
    case "comment": {
      const form = new FormData();
      form.set("content", item.content);
      return postComment(item.taskId, null, form);
    }
  }
}

/**
 * Keeps what somebody does with no connection, and sends it when there is
 * one: as soon as the browser says it is back, when the app comes to the
 * front again, and when it is opened.
 */
export function OutboxProvider({ me, children }: { me: string; children: React.ReactNode }) {
  const router = useRouter();
  const { t, tn, tm } = useI18n();
  const stored = useStoredOutbox();
  const pending = React.useMemo(() => changesFor(me, stored), [me, stored]);
  const flushing = React.useRef(false);

  const flush = React.useCallback(async () => {
    if (flushing.current || !navigator.onLine) return;
    const queue = changesFor(me, readOutbox());
    if (queue.length === 0) return;

    flushing.current = true;
    let sent = 0;
    try {
      for (const item of queue) {
        let outcome: ActionResult<unknown>;
        try {
          outcome = await deliver(item);
        } catch (error) {
          // Still no connection after all: stop, and try again later.
          if (isNetworkFailure(error)) break;
          outcome = { ok: false, error: "common.somethingWrong" };
        }
        dropChange(item.id);
        if (outcome.ok) {
          sent++;
        } else {
          // Refused, not lost in the post: say which, and let it go.
          const what = "title" in item ? item.title : t(item.kind === "comment" ? "outbox.aComment" : "outbox.aStep");
          toast.error(t("outbox.refused", { what, reason: tm(outcome.error) }), { duration: 10_000 });
        }
      }
    } finally {
      flushing.current = false;
    }

    if (sent > 0) {
      toast.success(tn("outbox.sent", sent));
      router.refresh();
    }
  }, [me, router, t, tn, tm]);

  React.useEffect(() => {
    void flush();
    const whenVisible = () => {
      if (document.visibilityState === "visible") void flush();
    };
    window.addEventListener("online", flush);
    document.addEventListener("visibilitychange", whenVisible);
    return () => {
      window.removeEventListener("online", flush);
      document.removeEventListener("visibilitychange", whenVisible);
    };
  }, [flush]);

  const send = React.useCallback(
    async (change: OutboxChange): Promise<Sent> => {
      const keep = () => {
        keepChange({ ...change, owner: me });
        return "kept" as const;
      };
      // Behind something still waiting, it waits too: changes arrive in the
      // order they were made.
      if (!navigator.onLine || changesFor(me, readOutbox()).length > 0) {
        const kept = keep();
        void flush();
        return kept;
      }
      try {
        const outcome = await deliver({ ...change, owner: me, id: "", at: "" } as OutboxItem);
        return outcome;
      } catch (error) {
        if (isNetworkFailure(error)) return keep();
        throw error;
      }
    },
    [me, flush],
  );

  const value = React.useMemo(() => ({ pending, send }), [pending, send]);
  return <OutboxContext.Provider value={value}>{children}</OutboxContext.Provider>;
}

/**
 * The outbox, where there is one. Outside the signed-in app — never, in
 * practice — sending simply sends.
 */
export function useOutbox(): Outbox {
  const outbox = React.useContext(OutboxContext);
  return (
    outbox ?? {
      pending: [],
      send: (change) => deliver({ ...change, owner: "", id: "", at: "" } as OutboxItem),
    }
  );
}
