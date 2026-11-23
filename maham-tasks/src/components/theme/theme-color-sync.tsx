"use client";

import * as React from "react";

/**
 * The browser's own chrome, in the theme's colour.
 *
 * The layout declares a theme colour for the device's light and dark
 * settings, which was right while those were the only two themes. Someone on
 * Midnight with a light-mode phone got a pale grey status bar over a navy
 * app. This reads the frame colour the theme actually painted and hands it to
 * every theme-color tag, whichever of them the device is currently using.
 *
 * It watches the class on <html> rather than asking next-themes. The theme
 * is applied in the provider's own effect, and React runs a child's effects
 * before its parent's — so reading the colour when the theme name changed
 * read the theme being left, one switch behind.
 *
 * And it watches <head>, because Next puts the tags back. Every client-side
 * navigation renders the route's metadata again, which inserts fresh
 * theme-color tags carrying the defaults — so the colour was right on the
 * page you landed on and wrong on every page after it.
 */
export function ThemeColorSync() {
  React.useEffect(() => {
    const root = document.documentElement;

    const sync = () => {
      const colour = getComputedStyle(root).getPropertyValue("--chrome").trim();
      if (!colour) return;
      for (const tag of document.querySelectorAll('meta[name="theme-color"]')) {
        tag.setAttribute("content", colour);
      }
    };

    sync();
    const themeChanged = new MutationObserver(sync);
    themeChanged.observe(root, { attributes: true, attributeFilter: ["class"] });
    // Writing an attribute is not a childList change, so this cannot loop.
    const tagsReplaced = new MutationObserver(sync);
    tagsReplaced.observe(document.head, { childList: true });
    return () => {
      themeChanged.disconnect();
      tagsReplaced.disconnect();
    };
  }, []);

  return null;
}
