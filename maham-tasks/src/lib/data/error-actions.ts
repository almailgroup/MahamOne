"use server";

import { createClient } from "@/lib/supabase/server";

/**
 * A fault in the browser, reported by the error boundary.
 *
 * Written as the signed-in person — row-level security allows an insert only
 * as yourself, and reading them back is an admin's business, not the
 * reporter's.
 *
 * Returns nothing and throws nothing: it is called from the boundary that is
 * already showing somebody an error, and a failure to record one must not
 * become a second one.
 */
export async function reportClientError(input: {
  message: string;
  route: string;
  digest?: string;
  userAgent?: string;
}): Promise<void> {
  try {
    const supabase = await createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    await supabase.from("app_errors").insert({
      source: "browser",
      digest: input.digest?.slice(0, 200) ?? null,
      // A key, not a sentence: this row is read back onto an admin's profile
      // page, and a fault recorded in English is a fault an Arabic reader
      // cannot read. `tm` renders the key and passes a real exception
      // message — which arrives in whatever language threw it — straight
      // through.
      message: input.message.slice(0, 2000) || "errors.unknown",
      route: input.route.slice(0, 500),
      user_agent: input.userAgent?.slice(0, 400) ?? null,
      user_id: user?.id ?? null,
    });
  } catch {
    // Nothing to do about it, and nothing worth telling the person.
  }
}
