"use client";

import * as React from "react";
import { useSearchParams } from "next/navigation";

import {
  EMPTY_FILTERS,
  readFiltersFromParams,
  writeFiltersToParams,
  type TaskListFilters,
} from "@/lib/task-filters";

/**
 * Filter state that lives in the address bar.
 *
 * A filtered view is worth linking to — "here are the urgent ones on your
 * plate" — and worth keeping across a reload. The URL is updated in place
 * with the History API rather than by navigating: a navigation would ask the
 * server to render the page again on every keystroke, for a change that only
 * concerns what the browser already has.
 */
export function useTaskFilters() {
  const params = useSearchParams();
  const [filters, setFilters] = React.useState<TaskListFilters>(() =>
    readFiltersFromParams(new URLSearchParams(params.toString())),
  );

  // Typing is written to the URL after a pause; the selects write at once.
  const pending = React.useRef<ReturnType<typeof setTimeout> | null>(null);

  const update = React.useCallback((patch: Partial<TaskListFilters>) => {
    setFilters((current) => {
      const next = { ...current, ...patch };

      if (pending.current) clearTimeout(pending.current);
      const write = () => {
        const url = new URL(window.location.href);
        url.search = writeFiltersToParams(next, url.searchParams).toString();
        window.history.replaceState(window.history.state, "", url);
      };
      if ("query" in patch) pending.current = setTimeout(write, 250);
      else write();

      return next;
    });
  }, []);

  const clear = React.useCallback(() => update(EMPTY_FILTERS), [update]);

  React.useEffect(
    () => () => {
      if (pending.current) clearTimeout(pending.current);
    },
    [],
  );

  return { filters, update, clear };
}
