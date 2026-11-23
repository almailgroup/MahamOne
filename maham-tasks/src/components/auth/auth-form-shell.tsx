import Link from "next/link";

/** Shared framing for the auth cards: title, subtitle, and a footer line. */
export function AuthFormShell({
  title,
  subtitle,
  children,
  footer,
}: {
  title: string;
  subtitle: string;
  children: React.ReactNode;
  /** A line under the form; a link when it has somewhere to go. */
  footer?: { prompt: string; linkLabel?: string; href?: string };
}) {
  return (
    <div className="rounded-3xl bg-card p-6 shadow-[var(--shadow-md)]">
      <div className="mb-6 flex flex-col gap-1.5">
        <h1 className="text-lg font-semibold tracking-tight">{title}</h1>
        <p className="text-sm text-muted-foreground">{subtitle}</p>
      </div>

      {children}

      {footer && (
      <p className="mt-6 text-center text-sm text-muted-foreground">
        {footer.prompt}
        {footer.href && footer.linkLabel && (
          <>
            {" "}
            <Link
              href={footer.href}
              // At 18px tall it was a poor thumb target, so it gets real
              // padding on touch.
              className="font-medium text-foreground underline-offset-4 hover:underline pointer-coarse:inline-flex pointer-coarse:min-h-11 pointer-coarse:items-center pointer-coarse:px-2"
            >
              {footer.linkLabel}
            </Link>
          </>
        )}
      </p>
      )}
    </div>
  );
}
