import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { db } from '@/db/db';
import { saveCompany, setupCompany } from '@/db/records';
import type { Company } from '@/db/types';
import { CompanyProvider } from '@/app/company';
import type { CloudLink } from '@/cloud/types';
import type { MemberPermissions, MemberRole } from '@/cloud/roles';
import { SALES } from '@/apps/sales/manifest';
import { INVENTORY } from '@/apps/inventory/manifest';
import {
  lastApp,
  rememberApp,
  resetLastApp,
  useApps,
  useCurrentApp,
  useOpenApp,
  useRememberApp,
} from './current-app';
import type { SuiteApp } from './types';

/**
 * The app the shell shows, in each layout of the apps (#3): the page's app,
 * or the last one used on the suite's own pages, and Books when the last
 * one isn't in the company's layout any more. Made-up data only.
 */

function Probe() {
  const app = useCurrentApp();
  const apps = useApps();
  // What the switcher, the app tiles and the palette do: open an app as a whole.
  const openApp = useOpenApp();
  useRememberApp();
  return (
    <>
      <p>
        {app.id} of {apps.map((a) => a.id).join(',')}
      </p>
      {[SALES, INVENTORY].map((chosen) => (
        <button key={chosen.id} type="button" onClick={() => openApp(chosen)}>
          {`open ${chosen.id}`}
        </button>
      ))}
    </>
  );
}

/**
 * Opens an app as a person would: after React has remembered the app on
 * screen (useRememberApp's effect), as it has long before anybody can click.
 * Clicked sooner, on a busy machine, that effect runs after the click and
 * puts the old app back.
 */
async function choose(app: SuiteApp) {
  const onScreen = () => screen.getByText(/ of /).textContent?.split(' of ')[0];
  await waitFor(() => expect(lastApp()).toBe(onScreen()));
  fireEvent.click(screen.getByRole('button', { name: `open ${app.id}` }));
}

/** The company kept in the cloud, with this role and the owner's limits. */
async function linkAs(role: MemberRole, permissions?: MemberPermissions) {
  const link: CloudLink = {
    companyId: company.id,
    userId: 'user-1',
    role,
    status: 'ready',
    cursor: 0,
    name: company.name,
    linkedAt: new Date().toISOString(),
    lastSyncAt: null,
    lastError: null,
    lastErrorAt: null,
    permissions,
  };
  await db.syncState.put(link);
}

async function show(path: string) {
  const router = createMemoryRouter(
    [
      {
        path: '*',
        element: (
          <CompanyProvider fallback={<p>Loading</p>} onboarding={<p>Welcome</p>}>
            <Probe />
          </CompanyProvider>
        ),
      },
    ],
    { initialEntries: [path] },
  );
  render(<RouterProvider router={router} />);
  return router;
}

const shown = async (text: string) => expect(await screen.findByText(text)).toBeInTheDocument();

let company: Company;

beforeEach(async () => {
  await db.delete();
  await db.open();
  resetLastApp();
  company = await setupCompany({ name: 'Made-up Trading', currency: 'KWD' });
});
afterEach(cleanup);

const CLASSIC = 'books,people,crm,compliance';
const SPLIT = 'sales,books,inventory,people,crm,compliance';

describe('the app open in the classic layout', () => {
  it('is the app of the page, as before', async () => {
    const router = await show('/invoices');
    await shown(`books of ${CLASSIC}`);
    await act(() => router.navigate('/payroll'));
    await shown(`people of ${CLASSIC}`);
    // Settings keeps the last app.
    await act(() => router.navigate('/settings/team'));
    await shown(`people of ${CLASSIC}`);
  });

  it('is Books on the suite’s own pages when the last app was Sales of the split layout', async () => {
    rememberApp('sales');
    await show('/settings/team');
    await shown(`books of ${CLASSIC}`);
  });
});

describe('the app open in the split layout', () => {
  beforeEach(async () => {
    company = await saveCompany({ ...company, appLayout: 'split' });
  });

  it('is Sales, Books or Inventory by the page', async () => {
    const router = await show('/invoices/1');
    await shown(`sales of ${SPLIT}`);
    // The items Sales sells, opened from Sales, keep its sidebar.
    await act(() => router.navigate('/products'));
    await shown(`sales of ${SPLIT}`);
    await act(() => router.navigate('/inventory/count'));
    await shown(`inventory of ${SPLIT}`);
    await act(() => router.navigate('/products'));
    await shown(`inventory of ${SPLIT}`);
    // Bills, opened from Inventory, keep its sidebar.
    await act(() => router.navigate('/bills'));
    await shown(`inventory of ${SPLIT}`);
    await act(() => router.navigate('/cheques'));
    await shown(`books of ${SPLIT}`);
    // Receivables in Books.
    await act(() => router.navigate('/invoices'));
    await shown(`books of ${SPLIT}`);
    await act(() => router.navigate('/settings/company'));
    await shown(`books of ${SPLIT}`);
  });

  it('keeps the last app on the suite’s own pages, and forgets it once the layout is back to four', async () => {
    rememberApp('inventory');
    await show('/settings/team');
    await shown(`inventory of ${SPLIT}`);
    await act(async () => {
      const { appLayout: _layout, ...classic } = company;
      await saveCompany(classic);
    });
    await shown(`books of ${CLASSIC}`);
  });

  it('opens Sales and Inventory with their own sidebars when Books, which lists their pages, was the last app', async () => {
    const router = await show('/books');
    await shown(`books of ${SPLIT}`);
    // The switcher, the home's tiles or the palette: Sales' home is /invoices,
    // which Books lists under Receivables.
    await choose(SALES);
    await shown(`sales of ${SPLIT}`);
    expect(router.state.location.pathname).toBe('/invoices');
    await act(() => router.navigate('/books'));
    await shown(`books of ${SPLIT}`);
    await act(() => router.navigate('/'));
    await shown(`books of ${SPLIT}`);
    await choose(INVENTORY);
    await shown(`inventory of ${SPLIT}`);
    expect(router.state.location.pathname).toBe('/inventory');
    // Receivables in Books still keep Books' sidebar when opened from it.
    await act(() => router.navigate('/cheques'));
    await shown(`books of ${SPLIT}`);
    await act(() => router.navigate('/invoices'));
    await shown(`books of ${SPLIT}`);
  });

  it('shows the page’s owner, Sales, when the remembered CRM is closed by the owner', async () => {
    await linkAs('admin', { apps: { crm: 'none' } });
    rememberApp('crm');
    const router = await show('/quotes');
    await shown(`sales of ${SPLIT}`);
    await act(() => router.navigate('/clients'));
    await shown(`sales of ${SPLIT}`);
    await act(() => router.navigate('/sales-orders/new'));
    await shown(`sales of ${SPLIT}`);
    // Sales is remembered from then on, for the suite's own pages.
    await act(() => router.navigate('/settings/team'));
    await shown(`sales of ${SPLIT}`);
  });
});

describe('the owner of a page as the last resort in the classic layout', () => {
  it('is Books, as before, for CRM’s shared pages when CRM is closed', async () => {
    await linkAs('admin', { apps: { crm: 'none' } });
    rememberApp('crm');
    const router = await show('/quotes');
    await shown(`books of ${CLASSIC}`);
    await act(() => router.navigate('/crm'));
    await shown(`books of ${CLASSIC}`);
  });
});
