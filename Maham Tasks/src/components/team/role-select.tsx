"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";

import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { USER_ROLES } from "@/lib/constants";
import { useI18n } from "@/lib/i18n/client";
import { updateMemberRole } from "@/lib/data/profile-actions";
import type { UserRole } from "@/lib/supabase/database.types";

/** Admin-only control for changing a member's role. */
export function RoleSelect({
  userId,
  role,
  disabled,
}: {
  userId: string;
  role: UserRole;
  disabled?: boolean;
}) {
  const router = useRouter();
  const { t, tm } = useI18n();
  const [pending, setPending] = React.useState(false);
  const [value, setValue] = React.useState<UserRole>(role);

  async function onChange(next: string) {
    const nextRole = next as UserRole;
    const previous = value;

    setValue(nextRole);
    setPending(true);
    const outcome = await updateMemberRole(userId, nextRole);
    setPending(false);

    if (!outcome.ok) {
      setValue(previous); // Roll the control back to the server's truth.
      toast.error(tm(outcome.error));
      return;
    }

    toast.success(t("team.roleUpdated"));
    router.refresh();
  }

  return (
    <Select value={value} onValueChange={onChange} disabled={disabled || pending}>
      <SelectTrigger size="sm" className="w-[9rem] sm:w-[9.5rem]">
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        {USER_ROLES.map((option) => (
          <SelectItem key={option.value} value={option.value}>
            {t(option.label)}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
