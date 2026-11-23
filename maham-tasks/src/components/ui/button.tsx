import * as React from "react";
import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";

import { cn } from "@/lib/utils";

const buttonVariants = cva(
  // `pointer-coarse` raises every control to 44px on touch without loosening
  // the desktop density: a 36px icon button is comfortable with a mouse and a
  // poor target for a thumb. 44 is Apple's own floor, and the app is used as a
  // home-screen app on an iPhone; 40 was close enough to look right in a
  // screenshot and still the wrong button often enough to notice.
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-full text-sm font-medium transition-[background-color,border-color,color,opacity,transform,box-shadow] duration-150 ease-[var(--ease-spring)] active:scale-[0.96] disabled:pointer-events-none disabled:opacity-50 disabled:active:scale-100 [&_svg]:pointer-events-none [&_svg]:shrink-0 focus-visible:outline-none pointer-coarse:min-h-11 pointer-coarse:min-w-11",
  {
    variants: {
      variant: {
        /** Inverted fill — the single strongest emphasis in the UI. */
        default:
          "bg-primary text-primary-foreground shadow-[var(--shadow-sm)] hover:bg-primary/90 hover:shadow-[var(--shadow-md)]",
        /** A soft filled pill, the workhorse for most actions. No outline: the fill is the shape. */
        outline:
          "bg-foreground/[0.06] text-foreground hover:bg-foreground/[0.1] hover:shadow-[var(--shadow-xs)]",
        secondary:
          "bg-secondary text-secondary-foreground hover:bg-secondary/80",
        ghost: "hover:bg-accent hover:text-accent-foreground",
        link: "text-foreground underline-offset-4 hover:underline",
        /** Reserved for irreversible actions; still greyscale by design. */
        destructive:
          "bg-destructive text-destructive-foreground hover:bg-destructive/90 shadow-sm",
      },
      size: {
        default: "h-10 px-4 py-2 [&_svg]:size-4",
        sm: "h-9 px-3.5 text-xs [&_svg]:size-3.5",
        lg: "h-11 px-6 [&_svg]:size-4",
        icon: "size-9 pointer-coarse:min-w-11 [&_svg]:size-4",
        "icon-sm": "size-9 pointer-coarse:min-w-11 [&_svg]:size-3.5",
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
