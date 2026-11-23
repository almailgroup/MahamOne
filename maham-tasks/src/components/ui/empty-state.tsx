import { cn } from "@/lib/utils";

/**
 * Empty states.
 *
 * There were four hand-rolled variants of this, all slightly different. One
 * component keeps them consistent, and gives each one room to actually say
 * what to do next instead of a bare line of grey text.
 */
export function EmptyState({
  icon,
  title,
  description,
  action,
  compact,
  className,
}: {
  icon?: React.ReactNode;
  title: string;
  description?: React.ReactNode;
  action?: React.ReactNode;
  /** Tighter padding, for empty states inside a panel rather than a page. */
  compact?: boolean;
  className?: string;
}) {
  return (
    <div
      className={cn(
        "flex flex-col items-center justify-center rounded-3xl bg-foreground/[0.035] text-center",
        compact ? "gap-2 px-4 py-8" : "gap-3 px-6 py-16",
        className,
      )}
    >
      {icon && (
        <span
          className={cn(
            "flex items-center justify-center rounded-full bg-primary/10 text-primary",
            compact ? "size-8 [&_svg]:size-4" : "size-11 [&_svg]:size-5",
          )}
          aria-hidden
        >
          {icon}
        </span>
      )}

      <div className="flex flex-col gap-1">
        <p className={cn("font-medium", compact ? "text-sm" : "text-base")}>
          {title}
        </p>
        {description && (
          <p className="mx-auto max-w-sm text-sm leading-relaxed text-muted-foreground">
            {description}
          </p>
        )}
      </div>

      {action && <div className="mt-1">{action}</div>}
    </div>
  );
}
