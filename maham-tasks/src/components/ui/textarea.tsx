import * as React from "react";

import { cn } from "@/lib/utils";

function Textarea({ className, ...props }: React.ComponentProps<"textarea">) {
  return (
    <textarea
      data-slot="textarea"
      className={cn(
        "flex min-h-20 w-full px-3 py-2 leading-relaxed rounded-lg border border-slate-300 bg-surface text-sm text-slate-900 shadow-xs transition-colors hover:border-slate-400 focus-visible:border-primary-500 focus-visible:ring-3 focus-visible:ring-primary-500/15 focus-visible:outline-none aria-invalid:border-red-400 aria-invalid:ring-3 aria-invalid:ring-red-500/15",
        "placeholder:text-slate-400",
        "disabled:cursor-not-allowed disabled:bg-slate-50 disabled:text-slate-500",
        className,
      )}
      {...props}
    />
  );
}

export { Textarea };
