import { Skeleton } from "@/components/ui/skeleton";

/**
 * Route-level loading placeholders.
 *
 * Every authenticated page is server-rendered and runs several Supabase
 * queries, so without these a navigation showed the previous page frozen until
 * the new one was ready. These mirror the real layout closely enough that the
 * content lands where the placeholder was rather than reflowing.
 */

function HeaderSkeleton() {
  return (
    <div className="flex items-start justify-between gap-4">
      <div className="flex flex-col gap-2">
        <Skeleton className="h-7 w-48" />
        <Skeleton className="h-4 w-64" />
      </div>
      <Skeleton className="h-9 w-28" />
    </div>
  );
}

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col gap-5 px-4 py-6 sm:px-6 lg:py-8">
      {children}
    </div>
  );
}

/** Metric tiles over two list panels. */
export function DashboardSkeleton() {
  return (
    <Shell>
      <HeaderSkeleton />
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6">
        {Array.from({ length: 6 }).map((_, index) => (
          <Skeleton key={index} className="h-[6.5rem] rounded-lg" />
        ))}
      </div>
      <Skeleton className="h-24 rounded-lg" />
      <div className="grid grid-cols-1 gap-3 lg:grid-cols-2">
        <Skeleton className="h-64 rounded-lg" />
        <Skeleton className="h-64 rounded-lg" />
      </div>
    </Shell>
  );
}

/** Four Kanban columns. */
export function BoardSkeleton() {
  return (
    <Shell>
      <HeaderSkeleton />
      <div className="flex flex-wrap gap-2">
        <Skeleton className="h-9 w-40" />
        <Skeleton className="h-9 w-48" />
        <Skeleton className="h-9 w-32" />
      </div>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {Array.from({ length: 4 }).map((_, column) => (
          <div key={column} className="flex flex-col gap-2 rounded-3xl bg-foreground/[0.04] p-2">
            <Skeleton className="h-4 w-24" />
            {Array.from({ length: column === 0 ? 3 : 2 }).map((_, card) => (
              <Skeleton key={card} className="h-[4.5rem] rounded-md" />
            ))}
          </div>
        ))}
      </div>
    </Shell>
  );
}

/** A stack of rows. */
export function ListSkeleton({ rows = 6 }: { rows?: number }) {
  return (
    <Shell>
      <HeaderSkeleton />
      <div className="flex flex-col gap-2">
        {Array.from({ length: rows }).map((_, index) => (
          <Skeleton key={index} className="h-16 rounded-lg" />
        ))}
      </div>
    </Shell>
  );
}

/** Single-column form page. */
export function FormSkeleton() {
  return (
    <div className="mx-auto flex w-full max-w-2xl flex-col gap-5 px-4 py-6 sm:px-6 lg:py-8">
      <HeaderSkeleton />
      <Skeleton className="h-72 rounded-lg" />
      <Skeleton className="h-48 rounded-lg" />
    </div>
  );
}

/**
 * The two panes of Messages, at the height the shell itself uses.
 *
 * Not a ListSkeleton: this route is not a page inside the shell's padding,
 * it is a full-height split, and a centred list of rows would jump sideways
 * the moment the real thing arrived.
 */
export function MessagesSkeleton() {
  return (
    <div className="flex h-[calc(100svh-3.5rem-var(--nav-space)-var(--safe-top)-var(--safe-bottom))] flex-col lg:h-[calc(100svh-3.5rem-var(--panel-gap))] lg:flex-row">
      <div className="flex min-h-0 flex-col gap-2 p-3 lg:w-80 lg:shrink-0 xl:w-96">
        <Skeleton className="h-9 rounded-lg" />
        {Array.from({ length: 7 }).map((_, index) => (
          <Skeleton key={index} className="h-14 rounded-lg" />
        ))}
      </div>
      <div className="hidden min-h-0 flex-1 flex-col gap-3 p-4 lg:flex">
        <Skeleton className="h-10 w-48 rounded-lg" />
        <div className="flex flex-1 flex-col justify-end gap-3">
          <Skeleton className="h-12 w-2/3 rounded-2xl" />
          <Skeleton className="h-12 w-1/2 self-end rounded-2xl" />
          <Skeleton className="h-12 w-3/5 rounded-2xl" />
        </div>
        <Skeleton className="h-11 rounded-xl" />
      </div>
    </div>
  );
}
