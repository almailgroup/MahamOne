import { redirect } from "next/navigation";

import { AppShell } from "@/components/layout/app-shell";
import { TimeZoneCookie } from "@/components/layout/timezone-cookie";
import { HolidaysProvider } from "@/components/work-calendar/holidays-provider";
import { LabelsProvider } from "@/components/labels/labels-provider";
import { OutboxProvider } from "@/components/offline/outbox-provider";
import {
  SIDEBAR_DEFAULT,
  SIDEBAR_MAX,
  SIDEBAR_MIN,
  SIDEBAR_STORAGE_KEY,
} from "@/lib/sidebar";
import {
  getHolidays,
  getLabels,
  getNotifications,
  getProjects,
  getUnreadDirectCount,
  getUnreadNotificationCount,
  needsOwnPassword,
  requireProfile,
} from "@/lib/data/queries";

/**
 * Authenticated layout. `requireProfile()` redirects to /login when there is no
 * session, which makes this a second gate behind the middleware.
 */
export default async function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  // All of these together, not the password check and then the rest. Only the
  // profile actually depends on knowing who is asking; the other three are
  // scoped by row-level security and could always have been on their way
  // while the question was being answered. Awaiting the check on its own put
  // a whole round trip in front of them for nothing.
  const [
    mustChangePassword,
    profile,
    projects,
    notifications,
    unreadCount,
    unreadMessages,
    holidays,
    labels,
  ] = await Promise.all([
    needsOwnPassword(),
    requireProfile(),
    getProjects(),
    getNotifications(),
    getUnreadNotificationCount(),
    getUnreadDirectCount(),
    getHolidays(),
    getLabels(),
  ]);

  // Nobody works out of an account whose password was handed to them. The
  // page this leads to is outside this layout, so there is nothing to loop on.
  if (mustChangePassword) redirect("/set-password");

  return (
    <>
      {/*
       * Apply the stored sidebar width before first paint. Without this the
       * rail renders at the default and visibly snaps once React hydrates —
       * the same problem, and the same fix, as a theme flash.
       */}
      <script
        dangerouslySetInnerHTML={{
          __html: `(function(){try{var w=localStorage.getItem('${SIDEBAR_STORAGE_KEY}');if(w){var n=Math.min(${SIDEBAR_MAX},Math.max(${SIDEBAR_MIN},parseInt(w,10)||${SIDEBAR_DEFAULT}));document.documentElement.style.setProperty('--sidebar-width',n+'px');}}catch(e){}})();`,
        }}
      />
      <TimeZoneCookie />

      {/* Holidays reach every date shortcut and the calendar from here, and
          labels every task. The outbox holds what is done with no signal. */}
      <HolidaysProvider holidays={holidays}>
        <LabelsProvider labels={labels}>
          <OutboxProvider me={profile.id}>
            <AppShell
              profile={profile}
              projects={projects}
              notifications={notifications}
              unreadCount={unreadCount}
              unreadMessages={unreadMessages}
            >
              {children}
            </AppShell>
          </OutboxProvider>
        </LabelsProvider>
      </HolidaysProvider>
    </>
  );
}
