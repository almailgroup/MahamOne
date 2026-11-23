"use client";

import * as React from "react";
import { Check, MonitorSmartphone, Palette } from "lucide-react";
import { useTheme } from "next-themes";

import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { useI18n } from "@/lib/i18n/client";
import { THEMES, type ThemeOption } from "@/lib/themes";
import { cn } from "@/lib/utils";

/**
 * Choosing a theme.
 *
 * This was a light/dark switch. Now it opens a menu: the device's own choice
 * first, then the light themes and the dark ones, each with a swatch drawn
 * from its own colours so the choice is made by eye rather than by name.
 *
 * Each theme is a tile, five to a row: the swatch with its name beneath.
 * Twenty themes as rows of a list are taller than a phone's screen once each
 * row is a full finger's height; as tiles, ten light and ten dark are two rows
 * each, and the whole menu fits on the smallest iPhone. It still scrolls if a
 * screen is shorter than that.
 *
 * Choosing does not close it. A theme is something you try on: pick one, see
 * the page in it, pick another. The menu used to shut on every choice, so
 * comparing two meant opening it again each time. It closes the usual ways —
 * a tap outside it, Escape, or the palette button again.
 *
 * Renders a stable placeholder until mounted. The stored theme lives in the
 * browser, so the server cannot know it, and drawing a tick next to the wrong
 * one for a frame is a hydration mismatch.
 */
export function ThemeToggle() {
  const { theme, setTheme } = useTheme();
  const { t } = useI18n();
  const [mounted, setMounted] = React.useState(false);

  React.useEffect(() => setMounted(true), []);

  if (!mounted) {
    return <Button variant="ghost" size="icon" aria-hidden className="opacity-0" />;
  }

  const active = theme ?? "system";
  const light = THEMES.filter((option) => option.mode === "light");
  const dark = THEMES.filter((option) => option.mode === "dark");

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon" aria-label={t("theme.title")} title={t("theme.title")}>
          <Palette className="size-4" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent
        align="end"
        collisionPadding={8}
        className="max-h-[var(--radix-dropdown-menu-content-available-height)] w-[21rem] overflow-y-auto p-2"
      >
        <DropdownMenuItem onSelect={keepOpen(() => setTheme("system"))} className="gap-2.5">
          <span className="flex size-6 items-center justify-center rounded-full bg-slate-100 text-slate-500 [&_svg]:size-3.5">
            <MonitorSmartphone />
          </span>
          <span className="flex-1 font-medium">{t("theme.system")}</span>
          {active === "system" && <Check className="size-4" />}
        </DropdownMenuItem>

        <DropdownMenuSeparator />
        <DropdownMenuLabel>{t("theme.groupLight")}</DropdownMenuLabel>
        <div className="grid grid-cols-5 gap-1">
          {light.map((option) => (
            <ThemeItem
              key={option.id}
              option={option}
              active={active === option.id}
              onSelect={keepOpen(() => setTheme(option.id))}
            />
          ))}
        </div>

        <DropdownMenuSeparator />
        <DropdownMenuLabel>{t("theme.groupDark")}</DropdownMenuLabel>
        <div className="grid grid-cols-5 gap-1">
          {dark.map((option) => (
            <ThemeItem
              key={option.id}
              option={option}
              active={active === option.id}
              onSelect={keepOpen(() => setTheme(option.id))}
            />
          ))}
        </div>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

/**
 * Wraps a menu item's choice so the menu stays open after it. Radix closes a
 * menu on select unless the event is cancelled.
 */
function keepOpen(choose: () => void) {
  return (event: Event) => {
    event.preventDefault();
    choose();
  };
}

function ThemeItem({
  option,
  active,
  onSelect,
}: {
  option: ThemeOption;
  active: boolean;
  onSelect: (event: Event) => void;
}) {
  const { t } = useI18n();
  return (
    <DropdownMenuItem
      onSelect={onSelect}
      title={t(option.label)}
      className="flex-col gap-1 px-0.5 pt-1.5 pb-1 text-[11px]"
    >
      <Swatch option={option} active={active} />
      <span className={cn("w-full truncate text-center", active && "font-semibold text-slate-900")}>
        {t(option.label)}
      </span>
      {active && <span className="sr-only">({t("theme.current")})</span>}
    </DropdownMenuItem>
  );
}

/**
 * The theme in miniature, as Maham One's own swatch draws it: its backdrop
 * with its main colour in the middle. Drawn from fixed values rather than the
 * live tokens, since every swatch has to show its own theme while the page is
 * wearing a different one. The one in use is ringed in the current theme's
 * main colour.
 */
function Swatch({ option, active }: { option: ThemeOption; active: boolean }) {
  const { ground, accent } = option.swatch;
  return (
    <span
      aria-hidden
      className={cn(
        "flex size-9 items-center justify-center rounded-full transition-shadow",
        active && "ring-2 ring-primary-600",
      )}
    >
      <span
        className="flex size-7 shrink-0 items-center justify-center rounded-full ring-1 ring-slate-900/15"
        style={{ backgroundColor: ground }}
      >
        <span className="size-4 rounded-full" style={{ backgroundColor: accent }} />
      </span>
    </span>
  );
}
