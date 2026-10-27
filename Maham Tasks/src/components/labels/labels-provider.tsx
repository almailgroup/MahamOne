"use client";

import * as React from "react";

import type { Label, LabelColour } from "@/lib/supabase/database.types";

/**
 * The company's labels, for every task on every page.
 *
 * A task carries only the ids of its labels; names and colours are looked up
 * here. Read once by the signed-in shell, so a list of forty tasks does not
 * fetch the same three label names forty times.
 */
type LabelsValue = { list: Label[]; byId: ReadonlyMap<string, Label> };

const EMPTY: LabelsValue = { list: [], byId: new Map() };
const LabelsContext = React.createContext<LabelsValue>(EMPTY);

export function LabelsProvider({
  labels,
  children,
}: {
  labels: Label[];
  children: React.ReactNode;
}) {
  const value = React.useMemo<LabelsValue>(
    () => ({ list: labels, byId: new Map(labels.map((label) => [label.id, label])) }),
    [labels],
  );
  return <LabelsContext.Provider value={value}>{children}</LabelsContext.Provider>;
}

/** Every label, by name. */
export function useLabels(): Label[] {
  return React.useContext(LabelsContext).list;
}

/** The labels behind these ids, in name order; ids no longer known are dropped. */
export function useLabelsFor(ids: readonly string[]): Label[] {
  const { byId } = React.useContext(LabelsContext);
  return React.useMemo(
    () =>
      ids
        .map((id) => byId.get(id))
        .filter((label): label is Label => label !== undefined)
        .sort((a, b) => a.name.localeCompare(b.name)),
    [ids, byId],
  );
}

export const LABEL_COLOURS: readonly LabelColour[] = [
  "slate",
  "blue",
  "green",
  "violet",
  "pink",
  "teal",
];

/** The dot's fill. Written out whole so Tailwind finds each class. */
export const LABEL_DOT: Record<LabelColour, string> = {
  slate: "bg-slate-400",
  blue: "bg-sky-500",
  green: "bg-emerald-500",
  violet: "bg-violet-500",
  pink: "bg-pink-500",
  teal: "bg-teal-500",
};
