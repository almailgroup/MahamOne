/**
 * Writes Maham Tasks' theme stylesheet and theme list from Maham One's themes
 * (src/lib/maham-tasks-themes.ts says why). From the repository root:
 *
 *   npx tsx --tsconfig tsconfig.scripts.json scripts/maham-tasks-themes.ts
 */
import { writeFileSync } from 'node:fs';
import {
  TASKS_THEME_CSS,
  TASKS_THEME_LIST,
  tasksThemeCss,
  tasksThemeList,
} from '../src/lib/maham-tasks-themes';

writeFileSync(TASKS_THEME_CSS, tasksThemeCss());
writeFileSync(TASKS_THEME_LIST, tasksThemeList());
console.log(`Wrote ${TASKS_THEME_CSS} and ${TASKS_THEME_LIST}.`);
