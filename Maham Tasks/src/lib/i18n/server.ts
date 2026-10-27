import "server-only";

import { cache } from "react";
import { cookies } from "next/headers";

import {
  DEFAULT_LOCALE,
  DEFAULT_TIME_ZONE,
  LOCALE_COOKIE,
  TIME_ZONE_COOKIE,
  createTranslator,
  isLocale,
  type Locale,
} from "./index";

/** The reader's language, from the cookie the selector sets. */
export const getLocale = cache(async (): Promise<Locale> => {
  const value = (await cookies()).get(LOCALE_COOKIE)?.value;
  return isLocale(value) ? value : DEFAULT_LOCALE;
});

/**
 * The viewer's timezone, from the cookie TimeZoneCookie writes.
 *
 * A value that is not a zone this runtime knows would make every Intl call
 * throw, so it is checked before it is trusted — the cookie is user input.
 */
export const getTimeZone = cache(async (): Promise<string> => {
  const value = (await cookies()).get(TIME_ZONE_COOKIE)?.value;
  if (!value) return DEFAULT_TIME_ZONE;
  try {
    new Intl.DateTimeFormat("en-CA", { timeZone: value });
    return value;
  } catch {
    return DEFAULT_TIME_ZONE;
  }
});

/** Server-side translator for Server Components and Server Actions. */
export const getI18n = cache(async () =>
  createTranslator(await getLocale(), await getTimeZone()),
);
