"use client";

import { createBrowserClient } from "@supabase/ssr";

import type { Database } from "./database.types";
import { supabaseAnonKey, supabaseUrl } from "./env";

/**
 * Browser-side Supabase client, for Client Components and Realtime
 * subscriptions. `createBrowserClient` memoises internally, so calling this
 * per-component is safe and keeps a single websocket.
 */
export function createClient() {
  return createBrowserClient<Database>(supabaseUrl(), supabaseAnonKey());
}
