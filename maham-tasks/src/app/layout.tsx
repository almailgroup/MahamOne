import type { Metadata, Viewport } from "next";
import localFont from "next/font/local";

import { ThemeProvider } from "@/components/theme/theme-provider";
import { ThemeColorSync } from "@/components/theme/theme-color-sync";
import { THEME_IDS } from "@/lib/themes";
import { I18nProvider } from "@/lib/i18n/client";
import { directionFor } from "@/lib/i18n";
import { getLocale, getTimeZone } from "@/lib/i18n/server";
import { Toaster } from "@/components/ui/sonner";
import { OfflineBar } from "@/components/offline/offline-bar";
import { ServiceWorkerRegistrar } from "@/components/offline/service-worker";
import "./globals.css";

/*
 * The fonts are files in this repository (./fonts, with their licence)
 * rather than fetched from Google Fonts at build time. Fetching them made
 * every build — CI's and Vercel's — depend on Google answering in the shape
 * Next expects; when it did not, the build failed with "An error occurred in
 * next/font" and nothing to do but wait. They were self-hosted at run time
 * either way, so visitors see no difference.
 */
const geistSans = localFont({
  src: "./fonts/geist-latin.woff2",
  variable: "--font-geist-sans",
  weight: "100 900",
  display: "swap",
});

const geistMono = localFont({
  src: "./fonts/geist-mono-latin.woff2",
  variable: "--font-geist-mono",
  weight: "100 900",
  display: "swap",
});

// Geist has no Arabic glyphs. Loaded for every page so switching language
// never waits on a font, and only used when the document is Arabic. Limited
// to Arabic characters, as Google's own stylesheet does, so digits and Latin
// text inside Arabic still come from Geist.
const notoArabic = localFont({
  src: "./fonts/noto-sans-arabic.woff2",
  variable: "--font-arabic",
  weight: "400 700",
  display: "swap",
  declarations: [
    {
      prop: "unicode-range",
      value:
        "U+0600-06FF, U+0750-077F, U+0870-0891, U+0897-08E1, U+08E3-08FF, U+200C-200E, U+2010-2011, U+204F, U+2E41, U+FB50-FDFF, U+FE70-FE74, U+FE76-FEFC, U+102E0-102FB, U+10E60-10E7E, U+10EC2-10EC7, U+10EC9-10EEE, U+10EF0-10EFF, U+1EE00-1EEFF",
    },
  ],
});

export const metadata: Metadata = {
  title: {
    default: "Maham Tasks",
    template: "%s · Maham Tasks",
  },
  description:
    "Plan, assign and track work — projects, tasks, Kanban boards and real-time collaboration.",
  applicationName: "Maham Tasks",
  /**
   * Installed to a home screen on iOS.
   *
   * `title` is the name under the icon, and without it iOS uses the page
   * title — "Today · Maham Tasks" or whichever page happened to be open when
   * it was added. `default` keeps the status bar opaque and the web view
   * below it, which is what the safe-area padding elsewhere is measured
   * against; `black-translucent` would put the page under the clock and is a
   * different layout, not a different colour.
   */
  appleWebApp: {
    capable: true,
    title: "Maham Tasks",
    statusBarStyle: "default",
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  // The app is laid out for the screen it is on, so there is nothing to zoom
  // into: pinching only ever happened because a page had overflowed sideways
  // or because Safari zoomed in by itself when a field was focused. Both are
  // fixed at the source — this stops the browser doing it uninvited.
  maximumScale: 1,
  userScalable: false,
  /**
   * Lets the page reach the edges of the screen, and — the reason it is here —
   * makes `env(safe-area-inset-*)` report real numbers. Without it every one
   * of them is `0px`, which is why the navigation bar sat on the iPhone's home
   * indicator despite having been padded away from it since the day it was
   * written. Anything that now reaches under the notch or the indicator pads
   * itself back out: the header at the top, the bar and the page at the
   * bottom.
   */
  viewportFit: "cover",
  // Matches the page grounds, so the browser chrome on a phone blends into
  // the app instead of framing it in a colour the design never uses.
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f3f3f4" },
    { media: "(prefers-color-scheme: dark)", color: "#2c2d32" },
  ],
};

export default async function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  // The language is a cookie the selector sets; `lang` and `dir` on the root
  // element are what make the whole layout mirror for Arabic, not just the
  // words. Everything below reads the same cookie through the provider.
  const [locale, timeZone] = await Promise.all([getLocale(), getTimeZone()]);

  return (
    <html lang={locale} dir={directionFor(locale)} suppressHydrationWarning>
      {/*
       * The manifest is asked for with credentials, which is not the default.
       *
       * A manifest is fetched with cookies omitted unless the link says
       * otherwise. Behind Vercel's deployment protection that reads as an
       * anonymous request, so the platform redirects it to vercel.com/sso-api
       * — a different origin, which turns a same-origin fetch into a CORS one
       * that vercel.com refuses. The console filled with CORS failures and the
       * app had no manifest: no name, no icon, nothing to install to a home
       * screen, on exactly the protected URLs the team tests from.
       *
       * Written out here rather than through `metadata.manifest`, which has
       * no way to set the attribute.
       */}
      <link
        rel="manifest"
        href="/manifest.webmanifest"
        crossOrigin="use-credentials"
      />
      <body
        className={`${geistSans.variable} ${geistMono.variable} ${notoArabic.variable}`}
      >
        <ThemeProvider
          attribute="class"
          defaultTheme="system"
          enableSystem
          themes={THEME_IDS}
          // globals.css sets color-scheme per theme family. next-themes only
          // knows the names light and dark, and left a stale inline value
          // behind when switching to any other.
          enableColorScheme={false}
          disableTransitionOnChange
        >
          <ThemeColorSync />
          <I18nProvider locale={locale} timeZone={timeZone}>
            <OfflineBar />
            {children}
            <Toaster />
            <ServiceWorkerRegistrar />
          </I18nProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
