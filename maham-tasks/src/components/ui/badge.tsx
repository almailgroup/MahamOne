import * as React from "react";
import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";

import { cn } from "@/lib/utils";

/**
 * Status and priority markers. Differentiation comes from fill weight and
 * border rather than hue, keeping the board strictly monochrome.
 */
const badgeVariants = cva(
  "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium whitespace-nowrap ring-1 ring-inset transition-colors [&_svg]:size-3 [&_svg]:pointer-events-none",
  {
    variants: {
      variant: {
        // Maham One's badge tones (src/components/ui/misc.tsx there).
        default: "bg-primary-50 text-primary-700 ring-primary-600/15",
        secondary: "bg-slate-200 text-slate-700 ring-slate-500/20",
        outline: "bg-slate-100 text-slate-700 ring-slate-500/10",
        muted: "bg-slate-100 text-slate-600 ring-slate-500/10",
        subtle: "bg-slate-50 text-slate-500 ring-slate-500/10",
        blue: "bg-blue-50 text-blue-700 ring-blue-600/15",
        amber: "bg-amber-50 text-amber-800 ring-amber-600/20",
        green: "bg-emerald-50 text-emerald-700 ring-emerald-600/20",
        red: "bg-red-50 text-red-700 ring-red-600/15",
        violet: "bg-violet-50 text-violet-700 ring-violet-600/15",
      },
    },
    defaultVariants: {
      variant: "outline",
    },
  },
);

function Badge({
  className,
  variant,
  asChild = false,
  ...props
}: React.ComponentProps<"span"> &
  VariantProps<typeof badgeVariants> & { asChild?: boolean }) {
  const Comp = asChild ? Slot : "span";
  return (
    <Comp
      data-slot="badge"
      className={cn(badgeVariants({ variant }), className)}
      {...props}
    />
  );
}

export { Badge, badgeVariants };
