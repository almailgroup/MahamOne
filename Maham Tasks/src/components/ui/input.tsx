import * as React from "react";

import { cn } from "@/lib/utils";

function Input({ className, type, ...props }: React.ComponentProps<"input">) {
  return (
    <input
      type={type}
      data-slot="input"
      className={cn(
        "flex h-10 w-full rounded-full bg-foreground/[0.055] shadow-[inset_0_1px_2px_rgb(0_0_0/0.06)] hover:bg-foreground/[0.08] px-4 py-1 text-sm transition-[background-color,box-shadow] duration-200 pointer-coarse:min-h-11",
        "placeholder:text-muted-foreground",
        "file:border-0 file:bg-transparent file:text-sm file:font-medium file:text-foreground",
        "disabled:cursor-not-allowed disabled:opacity-50",
        "focus-visible:outline-none focus-visible:bg-card focus-visible:ring-2 focus-visible:ring-ring/60 focus-visible:shadow-[var(--shadow-sm)]",
        "aria-invalid:ring-2 aria-invalid:ring-foreground/60",
        className,
      )}
      {...props}
    />
  );
}

export { Input };
