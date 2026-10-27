import { describe, expect, it } from "vitest";

import { EXPECTED_SCHEMA, healthReport } from "@/lib/health";

describe("the health report", () => {
  it("is ok when the database answers with every migration run", () => {
    expect(
      healthReport({ data: { database: "ok", schema: EXPECTED_SCHEMA, missing: [] }, error: null }, { latencyMs: 12, commit: "abc1234" }),
    ).toEqual({
      status: "ok",
      database: "ok",
      schema: EXPECTED_SCHEMA,
      expected: EXPECTED_SCHEMA,
      missing: [],
      latencyMs: 12,
      commit: "abc1234",
    });
  });

  it("is degraded, not down, when the migrations are behind the code", () => {
    expect(healthReport({ data: { schema: EXPECTED_SCHEMA - 2, missing: [] }, error: null }).status).toBe("degraded");
    expect(healthReport({ data: { schema: EXPECTED_SCHEMA, missing: [39] }, error: null })).toMatchObject({
      status: "degraded",
      missing: [39],
    });
    // Before the health function itself exists.
    expect(
      healthReport({ data: null, error: { code: "PGRST202", message: "Could not find the function" } }),
    ).toMatchObject({ status: "degraded", database: "ok", schema: null });
  });

  it("is down when the database cannot be reached or is not set up", () => {
    expect(healthReport("timed out").status).toBe("down");
    expect(healthReport({ data: null, error: { message: "connection refused" } })).toMatchObject({
      status: "down",
      database: "unreachable",
    });
    expect(healthReport("not configured")).toMatchObject({ status: "down", database: "not configured" });
  });
});
