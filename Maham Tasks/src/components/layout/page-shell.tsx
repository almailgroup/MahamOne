import { cn } from "@/lib/utils";

/**
 * One page container for the whole app.
 *
 * Before this, three different pages used three different max-widths and
 * paddings, so moving between them shifted the content sideways. Everything
 * now sits on the same rhythm.
 */
export function PageShell({
  children,
  width = "wide",
  className,
}: {
  children: React.ReactNode;
  /** `narrow` for single-column forms, `wide` for boards and lists. */
  width?: "narrow" | "wide" | "full";
  className?: string;
}) {
  return (
    <div
      className={cn(
        // Tighter on a phone. The same padding that frames a page nicely at
        // 1440px is a fifth of the screen at 390, and it is spent before the
        // page has shown anything.
        "animate-rise mx-auto flex w-full flex-col gap-3 px-4 py-3.5",
        "sm:gap-5 sm:px-6 sm:py-6 lg:py-8",
        width === "narrow" && "max-w-2xl",
        width === "wide" && "max-w-6xl",
        className,
      )}
    >
      {children}
    </div>
  );
}

/**
 * Page title block. `actions` sits on the same optical line as the title and
 * wraps beneath it on narrow screens rather than squeezing.
 */
export function PageHeader({
  title,
  description,
  icon,
  actions,
  meta,
}: {
  title: React.ReactNode;
  description?: React.ReactNode;
  icon?: React.ReactNode;
  actions?: React.ReactNode;
  meta?: React.ReactNode;
}) {
  return (
    <header className="flex flex-wrap items-start justify-between gap-x-4 gap-y-2.5 sm:gap-y-3">
      {/* basis-full below sm: the actions are shrink-0, so on a phone they won
          the row outright and truncated the page title to a couple of letters.
          They now wrap onto their own line and the title gets the full width. */}
      <div className="min-w-0 basis-full sm:flex-1 sm:basis-auto">
        <div className="flex items-center gap-2">
          {icon && (
            <span className="flex size-9 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary [&_svg]:size-[1.125rem]">
              {icon}
            </span>
          )}
          <h1 className="truncate">{title}</h1>
          {meta}
        </div>
        {description && (
          <p
            /* Two lines at most on a phone: these are explanations somebody
               reads once, and a four-line paragraph pushes the work itself
               off the bottom of the screen every time after that. */
            className="mt-0.5 line-clamp-2 max-w-2xl text-xs leading-relaxed text-muted-foreground sm:mt-1.5 sm:line-clamp-none sm:text-sm">
            {description}
          </p>
        )}
      </div>

      {actions && (
        <div className="flex shrink-0 flex-wrap items-center gap-2">{actions}</div>
      )}
    </header>
  );
}

/**
 * Section heading inside a page, a step down from PageHeader.
 */
export function SectionHeader({
  title,
  count,
  actions,
}: {
  title: React.ReactNode;
  count?: number;
  actions?: React.ReactNode;
}) {
  return (
    <div className="flex items-center justify-between gap-3">
      <h2 className="flex items-center gap-1.5 text-sm font-medium">
        {title}
        {count !== undefined && (
          <span className="tabular-nums text-muted-foreground">{count}</span>
        )}
      </h2>
      {actions}
    </div>
  );
}
