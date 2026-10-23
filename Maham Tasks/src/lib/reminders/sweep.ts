import "server-only";

import { createAdminClient } from "@/lib/supabase/admin";
import { isMissingFunction, isMissingTable } from "@/lib/supabase/missing";
import { sendClaimed, type DispatchTally } from "@/lib/reminders/dispatch";
import { alertAdmins } from "@/lib/reminders/admin-alerts";
import type { QueuedReminder } from "@/lib/reminders/types";
import {
  officeClock,
  quietReason,
  SUMMARY_UNTIL_HOUR,
  type QuietReason,
} from "@/lib/work-week";

/**
 * One scheduled run: tidy up, then — in office time on a working day — find
 * what is due and send it.
 *
 * Housekeeping happens whatever the day; it tells nobody anything. Everything
 * that reaches a person waits for the office to be open: nothing on a Friday
 * or Saturday, nothing on a company holiday, nothing before 07:00 or after
 * 19:00. Nothing is lost by waiting. The next working morning's run finds
 * the board as it is then, so a task that went from "due soon" to overdue
 * over the weekend is reported once, as overdue, rather than twice.
 *
 * Being assigned something is the exception, and is not sent from here: it
 * goes the moment it happens (dispatchForTask), because somebody at work
 * just did it.
 */

/** How many to attempt per run, so one invocation cannot run past its timeout. */
const BATCH_SIZE = 40;

type Admin = ReturnType<typeof createAdminClient>;

export type SweepResult = DispatchTally & {
  /** Why nothing was sent, when nothing was. */
  quiet: QuietReason | null;
  /** How many morning summaries were queued this run. */
  summaries: number;
  /** How many admins were told about faults and failed reminders. */
  alerted: number;
  enqueueError: string | null;
};

const NOTHING: DispatchTally = { considered: 0, sent: 0, retrying: 0, givenUp: 0 };

export async function sweep(supabase: Admin, now: Date = new Date()): Promise<SweepResult> {
  // Tasks that have sat in the bin for thirty days are gone for good, and
  // the error log keeps two weeks. Failure here is logged, not fatal.
  const { error: purgeError } = await supabase.rpc("purge_trashed_tasks");
  if (purgeError) console.error(`[reminders] purge_trashed_tasks: ${purgeError.message}`);
  const { error: errorPurge } = await supabase.rpc("purge_old_errors");
  if (errorPurge) console.error(`[reminders] purge_old_errors: ${errorPurge.message}`);

  const clock = officeClock(now);
  const quiet = quietReason(clock, await holidaysOn(supabase, clock.day));
  if (quiet) return { ...NOTHING, quiet, summaries: 0, alerted: 0, enqueueError: null };

  // Refresh the queue from the current state of the board, so one run both
  // finds new work and sends it.
  const { error: enqueueError } = await supabase.rpc("enqueue_task_reminders");

  let summaries = 0;
  if (clock.hour < SUMMARY_UNTIL_HOUR) {
    const { data, error } = await supabase.rpc("enqueue_morning_summaries");
    // Before migration 37 there is no such function; that is not news.
    if (error && !isMissingFunction(error)) {
      console.error(`[reminders] enqueue_morning_summaries: ${error.message}`);
    }
    summaries = typeof data === "number" ? data : 0;
  }

  // Claim the batch before touching a provider. Reading pending rows and
  // marking them sent afterwards meant a run killed by the function timeout
  // left rows pending that had already gone out, and the next run sent them
  // a second time. claim_reminders moves them to 'sending' in one statement.
  const { data, error } = await supabase.rpc("claim_reminders", { batch_size: BATCH_SIZE });
  if (error) throw new Error(`Could not read the reminder queue: ${error.message}`);

  const tally = await sendClaimed(supabase, (data ?? []) as QueuedReminder[]);

  // Last, so this run's own failures are in the note. Never the reason a
  // run fails: the reminders have gone either way.
  const alerted = await alertAdmins(supabase, now).catch((error: unknown) => {
    console.error("[alerts]", error);
    return 0;
  });

  return {
    ...tally,
    quiet: null,
    summaries,
    alerted,
    enqueueError: enqueueError ? enqueueError.message : null,
  };
}

/**
 * Whether `day` is a company holiday. A failed read counts as "no": a
 * reminder sent on a holiday is a nuisance, a whole working day of them
 * silently withheld because the table could not be read is worse.
 */
async function holidaysOn(supabase: Admin, day: string): Promise<Set<string>> {
  const { data, error } = await supabase.from("company_holidays").select("day").eq("day", day);
  if (error) {
    if (!isMissingTable(error)) console.error(`[reminders] company_holidays: ${error.message}`);
    return new Set();
  }
  return new Set((data ?? []).map((row) => row.day));
}
