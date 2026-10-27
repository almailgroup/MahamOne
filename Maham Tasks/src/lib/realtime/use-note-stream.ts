"use client";

import * as React from "react";

import { createClient } from "@/lib/supabase/client";
import type { PersonalNote, PersonalNoteItem } from "@/lib/supabase/database.types";

/**
 * Keeps an open shared list in step with whoever else has it open.
 *
 * Checklist lines are separate rows, so two people working the same list
 * almost never collide: ticking, adding and removing arrive as row events and
 * are applied as they come. The note's free text is the one place they can —
 * it is one column, saved on a debounce — so a remote edit to it is offered to
 * the caller, which applies it only when there is nothing local to lose.
 *
 * Only subscribes when the list is actually shared. A list nobody else can see
 * has nothing to synchronise, and an idle channel per note is a cost with no
 * benefit.
 */
export function useNoteStream({
  noteId,
  enabled,
  onItem,
  onNote,
}: {
  noteId: string;
  enabled: boolean;
  onItem: (change: {
    type: "INSERT" | "UPDATE" | "DELETE";
    item: PersonalNoteItem;
  }) => void;
  onNote: (note: PersonalNote) => void;
}) {
  const supabase = React.useMemo(() => createClient(), []);

  // Handlers change identity on every render of the editor; holding them in a
  // ref keeps the subscription from being torn down and rebuilt each time.
  const handlers = React.useRef({ onItem, onNote });
  React.useEffect(() => {
    handlers.current = { onItem, onNote };
  }, [onItem, onNote]);

  React.useEffect(() => {
    if (!enabled) return;

    const channel = supabase
      .channel(`note:${noteId}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "personal_note_items",
          filter: `note_id=eq.${noteId}`,
        },
        (payload) => {
          // A delete carries the old row, which is why the table keeps its
          // full replica identity.
          const row = (payload.eventType === "DELETE"
            ? payload.old
            : payload.new) as PersonalNoteItem;
          if (!row?.id) return;

          handlers.current.onItem({
            type: payload.eventType as "INSERT" | "UPDATE" | "DELETE",
            item: row,
          });
        },
      )
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "personal_notes",
          filter: `id=eq.${noteId}`,
        },
        (payload) => handlers.current.onNote(payload.new as PersonalNote),
      )
      .subscribe();

    return () => {
      void supabase.removeChannel(channel);
    };
  }, [supabase, noteId, enabled]);
}
