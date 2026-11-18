import type { Table } from 'dexie';
import { db, DATA_TABLES, type DataTable } from '@/db/db';
import { forgetCloudLink } from '@/db/records';
import { logActivity } from '@/db/activity';
import type { ActivityEntity, Attachment, Company, DocumentType, ID, Payment } from '@/db/types';
import type { LostChequeLeaves } from '@/db/cheque-print';
import { lostChequeLeaves } from '@/lib/cheque-print';
import { msg, t } from '@/i18n';
import {
  CLOUD_ERROR_MESSAGES,
  cloudError,
  CloudError,
  type CloudApi,
  type CompanyOp,
  type MyPermissions,
  type PulledRow,
  type PushChange,
  type PushResult,
  type RecordKey,
} from './api';
import { companyOps, onlyCounters, rebaseCompany } from './company-patch';
import { linkHasFeature } from './features';
import { blobToDataUrl, contentHash, dataUrlToBlob, filePath } from './files';
import { companySettingLabels, inArabic } from './labels';
import { syncStarted, withSyncLock } from './lock';
import { markRemote } from './outbox';
import { mergeNumbering } from './numbering';
import {
  canEdit,
  canSeePeople,
  isPrivateRecord,
  limitBlocksWrite,
  PEOPLE_TABLES,
  renewedDocumentId,
  sameData,
  type MemberRole,
} from './roles';
import type { CloudLink, FileTask, OutboxEntry } from './types';

/**
 * The sync engine. For each company kept in the cloud: send the changes
 * queued in the outbox in batches, then bring in what changed in the cloud
 * since the last rev seen, page by page, each page in one transaction.
 *
 * Nothing is lost: an outbox entry is removed only once the server has
 * confirmed that exact change; a change the server refuses is parked with its
 * reason and shown; a record with unsent changes here is never overwritten or
 * deleted by what comes from the cloud (the local change is sent and wins,
 * and the activity log notes the conflict). The company record, which every
 * device changes, is the exception that merges: see company-patch.ts.
 */

export const PUSH_BATCH = 200;
export const PUSH_BYTES = 512 * 1024;
export const PULL_PAGE = 500;
const ID_PAGE = 1000;
/** Records asked for at once, and fetched at the same time, while catching up on a table. */
const CATCH_UP_PAGE = 100;
const CATCH_UP_AT_ONCE = 8;
/** How long what the server has (server_features) is taken as known before asking again. */
export const FEATURES_RECHECK_MS = 10 * 60_000;
/** How long the owner's limits on this person are taken as known before asking again. */
export const PERMISSIONS_RECHECK_MS = 5 * 60_000;
/** Files younger than this are left alone by the clean-up: they may be on their way. */
const ORPHAN_AGE_MS = 60 * 60 * 1000;
/** Tries to remove a file before it is shown as a problem. */
const FILE_ATTEMPTS = 5;
const MINUTE = 60_000;
/**
 * How long a request of a sync may go unanswered (a dead connection after a
 * network change) before it is given up: the sync ends, lets go of the lock
 * and is tried again later. Files take longer.
 */
export const REQUEST_TIMEOUT_MS = 2 * MINUTE;
export const FILE_TIMEOUT_MS = 10 * MINUTE;
/**
 * Pauses before a file the cloud's rules refused is sent again by itself,
 * after the first, second… refusal: the refusal may not last (the owner
 * started deleting the company on another device and stopped). After the
 * last, it waits for "Try again" in Settings → Cloud.
 */
const FILE_RETRY_MS = [0, MINUTE, 5 * MINUTE, 15 * MINUTE, 60 * MINUTE, 180 * MINUTE, 360 * MINUTE];

export interface SyncProgress {
  companyId: string;
  kind: 'upload' | 'download';
  done: number;
  total: number;
}

export interface SyncContext {
  api: CloudApi;
  userId: string;
  onProgress?: (progress: SyncProgress) => void;
  /** Records per pull (tests use small pages). */
  pullPage?: number;
  /** How long any request may go unanswered (tests use short times). */
  timeoutMs?: number;
}

export interface SyncResult {
  pushed: number;
  pulled: number;
  conflicts: number;
  parked: number;
  /** Stopped before the end, for the company to leave this device (see lock.ts). */
  stopped?: boolean;
}

const SYNCED = new Set<string>(DATA_TABLES);

const table = (name: string): Table<Record<string, unknown>, string> =>
  db.table(name) as Table<Record<string, unknown>, string>;

const tablesForApply = () => [
  ...DATA_TABLES.map((name) => db[name] as Table),
  db.syncState,
  db.syncRevs,
  db.outbox,
];

/** Whether the company still syncs here for this account (it may have left the device meanwhile). */
async function stillLinked(companyId: string, ctx: SyncContext): Promise<boolean> {
  const link = await db.syncState.get(companyId);
  return Boolean(link && link.status !== 'removed' && link.userId === ctx.userId);
}

/* -------------------------------------------------------------------------- */
/* Requests                                                                   */
/* -------------------------------------------------------------------------- */

/** What a sync asks for to bring changes in: given up at once when the sync is told to stop. */
const RECEIVING = new Set<string>(['pullRecords', 'recordIds', 'syncInfo', 'downloadFile']);
/** The same while catching up on a table (see catchUpTables); sending uses getRecord too. */
const CATCHING_UP = new Set<string>([...RECEIVING, 'getRecord']);
const FILE_TRANSFERS = new Set<string>(['uploadFile', 'downloadFile']);

/** Detail of the error a request ends with when its sync was told to stop. */
const STOPPED = 'stopped';

/**
 * Settles with `request`, or fails after `ms` (retryable, like network
 * trouble) or as soon as `stop` fires. What the request answers later is
 * ignored.
 */
function deadline<T>(request: Promise<T>, ms: number, stop?: AbortSignal): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const finish = (settle: () => void) => {
      clearTimeout(timer);
      stop?.removeEventListener('abort', onStop);
      settle();
    };
    const onStop = () =>
      finish(() => reject(new CloudError('server', t(CLOUD_ERROR_MESSAGES.server), STOPPED)));
    const timer = setTimeout(
      () =>
        finish(() => reject(new CloudError('server', t(CLOUD_ERROR_MESSAGES.server), 'timeout'))),
      ms,
    );
    stop?.addEventListener('abort', onStop, { once: true });
    request.then(
      (value) => finish(() => resolve(value)),
      (error: unknown) => finish(() => reject(error)),
    );
  });
}

/**
 * The cloud as the sync talks to it: no request waits for an answer for
 * ever, and once `stop` fires (the company is about to leave this device)
 * what the sync brings in is given up at once. What it sends goes on.
 */
function guardedApi(ctx: SyncContext, stop?: AbortSignal, receiving = RECEIVING): CloudApi {
  return new Proxy(ctx.api, {
    get(target, key, receiver) {
      const value: unknown = Reflect.get(target, key, receiver);
      if (typeof value !== 'function' || typeof key !== 'string') return value;
      return (...args: unknown[]) => {
        const signal = receiving.has(key) ? stop : undefined;
        if (signal?.aborted) {
          return Promise.reject(new CloudError('server', t(CLOUD_ERROR_MESSAGES.server), STOPPED));
        }
        const answer: unknown = value.apply(target, args);
        if (!(answer instanceof Promise)) return answer;
        const ms =
          ctx.timeoutMs ?? (FILE_TRANSFERS.has(key) ? FILE_TIMEOUT_MS : REQUEST_TIMEOUT_MS);
        return deadline(answer, ms, signal);
      };
    },
  });
}

/* -------------------------------------------------------------------------- */
/* Demo and links                                                             */
/* -------------------------------------------------------------------------- */

/** The demo's address, on a reserved domain no real company has. */
const DEMO_EMAIL = 'accounts@rawdat-alkhaleej.example';

/** The demo company stays on the device it was made on. */
export function isDemoCompany(company: Pick<Company, 'demo' | 'email'>): boolean {
  return company.demo === true || company.email === DEMO_EMAIL;
}

export async function getLink(companyId: string): Promise<CloudLink | undefined> {
  return db.syncState.get(companyId);
}

function newLink(
  companyId: string,
  userId: string,
  role: MemberRole,
  status: CloudLink['status'],
  name: string,
): CloudLink {
  return {
    companyId,
    userId,
    role,
    status,
    cursor: 0,
    name,
    linkedAt: new Date().toISOString(),
    lastSyncAt: null,
    lastError: null,
    lastErrorAt: null,
    // Pulled from the start with every table this version has.
    tables: [...DATA_TABLES],
  };
}

/**
 * Keeps a company of this device in the cloud: creates it there with the
 * person as owner and queues every one of its records for upload. The
 * upload itself is the next sync (with progress).
 *
 * A company already in the person's cloud account (a restored backup, a copy
 * kept on this device) is refused with `company_exists`: its copy in the
 * cloud may have the team's newer work, so it is downloaded instead.
 */
export async function startUpload(companyId: ID, ctx: SyncContext): Promise<void> {
  const company = await db.companies.get(companyId);
  if (!company) throw new Error(t('Company not found'));
  if (isDemoCompany(company)) {
    throw new CloudError('invalid', t('The demo company stays on this device.'));
  }
  const existing = await db.syncState.get(companyId);
  if (existing && existing.status !== 'removed') return;
  try {
    const inCloud = (await ctx.api.myCompanies()).find((c) => c.id === companyId);
    // Only an empty one of the person's own (an upload that stopped before
    // its first record) is taken up again.
    if (
      inCloud &&
      !(inCloud.role === 'owner' && (await ctx.api.syncInfo(companyId)).recordCount === 0)
    ) {
      throw new CloudError('company_exists', t(CLOUD_ERROR_MESSAGES.company_exists));
    }
    await ctx.api.createCompany(companyId, company.name);
  } catch (error) {
    throw cloudError(error);
  }
  await db.transaction('rw', tablesForApply(), async () => {
    const at = new Date().toISOString();
    const entries: OutboxEntry[] = [];
    for (const name of DATA_TABLES) {
      const keys =
        name === 'companies'
          ? [companyId]
          : await table(name).where('companyId').equals(companyId).primaryKeys();
      for (const id of keys) {
        entries.push({ companyId, table: name, id: String(id), op: 'put', at, parked: 0 });
      }
    }
    await forgetCloudLink(companyId);
    await db.outbox.bulkAdd(entries);
    await db.syncState.put({
      ...newLink(companyId, ctx.userId, 'owner', 'uploading', company.name),
      total: entries.length,
    });
  });
}

/**
 * Brings a company from the cloud to this device. Its records arrive page by
 * page; the company itself is stored last, so it only appears once it is
 * complete. A copy already on this device is replaced.
 */
export async function startDownload(
  company: { id: string; name: string; role: MemberRole },
  ctx: SyncContext,
): Promise<void> {
  let total = 0;
  try {
    total = (await ctx.api.syncInfo(company.id)).recordCount;
  } catch (error) {
    throw cloudError(error);
  }
  await db.transaction(
    'rw',
    [...DATA_TABLES.map((name) => db[name] as Table), db.syncState, db.outbox, db.syncRevs],
    async () => {
      await forgetCloudLink(company.id);
      // Whatever an earlier copy left behind, without telling the cloud.
      for (const name of DATA_TABLES) {
        if (name === 'companies') await db.companies.delete(company.id);
        else await table(name).where('companyId').equals(company.id).delete();
      }
      await db.syncState.put({
        ...newLink(company.id, ctx.userId, company.role, 'downloading', company.name),
        total,
      });
    },
  );
}

/* -------------------------------------------------------------------------- */
/* One sync                                                                   */
/* -------------------------------------------------------------------------- */

/**
 * Sends what is queued, then brings in what changed. Throws a CloudError when
 * it can't. Told to stop (the company is about to leave this device, see
 * lock.ts), it stops bringing changes in and ends with `stopped`.
 */
export async function syncCompany(companyId: string, ctx: SyncContext): Promise<SyncResult> {
  const result: SyncResult = { pushed: 0, pulled: 0, conflicts: 0, parked: 0 };
  const link = await db.syncState.get(companyId);
  if (!link || link.status === 'removed' || link.userId !== ctx.userId) return result;
  const run = syncStarted(companyId);
  const sync: SyncContext = { ...ctx, api: guardedApi(ctx, run.stop) };
  try {
    // What the server has decides what may be sent (see heldForServer): asked
    // first when it isn't known yet, as for a company just uploaded.
    if (!link.features) await refreshFeatures(companyId, sync);
    await retryRefusedFiles(companyId, link.role);
    await processFileQueue(sync);
    await pushAll(companyId, sync, result);
    const touched = await pullAll(companyId, sync, result);
    await catchUpTables(
      companyId,
      { ...ctx, api: guardedApi(ctx, run.stop, CATCHING_UP) },
      result,
      touched,
    );
    await reconcile(companyId, touched);
    // Decisions the cloud took from this device are carried out now, as it keeps them.
    await settleDecisions(companyId, sync);
    // Reconciling (and carrying out) may have changed something here: send that too.
    await pushAll(companyId, sync, result);
    await refreshFeatures(companyId, sync);
    await refreshPermissions(companyId, sync, result.parked > 0);
    const after = await db.syncState.get(companyId);
    if (after && after.status !== 'removed') {
      await db.syncState.update(companyId, {
        status:
          after.status === 'uploading' && (await pendingCount(companyId)) === 0
            ? 'ready'
            : after.status,
        lastSyncAt: new Date().toISOString(),
        lastError: null,
        lastErrorAt: null,
      });
    }
    return result;
  } catch (error) {
    // Stopped for the company to leave this device: nothing went wrong.
    if (run.stop.aborted) return { ...result, stopped: true };
    const e = cloudError(error);
    if (e.code === 'not_member') {
      await db.syncState.update(companyId, { status: 'removed', removedReason: 'access' });
    }
    await db.syncState.update(companyId, {
      lastError: e.code,
      lastErrorAt: new Date().toISOString(),
    });
    throw e;
  } finally {
    run.end();
  }
}

export async function pendingCount(companyId: string): Promise<number> {
  return db.outbox.where('[companyId+parked]').equals([companyId, 0]).count();
}

export async function parkedEntries(companyId: string): Promise<OutboxEntry[]> {
  return db.outbox.where('[companyId+parked]').equals([companyId, 1]).toArray();
}

/* -------------------------------------------------------------------------- */
/* Sending                                                                    */
/* -------------------------------------------------------------------------- */

/** Owners before what refers to them, so the server can tell what is private. */
const PUSH_ORDER: Partial<Record<DataTable, number>> = {
  companies: 0,
  employees: 1,
  complianceDocuments: 2,
  renewals: 2,
  // Before their stock movements: the cloud keeps those of an issue that
  // stands, so a void reaches it first.
  stockIssues: 4,
  attachments: 8,
  activities: 9,
};

interface Outgoing {
  change: PushChange;
  seqs: number[];
  /** The transactions its changes were made in (OutboxEntry.group). */
  groups?: string[];
  /** Attachment content uploaded with this change. */
  file?: { storagePath: string; contentHash: string };
  /** The company record: this device's copy, kept as the base of its later changes. */
  base?: Record<string, unknown>;
  /** The company record: fields that had also changed in the cloud. */
  companyConflicts?: string[][];
}

/** The company record's change: the fields changed since the cloud's copy this device had. */
interface CompanyOutgoing {
  seqs: number[];
  /** The record as it is here, as the cloud keeps it. */
  local: Record<string, unknown>;
  /** Null when that copy isn't known (records synced by an earlier version). */
  ops: CompanyOp[] | null;
  baseRev: number | null;
}

interface Plan {
  batch: Outgoing[];
  company: CompanyOutgoing | null;
  /** Entries were dropped or parked: the outbox moved on, even with nothing to send. */
  progressed: boolean;
}

async function pushAll(companyId: string, ctx: SyncContext, result: SyncResult): Promise<void> {
  const link = await db.syncState.get(companyId);
  const total = link?.status === 'uploading' ? (link.total ?? 0) : 0;
  for (;;) {
    const entries = await db.outbox
      .where('[companyId+parked]')
      .equals([companyId, 0])
      .limit(PUSH_BATCH * 5)
      .toArray();
    if (entries.length === 0) return;
    const plan = await buildBatch(
      companyId,
      entries,
      ctx,
      result,
      link?.role,
      await heldForServer(companyId),
    );
    // The company may have left this device while the batch was prepared.
    if (!(await stillLinked(companyId, ctx))) return;
    if (plan.company) await sendCompany(companyId, plan.company, ctx, result);
    if (plan.batch.length) await sendBatch(companyId, plan.batch, ctx, result);
    if (!plan.company && plan.batch.length === 0 && !plan.progressed) return;
    if (total) {
      ctx.onProgress?.({
        companyId,
        kind: 'upload',
        total,
        done: Math.max(0, total - (await pendingCount(companyId))),
      });
    }
  }
}

/**
 * Parks entries the server refused, with the reason shown in Settings →
 * Cloud. A refused file (`file`) that may be taken later (`retry`) is sent
 * again by itself after a pause that grows with each refusal (FILE_RETRY_MS).
 */
async function park(
  seqs: number[],
  e: CloudError,
  { file = false, retry = false }: { file?: boolean; retry?: boolean } = {},
): Promise<void> {
  const now = Date.now();
  await db.outbox
    .where('seq')
    .anyOf(seqs)
    .modify((entry) => {
      entry.parked = 1;
      entry.error = e.code;
      entry.detail = e.detail.slice(0, 500);
      if (file) entry.file = 1;
      else delete entry.file;
      const attempts = (entry.attempts ?? 0) + 1;
      if (retry && attempts <= FILE_RETRY_MS.length) {
        entry.attempts = attempts;
        entry.retryAt = now + FILE_RETRY_MS[attempts - 1];
      } else {
        delete entry.attempts;
        delete entry.retryAt;
      }
    });
}

/**
 * Refused files whose pause is over go back in the queue, at the start of a
 * sync. Never a viewer's: viewers can't send files, so retrying would never
 * end.
 */
async function retryRefusedFiles(companyId: string, role: MemberRole): Promise<void> {
  if (!canEdit(role)) return;
  const now = Date.now();
  await db.outbox
    .where('[companyId+parked]')
    .equals([companyId, 1])
    .filter((entry) => entry.file === 1 && entry.retryAt !== undefined && entry.retryAt <= now)
    .modify((entry) => {
      entry.parked = 0;
      delete entry.retryAt;
    });
}

/** A stock movement of items issued: it waits with them for the server to take them. */
const issueMovement = (name: string, record: Record<string, unknown>) =>
  name === 'stockMovements' && record.sourceType === 'issue';

/**
 * Records a server without the tables of version 16 must not get: their
 * tables (it would refuse them), and confidential register documents and
 * their renewals (its rules would give them to staff and viewers, private
 * only when they have an employee). Until the owner runs the migration they
 * wait in the outbox, parked with that reason, whichever way they were
 * queued (saved here, the whole company uploaded, a backup merged); the
 * migration found, they go (see releaseHeld).
 */
async function heldForServer(
  companyId: string,
): Promise<(name: string, record: Record<string, unknown>) => boolean> {
  const link = await db.syncState.get(companyId);
  if (!link) return () => false;
  // Manpower costings (#3) and their activity, until the server has
  // 20261207000000_staffing_costings.sql: before it, the cloud refuses the
  // costings and doesn't know their activity is private.
  const costings = !linkHasFeature(link, 'staffing_costings');
  // Items issued to employees, until the server has
  // 20261210000000_warehouse_issues.sql: before it, the cloud refuses them.
  const issues = !linkHasFeature(link, 'stock_issues');
  const heldCosting = (name: string, record: Record<string, unknown>) =>
    (issues && (V18_TABLES.includes(name) || issueMovement(name, record))) ||
    (costings &&
      (V17_TABLES.includes(name) || (name === 'activities' && record.entity === 'costing')));
  if (linkHasFeature(link, 'tables_v16')) return heldCosting;
  const confidential = new Set(
    (
      await db.complianceDocuments
        .where('companyId')
        .equals(companyId)
        .filter((d) => d.confidential === true)
        .primaryKeys()
    ).map(String),
  );
  return (name, record) =>
    heldCosting(name, record) ||
    V16_TABLES.includes(name) ||
    (name === 'complianceDocuments' && record.confidential === true) ||
    (name === 'renewals' && confidential.has(renewedDocumentId(record) ?? ''));
}

/**
 * Puts parked for want of the migration go back in the queue once the server
 * has it. Manpower costings and their activity wait on for
 * 20261207000000_staffing_costings.sql.
 */
async function releaseHeld(companyId: string, features: readonly string[]): Promise<void> {
  const costings = features.includes('staffing_costings');
  const issues = features.includes('stock_issues');
  const waiting = await db.outbox
    .where('[companyId+parked]')
    .equals([companyId, 1])
    .filter((entry) => entry.error === 'server_outdated')
    .toArray();
  const activityIds = costings
    ? []
    : waiting.filter((entry) => entry.table === 'activities').map((entry) => entry.id);
  const costingActivities = new Set(
    (await db.activities.bulkGet(activityIds))
      .filter((activity) => activity?.entity === 'costing')
      .map((activity) => activity!.id),
  );
  const movementIds = issues
    ? []
    : waiting.filter((entry) => entry.table === 'stockMovements').map((entry) => entry.id);
  const issueMovements = new Set(
    (await db.stockMovements.bulkGet(movementIds))
      .filter((m) => m && issueMovement('stockMovements', m as unknown as Record<string, unknown>))
      .map((m) => m!.id),
  );
  const released = waiting
    .filter(
      (entry) =>
        (issues ||
          !(
            V18_TABLES.includes(entry.table) ||
            (entry.table === 'stockMovements' && issueMovements.has(entry.id))
          )) &&
        (costings ||
          !(
            V17_TABLES.includes(entry.table) ||
            (entry.table === 'activities' && costingActivities.has(entry.id))
          )),
    )
    .map((entry) => entry.seq!);
  if (released.length === 0) return;
  await db.outbox
    .where('seq')
    .anyOf(released)
    .modify((entry) => {
      if (entry.error !== 'server_outdated' || entry.parked !== 1) return;
      entry.parked = 0;
      delete entry.error;
      delete entry.detail;
    });
}

/** Changes made in more records at once than this (an import, say) are sent one by one. */
const CHANGE_GROUP_LIMIT = 20;

/**
 * The batch without the records at its end whose transaction has changes
 * left out of it, unless nothing else would be left to send.
 */
function withWholeChanges(batch: Outgoing[], entries: OutboxEntry[]): Outgoing[] {
  const sent = new Set(batch.flatMap((item) => item.seqs));
  const cut = new Set(
    entries.filter((e) => e.group && !sent.has(e.seq!)).map((e) => e.group as string),
  );
  if (cut.size === 0) return batch;
  const kept = [...batch];
  while (kept.length > 0 && (kept[kept.length - 1].groups ?? []).some((g) => cut.has(g))) {
    kept.pop();
  }
  return kept.length > 0 ? kept : batch;
}

/**
 * The batch in the parts the cloud takes or refuses whole: the records
 * changed in one local transaction together (a void and the payments it
 * freed), so a refused change doesn't leave what it changed with it in the
 * cloud. Large transactions are taken record by record.
 */
function changesOf(batch: Outgoing[]): Outgoing[][] {
  const sizes = new Map<string, number>();
  for (const item of batch) {
    for (const g of item.groups ?? []) sizes.set(g, (sizes.get(g) ?? 0) + 1);
  }
  const parent = batch.map((_, i) => i);
  const root = (i: number): number => (parent[i] === i ? i : (parent[i] = root(parent[i])));
  const first = new Map<string, number>();
  batch.forEach((item, i) => {
    for (const g of item.groups ?? []) {
      if ((sizes.get(g) ?? 0) > CHANGE_GROUP_LIMIT) continue;
      const j = first.get(g);
      if (j === undefined) first.set(g, i);
      else parent[root(i)] = root(j);
    }
  });
  const parts = new Map<number, Outgoing[]>();
  batch.forEach((item, i) => {
    const r = root(i);
    const part = parts.get(r);
    if (part) part.push(item);
    else parts.set(r, [item]);
  });
  return [...parts.values()];
}

async function buildBatch(
  companyId: string,
  entries: OutboxEntry[],
  ctx: SyncContext,
  result: SyncResult,
  role: MemberRole | undefined,
  held: (name: string, record: Record<string, unknown>) => boolean = () => false,
): Promise<Plan> {
  const groups = new Map<
    string,
    { table: string; id: string; seqs: number[]; last: OutboxEntry; made: Set<string> }
  >();
  for (const entry of entries) {
    const key = `${entry.table}/${entry.id}`;
    let group = groups.get(key);
    if (!group) {
      groups.set(
        key,
        (group = { table: entry.table, id: entry.id, seqs: [], last: entry, made: new Set() }),
      );
    }
    group.seqs.push(entry.seq!);
    if (entry.group) group.made.add(entry.group);
    if (entry.seq! >= group.last.seq!) group.last = entry;
  }
  const madeOf = (made: Set<string>) => (made.size ? { groups: [...made] } : {});
  const privateOwners = await privateOwnerIds(companyId);
  const plan: Plan = { batch: [], company: null, progressed: false };
  let bytes = 0;
  let full = false;
  for (const group of groups.values()) {
    if (plan.batch.length >= PUSH_BATCH) {
      full = true;
      break;
    }
    if (!SYNCED.has(group.table)) {
      // Not something the cloud keeps: drop it.
      await db.outbox.bulkDelete(group.seqs);
      plan.progressed = true;
      continue;
    }
    const record = await table(group.table).get(group.id);
    const ours =
      record &&
      (group.table === 'companies' ? group.id === companyId : record.companyId === companyId);
    const base = (await db.syncRevs.get([group.table, group.id]))?.rev ?? null;
    if (!ours) {
      if (group.last.op !== 'delete') {
        // Gone from this device without being deleted (the company was taken
        // off it while this sync ran): nothing to tell the cloud.
        await db.outbox.bulkDelete(group.seqs);
        plan.progressed = true;
        continue;
      }
      const item: Outgoing = {
        change: { tbl: group.table, id: group.id, deleted: true, base_rev: base },
        seqs: group.seqs,
        ...madeOf(group.made),
      };
      bytes += JSON.stringify(item.change).length;
      plan.batch.push(item);
      continue;
    }
    if (group.last.op !== 'delete' && held(group.table, record)) {
      await park(
        group.seqs,
        new CloudError('server_outdated', t(CLOUD_ERROR_MESSAGES.server_outdated)),
      );
      result.parked += 1;
      plan.progressed = true;
      continue;
    }
    if (group.table === 'companies') {
      const local = cloudCopy(group.table, record, privateOwners);
      const known = await db.syncRevs.get(['companies', companyId]);
      plan.company = {
        seqs: group.seqs,
        local,
        ops: known?.base ? companyOps(known.base, local) : null,
        baseRev: base,
      };
      continue;
    }
    const data = cloudCopy(group.table, record, privateOwners);
    const item: Outgoing = {
      change: { tbl: group.table, id: group.id, data, base_rev: base },
      seqs: group.seqs,
      ...madeOf(group.made),
    };
    if (group.table === 'attachments') {
      try {
        item.file = await uploadContent(companyId, record as unknown as Attachment, ctx);
      } catch (error) {
        // A file Storage refuses waits with its reason; the rest goes on. A
        // refusal by the rules may not last (the owner started deleting the
        // company and stopped): the file is sent again by itself later. One
        // too large, or of a kind not taken, waits for the person.
        const e = cloudError(error);
        if (e.retryable || e.code === 'not_member') throw e;
        await park(group.seqs, e, { file: true, retry: e.code === 'permission' && canEdit(role) });
        result.parked += 1;
        plan.progressed = true;
        continue;
      }
      if (item.file) Object.assign(data, { dataUrl: '', ...item.file });
    }
    const size = JSON.stringify(item.change).length;
    if (plan.batch.length > 0 && bytes + size > PUSH_BYTES) {
      full = true;
      break;
    }
    bytes += size;
    plan.batch.push(item);
  }
  // A change made with others goes with them: what the batch had no room
  // for waits, with the rest of its transaction, for the next one.
  if (full) plan.batch = withWholeChanges(plan.batch, entries);
  plan.batch.sort(
    (a, b) =>
      (PUSH_ORDER[a.change.tbl as DataTable] ?? 5) - (PUSH_ORDER[b.change.tbl as DataTable] ?? 5),
  );
  return plan;
}

/**
 * Ids of employees, letters, private register documents (an employee's, or
 * confidential) and their renewals: what makes a file private.
 */
async function privateOwnerIds(companyId: string): Promise<Set<string>> {
  const [employees, templates, letters, documents, renewals] = await Promise.all([
    db.employees.where('companyId').equals(companyId).primaryKeys(),
    db.letterTemplates.where('companyId').equals(companyId).primaryKeys(),
    db.employeeLetters.where('companyId').equals(companyId).primaryKeys(),
    db.complianceDocuments
      .where('companyId')
      .equals(companyId)
      .filter((d) => Boolean(d.employeeId) || d.confidential === true)
      .primaryKeys(),
    db.renewals.where('companyId').equals(companyId).toArray(),
  ]);
  const owners = new Set([...employees, ...templates, ...letters, ...documents].map(String));
  for (const renewal of renewals) {
    const documentId = renewedDocumentId(renewal as unknown as Record<string, unknown>);
    if (renewal.employeeId || (documentId && owners.has(documentId))) owners.add(renewal.id);
  }
  return owners;
}

/** The record as the cloud keeps it, with files and activity about employees marked private. */
function cloudCopy(
  name: string,
  record: Record<string, unknown>,
  privateOwners: Set<string>,
): Record<string, unknown> {
  const data: Record<string, unknown> = JSON.parse(JSON.stringify(record));
  delete data._private;
  // Bookkeeping of this device.
  delete data.contentMissing;
  // Any owner in the set makes the record private, whatever kind it is.
  const lookup = (_table: string, id: string) =>
    privateOwners.has(id) ? { employeeId: id } : null;
  if ((name === 'attachments' || name === 'activities') && isPrivateRecord(name, data, lookup)) {
    data._private = true;
  }
  return data;
}

/**
 * Uploads an attachment's content to Storage unless that exact content is
 * already there. Returns where it is, or nothing when this device doesn't
 * have the content (it came from the cloud and wasn't downloaded).
 */
async function uploadContent(
  companyId: string,
  attachment: Attachment,
  ctx: SyncContext,
): Promise<{ storagePath: string; contentHash: string } | undefined> {
  if (!attachment.dataUrl) return undefined;
  const blob = dataUrlToBlob(attachment.dataUrl);
  const hash = await contentHash(blob);
  const path = filePath(companyId, attachment.id);
  if (attachment.storagePath !== path || attachment.contentHash !== hash) {
    try {
      // The same path: a new version replaces the old file.
      await ctx.api.uploadFile(path, blob, attachment.type || blob.type);
    } catch (error) {
      throw cloudError(error);
    }
  }
  return { storagePath: path, contentHash: hash };
}

/**
 * Sends the company record's change: the changed fields, merged into the
 * cloud's copy. A server that can't merge (an older version) gets the whole
 * record, laid over the copy it has now, so fields others changed stay.
 */
async function sendCompany(
  companyId: string,
  item: CompanyOutgoing,
  ctx: SyncContext,
  result: SyncResult,
): Promise<void> {
  if (item.ops && item.ops.length === 0) {
    // Nothing differs from the cloud's copy this device has.
    await db.outbox.bulkDelete(item.seqs);
    return;
  }
  let data = item.local;
  let baseRev = item.baseRev;
  let conflicts: string[][] = [];
  try {
    if (item.ops) {
      const answer = await ctx.api.patchCompany(companyId, item.ops);
      if (answer) {
        await confirmCompany(companyId, item, answer.rev);
        result.pushed += 1;
        if (answer.conflicts.length && (await logCompanyConflicts(companyId, answer.conflicts))) {
          result.conflicts += 1;
        }
        return;
      }
      const current = await ctx.api.getRecord(companyId, 'companies', companyId);
      if (current) {
        const rebased = rebaseCompany(current.data, item.ops);
        data = rebased.data;
        conflicts = rebased.conflicts;
        baseRev = current.rev;
      }
    }
  } catch (error) {
    const e = cloudError(error);
    if (e.retryable || e.code === 'not_member' || e.code === 'resync') throw e;
    await park(item.seqs, e);
    result.parked += 1;
    return;
  }
  await sendBatch(
    companyId,
    [
      {
        change: { tbl: 'companies', id: companyId, data, base_rev: baseRev },
        seqs: item.seqs,
        // This device's copy as sent, not the merged one: the fields others
        // changed are not this device's changes, and they arrive with the
        // next pull (a later push must not put back what this device had).
        base: item.local,
        companyConflicts: conflicts,
      },
    ],
    ctx,
    result,
  );
}

/** The cloud merged this device's company change: forget it, and keep what was sent as the new base. */
async function confirmCompany(companyId: string, item: CompanyOutgoing, rev: number) {
  await db.transaction('rw', [db.outbox, db.syncRevs, db.syncState], async () => {
    markRemote();
    await db.outbox.bulkDelete(item.seqs);
    await db.outbox
      .where('[table+id]')
      .equals(['companies', companyId])
      .filter((e) => e.parked === 1)
      .delete();
    if (!(await db.syncState.get(companyId))) return;
    await db.syncRevs.put({ table: 'companies', id: companyId, companyId, rev, base: item.local });
  });
}

async function sendBatch(
  companyId: string,
  batch: Outgoing[],
  ctx: SyncContext,
  result: SyncResult,
): Promise<void> {
  let results: PushResult[];
  try {
    results = await ctx.api.pushRecords(
      companyId,
      batch.map((item) => item.change),
    );
  } catch (error) {
    const e = cloudError(error);
    if (e.retryable || e.code === 'not_member' || e.code === 'resync') throw e;
    // The server refused something in the batch: find it by halves and park
    // it, with whatever was changed with it (see changesOf).
    const parts = changesOf(batch);
    if (parts.length === 1) {
      await park(
        batch.flatMap((item) => item.seqs),
        e,
      );
      result.parked += batch.length;
      return;
    }
    const half = Math.ceil(parts.length / 2);
    await sendBatch(companyId, parts.slice(0, half).flat(), ctx, result);
    await sendBatch(companyId, parts.slice(half).flat(), ctx, result);
    return;
  }
  await confirm(companyId, batch, results, ctx, result);
}

/** Decisions on approval requests that change something once the cloud has them. */
const DECISIONS = new Set(['approved', 'rejected', 'cancelled']);

/**
 * Decisions on approval requests this device sent and the cloud took, by
 * company: carried out (or tidied up) after the cloud's copy is back here,
 * whatever the cloud kept (see settleDecisions).
 */
const decidedHere = new Map<string, Set<string>>();

/**
 * Notes a decision on an approval request among the changes the cloud just
 * took: one made on this device (a company uploaded whole sends its requests
 * as they are, to carry out nothing).
 */
function noteDecision(companyId: string, { change, groups }: Outgoing) {
  if (change.tbl !== 'approvals' || change.deleted || !groups?.length) return;
  const status = (change.data as Record<string, unknown> | undefined)?.status;
  if (typeof status !== 'string' || !DECISIONS.has(status)) return;
  let ids = decidedHere.get(companyId);
  if (!ids) decidedHere.set(companyId, (ids = new Set()));
  ids.add(change.id);
}

/**
 * Carries out the approvals this device sent, now the cloud's copy of each
 * is here: only those the cloud still has as approved (a request taken back
 * or decided on another device first stays as the cloud keeps it), and
 * tidies up after requests for new cheques that ended without one (see
 * carryOutDecided). Never stops the sync.
 */
async function settleDecisions(companyId: string, ctx: SyncContext): Promise<void> {
  const ids = decidedHere.get(companyId);
  if (!ids?.size) return;
  decidedHere.delete(companyId);
  try {
    const { carryOutDecided } = await import('@/db/approvals');
    await carryOutDecided(companyId, ids, async (tbl, id) => {
      try {
        return (await ctx.api.getRecord(companyId, tbl, id)) !== null;
      } catch {
        // Can't tell: the files stay.
        return true;
      }
    });
  } catch {
    // Carried out again from the request itself.
  }
}

/** The server has these changes: forget them here, note their versions and conflicts. */
async function confirm(
  companyId: string,
  batch: Outgoing[],
  results: PushResult[],
  ctx: SyncContext,
  result: SyncResult,
): Promise<void> {
  const byKey = new Map(results.map((r) => [`${r.tbl}/${r.id}`, r]));
  const conflicts: Outgoing[] = [];
  const removedFiles: string[] = [];
  await db.transaction('rw', [db.outbox, db.syncRevs, db.attachments, db.syncState], async () => {
    markRemote();
    // Taken off this device meanwhile: the outbox is all that is left to tidy.
    const linked = Boolean(await db.syncState.get(companyId));
    for (const item of batch) {
      const { tbl, id } = item.change;
      const answer = byKey.get(`${tbl}/${id}`);
      await db.outbox.bulkDelete(item.seqs);
      // A later version got through: an earlier refusal no longer matters.
      await db.outbox
        .where('[table+id]')
        .equals([tbl, id])
        .filter((e) => e.parked === 1)
        .delete();
      if (item.change.deleted) {
        if (tbl === 'attachments') removedFiles.push(filePath(companyId, id));
        if (linked) await db.syncRevs.delete([tbl, id]);
      } else if (answer?.rev != null && linked) {
        await db.syncRevs.put({
          table: tbl,
          id,
          companyId,
          rev: answer.rev,
          ...(item.base ? { base: item.base } : {}),
        });
      }
      if (item.file && linked) {
        await db.attachments.where('id').equals(id).modify(item.file);
      }
      if (answer?.conflict) conflicts.push(item);
    }
  });
  result.pushed += batch.length;
  for (const item of batch) noteDecision(companyId, item);
  if (removedFiles.length) await removeFiles(companyId, removedFiles, ctx);
  // What makes a conflict's note private, worked out once for them all.
  const privateOwners = conflicts.length ? await privateOwnerIds(companyId) : new Set<string>();
  for (const item of conflicts) {
    if (await logConflict(companyId, item.change, privateOwners)) result.conflicts += 1;
  }
  for (const item of batch) {
    if (
      item.companyConflicts?.length &&
      (await logCompanyConflicts(companyId, item.companyConflicts))
    ) {
      result.conflicts += 1;
    }
  }
}

/* -------------------------------------------------------------------------- */
/* Conflicts                                                                  */
/* -------------------------------------------------------------------------- */

const ENTITY: Partial<Record<DataTable, ActivityEntity>> = {
  clients: 'client',
  products: 'product',
  payments: 'payment',
  recurring: 'recurring',
  accounts: 'account',
  journals: 'journal',
  expenses: 'expense',
  vatReturns: 'vat_return',
  bankTransactions: 'bank',
  employees: 'employee',
  complianceDocuments: 'compliance',
  securityCheques: 'cheque',
  assets: 'asset',
  yearEnds: 'year_end',
  payRuns: 'payroll',
  stockEntries: 'stock',
  stockIssues: 'stock',
  // Private, like payroll (#3).
  staffingCostings: 'costing',
};

/**
 * Changes of these are expected on several devices at once and merge on
 * their own (the company record's real conflicts, fields both sides changed,
 * are noted by logCompanyConflicts).
 */
const QUIET = new Set<string>([
  'companies',
  'activities',
  'stockMovements',
  'syncRevs',
  // The cloud keeps a decision made, whatever an older copy says (see guardApprovalWrite).
  'approvals',
]);

/**
 * Whether the record a conflict is about is payroll or people data (a
 * manpower costing, a letter, an employee's or a confidential paper, the
 * renewal or a file of one; `privateOwners` from privateOwnerIds): its note
 * names it, so it is logged confidential, which every build since Phase 0
 * and every server rule keep from staff and viewers, even builds that don't
 * know its entity or drop the _private mark.
 */
function conflictIsPrivate(
  change: PushChange,
  data: Record<string, unknown>,
  privateOwners: Set<string>,
): boolean {
  // As cloudCopy: any owner in the set makes the record private.
  const lookup = (_table: string, id: string) =>
    privateOwners.has(id) ? { employeeId: id } : null;
  return isPrivateRecord(change.tbl, data, lookup);
}

async function logConflict(
  companyId: string,
  change: PushChange,
  privateOwners: Set<string>,
): Promise<boolean> {
  if (QUIET.has(change.tbl)) return false;
  const data = (change.data ?? {}) as Record<string, unknown>;
  const confidential = conflictIsPrivate(change, data, privateOwners);
  const label =
    (typeof data.number === 'string' && data.number) ||
    (typeof data.name === 'string' && data.name) ||
    (typeof data.reference === 'string' && data.reference) ||
    change.id.slice(0, 8);
  const entity: ActivityEntity =
    change.tbl === 'documents' && typeof data.type === 'string'
      ? (data.type as DocumentType)
      : (ENTITY[change.tbl as DataTable] ?? 'company');
  try {
    await logActivity(
      companyId,
      entity,
      change.id,
      'sync_conflict',
      change.deleted
        ? {
            text: msg(
              '{record} was changed on another device while it was deleted here. It was deleted.',
            ),
            vars: { record: label },
          }
        : {
            text: msg(
              '{record} was also changed on another device. The version saved on this device was kept.',
            ),
            vars: { record: label },
          },
      {
        documentId: change.tbl === 'documents' ? change.id : null,
        ...(confidential ? { confidential: true } : {}),
      },
    );
    return true;
  } catch {
    // A viewer can't write to the log; the change itself went through.
    return false;
  }
}

/**
 * Notes company settings changed here and on another device (this device's
 * values were kept), named as Settings names them, in English and Arabic.
 */
async function logCompanyConflicts(companyId: string, paths: string[][]): Promise<boolean> {
  const labels = companySettingLabels(paths);
  // Without the Arabic words (not loaded offline), Arabic readers see the English ones.
  const arabic = await inArabic(labels).catch(() => null);
  try {
    await logActivity(companyId, 'company', companyId, 'sync_conflict', {
      text: msg(
        'Company settings were also changed on another device. The values saved on this device were kept for: {fields}.',
      ),
      vars: { fields: labels.join(', ') },
      ...(arabic ? { arabic: { fields: arabic.join('، ') } } : {}),
    });
    return true;
  } catch {
    return false;
  }
}

/* -------------------------------------------------------------------------- */
/* Receiving                                                                  */
/* -------------------------------------------------------------------------- */

interface Touched {
  tables: Set<string>;
  documents: Set<string>;
  /** Payments deleted by the cloud's changes: their scans go with them (see reconcile). */
  deletedPayments?: Set<string>;
  /** Items deleted by the cloud's changes: their pictures go with them (see reconcile). */
  deletedProducts?: Set<string>;
  /** Payments whose record of cheque leaves the cloud's changes took away (see reconcile). */
  lostLeaves?: LostChequeLeaves[];
}

/**
 * Notes what a change from the cloud takes away with a record: the files of
 * a deleted payment or item, and cheque leaves no longer recorded on a payment
 * (a device on an older version of the app changed or deleted a printed cheque).
 */
function noteRemoved(
  touched: Touched,
  name: string,
  before: Record<string, unknown>,
  after: Record<string, unknown> | null,
) {
  if (name === 'payments') {
    if (!after) (touched.deletedPayments ??= new Set()).add(String(before.id));
    const numbers = lostChequeLeaves(before as unknown as Payment, after as unknown as Payment);
    if (numbers.length) {
      (touched.lostLeaves ??= []).push({ payment: before as unknown as Payment, numbers });
    }
  }
  if (name === 'products' && !after) (touched.deletedProducts ??= new Set()).add(String(before.id));
}

/** What became of a page of changes. */
type Applied = 'applied' | 'stale' | 'gone';

async function pullAll(companyId: string, ctx: SyncContext, result: SyncResult): Promise<Touched> {
  const touched: Touched = { tables: new Set(), documents: new Set() };
  let resynced = false;
  for (;;) {
    const link = await db.syncState.get(companyId);
    if (!link || link.status === 'removed') return touched;
    const asked = { since: link.cursor, epoch: link.epoch ?? 0 };
    let rows: PulledRow[];
    try {
      rows = await ctx.api.pullRecords(companyId, link.cursor, ctx.pullPage ?? PULL_PAGE);
    } catch (error) {
      const e = cloudError(error);
      if (e.code !== 'resync' || resynced) throw e;
      resynced = true;
      await fullResync(companyId, ctx, touched);
      continue;
    }
    if (rows.length) {
      const applied = await applyRows(companyId, rows, touched, asked);
      if (applied === 'gone') return touched;
      // The cursor was reset while the page was on its way: ask again from there.
      if (applied === 'stale') continue;
    }
    result.pulled += rows.length;
    if (link.status === 'downloading' && link.total) {
      ctx.onProgress?.({
        companyId,
        kind: 'download',
        total: link.total,
        done: Math.min(link.total, result.pulled),
      });
    }
    if (rows.length < (ctx.pullPage ?? PULL_PAGE)) break;
  }
  await finishPull(companyId, ctx, resynced);
  return touched;
}

/**
 * Ids of employees, letters, private register documents and their renewals
 * in a page of changes (see privateOwnerIds).
 */
function pageOwners(rows: PulledRow[]): Set<string> {
  const owners = new Set<string>();
  for (const row of rows) {
    if (row.deleted || !row.data) continue;
    if (
      row.tbl === 'employees' ||
      row.tbl === 'letterTemplates' ||
      row.tbl === 'employeeLetters' ||
      (row.tbl === 'complianceDocuments' && isPrivateRecord(row.tbl, row.data))
    ) {
      owners.add(row.id);
    }
  }
  for (const row of rows) {
    if (row.deleted || !row.data || row.tbl !== 'renewals') continue;
    const documentId = renewedDocumentId(row.data);
    if (isPrivateRecord(row.tbl, row.data) || (documentId && owners.has(documentId))) {
      owners.add(row.id);
    }
  }
  return owners;
}

/**
 * Stores a page of the cloud's changes in one transaction and moves the
 * cursor past it. `asked` is where the page was asked from: when the cursor
 * was reset meanwhile (a role that now sees more), the page is thrown away
 * ('stale') and asked for again. Rows the person's role may not hold (a page
 * asked for before the role changed) are left out. With `keepCursor` (records
 * of a table brought in by themselves, see catchUpTables) the cursor stays.
 */
export async function applyRows(
  companyId: string,
  rows: PulledRow[],
  touched: Touched = { tables: new Set(), documents: new Set() },
  asked?: { since: number; epoch: number },
  { keepCursor = false }: { keepCursor?: boolean } = {},
): Promise<Applied> {
  let outcome: Applied = 'applied';
  await db.transaction('rw', tablesForApply(), async () => {
    markRemote();
    const link = await db.syncState.get(companyId);
    if (!link || link.status === 'removed') {
      outcome = 'gone';
      return;
    }
    if (asked && ((link.epoch ?? 0) !== asked.epoch || link.cursor < asked.since)) {
      outcome = 'stale';
      return;
    }
    const entries = await db.outbox.where('companyId').equals(companyId).toArray();
    const pending = new Set(entries.map((e) => `${e.table}/${e.id}`));
    const hidePeople = !canSeePeople(link.role);
    const owners = hidePeople ? pageOwners(rows) : new Set<string>();
    const lookup = (_table: string, id: string) => (owners.has(id) ? { employeeId: id } : null);
    const holding = link.status === 'downloading';
    const duplicates = new Set(link.duplicates ?? []);
    let cursor = link.cursor;
    let pendingCompany = link.pendingCompany ?? null;
    let pendingCompanyRev = link.pendingCompanyRev;
    for (const row of rows) {
      if (!keepCursor) cursor = Math.max(cursor, row.rev);
      if (!SYNCED.has(row.tbl)) continue;
      // Payroll and people data this role may not hold.
      if (hidePeople && !row.deleted && isPrivateRecord(row.tbl, row.data, lookup)) continue;
      const store = table(row.tbl);
      const local = await store.get(row.id);
      // A record of another company with the same id is never touched.
      if (local && row.tbl !== 'companies' && local.companyId !== companyId) continue;
      if (pending.has(`${row.tbl}/${row.id}`)) {
        // This device's own change goes up and wins. The company record is
        // the exception: this device's changes are laid over the newer copy.
        if (row.tbl === 'companies' && row.data && local) {
          await rebaseCompanyHere(companyId, row, local, entries, link.role);
        }
        continue;
      }
      if (row.deleted) {
        // The company itself is only ever removed by the person, on purpose.
        if (row.tbl === 'companies') continue;
        if (local) {
          noteTouched(touched, row.tbl, local);
          await store.delete(row.id);
          noteRemoved(touched, row.tbl, local, null);
        }
        await db.syncRevs.delete([row.tbl, row.id]);
        continue;
      }
      const data = localCopy(companyId, row, local);
      if (!data) continue;
      if (row.tbl === 'companies' && holding) {
        pendingCompany = data;
        pendingCompanyRev = row.rev;
        continue;
      }
      if (!sameData(local, data)) {
        if (local) noteTouched(touched, row.tbl, local);
        if (local) noteRemoved(touched, row.tbl, local, data);
        noteTouched(touched, row.tbl, data);
        await store.put(data);
      }
      await db.syncRevs.put({
        table: row.tbl,
        id: row.id,
        companyId,
        rev: row.rev,
        ...(row.tbl === 'companies' ? { base: data } : {}),
      });
      if (row.tbl === 'documents') await noteDuplicates(companyId, data, duplicates);
    }
    await db.syncState.update(companyId, {
      cursor,
      pendingCompany,
      pendingCompanyRev,
      duplicates: await stillDuplicated(companyId, duplicates),
    });
  });
  return outcome;
}

/**
 * The company record has unsent changes here and a newer copy arrived: this
 * device's changes (since its base) are laid over the newer copy, which
 * becomes the base. A counter change the cloud refused (staff on an older
 * copy, with an older server) goes again.
 */
async function rebaseCompanyHere(
  companyId: string,
  row: PulledRow,
  local: Record<string, unknown>,
  entries: OutboxEntry[],
  role: MemberRole,
): Promise<void> {
  const remote = localCopy(companyId, row, local);
  if (!remote) return;
  const known = await db.syncRevs.get(['companies', companyId]);
  // Staff only ever change counters here (the outbox refuses the rest), so
  // without a base (synced by an earlier version) their change is the counters.
  const base =
    known?.base ?? (role === 'staff' ? { ...local, numbering: remote.numbering } : undefined);
  if (!base) {
    // What changed here isn't known (synced by an earlier version): keep this
    // copy, with the cloud's document counters so numbers aren't used twice.
    const numbering = mergeNumbering(
      local.numbering as Company['numbering'],
      remote.numbering as Company['numbering'],
    );
    if (!sameData(numbering, local.numbering)) {
      await table('companies').put({ ...local, numbering });
    }
    return;
  }
  const ops = companyOps(base, local);
  const { data } = rebaseCompany(remote, ops);
  if (!sameData(data, local)) await table('companies').put(data);
  await db.syncRevs.put({
    table: 'companies',
    id: companyId,
    companyId,
    rev: row.rev,
    base: remote,
  });
  // Nothing but counters (or nothing at all) left to send: a refusal of it
  // was about the older copy, so it goes again (or is dropped as sent).
  if (ops.length === 0 || onlyCounters(ops)) {
    const parked = entries
      .filter((e) => e.table === 'companies' && e.id === companyId && e.parked === 1)
      .map((e) => e.seq!);
    if (parked.length) {
      await db.outbox
        .where('seq')
        .anyOf(parked)
        .modify((entry) => {
          entry.parked = 0;
          delete entry.error;
          delete entry.detail;
        });
    }
  }
}

/** Notes a document that arrived with the number of another document here. */
async function noteDuplicates(
  companyId: string,
  doc: Record<string, unknown>,
  duplicates: Set<string>,
): Promise<void> {
  const number = typeof doc.number === 'string' ? doc.number : '';
  if (!number.trim() || typeof doc.type !== 'string') return;
  const same = (
    await db.documents
      .where('[companyId+type+number]')
      .equals([companyId, doc.type, number])
      .primaryKeys()
  ).map(String);
  if (same.length < 2) return;
  for (const id of same) duplicates.add(id);
}

/** The noted documents that still share their number with another one. */
async function stillDuplicated(companyId: string, ids: Set<string>): Promise<string[]> {
  const left: string[] = [];
  for (const id of ids) {
    const doc = await db.documents.get(id);
    if (!doc || doc.companyId !== companyId) continue;
    const count = await db.documents
      .where('[companyId+type+number]')
      .equals([companyId, doc.type, doc.number])
      .count();
    if (count > 1) left.push(id);
  }
  return left;
}

function noteTouched(touched: Touched, name: string, record: Record<string, unknown>) {
  touched.tables.add(name);
  if (name === 'documents') touched.documents.add(String(record.id));
  if (name === 'payments') {
    for (const id of (record.documentIds as string[] | undefined) ?? []) touched.documents.add(id);
    if (typeof record.creditId === 'string') touched.documents.add(record.creditId);
  }
}

/**
 * A record from the cloud as this device stores it, or null when it is not
 * one of this company's records. Attachments keep content already here.
 */
function localCopy(
  companyId: string,
  row: PulledRow,
  local: Record<string, unknown> | undefined,
): Record<string, unknown> | null {
  const data = row.data;
  if (!data || typeof data !== 'object' || data.id !== row.id) return null;
  if (row.tbl === 'companies' ? row.id !== companyId : data.companyId !== companyId) return null;
  const copy: Record<string, unknown> = { ...data };
  delete copy._private;
  if (row.tbl === 'attachments') {
    const same =
      local &&
      typeof local.dataUrl === 'string' &&
      local.dataUrl !== '' &&
      (local.contentHash === copy.contentHash || !copy.storagePath);
    copy.dataUrl = same ? local.dataUrl : typeof copy.dataUrl === 'string' ? copy.dataUrl : '';
    if (copy.dataUrl === '' && typeof copy.storagePath === 'string' && copy.storagePath) {
      copy.contentMissing = 1;
    } else {
      delete copy.contentMissing;
    }
  }
  return copy;
}

/** Ends a pull: a download stores its company last; a resync moves the cursor past purged deletes. */
async function finishPull(companyId: string, ctx: SyncContext, resynced: boolean): Promise<void> {
  const link = await db.syncState.get(companyId);
  if (!link) return;
  if (link.status !== 'downloading' && !resynced) return;
  const info = await ctx.api.syncInfo(companyId).catch((error) => {
    throw cloudError(error);
  });
  await db.transaction('rw', tablesForApply(), async () => {
    markRemote();
    const current = await db.syncState.get(companyId);
    if (!current) return;
    const patch: Partial<CloudLink> = { cursor: Math.max(current.cursor, info.purgedUntilRev) };
    if (current.status === 'downloading') {
      if (!current.pendingCompany) {
        // The company record isn't in the cloud yet (still uploading): try later.
        throw new CloudError('server', t('This company is still being uploaded. Try again soon.'));
      }
      await db.companies.put(current.pendingCompany as unknown as Company);
      if (current.pendingCompanyRev) {
        await db.syncRevs.put({
          table: 'companies',
          id: companyId,
          companyId,
          rev: current.pendingCompanyRev,
          base: current.pendingCompany,
        });
      }
      Object.assign(patch, { status: 'ready', pendingCompany: null, pendingCompanyRev: undefined });
    }
    await db.syncState.update(companyId, patch);
  });
}

/**
 * The device was away longer than deletes are remembered: keep only what the
 * cloud still has (and what is waiting to be sent from here), then bring in
 * everything again.
 */
async function fullResync(companyId: string, ctx: SyncContext, touched: Touched): Promise<void> {
  const ids = new Set<string>();
  let after: { tbl: string; id: string } | null = null;
  try {
    for (;;) {
      const page = await ctx.api.recordIds(companyId, after, ID_PAGE);
      for (const key of page) ids.add(`${key.tbl}/${key.id}`);
      if (page.length < ID_PAGE) break;
      after = page[page.length - 1];
    }
  } catch (error) {
    throw cloudError(error);
  }
  await db.transaction('rw', tablesForApply(), async () => {
    markRemote();
    const pending = new Set(
      (await db.outbox.where('companyId').equals(companyId).toArray()).map(
        (e) => `${e.table}/${e.id}`,
      ),
    );
    for (const name of DATA_TABLES) {
      if (name === 'companies') continue;
      const records = await table(name).where('companyId').equals(companyId).toArray();
      const gone = records.filter(
        (r) => !ids.has(`${name}/${String(r.id)}`) && !pending.has(`${name}/${String(r.id)}`),
      );
      if (gone.length === 0) continue;
      for (const record of gone) {
        noteTouched(touched, name, record);
        noteRemoved(touched, name, record, null);
      }
      await table(name).bulkDelete(gone.map((r) => String(r.id)));
      await db.syncRevs.bulkDelete(gone.map((r) => [name, String(r.id)] as [string, string]));
    }
    // Everything comes again, of every table.
    await db.syncState.update(companyId, { cursor: 0, tables: [...DATA_TABLES] });
  });
  const link = await db.syncState.get(companyId);
  if (link?.role === 'owner') {
    // Left-over files of records deleted while this device was away.
    void cleanupFiles(companyId, ctx).catch(() => undefined);
  }
}

/* -------------------------------------------------------------------------- */
/* Tables added later                                                         */
/* -------------------------------------------------------------------------- */

/**
 * Tables of database version 16. A version before it moved its cursor past
 * their records without storing them (it didn't know them); its links have
 * no `tables`.
 */
const V16_TABLES: readonly string[] = [
  'chequeLayouts',
  'vehicles',
  'approvals',
  'letterTemplates',
  'employeeLetters',
];

/**
 * Tables of database version 17 (manpower costings, #3). A link noted
 * before it has the tables it pulled with, without them.
 */
const V17_TABLES: readonly string[] = ['staffingCostings'];

/**
 * Tables of database version 18 (items issued to employees). A link noted
 * before it has the tables it pulled with, without them.
 */
const V18_TABLES: readonly string[] = ['stockIssues'];

/** The tables a link's device has pulled the company with (see CloudLink.tables). */
export function pulledTables(link: Pick<CloudLink, 'tables'>): string[] {
  return (
    link.tables ??
    DATA_TABLES.filter(
      (name) =>
        !V16_TABLES.includes(name) && !V17_TABLES.includes(name) && !V18_TABLES.includes(name),
    )
  );
}

/**
 * Brings in the records of the tables a link hasn't pulled with: the version
 * that pulled before moved its cursor past them, so they would never arrive.
 * Only those tables are read (their ids, then each record), and stored as a
 * pull stores them, for this person's role; the cursor stays where it is.
 * Then the link notes the tables. Stopped half way (no connection, or the
 * sync was told to stop: `ctx` gives up getRecord then too), it starts again
 * at the next sync; records already here are stored again.
 */
async function catchUpTables(
  companyId: string,
  ctx: SyncContext,
  result: SyncResult,
  touched: Touched,
): Promise<void> {
  const link = await db.syncState.get(companyId);
  if (!link || link.status === 'removed') return;
  const known = new Set(pulledTables(link));
  const missing = DATA_TABLES.filter((name) => !known.has(name));
  if (missing.length === 0) return;
  // A pull from the start brings every table anyway.
  if (link.cursor > 0) {
    const asked = { since: link.cursor, epoch: link.epoch ?? 0 };
    for (const name of missing) {
      let after: RecordKey | null = null;
      for (;;) {
        let page: RecordKey[];
        let rows: PulledRow[];
        try {
          page = await ctx.api.recordIds(companyId, after, CATCH_UP_PAGE, name);
          rows = await fetchRows(companyId, name, page, ctx);
        } catch (error) {
          throw cloudError(error);
        }
        if (rows.length) {
          const applied = await applyRows(companyId, rows, touched, asked, { keepCursor: true });
          // Gone from this device, or everything is coming again from the start.
          if (applied !== 'applied') return;
          result.pulled += rows.length;
        }
        if (page.length < CATCH_UP_PAGE) break;
        after = page[page.length - 1];
      }
    }
  }
  // What an older build kept for a role that doesn't see payroll and people
  // data, not knowing it was private (activity about a manpower costing,
  // pulled before the role changed): gone once, now this build knows.
  if (!canSeePeople(link.role)) await removeHiddenData(companyId);
  await db.syncState.update(companyId, { tables: [...DATA_TABLES] });
}

/** These records as the cloud has them now, as pulled rows; those deleted meanwhile are left out. */
async function fetchRows(
  companyId: string,
  tbl: string,
  keys: RecordKey[],
  ctx: SyncContext,
): Promise<PulledRow[]> {
  const rows: PulledRow[] = [];
  for (let i = 0; i < keys.length; i += CATCH_UP_AT_ONCE) {
    const group = keys.slice(i, i + CATCH_UP_AT_ONCE);
    const found = await Promise.all(group.map((key) => ctx.api.getRecord(companyId, tbl, key.id)));
    found.forEach((record, j) => {
      if (record) {
        rows.push({ tbl, id: group[j].id, data: record.data, rev: record.rev, deleted: false });
      }
    });
  }
  return rows;
}

/**
 * Notes what the server has (see features.ts), asked at most every
 * FEATURES_RECHECK_MS: the owner may run a migration at any time. When it
 * can't be asked, what was known stays.
 */
async function refreshFeatures(companyId: string, ctx: SyncContext): Promise<void> {
  const link = await db.syncState.get(companyId);
  if (!link || link.status === 'removed') return;
  const askedAt = link.featuresAt ? Date.parse(link.featuresAt) : 0;
  if (link.features && Date.now() - askedAt < FEATURES_RECHECK_MS) return;
  let features: string[];
  try {
    features = await ctx.api.serverFeatures(companyId);
  } catch {
    return;
  }
  await db.syncState.update(companyId, { features, featuresAt: new Date().toISOString() });
  if (features.includes('tables_v16')) await releaseHeld(companyId, features);
}

/**
 * Notes the owner's limits on this person (see roles.ts), once the server
 * has them, asked at most every PERMISSIONS_RECHECK_MS, and at once when the
 * server just refused a change (`now`): the limits may have changed since.
 * When they can't be asked, what was known stays.
 */
async function refreshPermissions(
  companyId: string,
  ctx: SyncContext,
  now: boolean,
): Promise<void> {
  const link = await db.syncState.get(companyId);
  if (!link || link.status === 'removed' || !linkHasFeature(link, 'super_admin')) return;
  const askedAt = link.permissionsAt ? Date.parse(link.permissionsAt) : 0;
  if (!now && Date.now() - askedAt < PERMISSIONS_RECHECK_MS) return;
  let mine: MyPermissions | null;
  try {
    mine = await ctx.api.myPermissions(companyId);
  } catch {
    return;
  }
  if (mine) await notePermissions(companyId, mine);
}

/** Keeps the owner's limits on this person as the server just said them. */
export async function notePermissions(companyId: string, mine: MyPermissions): Promise<void> {
  await db.syncState.update(companyId, {
    permissions: mine.permissions,
    approver: mine.approver,
    seniorRolesOwnerOnly: mine.seniorRolesOwnerOnly,
    permissionsAt: new Date().toISOString(),
  });
}

/* -------------------------------------------------------------------------- */
/* Derived data                                                               */
/* -------------------------------------------------------------------------- */

const STOCK_TABLES = [
  'documents',
  'stockEntries',
  'stockIssues',
  'landedCosts',
  'stockMovements',
  'products',
  'warehouses',
  'companies',
];

/** Codes of a change the cloud refused for good, not for want of a newer server. */
const REFUSED = new Set(['permission', 'approval_required']);

/** How often a device works out again the same document the cloud's changes brought, at most. */
const CORRECTIONS = 3;
const CORRECTION_WINDOW_MS = 30 * MINUTE;

/** When this device last worked out again a document from the cloud, by company and document. */
const corrections = new Map<string, number[]>();

function noteCorrection(companyId: string, id: string) {
  const key = `${companyId}/${id}`;
  const now = Date.now();
  const recent = (corrections.get(key) ?? []).filter((at) => now - at < CORRECTION_WINDOW_MS);
  recent.push(now);
  corrections.set(key, recent);
}

function correctedTooOften(companyId: string, id: string): boolean {
  const now = Date.now();
  const recent = (corrections.get(`${companyId}/${id}`) ?? []).filter(
    (at) => now - at < CORRECTION_WINDOW_MS,
  );
  return recent.length >= CORRECTIONS;
}

/**
 * Documents whose balances stay as the cloud's copy says instead of being
 * worked out again here: those a payment the cloud refused pays (only this
 * device has it, so every other device works them out without it), and
 * those this device keeps working out again only for the cloud to bring
 * them back as they were (a device with an older version counts a payment
 * the cloud refused it): sending them again would never end.
 */
async function keptAsInCloud(companyId: string, ids: string[]): Promise<Set<string>> {
  const held = new Set(ids.filter((id) => correctedTooOften(companyId, id)));
  const refused = (await parkedEntries(companyId)).filter(
    (e) => e.table === 'payments' && e.op === 'put' && REFUSED.has(e.error ?? ''),
  );
  if (refused.length === 0) return held;
  const payments = await db.payments.bulkGet([...new Set(refused.map((e) => e.id))]);
  for (const payment of payments) {
    if (!payment) continue;
    for (const id of payment.documentIds ?? []) held.add(id);
    if (payment.creditId) held.add(payment.creditId);
  }
  return held;
}

/**
 * Stock levels and costs, document balances and order progress are stored
 * with the records they come from. After changes from the cloud they are
 * worked out again here (the same everywhere, so every device agrees), and
 * whatever differs is saved and sent like any other change.
 */
async function reconcile(companyId: string, touched: Touched): Promise<void> {
  if (touched.tables.size === 0) return;
  const link = await db.syncState.get(companyId);
  if (!link || link.role === 'viewer' || link.status !== 'ready') return;
  // Books made view only by the owner: other devices work these out.
  if (limitBlocksWrite(link.role, link.permissions, 'documents', {})) return;
  const [{ rebuildStock }, { recalculateDocuments, refreshOrdersFor }] = await Promise.all([
    import('@/db/inventory'),
    import('@/db/documents'),
  ]);
  if (STOCK_TABLES.some((name) => touched.tables.has(name)) && (await keepsStock(companyId))) {
    await rebuildStock(companyId);
  }
  if (touched.documents.size) {
    const ids = [...touched.documents];
    const held = await keptAsInCloud(companyId, ids);
    const worked = ids.filter((id) => !held.has(id));
    const before = await db.documents.bulkGet(worked);
    await db.transaction('rw', [db.documents, db.clients, db.payments], () =>
      recalculateDocuments(worked),
    );
    const after = await db.documents.bulkGet(worked);
    worked.forEach((id, i) => {
      if (!sameData(before[i], after[i])) noteCorrection(companyId, id);
    });
    await refreshOrdersFor(ids);
  }
  if (touched.deletedPayments?.size) {
    await removeFilesOf(companyId, db.payments, [...touched.deletedPayments]);
  }
  if (touched.deletedProducts?.size) {
    await removeFilesOf(companyId, db.products, [...touched.deletedProducts]);
  }
  if (touched.lostLeaves?.length) {
    const { logLostChequeLeaves } = await import('@/db/cheque-print');
    await logLostChequeLeaves(companyId, touched.lostLeaves).catch(() => undefined);
  }
}

/**
 * The files of payments (scans) and items (pictures) deleted on another
 * device, deleted here too and sent, so their files go from the cloud as
 * well. A payment deleted by an older build (before #21), or an item (before
 * #29), leaves its files behind; this build deletes them with the record,
 * and then nothing is left here to delete. Never stops the sync.
 */
async function removeFilesOf(
  companyId: string,
  owners: typeof db.payments | typeof db.products,
  ownerIds: string[],
): Promise<void> {
  try {
    await db.transaction('rw', [owners, db.attachments], async () => {
      const back = new Set(
        (await (owners as Table<{ id: string }, string>).bulkGet(ownerIds))
          .filter(Boolean)
          .map((p) => p!.id),
      );
      const gone = ownerIds.filter((id) => !back.has(id));
      if (gone.length === 0) return;
      const scans = await db.attachments
        .where('ownerId')
        .anyOf(gone)
        .filter((a) => a.companyId === companyId)
        .primaryKeys();
      if (scans.length) await db.attachments.bulkDelete(scans);
    });
  } catch {
    // Not allowed (any more) or not saved: the next device to sync tidies up.
  }
}

/** Whether the company has stock to keep in step (stock items or movements). */
async function keepsStock(companyId: string): Promise<boolean> {
  if ((await db.stockMovements.where('companyId').equals(companyId).count()) > 0) return true;
  return (
    (await db.products
      .where('companyId')
      .equals(companyId)
      .filter((p) => p.kind === 'stock')
      .count()) > 0
  );
}

/* -------------------------------------------------------------------------- */
/* Roles                                                                      */
/* -------------------------------------------------------------------------- */

/**
 * Applies a role change, in one transaction with what follows from it: a
 * role that no longer sees payroll and people data loses this device's copy
 * of it; a role that sees more brings everything in again, since it was left
 * out before (a page asked for under the old role is then thrown away).
 */
export async function applyRole(companyId: string, role: MemberRole): Promise<void> {
  await db.transaction('rw', tablesForApply(), async () => {
    markRemote();
    const link = await db.syncState.get(companyId);
    if (!link || link.role === role) return;
    const seesMore = !canSeePeople(link.role) && canSeePeople(role);
    await db.syncState.update(companyId, {
      role,
      // The owner's limits and approvers follow the role: asked again.
      permissionsAt: undefined,
      ...(seesMore ? { cursor: 0, epoch: (link.epoch ?? 0) + 1, tables: [...DATA_TABLES] } : {}),
    });
    if (!canSeePeople(role)) await removeHiddenRecords(companyId);
  });
}

/** Removes from this device what the person's role may not see (payroll and people data). */
export async function removeHiddenData(companyId: string): Promise<void> {
  await db.transaction('rw', tablesForApply(), async () => {
    markRemote();
    await removeHiddenRecords(companyId);
  });
}

/** removeHiddenData's work, in the transaction already running. */
async function removeHiddenRecords(companyId: string): Promise<void> {
  const owners = await privateOwnerIds(companyId);
  const lookup = (_table: string, id: string) => (owners.has(id) ? { employeeId: id } : null);
  for (const name of DATA_TABLES) {
    if (name === 'companies') continue;
    const records = await table(name).where('companyId').equals(companyId).toArray();
    const hidden = records.filter(
      (r) =>
        (PEOPLE_TABLES as readonly string[]).includes(name) ||
        isPrivateRecord(name, r, lookup) ||
        owners.has(String(r.id)),
    );
    if (hidden.length === 0) continue;
    const keys = hidden.map((r) => String(r.id));
    await table(name).bulkDelete(keys);
    await db.syncRevs.bulkDelete(keys.map((id) => [name, id] as [string, string]));
    await db.outbox
      .where('companyId')
      .equals(companyId)
      .filter((e) => e.table === name && keys.includes(e.id))
      .delete();
  }
}

/* -------------------------------------------------------------------------- */
/* Files                                                                      */
/* -------------------------------------------------------------------------- */

/**
 * Removes files and returns those still stored afterwards. Storage skips
 * what its rules hide without an error, so what wasn't removed is checked:
 * with the server (stored_files), or, on an older server, against the files
 * this person can see.
 */
async function removeAndCheck(
  companyId: string,
  paths: string[],
  ctx: SyncContext,
): Promise<string[]> {
  const removed = new Set(await ctx.api.removeFiles(paths));
  const rest = paths.filter((path) => !removed.has(path));
  if (rest.length === 0) return [];
  const stored = await ctx.api.storedFiles(companyId, rest);
  const still = new Set(stored ?? (await ctx.api.listFiles(companyId)).map((f) => f.path));
  return rest.filter((path) => still.has(path));
}

/** Removes files from Storage; what can't be removed now waits in the file queue. */
async function removeFiles(companyId: string, paths: string[], ctx: SyncContext): Promise<void> {
  let left: string[];
  let code: string;
  try {
    left = await removeAndCheck(companyId, paths, ctx);
    code = 'permission';
  } catch (error) {
    left = paths;
    code = cloudError(error).code;
  }
  if (left.length === 0) return;
  const at = new Date().toISOString();
  await db.fileQueue.bulkAdd(
    left.map((path) => ({
      companyId,
      path,
      at,
      attempts: 1,
      lastError: code,
      userId: ctx.userId,
    })),
  );
}

/**
 * Tries the file removals that failed before: this account's only (a
 * removal waits for the account that deleted the record). A removal that
 * still removes nothing after a few tries is shown as a problem.
 */
export async function processFileQueue(ctx: SyncContext): Promise<void> {
  const mine = new Set(
    (await db.syncState.filter((l) => l.userId === ctx.userId).primaryKeys()).map(String),
  );
  const tasks = (await db.fileQueue.toArray())
    .filter((task) => !task.failed)
    .filter((task) => (task.userId ? task.userId === ctx.userId : mine.has(task.companyId)))
    .slice(0, 100);
  const byCompany = new Map<string, FileTask[]>();
  for (const task of tasks) {
    byCompany.set(task.companyId, [...(byCompany.get(task.companyId) ?? []), task]);
  }
  for (const [companyId, group] of byCompany) {
    let left: Set<string>;
    let code = 'permission';
    let retryable = false;
    try {
      left = new Set(
        await removeAndCheck(
          companyId,
          group.map((task) => task.path),
          ctx,
        ),
      );
    } catch (error) {
      const e = cloudError(error);
      if (e.code === 'not_member') {
        // Not in the company any more: its owner's clean-up takes care of them.
        await db.fileQueue.bulkDelete(group.map((task) => task.seq!));
        continue;
      }
      left = new Set(group.map((task) => task.path));
      code = e.code;
      retryable = e.retryable;
    }
    const done = group.filter((task) => !left.has(task.path)).map((task) => task.seq!);
    if (done.length) await db.fileQueue.bulkDelete(done);
    const again = group.filter((task) => left.has(task.path)).map((task) => task.seq!);
    if (again.length) {
      await db.fileQueue
        .where('seq')
        .anyOf(again)
        .modify((task) => {
          task.attempts += 1;
          task.lastError = code;
          if (!retryable && task.attempts >= FILE_ATTEMPTS) task.failed = 1;
        });
    }
  }
}

/** Tries the failed file removals of a company again at the next sync. */
export async function retryFileRemovals(companyId: string): Promise<void> {
  await db.fileQueue
    .where('companyId')
    .equals(companyId)
    .modify((task) => {
      delete task.failed;
      task.attempts = 0;
    });
}

/** Downloads the content of attachments that arrived without it (small ones). */
export async function downloadMissingFiles(
  companyId: string,
  ctx: SyncContext,
  maxBytes: number,
): Promise<void> {
  // Only files marked missing are read: reading every file would load all
  // their content.
  const missing = await db.attachments
    .where('[companyId+contentMissing]')
    .equals([companyId, 1])
    .filter((a) => !a.dataUrl && Boolean(a.storagePath) && (a.size ?? 0) <= maxBytes)
    .toArray();
  for (const attachment of missing) {
    await fetchAttachmentContent(attachment, ctx).catch(() => undefined);
  }
}

/** The content of an attachment, downloading it from the cloud when needed. */
export async function fetchAttachmentContent(
  attachment: Pick<Attachment, 'id' | 'dataUrl' | 'storagePath' | 'contentHash' | 'type'>,
  ctx: SyncContext,
): Promise<string> {
  if (attachment.dataUrl) return attachment.dataUrl;
  if (!attachment.storagePath) throw new Error(t('This file is not available.'));
  let blob: Blob;
  try {
    blob = await ctx.api.downloadFile(attachment.storagePath);
  } catch (error) {
    throw cloudError(error);
  }
  const dataUrl = await blobToDataUrl(blob, attachment.type || blob.type);
  await db.transaction('rw', db.attachments, async () => {
    markRemote();
    const current = await db.attachments.get(attachment.id);
    if (current && !current.dataUrl && current.contentHash === attachment.contentHash) {
      const filled: Attachment = { ...current, dataUrl };
      delete filled.contentMissing;
      await db.attachments.put(filled);
    }
  });
  return dataUrl;
}

/**
 * Removes files in the company's folder that no attachment uses any more
 * (owners only). Returns how many were removed.
 */
export async function cleanupFiles(companyId: string, ctx: SyncContext): Promise<number> {
  try {
    const files = await ctx.api.listFiles(companyId);
    const used = new Set<string>();
    let after: { tbl: string; id: string } | null = null;
    for (;;) {
      const page = await ctx.api.recordIds(companyId, after, ID_PAGE, 'attachments');
      for (const key of page) used.add(filePath(companyId, key.id));
      if (page.length < ID_PAGE) break;
      after = page[page.length - 1];
    }
    const cutoff = Date.now() - ORPHAN_AGE_MS;
    const orphans = files
      .filter((file) => !used.has(file.path))
      .filter((file) => !file.createdAt || Date.parse(file.createdAt) < cutoff)
      .map((file) => file.path);
    let removed = 0;
    for (let i = 0; i < orphans.length; i += 100) {
      removed += (await ctx.api.removeFiles(orphans.slice(i, i + 100))).length;
    }
    return removed;
  } catch (error) {
    throw cloudError(error);
  }
}

/* -------------------------------------------------------------------------- */
/* Refused changes                                                            */
/* -------------------------------------------------------------------------- */

/** Sends a refused change again (after the role was changed, say). */
export async function retryParked(companyId: string): Promise<void> {
  await db.outbox
    .where('[companyId+parked]')
    .equals([companyId, 1])
    .modify((entry) => {
      entry.parked = 0;
      delete entry.error;
      delete entry.detail;
      delete entry.file;
      delete entry.attempts;
      delete entry.retryAt;
    });
}

/**
 * Gives up a refused change: this device takes the record back as the cloud
 * has it. A record the cloud never had would be deleted from this device, so
 * that only happens with `deleteNew` (the person agreed to it); without it
 * nothing changes and the answer is 'not_in_cloud'. The company record itself
 * is never deleted this way. What was changed with it, and held back with it
 * (see changesOf), goes back as the cloud has it too: records made with it
 * leave this device.
 */
export async function discardParked(
  companyId: string,
  entry: Pick<OutboxEntry, 'table' | 'id'>,
  ctx: SyncContext,
  { deleteNew = false }: { deleteNew?: boolean } = {},
): Promise<'undone' | 'not_in_cloud'> {
  const made = new Set(
    (await db.outbox.where('[table+id]').equals([entry.table, entry.id]).toArray())
      .filter((e) => e.parked === 1 && e.group)
      .map((e) => e.group as string),
  );
  const outcome = await discardOne(companyId, entry, ctx, deleteNew);
  if (outcome !== 'undone' || made.size === 0) return outcome;
  const withIt = (await parkedEntries(companyId)).filter(
    (e) => e.group && made.has(e.group) && e.table !== 'companies',
  );
  const others = new Map(withIt.map((e) => [`${e.table}/${e.id}`, e]));
  others.delete(`${entry.table}/${entry.id}`);
  for (const other of others.values()) await discardOne(companyId, other, ctx, true);
  return outcome;
}

async function discardOne(
  companyId: string,
  entry: Pick<OutboxEntry, 'table' | 'id'>,
  ctx: SyncContext,
  deleteNew: boolean,
): Promise<'undone' | 'not_in_cloud'> {
  let remote: { data: Record<string, unknown>; rev: number } | null;
  try {
    remote = await guardedApi(ctx).getRecord(companyId, entry.table, entry.id);
  } catch (error) {
    throw cloudError(error);
  }
  let outcome: 'undone' | 'not_in_cloud' = 'undone';
  await db.transaction('rw', tablesForApply(), async () => {
    markRemote();
    const store = table(entry.table);
    const local = await store.get(entry.id);
    if (!remote && local && (!deleteNew || entry.table === 'companies')) {
      outcome = 'not_in_cloud';
      return;
    }
    await db.outbox.where('[table+id]').equals([entry.table, entry.id]).delete();
    if (!remote) {
      if (local) await store.delete(entry.id);
      await db.syncRevs.delete([entry.table, entry.id]);
      return;
    }
    const data = localCopy(
      companyId,
      { tbl: entry.table, id: entry.id, data: remote.data, rev: remote.rev, deleted: false },
      local,
    );
    if (data) await store.put(data);
    await db.syncRevs.put({
      table: entry.table,
      id: entry.id,
      companyId,
      rev: remote.rev,
      ...(entry.table === 'companies' && data ? { base: data } : {}),
    });
  });
  return outcome;
}

/* -------------------------------------------------------------------------- */
/* Leaving the cloud                                                          */
/* -------------------------------------------------------------------------- */

/**
 * Deletes the company in the cloud (owners): first the server confirms the
 * person is still the owner (and stops new uploads), then its files go, then
 * the company with everything in it, then this device's copy. Nothing is
 * removed when the person is no longer the owner.
 */
export async function deleteFromCloud(companyId: string, ctx: SyncContext): Promise<void> {
  // It holds the sync lock: no request may keep it waiting for ever.
  const api = guardedApi(ctx);
  await withSyncLock(companyId, async () => {
    try {
      if (!(await api.beginDeleteCompany(companyId))) {
        // An older server: ask it for the person's role before removing anything.
        const role = (await api.myCompanies()).find((c) => c.id === companyId)?.role;
        if (role !== 'owner') {
          throw new CloudError('permission', t('Only the owner can delete the company.'));
        }
      }
      for (let round = 0; ; round += 1) {
        const files = await api.listFiles(companyId);
        if (files.length === 0) break;
        if (round === 3) {
          throw new CloudError(
            'server',
            t('Some files could not be removed from the cloud. Try again.'),
          );
        }
        for (let i = 0; i < files.length; i += 100) {
          await api.removeFiles(files.slice(i, i + 100).map((file) => file.path));
        }
      }
      await api.deleteCompany(companyId);
    } catch (error) {
      throw cloudError(error);
    }
    await db.fileQueue.where('companyId').equals(companyId).delete();
    const { deleteCompany } = await import('@/db/records');
    // Gone from the cloud: changes not sent yet have nowhere to go.
    await deleteCompany(companyId, { force: true });
  });
}

/** Stops syncing a company here and keeps this device's copy as a local company. */
export async function keepAsLocal(companyId: string): Promise<void> {
  await db.transaction('rw', [db.syncState, db.outbox, db.syncRevs], () =>
    forgetCloudLink(companyId),
  );
}
