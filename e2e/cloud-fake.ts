import type { Page, Route, WebSocketRoute } from '@playwright/test';

/**
 * A stand-in for the app's Supabase project in browser tests: accounts
 * (sign up with email confirmation, password sign-in, sign-out), the
 * database functions the app calls, profiles and the Realtime socket. It
 * keeps state, so a company uploaded by one person can be downloaded by
 * another, as on the real service. The sandbox can't reach Supabase.
 */

export const SUPABASE_URL = 'https://gagdyhintrxdkiqhahzh.supabase.co';
export const PUBLISHABLE_KEY = 'sb_publishable_KyVAkWtemw_XDnNK8ZKRpA_-5x4pk8d';

type Role = 'owner' | 'admin' | 'accountant' | 'staff' | 'viewer';

export interface FakeUser {
  id: string;
  email: string;
  password: string;
  fullName: string;
  language: 'en' | 'ar';
  confirmed: boolean;
}

interface Row {
  company: string;
  tbl: string;
  id: string;
  data: Record<string, unknown> | null;
  rev: number;
  deleted: boolean;
}

interface Invite {
  id: string;
  token: string;
  company: string;
  email: string;
  role: Role;
  invitedBy: string;
  accepted: boolean;
  revoked?: boolean;
}

export interface SeenRequest {
  method: string;
  path: string;
  apikey: string | null;
  body: unknown;
}

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-headers': '*',
  'access-control-allow-methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
  'access-control-expose-headers': '*',
};

const base64url = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64url');

/** A database function refusing the call, as PostgREST answers it. */
class Refusal {
  constructor(
    readonly status: number,
    readonly body: { code: string; message: string },
  ) {}
}

const refuse = (message: string) => new Refusal(403, { code: '42501', message });

type Access = 'none' | 'view' | 'edit' | 'manage';

/**
 * The app a record belongs to, for the owner's limits on a member: the same
 * as almailbooks.record_app (and recordApp in src/cloud/roles.ts).
 */
function recordApp(tbl: string, data: Record<string, unknown> | null): string | null {
  const people = [
    'employees',
    'payRuns',
    'payrollSettings',
    'peopleSettings',
    'leaveRecords',
    'staffLoans',
    'finalSettlements',
    'letterTemplates',
    'employeeLetters',
    'staffingCostings',
  ];
  const shared = ['companies', 'activities', 'attachments', 'approvals'];
  if (people.includes(tbl)) return 'people';
  if (tbl === 'journals' && data?.kind === 'payroll') return 'people';
  const employee = typeof data?.employeeId === 'string' && data.employeeId !== '';
  if ((tbl === 'complianceDocuments' || tbl === 'renewals') && employee) return 'people';
  if (['complianceDocuments', 'renewals', 'complianceMarks', 'vehicles'].includes(tbl)) {
    return 'compliance';
  }
  return shared.includes(tbl) ? null : 'books';
}

/**
 * Payroll and people data, which staff and viewers never get: as
 * almailbooks.record_is_private, for the records these tests make (a file
 * or activity about them is marked _private by the app).
 */
function privateRow(tbl: string, data: Record<string, unknown> | null): boolean {
  const people = [
    'employees',
    'payRuns',
    'payrollSettings',
    'peopleSettings',
    'leaveRecords',
    'staffLoans',
    'finalSettlements',
    'letterTemplates',
    'employeeLetters',
    'staffingCostings',
  ];
  if (people.includes(tbl)) return true;
  if (!data) return false;
  if (data._private === true) return true;
  const employee = typeof data.employeeId === 'string' && data.employeeId !== '';
  switch (tbl) {
    case 'complianceDocuments':
      return employee || data.confidential === true;
    case 'journals':
      return data.kind === 'payroll';
    case 'approvals':
      return people.includes(String(data.subjectTbl));
    case 'activities':
      return (
        ['employee', 'payroll', 'costing'].includes(String(data.entity)) ||
        employee ||
        data.confidential === true
      );
    default:
      return false;
  }
}

/** The records a file is kept with, as almailbooks.attachment_app looks them up. */
const ATTACHMENT_OWNERS = [
  'employees',
  'employeeLetters',
  'letterTemplates',
  'complianceDocuments',
  'renewals',
  'vehicles',
  'documents',
  'payments',
  'expenses',
  'assets',
  'securityCheques',
  'products',
];

/** The books' settings on the company record, as almailbooks.company_books_changed. */
const COMPANY_BOOKS = [
  'accounting',
  'payment',
  'bankAccount',
  'emailTemplates',
  'defaults',
  'taxesEnabled',
  'openingBalances',
  'vouchers',
  'items',
  'chequePrinting',
];

const SENIOR: Role[] = ['admin', 'accountant'];

/**
 * What a document says, as almailbooks.invoice_content (and invoiceContent
 * in src/cloud/roles.ts), as canonical JSON: keys sorted, nulls left out.
 */
const CONTENT = [
  'type',
  'number',
  'clientId',
  'issueDate',
  'dueDate',
  'poNumber',
  'vendorReference',
  'currency',
  'exchangeRate',
  'items',
  'discount',
  'discountType',
  'taxes',
  'charges',
  'pricesIncludeTax',
  'deposit',
  'depositDueDate',
  'notes',
  'terms',
  'footer',
  'intro',
  'templateId',
  'accentColor',
  'deliveryDate',
  'deliveryPlace',
  'retentionPercent',
  'retentionKind',
  'replacesNumber',
];

function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value && typeof value === 'object') {
    const entries = Object.entries(value as Record<string, unknown>)
      .filter(([, v]) => v !== null && v !== undefined)
      .sort(([a], [b]) => (a < b ? -1 : 1));
    return `{${entries.map(([k, v]) => `${JSON.stringify(k)}:${canonical(v)}`).join(',')}}`;
  }
  return JSON.stringify(value ?? null);
}

const content = (doc: Record<string, unknown>) =>
  canonical(Object.fromEntries(CONTENT.map((key) => [key, doc[key]])));

const stage = (status: unknown) => (status === 'draft' || status === 'void' ? status : 'issued');

/** The address of a document's payment link, or '' for none. */
const linkUrl = (doc: Record<string, unknown>) => {
  const url = (doc.paymentLink as Record<string, unknown> | null | undefined)?.url;
  return typeof url === 'string' ? url : '';
};

type Data = Record<string, unknown>;

/**
 * What an approver confirms on a cheque, as almailbooks.cheque_content (and
 * chequeContent in src/cloud/roles.ts), as canonical JSON.
 */
function chequeContent(p: Data): Data {
  const cheque = (p.cheque && typeof p.cheque === 'object' ? p.cheque : {}) as Data;
  return {
    method: p.method,
    direction: p.direction ?? 'in',
    clientId: p.clientId,
    date: p.date,
    amount: p.amount,
    currency: p.currency,
    exchangeRate: p.exchangeRate ?? 1,
    accountId: p.accountId,
    number: cheque.number,
    bank: cheque.bank,
    chequeDate: cheque.date,
    drawer: cheque.drawer,
    drawerCivilId: cheque.drawerCivilId === '' ? null : cheque.drawerCivilId,
  };
}

const securityContent = (p: Data): Data => ({
  direction: p.direction ?? 'in',
  number: p.number,
  bank: p.bank,
  date: p.date,
  amount: p.amount,
  currency: p.currency,
  drawer: p.drawer,
  drawerCivilId: p.drawerCivilId === '' ? null : p.drawerCivilId,
});

/**
 * Whether a change of a payment or security cheque waits for an approver,
 * as almailbooks.cheque_change_needs_approver.
 */
function chequeNeedsApprover(
  cheques: { issued?: boolean; received?: boolean; securityOut?: boolean } | undefined,
  tbl: string,
  old: Data | null,
  data: Data | null,
): boolean {
  if (!cheques || typeof cheques !== 'object') return false;
  if (tbl === 'payments') {
    const covers = (p: Data | null) =>
      Boolean(
        p &&
        p.method === 'cheque' &&
        cheques[p.direction === 'out' ? 'issued' : 'received'] === true,
      );
    if (!covers(old) && !covers(data)) return false;
    if (!old || !data) return true;
    const a = chequeContent(old);
    const b = chequeContent(data);
    const leaves = ((data.cheque as Data | null)?.spoiledLeaves ?? []) as Data[];
    const moved = a.number == null ? null : String(a.number).trim();
    if (
      a.number !== b.number &&
      moved !== null &&
      leaves.some((leaf) => leaf?.number != null && String(leaf.number).trim() === moved)
    ) {
      delete a.number;
      delete b.number;
    }
    // A cheque given its first account keeps its confirmation.
    if (a.accountId == null || a.accountId === '') {
      delete a.accountId;
      delete b.accountId;
    }
    return canonical(a) !== canonical(b);
  }
  if (tbl === 'securityCheques') {
    const covers = (p: Data | null) =>
      Boolean(p && p.direction === 'out' && cheques.securityOut === true);
    if (!covers(old) && !covers(data)) return false;
    if (!old || !data) return true;
    return canonical(securityContent(old)) !== canonical(securityContent(data));
  }
  return false;
}

const chequeConfirmationRequired = () =>
  new Refusal(403, {
    code: '42501',
    message:
      'almail:approval_required This cheque needs confirmation. Send it for confirmation instead.',
  });

/** Refusals of almailbooks.records_guard, as PostgREST answers them. */
const approvalRequired = () =>
  new Refusal(403, {
    code: '42501',
    message:
      'almail:approval_required This change to an issued document needs approval. Send it for approval instead.',
  });

/** A row of public.change_events, as notification_feed answers it. */
interface ChangeRow {
  company: string;
  id: number;
  at: string;
  actor: string;
  op: string;
  tbl: string;
  record_id: string;
  kind: string;
  important: boolean;
  private: boolean;
  count: number;
  fold: string;
  summary: Data;
}

/** The kind of change a record makes, as almailbooks.change_kind. */
function changeKind(tbl: string, data: Data | null): string {
  const people = [
    'employees',
    'payRuns',
    'payrollSettings',
    'peopleSettings',
    'leaveRecords',
    'staffLoans',
    'finalSettlements',
    'letterTemplates',
    'employeeLetters',
    'staffingCostings',
  ];
  if (tbl === 'documents') return 'document';
  if (tbl === 'payments') return data?.method === 'cheque' ? 'cheque' : 'payment';
  if (tbl === 'securityCheques') return 'cheque';
  if (tbl === 'approvals') return 'approval';
  if (tbl === 'companies') return 'settings';
  if (people.includes(tbl)) return 'people';
  if (['complianceDocuments', 'renewals', 'complianceMarks', 'vehicles'].includes(tbl)) {
    return 'compliance';
  }
  if (tbl === 'clients') return 'contact';
  if (
    [
      'products',
      'warehouses',
      'stockMovements',
      'stockEntries',
      'landedCosts',
      'stockIssues',
    ].includes(tbl)
  ) {
    return 'item';
  }
  if (tbl === 'expenses') return 'expense';
  if (tbl === 'attachments') return 'file';
  return 'accounting';
}

/**
 * What a change did, as almailbooks.change_details, for what these tests
 * look at: documents, cheques and approval requests; everything else is an
 * ordinary change. Payroll and people records say only what happened.
 */
function changeDetails(
  tbl: string,
  old: Data | null,
  data: Data | null,
  isPrivate: boolean,
  client: Data | null,
): { important: boolean; summary: Data } | null {
  const row = (data ?? old)!;
  let what = !old ? 'added' : !data ? 'deleted' : 'updated';
  // A request about payroll (#10): what happened to it, and nothing of the pay run.
  if (isPrivate && tbl === 'approvals') {
    if (!old) what = 'requested';
    else if (data && data.status !== old.status) what = String(data.status);
    return {
      important: ['requested', 'approved', 'rejected'].includes(what),
      summary: { what, request: row.kind, status: data?.status ?? 'pending' },
    };
  }
  if (isPrivate) return { important: false, summary: { what } };
  if (tbl === 'documents') {
    if (old && data) {
      const was = stage(old.status);
      const now = stage(data.status);
      what =
        now === 'void' && was !== 'void'
          ? 'voided'
          : was === 'void' && now !== 'void'
            ? 'restored'
            : was === 'draft' && now === 'issued'
              ? 'issued'
              : was === 'issued' && now === 'issued' && content(old) !== content(data)
                ? 'edited'
                : 'updated';
    }
    const covered = row.type === 'invoice' || row.type === 'credit';
    const totals = (row.totals ?? {}) as Data;
    return {
      important:
        covered &&
        (['voided', 'restored', 'edited'].includes(what) ||
          (what === 'deleted' && stage(old?.status) !== 'draft')),
      summary: Object.fromEntries(
        Object.entries({
          what,
          type: row.type,
          number: row.number,
          status: row.status,
          total: typeof totals.total === 'number' ? totals.total : null,
          currency: row.currency,
          client: client?.name ?? null,
          clientAr: client?.nameAr ?? null,
        }).filter(([, v]) => v !== null && v !== undefined),
      ),
    };
  }
  if (tbl === 'approvals') {
    if (!old) what = 'requested';
    else if (data && data.status !== old.status) what = String(data.status);
    return {
      important: ['requested', 'approved', 'rejected'].includes(what),
      summary: {
        what,
        request: row.kind,
        number: row.subjectNumber,
        status: row.status,
        // Items to issue: who receives them, and what.
        ...(row.kind === 'stock_issue' ? issueSummary(row.after as Data | null) : {}),
      },
    };
  }
  if (tbl === 'stockIssues') {
    return { important: false, summary: { what, number: row.number, ...issueSummary(row) } };
  }
  if (tbl === 'companies' && old && data) {
    const strip = (r: Data) => {
      const copy = { ...r };
      for (const key of ['numbering', 'updatedAt']) delete copy[key];
      return canonical(copy);
    };
    if (strip(old) === strip(data)) return null;
  }
  return { important: false, summary: { what } };
}

/**
 * Who may change warehouses and the stock of sub-warehouses, and record
 * items issued, as records_guard and can_delete_record of
 * 20261210000000_warehouse_issues.sql (warehouseWriteRefusal in
 * src/cloud/roles.ts): the refusal's message, or null.
 */
function warehouseRules(
  role: Role | undefined,
  user: string,
  warehouse: (id: string) => Data | null,
) {
  const manages = role === 'owner' || role === 'admin' || role === 'accountant';
  const text = (value: unknown) => (typeof value === 'string' ? value : '');
  const isSub = (id: unknown) => text(id) !== '' && text(warehouse(text(id))?.parentId) !== '';
  const ruled = (w: Data | null) =>
    Boolean(w && (text(w.parentId) !== '' || (typeof w.keeper === 'object' && w.keeper !== null)));
  const inSub = (entry: Data | null) =>
    Boolean(entry && (isSub(entry.warehouseId) || isSub(entry.toWarehouseId)));
  const lines = (doc: Data | null) => {
    const items = Array.isArray(doc?.items) ? (doc!.items as Data[]) : [];
    const moved = items
      .filter((i) => isSub(i?.warehouseId))
      .map((i) => [text(i.id), text(i.productId), text(i.warehouseId), i.quantity ?? null])
      .sort((a, b) => String(a[0]).localeCompare(String(b[0])));
    return moved.length ? canonical({ moved, type: doc?.type, stage: stage(doc?.status) }) : '[]';
  };
  /** May ask for items to be issued from this warehouse (almailbooks.issues_from). */
  const issuesFrom = (id: unknown) => {
    if (!role || role === 'viewer') return false;
    if (manages) return true;
    const w = warehouse(text(id));
    const keeper = w?.keeper as Data | null | undefined;
    return Boolean(w && text(w.parentId) !== '' && w.archived !== true && keeper?.userId === user);
  };
  return {
    manages,
    issuesFrom,
    refusal(tbl: string, old: Data | null, data: Data | null, approver: boolean): string | null {
      switch (tbl) {
        case 'warehouses':
          return !manages && (ruled(data) || ruled(old))
            ? 'Only the owner, an admin or an accountant sets up sub-warehouses.'
            : null;
        case 'stockEntries':
          return !manages && (inSub(data) || inSub(old))
            ? 'Only the owner, an admin or an accountant changes the stock of a sub-warehouse directly.'
            : null;
        case 'stockIssues':
          if (!data) return old ? 'You cannot delete this record.' : null;
          return approver
            ? null
            : 'Only an approver records items issued. Send them for approval instead.';
        case 'documents':
          if (!data)
            return !manages && lines(old) !== '[]' ? 'You cannot delete this record.' : null;
          return !manages && lines(data) !== lines(old)
            ? 'Only the owner, an admin or an accountant moves the stock of a sub-warehouse on a document.'
            : null;
        case 'approvals':
          return !old &&
            data?.kind === 'stock_issue' &&
            !issuesFrom((data.after as Data)?.warehouseId)
            ? 'You can only issue items from the sub-warehouse you look after.'
            : null;
        default:
          return null;
      }
    },
  };
}

/** Who receives items issued, and what, as almailbooks.issue_summary. */
function issueSummary(issue: Data | null | undefined): Data {
  const recipient = (issue?.recipient ?? null) as Data | null;
  const lines = Array.isArray(issue?.lines) ? (issue!.lines as Data[]) : [];
  const filled = (value: unknown) => (typeof value === 'string' && value !== '' ? value : null);
  return Object.fromEntries(
    Object.entries({
      name: filled(recipient?.name),
      nameAr: filled(recipient?.nameAr),
      jobTitle: filled(recipient?.jobTitle),
      jobTitleAr: filled(recipient?.jobTitleAr),
      items: lines.length
        ? lines.map((l) =>
            Object.fromEntries(
              Object.entries({
                quantity: typeof l.quantity === 'number' ? l.quantity : null,
                name: filled(l.name),
                nameAr: filled(l.nameAr),
              }).filter(([, v]) => v !== null),
            ),
          )
        : null,
    }).filter(([, v]) => v !== null),
  );
}

export class FakeSupabase {
  users = new Map<string, FakeUser>();
  companies = new Map<
    string,
    { id: string; name: string; members: Map<string, Role>; createdAt: string }
  >();
  records = new Map<string, Row>();
  invites: Invite[] = [];
  requests: SeenRequest[] = [];
  /** The owner's limits and approver mark per member, by "company user". */
  access = new Map<
    string,
    { permissions: { apps?: Record<string, Access> }; canApprove: boolean }
  >();
  /** Companies whose owner makes admins and accountants alone. */
  seniorRolesOwnerOnly = new Set<string>();
  /** Email alerts by "company user", and the emails asked for from the app. */
  emailAlerts = new Map<string, { enabled: boolean; topics: string[]; appUrl: string }>();
  alertEmails: { company: string; to: string }[] = [];
  /** The kinds of paper each person chose (#18), by "company user"; missing: every kind. */
  alertScopes = new Map<string, string[] | null>();
  /** The change feed: the changes, each person's choice and how far they read, by "company user". */
  changes: ChangeRow[] = [];
  changeSettings = new Map<
    string,
    { enabled: boolean; immediateKinds: string[]; digest: string; appUrl: string }
  >();
  changeReads = new Map<string, number>();
  private changeSeq = 0;
  private pushSeq = 0;
  private rev = 0;
  private tokens = new Map<string, string>();
  private counter = 0;

  addUser(email: string, password: string, fullName: string, confirmed = true): FakeUser {
    this.counter += 1;
    const user: FakeUser = {
      id: `00000000-0000-4000-8000-${String(this.counter).padStart(12, '0')}`,
      email: email.toLowerCase(),
      password,
      fullName,
      language: 'en',
      confirmed,
    };
    this.users.set(user.email, user);
    return user;
  }

  /** An invitation link token for `email`, as the owner would create it. */
  invite(company: string, email: string, role: Role, invitedBy: string): Invite {
    const invite: Invite = {
      id: `invite-${this.invites.length + 1}`,
      token: 'ab'.repeat(32),
      company,
      email,
      role,
      invitedBy,
      accepted: false,
    };
    this.invites.push(invite);
    return invite;
  }

  rows(company: string, tbl?: string): Row[] {
    return [...this.records.values()].filter(
      (r) => r.company === company && !r.deleted && (!tbl || r.tbl === tbl),
    );
  }

  calls(fn: string): SeenRequest[] {
    return this.requests.filter((r) => r.path === `/rest/v1/rpc/${fn}`);
  }

  async install(page: Page): Promise<void> {
    await page.route(`${SUPABASE_URL}/**`, (route) => this.handle(route));
    await page.routeWebSocket(/\/realtime\/v1\/websocket/, (ws) => this.socket(ws));
  }

  private userJson(user: FakeUser) {
    const now = new Date().toISOString();
    return {
      id: user.id,
      aud: 'authenticated',
      role: 'authenticated',
      email: user.email,
      email_confirmed_at: user.confirmed ? now : null,
      confirmed_at: user.confirmed ? now : null,
      confirmation_sent_at: now,
      phone: '',
      app_metadata: { provider: 'email', providers: ['email'] },
      user_metadata: { full_name: user.fullName, language: user.language },
      identities: [],
      created_at: now,
      updated_at: now,
    };
  }

  private session(user: FakeUser) {
    const now = Math.floor(Date.now() / 1000);
    const token = [
      base64url({ alg: 'HS256', typ: 'JWT' }),
      base64url({
        sub: user.id,
        email: user.email,
        role: 'authenticated',
        aud: 'authenticated',
        iat: now,
        exp: now + 3600,
      }),
      'signature',
    ].join('.');
    this.tokens.set(token, user.id);
    return {
      access_token: token,
      token_type: 'bearer',
      expires_in: 3600,
      expires_at: now + 3600,
      refresh_token: `refresh-${user.id}`,
      user: this.userJson(user),
    };
  }

  private byToken(header: string | null): FakeUser | undefined {
    const id = this.tokens.get((header ?? '').replace(/^Bearer /i, ''));
    return [...this.users.values()].find((u) => u.id === id);
  }

  private async handle(route: Route): Promise<void> {
    const request = route.request();
    const url = new URL(request.url());
    const method = request.method();
    if (method === 'OPTIONS') {
      await route.fulfill({ status: 200, headers: CORS });
      return;
    }
    const raw = request.postData();
    let body: unknown;
    try {
      body = raw ? JSON.parse(raw) : null;
    } catch {
      body = raw;
    }
    const headers = await request.allHeaders();
    this.requests.push({ method, path: url.pathname, apikey: headers.apikey ?? null, body });
    const me = this.byToken(headers.authorization ?? null);
    const json = (status: number, value: unknown) =>
      route.fulfill({
        status,
        headers: { ...CORS, 'content-type': 'application/json' },
        body: JSON.stringify(value),
      });
    const b = (body ?? {}) as Record<string, unknown>;

    // Accounts
    if (url.pathname === '/auth/v1/signup') {
      const email = String(b.email).toLowerCase();
      const meta = (b.data ?? {}) as { full_name?: string; language?: 'en' | 'ar' };
      const user =
        this.users.get(email) ??
        this.addUser(email, String(b.password), meta.full_name ?? '', false);
      user.fullName = meta.full_name ?? user.fullName;
      user.language = meta.language ?? user.language;
      return json(200, this.userJson(user));
    }
    if (url.pathname === '/auth/v1/token' && url.searchParams.get('grant_type') === 'password') {
      const user = this.users.get(String(b.email).toLowerCase());
      if (!user || user.password !== b.password || !user.confirmed) {
        return json(400, {
          code: 400,
          error_code: 'invalid_credentials',
          msg: 'Invalid login credentials',
        });
      }
      return json(200, this.session(user));
    }
    if (url.pathname === '/auth/v1/logout') {
      return route.fulfill({ status: 204, headers: CORS });
    }
    if (url.pathname === '/auth/v1/user') {
      if (!me) return json(401, { code: 401, msg: 'Unauthorized' });
      if (method === 'PUT') {
        const data = (b.data ?? {}) as { full_name?: string; language?: 'en' | 'ar' };
        if (data.full_name) me.fullName = data.full_name;
        if (data.language) me.language = data.language;
      }
      return json(200, this.userJson(me));
    }
    if (url.pathname.startsWith('/auth/v1/')) return json(200, {});

    // Profiles
    if (url.pathname === '/rest/v1/profiles') {
      if (!me) return json(200, []);
      if (method === 'PATCH') {
        if (typeof b.full_name === 'string') me.fullName = b.full_name;
        if (b.language === 'en' || b.language === 'ar') me.language = b.language;
        return route.fulfill({ status: 204, headers: CORS });
      }
      const profile = { full_name: me.fullName, language: me.language, email: me.email };
      return (headers.accept ?? '').includes('vnd.pgrst.object')
        ? json(200, profile)
        : json(200, [profile]);
    }
    if (url.pathname === '/rest/v1/records') return json(200, []);
    if (url.pathname.startsWith('/storage/v1/')) return json(200, []);

    // The email-alerts function: "Send it now".
    if (url.pathname === '/functions/v1/email-alerts') {
      if (!me) return json(401, { ok: false, error: 'auth', message: 'Sign in again.' });
      const company = String(b.companyId ?? '');
      const role = this.companies.get(company)?.members.get(me.id);
      // Accountants too, as 20261130000000_people_alerts.sql lets them (#18).
      if (role !== 'owner' && role !== 'admin' && role !== 'accountant') {
        return json(403, { ok: false, error: 'permission', message: '' });
      }
      if (!this.emailAlerts.get(`${company} ${me.id}`)?.enabled) {
        return json(409, { ok: false, error: 'not_enabled', message: '' });
      }
      this.alertEmails.push({ company, to: me.email });
      return json(200, { ok: true, to: me.email, count: 3 });
    }

    // Database functions
    const fn = /^\/rest\/v1\/rpc\/(\w+)$/.exec(url.pathname)?.[1];
    if (fn && me) {
      const result = this.rpc(fn, b, me);
      if (result === undefined) return route.fulfill({ status: 204, headers: CORS });
      if (result instanceof Refusal) {
        return json(result.status, { ...result.body, details: null, hint: null });
      }
      return json(200, result);
    }
    return json(404, { message: 'Not found' });
  }

  /** Whether the owner's limits keep `user` from storing this record (as can_write_record). */
  private limited(
    company: string,
    user: string,
    tbl: string,
    data: Record<string, unknown> | null,
  ): boolean {
    if (this.companies.get(company)?.members.get(user) === 'owner') return false;
    let app = recordApp(tbl, data);
    // A file is of the app of the record it is kept with.
    if (tbl === 'attachments' && typeof data?.ownerId === 'string') {
      for (const owner of ATTACHMENT_OWNERS) {
        const row = this.records.get(`${company}/${owner}/${data.ownerId}`);
        if (row && !row.deleted) {
          app = recordApp(owner, row.data);
          break;
        }
      }
    }
    const limit = app ? this.access.get(`${company} ${user}`)?.permissions.apps?.[app] : undefined;
    return limit === 'none' || limit === 'view';
  }

  /** The books' settings on the company record changed (almailbooks.company_books_changed). */
  private booksChanged(old: Record<string, unknown> | null, data: Record<string, unknown>) {
    if (!old) return false;
    if (COMPANY_BOOKS.some((key) => canonical(old[key]) !== canonical(data[key]))) return true;
    // The WAMD number printed with the payment details, empty and none alike.
    const wamd = (row: Record<string, unknown>) => {
      const kuwait = row.kuwait;
      const phone =
        kuwait && typeof kuwait === 'object' && !Array.isArray(kuwait)
          ? (kuwait as Record<string, unknown>).wamdPhone
          : null;
      return canonical(phone === '' ? null : phone);
    };
    if (wamd(old) !== wamd(data)) return true;
    const rules = (row: Record<string, unknown>) =>
      (row.numbering && typeof row.numbering === 'object' ? row.numbering : {}) as Record<
        string,
        Record<string, unknown> | null
      >;
    const shape = (rule: Record<string, unknown> | null | undefined) => {
      if (!rule || typeof rule !== 'object') return canonical(rule);
      const copy = { ...rule };
      delete copy.next;
      delete copy.period;
      return canonical(copy);
    };
    const before = rules(old);
    const after = rules(data);
    return Object.keys(before).some(
      (key) => key !== 'employee' && key in after && shape(before[key]) !== shape(after[key]),
    );
  }

  /**
   * almailbooks.records_guard and the approval part of can_delete_record:
   * what is stored for a change, or the refusal.
   */
  private guard(
    company: string,
    user: string,
    role: Role | undefined,
    change: { tbl: string; id: string; data?: Record<string, unknown>; deleted?: boolean },
  ): Record<string, unknown> | null | Refusal {
    const row = this.records.get(`${company}/${change.tbl}/${change.id}`);
    const old = row && !row.deleted ? row.data : null;
    let data = change.deleted ? null : (change.data ?? null);
    const companyRow = this.records.get(`${company}/companies/${company}`);
    // Sub-warehouses and items issued (20261210000000_warehouse_issues.sql).
    const warehouses = warehouseRules(role, user, (id) => {
      const found = this.records.get(`${company}/warehouses/${id}`);
      return found && !found.deleted ? found.data : null;
    });
    const refused = warehouses.refusal(change.tbl, old, data, this.approver(company, user));
    if (refused) return refuse(`almail:permission ${refused}`);
    // The movements of items issued go with the issue while it stands.
    if (change.tbl === 'stockMovements' && !data && old?.sourceType === 'issue') {
      const issue = this.records.get(`${company}/stockIssues/${String(old.sourceId ?? '')}`);
      if (issue && !issue.deleted && issue.data?.status === 'posted') {
        return refuse('almail:permission You cannot delete this record.');
      }
    }
    if (change.tbl === 'approvals' && !old && data?.kind === 'stock_issue') {
      // Asked for by whoever sends it, as the one who issued the items:
      // named as the warehouse's keeper when it is theirs.
      const asked = (data.after ?? null) as Data | null;
      const store = this.records.get(`${company}/warehouses/${String(asked?.warehouseId ?? '')}`);
      const keeper = (store && !store.deleted ? store.data?.keeper : null) as Data | null;
      const name = typeof keeper?.name === 'string' ? keeper.name.trim() : '';
      const title = typeof keeper?.jobTitle === 'string' ? keeper.jobTitle.trim() : '';
      const named = keeper?.userId === user && name ? (title ? `${name} (${title})` : name) : null;
      const { requestedByName: _name, ...request } = data;
      data = named ? { ...request, requestedByName: named } : request;
      if (asked && typeof asked === 'object' && !Array.isArray(asked)) {
        const { issuedByName: _issuer, ...issue } = asked;
        data = {
          ...data,
          after: { ...issue, issuedBy: user, ...(named ? { issuedByName: named } : {}) },
        };
      }
    }
    // Employee letters (#19, 20261130000000_people_alerts.sql).
    if (change.tbl === 'peopleSettings') {
      if (role === 'owner' || role === 'admin') return data;
      // With the letters on, deleting the settings would turn them off.
      if (!data) {
        return old?.letters === true
          ? refuse('almail:permission You cannot delete this record.')
          : null;
      }
      // Anyone else's copy keeps the letters switch as it is stored.
      const kept: Record<string, unknown> = { ...data };
      if (old && 'letters' in old && old.letters !== undefined) kept.letters = old.letters;
      else delete kept.letters;
      return kept;
    }
    if (change.tbl === 'employeeLetters') {
      const settings = this.records.get(`${company}/peopleSettings/${company}`);
      if (settings?.deleted || settings?.data?.letters !== true) return data;
      const issuer = role === 'owner' || role === 'admin' || this.approver(company, user);
      const was = old ? String(old.status ?? 'draft') : null;
      if (!data) {
        return was && was !== 'draft'
          ? refuse('almail:permission You cannot delete this record.')
          : null;
      }
      const status = String(data.status ?? 'draft');
      if ((was === 'issued' || was === 'void') && status === 'draft') {
        return refuse('almail:invalid This letter is already issued, so it stays issued.');
      }
      const content = (row: Record<string, unknown>) => {
        const copy = { ...row };
        delete copy.printedAt;
        delete copy.updatedAt;
        return canonical(copy);
      };
      // An issued letter stays as it was issued, a void one void
      // (almailbooks.issued_letter_kept): only when it was printed is added,
      // and an issued one may be voided.
      let next = data;
      if (old && (was === 'issued' || was === 'void')) {
        const voiding = was === 'issued' && status === 'void';
        const keptLetter: Record<string, unknown> = { ...old };
        delete keptLetter.updatedAt;
        delete keptLetter.printedAt;
        if (voiding) {
          delete keptLetter.status;
          delete keptLetter.voidReason;
          delete keptLetter.voidedOn;
        }
        if (data.updatedAt != null) keptLetter.updatedAt = data.updatedAt;
        const printed = [old.printedAt, data.printedAt]
          .filter((at): at is string => typeof at === 'string')
          .sort()
          .pop();
        if (printed) keptLetter.printedAt = printed;
        if (voiding) {
          keptLetter.status = 'void';
          if (data.voidReason != null) keptLetter.voidReason = data.voidReason;
          if (data.voidedOn != null) keptLetter.voidedOn = data.voidedOn;
        }
        next = keptLetter;
      }
      const nextStatus = String(next.status ?? 'draft');
      if (
        !issuer &&
        (nextStatus !== 'draft' || (was !== null && was !== 'draft')) &&
        (!old || content(old) !== content(next))
      ) {
        return refuse(
          'almail:permission Only the owner, an admin or an approver issues letters. Ask for approval instead.',
        );
      }
      return next;
    }
    const rules = (companyRow?.data?.approvalRules ?? null) as {
      documentTypes?: string[];
      voidInsteadOfDelete?: boolean;
      cheques?: { issued?: boolean; received?: boolean; securityOut?: boolean };
      payroll?: boolean;
    } | null;
    if (change.tbl === 'companies') {
      const before = canonical(old?.approvalRules ?? null);
      if (data && role !== 'owner' && before !== canonical(data.approvalRules ?? null)) {
        return refuse('almail:permission Only the owner changes the approval rules.');
      }
      const books =
        role === 'owner'
          ? undefined
          : this.access.get(`${company} ${user}`)?.permissions.apps?.books;
      if (data && (books === 'view' || books === 'none') && this.booksChanged(old, data)) {
        return refuse('almail:permission The owner has made Maham Books view only for you.');
      }
      // The AI assistant's switch (20261208000000_ai_assistant.sql): anyone
      // but the owner or an admin keeps it as it is stored.
      if (data && role !== 'owner' && role !== 'admin') {
        const kept: Record<string, unknown> = { ...data };
        if (old && 'ai' in old && old.ai !== undefined) kept.ai = old.ai;
        else delete kept.ai;
        return kept;
      }
      return data;
    }
    const approver =
      role === 'owner' ||
      ((role === 'admin' || role === 'accountant') &&
        Boolean(this.access.get(`${company} ${user}`)?.canApprove));
    if (rules && (change.tbl === 'payments' || change.tbl === 'securityCheques')) {
      if (!approver && chequeNeedsApprover(rules.cheques, change.tbl, old, data)) {
        return data
          ? chequeConfirmationRequired()
          : refuse('almail:permission You cannot delete this record.');
      }
      return data;
    }
    if (change.tbl !== 'documents' && change.tbl !== 'approvals') return data;
    const covers = (doc: Record<string, unknown> | null) =>
      Boolean(doc && rules?.documentTypes?.includes(String(doc.type)));
    if (!data) {
      if (!old) return null;
      // Approval requests stay, whether or not the rules are on.
      if (change.tbl === 'approvals')
        return refuse('almail:permission You cannot delete this record.');
      if (
        rules &&
        covers(old) &&
        old.status !== 'draft' &&
        (rules.voidInsteadOfDelete || !approver)
      ) {
        return refuse('almail:permission You cannot delete this record.');
      }
      return null;
    }
    if (change.tbl === 'documents') {
      // With numberOnIssue, an invoice or credit note is never issued without its number.
      const defaults = (companyRow?.data?.defaults ?? null) as { numberOnIssue?: boolean } | null;
      if (
        defaults?.numberOnIssue === true &&
        (data.type === 'invoice' || data.type === 'credit') &&
        stage(data.status) === 'issued' &&
        String(data.number ?? '').trim() === '' &&
        (!old || old.status === 'draft')
      ) {
        return refuse(
          'almail:invalid This invoice has no number yet. Update the app on this device, then issue it again.',
        );
      }
      if (!rules || !old || approver || old.status === 'draft' || !(covers(old) || covers(data)))
        return data;
      if (content(old) !== content(data) || stage(old.status) !== stage(data.status)) {
        return approvalRequired();
      }
      // Its payment link, once it has one (almailbooks.payment_link_changed):
      // anyone else's copy keeps the stored link.
      const was = linkUrl(old);
      if (was === '' || was === linkUrl(data)) return data;
      const kept: Record<string, unknown> = { ...data };
      if ('paymentLink' in old && old.paymentLink !== undefined) kept.paymentLink = old.paymentLink;
      else delete kept.paymentLink;
      return kept;
    }
    // Approval requests, whether or not the rules are on. With salary
    // approval on (#10, 20261130000000_people_alerts.sql), a pay run's.
    const now = new Date().toISOString();
    const payroll =
      rules?.payroll === true &&
      (old ?? data).kind === 'payroll' &&
      (old ?? data).subjectTbl === 'payRuns';
    if (!old) {
      const wanted = data.status ?? 'pending';
      const selfApproved = payroll && (wanted === 'approved' || wanted === 'applied');
      if (approver && wanted !== 'pending' && (role === 'owner' || !selfApproved)) {
        if (role === 'owner') return data;
        const own: Record<string, unknown> = { ...data };
        if (own.requestedBy !== user) {
          delete own.requestedByName;
          Object.assign(own, { requestedBy: user, requestedAt: now });
        }
        if (own.decidedBy !== user) Object.assign(own, { decidedBy: user, decidedAt: now });
        return own;
      }
      const asked: Record<string, unknown> = { ...data };
      delete asked.expired;
      delete asked.resultId;
      return {
        ...asked,
        status: 'pending',
        requestedBy: user,
        requestedAt: now,
        decidedBy: null,
        decidedAt: null,
        decisionNote: '',
      };
    }
    const kept = (target: Record<string, unknown>, key: string) => {
      if (key in old && old[key] !== undefined) target[key] = old[key];
      else delete target[key];
    };
    const was = String(old.status ?? 'pending');
    const status = String(data.status ?? was);
    // Whoever isn't an approver changes nothing of a request but taking it back.
    const next: Record<string, unknown> = approver
      ? { ...data }
      : { ...old, status, ...('updatedAt' in data ? { updatedAt: data.updatedAt } : {}) };
    for (const key of [
      'kind',
      'subjectTbl',
      'subjectId',
      'subjectNumber',
      'before',
      'after',
    ].concat(['reason', 'requestedBy', 'requestedByName', 'requestedAt', 'createdAt'])) {
      kept(next, key);
    }
    const decision = {
      decidedBy: old.decidedBy ?? null,
      decidedAt: old.decidedAt ?? null,
      decisionNote: old.decisionNote ?? '',
    };
    if (
      status === was ||
      status === 'pending' ||
      ['rejected', 'cancelled', 'applied'].includes(was)
    ) {
      const same: Record<string, unknown> = { ...next, status: was, ...decision };
      kept(same, 'expired');
      kept(same, 'resultId');
      return same;
    }
    const takenBack = was === 'pending' && status === 'cancelled' && old.requestedBy === user;
    // The approved pay run posted: done, by whoever may post it.
    const posted =
      payroll &&
      was === 'approved' &&
      status === 'applied' &&
      (role === 'owner' || role === 'admin' || role === 'accountant') &&
      !this.limited(company, user, 'payRuns', null);
    if (!approver && !takenBack && !posted) {
      return refuse('almail:permission Only an approver decides approval requests.');
    }
    // A member the owner gave no access to People decides no pay run.
    if (
      payroll &&
      role !== 'owner' &&
      this.access.get(`${company} ${user}`)?.permissions.apps?.people === 'none' &&
      !takenBack
    ) {
      return refuse(
        "almail:permission The owner has given you no access to Maham People, so you don't decide pay runs.",
      );
    }
    if (payroll && was === 'pending' && (status === 'approved' || status === 'applied')) {
      if (old.requestedBy === user && role !== 'owner') {
        return refuse(
          'almail:permission Only the owner approves a pay run they sent for approval themselves.',
        );
      }
      const run = this.records.get(`${company}/payRuns/${String(old.subjectId)}`);
      const stored = run && !run.deleted ? run.data?.updatedAt : undefined;
      const asked = (old.after as Record<string, unknown> | null | undefined)?.runUpdatedAt;
      if (!(status === 'applied' && role === 'owner') && (stored ?? null) !== (asked ?? null)) {
        return refuse(
          'almail:invalid This pay run changed after it was sent for approval. Send it for approval again.',
        );
      }
    }
    if (!(approver && was === 'pending' && status === 'cancelled')) kept(next, 'expired');
    if (!(approver && status === 'applied')) kept(next, 'resultId');
    if (was === 'approved' && status === 'applied') return { ...next, ...decision };
    return { ...next, decidedBy: user, decidedAt: now };
  }

  private approver(company: string, user: string): boolean {
    const role = this.companies.get(company)?.members.get(user);
    return (
      role === 'owner' ||
      ((role === 'admin' || role === 'accountant') &&
        Boolean(this.access.get(`${company} ${user}`)?.canApprove))
    );
  }

  /** As almailbooks.records_change_event, once someone of the company asked for the feed. */
  private recordChange(
    company: string,
    user: string,
    push: number,
    tbl: string,
    id: string,
    old: Data | null,
    data: Data | null,
  ) {
    const on = [...this.changeSettings].some(
      ([key, settings]) => key.startsWith(`${company} `) && settings.enabled,
    );
    if (!on || tbl === 'activities' || (old && data && canonical(old) === canonical(data))) return;
    const row = (data ?? old)!;
    const people = [
      'employees',
      'payRuns',
      'payrollSettings',
      'peopleSettings',
      'leaveRecords',
      'staffLoans',
      'finalSettlements',
      'letterTemplates',
      'employeeLetters',
      'staffingCostings',
    ];
    const isPrivate =
      people.includes(tbl) ||
      row._private === true ||
      // A request about payroll or people data (a pay run).
      (tbl === 'approvals' && people.includes(String(row.subjectTbl))) ||
      (tbl === 'complianceDocuments' &&
        typeof row.employeeId === 'string' &&
        row.employeeId !== '');
    const clientId = typeof row.clientId === 'string' ? row.clientId : '';
    const client = clientId
      ? (this.records.get(`${company}/clients/${clientId}`)?.data ?? null)
      : null;
    const details = changeDetails(tbl, old, data, isPrivate, client);
    if (!details) return;
    const kind = changeKind(tbl, row);
    const op = !old ? 'insert' : !data ? 'delete' : 'update';
    const fold = details.important
      ? `one:${this.changeSeq + 1}`
      : ['tx', push, user, tbl, tbl === 'documents' ? row.type : '', kind, isPrivate].join(':');
    const folded = this.changes.find((c) => c.company === company && c.fold === fold);
    if (folded) {
      folded.count += 1;
      folded.op = folded.op === op ? op : 'mixed';
      folded.record_id = id;
      folded.summary = details.summary;
      return;
    }
    this.changeSeq += 1;
    this.changes.push({
      company,
      id: this.changeSeq,
      at: new Date().toISOString(),
      actor: user,
      op,
      tbl,
      record_id: id,
      kind,
      important: details.important,
      private: isPrivate,
      count: 1,
      fold,
      summary: details.summary,
    });
  }

  private changeSettingsRow(company: string, user: string) {
    const saved = this.changeSettings.get(`${company} ${user}`);
    return [
      {
        enabled: saved?.enabled ?? false,
        immediate_kinds: saved?.immediateKinds ?? [
          'document',
          'cheque',
          'approval',
          'member',
          'settings',
          'people',
        ],
        digest: saved?.digest ?? 'daily',
        last_sent_at: null,
        last_error: '',
        last_error_at: null,
        function_ready: true,
      },
    ];
  }

  private rpc(fn: string, b: Record<string, unknown>, me: FakeUser): unknown {
    const company = String(b.p_company ?? '');
    const entry = this.companies.get(company);
    const mine = entry?.members.get(me.id);
    const ownerOnly = this.seniorRolesOwnerOnly.has(company);
    switch (fn) {
      case 'create_company': {
        const id = String(b.p_id);
        let entry = this.companies.get(id);
        if (!entry) {
          entry = {
            id,
            name: String(b.p_name),
            members: new Map(),
            createdAt: new Date().toISOString(),
          };
          entry.members.set(me.id, 'owner');
          this.companies.set(id, entry);
        }
        return [{ id, name: entry.name, role: 'owner' }];
      }
      case 'my_companies':
        return [...this.companies.values()]
          .filter((c) => c.members.has(me.id))
          .map((c) => ({
            id: c.id,
            name: c.name,
            role: c.members.get(me.id),
            created_at: c.createdAt,
            members: c.members.size,
          }));
      case 'push_records': {
        const changes = b.p_changes as {
          tbl: string;
          id: string;
          data?: Record<string, unknown>;
          deleted?: boolean;
        }[];
        // All or nothing, like the database: the owner's limits on the member.
        const blocked = changes.some((change) => {
          const old = this.records.get(`${company}/${change.tbl}/${change.id}`)?.data ?? null;
          return (
            this.limited(company, me.id, change.tbl, change.data ?? null) ||
            this.limited(company, me.id, change.tbl, old)
          );
        });
        if (blocked) {
          return refuse('new row violates row-level security policy for table "records"');
        }
        // Then the company's approval rules (records_guard, can_delete_record).
        const stored: (Record<string, unknown> | null)[] = [];
        for (const change of changes) {
          const guarded = this.guard(company, me.id, mine, change);
          if (guarded instanceof Refusal) return guarded;
          stored.push(guarded);
        }
        this.pushSeq += 1;
        return changes.map((change, i) => {
          const before = this.records.get(`${company}/${change.tbl}/${change.id}`);
          this.recordChange(
            company,
            me.id,
            this.pushSeq,
            change.tbl,
            change.id,
            before && !before.deleted ? before.data : null,
            change.deleted ? null : stored[i],
          );
          this.rev += 1;
          this.records.set(`${company}/${change.tbl}/${change.id}`, {
            company,
            tbl: change.tbl,
            id: change.id,
            data: change.deleted ? null : stored[i],
            rev: this.rev,
            deleted: Boolean(change.deleted),
          });
          return { tbl: change.tbl, id: change.id, rev: this.rev, conflict: false };
        });
      }
      case 'pull_records': {
        const since = Number(b.p_since ?? 0);
        const limit = Number(b.p_limit ?? 500);
        // Staff and viewers never get payroll and people data (record_is_private).
        const seesPeople = mine === 'owner' || mine === 'admin' || mine === 'accountant';
        return [...this.records.values()]
          .filter((r) => r.company === company && r.rev > since)
          .filter((r) => seesPeople || !privateRow(r.tbl, r.data))
          .sort((x, y) => x.rev - y.rev)
          .slice(0, limit)
          .map((r) => ({ tbl: r.tbl, id: r.id, data: r.data, rev: r.rev, deleted: r.deleted }));
      }
      case 'company_sync_info': {
        const rows = this.rows(company);
        return [
          {
            purged_until_rev: 0,
            record_count: rows.length,
            max_rev: Math.max(0, ...rows.map((r) => r.rev)),
          },
        ];
      }
      case 'company_record_ids':
        return [];
      case 'server_features':
        return [
          'tables_v16',
          'super_admin',
          'approvals',
          'cheque_approvals',
          'change_feed',
          'payroll_approvals',
          'document_alerts',
          'employee_letters',
          'staffing_costings',
          'ai_assistant',
          'stock_issues',
        ];
      // The change feed (20261123000000_change_feed.sql).
      case 'notification_status': {
        if (!this.approver(company, me.id)) return [{ enabled: false, unread: 0, latest: 0 }];
        const key = `${company} ${me.id}`;
        const visible = this.changes.filter((c) => c.company === company && c.actor !== me.id);
        const read = this.changeReads.get(key) ?? 0;
        return [
          {
            enabled: Boolean(this.changeSettings.get(key)?.enabled),
            unread: Math.min(100, visible.filter((c) => c.id > read).length),
            latest: Math.max(0, ...visible.map((c) => c.id)),
          },
        ];
      }
      case 'notification_feed': {
        if (!this.approver(company, me.id)) {
          return refuse('almail:permission Only the owner and approvers see the changes.');
        }
        const read = this.changeReads.get(`${company} ${me.id}`) ?? 0;
        const after = Number(b.p_after ?? 0);
        const before = b.p_before == null ? Infinity : Number(b.p_before);
        const name = (id: string) => {
          const user = [...this.users.values()].find((u) => u.id === id);
          return user ? user.fullName || user.email : '';
        };
        return this.changes
          .filter((c) => c.company === company && c.actor !== me.id)
          .filter((c) => c.id > after && c.id < before)
          .sort((x, y) => y.id - x.id)
          .slice(0, Number(b.p_limit ?? 50))
          .map((c) => ({
            id: c.id,
            at: c.at,
            actor: c.actor,
            actor_name: name(c.actor),
            subject_name: c.kind === 'member' ? name(String(c.summary.user ?? '')) : '',
            kind: c.kind,
            op: c.op,
            tbl: c.tbl,
            record_id: c.record_id,
            count: c.count,
            important: c.important,
            private: c.private,
            summary: c.summary,
            unread: c.id > read,
          }));
      }
      case 'mark_notifications_read': {
        if (!this.approver(company, me.id)) return refuse('almail:permission');
        const key = `${company} ${me.id}`;
        const newest = Math.max(
          0,
          ...this.changes.filter((c) => c.company === company).map((c) => c.id),
        );
        this.changeReads.set(
          key,
          Math.max(this.changeReads.get(key) ?? 0, Math.min(Number(b.p_upto ?? 0), newest)),
        );
        return undefined;
      }
      case 'change_notification_settings':
      case 'set_change_notifications': {
        if (!this.approver(company, me.id)) return refuse('almail:permission');
        const key = `${company} ${me.id}`;
        if (fn === 'set_change_notifications') {
          const was = this.changeSettings.get(key)?.enabled ?? false;
          this.changeSettings.set(key, {
            enabled: Boolean(b.p_enabled),
            immediateKinds: (b.p_immediate_kinds as string[]) ?? [],
            digest: String(b.p_digest ?? 'daily'),
            appUrl: String(b.p_app_url ?? ''),
          });
          if (b.p_enabled && !was) {
            const newest = Math.max(
              0,
              ...this.changes.filter((c) => c.company === company).map((c) => c.id),
            );
            this.changeReads.set(key, Math.max(this.changeReads.get(key) ?? 0, newest));
          }
        }
        return this.changeSettingsRow(company, me.id);
      }
      case 'my_permissions': {
        const access = this.access.get(`${company} ${me.id}`);
        return [
          {
            permissions: mine === 'owner' ? {} : (access?.permissions ?? {}),
            can_approve: mine === 'owner' || Boolean(access?.canApprove),
            is_owner: mine === 'owner',
            senior_roles_owner_only: ownerOnly,
          },
        ];
      }
      case 'team_permissions':
        return [...(entry?.members ?? new Map<string, Role>()).keys()]
          .filter((id) => mine === 'owner' || mine === 'admin' || id === me.id)
          .map((id) => ({
            user_id: id,
            permissions: this.access.get(`${company} ${id}`)?.permissions ?? {},
            can_approve: Boolean(this.access.get(`${company} ${id}`)?.canApprove),
          }));
      case 'set_member_permissions':
        if (mine !== 'owner') return refuse('almail:permission Only the owner can set this.');
        this.access.set(`${company} ${String(b.p_user)}`, {
          permissions: (b.p_permissions ?? {}) as { apps?: Record<string, Access> },
          canApprove: Boolean(b.p_can_approve),
        });
        return undefined;
      case 'set_team_rules':
        if (mine !== 'owner') return refuse('almail:permission Only the owner can set this.');
        if (b.p_senior_roles_owner_only) this.seniorRolesOwnerOnly.add(company);
        else this.seniorRolesOwnerOnly.delete(company);
        return undefined;
      case 'owned_companies_overview':
        return [...this.companies.values()]
          .filter((c) => c.members.get(me.id) === 'owner')
          .map((c) => ({
            company_id: c.id,
            name: c.name,
            members: c.members.size,
            pending_approvals: 0,
          }));
      case 'set_member_role': {
        const target = entry?.members.get(String(b.p_user));
        const role = b.p_role as Role;
        if (mine !== 'owner' && mine !== 'admin') return refuse('almail:permission');
        if (!target || target === 'owner') return refuse('almail:permission');
        if (mine === 'admin' && ownerOnly && (SENIOR.includes(target) || SENIOR.includes(role))) {
          return refuse(
            'almail:permission Only the owner can make or change admins and accountants.',
          );
        }
        entry!.members.set(String(b.p_user), role);
        return undefined;
      }
      case 'remove_member': {
        const target = entry?.members.get(String(b.p_user));
        if (!target) return undefined;
        if (target === 'owner') return refuse('almail:permission');
        if (String(b.p_user) !== me.id) {
          if (mine !== 'owner' && mine !== 'admin') return refuse('almail:permission');
          if (mine === 'admin' && ownerOnly && SENIOR.includes(target)) {
            return refuse('almail:permission Only the owner can remove admins and accountants.');
          }
        }
        entry!.members.delete(String(b.p_user));
        return undefined;
      }
      // Who items can be issued to (20261210000000_warehouse_issues.sql).
      case 'stock_issue_recipients': {
        const rows = [...this.records.values()].filter((r) => r.company === company && !r.deleted);
        const rules = warehouseRules(mine, me.id, (id) => {
          const found = this.records.get(`${company}/warehouses/${id}`);
          return found && !found.deleted ? found.data : null;
        });
        const keeps = rows.some((r) => r.tbl === 'warehouses' && rules.issuesFrom(r.id));
        if (!mine || !(rules.manages || keeps)) {
          return refuse(
            'almail:permission Only whoever looks after a sub-warehouse sees who items are issued to.',
          );
        }
        const field = (row: Data | null, key: string) =>
          typeof row?.[key] === 'string' ? (row[key] as string) : '';
        return rows
          .filter((r) => r.tbl === 'employees' && field(r.data, 'status') !== 'left')
          .map((r) => ({
            id: r.id,
            number: field(r.data, 'number'),
            name: field(r.data, 'name'),
            name_ar: field(r.data, 'nameAr'),
            job_title: field(r.data, 'jobTitle'),
            job_title_ar: field(r.data, 'jobTitleAr'),
            department: field(r.data, 'department'),
          }))
          .sort((a, b) => a.name.localeCompare(b.name) || a.id.localeCompare(b.id));
      }
      case 'company_team': {
        const entry = this.companies.get(company);
        return [...(entry?.members ?? new Map<string, Role>()).entries()].map(([id, role]) => {
          const user = [...this.users.values()].find((u) => u.id === id)!;
          return {
            user_id: id,
            full_name: user.fullName,
            email: user.email,
            role,
            joined_at: '2026-10-01T09:00:00Z',
          };
        });
      }
      case 'list_invites':
        return this.invites
          .filter((i) => i.company === company && !i.accepted && !i.revoked)
          .map((i) => ({
            id: i.id,
            email: i.email,
            role: i.role,
            token: i.token,
            created_at: '2026-10-01T09:00:00Z',
            expires_at: new Date(Date.now() + 7 * 864e5).toISOString(),
            invited_by_name: me.fullName,
          }));
      case 'create_invite': {
        if (mine === 'admin' && ownerOnly && SENIOR.includes(b.p_role as Role)) {
          return refuse('almail:permission Only the owner can invite admins and accountants.');
        }
        // Like the server: the owner's invitation of an admin or accountant is the owner's to replace.
        const email = String(b.p_email).toLowerCase();
        if (
          mine === 'admin' &&
          ownerOnly &&
          this.invites.some(
            (i) =>
              i.company === company &&
              i.email === email &&
              !i.accepted &&
              !i.revoked &&
              SENIOR.includes(i.role),
          )
        ) {
          return refuse(
            'almail:permission Only the owner can cancel invitations of admins and accountants.',
          );
        }
        // Like the server: a new link for the same address cancels the pending one.
        for (const pending of this.invites) {
          if (pending.company === company && pending.email === String(b.p_email).toLowerCase()) {
            pending.revoked = true;
          }
        }
        const invite = this.invite(
          company,
          String(b.p_email).toLowerCase(),
          b.p_role as Role,
          me.id,
        );
        invite.token = `${'cd'.repeat(31)}${String(this.invites.length).padStart(2, '0')}`;
        return [
          {
            id: invite.id,
            token: invite.token,
            email: invite.email,
            role: invite.role,
            expires_at: new Date(Date.now() + 7 * 864e5).toISOString(),
          },
        ];
      }
      case 'revoke_invite': {
        // The invitation says which company it is of.
        const invite = this.invites.find((i) => i.id === b.p_invite);
        const role = invite ? this.companies.get(invite.company)?.members.get(me.id) : undefined;
        if (!invite || (role !== 'owner' && role !== 'admin')) {
          return refuse('almail:permission Only the owner and admins can cancel invitations.');
        }
        if (
          role === 'admin' &&
          this.seniorRolesOwnerOnly.has(invite.company) &&
          SENIOR.includes(invite.role)
        ) {
          return refuse(
            'almail:permission Only the owner can cancel invitations of admins and accountants.',
          );
        }
        if (!invite.accepted) invite.revoked = true;
        return null;
      }
      case 'invite_details': {
        const invite = this.invites.find((i) => i.token === b.p_token);
        if (!invite) return [];
        const entry = this.companies.get(invite.company)!;
        const by = [...this.users.values()].find((u) => u.id === invite.invitedBy);
        return [
          {
            company_id: invite.company,
            company_name: entry.name,
            invited_by_name: by?.fullName ?? '',
            email: invite.email,
            role: invite.role,
            expires_at: new Date(Date.now() + 6 * 864e5).toISOString(),
            status: invite.revoked ? 'revoked' : invite.accepted ? 'accepted' : 'pending',
            email_matches: invite.email === me.email,
          },
        ];
      }
      case 'accept_invite': {
        const invite = this.invites.find((i) => i.token === b.p_token)!;
        invite.accepted = true;
        const entry = this.companies.get(invite.company)!;
        entry.members.set(me.id, invite.role);
        return [{ company_id: entry.id, company_name: entry.name, role: invite.role }];
      }
      case 'email_alert_scope': {
        if (!this.companies.get(company)?.members.has(me.id)) return refuse('almail:not_member');
        return [{ document_kinds: this.alertScopes.get(`${company} ${me.id}`) ?? null }];
      }
      case 'set_email_alert_scope': {
        const role = this.companies.get(company)?.members.get(me.id);
        if (role !== 'owner' && role !== 'admin' && role !== 'accountant') {
          return refuse(
            'almail:permission Only the owner, admins and accountants can get email alerts.',
          );
        }
        const all = ['company', 'vehicle', 'staff', 'client'];
        const kinds = b.p_kinds === null ? null : ((b.p_kinds as string[]) ?? []);
        if (kinds && kinds.some((k) => !all.includes(k))) {
          return refuse('almail:invalid Unknown kind of paper.');
        }
        const chosen = kinds ? all.filter((k) => kinds.includes(k)) : null;
        this.alertScopes.set(
          `${company} ${me.id}`,
          chosen && chosen.length < all.length ? chosen : null,
        );
        return undefined;
      }
      case 'email_alert_settings':
      case 'set_email_alerts': {
        const key = `${company} ${me.id}`;
        if (fn === 'set_email_alerts') {
          const role = this.companies.get(company)?.members.get(me.id);
          if (role !== 'owner' && role !== 'admin' && role !== 'accountant') {
            return refuse(
              'almail:permission Only the owner, admins and accountants can get email alerts.',
            );
          }
          this.emailAlerts.set(key, {
            enabled: Boolean(b.p_enabled),
            topics: (b.p_topics as string[]) ?? [],
            appUrl: String(b.p_app_url ?? ''),
          });
        }
        const saved = this.emailAlerts.get(key);
        return [
          {
            enabled: saved?.enabled ?? false,
            topics: saved?.topics ?? ['documents', 'deadlines', 'cheques', 'bills', 'invoices'],
            last_sent_at: null,
            last_error: '',
            last_error_at: null,
            function_ready: true,
          },
        ];
      }
      default:
        return undefined;
    }
  }

  /** Realtime: joins and heartbeats are answered; nothing is pushed. */
  private socket(ws: WebSocketRoute) {
    ws.onMessage((message) => {
      let frame: unknown;
      try {
        frame = JSON.parse(String(message));
      } catch {
        return;
      }
      if (!Array.isArray(frame)) return;
      const [joinRef, ref, topic, event, payload] = frame as [
        string | null,
        string,
        string,
        string,
        Record<string, unknown>,
      ];
      if (event === 'phx_join') {
        const config = (payload?.config ?? {}) as { postgres_changes?: Record<string, unknown>[] };
        const bindings = (config.postgres_changes ?? []).map((b, i) => ({ ...b, id: i + 1 }));
        ws.send(
          JSON.stringify([
            joinRef,
            ref,
            topic,
            'phx_reply',
            { status: 'ok', response: { postgres_changes: bindings } },
          ]),
        );
      } else if (event === 'heartbeat' || event === 'phx_leave' || event === 'access_token') {
        ws.send(JSON.stringify([joinRef, ref, topic, 'phx_reply', { status: 'ok', response: {} }]));
      }
    });
  }
}
