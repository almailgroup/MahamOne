import type { Metadata } from "next";

import { AuthFormShell } from "@/components/auth/auth-form-shell";
import { getI18n } from "@/lib/i18n/server";
import { ForgotPasswordForm } from "@/components/auth/forgot-password-form";

export async function generateMetadata(): Promise<Metadata> {
  const { t } = await getI18n();
  return { title: t("auth.forgot.title") };
}

export default async function ForgotPasswordPage() {
  const { t } = await getI18n();

  return (
    <AuthFormShell
      title={t("auth.forgot.title")}
      subtitle={t("auth.forgot.subtitle")}
    >
      <ForgotPasswordForm />
    </AuthFormShell>
  );
}
