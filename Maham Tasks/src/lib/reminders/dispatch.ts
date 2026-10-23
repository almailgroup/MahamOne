import "server-only";

import { createAdminClient } from "@/lib/supabase/admin";
import { deliver } from "@/lib/reminders/providers";
import type { QueuedReminder } from "@/lib/reminders/types";

/**
 * Sending what has been claimed.
 *
 * Shared by the two things that drain the queue: the daily sweep, which claims
 * whatever is due across everybody, and the assignment path, which claims the
 * rows for the one task it has just created. They differ only in what they
 * claim — once a row is in hand, it is sent and recorded identically, which is
 * the point of this living in one place rather than being written twice.
 */

/** After this many failed attempts a reminder is given up on. */
export const MAX_ATTEMPTS = 4;

export type DispatchTally = {
  considered: number;
  sent: number;
  retrying: number;
  givenUp: number;
};

type Admin = ReturnType<typeof createAdminClient>;

export async function sendClaimed(
  supabase: Admin,
  claimed: QueuedReminder[],
): Promise<DispatchTally> {
  let sent = 0;
  let retrying = 0;
  let givenUp = 0;

  for (const reminder of claimed) {
    const result = await deliver(reminder);
    const attempts = reminder.attempts + 1;

    if (result.ok) {
      sent += 1;
      await supabase
        .from("reminder_queue")
        .update({
          status: "sent",
          attempts,
          sent_at: new Date().toISOString(),
          last_error: null,
          claimed_at: null,
        })
        .eq("id", reminder.id);
      continue;
    }

    // A device the push service says is gone: unsubscribed, app deleted,
    // browser data cleared. Removing the row is the only thing that stops
    // every future reminder queueing a message to nowhere.
    if (!result.ok && result.gone) {
      await supabase
        .from("push_subscriptions")
        .delete()
        .eq("endpoint", reminder.recipient);
    }

    // Stop retrying once it is clearly not going to work, or we have tried enough.
    const exhausted = !result.retryable || attempts >= MAX_ATTEMPTS;
    if (exhausted) givenUp += 1;
    else retrying += 1;

    // Tell the person. A reminder that could not be delivered used to end
    // here: marked failed in a table nobody reads, while somebody waited to
    // hear about work they never heard about. The bell they already watch is
    // the right place for it, and the message names the channel so the fix —
    // a wrong number, a revoked permission — is obvious.
    //
    // Written by the database, like every other notification here: the table
    // takes no inserts from anything holding a session.
    if (exhausted) {
      await supabase.rpc("notify_reminder_failed", { reminder: reminder.id });
    }

    await supabase
      .from("reminder_queue")
      .update({
        status: exhausted ? "failed" : "pending",
        attempts,
        last_error: result.error,
        // When it gave up, not when it was queued. An hour of retries sits
        // between those two, and "why did nobody hear about this" is a
        // question about the second one.
        failed_at: exhausted ? new Date().toISOString() : null,
        // Releasing the claim is what lets a retry be picked up again.
        claimed_at: null,
        // Back off so a struggling provider is not hammered on every run.
        scheduled_for: exhausted
          ? undefined
          : new Date(Date.now() + attempts * 15 * 60_000).toISOString(),
      })
      .eq("id", reminder.id);
  }

  return { considered: claimed.length, sent, retrying, givenUp };
}

/**
 * Send this task's queued reminders now.
 *
 * Called after somebody is assigned, so being handed work arrives while it is
 * still news rather than on the next morning's sweep. The row is written by a
 * database trigger and is already safely in the queue before this runs, so a
 * provider being down here costs nothing: the claim is released, and the daily
 * sweep picks it up exactly as it would have anyway.
 *
 * Deliberately returns rather than throws. It is called from a Server Action
 * after the assignment has already been saved, and a Telegram outage must not
 * turn a successful assignment into a failed one.
 */
export async function dispatchForTask(taskId: string): Promise<DispatchTally | null> {
  try {
    const supabase = createAdminClient();

    const { data, error } = await supabase.rpc("claim_task_reminders", {
      task: taskId,
    });

    if (error) {
      console.error(`[reminders] claim_task_reminders: ${error.message}`);
      return null;
    }

    const claimed = (data ?? []) as QueuedReminder[];
    if (claimed.length === 0) return null;

    return await sendClaimed(supabase, claimed);
  } catch (error) {
    // No service-role key, no network, a provider throwing on import — none of
    // it is the assigning user's problem, and the queue still holds the work.
    console.error(
      "[reminders] could not send on assignment; the daily run will:",
      error instanceof Error ? error.message : error,
    );
    return null;
  }
}
