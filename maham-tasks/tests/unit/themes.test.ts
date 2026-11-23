import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

import { MAHAM_ONE_THEMES } from "@/lib/maham-one-themes";
import { DARK_THEME_IDS, THEMES, THEME_IDS, modeOf, themeColor } from "@/lib/themes";

/**
 * Maham Tasks wears Maham One's themes.
 *
 * Their colours are generated from Maham One's recipes into
 * maham-one-themes.css, and Maham One's own tests measure them (contrast,
 * charts, every theme different) and keep the generated files up to date
 * (src/lib/maham-tasks-themes.test.ts at the repository root). These check
 * what Maham Tasks adds: that the picker offers exactly those themes, that
 * the stylesheet has each one, and that the app's colour names point at
 * Maham One's roles.
 */
const read = (file: string) =>
  readFileSync(path.resolve(__dirname, "../../src/app", file), "utf8")
    // Comments out, so the one above a block is not read as part of its selector.
    .replace(/\/\*[\s\S]*?\*\//g, "");

const THEME_CSS = read("maham-one-themes.css");
const GLOBALS = read("globals.css");

/** The selectors of every rule in the theme stylesheet. */
const SELECTORS = [...THEME_CSS.matchAll(/(^|\n)([^{}\n@][^{}]*?)\{/g)].map((m) =>
  m[2].split(",").map((part) => part.trim()),
);

describe("the theme picker", () => {
  it("offers Maham One's twenty themes, ten light and ten dark", () => {
    expect(THEMES.map((theme) => theme.id)).toEqual(MAHAM_ONE_THEMES.map((theme) => theme.id));
    expect(THEMES.filter((theme) => theme.mode === "light")).toHaveLength(10);
    expect(THEMES.filter((theme) => theme.mode === "dark")).toHaveLength(10);
  });

  it("can set and clear every class it uses, the device's light and dark included", () => {
    expect(THEME_IDS).toEqual(expect.arrayContaining(["light", "dark", "classic", "midnight"]));
    expect(new Set(THEME_IDS).size).toBe(THEME_IDS.length);
  });

  it("knows each theme's family, and reads an unknown one as light", () => {
    expect(modeOf("midnight")).toBe("dark");
    expect(modeOf("dark")).toBe("dark");
    expect(modeOf("gulf")).toBe("light");
    expect(modeOf("light")).toBe("light");
    expect(modeOf("ocean")).toBe("light");
    expect(modeOf(undefined)).toBe("light");
  });

  it("gives the browser's toolbar Maham One's colour for each", () => {
    const classic = MAHAM_ONE_THEMES.find((theme) => theme.id === "classic")!;
    const midnight = MAHAM_ONE_THEMES.find((theme) => theme.id === "midnight")!;
    expect(themeColor("light")).toBe(classic.themeColor);
    expect(themeColor("dark")).toBe(midnight.themeColor);
    expect(themeColor("system")).toBe(classic.themeColor);
  });
});

describe("the theme stylesheet", () => {
  it("has a rule for every theme, Classic on :root", () => {
    expect(SELECTORS).toContainEqual([":root"]);
    for (const theme of THEMES.filter((theme) => theme.id !== "classic")) {
      expect(
        SELECTORS.some((selector) => selector.includes(`.${theme.id}`)),
        `.${theme.id} has no colours`,
      ).toBe(true);
    }
  });

  it("shows Midnight for the device's dark setting", () => {
    expect(SELECTORS).toContainEqual([".midnight", ".dark"]);
  });

  it("switches on every dark: style for exactly the dark themes", () => {
    const variant = THEME_CSS.match(/@custom-variant dark \(&:is\(([^)]*)\)\);/);
    expect(variant).not.toBeNull();
    const named = [...variant![1].matchAll(/\.([\w-]+) \*/g)].map((m) => m[1]).sort();
    expect(named).toEqual(["dark", ...DARK_THEME_IDS].sort());
  });

  it("gives the dark themes dark form controls", () => {
    for (const id of DARK_THEME_IDS) {
      expect(THEME_CSS, `.${id} missing color-scheme: dark`).toMatch(
        new RegExp(`\\.${id}(,\\s*\\.dark)?\\s*\\{\\s*color-scheme: dark;`),
      );
    }
  });
});

describe("the app's colour names", () => {
  it("load Maham One's themes", () => {
    expect(GLOBALS).toContain('@import "./maham-one-themes.css";');
  });

  it("are Maham One's roles", () => {
    const roles: Record<string, string> = {
      "--card": "var(--color-surface)",
      "--foreground": "var(--color-slate-900)",
      "--primary": "var(--color-primary-solid)",
      "--primary-foreground": "var(--color-on-primary)",
      "--muted-foreground": "var(--color-slate-500)",
      "--border": "var(--color-slate-200)",
      "--input": "var(--color-slate-300)",
      "--ring": "var(--color-primary-500)",
      "--chrome": "var(--color-shell)",
    };
    for (const [name, value] of Object.entries(roles)) {
      expect(GLOBALS, name).toContain(`${name}: ${value};`);
    }
  });

  it("keep late work amber, apart from the main colour", () => {
    expect(GLOBALS).toContain("--warning: var(--color-amber-700);");
    expect(GLOBALS).not.toMatch(/--primary: var\(--color-amber/);
  });
});
