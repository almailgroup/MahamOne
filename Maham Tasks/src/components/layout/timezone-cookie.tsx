"use client";

import * as React from "react";
import { useRouter } from "next/navigation";

/** A year. The zone rarely changes, and a stale value only costs one refresh. */
const MAX_AGE = 60 * 60 * 24 * 365;

/**
 * Tells the server which calendar the viewer is on.
 *
 * "Due today" is a question about a person's day, not the database's. The
 * dashboard counts are aggregated in Postgres, which has no idea where the
 * reader is, so it used UTC — and four hours east of that, a task due at 02:00
 * was counted on the wrong day. The browser knows the answer; this is how it
 * tells the server, once, in a cookie the dashboard query reads.
 */
export function TimeZoneCookie() {
  const router = useRouter();

  React.useEffect(() => {
    const zone = Intl.DateTimeFormat().resolvedOptions().timeZone;
    if (!zone) return;

    const stored = document.cookie
      .split("; ")
      .find((entry) => entry.startsWith("tz="))
      ?.slice(3);

    if (stored && decodeURIComponent(stored) === zone) return;

    document.cookie = `tz=${encodeURIComponent(zone)}; path=/; max-age=${MAX_AGE}; samesite=lax`;
    // The page that is already on screen was rendered without the zone (or
    // with the old one). Re-render it now that the server can read the right
    // one. Guarded by the comparison above, so this happens once.
    router.refresh();
  }, [router]);

  return null;
}
