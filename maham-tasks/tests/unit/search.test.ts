import { describe, expect, it } from "vitest";

import { isSearchable, likeFilterValue, likePattern } from "@/lib/search";

describe("likePattern", () => {
  it("wraps the term so it matches anywhere in the field", () => {
    expect(likePattern("customs")).toBe("%customs%");
  });

  it("trims, so a stray space does not become part of the search", () => {
    expect(likePattern("  customs  ")).toBe("%customs%");
  });

  /**
   * The whole reason this function exists: typed into a raw pattern, these
   * are wildcards, and "50%" would match every task in the workspace.
   */
  it("escapes the LIKE wildcards", () => {
    expect(likePattern("50% off")).toBe("%50\\% off%");
    expect(likePattern("back_up")).toBe("%back\\_up%");
    expect(likePattern("a%b_c")).toBe("%a\\%b\\_c%");
  });

  it("escapes the escape character itself", () => {
    expect(likePattern("a\\b")).toBe("%a\\\\b%");
    // Otherwise this would read as an escaped %, and swallow the wildcard.
    expect(likePattern("a\\%")).toBe("%a\\\\\\%%");
  });
});

describe("isSearchable", () => {
  it("ignores anything shorter than two characters", () => {
    expect(isSearchable("")).toBe(false);
    expect(isSearchable(" ")).toBe(false);
    expect(isSearchable("a")).toBe(false);
    expect(isSearchable(" a ")).toBe(false);
  });

  it("accepts two characters or more", () => {
    expect(isSearchable("ab")).toBe(true);
    expect(isSearchable(" ab ")).toBe(true);
  });
});

describe("likeFilterValue", () => {
  it("quotes the pattern for an or() filter", () => {
    expect(likeFilterValue("customs")).toBe('"%customs%"');
  });

  /**
   * The reason quoting is needed at all: an `or` filter is a comma-separated
   * list, so an unquoted comma in the term would be read as a new condition.
   */
  it("survives commas, dots, colons and brackets", () => {
    expect(likeFilterValue("shipping, urgent")).toBe('"%shipping, urgent%"');
    expect(likeFilterValue("v1.2 (draft)")).toBe('"%v1.2 (draft)%"');
  });

  it("escapes quotes, which would otherwise close the value early", () => {
    expect(likeFilterValue('say "hi"')).toBe('"%say \\"hi\\"%"');
  });

  /** Two layers: the LIKE escape, then the quoting escape on top of it. */
  it("keeps the LIKE escapes intact through the quoting", () => {
    expect(likeFilterValue("50%")).toBe('"%50\\\\%%"');
    expect(likeFilterValue("back_up")).toBe('"%back\\\\_up%"');
  });
});
