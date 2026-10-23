"use client";

import * as React from "react";
import { Check, Languages } from "lucide-react";

import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { LOCALES, LOCALE_LABELS } from "@/lib/i18n";
import { useI18n, useSetLocale } from "@/lib/i18n/client";

/**
 * Language, in the header, next to the theme.
 *
 * Each language is named in itself — "العربية", not "Arabic" — because the
 * person looking for their language may not read the one currently showing.
 */
export function LanguageSelector() {
  const { locale, t } = useI18n();
  const setLocale = useSetLocale();

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon" aria-label={t("shell.language")}>
          <Languages className="size-4" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="min-w-[10rem]">
        {LOCALES.map((option) => (
          <DropdownMenuItem
            key={option}
            onSelect={() => setLocale(option)}
            lang={option}
            dir={option === "ar" ? "rtl" : "ltr"}
          >
            <Check className={option === locale ? "size-4" : "size-4 opacity-0"} />
            {LOCALE_LABELS[option]}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
