"use server";

import { buildSnapshot } from "@/lib/assistant/snapshot";
import { answerLocally } from "@/lib/assistant/local-brain";
import { answerLanguage } from "@/lib/assistant/language";
import { previewOf } from "@/lib/assistant/preview";
import { fail, ok, type ActionResult } from "@/lib/action-result";
import { createTranslator } from "@/lib/i18n";
import { getI18n } from "@/lib/i18n/server";
import type { AssistantAnswer, AssistantMessage } from "@/lib/assistant/types";

/**
 * Ask the assistant a question.
 *
 * The snapshot is built server-side, per request, under the caller's own
 * permissions — the browser never holds the task data the assistant reasons
 * over, and never learns the Worker's address or its key.
 *
 * When ALMAIL_AI_WORKER_URL is set this forwards the turn history and the
 * snapshot to the Cloudflare Worker that fronts Gemini. Until then it answers
 * from the local brain, which is also the fallback if that call fails: a
 * network hiccup should degrade the answer, not break the panel.
 */
export async function askAssistant(
  messages: AssistantMessage[],
): Promise<ActionResult<AssistantAnswer>> {
  const question = [...messages].reverse().find((m) => m.role === "user")?.text;
  if (!question?.trim()) return fail("action.askSomething");
  if (question.length > 2000) return fail("action.questionTooLong");

  const [snapshot, i18n] = await Promise.all([buildSnapshot(), getI18n()]);
  const endpoint = process.env.ALMAIL_AI_WORKER_URL;

  /*
   * The language of the question, not of the interface.
   *
   * Somebody on the English interface who types in Arabic is speaking
   * Arabic. Decided here rather than in the Worker so the local brain and
   * Gemini answer in the same language as each other, from one rule.
   */
  const replyIn = answerLanguage(question, snapshot.locale);
  const speaker = replyIn === snapshot.locale ? i18n : createTranslator(replyIn);

  if (!endpoint) {
    // Whoever is asking cannot act on this; whoever runs the workspace can,
    // and until now had nothing to act on. Both ways of ending up with a
    // local answer looked identical from every side, which is a poor way to
    // spend an evening wondering why Gemini is not answering.
    console.warn(
      "[assistant] ALMAIL_AI_WORKER_URL is not set on this deployment, " +
        "so the answer came from the local brain. Environment variables are " +
        "fixed when a deployment is built: adding one means redeploying.",
    );
    return ok(answerLocally(question, snapshot, speaker));
  }

  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        // Shared secret, so only this app can spend the Gemini quota.
        ...(process.env.ALMAIL_AI_WORKER_SECRET
          ? { authorization: `Bearer ${process.env.ALMAIL_AI_WORKER_SECRET}` }
          : {}),
      },
      body: JSON.stringify({ messages, snapshot: { ...snapshot, replyIn } }),
      // A chat turn that has not answered in 20s is not going to.
      signal: AbortSignal.timeout(20_000),
    });

    if (!response.ok) {
      // The body carries the Worker's own account of what went wrong. Without
      // it the log says only "502", which names the messenger, not the news.
      const detail = await response.text().catch(() => "");
      throw new Error(
        `Worker replied ${response.status}${detail ? `: ${detail.slice(0, 300)}` : ""}`,
      );
    }

    const body = (await response.json()) as {
      text?: string;
      action?: { name?: string; arguments?: Record<string, unknown> } | null;
    };

    // A turn that only proposes something carries no prose, and that is fine:
    // the panel has a card to show. A turn with neither is a failure.
    const proposed = body.action?.name
      ? { name: body.action.name, arguments: body.action.arguments ?? {} }
      : null;

    // A proposal nobody could read is not one worth showing. If the snapshot
    // cannot make sense of it — an id that is not on this board, a field
    // missing — it is dropped and the prose stands on its own.
    const preview = proposed ? previewOf(proposed, snapshot, i18n) : null;
    const action = proposed && preview ? { ...proposed, preview } : null;
    if (!body.text?.trim() && !action) {
      throw new Error("Worker replied with no text");
    }

    return ok({ text: body.text ?? "", source: "gemini", action });
  } catch (error) {
    // Silent in front of the person asking, who cannot act on it and is
    // better served by a worse answer than by an error. Not silent in the
    // server log, which is where somebody can.
    console.error("[assistant] the Worker call failed, answering locally:", error);
    // `true`: a model is configured, it just did not answer. Saying otherwise
    // would send whoever asked to re-check settings that are fine.
    return ok(answerLocally(question, snapshot, speaker, true));
  }
}
