import type { Metadata } from "next";

import { AuthFormShell } from "@/components/auth/auth-form-shell";
import { getI18n } from "@/lib/i18n/server";
import { ResetPasswordForm } from "@/components/auth/reset-password-form";

export async function generateMetadata(): Promise<Metadata> {
  const { t } = await getI18n();
  return { title: t("auth.reset.title") };
}

/**
 * Reached only from a password-reset email: the callback exchanges the link
 * for a session before forwarding here, so this page is behind the middleware
 * like any other signed-in route. Someone arriving without a valid link has no
 * session and is sent to sign in, which is the correct answer.
 */
export default async function ResetPasswordPage() {
  const { t } = await getI18n();

  return (
    <AuthFormShell
      title={t("auth.reset.title")}
      subtitle={t("auth.reset.subtitle")}
    >
      <ResetPasswordForm />
    </AuthFormShell>
  );
}
