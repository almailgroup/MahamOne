"use client";

import * as React from "react";

import {
  Avatar,
  AvatarFallback,
  AvatarImage,
} from "@/components/ui/avatar";
import { initialsFrom } from "@/lib/initials";
import { Textarea } from "@/components/ui/textarea";
import { mentionName } from "@/lib/mentions";
import { cn } from "@/lib/utils";
import type { Profile } from "@/lib/supabase/database.types";

/**
 * Textarea with @mention autocomplete.
 *
 * Typing "@" opens a filtered team list; Enter or Tab inserts the name. The
 * popup swallows Enter only while it is open, so ordinary newlines still work.
 */
export function MentionTextarea({
  value,
  onChange,
  team,
  onSubmit,
  ...props
}: {
  value: string;
  onChange: (next: string) => void;
  team: Profile[];
  onSubmit?: () => void;
} & Omit<React.ComponentProps<"textarea">, "value" | "onChange">) {
  const ref = React.useRef<HTMLTextAreaElement>(null);
  const [query, setQuery] = React.useState<string | null>(null);
  const [anchor, setAnchor] = React.useState(0);
  const [highlight, setHighlight] = React.useState(0);

  const matches = React.useMemo(() => {
    if (query === null) return [];
    const needle = query.toLowerCase();
    return team
      .filter((person) => mentionName(person).toLowerCase().includes(needle))
      .slice(0, 6);
  }, [query, team]);

  const open = query !== null && matches.length > 0;

  /** Recompute the pending @query from the caret position. */
  function syncQuery(text: string, caret: number) {
    const upto = text.slice(0, caret);
    const at = upto.lastIndexOf("@");

    if (at === -1) {
      setQuery(null);
      return;
    }

    const fragment = upto.slice(at + 1);
    // A mention runs until whitespace; bail out once the fragment spans lines
    // or gets long enough that it is clearly ordinary prose.
    if (/[\n\r]/.test(fragment) || fragment.length > 40) {
      setQuery(null);
      return;
    }

    setAnchor(at);
    setQuery(fragment);
    setHighlight(0);
  }

  function insert(person: Profile) {
    const name = mentionName(person);
    const caret = ref.current?.selectionStart ?? value.length;
    const next = `${value.slice(0, anchor)}@${name} ${value.slice(caret)}`;

    onChange(next);
    setQuery(null);

    // Restore the caret after the inserted mention.
    const cursor = anchor + name.length + 2;
    requestAnimationFrame(() => {
      ref.current?.focus();
      ref.current?.setSelectionRange(cursor, cursor);
    });
  }

  function onKeyDown(event: React.KeyboardEvent<HTMLTextAreaElement>) {
    if (open) {
      if (event.key === "ArrowDown") {
        event.preventDefault();
        setHighlight((index) => (index + 1) % matches.length);
        return;
      }
      if (event.key === "ArrowUp") {
        event.preventDefault();
        setHighlight((index) => (index - 1 + matches.length) % matches.length);
        return;
      }
      if (event.key === "Enter" || event.key === "Tab") {
        event.preventDefault();
        insert(matches[highlight]);
        return;
      }
      if (event.key === "Escape") {
        event.preventDefault();
        setQuery(null);
        return;
      }
    }

    // Cmd/Ctrl+Enter submits, matching the hint under the field.
    if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
      event.preventDefault();
      onSubmit?.();
    }
  }

  return (
    <div className="relative">
      <Textarea
        {...props}
        ref={ref}
        value={value}
        onChange={(event) => {
          onChange(event.target.value);
          syncQuery(event.target.value, event.target.selectionStart ?? 0);
        }}
        onKeyDown={onKeyDown}
        onBlur={() => setQuery(null)}
      />

      {open && (
        <ul
          role="listbox"
          className="absolute bottom-full start-0 z-50 mb-1 w-64 overflow-hidden rounded-xl bg-popover p-1 shadow-md"
        >
          {matches.map((person, index) => (
            <li key={person.id}>
              <button
                type="button"
                role="option"
                aria-selected={index === highlight}
                // mousedown fires before the textarea's blur clears the query.
                onMouseDown={(event) => {
                  event.preventDefault();
                  insert(person);
                }}
                onMouseEnter={() => setHighlight(index)}
                className={cn(
                  "flex w-full items-center gap-2 rounded-sm px-2 py-1.5 text-start text-sm transition-colors",
                  index === highlight
                    ? "bg-accent text-accent-foreground"
                    : "text-foreground",
                )}
              >
                <Avatar className="size-5">
                  {person.avatar_url && (
                    <AvatarImage src={person.avatar_url} alt="" />
                  )}
                  <AvatarFallback className="text-[9px]">
                    {initialsFrom(person.full_name, person.email)}
                  </AvatarFallback>
                </Avatar>
                <span className="truncate">{mentionName(person)}</span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
