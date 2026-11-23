/*
 * Generated from Maham One's themes (src/lib/themes.ts) by
 * scripts/maham-tasks-themes.ts. Change the themes there and run
 * `npx tsx --tsconfig tsconfig.scripts.json scripts/maham-tasks-themes.ts`
 * from the repository root, rather than editing this file.
 */

export type MahamOneThemeId =
  | "classic"
  | "gulf"
  | "sky"
  | "turquoise"
  | "oasis"
  | "sand"
  | "sunset"
  | "rose"
  | "lavender"
  | "graphite"
  | "midnight"
  | "deep-sea"
  | "lagoon"
  | "oasis-night"
  | "desert-night"
  | "ember"
  | "rose-night"
  | "amethyst"
  | "charcoal"
  | "black";

export const MAHAM_ONE_THEMES: readonly {
  id: MahamOneThemeId;
  mode: "light" | "dark";
  /** The backdrop, a card on it, and the main action. */
  swatch: { ground: string; card: string; accent: string };
  /** The browser's toolbar colour. */
  themeColor: string;
}[] = [
  {
    id: "classic",
    mode: "light",
    swatch: { ground: "#eff1f6", card: "#ffffff", accent: "#4f39f6" },
    themeColor: "#4f46e5",
  },
  {
    id: "gulf",
    mode: "light",
    swatch: { ground: "#ebf2fa", card: "#ffffff", accent: "#155dfc" },
    themeColor: "#155dfc",
  },
  {
    id: "sky",
    mode: "light",
    swatch: { ground: "#e8f3fa", card: "#ffffff", accent: "#0069a8" },
    themeColor: "#0069a8",
  },
  {
    id: "turquoise",
    mode: "light",
    swatch: { ground: "#e8f4f4", card: "#ffffff", accent: "#00786f" },
    themeColor: "#00786f",
  },
  {
    id: "oasis",
    mode: "light",
    swatch: { ground: "#eaf4ee", card: "#ffffff", accent: "#008236" },
    themeColor: "#008236",
  },
  {
    id: "sand",
    mode: "light",
    swatch: { ground: "#f7f0e5", card: "#ffffff", accent: "#a65f00" },
    themeColor: "#a65f00",
  },
  {
    id: "sunset",
    mode: "light",
    swatch: { ground: "#faeee9", card: "#ffffff", accent: "#ca3500" },
    themeColor: "#ca3500",
  },
  {
    id: "rose",
    mode: "light",
    swatch: { ground: "#f8eef1", card: "#ffffff", accent: "#c6005c" },
    themeColor: "#c6005c",
  },
  {
    id: "lavender",
    mode: "light",
    swatch: { ground: "#f3eff8", card: "#ffffff", accent: "#7f22fe" },
    themeColor: "#7f22fe",
  },
  {
    id: "graphite",
    mode: "light",
    swatch: { ground: "#f1f1f4", card: "#ffffff", accent: "#18181b" },
    themeColor: "#18181b",
  },
  {
    id: "midnight",
    mode: "dark",
    swatch: { ground: "#070b19", card: "#161b2a", accent: "#4f39f6" },
    themeColor: "#0d1220",
  },
  {
    id: "deep-sea",
    mode: "dark",
    swatch: { ground: "#000e20", card: "#0b1e31", accent: "#155dfc" },
    themeColor: "#031527",
  },
  {
    id: "lagoon",
    mode: "dark",
    swatch: { ground: "#000f12", card: "#0a2022", accent: "#00786f" },
    themeColor: "#021619",
  },
  {
    id: "oasis-night",
    mode: "dark",
    swatch: { ground: "#070d09", card: "#161c19", accent: "#008236" },
    themeColor: "#0d1310",
  },
  {
    id: "desert-night",
    mode: "dark",
    swatch: { ground: "#100b07", card: "#1f1b16", accent: "#a65f00" },
    themeColor: "#16120d",
  },
  {
    id: "ember",
    mode: "dark",
    swatch: { ground: "#0d0908", card: "#1d1817", accent: "#ca3500" },
    themeColor: "#140f0e",
  },
  {
    id: "rose-night",
    mode: "dark",
    swatch: { ground: "#0f090b", card: "#1f181b", accent: "#c6005c" },
    themeColor: "#160f12",
  },
  {
    id: "amethyst",
    mode: "dark",
    swatch: { ground: "#0e0916", card: "#1e1927", accent: "#7f22fe" },
    themeColor: "#15101d",
  },
  {
    id: "charcoal",
    mode: "dark",
    swatch: { ground: "#0b0b0b", card: "#1b1b1b", accent: "#e5e5e5" },
    themeColor: "#121212",
  },
  {
    id: "black",
    mode: "dark",
    swatch: { ground: "#000000", card: "#070707", accent: "#0069a8" },
    themeColor: "#000000",
  },
];
