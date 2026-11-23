"use client";

import * as React from "react";

/**
 * Hold the page still while something is open over it.
 *
 * `overflow: hidden` on the body is the usual answer and does not work on
 * iOS: Safari keeps scrolling the page underneath, so opening the navigation
 * drawer and dragging moved the board behind it, and closing left you
 * somewhere you had not chosen to be.
 *
 * Fixing the body does work, and costs the scroll position, which is why it is
 * recorded and put back. The page is pinned by its offset rather than simply
 * frozen, so nothing jumps at the moment it opens.
 */
/**
 * @param leaving Set this before closing when the close is a navigation. The
 *   position belongs to the page being left, and putting it back lands the new
 *   one part-scrolled — tapping Calendar in the drawer arrived 59px down a page
 *   that had never been scrolled. It cannot be worked out from the URL here:
 *   the drawer closes on the tap, before the route has changed.
 */
export function useScrollLock(active: boolean, leaving?: React.RefObject<boolean>) {
  React.useEffect(() => {
    if (!active) return;

    const { body } = document;
    const y = window.scrollY;
    const previous = {
      position: body.style.position,
      top: body.style.top,
      left: body.style.left,
      right: body.style.right,
      width: body.style.width,
    };

    body.style.position = "fixed";
    body.style.top = `-${y}px`;
    body.style.left = "0";
    body.style.right = "0";
    body.style.width = "100%";

    return () => {
      Object.assign(body.style, previous);
      // `scrollTo` rather than restoring a saved scroll: unfixing the body
      // drops the page back to the top, and this is the same frame, so the
      // jump is never painted.
      if (!leaving?.current) window.scrollTo(0, y);
      if (leaving) leaving.current = false;
    };
  }, [active, leaving]);
}
