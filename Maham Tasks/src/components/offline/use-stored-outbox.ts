"use client";

import * as React from "react";

import { OUTBOX_EVENT, OUTBOX_KEY, readOutbox, type OutboxItem } from "@/lib/outbox";

/**
 * Every change waiting in this browser's outbox, kept current as this tab or
 * another one adds or sends one. On its own, without the provider's server
 * calls, so the offline page can show the count and stay small.
 *
 * An external store rather than state set in an effect, and the same empty
 * list on the server and in the browser. Setting state on mount updated the
 * provider above every page while parts of the page were still streaming
 * in; React then drew those parts afresh, and the streamed copy, arriving
 * after, was left hidden in the document — every page's text, twice.
 */

const EMPTY: OutboxItem[] = [];

let cachedRaw: string | null | undefined;
let cachedItems: OutboxItem[] = EMPTY;

function snapshot(): OutboxItem[] {
  let raw: string | null = null;
  try {
    raw = window.localStorage.getItem(OUTBOX_KEY);
  } catch {
    // Storage blocked: nothing kept, nothing to show.
  }
  if (raw === cachedRaw) return cachedItems;
  cachedRaw = raw;
  const items = readOutbox();
  cachedItems = items.length === 0 ? EMPTY : items;
  return cachedItems;
}

function subscribe(onChange: () => void) {
  const fromOtherTab = (event: StorageEvent) => {
    if (event.key === OUTBOX_KEY) onChange();
  };
  window.addEventListener(OUTBOX_EVENT, onChange);
  window.addEventListener("storage", fromOtherTab);
  return () => {
    window.removeEventListener(OUTBOX_EVENT, onChange);
    window.removeEventListener("storage", fromOtherTab);
  };
}

export function useStoredOutbox(): OutboxItem[] {
  return React.useSyncExternalStore(subscribe, snapshot, () => EMPTY);
}
