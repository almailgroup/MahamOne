import { describe, expect, it } from "vitest";

import { en } from "@/lib/i18n/en";
import { ar } from "@/lib/i18n/ar";
import {
  LOCALES,
  createTranslator,
  directionFor,
  isLocale,
  localeTag,
} from "@/lib/i18n";

const placeholders = (text: string) =>
  [...text.matchAll(/\{(\w+)\}/g)].map((match) => match[1]).sort();

describe("dictionaries", () => {
  it("Arabic has every English key", () => {
    for (const key of Object.keys(en)) expect(ar, key).toHaveProperty(key);
  });

  it("Arabic adds nothing but the plural forms English does not need", () => {
    const extras = Object.keys(ar).filter((key) => !(key in en));
    for (const key of extras) {
      const stem = key.replace(/_(zero|two|few|many)$/, "");
      expect(stem, key).not.toBe(key);
      expect(en, `${stem}_other`).toHaveProperty(`${stem}_other`);
    }
  });

  /** Read the same in both languages: an address, a product name. */
  const SAME_IN_BOTH = new Set([
    "auth.emailPlaceholder",
    "team.emailPlaceholder",
    // A product name, not a phrase: the same in both, like Google Drive.
    "nav.assistant",
  ]);

  it("nothing is left empty or untranslated", () => {
    for (const [key, value] of Object.entries(ar) as [string, string][]) {
      expect(value.trim(), key).not.toBe("");
      if (SAME_IN_BOTH.has(key)) continue;
      // A key copied over verbatim is a placeholder someone forgot — unless the
      // English is itself a proper noun or symbol that reads the same in both.
      if (/[A-Za-z]{3,}/.test(value) && !/[؀-ۿ]/.test(value)) {
        expect(value, `${key} is still English`).not.toBe(en[key as keyof typeof en]);
      }
    }
  });

  it("every {placeholder} in English is in the Arabic too", () => {
    for (const key of Object.keys(en) as (keyof typeof en)[]) {
      const wanted = placeholders(en[key]);
      const found = placeholders(ar[key]);
      // A plural form may spell the number out — "مهمتان" for two — and so
      // drop {n}; it may not invent a placeholder English does not fill.
      const plural = /_(zero|one|two|few|many|other)$/.test(key);
      const without = (names: string[]) => names.filter((name) => name !== "n");
      expect(plural ? without(found) : found, key).toEqual(plural ? without(wanted) : wanted);
      for (const name of found) expect(wanted, key).toContain(name);
    }
  });

  it("counted phrases have an _other form in both languages", () => {
    const stems = new Set(
      Object.keys(en)
        .filter((key) => /_(zero|one|two|few|many|other)$/.test(key))
        .map((key) => key.replace(/_(zero|one|two|few|many|other)$/, "")),
    );
    for (const stem of stems) {
      expect(en, `${stem}_other`).toHaveProperty(`${stem}_other`);
      expect(ar, `${stem}_other`).toHaveProperty(`${stem}_other`);
    }
  });
});

describe("createTranslator", () => {
  it("fills placeholders and leaves unknown ones visible", () => {
    const { t } = createTranslator("en");
    expect(t("bell.labelUnread", { n: 3 })).toBe("Notifications, 3 unread");
    expect(t("error.reference", {})).toBe("Reference: {digest}");
  });

  it("picks the Arabic plural category from the count", () => {
    const { tn } = createTranslator("ar");
    // Arabic distinguishes 0, 1, 2, 3–10, 11–99 and 100+.
    const forms = new Set([0, 1, 2, 5, 15, 100].map((n) => tn("count.tasks", n)));
    expect(forms.size).toBeGreaterThanOrEqual(4);
    expect(tn("count.tasks", 1)).not.toContain("{n}");
  });

  it("falls back to _other when a language does not need a category", () => {
    const { tn } = createTranslator("en");
    expect(tn("count.tasks", 0)).toBe("0 tasks");
    expect(tn("count.tasks", 1)).toBe("1 task");
    expect(tn("count.tasks", 2)).toBe("2 tasks");
  });
});

describe("locale metadata", () => {
  it("Arabic is right-to-left with Western digits", () => {
    expect(directionFor("ar")).toBe("rtl");
    expect(directionFor("en")).toBe("ltr");
    expect(new Intl.NumberFormat(localeTag("ar")).format(1234)).toBe("1,234");
  });

  /**
   * Both tags are named rather than left to the runtime. Leaving English unset
   * meant Intl asked whoever was running it: Node on Vercel said en-US and the
   * browser said en-GB, the two spelled the same date differently, and React
   * threw the server's HTML away (hydration error #418).
   */
  it("names a locale for both languages, so no runtime picks its own", () => {
    for (const locale of LOCALES) {
      expect(localeTag(locale), locale).toBeTruthy();
      expect(() => new Intl.DateTimeFormat(localeTag(locale)), locale).not.toThrow();
    }
  });

  it("carries the viewer's timezone, defaulting to UTC until the cookie exists", () => {
    expect(createTranslator("en").timeZone).toBe("UTC");
    expect(createTranslator("en", "Asia/Dubai").timeZone).toBe("Asia/Dubai");
  });

  it("rejects anything that is not a supported locale", () => {
    for (const locale of LOCALES) expect(isLocale(locale)).toBe(true);
    expect(isLocale("fr")).toBe(false);
    expect(isLocale(undefined)).toBe(false);
    expect(isLocale("AR")).toBe(false);
  });
});
