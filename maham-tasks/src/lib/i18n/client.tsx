"use client";

import * as React from "react";
import { useRouter } from "next/navigation";

import {
  DEFAULT_TIME_ZONE,
  LOCALE_COOKIE,
  createTranslator,
  type Locale,
  type Translator,
} from "./index";

const I18nContext = React.createContext<Translator | null>(null);

/**
 * Hands every client component the translator for the reader's language.
 *
 * The locale comes from the root layout, which read the cookie on the server;
 * the dictionary itself is bundled, so switching language never waits on a
 * request for strings.
 */
export function I18nProvider({
  locale,
  timeZone = DEFAULT_TIME_ZONE,
  children,
}: {
  locale: Locale;
  /**
   * The viewer's timezone as the *server* read it. Deliberately not
   * `Intl.DateTimeFormat().resolvedOptions().timeZone` — the browser knowing
   * better than the server is precisely what tore the two renders apart.
   * TimeZoneCookie corrects the cookie and refreshes.
   */
  timeZone?: string;
  children: React.ReactNode;
}) {
  const value = React.useMemo(
    () => createTranslator(locale, timeZone),
    [locale, timeZone],
  );
  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

export function useI18n(): Translator {
  const value = React.useContext(I18nContext);
  if (!value) {
    throw new Error("useI18n must be used inside I18nProvider.");
  }
  return value;
}

/** A year; the choice rarely changes, and a stale one costs one click. */
const MAX_AGE = 60 * 60 * 24 * 365;

/**
 * Change language.
 *
 * Writes the cookie the server reads, then asks the server to render the
 * page again in the new language — `lang` and `dir` on <html> included, so
 * the whole layout mirrors rather than only the words changing.
 */
export function useSetLocale() {
  const router = useRouter();
  return React.useCallback(
    (locale: Locale) => {
      document.cookie = `${LOCALE_COOKIE}=${locale}; path=/; max-age=${MAX_AGE}; samesite=lax`;
      router.refresh();
    },
    [router],
  );
}

/**
 * A placeholder no real value contains, for a sentence that needs one part
 * set differently from the rest: `t("x", { name: MARK })` and then
 * `<Emphasised sentence={…}>{name}</Emphasised>`. Splitting the translated
 * sentence, rather than assembling it from fragments, is what lets the bold
 * part sit wherever the grammar of the language puts it.
 */
export const MARK = "\u0000";

export function Emphasised({
  sentence,
  children,
}: {
  sentence: string;
  children: React.ReactNode;
}) {
  const [before, after] = sentence.split(MARK);
  return (
    <>
      {before}
      <span className="font-medium text-foreground">{children}</span>
      {after}
    </>
  );
}
