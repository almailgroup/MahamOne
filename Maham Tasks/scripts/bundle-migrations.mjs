#!/usr/bin/env node
/**
 * Concatenates supabase/migrations/*.sql, in filename order, into
 * supabase/setup.sql — a single file that can be pasted into the Supabase SQL
 * editor in one go for first-time setup.
 *
 * The migrations remain the source of truth. Re-run `npm run db:bundle` after
 * adding or editing one so the bundle cannot drift.
 */
import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const DIR = "supabase/migrations";
const OUT = "supabase/setup.sql";

const files = readdirSync(DIR)
  .filter((name) => name.endsWith(".sql"))
  .sort();

if (files.length === 0) {
  console.error(`No migrations found in ${DIR}`);
  process.exit(1);
}

const header = `-- ---------------------------------------------------------------------------
-- Almailgroup Task Management Portal — complete database setup
--
-- GENERATED FILE. Do not edit by hand: run \`npm run db:bundle\` instead.
-- Source of truth is ${DIR}/, concatenated here in filename order.
--
-- First-time setup: paste this whole file into the Supabase SQL editor and
-- run it. It is safe to re-run; every statement is idempotent.
--
-- Bundled migrations:
${files.map((name) => `--   ${name}`).join("\n")}
-- ---------------------------------------------------------------------------

`;

const body = files
  .map((name) => {
    const sql = readFileSync(join(DIR, name), "utf8").trimEnd();
    return `-- =========================================================================\n-- ${name}\n-- =========================================================================\n\n${sql}\n`;
  })
  .join("\n");

writeFileSync(OUT, `${header}${body}`);
console.log(`Bundled ${files.length} migrations into ${OUT}`);
