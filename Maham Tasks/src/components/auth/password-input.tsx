"use client";

import * as React from "react";
import { Eye, EyeOff } from "lucide-react";

import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import { useI18n } from "@/lib/i18n/client";

/**
 * A password field you can read back.
 *
 * Typing a password you cannot see is the main reason people fail to sign in
 * on a phone, where a long password and a soft keyboard make a typo likely and
 * invisible. The toggle is a real button so it is reachable by keyboard, and
 * it is excluded from the tab order between the field and the submit button —
 * `tabIndex={-1}` — so Tab still goes straight from the password to Sign in.
 *
 * It also warns about Caps Lock, which is the other half of the same problem:
 * the field is masked, so there is no way to notice.
 */
export function PasswordInput({
  id,
  name,
  autoComplete,
  required,
  invalid,
  placeholder,
  className,
  ...props
}: React.ComponentProps<"input"> & { invalid?: boolean }) {
  const { t } = useI18n();
  const [visible, setVisible] = React.useState(false);
  const [capsLock, setCapsLock] = React.useState(false);

  const onKey = (event: React.KeyboardEvent<HTMLInputElement>) => {
    // getModifierState is unavailable on some mobile keyboards; there it
    // simply never warns rather than warning wrongly.
    setCapsLock(event.getModifierState?.("CapsLock") ?? false);
  };

  return (
    <div className="flex flex-col gap-1.5">
      <div className="relative">
        <Input
          {...props}
          id={id}
          name={name}
          type={visible ? "text" : "password"}
          autoComplete={autoComplete}
          required={required}
          placeholder={placeholder}
          aria-invalid={invalid}
          onKeyUp={onKey}
          onKeyDown={onKey}
          onBlur={() => setCapsLock(false)}
          className={cn("pe-11", className)}
        />

        <button
          type="button"
          tabIndex={-1}
          onClick={() => setVisible((current) => !current)}
          aria-pressed={visible}
          aria-label={visible ? t("auth.hidePassword") : t("auth.showPassword")}
          title={visible ? t("auth.hidePassword") : t("auth.showPassword")}
          className={cn(
            "absolute end-1 top-1/2 flex size-8 -translate-y-1/2 items-center justify-center rounded-lg",
            "text-muted-foreground transition-colors hover:bg-accent hover:text-foreground",
            "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
            "pointer-coarse:size-9",
          )}
        >
          {visible ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
        </button>
      </div>

      {capsLock && (
        <p role="status" className="text-xs font-medium text-warning">
          {t("auth.capsLock")}
        </p>
      )}
    </div>
  );
}
