import { describe, expect, it } from "vitest";

import {
  SIDEBAR_CHAT_MAX,
  SIDEBAR_CHAT_MIN,
  SIDEBAR_DEFAULT,
  SIDEBAR_MAX,
  SIDEBAR_MIN,
  clampSidebarWidth,
  sidebarBounds,
} from "@/lib/sidebar";

describe("clampSidebarWidth", () => {
  it("holds navigation inside its own bounds", () => {
    expect(clampSidebarWidth(10)).toBe(SIDEBAR_MIN);
    expect(clampSidebarWidth(9999)).toBe(SIDEBAR_MAX);
    expect(clampSidebarWidth(300)).toBe(300);
  });

  it("lets the assistant go wider than navigation ever can", () => {
    expect(clampSidebarWidth(9999, "chat")).toBe(SIDEBAR_CHAT_MAX);
    expect(SIDEBAR_CHAT_MAX).toBeGreaterThan(SIDEBAR_MAX);
    expect(clampSidebarWidth(10, "chat")).toBe(SIDEBAR_CHAT_MIN);
  });

  it("falls back to the default for a value that is not a number", () => {
    // A corrupt localStorage entry parses to NaN, which must not become the width.
    expect(clampSidebarWidth(Number.NaN)).toBe(SIDEBAR_DEFAULT);
  });

  it("rounds to whole pixels", () => {
    expect(clampSidebarWidth(300.6)).toBe(301);
  });

  it("keeps every preferred width inside its own min and max", () => {
    for (const mode of ["nav", "chat"] as const) {
      const { min, max, preferred } = sidebarBounds(mode);
      expect(preferred).toBeGreaterThanOrEqual(min);
      expect(preferred).toBeLessThanOrEqual(max);
    }
  });
});
