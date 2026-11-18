import {
  chequeContent,
  documentStage,
  invoiceContent,
  sameData,
  securityChequeContent,
} from './roles';

/**
 * The change feed of 20261123000000_change_feed.sql, as the app's test
 * clouds keep it: what kind of change a record makes and what it did, the
 * same as almailbooks.change_kind and almailbooks.change_details. The SQL
 * tests check the two give the same answers.
 */

/** The kinds of change (public.change_events.kind); team changes are 'member'. */
export const CHANGE_KINDS = [
  'document',
  'payment',
  'cheque',
  'approval',
  'settings',
  'member',
  'people',
  'compliance',
  'contact',
  'item',
  'expense',
  'accounting',
  'file',
] as const;
export type ChangeKind = (typeof CHANGE_KINDS)[number];

/** The kinds that have important changes: the ones that may be emailed at once. */
export const IMMEDIATE_KINDS = [
  'document',
  'cheque',
  'approval',
  'member',
  'settings',
  'people',
] as const;
export type ImmediateKind = (typeof IMMEDIATE_KINDS)[number];

export function isImmediateKind(value: unknown): value is ImmediateKind {
  return (IMMEDIATE_KINDS as readonly unknown[]).includes(value);
}

/** The daily summary of everything else: at 8:00 Kuwait time, or none. */
export type ChangeDigest = 'daily' | 'off';

type Row = Record<string, unknown>;

const PEOPLE = new Set([
  'employees',
  'payRuns',
  'payrollSettings',
  'peopleSettings',
  'leaveRecords',
  'staffLoans',
  'finalSettlements',
  'letterTemplates',
  'employeeLetters',
  // Since 20261207000000_staffing_costings.sql.
  'staffingCostings',
]);
const COMPLIANCE = new Set(['complianceDocuments', 'renewals', 'complianceMarks', 'vehicles']);
const ITEMS = new Set([
  'products',
  'warehouses',
  'stockMovements',
  'stockEntries',
  'landedCosts',
  // Since 20261210000000_warehouse_issues.sql.
  'stockIssues',
]);

/** The kind of change a record makes, as almailbooks.change_kind. */
export function changeKind(table: string, data: Row | null | undefined): ChangeKind {
  if (table === 'documents') return 'document';
  if (table === 'payments') return data?.method === 'cheque' ? 'cheque' : 'payment';
  if (table === 'securityCheques') return 'cheque';
  if (table === 'approvals') return 'approval';
  if (table === 'companies') return 'settings';
  if (PEOPLE.has(table)) return 'people';
  if (COMPLIANCE.has(table)) return 'compliance';
  if (table === 'clients') return 'contact';
  if (ITEMS.has(table)) return 'item';
  if (table === 'expenses') return 'expense';
  if (table === 'attachments') return 'file';
  return 'accounting';
}

/** JSON's ->> : a text, or null. */
function text(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  return typeof value === 'object' ? JSON.stringify(value) : String(value);
}

const num = (value: unknown) => (typeof value === 'number' ? value : null);
const obj = (value: unknown): Row | null =>
  value && typeof value === 'object' && !Array.isArray(value) ? (value as Row) : null;

/** Without the null fields, as jsonb_strip_nulls (one level is enough here). */
function strip(row: Row): Row {
  return Object.fromEntries(
    Object.entries(row).filter(([, value]) => value !== null && value !== undefined),
  );
}

/** A non-empty text, as nullif(…, ''). */
const filled = (value: unknown) => {
  const found = text(value);
  return found === '' ? null : found;
};

/**
 * Who receives items issued, and what, as almailbooks.issue_summary: the
 * employee's name and job title, and each line's quantity and item.
 */
export function issueSummary(issue: Row | null): Row {
  const recipient = obj(issue?.recipient);
  const lines = Array.isArray(issue?.lines) ? (issue!.lines as unknown[]) : [];
  return strip({
    name: filled(recipient?.name),
    nameAr: filled(recipient?.nameAr),
    jobTitle: filled(recipient?.jobTitle),
    jobTitleAr: filled(recipient?.jobTitleAr),
    items: lines.length
      ? lines.map((line) => {
          const l = obj(line);
          return strip({
            quantity: num(l?.quantity),
            name: filled(l?.name),
            nameAr: filled(l?.nameAr),
          });
        })
      : null,
  });
}

function without(row: Row | null, ...keys: string[]): Row | null {
  if (!row) return row;
  const copy = { ...row };
  for (const key of keys) delete copy[key];
  return copy;
}

/** Whether two numbering settings differ only in their counters, as almailbooks.counters_only. */
export function countersOnly(before: unknown, after: unknown): boolean {
  const old = obj(before);
  const next = obj(after);
  if (!old || !next) return sameData(before ?? null, after ?? null);
  return Object.keys(old).every(
    (key) =>
      !(key in next) ||
      sameData(without(obj(old[key]), 'next', 'period'), without(obj(next[key]), 'next', 'period')),
  );
}

export interface ChangeDetails {
  important: boolean;
  /** What changed, in a few fields; "what" says what happened. */
  summary: Row;
}

/** The names of the contact a document, payment or cheque is for. */
export type ContactNames = { name?: unknown; nameAr?: unknown } | null | undefined;

/**
 * What a change did and whether it is important, as
 * almailbooks.change_details; null for a change nobody needs to hear about
 * (a document counter moving on). `before` is null for a new record, `after`
 * for a deleted one. Private changes carry no names, numbers or amounts.
 */
export function changeDetails(
  table: string,
  before: Row | null,
  after: Row | null,
  isPrivate: boolean,
  contact?: ContactNames,
): ChangeDetails | null {
  const data = (after ?? before ?? {}) as Row;
  let what = !before ? 'added' : !after ? 'deleted' : 'updated';

  if (isPrivate) {
    if (table === 'approvals') {
      const was = text(before?.status) ?? 'pending';
      const now = text(after?.status) ?? 'pending';
      if (!before) what = 'requested';
      else if (after && now !== was) what = now;
      return {
        important: ['requested', 'approved', 'rejected'].includes(what),
        summary: strip({ what, request: text(data.kind), status: now }),
      };
    }
    if (table === 'payRuns') {
      const was = text(before?.status);
      const now = text(after?.status);
      if (before && after && now !== was) what = now ?? 'updated';
      const period = text(data.period);
      return {
        important: what !== 'updated' && what !== 'draft',
        summary: strip({
          what,
          status: text(data.status),
          was: what !== 'added' && what !== 'deleted' ? was : null,
          period: period && /^\d{4}-\d{2}$/.test(period) ? period : null,
        }),
      };
    }
    return { important: false, summary: { what } };
  }

  const client = ['documents', 'payments', 'securityCheques'].includes(table) ? contact : null;
  const names = { client: text(client?.name), clientAr: text(client?.nameAr) };
  let important = false;
  let summary: Row;

  switch (table) {
    case 'documents': {
      const was = before ? documentStage(before.status) : null;
      const now = after ? documentStage(after.status) : null;
      if (before && after) {
        what =
          now === 'void' && was !== 'void'
            ? 'voided'
            : was === 'void' && now !== 'void'
              ? 'restored'
              : was === 'draft' && now === 'issued'
                ? 'issued'
                : was === 'issued' &&
                    now === 'issued' &&
                    !sameData(invoiceContent(before), invoiceContent(after))
                  ? 'edited'
                  : 'updated';
      }
      important =
        (data.type === 'invoice' || data.type === 'credit') &&
        (['voided', 'restored', 'edited'].includes(what) ||
          (what === 'deleted' && was !== 'draft'));
      const totals = obj(data.totals);
      summary = {
        what,
        type: text(data.type),
        number: text(data.number),
        status: text(data.status),
        was:
          before && after && text(before.status) !== text(after.status)
            ? text(before.status)
            : null,
        total: num(totals?.total),
        currency: text(data.currency),
        ...names,
      };
      break;
    }
    case 'payments': {
      const cheque = after?.method === 'cheque' || before?.method === 'cheque';
      const was = text(obj(before?.cheque)?.status);
      const now = text(obj(after?.cheque)?.status);
      if (before && after) {
        what =
          cheque && !sameData(chequeContent(before), chequeContent(after))
            ? 'edited'
            : cheque && now !== null && now !== was
              ? now
              : after.voided === true && before.voided !== true
                ? 'voided'
                : !sameData(before.amount, after.amount) ||
                    !sameData(before.currency, after.currency) ||
                    !sameData(before.date, after.date) ||
                    !sameData(before.clientId, after.clientId)
                  ? 'edited'
                  : 'updated';
      }
      important =
        cheque && ['added', 'deleted', 'edited', 'voided', 'returned', 'cancelled'].includes(what);
      const details = obj(data.cheque);
      summary = {
        what,
        direction: text(data.direction) ?? 'in',
        method: text(data.method),
        number: text(data.number),
        amount: num(data.amount),
        currency: text(data.currency),
        cheque: text(details?.number),
        bank: text(details?.bank),
        status: text(details?.status),
        was: what === now ? was : null,
        ...names,
      };
      break;
    }
    case 'securityCheques': {
      const was = text(before?.status);
      const now = text(after?.status);
      if (before && after) {
        what = !sameData(securityChequeContent(before), securityChequeContent(after))
          ? 'edited'
          : now !== null && now !== was
            ? now
            : 'updated';
      }
      important = ['added', 'deleted', 'edited', 'cashed'].includes(what);
      summary = {
        what,
        direction: text(data.direction) ?? 'in',
        cheque: text(data.number),
        bank: text(data.bank),
        amount: num(data.amount),
        currency: text(data.currency),
        status: text(data.status),
        was: what === now ? was : null,
        ...names,
      };
      break;
    }
    case 'approvals': {
      const was = text(before?.status) ?? 'pending';
      const now = text(after?.status) ?? 'pending';
      if (!before) what = 'requested';
      else if (after && now !== was) what = now;
      important = ['requested', 'approved', 'rejected'].includes(what);
      summary = {
        what,
        request: text(data.kind),
        subject: text(data.subjectTbl),
        number: text(data.subjectNumber),
        status: now,
        // Items to issue: who receives them, and what.
        ...(data.kind === 'stock_issue' && obj(data.after) ? issueSummary(obj(data.after)) : {}),
      };
      break;
    }
    case 'companies': {
      const changes: string[] = [];
      if (before && after) {
        if (!countersOnly(before.numbering, after.numbering)) changes.push('numbering');
        const lock = (row: Row) => obj(row.accounting)?.lockDate;
        if (!sameData(lock(before), lock(after))) changes.push('lockDate');
        if (!sameData(before.approvalRules ?? null, after.approvalRules ?? null)) {
          changes.push('approvalRules');
        }
        const rest = (row: Row) =>
          without(row, 'numbering', 'updatedAt', 'approvalRules', 'accounting');
        const books = (row: Row) => {
          const accounting = obj(row.accounting);
          return accounting ? without(accounting, 'lockDate') : (row.accounting ?? null);
        };
        if (
          !changes.length &&
          sameData(rest(before), rest(after)) &&
          sameData(books(before), books(after))
        ) {
          return null;
        }
      }
      important = changes.length > 0;
      const locked = changes.includes('lockDate');
      summary = {
        what: 'settings',
        changes,
        lockDate: locked ? text(obj(after?.accounting)?.lockDate) : null,
        was: locked ? text(obj(before?.accounting)?.lockDate) : null,
      };
      break;
    }
    case 'clients':
      summary = {
        what,
        name: text(data.name),
        nameAr: text(data.nameAr),
        vendor: data.isVendor === true ? true : null,
      };
      break;
    case 'products':
      summary = { what, name: text(data.name), nameAr: text(data.nameAr), sku: text(data.sku) };
      break;
    case 'expenses':
      summary = {
        what,
        number: text(data.number),
        amount: num(data.amount),
        currency: text(data.currency),
      };
      break;
    case 'journals':
      summary = { what, number: text(data.number) };
      break;
    case 'stockIssues':
      summary = { what, number: text(data.number), ...issueSummary(data) };
      break;
    case 'vehicles':
      summary = { what, name: text(data.plate) };
      break;
    case 'complianceDocuments':
      summary = { what, name: text(data.title), type: text(data.type) };
      break;
    case 'attachments':
      summary = { what, name: text(data.name) };
      break;
    default:
      summary = { what };
  }
  return { important, summary: strip(summary) };
}
