import * as React from "react";

import { cn } from "@/lib/utils";

function Textarea({ className, ...props }: React.ComponentProps<"textarea">) {
  return (
    <textarea
      data-slot="textarea"
      className={cn(
        "flex min-h-[72px] w-full rounded-2xl bg-foreground/[0.055] shadow-[inset_0_1px_2px_rgb(0_0_0/0.06)] hover:bg-foreground/[0.08] px-4 py-2.5 text-sm transition-[background-color,box-shadow] duration-200",
        "placeholder:text-muted-foreground",
        "disabled:cursor-not-allowed disabled:opacity-50",
        "focus-visible:outline-none focus-visible:bg-card focus-visible:ring-2 focus-visible:ring-ring/60 focus-visible:shadow-[var(--shadow-sm)]",
        className,
      )}
      {...props}
    />
  );
}

export { Textarea };
