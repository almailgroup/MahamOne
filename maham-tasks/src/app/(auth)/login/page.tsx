import type { Metadata } from "next";
import { Suspense } from "react";

import { AuthFormShell } from "@/components/auth/auth-form-shell";
import { getI18n } from "@/lib/i18n/server";
import { LoginForm } from "@/components/auth/login-form";
import { Skeleton } from "@/components/ui/skeleton";

export async function generateMetadata(): Promise<Metadata> {
  const { t } = await getI18n();
  return { title: t("auth.login.title") };
}

export default async function LoginPage() {
  const { t } = await getI18n();

  return (
    <AuthFormShell
      title={t("auth.login.title")}
      subtitle={t("auth.login.subtitle")}
      // No "create one": accounts are added by an admin from the Team page,
      // and the database refuses any other kind (close_self_registration).
      footer={{ prompt: t("auth.login.prompt") }}
    >
      {/* LoginForm reads search params, so it needs a Suspense boundary. */}
      <Suspense fallback={<Skeleton className="h-56 w-full" />}>
        <LoginForm />
      </Suspense>
    </AuthFormShell>
  );
}
