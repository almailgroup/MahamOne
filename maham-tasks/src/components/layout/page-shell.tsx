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
        // Maham One's page padding and width (its app/layout.tsx).
        "animate-rise mx-auto flex w-full flex-col gap-4 px-4 pt-5 pb-6",
        "sm:gap-6 sm:px-6 lg:px-8 lg:pt-6 lg:pb-10",
        width === "narrow" && "max-w-2xl",
        width === "wide" && "max-w-7xl",
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
    <header className="flex flex-wrap items-start justify-between gap-x-4 gap-y-3 sm:items-end">
      {/* basis-full below sm: the actions are shrink-0, so on a phone they won
          the row outright and truncated the page title to a couple of letters.
          They now wrap onto their own line and the title gets the full width. */}
      <div className="min-w-0 basis-full sm:flex-1 sm:basis-auto">
        <div className="flex items-center gap-2">
          {icon && (
            <span className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-primary-50 text-primary-600 [&_svg]:size-[1.125rem]">
              {icon}
            </span>
          )}
          <h1 className="truncate text-slate-900">{title}</h1>
          {meta}
        </div>
        {description && (
          <p
            /* Two lines at most on a phone: these are explanations somebody
               reads once, and a four-line paragraph pushes the work itself
               off the bottom of the screen every time after that. */
            className="mt-1 line-clamp-2 max-w-2xl text-sm text-slate-500 sm:line-clamp-none">
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
      <h2 className="flex items-center gap-1.5 text-sm font-semibold text-slate-700">
        {title}
        {count !== undefined && (
          <span className="tabular-nums font-medium text-slate-500">{count}</span>
        )}
      </h2>
      {actions}
    </div>
  );
}
