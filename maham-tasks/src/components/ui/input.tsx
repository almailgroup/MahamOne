import * as React from "react";

import { cn } from "@/lib/utils";

function Input({ className, type, ...props }: React.ComponentProps<"input">) {
  return (
    <input
      type={type}
      data-slot="input"
      className={cn(
        "flex h-9 w-full px-3 py-1 pointer-coarse:h-11 rounded-lg border border-slate-300 bg-surface text-sm text-slate-900 shadow-xs transition-colors hover:border-slate-400 focus-visible:border-primary-500 focus-visible:ring-3 focus-visible:ring-primary-500/15 focus-visible:outline-none aria-invalid:border-red-400 aria-invalid:ring-3 aria-invalid:ring-red-500/15",
        "placeholder:text-slate-400",
        "file:border-0 file:bg-transparent file:text-sm file:font-medium file:text-foreground",
        "disabled:cursor-not-allowed disabled:bg-slate-50 disabled:text-slate-500",
                className,
      )}
      {...props}
    />
  );
}

export { Input };
