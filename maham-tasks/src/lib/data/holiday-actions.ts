"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { createClient } from "@/lib/supabase/server";
import {
  describeDatabaseError,
  fail,
  fieldErrorsFrom,
  ok,
  type ActionResult,
} from "@/lib/action-result";

/**
 * Keeping the list of company holidays.
 *
 * Row-level security decides who may: admins only (company_holidays). Nothing
 * here checks a role — a refused write comes back as an error and is
 * translated, not second-guessed.
 *
 * A holiday of several days is stored as one row per day under one name, so
 * adding takes a first and last day, and removing takes the same pair.
 */

const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "holiday.badDate");

/** The longest run added at once. The Eids are three or four days; a month
 *  is a mistake in the date field, not a holiday. */
const MAX_DAYS = 14;

const holidaySchema = z
  .object({
    name: z.string().trim().min(1, "holiday.nameRequired").max(80, "holiday.nameTooLong"),
    from: isoDate,
    to: isoDate,
  })
  .refine((v) => v.to >= v.from, { message: "holiday.endBeforeStart", path: ["to"] })
  .refine((v) => daysIn(v.from, v.to).length <= MAX_DAYS, {
    message: "holiday.tooLong",
    path: ["to"],
  });

/** Every ISO day from `from` to `to`, both included. */
function daysIn(from: string, to: string): string[] {
  const days: string[] = [];
  const cursor = new Date(`${from}T00:00:00Z`);
  const end = new Date(`${to}T00:00:00Z`);
  while (cursor <= end && days.length <= MAX_DAYS) {
    days.push(cursor.toISOString().slice(0, 10));
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }
  return days;
}

function revalidate() {
  // Every signed-in page carries the list (the shell hands it to the date
  // shortcuts), and the calendar draws it.
  revalidatePath("/", "layout");
}

export async function addHoliday(input: {
  name: string;
  from: string;
  to?: string;
}): Promise<ActionResult<{ days: number }>> {
  const parsed = holidaySchema.safeParse({ ...input, to: input.to || input.from });
  if (!parsed.success) {
    return fail("action.checkFields", fieldErrorsFrom(parsed.error.issues));
  }

  const supabase = await createClient();
  const rows = daysIn(parsed.data.from, parsed.data.to).map((day) => ({
    day,
    name: parsed.data.name,
  }));

  // An existing day takes the new name rather than refusing the whole run.
  const { error } = await supabase.from("company_holidays").upsert(rows, { onConflict: "day" });
  if (error) return fail(describeDatabaseError(error));

  revalidate();
  return ok({ days: rows.length });
}

export async function removeHoliday(input: {
  from: string;
  to: string;
}): Promise<ActionResult<void>> {
  if (!isoDate.safeParse(input.from).success || !isoDate.safeParse(input.to).success) {
    return fail("holiday.badDate");
  }

  const supabase = await createClient();
  const { error } = await supabase
    .from("company_holidays")
    .delete()
    .gte("day", input.from)
    .lte("day", input.to);
  if (error) return fail(describeDatabaseError(error));

  revalidate();
  return ok(undefined);
}

/**
 * Kuwait's fixed public holidays for a year: New Year's Day, National Day and
 * Liberation Day. The Islamic holidays move with the moon and are announced
 * each year, so they are added by hand once the dates are confirmed.
 */
export async function addFixedNationalHolidays(
  year: number,
  names: { newYear: string; national: string; liberation: string },
): Promise<ActionResult<{ days: number }>> {
  if (!Number.isInteger(year) || year < 2020 || year > 2100) return fail("holiday.badDate");

  const supabase = await createClient();
  const rows = [
    { day: `${year}-01-01`, name: names.newYear },
    { day: `${year}-02-25`, name: names.national },
    { day: `${year}-02-26`, name: names.liberation },
  ];
  const { error } = await supabase.from("company_holidays").upsert(rows, { onConflict: "day" });
  if (error) return fail(describeDatabaseError(error));

  revalidate();
  return ok({ days: rows.length });
}
