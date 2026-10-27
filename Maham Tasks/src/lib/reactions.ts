/**
 * Reactions on a comment: the five that exist, and how a pile of them reads.
 *
 * The list is the database's own check constraint, written out a second time
 * so the picker cannot offer one the insert would refuse. A unit test reads
 * the migration and holds the two to each other.
 */
export const REACTIONS = ["👍", "✅", "🙏", "👀", "🎉"] as const;

export type Reaction = (typeof REACTIONS)[number];

export function isReaction(value: unknown): value is Reaction {
  return typeof value === "string" && (REACTIONS as readonly string[]).includes(value);
}

/** One reaction row, as much of it as the thread needs. */
export type ReactionRow = { emoji: string; user_id: string };

export type ReactionSummary = {
  emoji: Reaction;
  count: number;
  /** Whether the reader is one of them — the chip is drawn pressed. */
  mine: boolean;
  /** Who, in the order they reacted, for the chip's tooltip. */
  userIds: string[];
};

/**
 * Rows grouped into chips, in the picker's own order rather than by count.
 *
 * Ordering by count makes the chips swap places as people react, and a chip
 * that moves while somebody is reaching for it is a tap on the wrong one.
 * Anything not on the list is dropped: the database refuses it anyway, and a
 * stale optimistic row must not draw a chip that cannot be taken back.
 */
export function summariseReactions(
  rows: readonly ReactionRow[],
  meId: string,
): ReactionSummary[] {
  return REACTIONS.flatMap((emoji) => {
    const userIds = rows.filter((row) => row.emoji === emoji).map((row) => row.user_id);
    if (userIds.length === 0) return [];
    return [{ emoji, count: userIds.length, mine: userIds.includes(meId), userIds }];
  });
}

/** The same rows with the reader's reaction added or taken away. */
export function toggledReactions(
  rows: readonly ReactionRow[],
  emoji: Reaction,
  meId: string,
): ReactionRow[] {
  const mine = rows.some((row) => row.emoji === emoji && row.user_id === meId);
  return mine
    ? rows.filter((row) => !(row.emoji === emoji && row.user_id === meId))
    : [...rows, { emoji, user_id: meId }];
}
