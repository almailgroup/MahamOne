/**
 * How the team room breaks a list of messages into days and runs.
 *
 * The interesting cases are all timezone cases: the app is used from Dubai,
 * and the database stores UTC, so "which day was this" and "what time does it
 * say" have to be answered in the same place or the separator contradicts the
 * timestamps underneath it.
 */

import { describe, expect, test } from "vitest";

import {
  RUN_GAP_MS,
  continues,
  dayKey,
  startsNewDay,
} from "@/lib/chat/grouping";
import { formatTimeOfDay } from "@/lib/dates";

const DUBAI = "Asia/Dubai";

const at = (iso: string, author = "aisha") => ({ author_id: author, created_at: iso });

describe("which day a message belongs to", () => {
  test("the first message always opens a day", () => {
    expect(startsNewDay(undefined, at("2026-09-16T08:00:00Z"), DUBAI)).toBe(true);
  });

  test("two messages in the same local day stay together", () => {
    expect(
      startsNewDay(at("2026-09-16T06:00:00Z"), at("2026-09-16T15:00:00Z"), DUBAI),
    ).toBe(false);
  });

  test("late evening in Dubai is already tomorrow in UTC, and the reader is in Dubai", () => {
    // 20:30 and 21:30 UTC are 00:30 and 01:30 the next day in Dubai — one day
    // in Dubai, two days in UTC. Reading it in UTC would split them.
    const previous = at("2026-09-16T20:30:00Z");
    const message = at("2026-09-16T21:30:00Z");
    expect(startsNewDay(previous, message, DUBAI)).toBe(false);
    expect(dayKey(previous.created_at, DUBAI)).toBe("2026-09-17");
  });

  test("midnight in Dubai does split the day, even though UTC has not turned over", () => {
    // 19:00 UTC is 23:00 in Dubai; 20:00 UTC is 00:00 the next day there.
    expect(
      startsNewDay(at("2026-09-16T19:00:00Z"), at("2026-09-16T20:00:00Z"), DUBAI),
    ).toBe(true);
  });

  test("the separator and the timestamp beside it agree about the day", () => {
    const iso = "2026-09-16T20:30:00Z";
    expect(dayKey(iso, DUBAI)).toBe("2026-09-17");
    expect(formatTimeOfDay(iso, "en-AE", DUBAI)).toMatch(/12:30/);
  });
});

describe("which messages are one run", () => {
  test("nothing continues the first message", () => {
    expect(continues(undefined, at("2026-09-16T08:00:00Z"))).toBe(false);
  });

  test("the same person a minute later is the same breath", () => {
    expect(
      continues(at("2026-09-16T08:00:00Z"), at("2026-09-16T08:01:00Z")),
    ).toBe(true);
  });

  test("a different person always starts a new block", () => {
    expect(
      continues(
        at("2026-09-16T08:00:00Z", "aisha"),
        at("2026-09-16T08:00:30Z", "omar"),
      ),
    ).toBe(false);
  });

  test("the gap is exclusive at its limit", () => {
    const start = Date.parse("2026-09-16T08:00:00Z");
    const justInside = new Date(start + RUN_GAP_MS - 1).toISOString();
    const exactly = new Date(start + RUN_GAP_MS).toISOString();
    expect(continues(at("2026-09-16T08:00:00Z"), at(justInside))).toBe(true);
    expect(continues(at("2026-09-16T08:00:00Z"), at(exactly))).toBe(false);
  });

  test("a message that arrives out of order does not join the run behind it", () => {
    // Realtime can deliver an insert before the list it is appended to has
    // settled; a negative gap is not five minutes of silence.
    expect(
      continues(at("2026-09-16T08:05:00Z"), at("2026-09-16T08:00:00Z")),
    ).toBe(false);
  });
});
