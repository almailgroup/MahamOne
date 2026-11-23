import * as React from "react";
import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";

import { cn } from "@/lib/utils";

/**
 * Maham One's buttons (its src/components/ui/button.tsx): the same shapes,
 * heights and colours, under the variant names this app already uses.
 */
const buttonVariants = cva(
  // `pointer-coarse` raises every control to 44px on touch without loosening
  // the desktop density: a 36px icon button is comfortable with a mouse and a
  // poor target for a thumb. 44 is Apple's own floor, as in Maham One.
  "inline-flex shrink-0 items-center justify-center gap-2 whitespace-nowrap rounded-lg text-sm font-medium transition-colors disabled:pointer-events-none disabled:opacity-50 [&_svg]:pointer-events-none [&_svg]:size-4 [&_svg]:shrink-0 pointer-coarse:min-h-11 pointer-coarse:min-w-11",
  {
    variants: {
      variant: {
        /** The main action: Maham One's primary, in the theme's colour. */
        default:
          "bg-primary-solid text-on-primary shadow-sm hover:bg-primary-solid-hover active:bg-primary-solid-active",
        /** White with an edge, for most other actions. */
        outline:
          "border border-slate-300 bg-surface text-slate-700 shadow-xs hover:bg-slate-50 hover:text-slate-900",
        secondary: "bg-slate-100 text-slate-800 hover:bg-slate-200 hover:text-slate-900",
        /** A soft tint of the main colour. */
        subtle: "bg-primary-50 text-primary-700 hover:bg-primary-100",
        ghost: "text-slate-600 hover:bg-slate-100 hover:text-slate-900",
        link: "text-primary-700 underline-offset-4 hover:underline",
        /** For deleting: red, as in Maham One. */
        destructive: "bg-red-solid text-white shadow-sm hover:bg-red-solid-hover",
      },
      size: {
        default: "h-9 px-4",
        xs: "h-7 px-2 text-xs",
        sm: "h-8 px-3",
        lg: "h-11 px-5 text-base",
        icon: "size-9",
        "icon-sm": "size-8",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  },
);

function Button({
  className,
  variant,
  size,
  asChild = false,
  ...props
}: React.ComponentProps<"button"> &
  VariantProps<typeof buttonVariants> & { asChild?: boolean }) {
  const Comp = asChild ? Slot : "button";
  return (
    <Comp
      data-slot="button"
      className={cn(buttonVariants({ variant, size, className }))}
      {...props}
    />
  );
}

export { Button, buttonVariants };
