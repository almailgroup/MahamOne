"use client";

import * as React from "react";

import { useRouter } from "next/navigation";
import { toast } from "sonner";

import { askAssistant } from "@/lib/data/assistant-actions";
import { runAssistantAction } from "@/lib/data/assistant-run";
import { useI18n } from "@/lib/i18n/client";
import type { AssistantMessage } from "@/lib/assistant/types";

export type Assistant = {
  messages: AssistantMessage[];
  draft: string;
  /**
   * Takes an updater as well as a value. Dictation needs it: two settled
   * phrases can arrive in one tick, and both would read the same stale draft
   * if all they had was `setDraft(draft + heard)`.
   */
  setDraft: React.Dispatch<React.SetStateAction<string>>;
  pending: boolean;
  send: (text: string) => void;
  clear: () => void;
  /** Carry out the proposal on a message, once the person has agreed. */
  confirm: (messageId: string) => void;
  /** Decline it, and leave the board alone. */
  dismiss: (messageId: string) => void;
  /** The message whose proposal is being carried out, if any. */
  running: string | null;
};

const newId = () =>
  typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random()}`;

/**
 * The AI assistant's conversation.
 *
 * Held once, in AppShell, and handed to both the rail panel and the mobile
 * drawer panel. All of it is shared — not just the thread: when each panel
 * kept its own `pending` and `draft`, the two surfaces disagreed about whether
 * a question was in flight, and a viewport that crossed the `lg` breakpoint
 * with the drawer open could fire two requests into one thread.
 */
export function useAssistant(): Assistant {
  const [messages, setMessages] = React.useState<AssistantMessage[]>([]);
  const [draft, setDraft] = React.useState("");
  const [pending, setPending] = React.useState(false);
  const [running, setRunning] = React.useState<string | null>(null);
  const { t, tm } = useI18n();
  const router = useRouter();

  const send = React.useCallback(
    (text: string) => {
      const question = text.trim();
      if (!question || pending) return;

      const asked: AssistantMessage = {
        id: newId(),
        role: "user",
        text: question,
        at: new Date().toISOString(),
      };
      const history = [...messages, asked];

      setMessages(history);
      setDraft("");
      setPending(true);

      void (async () => {
        let reply: string;
        let action: AssistantMessage["action"] = null;
        try {
          const outcome = await askAssistant(history);
          reply = outcome.ok ? outcome.data.text : tm(outcome.error);
          if (outcome.ok) action = outcome.data.action ?? null;
        } catch {
          // A Server Action rejects outright when the network drops or the
          // deployment 500s. Without this the spinner ran forever and the
          // panel stayed disabled — and since it is no longer a dialog that
          // unmounts, closing and reopening did not clear it either.
          reply = t("assistant.unreachable");
        }

        setMessages((current) => [
          ...current,
          {
            id: newId(),
            role: "assistant",
            text: reply,
            at: new Date().toISOString(),
            action,
          },
        ]);
        setPending(false);
      })();
    },
    [messages, pending, t, tm],
  );

  const settle = React.useCallback(
    (messageId: string, outcome: "done" | "dismissed") =>
      setMessages((current) =>
        current.map((message) =>
          message.id === messageId ? { ...message, outcome } : message,
        ),
      ),
    [],
  );

  /**
   * Carry out what was proposed.
   *
   * The arguments go back to the server exactly as they arrived and are
   * validated there before anything is written — this is the button, not the
   * authority. A refresh follows a success so the board behind the panel
   * shows the change rather than the state before it.
   */
  const confirm = React.useCallback(
    (messageId: string) => {
      const message = messages.find((entry) => entry.id === messageId);
      if (!message?.action || message.outcome || running) return;

      setRunning(messageId);
      void (async () => {
        try {
          const outcome = await runAssistantAction(message.action!);
          if (!outcome.ok) {
            toast.error(tm(outcome.error));
            return;
          }
          settle(messageId, "done");
          toast.success(t("assistant.done"));
          router.refresh();
        } catch {
          toast.error(t("assistant.unreachable"));
        } finally {
          setRunning(null);
        }
      })();
    },
    [messages, running, settle, t, tm, router],
  );

  const dismiss = React.useCallback(
    (messageId: string) => settle(messageId, "dismissed"),
    [settle],
  );

  const clear = React.useCallback(() => {
    if (pending || running) return;
    setMessages([]);
  }, [pending, running]);

  return { messages, draft, setDraft, pending, send, clear, confirm, dismiss, running };
}
