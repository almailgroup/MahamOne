/**
 * Deterministic two-letter initials for avatar fallbacks.
 *
 * Lives in its own module, with no "use client" directive, because Server
 * Components call it. Every export of a "use client" module becomes a client
 * reference when imported from the server, so a plain function defined there
 * throws when invoked during a server render.
 */
export function initialsFrom(
  name?: string | null,
  email?: string | null,
): string {
  const source = name?.trim() || email?.split("@")[0] || "";
  if (!source) return "?";

  const parts = source.split(/[\s._-]+/).filter(Boolean);
  if (parts.length === 0) return "?";
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();

  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}
