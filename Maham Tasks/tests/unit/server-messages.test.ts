import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

import { describe, expect, it } from "vitest";

import { en } from "@/lib/i18n/en";
import { describeDatabaseError } from "@/lib/action-result";

/**
 * Server Actions return their messages as dictionary keys, and the client
 * translates them. A sentence typed straight into a `fail(...)` would reach
 * an Arabic reader in English, so this reads the source and refuses any
 * string literal that looks like one.
 */
const roots = ["src/lib/data", "src/lib/auth", "src/lib/validation.ts"];

function sources(): string[] {
  const files: string[] = [];
  for (const root of roots) {
    if (root.endsWith(".ts")) {
      files.push(root);
      continue;
    }
    for (const name of readdirSync(root)) {
      if (name.endsWith(".ts")) files.push(join(root, name));
    }
  }
  return files;
}

/** Internal wording that never reaches a reader. */
const INTERNAL = [
  /^Worker replied/,
  /^Your account has no profile yet/,
  /^[A-Za-z0-9]+$/,
  /^I deleted the wrong one$/,
  /^Choose your password$/,
  /^Due today$/,
  /^Follow-up due$/,
  /^Task assigned$/,
  /^Task overdue$/,
];

describe("server messages", () => {
  it("are dictionary keys, not English sentences", () => {
    const offenders: string[] = [];
    for (const file of sources()) {
      const text = readFileSync(file, "utf8");
      for (const match of text.matchAll(/"([A-Z][^"\n]{8,})"/g)) {
        const literal = match[1];
        if (INTERNAL.some((pattern) => pattern.test(literal))) continue;
        if (/^[a-z]+(\.[A-Za-z0-9_]+)+$/.test(literal)) continue;
        offenders.push(`${file}: ${literal}`);
      }
    }
    expect(offenders).toEqual([]);
  });

  it("describe database errors with keys the dictionary has", () => {
    for (const code of ["42501", "23505", "23503", "23514", "PGRST116", undefined]) {
      expect(en).toHaveProperty(describeDatabaseError({ code }));
    }
  });

  it("recognise the messages the SQL raises", () => {
    expect(
      describeDatabaseError({
        code: "42501",
        message: "Only a manager or admin can reopen a completed task.",
      }),
    ).toBe("kanban.reopenGate");
    expect(
      describeDatabaseError({
        code: "23514",
        message: "Cannot remove the last admin. Promote another member first.",
      }),
    ).toBe("db.lastAdmin");
  });

  it("pass an unexpected database message through untouched", () => {
    expect(describeDatabaseError({ code: "42501", message: "custom policy text" })).toBe(
      "custom policy text",
    );
  });
});
