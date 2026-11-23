"use client";

import * as React from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  LayoutDashboard,
  ListChecks,
  ListFilter,
  Menu,
  Sunrise,
  type LucideIcon,
} from "lucide-react";

import { cn } from "@/lib/utils";
import { useI18n } from "@/lib/i18n/client";

/**
 * Thumb-reachable navigation for phones and small tablets.
 *
 * Every destination used to be two taps away behind a hamburger at the top
 * left of the screen — the hardest corner to reach one-handed. The four places
 * people actually live in are now one tap, and everything else (projects, the
 * team, the assistant) is behind "More", which opens the same drawer.
 *
 * Above `lg` the sidebar rail is always on screen, so this is hidden there.
 */
const ITEMS = [
  { href: "/today", label: "nav.today", icon: Sunrise },
  { href: "/tasks?filter=all", match: "/tasks", label: "nav.tasks", icon: ListFilter },
  // Home sits in the middle, where a thumb rests, and where every app that
  // has a home puts it.
  { href: "/dashboard", label: "nav.home", icon: LayoutDashboard },
  { href: "/my-list", label: "nav.myList", icon: ListChecks },
] as const;

export function BottomNav({ onOpenMore }: { onOpenMore: () => void }) {
  const pathname = usePathname();
  const { t } = useI18n();

  return (
    <nav
      aria-label={t("nav.tasks")}
      className={cn(
        // A floating pill, with no line across the screen. It stands off the
        // home indicator by the safe-area gap, and every page that sizes
        // itself to the screen leaves --nav-space for it.
        "chrome-touch fixed inset-x-3 bottom-[var(--safe-bottom)] z-30 h-[4.25rem] rounded-full lg:hidden",
        // Solid, not frosted: at any translucency the card underneath showed
        // through as ghosted text behind the labels.
        "bg-chrome shadow-[0_8px_30px_-6px_rgb(0_0_0/0.22),0_2px_8px_-2px_rgb(0_0_0/0.12)] ring-1 ring-foreground/[0.06]",
      )}
    >
      <ul className="mx-auto flex h-full max-w-lg items-stretch px-1.5">
        {ITEMS.map((item) => {
          const active = pathname === ("match" in item ? item.match : item.href);
          return (
            <li key={item.href} className="flex-1">
              <Link
                href={item.href}
                // Four links, always on screen: fetch the pages, not just
                // their skeletons. See the note on the sidebar's NavLink.
                prefetch
                aria-current={active ? "page" : undefined}
                className={itemClass(active)}
              >
                <NavGlyph icon={item.icon} label={t(item.label)} active={active} />
              </Link>
            </li>
          );
        })}

        <li className="flex-1">
          <button
            type="button"
            onClick={onOpenMore}
            aria-label={t("shell.moreLabel")}
            className={itemClass(false)}
          >
            <NavGlyph icon={Menu} label={t("shell.more")} active={false} />
          </button>
        </li>
      </ul>
    </nav>
  );
}

function itemClass(active: boolean) {
  return cn(
    "group flex h-full w-full flex-col items-center justify-center rounded-full outline-none",
    "focus-visible:ring-2 focus-visible:ring-ring",
    active ? "text-foreground" : "text-muted-foreground",
  );
}

/**
 * The icon and its label. The page you are on rises out of the row: its icon
 * sits in a soft, glowing wash of the theme's main colour, and the pair lifts a few
 * pixels with a little spring, so the choice is seen from the corner of the
 * eye rather than read. Everything else stays flat and quiet, and gives a
 * small press when touched.
 */
function NavGlyph({
  icon: Icon,
  label,
  active,
}: {
  icon: LucideIcon;
  label: string;
  active: boolean;
}) {
  return (
    <span
      data-active={active || undefined}
      className={cn(
        "flex flex-col items-center gap-1 transition-transform duration-300 ease-[cubic-bezier(0.34,1.56,0.64,1)] motion-reduce:transition-none",
        active ? "-translate-y-1" : "group-active:scale-90",
      )}
    >
      <span
        className={cn(
          "flex h-8 w-14 items-center justify-center rounded-full transition-[background-color,color,box-shadow] duration-300 motion-reduce:transition-none",
          // A wash of the theme's colour rather than a solid block of it,
          // strongest at the top and thinning towards the bar beneath, and a
          // glow of the same colour blurred out until it has no edge — so
          // the pill dissolves into the bar instead of sitting on it.
          //
          // The glow is a shadow because a shadow is drawn only outside the
          // pill: a blurred layer behind it would deepen the wash under the
          // icon too. tests/unit/themes.test.ts holds the icon to 3:1 where
          // the wash is strongest.
          active
            ? "bg-linear-to-b from-primary/24 to-primary/6 text-primary shadow-[0_5px_16px_-5px_color-mix(in_oklab,var(--primary)_42%,transparent),0_0_22px_-4px_color-mix(in_oklab,var(--primary)_20%,transparent)]"
            : "group-hover:bg-foreground/[0.06]",
        )}
      >
        <Icon className={cn("size-[1.15rem]", active && "stroke-[2.25]")} aria-hidden />
      </span>
      <span
        className={cn(
          "max-w-full truncate px-0.5 text-[0.6875rem] leading-none",
          active ? "font-semibold" : "font-medium",
        )}
      >
        {label}
      </span>
    </span>
  );
}
