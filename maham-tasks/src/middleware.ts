import type { NextRequest } from "next/server";

import { updateSession } from "@/lib/supabase/middleware";

export async function middleware(request: NextRequest) {
  return updateSession(request);
}

export const config = {
  matcher: [
    /*
     * Run on every path except static assets, image files and the metadata
     * routes, so the auth session is refreshed for all real navigations and
     * Server Actions.
     *
     * The manifest has to be excluded explicitly: a browser fetches it to
     * decide whether the app can be installed, and it does so without the
     * session cookie. Redirecting it to /login made the portal
     * un-installable — the extension-based rule above did not catch it
     * because .webmanifest was not in the list.
     *
     * `sw.js` is the same story with worse consequences. A service worker is
     * fetched by the browser on its own schedule, sometimes with no cookie at
     * all; a 307 to /login would be registered as the worker, and a redirect
     * cannot be one. The app would then have no worker and no offline page,
     * and the browser would not try again for a day.
     */
    "/((?!_next/static|_next/image|favicon.ico|manifest.webmanifest|sw.js|robots.txt|sitemap.xml|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico|webmanifest)$).*)",
  ],
};
