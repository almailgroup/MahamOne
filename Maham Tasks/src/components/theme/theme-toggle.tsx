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
 * Thirty themes as rows of a list, even in two columns, are taller than a
 * phone's screen once each row is a full finger's height; as tiles, fifteen
 * light and fifteen dark are three rows each, and the whole menu fits on the
 * smallest iPhone. It still scrolls if a screen is shorter than that.
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
        className="max-h-[var(--radix-dropdown-menu-content-available-height)] w-[21rem] overflow-y-auto"
      >
        <DropdownMenuItem onSelect={keepOpen(() => setTheme("system"))} className="gap-2.5">
          <span className="flex size-6 items-center justify-center rounded-full bg-muted [&_svg]:size-3.5">
            <MonitorSmartphone />
          </span>
          <span className="flex-1">{t("theme.system")}</span>
          {active === "system" && <Check className="size-4" />}
        </DropdownMenuItem>

        <DropdownMenuSeparator />
        <DropdownMenuLabel>{t("theme.groupLight")}</DropdownMenuLabel>
        <div className="grid grid-cols-5 gap-0.5">
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
        <div className="grid grid-cols-5 gap-0.5">
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
      <span className={cn("w-full truncate text-center", active && "font-semibold")}>
        {t(option.label)}
      </span>
      {active && <span className="sr-only">({t("theme.current")})</span>}
    </DropdownMenuItem>
  );
}

/**
 * The theme in miniature: its page, a card on it, and its main colour.
 * Drawn from fixed values rather than the live tokens, since every swatch has
 * to show its own theme while the page is wearing a different one. The one
 * in use is ringed in the current theme's own focus colour.
 */
function Swatch({ option, active }: { option: ThemeOption; active: boolean }) {
  const { ground, card, accent } = option.swatch;
  return (
    <span
      aria-hidden
      className={cn("rounded-full p-0.5 ring-2 ring-transparent", active && "ring-ring")}
    >
      <span
        className={cn(
          "relative flex size-8 shrink-0 items-end justify-end overflow-hidden rounded-full p-1",
          "ring-1 ring-foreground/15 ring-inset",
        )}
        style={{ background: ground }}
      >
        <span
          className="absolute start-1 top-1 size-4 rounded-full"
          style={{ background: card }}
        />
        <span className="relative size-3 rounded-full" style={{ background: accent }} />
      </span>
    </span>
  );
}
