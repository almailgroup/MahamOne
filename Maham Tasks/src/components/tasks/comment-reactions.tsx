"use client";

import * as React from "react";
import { SmilePlus } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { toggleReaction } from "@/lib/data/comment-actions";
import { useI18n } from "@/lib/i18n/client";
import {
  REACTIONS,
  summariseReactions,
  toggledReactions,
  type Reaction,
  type ReactionRow,
} from "@/lib/reactions";
import { cn } from "@/lib/utils";
import type { Profile } from "@/lib/supabase/database.types";

/**
 * Reactions on a comment, in two pieces: the chips under it, which only
 * exist once somebody has reacted, and the button that adds one, which sits
 * with the comment's other controls. One row holding both left an empty
 * strip under every comment nobody had reacted to.
 *
 * Optimistic: the chip changes on the tap and the server is told after. A
 * thumb that takes half a second to land feels like it did not, and the one
 * way this can fail — losing sight of the task — is rare enough that putting
 * it back and saying so is the right price.
 */

/** The tap, shared by a chip and the picker so the two cannot disagree. */
function useToggle(
  commentId: string,
  rows: ReactionRow[],
  meId: string,
  onChange: (rows: ReactionRow[]) => void,
) {
  const { tm } = useI18n();
  return React.useCallback(
    async (emoji: Reaction) => {
      const before = rows;
      onChange(toggledReactions(rows, emoji, meId));
      const outcome = await toggleReaction(commentId, emoji);
      if (!outcome.ok) {
        onChange(before);
        toast.error(tm(outcome.error));
      }
    },
    [commentId, rows, meId, onChange, tm],
  );
}

type Props = {
  commentId: string;
  rows: ReactionRow[];
  me: Profile;
  /** Hands the new rows back up, so the thread owns the one copy of them. */
  onChange: (rows: ReactionRow[]) => void;
};

/**
 * Monochrome. The emoji carry their own colour; the chip around them is the
 * same grey as everything else, and darker when it is yours.
 */
export function ReactionChips({
  commentId,
  rows,
  me,
  onChange,
  teamById,
}: Props & { teamById: Map<string, Profile> }) {
  const { t } = useI18n();
  const toggle = useToggle(commentId, rows, me.id, onChange);
  const chips = summariseReactions(rows, me.id);
  if (chips.length === 0) return null;

  const nameOf = (id: string) => {
    if (id === me.id) return t("chat.you");
    const person = teamById.get(id);
    return person?.full_name ?? person?.email ?? "—";
  };

  return (
    <div className="mt-1 flex flex-wrap items-center gap-1">
      {chips.map((chip) => (
        <button
          key={chip.emoji}
          type="button"
          onClick={() => toggle(chip.emoji)}
          aria-pressed={chip.mine}
          aria-label={t("reaction.label", { emoji: chip.emoji, n: chip.count })}
          title={chip.userIds.map(nameOf).join(", ")}
          className={cn(
            "inline-flex h-6 items-center gap-1 rounded-full px-1.5 text-xs tabular-nums transition-colors",
            "pointer-coarse:h-8 pointer-coarse:px-2",
            chip.mine
              ? "bg-primary/15 text-foreground"
              : "bg-foreground/[0.06] text-muted-foreground hover:bg-accent hover:text-foreground",
          )}
        >
          <span aria-hidden>{chip.emoji}</span>
          {chip.count}
        </button>
      ))}
    </div>
  );
}

export function ReactionPicker({
  commentId,
  rows,
  me,
  onChange,
  className,
}: Props & { className?: string }) {
  const { t } = useI18n();
  const [open, setOpen] = React.useState(false);
  const toggle = useToggle(commentId, rows, me.id, onChange);

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button
          type="button"
          variant="ghost"
          size="icon-sm"
          aria-label={t("reaction.add")}
          title={t("reaction.add")}
          className={className}
        >
          <SmilePlus />
        </Button>
      </PopoverTrigger>
      <PopoverContent align="end" className="flex w-auto gap-0.5 p-1">
        {REACTIONS.map((emoji) => (
          <button
            key={emoji}
            type="button"
            onClick={() => {
              setOpen(false);
              void toggle(emoji);
            }}
            aria-label={emoji}
            className="flex size-9 items-center justify-center rounded-md text-lg transition-colors hover:bg-accent"
          >
            {emoji}
          </button>
        ))}
      </PopoverContent>
    </Popover>
  );
}
