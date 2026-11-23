import { readFileSync } from "node:fs";
import { readdir } from "node:fs/promises";
import path from "node:path";
import { describe, expect, it } from "vitest";

const SRC = path.resolve(__dirname, "../../src");

async function walk(dir: string): Promise<string[]> {
  const entries = await readdir(dir, { withFileTypes: true });
  const files = await Promise.all(
    entries.map(async (entry) => {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) return walk(full);
      return /\.tsx?$/.test(entry.name) ? [full] : [];
    }),
  );
  return files.flat();
}

const isClientModule = (file: string) => {
  const head = readFileSync(file, "utf8").slice(0, 200);
  return /^\s*["']use client["']/.test(head);
};

/** Resolve an `@/…` import to a file on disk, trying the usual extensions. */
function resolveAlias(spec: string): string | null {
  if (!spec.startsWith("@/")) return null;
  const base = path.join(SRC, spec.slice(2));
  for (const candidate of [
    `${base}.ts`, `${base}.tsx`,
    path.join(base, "index.ts"), path.join(base, "index.tsx"),
  ]) {
    try {
      readFileSync(candidate);
      return candidate;
    } catch {
      // try the next extension
    }
  }
  return null;
}

function importsOf(file: string): string[] {
  const source = readFileSync(file, "utf8");
  return [...source.matchAll(/from\s+["'](@\/[^"']+)["']/g)].map((m) => m[1]);
}

/**
 * The bug this exists to prevent.
 *
 * Every export of a "use client" module becomes a *client reference* when a
 * Server Component imports it — an opaque marker, not the function. Calling one
 * during a server render throws at runtime. It happened here once: a plain
 * helper (`initialsFrom`) lived in a "use client" file, the /team page called
 * it on the server, and the page 500'd in production.
 *
 * TypeScript and ESLint both pass on that code, which is exactly why it needs
 * its own check. A server module may *render* a client component, so only
 * value imports that are not components are a problem — a component is
 * PascalCase by convention, so anything else crossing the line is flagged.
 */
describe("client/server boundary", () => {
  it("no server module imports a non-component value from a client module", async () => {
    const files = await walk(SRC);
    const offences: string[] = [];

    for (const file of files) {
      if (isClientModule(file)) continue; // client importing client is fine
      if (file.endsWith(".d.ts")) continue;

      const source = readFileSync(file, "utf8");

      for (const spec of importsOf(file)) {
        const target = resolveAlias(spec);
        if (!target || !isClientModule(target)) continue;

        // Every clause for this specifier, not just the first: a file can
        // import a module more than once, and an early components-only clause
        // would otherwise hide a later one that pulls a plain helper across.
        const escaped = spec.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&");
        const clauses = [
          ...source.matchAll(
            new RegExp(`import\\s+([^;]+?)\\s+from\\s+["']${escaped}["']`, "g"),
          ),
        ];

        for (const clause of clauses) {
          const names = clause[1];
          if (/^\s*type\s/.test(names)) continue; // type-only, erased at build

          const named = [...names.matchAll(/([A-Za-z_$][\w$]*)(?:\s+as\s+([A-Za-z_$][\w$]*))?/g)]
            .map((m) => m[2] ?? m[1])
            .filter((name) => name !== "type");

          for (const name of named) {
            // PascalCase reads as a component, which a server module may render.
            if (/^[A-Z]/.test(name)) continue;
            offences.push(
              `${path.relative(SRC, file)} imports { ${name} } from ${spec} — that module is "use client", so ${name} is a client reference on the server.`,
            );
          }
        }
      }
    }

    expect(offences).toEqual([]);
  });
});
