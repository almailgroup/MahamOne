"use client";

import * as React from "react";

import type { HolidaySet } from "@/lib/work-week";

/**
 * The company's holidays, for anything in the browser that counts working
 * days — the date shortcuts, the calendar.
 *
 * Read once on the server for the signed-in shell and handed down, rather
 * than fetched by each control that needs it: a date shortcut has to know the
 * answer the moment it is tapped.
 */
export type Holiday = { day: string; name: string };

type HolidaysValue = { set: HolidaySet; names: ReadonlyMap<string, string> };

const EMPTY: HolidaysValue = { set: new Set(), names: new Map() };
const HolidaysContext = React.createContext<HolidaysValue>(EMPTY);

export function HolidaysProvider({
  holidays,
  children,
}: {
  holidays: Holiday[];
  children: React.ReactNode;
}) {
  const value = React.useMemo<HolidaysValue>(
    () => ({
      set: new Set(holidays.map((h) => h.day)),
      names: new Map(holidays.map((h) => [h.day, h.name])),
    }),
    [holidays],
  );
  return <HolidaysContext.Provider value={value}>{children}</HolidaysContext.Provider>;
}

/** The holiday days, "2026-03-20", for the working-day arithmetic. */
export function useHolidaySet(): HolidaySet {
  return React.useContext(HolidaysContext).set;
}

/** The holiday on an ISO day, by name, or undefined. */
export function useHolidayNames(): ReadonlyMap<string, string> {
  return React.useContext(HolidaysContext).names;
}
