import type { ChangeEvent } from '@/cloud/api';
import { IMMEDIATE_KINDS, type ImmediateKind } from '@/cloud/change-feed';
import { RECORD_LABELS } from '@/cloud/labels';
import { ROLE_LABELS } from '@/cloud/roles';
import { kindLabel as requestLabel } from '@/features/approvals/labels';
import { currentLanguage, msg, t, tp } from '@/i18n';
import { lookup } from '@/lib/known';
import { documentTypeInfo } from '@/lib/compliance';

/**
 * The changes of the team in words, for the bell, the Updates page and the
 * emails of the email-alerts function (in the interface language at the
 * time: load the reader's first). Each change reads as what was done to
 * what ("Voided invoice INV-0042"), with who did it apart. Changes about
 * payroll and people data carry no names or amounts, so none are shown.
 */

/** The kinds of change in words (English keys), for the filters. */
export const CHANGE_KIND_LABELS: Record<string, string> = {
  document: msg('Invoices and documents'),
  payment: msg('Payments'),
  cheque: msg('Cheques'),
  approval: msg('Approval requests'),
  settings: msg('Company settings'),
  member: msg('Team'),
  people: msg('Payroll and people'),
  compliance: msg('Compliance'),
  contact: msg('Customers and vendors'),
  item: msg('Items and stock'),
  expense: msg('Expenses'),
  accounting: msg('Accounting'),
  file: msg('Files'),
  document_expiry: msg('Expiry reminders'),
};

/** A kind in words, also one a newer version records. */
export function changeKindLabel(kind: string): string {
  return lookup(CHANGE_KIND_LABELS, kind, msg('Other changes'));
}

/** What is emailed at once, kind by kind (Settings → Email alerts → Changes by your team). */
export const IMMEDIATE_KIND_LABELS: Record<ImmediateKind, { label: string; description: string }> =
  {
    document: {
      label: msg('Invoices and credit notes'),
      description: msg('An issued invoice or credit note changed, voided, restored or deleted.'),
    },
    cheque: {
      label: msg('Cheques'),
      description: msg(
        'A cheque recorded, changed, returned, cancelled or deleted, and security cheques.',
      ),
    },
    approval: {
      label: msg('Approval requests'),
      description: msg('A request for approval, and each approval or rejection.'),
    },
    member: {
      label: msg('Team'),
      description: msg('Someone joined or left, a role or a member’s permissions changed.'),
    },
    settings: {
      label: msg('Company settings'),
      description: msg('The numbering, the lock date or the approval rules changed.'),
    },
    people: {
      label: msg('Payroll'),
      description: msg('A pay run added, approved, paid or deleted (without names or amounts).'),
    },
  };

export { IMMEDIATE_KINDS };

/** Types of document, as the app names them (the same English keys). */
const DOCUMENT_TYPES: Record<string, { one: string; many: string }> = {
  invoice: { one: msg('Invoice'), many: msg('Invoices') },
  quote: { one: msg('Quote'), many: msg('Quotes') },
  credit: { one: msg('Credit note'), many: msg('Credit notes') },
  bill: { one: msg('Bill'), many: msg('Bills') },
  vendor_credit: { one: msg('Vendor credit'), many: msg('Vendor credits') },
  proforma: { one: msg('Proforma invoice'), many: msg('Proforma invoices') },
  sales_order: { one: msg('Sales order'), many: msg('Sales orders') },
  purchase_order: { one: msg('Purchase order'), many: msg('Purchase orders') },
  delivery_note: { one: msg('Delivery note'), many: msg('Delivery notes') },
};

/** Writes amounts and dates the reader's way. */
export interface ChangeFormat {
  money: (amount: number, currency: string) => string;
  date: (value: string) => string;
}

export interface ChangeLine {
  /** Who made it. */
  actor: string;
  /** What was done to what. */
  text: string;
  /** The customer and the amount, when there are any to show. */
  detail: string;
  important: boolean;
  /**
   * The text starts with the person it is about, who made it (or nobody
   * did: a new owner taking over): it reads without the actor before it.
   */
  named?: boolean;
}

const str = (value: unknown) => (typeof value === 'string' ? value.trim() : '');
const lower = (text: string) => (currentLanguage() === 'en' ? text.toLowerCase() : text);
const joined = (...parts: string[]) => parts.filter(Boolean).join(' ');

/** "Invoice INV-0042" in the middle of a sentence. */
function documentName(summary: Record<string, unknown>): string {
  const type = DOCUMENT_TYPES[str(summary.type)];
  return joined(lower(t(type?.one ?? msg('Document'))), str(summary.number));
}

/** The record a change is about, in a few words. */
function thing(event: ChangeEvent): string {
  const s = event.summary;
  if (event.private) {
    if (event.tbl === 'payRuns') {
      const period = str(s.period);
      // A left-to-right run in Arabic, so "2026-10" doesn't read "10-2026".
      const month = currentLanguage() === 'ar' ? `\u2066${period}\u2069` : period;
      return period ? t('the pay run for {month}', { month }) : t('a pay run');
    }
    if (event.tbl === 'approvals') return lower(t(requestLabel(str(s.request))));
    return lower(t(lookup(RECORD_LABELS, event.tbl, msg('Record'))));
  }
  switch (event.tbl) {
    case 'documents':
      return documentName(s);
    case 'payments':
      if (event.kind === 'cheque' || s.method === 'cheque') {
        return t('cheque {number}', { number: str(s.cheque) || str(s.number) || '—' });
      }
      return t('payment {number}', { number: str(s.number) || '—' });
    case 'securityCheques':
      return t('security cheque {number}', { number: str(s.cheque) || '—' });
    case 'approvals':
      return joined(lower(t(requestLabel(str(s.request)))), str(s.number));
    case 'clients':
    case 'products': {
      const name = (currentLanguage() === 'ar' && str(s.nameAr)) || str(s.name);
      return name || lower(t(lookup(RECORD_LABELS, event.tbl, msg('Record'))));
    }
    case 'expenses':
      return t('expense {number}', { number: str(s.number) || '—' });
    case 'journals':
      return t('journal entry {number}', { number: str(s.number) || '—' });
    default: {
      const label = lower(t(lookup(RECORD_LABELS, event.tbl, msg('Record'))));
      return joined(label, str(s.name));
    }
  }
}

/** Ordinary changes folded together: "12 changes to invoices". */
function foldText(event: ChangeEvent): string {
  const s = event.summary;
  const things =
    event.tbl === 'documents' && DOCUMENT_TYPES[str(s.type)]
      ? lower(t(DOCUMENT_TYPES[str(s.type)].many))
      : lower(t(changeKindLabel(event.kind)));
  return tp(event.count, '{count} change to {things}', '{count} changes to {things}', { things });
}

function teamText(event: ChangeEvent): string {
  const s = event.summary;
  const name = event.subjectName.trim() || t('a member');
  const role = lower(t(lookup(ROLE_LABELS, str(s.role), msg('Member'))));
  switch (s.reason) {
    case 'joined':
      return t('{name} joined the team as {role}', { name, role });
    case 'left':
      return event.actor && event.actor === str(s.user)
        ? t('{name} left the team', { name })
        : t('Removed {name} from the team', { name });
    case 'ownership':
      return t('Made {name} the owner', { name });
    case 'succession':
      return t('{name} took over as the owner', { name });
    case 'permissions':
      return t('Changed what {name} may do', { name });
    default:
      // Their own role, changed as they handed over the company.
      return selfChange(event)
        ? t('{name} became {role}', { name, role })
        : t('Made {name} {role}', { name, role });
  }
}

/** A change of the team made by the member it is about. */
function selfChange(event: ChangeEvent): boolean {
  return Boolean(event.actor) && event.actor === str(event.summary.user);
}

/** Whether a change of the team is said starting with the member it is about (see teamText). */
function namedInText(event: ChangeEvent): boolean {
  const reason = str(event.summary.reason);
  if (reason === 'joined' || reason === 'succession') return true;
  if (reason === 'ownership' || reason === 'permissions') return false;
  return selfChange(event);
}

function settingsText(event: ChangeEvent, format?: ChangeFormat): string {
  const s = event.summary;
  const changes = Array.isArray(s.changes) ? s.changes.map(String) : [];
  const parts: string[] = [];
  if (changes.includes('lockDate')) {
    const date = str(s.lockDate);
    parts.push(
      date
        ? t('Moved the lock date to {date}', { date: format ? format.date(date) : date })
        : t('Removed the lock date'),
    );
  }
  if (changes.includes('numbering')) parts.push(t('Changed the numbering'));
  if (changes.includes('approvalRules')) parts.push(t('Changed the approval rules'));
  return parts.length ? parts.join(' · ') : t('Changed the company settings');
}

/** What was done, as a sentence around the record. */
function actionText(event: ChangeEvent, what: string, name: string): string {
  switch (what) {
    case 'added':
      return t('Added {thing}', { thing: name });
    case 'deleted':
      return t('Deleted {thing}', { thing: name });
    case 'voided':
      return t('Voided {thing}', { thing: name });
    case 'restored':
      return t('Restored {thing} from void', { thing: name });
    case 'issued':
      return t('Issued {thing}', { thing: name });
    case 'edited':
      return event.tbl === 'documents'
        ? t('Edited {thing} after it was issued', { thing: name })
        : t('Changed {thing}', { thing: name });
    case 'deposited':
      return t('Deposited {thing}', { thing: name });
    case 'cleared':
      return t('Cleared {thing}', { thing: name });
    case 'returned':
      return t('Marked {thing} as returned', { thing: name });
    case 'cancelled':
      return event.tbl === 'approvals'
        ? t('Took back the request: {thing}', { thing: name })
        : t('Cancelled {thing}', { thing: name });
    case 'cashed':
      return t('Cashed {thing}', { thing: name });
    case 'held':
      return t('Put {thing} back as held', { thing: name });
    case 'requested':
      return t('Asked for approval: {thing}', { thing: name });
    case 'approved':
      return t('Approved {thing}', { thing: name });
    case 'rejected':
      return t('Turned down {thing}', { thing: name });
    case 'applied':
      return t('Carried out {thing}', { thing: name });
    case 'paid':
      return t('Marked {thing} as paid', { thing: name });
    default:
      return t('Changed {thing}', { thing: name });
  }
}

/** The customer and the amount of a change about a document, payment or cheque. */
function detailText(event: ChangeEvent, format?: ChangeFormat): string {
  if (event.private || event.count > 1) return '';
  const s = event.summary;
  const client = (currentLanguage() === 'ar' && str(s.clientAr)) || str(s.client);
  const amount =
    typeof s.total === 'number' ? s.total : typeof s.amount === 'number' ? s.amount : null;
  const currency = str(s.currency);
  const money =
    amount !== null && currency
      ? format
        ? format.money(amount, currency)
        : `${amount} ${currency}`
      : '';
  return [client, money].filter(Boolean).join(' · ');
}

/**
 * An expiry reminder of the morning alerts in Updates (#18): what is due, by
 * nobody. Employees' papers and confidential ones say whose they are only
 * through their link.
 */
function expiryText(event: ChangeEvent, format?: ChangeFormat): string {
  const s = event.summary;
  const type = t(documentTypeInfo(str(s.type)).label);
  const title = str(s.title);
  const name = str(s.name);
  const paper = event.private
    ? s.employee === true
      ? t('An employee’s {document}', { document: lower(type) })
      : t('A confidential document')
    : joined(title || type, name ? `· ${name}` : '');
  const rawDate = str(s.date);
  const date = rawDate && format ? format.date(rawDate) : rawDate;
  switch (s.what) {
    case 'expired':
      return t('{document} expired on {date}', { document: paper, date });
    case 'noscan':
      return t('{document}: the new copy is not uploaded yet', { document: paper });
    default:
      return t('{document} expires on {date}', { document: paper, date });
  }
}

/**
 * Who receives items issued, and what, from a change's summary (see
 * issue_summary): "1 Trouser, 2 T-shirts" and "Mohammed Ahmed (Security
 * Guard)".
 */
function issuedItems(s: Record<string, unknown>): { items: string; name: string } {
  const ar = currentLanguage() === 'ar';
  const items = (Array.isArray(s.items) ? (s.items as Record<string, unknown>[]) : [])
    .map((i) => joined(String(i?.quantity ?? ''), (ar && str(i?.nameAr)) || str(i?.name)))
    .filter(Boolean)
    .join(ar ? '، ' : ', ');
  const person = (ar && str(s.nameAr)) || str(s.name);
  const title = (ar && str(s.jobTitleAr)) || str(s.jobTitle);
  return { items, name: title ? `${person} (${title})` : person };
}

/** Items issued to an employee, asked for or kept, in words; null for any other change. */
function issueText(event: ChangeEvent): string | null {
  const s = event.summary;
  const asked = event.tbl === 'approvals' && str(s.request) === 'stock_issue';
  if (event.private || event.count > 1 || !(asked || event.tbl === 'stockIssues')) return null;
  const { items, name } = issuedItems(s);
  if (!name || !items) return null;
  switch (str(s.what)) {
    case 'requested':
      return t('Issued {items} to {name}, waiting for approval', { items, name });
    case 'approved':
    case 'applied':
      return t('Confirmed the items issued to {name}: {items}', { items, name });
    case 'rejected':
      return t('Turned down the items to issue to {name}: {items}', { items, name });
    case 'cancelled':
      return t('Took back the items to issue to {name}: {items}', { items, name });
    case 'added':
      return t('Recorded {items} issued to {name}', { items, name });
    default:
      return null;
  }
}

/** A change in words, in the interface language. */
export function describeChange(event: ChangeEvent, format?: ChangeFormat): ChangeLine {
  const actor = event.actorName.trim() || t('Someone in the team');
  if (event.kind === 'document_expiry') {
    return {
      actor,
      text: expiryText(event, format),
      detail: '',
      important: event.important,
      // Nobody did it: it reads without anyone before it.
      named: true,
    };
  }
  let text: string;
  if (event.kind === 'member') text = teamText(event);
  else if (event.count > 1) text = foldText(event);
  else if (event.tbl === 'companies') text = settingsText(event, format);
  else text = issueText(event) ?? actionText(event, str(event.summary.what), thing(event));
  return {
    actor,
    text,
    detail: detailText(event, format),
    important: event.important,
    ...(event.kind === 'member' && namedInText(event) ? { named: true } : {}),
  };
}

/** One person's changes, for an email: the important ones each, the rest counted by kind. */
export interface ChangeGroup {
  actor: string;
  important: ChangeEvent[];
  others: { kind: string; count: number }[];
  total: number;
}

/** Changes grouped by who made them, in the order of their first change. */
export function groupChanges(events: ChangeEvent[]): ChangeGroup[] {
  const groups = new Map<string, ChangeGroup>();
  for (const event of [...events].sort((a, b) => a.id - b.id)) {
    const key = event.actor ?? '';
    let group = groups.get(key);
    if (!group) {
      group = {
        actor: event.actorName.trim() || t('Someone in the team'),
        important: [],
        others: [],
        total: 0,
      };
      groups.set(key, group);
    }
    group.total += event.count;
    if (event.important) {
      group.important.push(event);
      continue;
    }
    const other = group.others.find((o) => o.kind === event.kind);
    if (other) other.count += event.count;
    else group.others.push({ kind: event.kind, count: event.count });
  }
  return [...groups.values()];
}

/* -------------------------------------------------------------------------- */
/* When to email (the email-alerts function's "notify")                       */
/* -------------------------------------------------------------------------- */

/** Emails per person and company a day (Kuwait time), important ones and summaries together. */
export const MAX_CHANGE_EMAILS_A_DAY = 20;
/** At most one email every this many minutes; what comes meanwhile waits for the next. */
export const MIN_MINUTES_BETWEEN_EMAILS = 15;
/** The summary of everything else goes out from this hour, Kuwait time. */
export const SUMMARY_HOUR = 8;

/** What the function keeps for a person (public.notification_settings). */
export interface NotifyState {
  immediateKinds: readonly string[];
  digest: 'daily' | 'off';
  /** The last day the summary was looked at. */
  digestOn: string | null;
  /** The day emails were last counted for, and how many went that day. */
  sentOn: string | null;
  sentCount: number;
  /** When the last email went (ms since 1970); null before the first. */
  lastSentMs: number | null;
}

export type ChangeEmailKind = 'immediate' | 'daily';

export interface NotifyDecision {
  /** The email to send now with every change waiting, or none. */
  send: ChangeEmailKind | null;
  /** The summary is off and nothing important waits: the rest is let go (it stays in the bell). */
  letGo: boolean;
  /** Today's summary is done with (sent, nothing to send, or let go). */
  summaryDone: boolean;
}

/**
 * Whether to email the changes waiting for someone now: important changes
 * of the kinds they chose at once, everything else in the morning summary,
 * within the caps (one email every 15 minutes, 20 a day). `clock` is Kuwait's.
 */
export function notifyDecision(
  waiting: readonly Pick<ChangeEvent, 'important' | 'kind'>[],
  state: NotifyState,
  clock: { date: string; hour: number },
  nowMs: number,
): NotifyDecision {
  const sentToday = state.sentOn === clock.date ? state.sentCount : 0;
  const capOk =
    sentToday < MAX_CHANGE_EMAILS_A_DAY &&
    (state.lastSentMs === null || nowMs - state.lastSentMs >= MIN_MINUTES_BETWEEN_EMAILS * 60_000);
  const urgent = waiting.some((e) => e.important && state.immediateKinds.includes(e.kind));
  const morning = clock.hour >= SUMMARY_HOUR && state.digestOn !== clock.date;
  if (urgent) {
    return { send: capOk ? 'immediate' : null, letGo: false, summaryDone: false };
  }
  if (!morning) return { send: null, letGo: false, summaryDone: false };
  if (state.digest === 'off') return { send: null, letGo: waiting.length > 0, summaryDone: true };
  if (!waiting.length) return { send: null, letGo: false, summaryDone: true };
  return capOk
    ? { send: 'daily', letGo: false, summaryDone: true }
    : { send: null, letGo: false, summaryDone: false };
}
