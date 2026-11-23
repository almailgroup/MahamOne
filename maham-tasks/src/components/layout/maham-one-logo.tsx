import Image from "next/image";

import { cn } from "@/lib/utils";

/**
 * The Maham One logo, as Maham One shows it at the top of its sidebar: the
 * same files (public/brand, copied from Maham One's), with a white "Maham"
 * on dark themes. Its height sets its size (`h-8`); the width follows.
 *
 * `unoptimized`: the files are served as they are, so the service worker can
 * keep them for offline use (it keeps /brand/).
 */
export function MahamOneLogo({ className }: { className?: string }) {
  return (
    <span role="img" aria-label="Maham One" className={cn("inline-flex shrink-0", className)}>
      <Image
        src="/brand/maham-one-logo.png"
        alt=""
        width={955}
        height={192}
        priority
        unoptimized
        draggable={false}
        className="h-full w-auto dark:hidden"
      />
      <Image
        src="/brand/maham-one-logo-dark.png"
        alt=""
        width={955}
        height={192}
        unoptimized
        draggable={false}
        className="hidden h-full w-auto dark:block"
      />
    </span>
  );
}

/** The mark alone, where the name doesn't fit (the phone's top bar). */
export function MahamOneMark({ className }: { className?: string }) {
  return (
    <Image
      src="/brand/maham-one-mark.png"
      alt="Maham One"
      width={256}
      height={256}
      unoptimized
      draggable={false}
      className={cn("shrink-0 object-contain", className)}
    />
  );
}

/** Maham Tasks among Maham One's apps: its icon on its colour, as Maham One draws an app. */
export const TASKS_TONE = "bg-blue-100 text-blue-700";
