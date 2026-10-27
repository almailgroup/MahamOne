import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

import { DARK_THEME_IDS, THEMES, THEME_IDS, modeOf } from "@/lib/themes";

/**
 * Every theme, measured.
 *
 * A theme is a list of colours in globals.css and an entry in lib/themes.ts.
 * These read the CSS and check the two agree, and then check each theme the
 * way a person would notice if it were wrong: text that cannot be read, a
 * form field whose edge disappears, a main button the same colour as a late
 * task.
 */
const CSS = readFileSync(path.resolve(__dirname, "../../src/app/globals.css"), "utf8")
  // Comments out, so the one above a block is not read as part of its selector.
  .replace(/\/\*[\s\S]*?\*\//g, "");

/**
 * The colour tokens declared under exactly this selector, across every block
 * that names it on its own. A grouped rule — `.dark, .midnight { … }` — is
 * not the theme's palette and is skipped.
 */
function block(selector: string): Record<string, string> {
  const found: Record<string, string> = {};
  for (const rule of CSS.matchAll(/(^|\n)([^{}\n@][^{}]*?)\{([^}]*)\}/g)) {
    if (rule[2].trim() !== selector) continue;
    for (const m of rule[3].matchAll(/--([\w-]+):\s*(#[0-9a-fA-F]{6})\s*;/g)) {
      found[m[1]] = m[2];
    }
  }
  return found;
}

/** What a theme actually renders with: its own tokens over the light ones. */
function tokens(id: string): Record<string, string> {
  const base = block(":root");
  if (id === "light") return base;
  return { ...base, ...block(`.${id}`) };
}

function luminance(hex: string): number {
  const [r, g, b] = [1, 3, 5].map((i) => {
    const c = parseInt(hex.slice(i, i + 2), 16) / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function contrast(a: string, b: string): number {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

function hue(hex: string): { h: number; s: number } {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255);
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const d = max - min;
  const l = (max + min) / 2;
  const s = d === 0 ? 0 : d / (1 - Math.abs(2 * l - 1));
  let h = 0;
  if (d !== 0) {
    if (max === r) h = ((g - b) / d) % 6;
    else if (max === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
  }
  return { h: (h * 60 + 360) % 360, s };
}

/** `over` laid on `base` at this opacity, as the browser composites it. */
function mix(base: string, over: string, alpha: number): string {
  const channel = (hex: string, i: number) => parseInt(hex.slice(i, i + 2), 16);
  return (
    "#" +
    [1, 3, 5]
      .map((i) => Math.round(channel(base, i) * (1 - alpha) + channel(over, i) * alpha))
      .map((v) => v.toString(16).padStart(2, "0"))
      .join("")
  );
}

describe("the theme list and the stylesheet", () => {
  it("has colours for every theme it offers", () => {
    for (const id of THEME_IDS) {
      if (id === "light") continue;
      expect(Object.keys(block(`.${id}`)).length, `.${id} has no tokens`).toBeGreaterThan(10);
    }
  });

  it("switches on every dark: style for exactly the dark themes", () => {
    const variant = CSS.match(/@custom-variant dark \(&:is\(([^)]*)\)\);/);
    expect(variant).not.toBeNull();
    const named = [...variant![1].matchAll(/\.([\w-]+) \*/g)].map((m) => m[1]).sort();
    expect(named).toEqual([...DARK_THEME_IDS].sort());
  });

  it("gives the dark themes dark form controls and dark shadows", () => {
    for (const id of DARK_THEME_IDS) {
      expect(CSS, `.${id} missing from color-scheme: dark`).toMatch(
        new RegExp(`\\.${id}(,|\\s*\\{)[^}]*?color-scheme: dark`, "s"),
      );
    }
    const shadows = CSS.match(/((?:\s*\.[\w-]+,?)+)\s*\{\s*--shadow-xs: 0 1px 2px 0 rgb\(0 0 0/);
    expect(shadows).not.toBeNull();
    const named = [...shadows![1].matchAll(/\.([\w-]+)/g)].map((m) => m[1]).sort();
    expect(named).toEqual([...DARK_THEME_IDS].sort());
  });

  it("reads an unknown theme as light", () => {
    expect(modeOf("midnight")).toBe("dark");
    expect(modeOf("paper")).toBe("light");
    expect(modeOf("system")).toBe("light");
    expect(modeOf(undefined)).toBe("light");
  });
});

describe.each(THEMES.map((theme) => [theme.id]))("the %s theme", (id) => {
  const t = tokens(id);
  const AA = 4.5;

  it("keeps body text readable on every surface it sits on", () => {
    for (const surface of ["background", "card", "chrome", "muted", "accent"]) {
      expect(
        contrast(t.foreground, t[surface]),
        `foreground on ${surface}`,
      ).toBeGreaterThanOrEqual(AA);
    }
    expect(contrast(t["card-foreground"], t.card)).toBeGreaterThanOrEqual(AA);
    expect(contrast(t["popover-foreground"], t.popover)).toBeGreaterThanOrEqual(AA);
    expect(contrast(t["accent-foreground"], t.accent)).toBeGreaterThanOrEqual(AA);
  });

  it("keeps secondary text readable too", () => {
    for (const surface of ["background", "card", "chrome", "muted"]) {
      expect(
        contrast(t["muted-foreground"], t[surface]),
        `muted-foreground on ${surface}`,
      ).toBeGreaterThanOrEqual(AA);
    }
  });

  it("puts readable text on the main button", () => {
    expect(contrast(t["primary-foreground"], t.primary)).toBeGreaterThanOrEqual(AA);
    expect(contrast(t["destructive-foreground"], t.destructive)).toBeGreaterThanOrEqual(AA);
  });

  it("draws checkboxes and the focus ring at 3:1, as WCAG 1.4.11 asks", () => {
    // Text fields are filled wells with no outline now; `input` is the ring
    // of an unticked checkbox, the one control with nothing else to show it.
    expect(contrast(t.input, t.card), "checkbox ring on card").toBeGreaterThanOrEqual(3);
    expect(contrast(t.ring, t.background), "ring on background").toBeGreaterThanOrEqual(3);
  });

  it("keeps late work legible wherever it is flagged", () => {
    expect(contrast(t.warning, t.card), "warning on card").toBeGreaterThanOrEqual(AA);
    expect(contrast(t.warning, t["warning-surface"]), "warning on its tint").toBeGreaterThanOrEqual(AA);
  });

  it("never makes the main action look like a late task", () => {
    // Amber means late or urgent work in every theme. A main button anywhere
    // from orange to yellow would make that mean nothing.
    const { h, s } = hue(t.primary);
    const amberish = s > 0.25 && h >= 15 && h <= 65;
    expect(amberish, `primary ${t.primary} is hue ${h.toFixed(0)}°`).toBe(false);
  });

  it("marks the phone's current page clearly on its soft tint", () => {
    // The bottom bar's current page sits in a wash of the main colour over
    // the frame, 24% at its strongest, with its icon in the main colour and
    // its label in the body colour. Icons are held to 3:1 (WCAG 1.4.11), the
    // label to text, against the strongest part of the wash.
    const tint = mix(t.chrome, t.primary, 0.24);
    expect(contrast(t.primary, tint), "icon on its tint").toBeGreaterThanOrEqual(3);
    expect(contrast(t.foreground, tint), "label on its tint").toBeGreaterThanOrEqual(AA);
  });

  it("sets the page apart from the frame around it", () => {
    // No line divides them any more; the step in tone has to be there.
    expect(t.chrome).not.toBe(t.background);
  });
});
