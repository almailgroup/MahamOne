"use client";

import * as React from "react";
import { useTheme } from "next-themes";

import { themeColor } from "@/lib/themes";

/**
 * The browser's toolbar takes the theme's colour, as in Maham One: the main
 * colour for a light theme, the page for a dark one. The viewport's own
 * tags (layout.tsx) cover the first paint; this follows any later choice.
 */
export function ThemeColorSync() {
  const { resolvedTheme } = useTheme();

  React.useEffect(() => {
    const colour = themeColor(resolvedTheme);
    const sync = () => {
      for (const tag of document.querySelectorAll('meta[name="theme-color"]')) {
        tag.setAttribute("content", colour);
      }
    };
    sync();
    // Next.js replaces the tags on navigation.
    const tagsReplaced = new MutationObserver(sync);
    tagsReplaced.observe(document.head, { childList: true });
    return () => tagsReplaced.disconnect();
  }, [resolvedTheme]);

  return null;
}
