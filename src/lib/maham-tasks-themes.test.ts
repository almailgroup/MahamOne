import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import {
  TASKS_THEME_CSS,
  TASKS_THEME_LIST,
  tasksThemeCss,
  tasksThemeList,
} from './maham-tasks-themes';
import { DARK_THEMES, LIGHT_THEMES, resolveTheme } from './themes';

/**
 * Maham Tasks' themes are Maham One's: its files are generated from these
 * recipes and must not drift. If this fails after changing a theme, run
 * `npx tsx --tsconfig tsconfig.scripts.json scripts/maham-tasks-themes.ts`.
 */
describe("Maham Tasks' themes", () => {
  it('are up to date with Maham One’s', () => {
    expect(readFileSync(TASKS_THEME_CSS, 'utf8')).toBe(tasksThemeCss());
    expect(readFileSync(TASKS_THEME_LIST, 'utf8')).toBe(tasksThemeList());
  });

  it('give every theme its colours, Classic as the starting point', () => {
    const css = tasksThemeCss();
    expect(css).toContain(':root {\n  color-scheme: light;');
    for (const id of [...LIGHT_THEMES, ...DARK_THEMES].filter((id) => id !== 'classic')) {
      expect(css).toContain(`.${id}`);
    }
    // The device's dark setting (next-themes calls it "dark") shows Midnight.
    expect(css).toContain('.midnight,\n.dark {\n  color-scheme: dark;');
    expect(css).toContain(
      `  --color-primary-solid: ${resolveTheme('gulf').vars['--color-primary-solid']};`,
    );
  });

  it('switch on dark: styles for exactly the dark themes', () => {
    const variant = /@custom-variant dark \(&:is\((.*)\)\);/.exec(tasksThemeCss())?.[1];
    expect(variant?.split(', ').sort()).toEqual(
      ['dark', ...DARK_THEMES].map((name) => `.${name} *`).sort(),
    );
  });
});
