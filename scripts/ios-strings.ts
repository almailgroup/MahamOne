/**
 * Writes the iPhone app's Arabic strings, `ios/Shared/Resources/ar.json`, from
 * the web's dictionaries in `src/i18n/ar/*.ts`. From the repository root:
 *
 *   npx tsx --tsconfig tsconfig.scripts.json scripts/ios-strings.ts
 *
 * The dictionaries are merged the way `loadArabic()` in `src/i18n/index.ts`
 * merges them: Vite's `import.meta.glob` lists the files sorted by path, and
 * `Object.assign` lets a later file's entry replace an earlier one. Each
 * entry is the English key with either the Arabic text or its plural forms
 * (`{ zero, one, two, few, many, other }`). Run it again whenever a
 * dictionary changes.
 */
import { mkdirSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import type { Dictionary, PluralForms } from '../src/i18n/index';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SOURCE = join(ROOT, 'src/i18n/ar');
const TARGET = join(ROOT, 'ios/Shared/Resources/ar.json');

const PLURAL_FORMS = ['zero', 'one', 'two', 'few', 'many', 'other'] as const;

function check(key: string, value: unknown, file: string): string | PluralForms {
  if (typeof value === 'string') return value;
  if (value && typeof value === 'object') {
    const forms = value as Record<string, unknown>;
    const unknown = Object.keys(forms).filter(
      (name) => !(PLURAL_FORMS as readonly string[]).includes(name),
    );
    if (unknown.length) throw new Error(`${file}: "${key}" has unknown forms ${unknown}`);
    if (typeof forms.other !== 'string') throw new Error(`${file}: "${key}" has no "other" form`);
    for (const name of PLURAL_FORMS) {
      const form = forms[name];
      if (form !== undefined && typeof form !== 'string') {
        throw new Error(`${file}: "${key}" form "${name}" is not text`);
      }
    }
    return value as PluralForms;
  }
  throw new Error(`${file}: "${key}" is neither text nor plural forms`);
}

async function main() {
  // Sorted by path, as import.meta.glob lists them.
  const files = readdirSync(SOURCE)
    .filter((name) => name.endsWith('.ts'))
    .map((name) => join(SOURCE, name))
    .sort();
  const merged: Dictionary = {};
  let plurals = 0;
  for (const path of files) {
    const module = (await import(pathToFileURL(path).href)) as { default: Dictionary };
    const dictionary = module.default;
    if (!dictionary || typeof dictionary !== 'object') {
      throw new Error(`${path} has no default dictionary`);
    }
    Object.assign(merged, dictionary);
    for (const [key, value] of Object.entries(dictionary)) check(key, value, path);
  }
  for (const value of Object.values(merged)) if (typeof value !== 'string') plurals += 1;
  mkdirSync(dirname(TARGET), { recursive: true });
  writeFileSync(TARGET, `${JSON.stringify(merged, null, 2)}\n`);
  const count = Object.keys(merged).length;
  console.log(
    `Wrote ${count} entries (${plurals} with plural forms) from ${files.length} files to ${TARGET}.`,
  );
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
