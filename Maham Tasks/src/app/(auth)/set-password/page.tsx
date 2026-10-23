import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { AuthFormShell } from "@/components/auth/auth-form-shell";
import { getI18n } from "@/lib/i18n/server";
import { ResetPasswordForm } from "@/components/auth/reset-password-form";
import { needsOwnPassword } from "@/lib/data/queries";

export async function generateMetadata(): Promise<Metadata> {
  const { t } = await getI18n();
  return { title: t("auth.setPassword.title") };
}

/**
 * First sign-in for an account an admin created.
 *
 * They arrive holding a password somebody else picked and wrote down, which is
 * exactly as private as wherever it was written. The app asks for a new one
 * before anything else, and the layout of the signed-in app sends them here
 * until they have chosen it.
 *
 * Behind the middleware like every other private route, and outside the app
 * shell so the redirect that brings people here cannot loop.
 */
export default async function SetPasswordPage() {
  // Someone who has already chosen has no business on this page.
  if (!(await needsOwnPassword())) redirect("/dashboard");
  const { t } = await getI18n();

  return (
    <AuthFormShell
      title={t("auth.setPassword.title")}
      subtitle={t("auth.setPassword.subtitle")}
      footer={{
        prompt: t("auth.setPassword.prompt"),
        linkLabel: t("shell.signOut"),
        href: "/auth/signout",
      }}
    >
      <ResetPasswordForm />
    </AuthFormShell>
  );
}
