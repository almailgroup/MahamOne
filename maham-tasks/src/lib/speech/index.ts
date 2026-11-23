import type { Locale } from "@/lib/i18n";

/**
 * Which language the recogniser should listen for.
 *
 * Deliberately not `localeTag()`. That one is pinned to `en-AE` and
 * `ar-AE-u-nu-latn` because it formats dates and numbers, and a speech
 * recogniser will not take a Unicode extension like `-u-nu-latn` at all — it
 * wants a plain BCP-47 language tag off the list its engine supports.
 *
 * `en-US` rather than `en-AE`, which is not a locale any speech engine
 * models: English here is spoken in every accent there is, and the general
 * American model is the best-trained of the ones on offer. Arabic is
 * `ar-AE` because Gulf Arabic genuinely is a separate model, and dictating
 * into the Modern Standard one gets a transcript nobody wrote.
 */
export function speechLocale(locale: Locale): string {
  return locale === "ar" ? "ar-AE" : "en-US";
}

/**
 * What went wrong, as a message key.
 *
 * The browser's own codes are not for reading — "not-allowed" is true of both
 * a person who declined the microphone and a page served over plain HTTP.
 */
export function speechError(code: string): string {
  switch (code) {
    case "not-allowed":
    case "service-not-allowed":
      return "voice.blocked";
    case "audio-capture":
      return "voice.noMicrophone";
    case "network":
      return "voice.offline";
    case "language-not-supported":
      return "voice.noLanguage";
    // "no-speech" is not a failure: somebody pressed the button and thought
    // better of it. "aborted" is this code stopping the recogniser itself.
    case "no-speech":
    case "aborted":
      return "";
    default:
      return "voice.failed";
  }
}
