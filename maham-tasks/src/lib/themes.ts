import type { TranslationKey } from "@/lib/i18n";
import { MAHAM_ONE_THEMES, type MahamOneThemeId } from "@/lib/maham-one-themes";

/**
 * The themes a person can choose: Maham One's twenty, in the same colours.
 *
 * Their colours and this list's swatches are generated from Maham One's own
 * theme recipes (maham-one-themes.css and maham-one-themes.ts, made by
 * scripts/maham-tasks-themes.ts at the repository root), so the two apps
 * always look alike. This file adds what Maham Tasks needs on top: the label
 * of each and the names next-themes uses.
 *
 * "Match this device" is next-themes' `system`, which resolves to `light` or
 * `dark`: Classic and Midnight, Maham One's defaults.
 */
export type ThemeMode = "light" | "dark";

export type ThemeOption = {
  id: MahamOneThemeId;
  mode: ThemeMode;
  label: TranslationKey;
  /** What the picker draws: the backdrop, a card on it, and the main action. */
  swatch: { ground: string; card: string; accent: string };
};

export const THEMES: readonly ThemeOption[] = MAHAM_ONE_THEMES.map((theme) => ({
  id: theme.id,
  mode: theme.mode,
  label: `theme.${theme.id}` as TranslationKey,
  swatch: theme.swatch,
}));

/** The device's setting, as next-themes names it, and the theme it shows. */
const DEVICE: Record<"light" | "dark", MahamOneThemeId> = {
  light: "classic",
  dark: "midnight",
};

/**
 * Every class next-themes may put on <html>. `light` and `dark` are among
 * them so that choosing a theme clears the device's one.
 */
export const THEME_IDS: string[] = [...THEMES.map((theme) => theme.id), "light", "dark"];

export const DARK_THEME_IDS = THEMES.filter((theme) => theme.mode === "dark").map(
  (theme) => theme.id,
);

function resolve(themeId: string | undefined): (typeof MAHAM_ONE_THEMES)[number] | undefined {
  const id = themeId === "light" || themeId === "dark" ? DEVICE[themeId] : themeId;
  return MAHAM_ONE_THEMES.find((theme) => theme.id === id);
}

export function modeOf(themeId: string | undefined): ThemeMode {
  return resolve(themeId)?.mode ?? "light";
}

/** The browser's toolbar colour for a theme, as Maham One sets it. */
export function themeColor(themeId: string | undefined): string {
  return (resolve(themeId) ?? resolve("classic"))!.themeColor;
}
