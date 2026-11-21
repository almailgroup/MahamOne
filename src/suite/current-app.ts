import { useCallback, useEffect, useMemo, useSyncExternalStore } from 'react';
import { useLocation, useNavigate } from 'react-router';
import { useCompany } from '@/app/company';
import { useRoleView } from '@/features/cloud/role-gates';
import { accessMap, appById, appForPath, appsFor, canOpen, isAppId, type AccessMap } from './apps';
import type { AppId, SuiteApp } from './types';

/**
 * The app open in the shell. Pages belong to an app by their URL
 * (src/suite/apps.ts), in the company's layout of apps; the suite's own
 * pages (Home, Settings) keep the sidebar of the last app used, remembered
 * in this browser.
 */

// Old storage names stay (src/lib/brand.ts).
const LAST_APP_KEY = 'almailbooks.suite.app';

function readLast(): AppId | null {
  try {
    const saved = localStorage.getItem(LAST_APP_KEY);
    return isAppId(saved) ? saved : null;
  } catch {
    return null;
  }
}

let last: AppId | null = readLast();
const listeners = new Set<() => void>();

export function rememberApp(id: AppId): void {
  if (id === last) return;
  last = id;
  try {
    localStorage.setItem(LAST_APP_KEY, id);
  } catch {
    // Not saved; the choice still applies to this visit.
  }
  listeners.forEach((listener) => listener());
}

/**
 * Opens an app chosen as a whole (the switcher, the phone's app tiles, the
 * home's tiles, the palette's apps): remembered first, so its home opens
 * with its own sidebar even where the last app shares that page (in the
 * split layout Books lists Sales' invoices and Inventory's stock).
 */
export function useOpenApp(): (app: Pick<SuiteApp, 'id' | 'home'>) => void {
  const navigate = useNavigate();
  return useCallback(
    (app) => {
      rememberApp(app.id);
      void navigate(app.home);
    },
    [navigate],
  );
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

/** For tests: the last app remembered. */
export function lastApp(): AppId | null {
  return last;
}

/** For tests: forget the last app. */
export function resetLastApp(): void {
  last = null;
  listeners.forEach((listener) => listener());
}

function useLastApp(): AppId | null {
  return useSyncExternalStore(subscribe, () => last);
}

/**
 * The apps of the current company, in its layout: today's four, or Sales,
 * Books and Inventory in place of Books once it split them (Settings → Team).
 */
export function useApps(): readonly SuiteApp[] {
  return appsFor(useCompany());
}

/** What the person may do in each app of the current company. */
export function useAppAccess(): AccessMap {
  const { role, known, permissions } = useRoleView();
  const apps = useApps();
  return useMemo(() => accessMap(role, known, permissions, apps), [role, known, permissions, apps]);
}

/**
 * The app the shell shows: the one the page belongs to, or the last one on
 * the suite's own pages. An app the person may not open is never shown:
 * staff on a People page see Books around the lock card. The last app is
 * forgotten when it isn't in the layout (Sales, after the layout went back
 * to the four apps). When neither can be opened (CRM remembered, but the
 * owner closed it), the page's owner in the layout (Sales for quotes in
 * the split layout), and Books after that.
 */
export function useCurrentApp(): SuiteApp {
  const { pathname } = useLocation();
  const apps = useApps();
  const access = useAppAccess();
  const remembered = useLastApp();
  const fromPath = appForPath(pathname, remembered, apps);
  const owner = appForPath(pathname, null, apps);
  const id = [fromPath, remembered, owner].find(
    (candidate): candidate is AppId =>
      candidate != null && isAppId(candidate, apps) && canOpen(access[candidate]),
  );
  return appById(id ?? 'books', apps);
}

/**
 * Remembers the app of the page being visited, for the suite's own pages:
 * its owner when the app that shares it can't be opened.
 */
export function useRememberApp(): void {
  const { pathname } = useLocation();
  const apps = useApps();
  const access = useAppAccess();
  const remembered = useLastApp();
  const fromPath = appForPath(pathname, remembered, apps);
  const owner = appForPath(pathname, null, apps);
  const id = [fromPath, owner].find(
    (candidate): candidate is AppId => candidate != null && canOpen(access[candidate]),
  );
  useEffect(() => {
    if (id) rememberApp(id);
  }, [id]);
}
