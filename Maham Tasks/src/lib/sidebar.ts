/**
 * Sidebar width constants.
 *
 * Deliberately in a module with no "use client" directive: the authenticated
 * layout is a Server Component and interpolates these into its pre-paint
 * script, and every export of a client module becomes a client reference when
 * the server imports it.
 */
export const SIDEBAR_MIN = 208;
export const SIDEBAR_MAX = 440;
export const SIDEBAR_DEFAULT = 240;
export const SIDEBAR_STORAGE_KEY = "almailgroup:sidebar-width";

/**
 * The rail holds a conversation when the assistant is open, which needs more room
 * than a list of links. It gets its own bounds rather than widening the ones
 * above, so closing the assistant returns the sidebar to sane navigation
 * widths instead of leaving it stretched.
 */
export const SIDEBAR_CHAT_MIN = 320;
export const SIDEBAR_CHAT_MAX = 640;
export const SIDEBAR_CHAT_DEFAULT = 420;

export type SidebarMode = "nav" | "chat";

export function sidebarBounds(mode: SidebarMode = "nav") {
  return mode === "chat"
    ? { min: SIDEBAR_CHAT_MIN, max: SIDEBAR_CHAT_MAX, preferred: SIDEBAR_CHAT_DEFAULT }
    : { min: SIDEBAR_MIN, max: SIDEBAR_MAX, preferred: SIDEBAR_DEFAULT };
}

export function clampSidebarWidth(
  value: number,
  mode: SidebarMode = "nav",
): number {
  const { min, max, preferred } = sidebarBounds(mode);
  if (!Number.isFinite(value)) return preferred;
  return Math.min(max, Math.max(min, Math.round(value)));
}
