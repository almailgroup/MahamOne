/**
 * What the recogniser is asked for, and what it says when it cannot.
 *
 * Both are small, and both were wrong in an obvious way first: the language
 * tag the rest of the app formats dates with is not one a speech engine will
 * take, and the browser's own error codes are not sentences anybody should
 * read.
 */

import { describe, expect, test } from "vitest";

import { speechError, speechLocale } from "@/lib/speech";
import { localeTag } from "@/lib/i18n";
import { en } from "@/lib/i18n/en";

describe("speechLocale", () => {
  test("asks for Gulf Arabic, not Modern Standard", () => {
    expect(speechLocale("ar")).toBe("ar-AE");
  });

  test("asks for a general English model", () => {
    expect(speechLocale("en")).toBe("en-US");
  });

  /**
   * `localeTag("ar")` is `ar-AE-u-nu-latn`, which is a formatting tag: the
   * Unicode extension picks Latin digits. A recogniser will not take it.
   */
  test("is not the formatting tag", () => {
    expect(speechLocale("ar")).not.toBe(localeTag("ar"));
    expect(speechLocale("ar")).not.toContain("-u-");
    expect(speechLocale("en")).not.toContain("-u-");
  });

  test("gives a plain BCP-47 tag in both languages", () => {
    for (const locale of ["en", "ar"] as const) {
      expect(speechLocale(locale)).toMatch(/^[a-z]{2}-[A-Z]{2}$/);
    }
  });
});

describe("speechError", () => {
  test("a declined microphone says how to undo it", () => {
    expect(speechError("not-allowed")).toBe("voice.blocked");
    expect(speechError("service-not-allowed")).toBe("voice.blocked");
  });

  test("names the ones a person can act on", () => {
    expect(speechError("audio-capture")).toBe("voice.noMicrophone");
    expect(speechError("network")).toBe("voice.offline");
    expect(speechError("language-not-supported")).toBe("voice.noLanguage");
  });

  /**
   * Pressing the button and saying nothing is not a failure, and neither is
   * this code stopping the recogniser itself. Both arrive as errors and
   * neither is worth a line of red text.
   */
  test("silence and a deliberate stop are not errors", () => {
    expect(speechError("no-speech")).toBe("");
    expect(speechError("aborted")).toBe("");
  });

  test("anything unrecognised still says something", () => {
    expect(speechError("some-future-code")).toBe("voice.failed");
  });

  test("every message it can return exists in the dictionary", () => {
    const codes = [
      "not-allowed", "service-not-allowed", "audio-capture", "network",
      "language-not-supported", "no-speech", "aborted", "whatever",
    ];
    for (const code of codes) {
      const key = speechError(code);
      if (key) expect(Object.keys(en)).toContain(key);
    }
  });
});
