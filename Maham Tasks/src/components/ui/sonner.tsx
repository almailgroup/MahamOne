"use client";

import { useTheme } from "next-themes";

import { modeOf } from "@/lib/themes";
import { Toaster as Sonner, type ToasterProps } from "sonner";

/**
 * Toast host. Styling is pinned to the app's own tokens rather than Sonner's
 * defaults so notifications stay inside the monochrome scheme.
 */
function Toaster(props: ToasterProps) {
  const { resolvedTheme } = useTheme();

  return (
    <Sonner
      // Sonner knows light and dark; "midnight" would fall back to light.
      theme={resolvedTheme ? modeOf(resolvedTheme) : "system"}
      className="toaster group"
      position="bottom-right"
      // Clear of the navigation bar on a phone, which occupies the same
      // corner a toast would otherwise land in. The bar stands off the home
      // indicator, so the toast has to as well: a fixed 4.75rem put it
      // across the bar on every iPhone with one.
      mobileOffset={{
        bottom: "calc(var(--nav-space) + var(--safe-bottom))",
        left: "1rem",
        right: "1rem",
      }}
      toastOptions={{
        classNames: {
          toast:
            "group toast group-[.toaster]:bg-popover group-[.toaster]:text-popover-foreground group-[.toaster]:border-0 group-[.toaster]:shadow-lg group-[.toaster]:rounded-2xl",
          description: "group-[.toast]:text-muted-foreground",
          actionButton:
            "group-[.toast]:bg-primary group-[.toast]:text-primary-foreground",
          cancelButton:
            "group-[.toast]:bg-muted group-[.toast]:text-muted-foreground",
        },
      }}
      {...props}
    />
  );
}

export { Toaster };
