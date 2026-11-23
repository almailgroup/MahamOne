/**
 * Maham Tasks (maham-tasks/) wears Maham One's themes. Its stylesheet and its
 * theme picker are generated from the recipes in ./themes, so the two apps
 * show the same twenty themes in the same colours, and a change to a theme
 * here reaches Maham Tasks by running
 *
 *   npx tsx --tsconfig tsconfig.scripts.json scripts/maham-tasks-themes.ts
 *
 * A test (maham-tasks-themes.test.ts) fails while the files in maham-tasks
 * are not what this makes.
 *
 * Maham Tasks applies a theme as a class on <html> (next-themes), so each
 * theme is a block of the same colour variables Maham One sets at run time
 * (`--color-slate-*`, `--color-primary-*`, `--color-surface`…). Classic's sit
 * on :root, so every theme starts from the same values. `light` and `dark`
 * are the names next-themes gives the device's setting: Classic and Midnight,
 * Maham One's defaults.
 */
import { DARK_THEMES, LIGHT_THEMES, resolveTheme, type ThemeId } from './themes';
import { toHex } from './oklch';

/** The stylesheet, relative to the repository. */
export const TASKS_THEME_CSS = 'maham-tasks/src/app/maham-one-themes.css';
/** The picker's list, relative to the repository. */
export const TASKS_THEME_LIST = 'maham-tasks/src/lib/maham-one-themes.ts';

const HOW =
  "Generated from Maham One's themes (src/lib/themes.ts) by\n" +
  ' * scripts/maham-tasks-themes.ts. Change the themes there and run\n' +
  ' * `npx tsx --tsconfig tsconfig.scripts.json scripts/maham-tasks-themes.ts`\n' +
  ' * from the repository root, rather than editing this file.';

const ALL: ThemeId[] = [...LIGHT_THEMES, ...DARK_THEMES];

/** next-themes' names for the device's setting, shown as Maham One's defaults. */
const ALIASES: Partial<Record<ThemeId, string>> = { midnight: 'dark' };

function block(selector: string, id: ThemeId): string {
  const theme = resolveTheme(id);
  const lines = [`  color-scheme: ${theme.scheme};`];
  for (const [name, value] of Object.entries(theme.vars)) lines.push(`  ${name}: ${value};`);
  return `${selector} {\n${lines.join('\n')}\n}`;
}

/** Maham Tasks' theme stylesheet. */
export function tasksThemeCss(): string {
  const dark = DARK_THEMES.flatMap((id) => [ALIASES[id], id]).filter(Boolean) as string[];
  const variant = dark.map((name) => `.${name} *`).join(', ');
  const blocks = ALL.map((id) => {
    if (id === 'classic') return block(':root', id);
    const names = [id, ALIASES[id]].filter(Boolean).map((name) => `.${name}`);
    return block(names.join(',\n'), id);
  });
  return (
    `/*\n * ${HOW}\n */\n\n` +
    `/* \`dark:\` answers to every dark theme. */\n` +
    `@custom-variant dark (&:is(${variant}));\n\n` +
    `${blocks.join('\n\n')}\n`
  );
}

/** The picker's list: each theme's id, family and swatch. */
export function tasksThemeList(): string {
  const rows = ALL.map((id) => {
    const theme = resolveTheme(id);
    const swatch = {
      ground: toHex(theme.vars['--color-shell']),
      card: toHex(theme.vars['--color-surface']),
      accent: toHex(theme.vars['--color-primary-solid']),
    };
    return (
      `  {\n` +
      `    id: "${id}",\n` +
      `    mode: "${theme.scheme}",\n` +
      `    swatch: { ground: "${swatch.ground}", card: "${swatch.card}", accent: "${swatch.accent}" },\n` +
      `    themeColor: "${toHex(theme.themeColor)}",\n` +
      `  },`
    );
  });
  return (
    `/*\n * ${HOW}\n */\n\n` +
    `export type MahamOneThemeId =\n${ALL.map((id) => `  | "${id}"`).join('\n')};\n\n` +
    `export const MAHAM_ONE_THEMES: readonly {\n` +
    `  id: MahamOneThemeId;\n` +
    `  mode: "light" | "dark";\n` +
    `  /** The backdrop, a card on it, and the main action. */\n` +
    `  swatch: { ground: string; card: string; accent: string };\n` +
    `  /** The browser's toolbar colour. */\n` +
    `  themeColor: string;\n` +
    `}[] = [\n${rows.join('\n')}\n];\n`
  );
}
