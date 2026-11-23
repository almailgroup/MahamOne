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
        // Maham One's tab bar (its features/shell/bottom-bar.tsx): a floating
        // rounded bar clear of the home indicator by the safe-area gap. Every
        // page that sizes itself to the screen leaves --nav-space for it.
        "chrome-touch fixed inset-x-3 bottom-[var(--safe-bottom)] z-30 h-16 rounded-2xl lg:hidden",
        // Solid, not frosted: at any translucency the card underneath showed
        // through as ghosted text behind the labels.
        "bg-surface shadow-[0_10px_30px_-8px_rgb(15_23_42/0.3)] ring-1 ring-slate-900/5",
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
    "group flex h-full w-full flex-col items-center justify-center rounded-xl outline-none",
    "focus-visible:ring-2 focus-visible:ring-ring",
    active ? "text-primary-700" : "text-slate-600",
  );
}

/**
 * The icon and its label. The page you are on is in the main colour, as in
 * Maham One, and the pair lifts a few pixels with a little spring, so the
 * choice is seen from the corner of the eye rather than read.
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
        active && "-translate-y-1",
      )}
    >
      <span className="flex h-6 w-14 items-center justify-center transition-colors">
        <Icon className="size-5" aria-hidden />
      </span>
      <span className="max-w-full truncate px-0.5 text-xs leading-none font-medium">
        {label}
      </span>
    </span>
  );
}
