import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

/**
 * Guards every PostgREST embed in the data layer against foreign-key ambiguity.
 *
 * `.select("user:profiles(*)")` reads like it names a relationship, but the
 * `user:` part is only a rename of the output key. When the queried table
 * reaches the embedded table through more than one foreign key — as
 * `project_members` does (`user_id` and `added_by`) and `notifications` does
 * (`user_id` and `actor_id`) — PostgREST refuses the request as ambiguous
 * instead of guessing, and supabase-js hands back `data: null`.
 *
 * Nothing in the type system notices: the query still compiles, the page still
 * renders, and the list is simply empty. That is how project members went
 * missing while membership itself worked perfectly. So this test reads the
 * migrations for the real foreign keys and checks every embed against them.
 */

const ROOT = path.resolve(__dirname, "../..");
const MIGRATIONS = path.join(ROOT, "supabase/migrations");
const DATA = path.join(ROOT, "src");
const TYPES = path.join(ROOT, "src/lib/supabase/database.types.ts");

type ForeignKey = { table: string; column: string; target: string };

/**
 * Every inline `references public.<table>` in the migrations, and every
 * table's primary key.
 *
 * The primary key matters because it is what separates a junction table from
 * an ordinary one: PostgREST reads a table whose composite primary key is two
 * foreign keys as a many-to-many relationship between them.
 */
function schema(): { keys: ForeignKey[]; primaryKeys: Map<string, string[]> } {
  const keys: ForeignKey[] = [];
  const primaryKeys = new Map<string, string[]>();

  for (const file of readdirSync(MIGRATIONS).sort()) {
    if (!file.endsWith(".sql")) continue;
    let table: string | null = null;

    for (const line of readFileSync(path.join(MIGRATIONS, file), "utf8").split("\n")) {
      const opens = line.match(/^create table (?:if not exists )?public\.(\w+)\s*\(/i);
      if (opens) {
        table = opens[1];
        continue;
      }
      if (table && /^\s*\)\s*;/.test(line)) {
        table = null;
        continue;
      }
      if (!table) continue;

      const column = line.match(
        /^\s*(\w+)\s+\w+[^,]*?references\s+public\.(\w+)\s*\(/i,
      );
      if (column) keys.push({ table, column: column[1], target: column[2] });

      // `id uuid primary key …`
      const inlinePk = line.match(/^\s*(\w+)\s+\w+[^,]*\bprimary key\b/i);
      if (inlinePk) primaryKeys.set(table, [inlinePk[1]]);

      // `primary key (a, b)`
      const tablePk = line.match(/^\s*primary key\s*\(([^)]+)\)/i);
      if (tablePk) {
        primaryKeys.set(
          table,
          tablePk[1].split(",").map((part) => part.trim()),
        );
      }
    }
  }

  return { keys, primaryKeys };
}

type Embed = { parent: string; target: string; hints: string[] };

/**
 * Walk a `select()` string, pairing each embed with the table it hangs off.
 *
 * `"*, assignments:task_assignments(user:profiles(*))"` under `.from("tasks")`
 * yields tasks→task_assignments and task_assignments→profiles.
 */
function embedsOf(select: string, from: string): Embed[] {
  const found: Embed[] = [];

  const walk = (source: string, parent: string) => {
    let depth = 0;
    let start = 0;
    let name = "";

    for (let i = 0; i < source.length; i += 1) {
      const char = source[i];

      if (char === "(") {
        if (depth === 0) {
          name = source.slice(start, i).trim();
          start = i + 1;
        }
        depth += 1;
        continue;
      }

      if (char === ")") {
        depth -= 1;
        if (depth === 0) {
          // `alias:table!hint!inner` — drop the alias, keep the hints.
          const [, spec = name] = name.match(/^(?:[\w]+:)?(.+)$/) ?? [];
          const [target, ...hints] = spec.split("!").map((part) => part.trim());
          found.push({ parent, target, hints });
          walk(source.slice(start, i), target);
          start = i + 1;
          name = "";
        }
        continue;
      }

      if (char === "," && depth === 0) {
        start = i + 1;
        name = "";
      }
    }
  };

  walk(select, from);
  return found;
}

/** Source files that talk to PostgREST, with each `.from().select()` pair. */
function queries(): { file: string; from: string; select: string }[] {
  const files: string[] = [];
  const collect = (dir: string) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) collect(full);
      else if (/\.tsx?$/.test(entry.name)) files.push(full);
    }
  };
  collect(DATA);

  const pairs: { file: string; from: string; select: string }[] = [];

  for (const file of files) {
    const source = readFileSync(file, "utf8");

    // A select can be a named constant — `.select(TASK_WITH_ASSIGNEES)` — and
    // the check is worthless if extracting one hides it. Resolve the string
    // constants declared in the same file.
    const constants = new Map(
      [...source.matchAll(/const\s+(\w+)\s*(?::\s*string\s*)?=\s*\n?\s*["']([^"']*)["']\s*;/g)].map(
        (m) => [m[1], m[2]],
      ),
    );
    // Each select belongs to the nearest `.from()` above it, which is how the
    // query builder chains read — including when the chain is split across a
    // `let query = …` and a later `.select()`.
    const froms = [...source.matchAll(/\.from\(\s*["'](\w+)["']\s*\)/g)];

    for (const select of source.matchAll(
      /\.select\(\s*(?:["']([^"']*)["']|(\w+))/g,
    )) {
      const literal = select[1] ?? constants.get(select[2] ?? "");
      if (literal === undefined) continue;

      const at = select.index ?? 0;
      const owner = froms.filter((f) => (f.index ?? 0) < at).pop();
      if (!owner) continue;
      pairs.push({ file: path.relative(ROOT, file), from: owner[1], select: literal });
    }
  }

  return pairs;
}

describe("PostgREST embeds", () => {
  const { keys, primaryKeys } = schema();

  /**
   * A foreign key that can carry a many-to-many route.
   *
   * PostgREST's rule is that the junction table's foreign keys must be *part
   * of* its composite primary key — not that the key is made of nothing else.
   * This used to require every key column to be a foreign key, which missed
   * `comment_reactions`: keyed on comment, person and emoji, it is a junction
   * between comments and profiles all the same, and a bare profiles(*) from
   * a comment would have been refused while this test passed.
   */
  const inCompositeKey = (table: string, column: string) => {
    const pk = primaryKeys.get(table) ?? [];
    return pk.length >= 2 && pk.includes(column);
  };

  /**
   * Every way PostgREST can get from one table to another.
   *
   * Not just the foreign keys on the table itself: a third table holding a key
   * to each of them is a junction, and PostgREST offers that as a
   * many-to-many embed too. So a table with a single foreign key to `profiles`
   * can still be ambiguous about it — `personal_notes` has one, and two other
   * tables (its lines and its shares) point at both a note and a profile,
   * which makes four routes and one refused query.
   */
  const routes = (parent: string, target: string): string[] => {
    const direct = keys
      .filter((key) => key.table === parent && key.target === target)
      .map((key) => `${parent}.${key.column}`);

    const viaJunction = keys
      .filter((key) => key.target === parent && inCompositeKey(key.table, key.column))
      .flatMap((toParent) =>
        keys
          .filter(
            (key) =>
              key.table === toParent.table &&
              key.target === target &&
              inCompositeKey(key.table, key.column),
          )
          .map((toTarget) => `${toParent.table}.${toTarget.column}`),
      );

    return [...direct, ...viaJunction];
  };

  it("knows the relationships that make a bare embed ambiguous", () => {
    // If these ever read empty the parser has stopped seeing the schema, and
    // every other assertion below would pass for the wrong reason.
    expect(routes("project_members", "profiles").sort()).toEqual([
      "project_members.added_by",
      "project_members.user_id",
    ]);
    expect(routes("notifications", "profiles").sort()).toEqual([
      "notifications.actor_id",
      "notifications.user_id",
    ]);

    // One of its own, and one more through the shares table, which points at
    // both a note and a profile inside its primary key. This is the shape that
    // took My List down: a single foreign key is not the same as a single
    // route. (`added_by` is a key to profiles too, but outside the primary key,
    // so PostgREST does not route through it.)
    expect(routes("personal_notes", "profiles").sort()).toEqual([
      "personal_note_shares.user_id",
      "personal_notes.user_id",
    ]);

    // A third key column does not stop a table being a junction.
    expect(routes("comments", "profiles").sort()).toEqual([
      "comment_reactions.user_id",
      "comments.user_id",
    ]);
  });

  it("names the foreign key whenever more than one leads to the same table", () => {
    const ambiguous: string[] = [];

    for (const query of queries()) {
      for (const embed of embedsOf(query.select, query.from)) {
        const paths = routes(embed.parent, embed.target);
        if (paths.length < 2) continue;

        // `!inner` and `!left` pick a join type, not a foreign key.
        const hint = embed.hints.find((h) => h !== "inner" && h !== "left");
        if (!hint) {
          ambiguous.push(
            `${query.file}: ${embed.parent} → ${embed.target} reaches through ` +
              `${paths.join(" and ")}, so the embed must say which`,
          );
          continue;
        }

        const named = paths.some((path) => {
          const [table, column] = path.split(".");
          return hint === column || hint === `${table}_${column}_fkey`;
        });
        expect(
          named,
          `${query.file}: "${hint}" is not a foreign key from ${embed.parent} to ${embed.target}`,
        ).toBe(true);
      }
    }

    expect(ambiguous).toEqual([]);
  });
});

describe("database.types.ts", () => {
  const source = readFileSync(TYPES, "utf8");

  /** The tables the hand-written types describe. */
  const described = new Set(
    [...source.matchAll(/^ {6}(\w+): \{$/gm)].map((m) => m[1]),
  );

  const declared = new Set(
    [
      ...source.matchAll(
        /foreignKeyName: "(\w+)";\s*columns: \["(\w+)"\];\s*referencedRelation: "(\w+)"/g,
      ),
    ].map((m) => `${m[1]}|${m[2]}|${m[3]}`),
  );

  /**
   * The types claim to match `supabase gen types typescript`, and the embed
   * check above is only as good as what they declare: an undeclared second
   * foreign key is exactly how an ambiguous embed type-checks cleanly.
   */
  it("declares every foreign key the migrations create", () => {
    const undeclared = schema().keys
      .filter((key) => described.has(key.table))
      .filter(
        (key) =>
          !declared.has(
            `${key.table}_${key.column}_fkey|${key.column}|${key.target}`,
          ),
      )
      .map((key) => `${key.table}.${key.column} → ${key.target}`);

    expect(undeclared).toEqual([]);
  });
});
