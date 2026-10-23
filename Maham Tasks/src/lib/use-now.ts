"use client";

import * as React from "react";

/**
 * One shared clock for every live timer on the page.
 *
 * A board can hold dozens of ticking cards; giving each its own interval
 * would mean dozens of timers firing a second apart and dozens of separate
 * renders. They all read from this single interval instead, which only runs
 * while something is subscribed.
 */
const subscribers = new Set<() => void>();
let timer: ReturnType<typeof setInterval> | null = null;
let snapshot = 0;

function subscribe(onChange: () => void) {
  subscribers.add(onChange);

  if (timer === null) {
    snapshot = Date.now();
    timer = setInterval(() => {
      snapshot = Date.now();
      for (const notify of subscribers) notify();
    }, 1000);
  }

  return () => {
    subscribers.delete(onChange);
    if (subscribers.size === 0 && timer !== null) {
      clearInterval(timer);
      timer = null;
    }
  };
}

function getSnapshot() {
  // Seeded on first read so the first paint is not a second behind.
  if (snapshot === 0) snapshot = Date.now();
  return snapshot;
}

/** The server has no clock worth sending; 0 reads as "not running yet". */
function getServerSnapshot() {
  return 0;
}

/**
 * Wall-clock milliseconds, refreshed once a second.
 *
 * Returns null until the component has hydrated. The server cannot know the
 * viewer's clock, so rendering a time during SSR would guarantee a mismatch;
 * useSyncExternalStore gives us the placeholder render and the real one
 * without React complaining about either.
 */
export function useNow(): number | null {
  const value = React.useSyncExternalStore(
    subscribe,
    getSnapshot,
    getServerSnapshot,
  );
  return value === 0 ? null : value;
}
