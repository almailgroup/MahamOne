/**
 * Writes the iPhone app's themes (ios/App/DesignSystem/Themes.generated.swift)
 * from the web's (src/lib/themes.ts): all twenty, every colour variable, in
 * Display P3, the space Safari draws the saturated OKLCH shades in. Run it
 * again whenever the web's themes or their names change. From the
 * repository root:
 *
 *   npx tsx --tsconfig tsconfig.scripts.json scripts/ios-themes.ts
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  allThemes,
  DARK_THEMES,
  DEFAULT_DARK,
  DEFAULT_LIGHT,
  LIGHT_THEMES,
} from '../src/lib/themes';
import { parseColor } from '../src/lib/oklch';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const OUT = join(ROOT, 'ios/App/DesignSystem/Themes.generated.swift');
const NAMES = join(ROOT, 'src/features/theme/names.ts');

type Vector = [number, number, number];

/** OKLCH to linear sRGB, not clipped: P3 holds more than sRGB. */
function oklchToLinearSrgb(l: number, c: number, h: number): Vector {
  const a = c * Math.cos((h * Math.PI) / 180);
  const b = c * Math.sin((h * Math.PI) / 180);
  const l_ = (l + 0.3963377774 * a + 0.2158037573 * b) ** 3;
  const m_ = (l - 0.1055613458 * a - 0.0638541728 * b) ** 3;
  const s_ = (l - 0.0894841775 * a - 1.291485548 * b) ** 3;
  return [
    4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_,
    -1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_,
    -0.0041960863 * l_ - 0.7034186147 * m_ + 1.707614701 * s_,
  ];
}

const toLinear = (c: number) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);

/** The transfer curve of sRGB, which Display P3 shares. */
function encode(v: number): number {
  const sign = Math.sign(v);
  const x = Math.abs(v);
  return sign * (x <= 0.0031308 ? 12.92 * x : 1.055 * x ** (1 / 2.4) - 0.055);
}

/** Linear sRGB to gamma-encoded Display P3, 0–1. */
function linearSrgbToP3([r, g, b]: Vector): Vector {
  const p: Vector = [
    0.8224621 * r + 0.177538 * g,
    0.0331941 * r + 0.9668058 * g,
    0.0170827 * r + 0.0723974 * g + 0.9105199 * b,
  ];
  return p.map((v) => Math.min(1, Math.max(0, encode(v)))) as Vector;
}

interface P3 {
  rgb: Vector;
  opacity: number;
}

const HEX = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i;
const RGB = /^rgb\(\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*(?:\/\s*([\d.]+)(%?))?\s*\)$/i;
const MIX = /^color-mix\(\s*in\s+oklab\s*,\s*(.+?)\s+([\d.]+)%\s*,\s*transparent\s*\)$/i;

/**
 * A theme value in Display P3: an OKLCH or hex colour; `rgb(r g b / a)`;
 * or `color-mix(in oklab, X n%, transparent)`, which is X at n% opacity.
 */
function toP3(value: string): P3 {
  const text = value.trim();
  const mix = MIX.exec(text);
  if (mix) {
    const base = toP3(mix[1]);
    return { rgb: base.rgb, opacity: base.opacity * (Number(mix[2]) / 100) };
  }
  const rgb = RGB.exec(text);
  if (rgb) {
    const channels = [rgb[1], rgb[2], rgb[3]].map((n) => toLinear(Number(n) / 255)) as Vector;
    const alpha = rgb[4] === undefined ? 1 : Number(rgb[4]) / (rgb[5] ? 100 : 1);
    return { rgb: linearSrgbToP3(channels), opacity: alpha };
  }
  const hex = HEX.exec(text);
  if (hex) {
    let h = hex[1];
    if (h.length === 3) h = [...h].map((c) => c + c).join('');
    const channels = [0, 2, 4].map((i) =>
      toLinear(parseInt(h.slice(i, i + 2), 16) / 255),
    ) as Vector;
    return { rgb: linearSrgbToP3(channels), opacity: 1 };
  }
  if (/^oklch\(/i.test(text)) {
    const { l, c, h } = parseColor(text);
    return { rgb: linearSrgbToP3(oklchToLinearSrgb(l, c, h)), opacity: 1 };
  }
  throw new Error(`Can't convert this theme value to Display P3: ${value}`);
}

/** 0.93341 → "0.9334", 1 → "1". */
function num(n: number): string {
  const fixed = n.toFixed(4).replace(/0+$/, '').replace(/\.$/, '');
  return fixed === '-0' ? '0' : fixed;
}

/** "deep-sea" → "deepSea". */
const caseName = (id: string) => id.replace(/-([a-z])/g, (_, c: string) => c.toUpperCase());

/** "--color-primary-50" → "primary-50", "--scrollbar-thumb" → "scrollbar-thumb". */
const varName = (key: string) => key.replace(/^--color-/, '').replace(/^--/, '');

/** The English names of the themes, read from names.ts (without loading the i18n). */
function themeNames(): Record<string, string> {
  const source = readFileSync(NAMES, 'utf8');
  const names: Record<string, string> = {};
  for (const match of source.matchAll(/^\s*'?([a-z-]+)'?:\s*msg\('([^']+)'\)/gm)) {
    names[match[1]] = match[2];
  }
  return names;
}

const swiftString = (s: string) => `"${s.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;

function main() {
  const themes = allThemes();
  const names = themeNames();
  const order = Object.keys(themes[0].vars);
  for (const theme of themes) {
    const keys = Object.keys(theme.vars);
    if (keys.length !== order.length || keys.some((k, i) => k !== order[i])) {
      throw new Error(`Theme ${theme.id} doesn't set the same variables as ${themes[0].id}.`);
    }
    if (!names[theme.id]) throw new Error(`No name for theme ${theme.id} in names.ts.`);
  }

  const lines: string[] = [];
  const out = (line = '') => lines.push(line);

  out('// Generated by scripts/ios-themes.ts from src/lib/themes.ts and');
  out('// src/features/theme/names.ts. Do not edit; after the web changes, run');
  out('//   npx tsx --tsconfig tsconfig.scripts.json scripts/ios-themes.ts');
  out('// from the repository root.');
  out();
  out('import SwiftUI');
  out();
  out("/// The web's twenty interface themes, light then dark.");
  out('enum ThemeID: String, CaseIterable, Codable, Sendable {');
  for (const theme of themes) {
    const name = caseName(theme.id);
    out(name === theme.id ? `  case ${name}` : `  case ${name} = ${swiftString(theme.id)}`);
  }
  out();
  out('  /// Whether the theme is light or dark.');
  out('  var scheme: ColorScheme {');
  out('    switch self {');
  out(`    case ${LIGHT_THEMES.map((id) => `.${caseName(id)}`).join(', ')}: .light`);
  out(`    case ${DARK_THEMES.map((id) => `.${caseName(id)}`).join(', ')}: .dark`);
  out('    }');
  out('  }');
  out();
  out("  /// The theme's name, an English key: show it with `t(theme.nameKey)`.");
  out('  var nameKey: String {');
  out('    switch self {');
  for (const theme of themes)
    out(`    case .${caseName(theme.id)}: ${swiftString(names[theme.id])}`);
  out('    }');
  out('  }');
  out();
  out(
    `  static let lightThemes: [ThemeID] = [${LIGHT_THEMES.map((id) => `.${caseName(id)}`).join(', ')}]`,
  );
  out(
    `  static let darkThemes: [ThemeID] = [${DARK_THEMES.map((id) => `.${caseName(id)}`).join(', ')}]`,
  );
  out(`  static let defaultLight: ThemeID = .${caseName(DEFAULT_LIGHT)}`);
  out(`  static let defaultDark: ThemeID = .${caseName(DEFAULT_DARK)}`);
  out('}');
  out();
  out('/// The colour variables every theme sets, named as on the web without');
  out('/// `--color-`, in the order of the arrays in `ThemeColors`.');
  out('enum ThemeVariables {');
  out('  static let names: [String] = [');
  for (const key of order) out(`    ${swiftString(varName(key))},`);
  out('  ]');
  out('}');
  out();
  out("/// Every theme's colours in Display P3, in the order of `ThemeVariables.names`.");
  out('enum ThemeColors {');
  out('  static func colors(of theme: ThemeID) -> [Color] {');
  out('    switch theme {');
  for (const theme of themes) out(`    case .${caseName(theme.id)}: ${caseName(theme.id)}`);
  out('    }');
  out('  }');
  for (const theme of themes) {
    out();
    out(`  // ${names[theme.id]} (${theme.scheme})`);
    out(`  private static let ${caseName(theme.id)}: [Color] = [`);
    for (const key of order) {
      const css = theme.vars[key];
      const { rgb, opacity } = toP3(css);
      out(
        `    Color(.displayP3, red: ${num(rgb[0])}, green: ${num(rgb[1])}, blue: ${num(rgb[2])}, opacity: ${num(opacity)}),  // ${varName(key)} ${css}`,
      );
    }
    out('  ]');
  }
  out('}');
  out();

  writeFileSync(OUT, lines.join('\n'));
  console.log(`Wrote ${themes.length} themes × ${order.length} colours to ${OUT}.`);
}

main();
