"use server";

import { revalidatePath } from "next/cache";

import { createClient } from "@/lib/supabase/server";
import { publicPushKey } from "@/lib/push/keys";
import { fail, ok, type ActionResult } from "@/lib/action-result";

/**
 * Registering a device for notifications.
 *
 * A subscription belongs to a browser on a device, not to a person, so this
 * is per-device by design: saying yes on the phone does not make the laptop
 * buzz, and turning the phone off leaves the laptop alone.
 *
 * Row-level security allows somebody to write only their own rows; the
 * `user_id` here is the session's, never the client's word for it.
 */
export type DeviceSubscription = {
  endpoint: string;
  p256dh: string;
  auth: string;
  userAgent?: string;
};

/**
 * The public half of the signing key, for `pushManager.subscribe`.
 *
 * Generated on first use and kept in a table only the service role can read;
 * this returns the half that is meant to be public. Null means push is not
 * available — no service-role key configured — and the UI says so rather than
 * offering a switch that cannot work.
 */
export async function getPushPublicKey(): Promise<string | null> {
  return publicPushKey();
}

export async function registerDevice(
  subscription: DeviceSubscription,
): Promise<ActionResult<void>> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return fail("action.sessionExpired");

  if (!subscription.endpoint || !subscription.p256dh || !subscription.auth) {
    return fail("push.incomplete");
  }

  // The endpoint is unique across everybody, and a browser hands back the
  // same one until it is unsubscribed — so re-registering is an update, not
  // a second row.
  const { error } = await supabase.from("push_subscriptions").upsert(
    {
      user_id: user.id,
      endpoint: subscription.endpoint,
      p256dh: subscription.p256dh,
      auth: subscription.auth,
      user_agent: subscription.userAgent?.slice(0, 300) ?? null,
      last_used_at: new Date().toISOString(),
    },
    { onConflict: "endpoint" },
  );

  if (error) return fail("push.couldNotRegister");

  // Registering a device is also saying yes to the channel: nobody grants a
  // browser permission and then expects nothing to arrive.
  await supabase
    .from("notification_preferences")
    .update({ push_enabled: true })
    .eq("user_id", user.id);

  revalidatePath("/profile");
  return ok(undefined);
}

export async function forgetDevice(endpoint: string): Promise<ActionResult<void>> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return fail("action.sessionExpired");

  const { error } = await supabase
    .from("push_subscriptions")
    .delete()
    .eq("endpoint", endpoint)
    .eq("user_id", user.id);

  if (error) return fail("push.couldNotRemove");

  // No devices left means the channel has nowhere to go; leaving it on would
  // queue messages to nobody on every sweep.
  const { count } = await supabase
    .from("push_subscriptions")
    .select("id", { count: "exact", head: true })
    .eq("user_id", user.id);

  if ((count ?? 0) === 0) {
    await supabase
      .from("notification_preferences")
      .update({ push_enabled: false })
      .eq("user_id", user.id);
  }

  revalidatePath("/profile");
  return ok(undefined);
}
