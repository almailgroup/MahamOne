import type { Profile } from "@/lib/supabase/database.types";

/**
 * @mention handling.
 *
 * Comments are stored as plain text with `@Full Name` mentions. Resolving them
 * at render time against the current team means a renamed member's older
 * mentions still light up, and there is no second source of truth to keep in
 * sync with the comment body.
 */

/** Display name used for mentions. */
export function mentionName(profile: Profile): string {
  return profile.full_name?.trim() || profile.email.split("@")[0];
}

/**
 * Split text into plain and mention segments.
 *
 * Candidate names are matched longest-first so "@Ada Lovelace" wins over
 * "@Ada" when both are team members.
 */
export function parseMentions(
  content: string,
  team: Profile[],
): { text: string; mentioned?: Profile }[] {
  const names = team
    .map((profile) => ({ profile, name: mentionName(profile) }))
    .filter((entry) => entry.name.length > 0)
    .sort((a, b) => b.name.length - a.name.length);

  const segments: { text: string; mentioned?: Profile }[] = [];
  let cursor = 0;

  while (cursor < content.length) {
    const at = content.indexOf("@", cursor);
    if (at === -1) break;

    const match = names.find((entry) =>
      content.startsWith(entry.name, at + 1),
    );

    if (!match) {
      cursor = at + 1;
      continue;
    }

    if (at > cursor) segments.push({ text: content.slice(cursor, at) });
    segments.push({ text: `@${match.name}`, mentioned: match.profile });
    cursor = at + 1 + match.name.length;
  }

  if (cursor < content.length) segments.push({ text: content.slice(cursor) });
  return segments;
}

/** Render comment text with mentions emphasised (weight, not colour). */
export function MentionText({
  content,
  team,
}: {
  content: string;
  team: Profile[];
}) {
  const segments = parseMentions(content, team);

  return (
    <span className="whitespace-pre-wrap break-words">
      {segments.map((segment, index) =>
        segment.mentioned ? (
          <span
            key={index}
            className="rounded bg-muted px-1 font-medium text-foreground"
          >
            {segment.text}
          </span>
        ) : (
          <span key={index}>{segment.text}</span>
        ),
      )}
    </span>
  );
}
