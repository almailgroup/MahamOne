import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

import {
  REACTIONS,
  isReaction,
  summariseReactions,
  toggledReactions,
} from "@/lib/reactions";

const ME = "me";

describe("the reactions on offer", () => {
  it("are exactly the ones the database accepts", () => {
    // The picker and the check constraint are two copies of one list. If they
    // drift, the picker offers a reaction the insert refuses.
    const sql = readFileSync(
      path.resolve(__dirname, "../../supabase/migrations/20261002000033_comment_reactions.sql"),
      "utf8",
    );
    const check = sql.match(/emoji in \(([^)]*)\)/);
    expect(check).not.toBeNull();
    const allowed = [...check![1].matchAll(/'([^']+)'/g)].map((m) => m[1]);
    expect(allowed).toEqual([...REACTIONS]);
  });

  it("refuses anything else", () => {
    expect(isReaction("👍")).toBe(true);
    expect(isReaction("🔥")).toBe(false);
    expect(isReaction(undefined)).toBe(false);
  });
});

describe("summariseReactions", () => {
  it("groups rows into one chip per emoji, with a count", () => {
    const chips = summariseReactions(
      [
        { emoji: "👍", user_id: "a" },
        { emoji: "👍", user_id: "b" },
        { emoji: "🎉", user_id: "a" },
      ],
      ME,
    );
    expect(chips.map((chip) => [chip.emoji, chip.count])).toEqual([
      ["👍", 2],
      ["🎉", 1],
    ]);
  });

  it("keeps the picker's order, so a chip does not jump as people react", () => {
    const chips = summariseReactions(
      [
        { emoji: "🎉", user_id: "a" },
        { emoji: "🎉", user_id: "b" },
        { emoji: "🎉", user_id: "c" },
        { emoji: "✅", user_id: "a" },
      ],
      ME,
    );
    expect(chips.map((chip) => chip.emoji)).toEqual(["✅", "🎉"]);
  });

  it("marks the ones that are the reader's", () => {
    const [chip] = summariseReactions([{ emoji: "🙏", user_id: ME }], ME);
    expect(chip.mine).toBe(true);
  });

  it("drops anything the database would not have accepted", () => {
    expect(summariseReactions([{ emoji: "🔥", user_id: "a" }], ME)).toEqual([]);
  });
});

describe("toggledReactions", () => {
  it("adds the reader's reaction", () => {
    expect(toggledReactions([], "👀", ME)).toEqual([{ emoji: "👀", user_id: ME }]);
  });

  it("takes it back on a second tap, leaving everybody else's", () => {
    const rows = [
      { emoji: "👀", user_id: ME },
      { emoji: "👀", user_id: "a" },
    ];
    expect(toggledReactions(rows, "👀", ME)).toEqual([{ emoji: "👀", user_id: "a" }]);
  });
});
