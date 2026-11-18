import { describe, expect, it } from 'vitest';
import { matchRoutes } from 'react-router';
import { routes } from '@/app/routes';
import {
  canEdit as roleCanEdit,
  canSeePeople,
  LIMIT_APPS,
  limitAppOf,
  MEMBER_ROLES,
} from '@/cloud/roles';
import { navLinks, type NavLink } from '@/features/shell/nav';
import {
  accessMap,
  appAccess,
  appById,
  appForPath,
  appLayoutOf,
  APPS,
  appsFor,
  canEdit,
  canOpen,
  createColumns,
  createGroups,
  firstSegment,
  isAppId,
  limitTitle,
  roleAccess,
  SPLIT_APPS,
  visibleApps,
} from './apps';
import type { SuiteApp } from './types';

const ROLES = [...MEMBER_ROLES, null] as const;

describe('the apps of Maham One', () => {
  it('are Books, People, CRM and Compliance', () => {
    expect(APPS.map((a) => a.id)).toEqual(['books', 'people', 'crm', 'compliance']);
    expect(new Set(APPS.map((a) => a.tone)).size).toBe(APPS.length);
  });

  it('each own their own first path segments', () => {
    const owners = APPS.flatMap((a) => a.owns);
    expect(owners.filter((s, i) => owners.indexOf(s) !== i)).toEqual([]);
    for (const app of APPS) expect(app.owns).toContain(firstSegment(app.home));
  });

  it('only share pages another app owns', () => {
    for (const app of APPS) {
      for (const segment of app.shares ?? []) {
        expect(APPS.some((other) => other.id !== app.id && other.owns.includes(segment))).toBe(
          true,
        );
      }
    }
  });

  it('find the app of a page from its address', () => {
    expect(firstSegment('/invoices/x/edit?status=overdue')).toBe('invoices');
    expect(firstSegment('/')).toBe('');
    expect(appForPath('/invoices/1')).toBe('books');
    expect(appForPath('/books')).toBe('books');
    expect(appForPath('/employees/1/edit')).toBe('people');
    expect(appForPath('/payroll/leave')).toBe('people');
    expect(appForPath('/people/directory')).toBe('people');
    expect(appForPath('/compliance/documents')).toBe('compliance');
    expect(appForPath('/crm/prospects')).toBe('crm');
    // Every app's files, listed in Compliance.
    expect(appForPath('/files')).toBe('compliance');
    // The suite's own pages belong to no app.
    expect(appForPath('/')).toBeNull();
    expect(appForPath('/settings/team')).toBeNull();
    expect(appForPath('/setup')).toBeNull();
  });

  it('keep CRM around the Books pages it lists when CRM was open', () => {
    expect(appForPath('/clients/1', 'crm')).toBe('crm');
    expect(appForPath('/quotes', 'crm')).toBe('crm');
    // The quote design, opened from CRM's Quotes.
    expect(appForPath('/templates?type=quote', 'crm')).toBe('crm');
    expect(appForPath('/clients/1', 'books')).toBe('books');
    expect(appForPath('/clients/1', null)).toBe('books');
    // Not a page CRM lists.
    expect(appForPath('/invoices', 'crm')).toBe('books');
  });

  it('have three phone tabs, sidebar links, tools and New groups that open real pages', () => {
    for (const app of APPS) {
      expect(app.tabs).toHaveLength(3);
      // A few tools for the home, each once, never the home itself.
      const tools = app.tools.map((tool) => tool.to);
      expect(tools.length, app.id).toBeGreaterThan(0);
      expect(tools.length, app.id).toBeLessThanOrEqual(12);
      expect(new Set(tools).size, app.id).toBe(tools.length);
      expect(tools, app.id).not.toContain('/');
      const targets = [
        app.home,
        ...tools,
        ...app.tabs.map((tab) => tab.to),
        ...navLinks(app.nav).map((l) => l.to),
        ...app.footer.map((l) => l.to),
        ...app.create.flatMap((g) => g.actions.map((a) => a.to)),
      ];
      for (const to of targets) {
        const match = matchRoutes(routes, to.split('?')[0]);
        expect(match?.[match.length - 1].route.path, `${app.id}: ${to}`).not.toBe('*');
      }
    }
  });

  it('give each sidebar group its own id', () => {
    const ids = APPS.flatMap((a) => a.nav.flatMap((e) => (e.kind === 'group' ? [e.id] : [])));
    expect(ids.filter((id, i) => ids.indexOf(id) !== i)).toEqual([]);
  });
});

describe('who opens which app', () => {
  it('shows People exactly to the roles that may see salaries', () => {
    for (const role of ROLES) {
      expect(canOpen(appAccess('people', role)), String(role)).toBe(canSeePeople(role));
    }
  });

  it('never lets someone work in an app their role may not change', () => {
    for (const role of ROLES) {
      for (const app of APPS) {
        if (canEdit(appAccess(app.id, role))) expect(roleCanEdit(role)).toBe(true);
      }
    }
  });

  it('follows the access matrix', () => {
    expect(accessMap('owner')).toEqual({
      books: 'manage',
      people: 'manage',
      crm: 'manage',
      compliance: 'manage',
    });
    expect(accessMap(null)).toEqual(accessMap('owner'));
    expect(accessMap('accountant')).toEqual({
      books: 'manage',
      people: 'manage',
      crm: 'edit',
      compliance: 'manage',
    });
    expect(accessMap('staff')).toEqual({
      books: 'edit',
      people: 'none',
      crm: 'edit',
      compliance: 'view',
    });
    expect(accessMap('viewer')).toEqual({
      books: 'view',
      people: 'none',
      crm: 'view',
      compliance: 'view',
    });
  });

  it('shows nothing of People and changes nothing until the role is known', () => {
    expect(accessMap('owner', false)).toEqual({
      books: 'view',
      people: 'none',
      crm: 'view',
      compliance: 'view',
    });
    expect(visibleApps(accessMap('owner', false)).map((a) => a.id)).not.toContain('people');
  });
});

describe('the New menus', () => {
  const ids = (role: Parameters<typeof accessMap>[0]) =>
    createGroups('books', accessMap(role)).flatMap((g) => g.actions.map((a) => a.id));

  it('offer each action once, the open app’s first', () => {
    const all = ids('owner');
    expect(all.filter((id, i) => all.indexOf(id) !== i)).toEqual([]);
    for (const app of APPS) {
      const labels = createGroups(app.id, accessMap('owner')).map((g) => g.label);
      expect(
        labels.filter((l, i) => labels.indexOf(l) !== i),
        app.id,
      ).toEqual([]);
    }
    expect(all[0]).toBe('invoice');
    expect(createGroups('people', accessMap('owner'))[0].actions[0].id).toBe('employee');
    // CRM's Sales first, then the rest of Books' sales in the same group.
    expect(createGroups('crm', accessMap('owner'))[0].actions.map((a) => a.id)).toEqual([
      'quote',
      'client',
      'sales_order',
      'invoice',
      'proforma',
      'delivery_note',
      'credit',
      'recurring',
      'payment_in',
    ]);
  });

  it('never offer an employee to staff, nor anything to viewers', () => {
    expect(ids('staff')).not.toContain('employee');
    expect(ids('staff')).toContain('invoice');
    expect(ids('viewer')).toEqual([]);
  });

  it('lay groups out in two columns', () => {
    const [left, right] = createColumns(createGroups('books', accessMap('owner')));
    expect(left.map((g) => g.label)).toContain('Sales');
    expect(right.map((g) => g.label)).toContain('Purchases');
    expect(left.length + right.length).toBe(createGroups('books', accessMap('owner')).length);
  });
});

describe('the owner’s limits on a member', () => {
  it('cover every app', () => {
    expect([...LIMIT_APPS]).toEqual(APPS.map((app) => app.id));
  });

  it('only take away from the role, and never from the owner', () => {
    const limits = { apps: { books: 'view', people: 'none', compliance: 'edit' } } as const;
    expect(accessMap('accountant', true, limits)).toEqual({
      books: 'view',
      people: 'none',
      // CRM works on Books' customers and quotes: no more open than Books.
      crm: 'view',
      compliance: 'edit',
    });
    // Staff look at Compliance whatever the limit says.
    expect(appAccess('compliance', 'staff', true, limits)).toBe('view');
    expect(accessMap('owner', true, limits)).toEqual(accessMap('owner'));
    expect(accessMap(null, true, limits)).toEqual(accessMap(null));
    for (const role of ROLES) expect(accessMap(role, true, {})).toEqual(accessMap(role));
  });

  it('never hide Books, which the other apps use', () => {
    const off = { apps: { books: 'none' } } as const;
    expect(appAccess('books', 'admin', true, off)).toBe('view');
    expect(appAccess('crm', 'admin', true, off)).toBe('view');
    expect(visibleApps(accessMap('staff', true, off)).map((app) => app.id)).toEqual([
      'books',
      'crm',
      'compliance',
    ]);
  });
});

/* -------------------------------------------------------------------------- */
/* The layouts (#3): the classic four apps, or Books split in three          */
/* -------------------------------------------------------------------------- */

const icon = (i: { displayName?: string }) => i.displayName ?? '?';
const FLAGS = [
  'taxesOnly',
  'registerExtrasOnly',
  'fileFinderOnly',
  'approvalsOnly',
  'payrollApprovalsOnly',
  'costingOnly',
] as const;
const flags = (link: NavLink & { end?: boolean }) =>
  [link.end ? 'end' : '', ...FLAGS.filter((f) => link[f])]
    .filter(Boolean)
    .map((f) => ` [${f}]`)
    .join('');

/** An app's manifest as text: everything the shell builds from it. */
function describeApp(app: SuiteApp): string[] {
  const lines = [
    `${app.id} · ${app.name} · ${app.nameAr} · ${app.tone} · ${icon(app.icon)} · ${app.home}${app.preview ? ' · preview' : ''}`,
    `  ${app.description}`,
    `  owns ${app.owns.join(' ')}`,
    `  shares ${(app.shares ?? []).join(' ')}`,
  ];
  for (const e of app.nav) {
    if (e.kind === 'link') lines.push(`  nav ${e.to} ${e.label} · ${icon(e.icon)}${flags(e)}`);
    else {
      lines.push(`  group ${e.id} ${e.label} · ${icon(e.icon)}`);
      for (const c of e.children) lines.push(`    ${c.to} ${c.label}${flags(c)}`);
    }
  }
  lines.push(`  footer ${app.footer.map((l) => `${l.to} ${icon(l.icon)}`).join(', ')}`);
  for (const g of app.create) {
    lines.push(`  create ${g.label} (${g.column ?? '-'}) ${g.actions.map((a) => a.id).join(' ')}`);
  }
  lines.push(`  tools ${app.tools.map((t) => t.to).join(' ')}`);
  lines.push(`  tabs ${app.tabs.map((t) => `${t.to} ${t.label}`).join(', ')}`);
  lines.push(
    `  access ${Object.entries(app.access)
      .map(([k, v]) => `${k}=${v}`)
      .join(' ')}`,
  );
  return lines;
}

/** Every first path segment the apps own, sorted. */
const ownedSegments = (apps: readonly SuiteApp[]) => apps.flatMap((a) => a.owns).sort();

describe('the classic layout', () => {
  it('is the layout of every company until it splits Books', () => {
    expect(appLayoutOf(undefined)).toBe('classic');
    expect(appLayoutOf({})).toBe('classic');
    expect(appLayoutOf({ appLayout: 'split' })).toBe('split');
    // A value a newer build may write: today's four apps here.
    expect(appLayoutOf({ appLayout: 'other' as 'split' })).toBe('classic');
    expect(appsFor({})).toBe(APPS);
    expect(appsFor({ appLayout: 'split' })).toBe(SPLIT_APPS);
  });

  it('is exactly today’s four apps: names, owners, sidebars, New menus, tools, tabs and access', () => {
    expect(APPS.flatMap(describeApp)).toEqual([
      'books · Maham Books · مهام بوكس · indigo · BookOpenText · /books',
      '  Invoices, purchases, cheques, banking, accounting and reports.',
      '  owns books invoices quotes credits proformas sales-orders delivery-notes recurring payments payments-made cheques clients vendors bills vendor-credits purchase-orders expenses products inventory reports accounts journals assets year-end banking vat templates',
      '  shares ',
      '  nav / Home · House [end]',
      '  nav /books Dashboard · LayoutDashboard [end]',
      '  group sales Sales · ShoppingBag',
      '    /clients Clients',
      '    /quotes Quotes',
      '    /proformas Proforma invoices',
      '    /sales-orders Sales orders',
      '    /invoices Invoices',
      '    /delivery-notes Delivery notes',
      '    /payments Payments received',
      '    /credits Credit notes',
      '    /recurring Recurring invoices',
      '  group purchases Purchases · ShoppingCart',
      '    /vendors Vendors',
      '    /purchase-orders Purchase orders',
      '    /bills Bills',
      '    /expenses Expenses',
      '    /payments-made Payments made',
      '    /vendor-credits Vendor credits',
      '  nav /cheques Cheques · WalletCards',
      '  group inventory Inventory · Boxes',
      '    /products Products & services',
      '    /inventory Stock and warehouses',
      '    /inventory/issues Issued items',
      '  nav /banking Banking · Banknote',
      '  group accounting Accounting · BookOpen',
      '    /accounts Chart of accounts',
      '    /journals Manual journals',
      '    /assets Fixed assets',
      '    /year-end Year-end close',
      '    /vat VAT returns [taxesOnly]',
      '  nav /reports Reports · ChartColumn',
      '  nav /approvals Approvals · ClipboardCheck [approvalsOnly]',
      '  footer /templates Palette, /settings Settings',
      '  create Sales (0) invoice quote proforma sales_order delivery_note credit recurring payment_in',
      '  create Purchases (1) bill expense purchase_order payment_out vendor_credit',
      '  create Contacts and items (1) client vendor product',
      '  create Accounting (0) journal asset stock_adjustment stock_issue',
      '  tools /invoices /quotes /clients /payments /vendors /bills /expenses /cheques /products /banking /accounts /reports',
      '  tabs / Home, /invoices Invoices, /expenses Expenses',
      '  access device=manage owner=manage admin=manage accountant=manage staff=edit viewer=view',
      'people · Maham People · مهام بيبول · emerald · UsersRound · /people',
      '  Employees, payroll, leave and staff loans.',
      '  owns people employees payroll',
      '  shares ',
      '  nav / Home · House [end]',
      '  nav /people Overview · LayoutDashboard [end]',
      '  nav /people/directory Directory · Contact',
      '  nav /employees Employees · IdCard',
      '  nav /payroll Payroll · WalletCards',
      '  nav /payroll/leave Leave · CalendarDays',
      '  nav /payroll/leave-reasons Leave reasons · Tags',
      '  nav /payroll/loans Staff loans · HandCoins',
      '  nav /people/letters Letters · Mails',
      // Manpower costing (#3, part b).
      '  nav /people/costing Manpower costing · Calculator [costingOnly]',
      '  nav /payroll/settings Payroll settings · SlidersHorizontal',
      '  nav /approvals Approvals · ClipboardCheck [payrollApprovalsOnly]',
      '  footer /settings Settings',
      '  create People (-) employee letter costing',
      '  tools /people/directory /employees /payroll /payroll/leave /payroll/loans',
      '  tabs / Home, /employees Employees, /payroll Payroll',
      '  access device=manage owner=manage admin=manage accountant=manage staff=none viewer=none',
      'crm · Maham CRM · مهام CRM · sky · Handshake · /crm · preview',
      '  Quotes pipeline, follow-ups and prospects.',
      '  owns crm',
      '  shares clients quotes sales-orders templates',
      '  nav / Home · House [end]',
      '  nav /crm Pipeline · SquareKanban [end]',
      '  nav /crm/prospects Prospects · UserSearch',
      '  nav /clients Customers · Users',
      '  nav /quotes Quotes · ScrollText',
      '  nav /sales-orders Sales orders · ClipboardList',
      '  footer /settings Settings',
      '  create Sales (-) quote client sales_order',
      '  tools /crm /crm/prospects /clients /quotes /sales-orders',
      '  tabs / Home, /crm Pipeline, /quotes Quotes',
      '  access device=manage owner=manage admin=manage accountant=edit staff=edit viewer=view',
      'compliance · Maham Compliance · مهام الامتثال · amber · ShieldCheck · /compliance',
      '  Licences, staff papers and statutory deadlines.',
      '  owns compliance files',
      '  shares ',
      '  nav / Home · House [end]',
      '  nav /compliance Calendar · CalendarClock [end]',
      '  nav /compliance/documents Documents · FolderCheck',
      '  nav /compliance/vehicles Vehicles · Car [registerExtrasOnly]',
      '  nav /files Files · FileSearch [fileFinderOnly]',
      '  footer /settings Settings',
      '  tools /compliance /compliance/documents',
      '  tabs / Home, /compliance Calendar, /compliance/documents Documents',
      '  access device=manage owner=manage admin=manage accountant=manage staff=view viewer=view',
    ]);
  });

  it('keeps the old defaults of every helper', () => {
    expect(accessMap('staff', true, undefined, APPS)).toEqual(accessMap('staff'));
    expect(Object.keys(accessMap('owner'))).toEqual(['books', 'people', 'crm', 'compliance']);
    for (const app of APPS) expect(appById(app.id)).toBe(app);
    // Sales and Inventory have no app of their own here: their pages are Books'.
    expect(appById('sales')).toBe(appById('books'));
    expect(appForPath('/invoices', 'sales')).toBe('books');
    expect(isAppId('sales', APPS)).toBe(false);
    expect(isAppId('sales')).toBe(true);
    expect(isAppId('elsewhere')).toBe(false);
    expect(createGroups('sales', accessMap('owner'))).toEqual(
      createGroups('books', accessMap('owner')),
    );
  });
});

describe('the split layout', () => {
  const owner = accessMap('owner', true, undefined, SPLIT_APPS);

  it('has six apps: Sales, Books (finance) and Inventory, then People, CRM and Compliance', () => {
    expect(SPLIT_APPS.map((a) => a.id)).toEqual([
      'sales',
      'books',
      'inventory',
      'people',
      'crm',
      'compliance',
    ]);
    expect(SPLIT_APPS.map((a) => [a.name, a.nameAr])).toEqual([
      ['Maham Sales', 'مهام سيلز'],
      // Finance keeps the name.
      ['Maham Books', 'مهام بوكس'],
      ['Maham Inventory', 'مهام إنفنتوري'],
      ['Maham People', 'مهام بيبول'],
      ['Maham CRM', 'مهام CRM'],
      ['Maham Compliance', 'مهام الامتثال'],
    ]);
    expect(new Set(SPLIT_APPS.map((a) => a.tone)).size).toBe(SPLIT_APPS.length);
    expect(appById('sales', SPLIT_APPS).tone).toBe('violet');
    expect(appById('inventory', SPLIT_APPS).tone).toBe('teal');
    // People, CRM and Compliance are the very same apps.
    for (const id of ['people', 'crm', 'compliance'] as const) {
      expect(appById(id, SPLIT_APPS)).toBe(appById(id));
    }
    // Books keeps its id, name, home and access.
    const finance = appById('books', SPLIT_APPS);
    expect([finance.id, finance.name, finance.home]).toEqual(['books', 'Maham Books', '/books']);
    expect(finance.access).toEqual(appById('books').access);
  });

  it('gives each segment one owner, and owns exactly the segments of today: no address changes', () => {
    const owners = SPLIT_APPS.flatMap((a) => a.owns);
    expect(owners.filter((s, i) => owners.indexOf(s) !== i)).toEqual([]);
    expect(ownedSegments(SPLIT_APPS)).toEqual(ownedSegments(APPS));
    for (const app of SPLIT_APPS) expect(app.owns).toContain(firstSegment(app.home));
    expect(appById('sales', SPLIT_APPS).owns).toEqual([
      'quotes',
      'proformas',
      'sales-orders',
      'invoices',
      'delivery-notes',
      'credits',
      'recurring',
      'payments',
      'clients',
    ]);
    expect(appById('inventory', SPLIT_APPS).owns).toEqual(['products', 'inventory']);
  });

  it('only shares pages another app owns', () => {
    for (const app of SPLIT_APPS) {
      for (const segment of app.shares ?? []) {
        expect(
          SPLIT_APPS.some((other) => other.id !== app.id && other.owns.includes(segment)),
          `${app.id}: ${segment}`,
        ).toBe(true);
      }
    }
    // Receivables, and the items and stock Books values.
    expect(appById('books', SPLIT_APPS).shares).toEqual([
      'clients',
      'invoices',
      'payments',
      'credits',
      'products',
      'inventory',
    ]);
    expect(appById('inventory', SPLIT_APPS).shares).toEqual([
      'purchase-orders',
      'bills',
      'vendors',
      'delivery-notes',
    ]);
  });

  it('finds the app of a page from its address', () => {
    const at = (path: string, last?: Parameters<typeof appForPath>[1]) =>
      appForPath(path, last, SPLIT_APPS);
    expect(at('/invoices/1')).toBe('sales');
    expect(at('/quotes/new')).toBe('sales');
    expect(at('/clients')).toBe('sales');
    expect(at('/products')).toBe('inventory');
    expect(at('/inventory/count')).toBe('inventory');
    expect(at('/bills/1')).toBe('books');
    expect(at('/cheques')).toBe('books');
    expect(at('/books')).toBe('books');
    expect(at('/templates')).toBe('books');
    expect(at('/payroll')).toBe('people');
    expect(at('/crm')).toBe('crm');
    expect(at('/files')).toBe('compliance');
    expect(at('/settings/team')).toBeNull();
    // Opened from Books' Receivables, an invoice keeps Books' sidebar.
    expect(at('/invoices/1', 'books')).toBe('books');
    expect(at('/products', 'books')).toBe('books');
    // Bills and purchase orders, opened from Inventory.
    expect(at('/purchase-orders/1', 'inventory')).toBe('inventory');
    expect(at('/delivery-notes', 'inventory')).toBe('inventory');
    // CRM keeps the Sales pages it lists.
    expect(at('/quotes', 'crm')).toBe('crm');
    expect(at('/clients/1', 'crm')).toBe('crm');
    expect(at('/invoices', 'crm')).toBe('sales');
    // Items and the designs, opened from Sales.
    expect(at('/products', 'sales')).toBe('sales');
    expect(at('/templates', 'sales')).toBe('sales');
    expect(at('/bills', 'sales')).toBe('books');
  });

  it('has three phone tabs, sidebar links, tools and New groups that open real pages', () => {
    for (const app of SPLIT_APPS) {
      expect(app.tabs).toHaveLength(3);
      const tools = app.tools.map((tool) => tool.to);
      expect(tools.length, app.id).toBeGreaterThan(0);
      expect(tools.length, app.id).toBeLessThanOrEqual(12);
      expect(new Set(tools).size, app.id).toBe(tools.length);
      expect(tools, app.id).not.toContain('/');
      const targets = [
        app.home,
        ...tools,
        ...app.tabs.map((tab) => tab.to),
        ...navLinks(app.nav).map((l) => l.to),
        ...app.footer.map((l) => l.to),
        ...app.create.flatMap((g) => g.actions.map((a) => a.to)),
      ];
      for (const to of targets) {
        const match = matchRoutes(routes, to.split('?')[0]);
        expect(match?.[match.length - 1].route.path, `${app.id}: ${to}`).not.toBe('*');
        // Each page in its own app's sidebar, or one the app shares.
        const owner = appForPath(to, app.id, SPLIT_APPS);
        expect(owner === null || owner === app.id, `${app.id}: ${to} is ${owner}'s`).toBe(true);
      }
    }
    const ids = SPLIT_APPS.flatMap((a) => a.nav.flatMap((e) => (e.kind === 'group' ? [e.id] : [])));
    expect(ids.filter((id, i) => ids.indexOf(id) !== i)).toEqual([]);
  });

  it('lists every page of today’s Books in Sales, Books or Inventory', () => {
    const before = new Set(navLinks(appById('books').nav).map((l) => l.to));
    const after = new Set(
      SPLIT_APPS.filter((a) => limitAppOf(a.id) === 'books').flatMap((a) =>
        navLinks(a.nav).map((l) => l.to),
      ),
    );
    expect([...before].filter((to) => !after.has(to))).toEqual([]);
  });

  it('opens Sales and Inventory to whoever opens Books, as far as Books', () => {
    for (const role of ROLES) {
      for (const id of ['sales', 'inventory'] as const) {
        expect(roleAccess(id, role), `${role} ${id}`).toBe(roleAccess('books', role));
        expect(appAccess(id, role), `${role} ${id}`).toBe(appAccess('books', role));
        expect(appAccess(id, role, false)).toBe('view');
      }
    }
    expect(owner).toEqual({
      sales: 'manage',
      books: 'manage',
      inventory: 'manage',
      people: 'manage',
      crm: 'manage',
      compliance: 'manage',
    });
    expect(accessMap('staff', true, undefined, SPLIT_APPS)).toEqual({
      sales: 'edit',
      books: 'edit',
      inventory: 'edit',
      people: 'none',
      crm: 'edit',
      compliance: 'view',
    });
    expect(
      visibleApps(accessMap('viewer', true, undefined, SPLIT_APPS), SPLIT_APPS).map((a) => a.id),
    ).toEqual(['sales', 'books', 'inventory', 'crm', 'compliance']);
  });

  it('applies the owner’s limit on Books to Sales and Inventory, with the four ids it is kept with', () => {
    expect([...LIMIT_APPS]).toEqual(APPS.map((app) => app.id));
    expect(SPLIT_APPS.map((app) => limitAppOf(app.id))).toEqual([
      'books',
      'books',
      'books',
      'people',
      'crm',
      'compliance',
    ]);
    const viewOnly = { apps: { books: 'view' } } as const;
    expect(accessMap('accountant', true, viewOnly, SPLIT_APPS)).toEqual({
      sales: 'view',
      books: 'view',
      inventory: 'view',
      people: 'manage',
      crm: 'view',
      compliance: 'manage',
    });
    // Never hidden, as Books.
    const off = { apps: { books: 'none' } } as const;
    for (const id of ['sales', 'books', 'inventory'] as const) {
      expect(appAccess(id, 'admin', true, off)).toBe('view');
    }
    // A limit on another app leaves them as they are.
    expect(appAccess('sales', 'admin', true, { apps: { people: 'none' } })).toBe('manage');
    expect(accessMap('owner', true, viewOnly, SPLIT_APPS)).toEqual(owner);
  });

  it('names Books’ limit and links after the three apps it stands for', () => {
    expect(limitTitle('books', SPLIT_APPS, 'en')).toBe(
      'Maham Sales · Maham Books · Maham Inventory',
    );
    expect(limitTitle('books', SPLIT_APPS, 'ar')).toBe('مهام سيلز · مهام بوكس · مهام إنفنتوري');
    expect(limitTitle('people', SPLIT_APPS, 'en')).toBe('Maham People');
    for (const id of LIMIT_APPS) {
      expect(limitTitle(id, APPS, 'en')).toBe(appById(id).name);
    }
  });

  it('offers every action of today once, the open app’s first', () => {
    const all = (current: Parameters<typeof createGroups>[0]) =>
      createGroups(current, owner, SPLIT_APPS).flatMap((g) => g.actions.map((a) => a.id));
    const today = createGroups('books', accessMap('owner')).flatMap((g) =>
      g.actions.map((a) => a.id),
    );
    for (const app of SPLIT_APPS) {
      const ids = all(app.id);
      expect(
        ids.filter((id, i) => ids.indexOf(id) !== i),
        app.id,
      ).toEqual([]);
      expect([...ids].sort(), app.id).toEqual([...today].sort());
      const labels = createGroups(app.id, owner, SPLIT_APPS).map((g) => g.label);
      expect(
        labels.filter((l, i) => labels.indexOf(l) !== i),
        app.id,
      ).toEqual([]);
    }
    expect(all('sales')[0]).toBe('invoice');
    expect(all('books')[0]).toBe('bill');
    expect(all('inventory').slice(0, 2)).toEqual(['product', 'stock_adjustment']);
    // Viewers create nothing; staff never an employee.
    expect(
      createGroups('sales', accessMap('viewer', true, undefined, SPLIT_APPS), SPLIT_APPS),
    ).toEqual([]);
    const staff = createGroups(
      'sales',
      accessMap('staff', true, undefined, SPLIT_APPS),
      SPLIT_APPS,
    );
    expect(staff.flatMap((g) => g.actions.map((a) => a.id))).not.toContain('employee');
    // Limited to view only in Books: nothing of Sales, Books or Inventory.
    const limitedAccess = accessMap('accountant', true, { apps: { books: 'view' } }, SPLIT_APPS);
    const limited = createGroups('sales', limitedAccess, SPLIT_APPS, { costing: true }).flatMap(
      (g) => g.actions.map((a) => a.id),
    );
    expect(limited).toEqual(['employee', 'letter', 'costing']);
    // A new manpower costing only while costing is in effect (#3, D1 and D4).
    expect(
      createGroups('sales', limitedAccess, SPLIT_APPS).flatMap((g) => g.actions.map((a) => a.id)),
    ).toEqual(['employee', 'letter']);
  });
});
