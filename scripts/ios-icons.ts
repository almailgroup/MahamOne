/**
 * Writes the iPhone app's icons from the web's: every lucide-react icon that
 * src/ imports (navigation, the Create sheet, buttons, badges, pages), plus
 * the few the native shell adds, as template vector images in
 * ios/App/Icons.xcassets/<lucide-name>.imageset, and the Swift `Icon` enum
 * that names them (ios/App/DesignSystem/Icons.generated.swift). Run it again
 * when the web starts using another icon. From the repository root:
 *
 *   npx tsx --tsconfig tsconfig.scripts.json scripts/ios-icons.ts
 */
import { mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SRC = join(ROOT, 'src');
const LUCIDE = join(ROOT, 'node_modules/lucide-react/dist/esm');
const CATALOG = join(ROOT, 'ios/App/Icons.xcassets');
const SWIFT = join(ROOT, 'ios/App/DesignSystem/Icons.generated.swift');

/** Icons the native app uses that the web doesn't import. */
const EXTRA = ['ListChecks', 'Inbox'];

/** Heavier strokes the web asks for with strokeWidth (the launcher's +, the theme swatch's check). */
const BOLD: Record<string, number> = { Plus: 3, Check: 3 };

/**
 * Icons that point somewhere, mirrored in Arabic (src/index.css), by the
 * lucide class names the web's stylesheet lists.
 */
const MIRRORED = new Set([
  'arrow-right',
  'arrow-left',
  'chevron-right',
  'chevron-left',
  'chevrons-right',
  'chevrons-left',
  'arrow-up-right',
  'arrow-down-left',
  'undo-2',
  'redo-2',
  'corner-down-right',
  'log-out',
  'log-in',
  'send',
  'list-indent-increase',
]);

type Attrs = Record<string, string | number>;
type IconNode = [string, Attrs][];

function sourceFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return sourceFiles(path);
    return /\.(ts|tsx)$/.test(name) && !/\.test\.tsx?$/.test(name) ? [path] : [];
  });
}

/** The icon components src/ imports from lucide-react. */
function usedIcons(): string[] {
  const names = new Set<string>(EXTRA);
  const importRe = /import\s*(type\s*)?\{([^}]*)\}\s*from\s*['"]lucide-react['"]/g;
  for (const file of sourceFiles(SRC)) {
    const text = readFileSync(file, 'utf8');
    for (const match of text.matchAll(importRe)) {
      if (match[1]) continue;
      for (const part of match[2].split(',')) {
        const name = part.trim().replace(/\s+as\s+.*$/, '');
        if (!name || name.startsWith('type ') || /^Lucide(Icon|Props)$/.test(name)) continue;
        names.add(name);
      }
    }
  }
  return [...names].sort();
}

/** Each exported component name of lucide-react, with the file it comes from. */
function exportFiles(): Map<string, string> {
  const entry = readFileSync(join(LUCIDE, 'lucide-react.mjs'), 'utf8');
  const files = new Map<string, string>();
  for (const match of entry.matchAll(/export \{([^}]+)\} from '\.\/icons\/([a-z0-9-]+)\.mjs';/g)) {
    for (const part of match[1].split(',')) {
      const alias = /default as (\w+)/.exec(part.trim());
      if (alias) files.set(alias[1], match[2]);
    }
  }
  return files;
}

const n = (v: string | number | undefined) => Number(v ?? 0);

/** How many numbers each path command takes. */
const ARITY: Record<string, number> = {
  m: 2,
  l: 2,
  h: 1,
  v: 1,
  c: 6,
  s: 4,
  q: 4,
  t: 2,
  a: 7,
  z: 0,
};
const NUMBER = /^[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/;

/**
 * Path data rewritten with every number apart, arc flags included
 * ("a2 2 0 012-2" is "a2 2 0 0 1 2 -2"): lucide writes them compactly, as
 * SVG allows, but not every SVG reader follows that.
 */
function normalizePath(d: string): string {
  const out: string[] = [];
  let rest = d.trim();
  let command = '';
  let index = 0;
  while (rest.length) {
    rest = rest.replace(/^[\s,]+/, '');
    if (!rest.length) break;
    if (/^[a-zA-Z]/.test(rest)) {
      command = rest[0];
      rest = rest.slice(1);
      index = 0;
      out.push(command);
      continue;
    }
    const arity = ARITY[command.toLowerCase()];
    if (!arity) throw new Error(`Unexpected numbers after "${command}" in ${d}`);
    const position = index % arity;
    // An arc's large-arc and sweep flags are single digits.
    if (command.toLowerCase() === 'a' && (position === 3 || position === 4)) {
      out.push(rest[0]);
      rest = rest.slice(1);
    } else {
      const match = NUMBER.exec(rest);
      if (!match) throw new Error(`Can't read the path data at "${rest}" in ${d}`);
      out.push(match[0]);
      rest = rest.slice(match[0].length);
    }
    index += 1;
  }
  return out.join(' ').replace(/([a-zA-Z]) /g, '$1');
}

/** Every shape as a path, which every SVG reader draws the same. */
function toPath(tag: string, a: Attrs): string {
  switch (tag) {
    case 'path':
      return normalizePath(String(a.d));
    case 'circle': {
      const [cx, cy, r] = [n(a.cx), n(a.cy), n(a.r)];
      return `M${cx - r} ${cy}a${r} ${r} 0 1 0 ${2 * r} 0a${r} ${r} 0 1 0 ${-2 * r} 0z`;
    }
    case 'ellipse': {
      const [cx, cy, rx, ry] = [n(a.cx), n(a.cy), n(a.rx), n(a.ry)];
      return `M${cx - rx} ${cy}a${rx} ${ry} 0 1 0 ${2 * rx} 0a${rx} ${ry} 0 1 0 ${-2 * rx} 0z`;
    }
    case 'line':
      return `M${n(a.x1)} ${n(a.y1)}L${n(a.x2)} ${n(a.y2)}`;
    case 'polyline':
    case 'polygon': {
      const points = String(a.points)
        .trim()
        .split(/[\s,]+/)
        .map(Number);
      const pairs: string[] = [];
      for (let i = 0; i + 1 < points.length; i += 2) pairs.push(`${points[i]} ${points[i + 1]}`);
      return `M${pairs.join('L')}${tag === 'polygon' ? 'z' : ''}`;
    }
    case 'rect': {
      const [x, y, w, h] = [n(a.x), n(a.y), n(a.width), n(a.height)];
      let rx = a.rx === undefined ? n(a.ry) : n(a.rx);
      let ry = a.ry === undefined ? rx : n(a.ry);
      rx = Math.min(rx, w / 2);
      ry = Math.min(ry, h / 2);
      if (!rx || !ry) return `M${x} ${y}h${w}v${h}h${-w}z`;
      return (
        `M${x + rx} ${y}h${w - 2 * rx}a${rx} ${ry} 0 0 1 ${rx} ${ry}v${h - 2 * ry}` +
        `a${rx} ${ry} 0 0 1 ${-rx} ${ry}h${-(w - 2 * rx)}a${rx} ${ry} 0 0 1 ${-rx} ${-ry}` +
        `v${-(h - 2 * ry)}a${rx} ${ry} 0 0 1 ${rx} ${-ry}z`
      );
    }
    default:
      throw new Error(`Unknown lucide element <${tag}>`);
  }
}

/** Template images take their colour from SwiftUI; black is the ink. */
const ink = (value: string | number) => (value === 'currentColor' ? '#000000' : String(value));

function svg(node: IconNode, strokeWidth: number): string {
  const paths = node.map(([tag, attrs]) => {
    const fill = attrs.fill === undefined ? 'none' : ink(attrs.fill);
    const stroke = attrs.stroke === undefined ? '#000000' : ink(attrs.stroke);
    const width = attrs['stroke-width'] ?? attrs.strokeWidth ?? strokeWidth;
    return (
      `<path d="${toPath(tag, attrs)}" fill="${fill}" stroke="${stroke}" stroke-width="${width}" ` +
      `stroke-linecap="round" stroke-linejoin="round"/>`
    );
  });
  return (
    `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">` +
    `${paths.join('')}</svg>\n`
  );
}

const SWIFT_KEYWORDS = new Set(
  (
    'associatedtype class deinit enum extension fileprivate func import init inout internal let ' +
    'open operator private precedencegroup protocol public rethrows static struct subscript typealias ' +
    'var break case catch continue default defer do else fallthrough for guard if in repeat return ' +
    'throw switch where while as false is nil self super throws true try package some any await async'
  ).split(' '),
);

/** "ChevronsUpDown" → "chevronsUpDown", "Repeat" → "`repeat`". */
function caseName(component: string): string {
  const name = component[0].toLowerCase() + component.slice(1);
  return SWIFT_KEYWORDS.has(name) ? `\`${name}\`` : name;
}

/** "ChevronsUpDown" → "chevrons-up-down", "Loader2" → "loader-2". */
const kebab = (component: string) =>
  component
    .replace(/([a-z0-9])([A-Z])/g, '$1-$2')
    .replace(/([a-zA-Z])([0-9])/g, '$1-$2')
    .toLowerCase();

interface Generated {
  component: string;
  asset: string;
  mirrored: boolean;
}

function writeImageset(asset: string, contents: string) {
  const dir = join(CATALOG, `${asset}.imageset`);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, `${asset}.svg`), contents);
  writeFileSync(
    join(dir, 'Contents.json'),
    `${JSON.stringify(
      {
        images: [{ filename: `${asset}.svg`, idiom: 'universal' }],
        info: { author: 'xcode', version: 1 },
        properties: {
          'preserves-vector-representation': true,
          'template-rendering-intent': 'template',
        },
      },
      null,
      2,
    )}\n`,
  );
}

async function main() {
  const files = exportFiles();
  const used = usedIcons();
  rmSync(CATALOG, { recursive: true, force: true });
  mkdirSync(CATALOG, { recursive: true });
  writeFileSync(
    join(CATALOG, 'Contents.json'),
    `${JSON.stringify({ info: { author: 'xcode', version: 1 } }, null, 2)}\n`,
  );

  const generated: Generated[] = [];
  const assets = new Set<string>();
  for (const component of used) {
    const file = files.get(component);
    if (!file) throw new Error(`lucide-react has no icon called ${component}.`);
    const module = (await import(pathToFileURL(join(LUCIDE, 'icons', `${file}.mjs`)).href)) as {
      __iconData?: { name: string; node: IconNode };
    };
    const data = module.__iconData;
    if (!data) throw new Error(`No icon data in lucide-react's ${file}.mjs.`);
    const mirrored = MIRRORED.has(kebab(component)) || MIRRORED.has(data.name);
    const variants: [string, string, number][] = [[component, data.name, 2]];
    if (BOLD[component]) variants.push([`${component}Bold`, `${data.name}-bold`, BOLD[component]]);
    for (const [name, asset, width] of variants) {
      if (!assets.has(asset)) writeImageset(asset, svg(data.node, width));
      assets.add(asset);
      generated.push({ component: name, asset, mirrored });
    }
  }

  // Two web names for one icon (AlertCircle and CircleAlert): one case, and
  // the other name as an alias of it.
  const primary = new Map<string, Generated>();
  for (const g of generated) {
    const current = primary.get(g.asset);
    if (!current || (kebab(g.component) === g.asset && kebab(current.component) !== g.asset)) {
      primary.set(g.asset, g);
    }
  }
  const cases = generated.filter((g) => primary.get(g.asset) === g);
  const aliases = generated.filter((g) => primary.get(g.asset) !== g);
  const plain = (g: Generated) => caseName(g.component).replace(/`/g, '');

  const lines: string[] = [
    '// Generated by scripts/ios-icons.ts from the lucide-react icons src/ imports.',
    '// Do not edit; after the web starts using another icon, run',
    '//   npx tsx --tsconfig tsconfig.scripts.json scripts/ios-icons.ts',
    '// from the repository root.',
    '',
    '/// A lucide icon (lucide-react 1.50.0), named as the web imports it',
    '/// (`KanbanSquare` is `.kanbanSquare`). The raw value is its image in',
    '/// Icons.xcassets, a template vector drawn on the 24-point lucide grid.',
    'enum Icon: String, CaseIterable, Sendable {',
    ...cases.map((g) => `  case ${caseName(g.component)} = "${g.asset}"`),
    '',
    ...aliases.map(
      (g) => `  static let ${caseName(g.component)}: Icon = .${plain(primary.get(g.asset) ?? g)}`,
    ),
    ...(aliases.length ? [''] : []),
    '  /// Icons that point somewhere face the other way in Arabic, as on the web.',
    '  var mirrorsInRightToLeft: Bool {',
    '    switch self {',
    `    case ${cases
      .filter((g) => g.mirrored)
      .map((g) => `.${plain(g)}`)
      .join(', ')}: true`,
    '    default: false',
    '    }',
    '  }',
    '}',
    '',
  ];
  writeFileSync(SWIFT, lines.join('\n'));
  console.log(`Wrote ${assets.size} icons to ${CATALOG} and their names to ${SWIFT}.`);
}

await main();
