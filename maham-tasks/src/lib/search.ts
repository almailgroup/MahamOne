/**
 * Turning what someone typed into a PostgREST `ilike` pattern.
 *
 * `%` and `_` are wildcards in LIKE — `%` for any run of characters, `_` for
 * exactly one — so a search for "50% off" or "back_up" would otherwise match
 * far more than it should. A backslash escapes them, and has to be escaped
 * itself before it can do that.
 */
export function likePattern(term: string): string {
  return `%${term.trim().replace(/[\\%_]/g, (char) => `\\${char}`)}%`;
}

/** Below two characters a search matches most of the workspace: noise, not results. */
export const MIN_SEARCH_LENGTH = 2;

export function isSearchable(term: string): boolean {
  return term.trim().length >= MIN_SEARCH_LENGTH;
}

/**
 * The same pattern, quoted for use inside a PostgREST `or=(…)` filter.
 *
 * An `or` filter packs several conditions into one value, separated by commas
 * and delimited by brackets — so a search for "shipping, urgent" would be read
 * as two conditions and either fail or filter on something nobody asked for.
 * Double quotes protect the value; inside them a backslash escapes a quote or
 * another backslash, and the LIKE escapes added above are themselves
 * backslashes, so they have to survive this second layer intact.
 */
export function likeFilterValue(term: string): string {
  const escaped = likePattern(term).replace(/[\\"]/g, (char) => `\\${char}`);
  return `"${escaped}"`;
}
