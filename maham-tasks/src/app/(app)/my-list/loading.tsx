import { Skeleton } from "@/components/ui/skeleton";

export default function Loading() {
  return (
    <div className="flex h-[calc(100svh-3.5rem-var(--panel-gap))] flex-col lg:flex-row">
      <div className="flex flex-col gap-3 p-4 lg:w-80 lg:shrink-0 xl:w-96">
        <Skeleton className="h-7 w-28" />
        <Skeleton className="h-9 w-full" />
        {[0, 1, 2, 3].map((row) => (
          <Skeleton key={row} className="h-14 w-full rounded-lg" />
        ))}
      </div>
      <div className="hidden flex-1 flex-col gap-4 p-6 lg:flex">
        <Skeleton className="h-8 w-64" />
        {[0, 1, 2].map((row) => (
          <Skeleton key={row} className="h-6 w-full max-w-md" />
        ))}
      </div>
    </div>
  );
}
