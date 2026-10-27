import { describe, expect, it } from "vitest";

import { strengthOf } from "@/components/auth/password-meter";

/**
 * The meter rates length above cleverness on purpose. A long passphrase is
 * harder to guess than a short one with a symbol bolted on, and a meter that
 * says otherwise teaches people the wrong lesson.
 */
describe("strengthOf", () => {
  it("calls anything under the minimum too short", () => {
    expect(strengthOf("")).toBe(0);
    expect(strengthOf("short")).toBe(0);
    expect(strengthOf("1234567")).toBe(0);
  });

  it("accepts exactly the minimum, without praising it", () => {
    expect(strengthOf("12345678")).toBe(1);
  });

  it("rewards length", () => {
    expect(strengthOf("a".repeat(12))).toBeGreaterThan(strengthOf("a".repeat(8)));
    expect(strengthOf("a".repeat(16))).toBeGreaterThan(strengthOf("a".repeat(12)));
  });

  it("rates a long passphrase at least as highly as a short cryptic one", () => {
    expect(strengthOf("correct horse battery staple")).toBeGreaterThanOrEqual(
      strengthOf("P@ssw0rd"),
    );
  });

  it("gives some credit for variety, but not enough to rescue a short one", () => {
    expect(strengthOf("Ab3!xyzq")).toBeGreaterThan(strengthOf("abcdefgh"));
    expect(strengthOf("Ab3!xyz")).toBe(0); // seven characters is still too short
  });

  it("never leaves the four steps it can render", () => {
    for (const value of ["", "x", "12345678", "a".repeat(40), "Aa1!".repeat(20)]) {
      const score = strengthOf(value);
      expect(score).toBeGreaterThanOrEqual(0);
      expect(score).toBeLessThanOrEqual(3);
    }
  });
});
