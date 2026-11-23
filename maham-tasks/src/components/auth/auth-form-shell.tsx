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
    <div className="rounded-xl border border-slate-200 bg-surface p-5 shadow-xs sm:p-8">
      <div className="mb-6 flex flex-col gap-1.5">
        <h1 className="text-2xl font-semibold tracking-tight text-balance text-slate-900">{title}</h1>
        <p className="text-sm text-pretty text-slate-600">{subtitle}</p>
      </div>

      {children}

      {footer && (
      <p className="mt-6 text-center text-sm text-slate-600">
        {footer.prompt}
        {footer.href && footer.linkLabel && (
          <>
            {" "}
            <Link
              href={footer.href}
              // At 18px tall it was a poor thumb target, so it gets real
              // padding on touch.
              className="font-medium text-primary-700 underline-offset-4 hover:underline pointer-coarse:inline-flex pointer-coarse:min-h-11 pointer-coarse:items-center pointer-coarse:px-2"
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
