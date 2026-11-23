/**
 * How a run of messages is broken up on screen.
 *
 * Two rules, both pure and both dependent on the viewer's own timezone, which
 * is why they live here rather than inside the component: a message sent at
 * 23:30 UTC is tomorrow in Dubai, and the separator has to agree with the
 * clock time printed beside it.
 */

/** A message's identity, as far as grouping is concerned. */
export type Grouped = {
  author_id: string;
  created_at: string;
};

/** Messages further apart than this start a new block, same author or not. */
export const RUN_GAP_MS = 5 * 60_000;

/**
 * The calendar day a moment falls on, where the reader is.
 *
 * `en-CA` because it formats as `YYYY-MM-DD`, which sorts and compares as a
 * string. The locale is fixed on purpose: this value is never shown, and a
 * translated month name would make two identical days look different.
 */
export function dayKey(iso: string, timeZone?: string): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone }).format(new Date(iso));
}

/** Whether this message is the first of a new day. */
export function startsNewDay(
  previous: Grouped | undefined,
  message: Grouped,
  timeZone?: string,
): boolean {
  if (!previous) return true;
  return dayKey(previous.created_at, timeZone) !== dayKey(message.created_at, timeZone);
}

/**
 * Whether this message continues the one before it — same person, close
 * enough in time to be the same breath, so it is shown without repeating
 * their name and picture.
 */
export function continues(previous: Grouped | undefined, message: Grouped): boolean {
  if (!previous || previous.author_id !== message.author_id) return false;
  const gap =
    new Date(message.created_at).getTime() - new Date(previous.created_at).getTime();
  return gap >= 0 && gap < RUN_GAP_MS;
}
