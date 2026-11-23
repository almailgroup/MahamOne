"use client";

import * as React from "react";
import * as CheckboxPrimitive from "@radix-ui/react-checkbox";
import { Check } from "lucide-react";

import { cn } from "@/lib/utils";

function Checkbox({
  className,
  ...props
}: React.ComponentProps<typeof CheckboxPrimitive.Root>) {
  return (
    <CheckboxPrimitive.Root
      data-slot="checkbox"
      className={cn(
        // A circle, like ticking off a reminder: the round shape the rest of
        // the interface uses, and the one control that keeps an edge — an
        // unticked box has nothing else to show it is there, so the ring
        // stays at the 3:1 the theme tests hold `input` to.
        "peer size-[1.25rem] shrink-0 rounded-full border-[1.5px] border-input transition-all duration-150 hover:bg-foreground/[0.06]",
        // The circle is 20px, and the target around it grows to 44 on touch.
        // What a thumb has to hit and what the eye has to read are not the
        // same shape, and only one of them belongs at Apple's minimum.
        "pointer-coarse:relative pointer-coarse:after:absolute pointer-coarse:after:-inset-[12px] pointer-coarse:after:content-['']",
        "focus-visible:outline-none disabled:cursor-not-allowed disabled:opacity-50",
        "data-[state=checked]:border-primary data-[state=checked]:bg-primary data-[state=checked]:text-primary-foreground",
        className,
      )}
      {...props}
    >
      <CheckboxPrimitive.Indicator className="flex items-center justify-center text-current">
        <Check className="size-3.5" />
      </CheckboxPrimitive.Indicator>
    </CheckboxPrimitive.Root>
  );
}

export { Checkbox };
