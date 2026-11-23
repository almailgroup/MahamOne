"use client";

import * as React from "react";
import Link from "next/link";
import { LogOut, User } from "lucide-react";

import {
  Avatar,
  AvatarFallback,
  AvatarImage,
} from "@/components/ui/avatar";
import { initialsFrom } from "@/lib/initials";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { signOut } from "@/lib/auth/actions";
import { roleMeta } from "@/lib/constants";
import type { Profile } from "@/lib/supabase/database.types";
import { useI18n } from "@/lib/i18n/client";

export function UserMenu({ profile }: { profile: Profile }) {
  const { t } = useI18n();
  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        className="flex items-center justify-center rounded-full transition-opacity hover:opacity-80 focus-visible:outline-none pointer-coarse:size-11"
        aria-label={t("shell.accountMenu")}
      >
        <Avatar>
          {profile.avatar_url && (
            <AvatarImage src={profile.avatar_url} alt="" />
          )}
          <AvatarFallback>
            {initialsFrom(profile.full_name, profile.email)}
          </AvatarFallback>
        </Avatar>
      </DropdownMenuTrigger>

      <DropdownMenuContent align="end" className="w-56">
        <DropdownMenuLabel className="flex flex-col gap-0.5 px-2.5 py-2">
          <span className="text-sm font-medium text-slate-900">
            {profile.full_name ?? profile.email}
          </span>
          <span className="truncate text-xs font-normal text-slate-500">
            {profile.email}
          </span>
          <span className="mt-1 text-xs font-normal text-slate-500">
            {t(roleMeta(profile.role).label)}
          </span>
        </DropdownMenuLabel>

        <DropdownMenuSeparator />

        <DropdownMenuItem asChild>
          <Link href="/profile">
            <User />
            {t("shell.profile")}
          </Link>
        </DropdownMenuItem>

        <DropdownMenuSeparator />

        {/* A form post keeps sign-out a non-idempotent POST rather than a link. */}
        <form action={signOut}>
          <button
            type="submit"
            className="relative flex w-full cursor-default select-none items-center gap-2 rounded-md px-2.5 py-2 text-sm text-slate-700 outline-none transition-colors hover:bg-slate-100 hover:text-slate-900 focus-visible:bg-slate-100 pointer-coarse:min-h-11"
          >
            <LogOut className="size-4 text-slate-400 rtl:-scale-x-100" />
            {t("shell.signOut")}
          </button>
        </form>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
