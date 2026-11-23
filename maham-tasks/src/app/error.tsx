"use client";

import * as React from "react";
import { RotateCcw } from "lucide-react";

import { Button } from "@/components/ui/button";
import { reportClientError } from "@/lib/data/error-actions";
import { useI18n } from "@/lib/i18n/client";

/**
 * Route-level error boundary. Deliberately generic: the underlying message can
 * contain internals, so it is logged rather than rendered.
 */
export default function ErrorBoundary({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  const { t } = useI18n();

  React.useEffect(() => {
    console.error(error);

    // And somewhere a person will actually look. The console is on the
    // phone that hit the fault, which is the one place nobody reads.
    void reportClientError({
      message: `${error.name}: ${error.message}`,
      route: window.location.pathname + window.location.search,
      digest: error.digest,
      userAgent: navigator.userAgent,
    });
  }, [error]);

  return (
    <div className="flex min-h-svh items-center justify-center bg-background px-4">
      <div className="w-full max-w-sm rounded-3xl bg-card p-6 text-center shadow-[var(--shadow-md)]">
        <h1 className="text-base font-semibold tracking-tight">
          {t("error.title")}
        </h1>
        <p className="mt-1.5 text-sm leading-relaxed text-muted-foreground">
          {t("error.body")}
        </p>
        {error.digest && (
          <p className="mt-3 font-mono text-xs text-muted-foreground">
            {t("error.reference", { digest: error.digest })}
          </p>
        )}
        <Button variant="outline" size="sm" className="mt-4" onClick={reset}>
          <RotateCcw />
          {t("error.retry")}
        </Button>
      </div>
    </div>
  );
}
