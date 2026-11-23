"use client";

import * as React from "react";

import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";

/**
 * Six digits, large and spaced, and nothing else accepted: spaces and dashes
 * from a pasted "123 456" are dropped rather than refused. `one-time-code`
 * lets an iPhone offer the code from its own Passwords app.
 */
export function CodeInput({
  id,
  value,
  onChange,
  disabled,
  className,
}: {
  id: string;
  value: string;
  onChange: (digits: string) => void;
  disabled?: boolean;
  className?: string;
}) {
  return (
    <Input
      id={id}
      name={id}
      value={value}
      onChange={(event) => onChange(event.target.value.replace(/\D/g, "").slice(0, 6))}
      inputMode="numeric"
      autoComplete="one-time-code"
      pattern="[0-9]*"
      maxLength={6}
      autoFocus
      disabled={disabled}
      placeholder="000000"
      dir="ltr"
      className={cn(
        // It is focused from the start, so it keeps the field's own soft focus
        // ring, as every field in Maham One does.
        "h-14 text-center text-2xl font-semibold tabular-nums tracking-[0.5em] placeholder:text-slate-300",
        className,
      )}
    />
  );
}
