"use client";

import * as React from "react";

/**
 * Registers the service worker, once, after the page has settled.
 *
 * Deliberately after `load`: registering during hydration competes with the
 * page's own requests for the connection it is trying to make fast, and
 * nothing the worker does is needed in the first second.
 *
 * Development is left alone. The worker would cache build assets that the dev
 * server rewrites on every edit, and the confusion that causes is worth more
 * than the coverage.
 */
export function ServiceWorkerRegistrar() {
  React.useEffect(() => {
    if (process.env.NODE_ENV !== "production") return;
    if (typeof navigator === "undefined" || !("serviceWorker" in navigator)) return;

    const register = () => {
      navigator.serviceWorker.register("/sw.js").catch(() => {
        // A failed registration is not worth a message: everything still
        // works, it just works online only.
      });
    };

    if (document.readyState === "complete") register();
    else window.addEventListener("load", register, { once: true });

    return () => window.removeEventListener("load", register);
  }, []);

  return null;
}
