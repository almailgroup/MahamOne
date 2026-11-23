import type { Metadata } from "next";
import { Suspense } from "react";

import { AuthFormShell } from "@/components/auth/auth-form-shell";
import { SecondStepForm } from "@/components/auth/second-step-form";
import { Skeleton } from "@/components/ui/skeleton";
import { getI18n } from "@/lib/i18n/server";

export async function generateMetadata(): Promise<Metadata> {
  const { t } = await getI18n();
  return { title: t("auth.twoStep.title") };
}

/**
 * The second half of signing in, for anybody with an authenticator app. The
 * middleware sends every page here until the code has been entered.
 */
export default async function SecondStepPage() {
  const { t } = await getI18n();

  return (
    <AuthFormShell title={t("auth.twoStep.title")} subtitle={t("auth.twoStep.subtitle")}>
      {/* Reads the search params, so it needs a Suspense boundary. */}
      <Suspense fallback={<Skeleton className="h-40 w-full" />}>
        <SecondStepForm />
      </Suspense>
    </AuthFormShell>
  );
}
