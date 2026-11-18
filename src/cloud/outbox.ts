import Dexie, {
  type DBCore,
  type DBCoreMutateRequest,
  type DBCoreMutateResponse,
  type DBCoreTable,
  type DBCoreTransaction,
  type Middleware,
} from 'dexie';
import { t } from '@/i18n';
import { shortId } from '@/lib/ids';
import {
  aiSwitchChanged,
  approvalRulesChanged,
  approvalRulesOf,
  appLimit,
  ATTACHMENT_OWNER_TABLES,
  canPostPayroll,
  canWriteRecord,
  companyBooksChanged,
  hasLimits,
  chequeChangeNeedsApprover,
  deleteKeptBy,
  documentChangeNeedsApproval,
  guardApprovalWrite,
  isApprover,
  isPayrollApproval,
  issuesLetters,
  issuesWithoutNumber,
  letterKept,
  letterWriteRefusal,
  lettersSwitchedOn,
  limitBlocksWrite,
  paymentLinkNeedsApprover,
  payrollDecisionRefusal,
  rulesCoverPayroll,
  sameData,
  peopleSettingsKept,
  staffCompanyChangeOk,
  switchesAi,
  switchesLetters,
  type RecordLookup,
  warehouseWriteRefusal,
} from './roles';
import { linkHasFeature } from './features';
import type { CloudLink, OutboxEntry } from './types';

/**
 * Change capture. Every write to a synced table of a company kept in the
 * cloud also writes an outbox entry, in the same IndexedDB transaction, so a
 * change can't be saved without being queued for the server (and a failed
 * write queues nothing). Writes that bring changes from the server are tagged
 * with `markRemote()` and are not sent back. Saving something unchanged queues
 * nothing.
 *
 * The capture also refuses, before anything is written, changes the person's
 * role does not allow (viewers change nothing; staff stay out of accounting
 * setup and payroll), the owner's limits on them (an app made view only) or
 * the company's approval rules (an issued invoice only an approver may
 * change, a cheque only an approver may record), with a message they can
 * act on. The server enforces the same rules on its own.
 */

export class CloudPermissionError extends Error {
  constructor(
    message: string,
    readonly companyId: string,
  ) {
    super(message);
    this.name = 'CloudPermissionError';
  }
}

const remote = new WeakSet<object>();
const linkCache = new WeakMap<object, Map<string, CloudLink | null>>();
/** The group of the changes of each transaction (OutboxEntry.group). */
const groups = new WeakMap<object, string>();

function groupOf(trans: object): string {
  let group = groups.get(trans);
  if (!group) groups.set(trans, (group = shortId()));
  return group;
}
const notified = new WeakSet<object>();

/** Marks the running transaction as applying the server's changes: they are not queued. */
export function markRemote(): void {
  const tx = Dexie.currentTransaction;
  if (!tx) throw new Error('markRemote() needs a transaction');
  remote.add(tx.idbtrans);
}

type Listener = (companyIds: string[]) => void;
const listeners = new Set<Listener>();

/** Called after a transaction that queued changes has been saved. */
export function onLocalChange(listener: Listener): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

function notifyOnCommit(trans: DBCoreTransaction, companyIds: Set<string>) {
  const native = trans as unknown as IDBTransaction;
  const pending = ((native as unknown as { _almailCompanies?: Set<string> })._almailCompanies ??=
    new Set());
  for (const id of companyIds) pending.add(id);
  if (notified.has(native) || typeof native.addEventListener !== 'function') return;
  notified.add(native);
  native.addEventListener('complete', () => {
    const ids = [...pending];
    for (const listener of listeners) {
      try {
        listener(ids);
      } catch {
        // A listener's problem must not affect saving.
      }
    }
  });
}

interface Change {
  key: unknown;
  before: Record<string, unknown> | undefined;
  after: Record<string, unknown> | undefined;
  companyId: string | null;
}

function companyOf(table: string, change: Omit<Change, 'companyId'>): string | null {
  if (table === 'companies') return typeof change.key === 'string' ? change.key : null;
  const row = change.after ?? change.before;
  return typeof row?.companyId === 'string' ? row.companyId : null;
}

async function linksFor(
  down: DBCore,
  trans: DBCoreTransaction,
  companyIds: (string | null)[],
): Promise<Map<string, CloudLink | null>> {
  let cache = linkCache.get(trans);
  if (!cache) {
    cache = new Map();
    linkCache.set(trans, cache);
  }
  const missing = [...new Set(companyIds.filter((id): id is string => !!id && !cache.has(id)))];
  if (missing.length) {
    const rows = (await down.table('syncState').getMany({ trans, keys: missing })) as (
      CloudLink | undefined
    )[];
    missing.forEach((id, i) => cache.set(id, rows[i] ?? null));
  }
  return cache;
}

/** Tables whose changes the company's approval rules decide on (see refuseByRules). */
const RULED = new Set(['documents', 'approvals', 'payments', 'securityCheques']);

/** Tables whose changes the sub-warehouses decide on (see refuseWarehouses). */
const WAREHOUSE_RULED = new Set([
  'warehouses',
  'stockEntries',
  'stockIssues',
  'documents',
  'approvals',
]);

/**
 * The warehouses the records being written name, as stored in this
 * transaction: whether they are sub-warehouses, and who looks after them,
 * decides who may write them (see refuseWarehouses).
 */
async function warehousesFor(
  down: DBCore,
  trans: DBCoreTransaction,
  changes: Change[],
): Promise<Map<string, Record<string, unknown>>> {
  const named = (row: Record<string, unknown> | undefined): unknown[] => {
    if (!row) return [];
    const items = Array.isArray(row.items) ? (row.items as Record<string, unknown>[]) : [];
    const asked = (row.after ?? null) as Record<string, unknown> | null;
    return [
      row.warehouseId,
      row.toWarehouseId,
      asked?.warehouseId,
      ...items.map((i) => i?.warehouseId),
    ];
  };
  const ids = [
    ...new Set(
      changes
        .flatMap((c) => [...named(c.before), ...named(c.after)])
        .filter((id): id is string => typeof id === 'string' && id !== ''),
    ),
  ];
  const found = new Map<string, Record<string, unknown>>();
  if (ids.length === 0 || !down.schema.tables.some((t) => t.name === 'warehouses')) return found;
  const rows = (await down.table('warehouses').getMany({ trans, keys: ids })) as (
    Record<string, unknown> | undefined
  )[];
  ids.forEach((id, i) => {
    if (rows[i]) found.set(id, rows[i]!);
  });
  return found;
}

/**
 * Sub-warehouses and items issued, as records_guard and can_delete_record
 * of 20261210000000_warehouse_issues.sql once the company's server has
 * them: sub-warehouses (and their keepers) are set up, and their stock
 * changed directly, by the owner, an admin or an accountant; items issued
 * are written by approvers only and never deleted; a request to issue items
 * comes from whoever may issue from the warehouse.
 */
function refuseWarehouses(
  link: CloudLink,
  table: string,
  change: Change,
  warehouses: Map<string, Record<string, unknown>> | undefined,
): string | null {
  if (!WAREHOUSE_RULED.has(table) || !linkHasFeature(link, 'stock_issues')) return null;
  if (table === 'stockIssues' && change.after === undefined) {
    return t('Items issued are voided, never deleted.');
  }
  const refusal = warehouseWriteRefusal(
    { role: link.role, userId: link.userId, approver: isApprover(link.role, link.approver) },
    table,
    change.before,
    change.after,
    (id) => warehouses?.get(id),
  );
  if (refusal === 'approver') {
    return t('Only an approver records items issued. Send them for approval instead.');
  }
  if (refusal === 'keeper') {
    return t('You can only issue items from the sub-warehouse you look after.');
  }
  return refusal === 'manager'
    ? t(
        'Only the owner, an admin or an accountant sets up sub-warehouses or changes their stock directly.',
      )
    : null;
}

/**
 * The records the files being written are kept with, as stored in this
 * transaction (the owner's limits follow them: see recordApp).
 */
async function ownersFor(
  down: DBCore,
  trans: DBCoreTransaction,
  changes: Change[],
): Promise<RecordLookup> {
  const ids = [
    ...new Set(
      changes
        .flatMap((c) => [c.before?.ownerId, c.after?.ownerId])
        .filter((id): id is string => typeof id === 'string' && id !== ''),
    ),
  ];
  const tables = ATTACHMENT_OWNER_TABLES.filter((name) =>
    down.schema.tables.some((t) => t.name === name),
  );
  const found = new Map<string, Record<string, unknown>>();
  if (ids.length) {
    const rows = await Promise.all(
      tables.map(
        (name) =>
          down.table(name).getMany({ trans, keys: ids }) as Promise<
            (Record<string, unknown> | undefined)[]
          >,
      ),
    );
    tables.forEach((name, i) =>
      rows[i].forEach((row, j) => {
        if (row) found.set(`${name} ${ids[j]}`, row);
      }),
    );
  }
  return (table, id) => found.get(`${table} ${id}`) ?? null;
}

/**
 * The pay runs requests for their approval being written are about, as
 * stored in this transaction (the cloud approves a pay run only as it was
 * sent: see payrollDecisionRefusal).
 */
async function payRunsFor(
  down: DBCore,
  trans: DBCoreTransaction,
  changes: Change[],
): Promise<Map<string, Record<string, unknown>>> {
  const ids = [
    ...new Set(
      changes
        .map((c) => c.before ?? c.after)
        .filter((row) => isPayrollApproval(row) && typeof row?.subjectId === 'string')
        .map((row) => row!.subjectId as string),
    ),
  ];
  const found = new Map<string, Record<string, unknown>>();
  if (ids.length === 0 || !down.schema.tables.some((t) => t.name === 'payRuns')) return found;
  const rows = (await down.table('payRuns').getMany({ trans, keys: ids })) as (
    Record<string, unknown> | undefined
  )[];
  ids.forEach((id, i) => {
    if (rows[i]) found.set(id, rows[i]!);
  });
  return found;
}

/**
 * The People settings of these companies, as stored in this transaction:
 * whether their letters are on decides who may write a letter (#19).
 */
async function peopleSettingsFor(
  down: DBCore,
  trans: DBCoreTransaction,
  companyIds: (string | null)[],
): Promise<Map<string, Record<string, unknown> | null>> {
  const ids = [...new Set(companyIds.filter((id): id is string => !!id))];
  const found = new Map<string, Record<string, unknown> | null>();
  if (ids.length === 0 || !down.schema.tables.some((t) => t.name === 'peopleSettings')) {
    return found;
  }
  const rows = (await down.table('peopleSettings').getMany({ trans, keys: ids })) as (
    Record<string, unknown> | undefined
  )[];
  ids.forEach((id, i) => found.set(id, rows[i] ?? null));
  return found;
}

/**
 * Employee letters (#19), as records_guard and can_delete_record of
 * 20261130000000_people_alerts.sql once the company's server has them: only
 * the owner or an admin turns the letters switch on or off (the cloud keeps
 * it for anyone else's copy); with letters on, a letter issued or void never
 * goes back to a draft nor is deleted, and only someone who issues letters
 * issues one, or changes or voids one that is issued.
 */
function refuseLetters(
  link: CloudLink,
  table: string,
  change: Change,
  settings: Record<string, unknown> | null | undefined,
): string | null {
  if (!linkHasFeature(link, 'employee_letters')) return null;
  if (table === 'peopleSettings') {
    if (change.after === undefined) {
      // Deleting the settings would turn the letters off.
      return change.before && peopleSettingsKept(link.role, change.before)
        ? t('Only the owner or an admin turns employee letters on or off.')
        : null;
    }
    return !switchesLetters(link.role) && !sameData(change.before?.letters, change.after.letters)
      ? t('Only the owner or an admin turns employee letters on or off.')
      : null;
  }
  if (table !== 'employeeLetters' || !lettersSwitchedOn(settings)) return null;
  if (!change.after) {
    return change.before && letterKept(change.before)
      ? t('Issued letters are kept, so their numbers stay used. Void it instead.')
      : null;
  }
  const refusal = letterWriteRefusal(
    change.before,
    change.after,
    issuesLetters(link.role, link.approver),
  );
  if (refusal === 'issued') return t('This letter is already issued, so it stays issued.');
  return refusal === 'issuer'
    ? t('Only the owner, an admin or an approver issues letters. Ask for approval instead.')
    : null;
}

/** The company records of these companies, as stored in this transaction. */
async function companiesFor(
  down: DBCore,
  trans: DBCoreTransaction,
  companyIds: string[],
): Promise<Map<string, Record<string, unknown> | null>> {
  const ids = [...new Set(companyIds)];
  const found = new Map<string, Record<string, unknown> | null>();
  if (ids.length === 0) return found;
  const rows = (await down.table('companies').getMany({ trans, keys: ids })) as (
    Record<string, unknown> | undefined
  )[];
  ids.forEach((id, i) => found.set(id, rows[i] ?? null));
  return found;
}

/**
 * The company's approval rules, as the server applies them (records_guard,
 * can_delete_record). `company` is the company's record as stored here; its
 * rules are null while never turned on. Approval requests are kept honest,
 * and invoices numbered when they are issued are never issued without a
 * number, whether or not the rules are on. The AI assistant's switch on the
 * company record is the owner's and the admins' (records_guard of
 * 20261208000000_ai_assistant.sql keeps it for anyone else's copy; refused
 * here whether or not the server has it, so the app works the same).
 */
function refuseByRules(
  link: CloudLink,
  table: string,
  change: Change,
  company: Record<string, unknown> | null | undefined,
  runs?: Map<string, Record<string, unknown>>,
): string | null {
  if (table === 'companies') {
    if (change.after === undefined) return null;
    if (link.role !== 'owner' && approvalRulesChanged(change.before, change.after)) {
      return t('Only the owner changes the approval rules.');
    }
    return !switchesAi(link.role) && aiSwitchChanged(change.before, change.after)
      ? t('Only the owner or an admin turns the AI assistant on or off.')
      : null;
  }
  const rules = approvalRulesOf(company);
  const approver = isApprover(link.role, link.approver);
  if (!change.after) {
    if (!change.before) return null;
    const kept = deleteKeptBy(rules, table, change.before, approver);
    if (kept === 'request') {
      return t('Approval requests are kept as the record of who asked and who decided.');
    }
    if (kept === 'void') {
      return t('Issued documents are voided, never deleted, so their numbers stay used.');
    }
    if (kept === 'approver') {
      return t(
        'This document is issued, so only an approver can delete it. Ask for a void instead.',
      );
    }
  }
  if (table === 'documents' && issuesWithoutNumber(company, change.before, change.after)) {
    return t('This invoice has no number yet. Issue it again to give it one.');
  }
  if (table === 'approvals' && change.after) {
    // Salary approval (#10), once the company's server has it.
    const payroll = {
      on: rulesCoverPayroll(rules) && linkHasFeature(link, 'payroll_approvals'),
      poster: canPostPayroll(link.role, link.permissions),
    };
    const write = guardApprovalWrite(
      change.before,
      change.after,
      {
        userId: link.userId,
        approver,
        owner: link.role === 'owner',
        now: new Date().toISOString(),
      },
      payroll,
    );
    if ('refused' in write) return t('Only an approver decides approval requests.');
    if (!payroll.on || !isPayrollApproval(change.before ?? change.after)) return null;
    const subject = (change.before ?? change.after)?.subjectId;
    const refusal = payrollDecisionRefusal(
      change.before,
      change.after,
      {
        userId: link.userId,
        owner: link.role === 'owner',
        peopleShut: appLimit(link.role, link.permissions, 'people') === 'none',
      },
      typeof subject === 'string' ? runs?.get(subject) : undefined,
    );
    if (refusal === 'people') {
      return t('The owner has given you no access to Maham People, so you don’t decide pay runs.');
    }
    if (refusal === 'self') {
      return t('Only the owner approves a pay run they sent for approval themselves.');
    }
    return refusal === 'stale'
      ? t(
          'This pay run changed after it was sent for approval. Reject this request; it can be sent again.',
        )
      : null;
  }
  if (!rules) return null;
  if (table === 'payments' || table === 'securityCheques') {
    // A cheque the rules keep for approvers: recorded, changed or deleted by them only.
    return !approver && chequeChangeNeedsApprover(rules, table, change.before, change.after)
      ? t('This cheque needs confirmation. Send it for confirmation instead.')
      : null;
  }
  if (table === 'documents' && change.after) {
    if (approver) return null;
    if (documentChangeNeedsApproval(rules, change.before, change.after)) {
      return t('This change needs approval. Send it for approval instead.');
    }
    return paymentLinkNeedsApprover(rules, change.before, change.after)
      ? t(
          'Only an approver can change or remove the payment link of an issued invoice. You can add one where there is none.',
        )
      : null;
  }
  return null;
}

function refuse(
  link: CloudLink,
  table: string,
  change: Change,
  company: Record<string, unknown> | null | undefined,
  lookup: RecordLookup | undefined,
  runs?: Map<string, Record<string, unknown>>,
  settings?: Record<string, unknown> | null,
  warehouses?: Map<string, Record<string, unknown>>,
): string | null {
  return (
    refuseByRole(link, table, change, lookup) ??
    refuseLetters(link, table, change, settings) ??
    refuseWarehouses(link, table, change, warehouses) ??
    refuseByRules(link, table, change, company, runs)
  );
}

function refuseByRole(
  link: CloudLink,
  table: string,
  change: Change,
  lookup: RecordLookup | undefined,
): string | null {
  if (link.status === 'removed') {
    return t(
      'This company is no longer shared with you. Keep it as a company on this device or remove it.',
    );
  }
  if (link.role === 'viewer') return t('You can view this company but not change it.');
  // The owner's limits on this person, as the server applies them: a file
  // is of the app of the record it is kept with, and the books' settings on
  // the company record are Maham Books'.
  const limited = (row: Record<string, unknown> | undefined) =>
    row !== undefined && limitBlocksWrite(link.role, link.permissions, table, row, lookup);
  const booksLimit = appLimit(link.role, link.permissions, 'books');
  if (
    limited(change.before) ||
    limited(change.after) ||
    (table === 'companies' &&
      (booksLimit === 'view' || booksLimit === 'none') &&
      companyBooksChanged(change.before, change.after))
  ) {
    return t(
      'The owner has made this app view only for you. Ask the owner if you need to change it.',
    );
  }
  if (link.role !== 'staff') return null;
  const denied = t('Your role can’t make this change. Ask an owner, admin or accountant.');
  if (table === 'companies') {
    if (!change.after) return denied;
    return change.before && staffCompanyChangeOk(change.before, change.after) ? null : denied;
  }
  if (change.before && !canWriteRecord('staff', table, change.before)) return denied;
  if (change.after && !canWriteRecord('staff', table, change.after)) return denied;
  return null;
}

async function capture(
  down: DBCore,
  table: DBCoreTable,
  name: string,
  req: DBCoreMutateRequest,
): Promise<DBCoreMutateResponse> {
  const { trans } = req;
  if (remote.has(trans)) return table.mutate(req);
  const primaryKey = table.schema.primaryKey;
  const keyOf = (value: unknown) => primaryKey.extractKey!(value);

  let keys: unknown[];
  let before: (Record<string, unknown> | undefined)[];
  let after: (Record<string, unknown> | undefined)[];
  if (req.type === 'add' || req.type === 'put') {
    after = req.values as Record<string, unknown>[];
    keys = req.keys ?? after.map(keyOf);
    before = await table.getMany({ trans, keys });
  } else if (req.type === 'delete') {
    keys = req.keys;
    before = await table.getMany({ trans, keys });
    after = keys.map(() => undefined);
  } else {
    const found = await table.query({
      trans,
      values: true,
      query: { index: primaryKey, range: req.range },
    });
    before = found.result as Record<string, unknown>[];
    keys = before.map(keyOf);
    after = keys.map(() => undefined);
  }

  const changes: Change[] = keys.map((key, i) => {
    const change = { key, before: before[i], after: after[i] };
    return { ...change, companyId: companyOf(name, change) };
  });
  const companyIds = changes.map((c) => c.companyId);
  const linked = linksFor(down, trans, companyIds);
  // All at once: Dexie keeps its transaction across only so many waits.
  const [links, companies, owners, runs, settings, warehouses] = await Promise.all([
    linked,
    RULED.has(name) && down.schema.tables.some((t) => t.name === 'companies')
      ? companiesFor(
          down,
          trans,
          companyIds.filter((id): id is string => !!id),
        )
      : null,
    // The records files are kept with, looked up only for someone the owner
    // limited: never for a company kept on this device, nor for anyone else.
    name === 'attachments'
      ? linked.then((found) => {
          const limited = changes.filter((change) => {
            const link = change.companyId ? found.get(change.companyId) : null;
            return !!link && hasLimits(link.role, link.permissions);
          });
          return limited.length ? ownersFor(down, trans, limited) : undefined;
        })
      : undefined,
    // The pay runs of requests for their approval (#10).
    name === 'approvals' ? payRunsFor(down, trans, changes) : undefined,
    // Whether the companies' letters are on (#19).
    name === 'employeeLetters' ? peopleSettingsFor(down, trans, companyIds) : undefined,
    // The warehouses the records name: sub-warehouses and their keepers.
    WAREHOUSE_RULED.has(name) ? warehousesFor(down, trans, changes) : undefined,
  ]);
  for (const change of changes) {
    const link = change.companyId ? links.get(change.companyId) : null;
    if (!link) continue;
    const lookup = owners && hasLimits(link.role, link.permissions) ? owners : undefined;
    const reason = refuse(
      link,
      name,
      change,
      companies?.get(link.companyId),
      lookup,
      runs,
      settings?.get(link.companyId),
      warehouses,
    );
    if (reason) throw new CloudPermissionError(reason, link.companyId);
  }

  const result = await table.mutate(req);

  const at = new Date().toISOString();
  const group = groupOf(trans);
  const entries: OutboxEntry[] = [];
  changes.forEach((change, i) => {
    if (result.failures[i] || !change.companyId || !links.get(change.companyId)) return;
    if (change.after === undefined && change.before === undefined) return;
    if (change.after !== undefined && sameData(change.before, change.after)) return;
    entries.push({
      companyId: change.companyId,
      table: name,
      id: String(change.key),
      op: change.after === undefined ? 'delete' : 'put',
      at,
      parked: 0,
      group,
    });
  });
  if (entries.length) {
    await down.table('outbox').mutate({ type: 'add', trans, values: entries });
    notifyOnCommit(trans, new Set(entries.map((e) => e.companyId)));
  }
  return result;
}

/**
 * The middleware for the app's database. `tables` are the synced tables; the
 * database must have `outbox` and `syncState` tables.
 */
export function outboxMiddleware(tables: readonly string[]): Middleware<DBCore> {
  const synced = new Set(tables);
  return {
    stack: 'dbcore',
    name: 'MahamBooksOutbox',
    // Above Dexie's own middleware, so it sees the same transaction objects as Dexie.
    level: 20,
    create(down) {
      const enabled = down.schema.tables.some((t) => t.name === 'outbox');
      if (!enabled) return {};
      const withCompanies = down.schema.tables.some((t) => t.name === 'companies');
      const withPayRuns = down.schema.tables.some((t) => t.name === 'payRuns');
      const withPeopleSettings = down.schema.tables.some((t) => t.name === 'peopleSettings');
      const withWarehouses = down.schema.tables.some((t) => t.name === 'warehouses');
      // The records files are kept with, for the owner's limits (see ownersFor).
      const owners = ATTACHMENT_OWNER_TABLES.filter((name) =>
        down.schema.tables.some((t) => t.name === name),
      );
      return {
        transaction(stores, mode, options) {
          if (mode === 'readwrite' && stores.some((s) => synced.has(s))) {
            // The company record too where its approval rules decide on a change.
            const wanted =
              stores.some((s) => RULED.has(s)) && withCompanies
                ? ['outbox', 'syncState', 'companies']
                : ['outbox', 'syncState'];
            if (stores.includes('attachments')) wanted.push(...owners);
            // Requests for a pay run's approval are judged with the pay run.
            if (stores.includes('approvals') && withPayRuns) wanted.push('payRuns');
            // Letters are judged with the company's letters switch (#19).
            if (stores.includes('employeeLetters') && withPeopleSettings) {
              wanted.push('peopleSettings');
            }
            // Stock and documents are judged with the warehouses they name.
            if (stores.some((s) => WAREHOUSE_RULED.has(s)) && withWarehouses) {
              wanted.push('warehouses');
            }
            const extra = wanted.filter((s) => !stores.includes(s));
            return down.transaction([...stores, ...extra], mode, options);
          }
          return down.transaction(stores, mode, options);
        },
        table(name) {
          const table = down.table(name);
          if (name === 'syncState') {
            // A link changed in this transaction: look it up again.
            return {
              ...table,
              mutate: (req) => {
                linkCache.delete(req.trans);
                return table.mutate(req);
              },
            };
          }
          if (!synced.has(name)) return table;
          return { ...table, mutate: (req) => capture(down, table, name, req) };
        },
      };
    },
  };
}
