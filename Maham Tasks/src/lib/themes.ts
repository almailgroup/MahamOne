import type { TranslationKey } from "@/lib/i18n";

/**
 * The themes a person can choose, and the one fact the code needs about
 * each: whether it is light or dark.
 *
 * Each theme's colours live in globals.css as a block of tokens under its own
 * class. This list is the other half — the picker's order, the labels, the
 * swatch it draws — and a unit test holds the two to each other, so a theme
 * cannot be offered without colours or coloured without being offered.
 *
 * Light and Dark are the house style: monochrome, nothing saturated. The
 * others tint the surfaces or the main action, and nothing else. Amber means
 * late or urgent work in every one of them, which is why no theme here is
 * warm enough to be confused with it.
 */
export type ThemeMode = "light" | "dark";

export type ThemeOption = {
  id: string;
  mode: ThemeMode;
  label: TranslationKey;
  /** What the picker draws: the page, a card on it, and the main action. */
  swatch: { ground: string; card: string; accent: string };
};

export const THEMES: readonly ThemeOption[] = [
  {
    id: "light",
    mode: "light",
    label: "theme.light",
    swatch: { ground: "#f3f3f4", card: "#ffffff", accent: "#111217" },
  },
  {
    id: "paper",
    mode: "light",
    label: "theme.paper",
    swatch: { ground: "#f3efe7", card: "#fffdf8", accent: "#2b2620" },
  },
  {
    id: "ocean",
    mode: "light",
    label: "theme.ocean",
    swatch: { ground: "#edf2f8", card: "#ffffff", accent: "#1d4ed8" },
  },
  {
    id: "lavender",
    mode: "light",
    label: "theme.lavender",
    swatch: { ground: "#f2f0f8", card: "#ffffff", accent: "#6d28d9" },
  },
  {
    id: "mint",
    mode: "light",
    label: "theme.mint",
    swatch: { ground: "#ecf5f0", card: "#ffffff", accent: "#047857" },
  },
  {
    id: "rose",
    mode: "light",
    label: "theme.rose",
    swatch: { ground: "#f8eff3", card: "#ffffff", accent: "#be185d" },
  },
  {
    id: "sky",
    mode: "light",
    label: "theme.sky",
    swatch: { ground: "#eaf4f7", card: "#ffffff", accent: "#0e7490" },
  },
  {
    id: "teal",
    mode: "light",
    label: "theme.teal",
    swatch: { ground: "#ebf5f3", card: "#ffffff", accent: "#0f766e" },
  },
  {
    id: "indigo",
    mode: "light",
    label: "theme.indigo",
    swatch: { ground: "#eff0fa", card: "#ffffff", accent: "#4338ca" },
  },
  {
    id: "orchid",
    mode: "light",
    label: "theme.orchid",
    swatch: { ground: "#f7eff8", card: "#ffffff", accent: "#a21caf" },
  },
  {
    id: "sage",
    mode: "light",
    label: "theme.sage",
    swatch: { ground: "#eff2ec", card: "#ffffff", accent: "#3f6212" },
  },
  {
    id: "slate",
    mode: "light",
    label: "theme.slate",
    swatch: { ground: "#f0f2f5", card: "#ffffff", accent: "#334155" },
  },
  {
    id: "ruby",
    mode: "light",
    label: "theme.ruby",
    swatch: { ground: "#f9efef", card: "#ffffff", accent: "#b91c1c" },
  },
  {
    id: "navy",
    mode: "light",
    label: "theme.navy",
    swatch: { ground: "#eef1f6", card: "#ffffff", accent: "#1e3a5f" },
  },
  {
    id: "ink",
    mode: "light",
    label: "theme.ink",
    swatch: { ground: "#ffffff", card: "#f0f0f0", accent: "#000000" },
  },
  {
    id: "dark",
    mode: "dark",
    label: "theme.dark",
    swatch: { ground: "#2c2d32", card: "#3a3b42", accent: "#f2f3f6" },
  },
  {
    id: "midnight",
    mode: "dark",
    label: "theme.midnight",
    swatch: { ground: "#111a2e", card: "#1a2440", accent: "#93b6ff" },
  },
  {
    id: "black",
    mode: "dark",
    label: "theme.black",
    swatch: { ground: "#000000", card: "#161618", accent: "#f5f5f7" },
  },
  {
    id: "forest",
    mode: "dark",
    label: "theme.forest",
    swatch: { ground: "#11211a", card: "#1a2f25", accent: "#86d9a8" },
  },
  {
    id: "plum",
    mode: "dark",
    label: "theme.plum",
    swatch: { ground: "#1c1426", card: "#271c35", accent: "#c4a5ff" },
  },
  {
    id: "graphite",
    mode: "dark",
    label: "theme.graphite",
    swatch: { ground: "#1b1f24", card: "#252a31", accent: "#cbd5e1" },
  },
  {
    id: "rosewood",
    mode: "dark",
    label: "theme.rosewood",
    swatch: { ground: "#24141b", card: "#311c25", accent: "#f9a8d4" },
  },
  {
    id: "lagoon",
    mode: "dark",
    label: "theme.lagoon",
    swatch: { ground: "#0f2226", card: "#173035", accent: "#5eead4" },
  },
  {
    id: "cosmos",
    mode: "dark",
    label: "theme.cosmos",
    swatch: { ground: "#15162e", card: "#1f2142", accent: "#a5b4fc" },
  },
  {
    id: "dim",
    mode: "dark",
    label: "theme.dim",
    swatch: { ground: "#34373e", card: "#3f434b", accent: "#e5e7eb" },
  },
  {
    id: "garnet",
    mode: "dark",
    label: "theme.garnet",
    swatch: { ground: "#241012", card: "#321719", accent: "#fca5a5" },
  },
  {
    id: "moss",
    mode: "dark",
    label: "theme.moss",
    swatch: { ground: "#161c12", card: "#20281a", accent: "#b5dd8b" },
  },
  {
    id: "abyss",
    mode: "dark",
    label: "theme.abyss",
    swatch: { ground: "#0a1c28", card: "#11293a", accent: "#7dd3fc" },
  },
  {
    id: "espresso",
    mode: "dark",
    label: "theme.espresso",
    swatch: { ground: "#1e1814", card: "#2a221d", accent: "#e5e1dc" },
  },
  {
    id: "fjord",
    mode: "dark",
    label: "theme.fjord",
    swatch: { ground: "#2e3440", card: "#3b4252", accent: "#88c0d0" },
  },
];

export const THEME_IDS = THEMES.map((theme) => theme.id);

/** The ones that switch on every `dark:` style, and dark form controls. */
export const DARK_THEME_IDS = THEMES.filter((theme) => theme.mode === "dark").map(
  (theme) => theme.id,
);

/**
 * Light or dark, for the things that only know those two — the toasts, the
 * command palette's "switch to dark". An unknown name is read as light, which
 * is what the page itself falls back to.
 */
export function modeOf(themeId: string | undefined): ThemeMode {
  return THEMES.find((theme) => theme.id === themeId)?.mode ?? "light";
}
