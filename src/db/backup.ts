import { z } from 'zod';
import { db, DATA_TABLES, setMeta, getMeta, type DataTable } from './db';
import { assertNothingUnsent, CURRENT_COMPANY_KEY, SYNC_TABLES, unsentChanges } from './records';
import { seedMissingCharts } from './chart-setup';
import { recalculateDocuments, refreshOrdersFor } from './documents';
import { rebuildStock } from './inventory';
import type { Attachment, Company, ID, Payment } from './types';
import { APP_NAME, FILE_PREFIX, suiteName } from '@/lib/brand';
import { t } from '@/i18n';
import { contentHash, dataUrlToBlob } from '@/cloud/files';
import { markRemote } from '@/cloud/outbox';
import { mergeNumbering } from '@/cloud/numbering';

export const BACKUP_FORMAT = 1;
export const LAST_BACKUP_KEY = 'lastBackupAt';

export type BackupData = Record<DataTable, Record<string, unknown>[]>;

/** A file listed in a backup without its content (it could not be downloaded from the cloud). */
export interface MissingFile {
  id: ID;
  companyId: ID;
  /** Record the file belongs to. */
  ownerId: ID;
  name: string;
  type: string;
  size: number;
}

export interface Backup {
  /** Written as the app name. Files are recognised by their structure, so
   * backups from earlier builds restore whatever they were labelled. */
  app: string;
  format: number;
  exportedAt: string;
  data: BackupData;
  /**
   * Files whose content is not in the backup: they were kept in the cloud
   * and could not be downloaded when it was made. Their records are in
   * `data.attachments`, with no content.
   */
  missingFiles?: MissingFile[];
}

const row = z.looseObject({ id: z.string().min(1) });
const ownedRow = z.looseObject({ id: z.string().min(1), companyId: z.string().min(1) });

const backupSchema = z.object({
  app: z.string().min(1),
  format: z.number().int().min(1),
  exportedAt: z.string(),
  data: z.object({
    companies: z.array(row),
    clients: z.array(ownedRow).default([]),
    products: z.array(ownedRow).default([]),
    taxRates: z.array(ownedRow).default([]),
    documents: z.array(ownedRow).default([]),
    payments: z.array(ownedRow).default([]),
    recurring: z.array(ownedRow).default([]),
    activities: z.array(ownedRow).default([]),
    accounts: z.array(ownedRow).default([]),
    journals: z.array(ownedRow).default([]),
    expenses: z.array(ownedRow).default([]),
    attachments: z.array(ownedRow).default([]),
    vatReturns: z.array(ownedRow).default([]),
    bankTransactions: z.array(ownedRow).default([]),
    employees: z.array(ownedRow).default([]),
    complianceDocuments: z.array(ownedRow).default([]),
    renewals: z.array(ownedRow).default([]),
    complianceMarks: z.array(ownedRow).default([]),
    peopleSettings: z.array(ownedRow).default([]),
    securityCheques: z.array(ownedRow).default([]),
    assets: z.array(ownedRow).default([]),
    depreciationRuns: z.array(ownedRow).default([]),
    yearEnds: z.array(ownedRow).default([]),
    payRuns: z.array(ownedRow).default([]),
    payrollSettings: z.array(ownedRow).default([]),
    leaveRecords: z.array(ownedRow).default([]),
    staffLoans: z.array(ownedRow).default([]),
    finalSettlements: z.array(ownedRow).default([]),
    warehouses: z.array(ownedRow).default([]),
    stockMovements: z.array(ownedRow).default([]),
    stockEntries: z.array(ownedRow).default([]),
    landedCosts: z.array(ownedRow).default([]),
    chequeLayouts: z.array(ownedRow).default([]),
    vehicles: z.array(ownedRow).default([]),
    approvals: z.array(ownedRow).default([]),
    letterTemplates: z.array(ownedRow).default([]),
    employeeLetters: z.array(ownedRow).default([]),
    staffingCostings: z.array(ownedRow).default([]),
    stockIssues: z.array(ownedRow).default([]),
  }),
  missingFiles: z.array(z.looseObject({ id: z.string().min(1) })).optional(),
});

export class BackupError extends Error {}

/**
 * Exports all data, or a single company with everything that belongs to it,
 * as it is on this device. Files whose content is not here (kept in the
 * cloud) go in without it and are listed in `missingFiles`; `addCloudFiles`
 * can put their content in, for the backup only.
 */
export async function exportBackup(companyId?: ID): Promise<Backup> {
  const data = {} as BackupData;
  for (const table of DATA_TABLES) {
    const rows =
      table === 'companies'
        ? await db.companies.toArray()
        : companyId
          ? await db[table].where('companyId').equals(companyId).toArray()
          : await db[table].toArray();
    data[table] = (companyId && table === 'companies'
      ? rows.filter((r) => r.id === companyId)
      : rows) as unknown as Record<string, unknown>[];
  }
  const backup: Backup = {
    app: APP_NAME,
    format: BACKUP_FORMAT,
    exportedAt: new Date().toISOString(),
    data,
  };
  listMissingFiles(backup);
  return backup;
}

/** Keeps `missingFiles` in step with the files of the backup that have no content. */
function listMissingFiles(backup: Backup): void {
  const missing = filesWithoutContent(backup).map((a): MissingFile => ({
    id: a.id,
    companyId: a.companyId,
    ownerId: a.ownerId,
    name: a.name,
    type: a.type,
    size: a.size,
  }));
  if (missing.length) backup.missingFiles = missing;
  else delete backup.missingFiles;
}

/**
 * The longest backup written as one file, in characters. A browser can't
 * hold much more than 500 million characters in one text, and a backup is
 * read back as one (restore), so it stays well under that.
 */
export const MAX_BACKUP_SIZE = 400_000_000;

/** Files of the backup whose content is not in it: kept in the cloud, not on this device. */
export function filesWithoutContent(backup: Backup): Attachment[] {
  return (backup.data.attachments as unknown as Attachment[]).filter((a) => !a.dataUrl);
}

/** Characters a file's content adds to a backup (a base64 data URL), from its size. */
export function contentSize(file: Pick<Attachment, 'size' | 'type'>): number {
  const header = `data:${file.type || 'application/octet-stream'};base64,`;
  return header.length + Math.ceil(Math.max(0, file.size || 0) / 3) * 4;
}

/** Files downloaded at the same time for a backup. */
const DOWNLOADS_AT_ONCE = 4;

/**
 * Puts the content of the backup's files kept in the cloud into the backup.
 * `download` brings one file's content as a data URL for the backup alone:
 * nothing is stored on this device (see cloud/attachments). Returns the
 * files it brought, and those it could not (offline, signed out, no longer
 * in the cloud), which stay listed in `missingFiles`.
 */
export async function addCloudFiles(
  backup: Backup,
  download: (file: Attachment) => Promise<string>,
  onProgress?: (done: number, total: number) => void,
): Promise<{ added: Attachment[]; failed: Attachment[] }> {
  // The backup's own rows: content put on them goes into the backup.
  const files = filesWithoutContent(backup);
  const added: Attachment[] = [];
  const failed: Attachment[] = [];
  let next = 0;
  let done = 0;
  onProgress?.(0, files.length);
  const worker = async () => {
    while (next < files.length) {
      const file = files[next++];
      try {
        const dataUrl = await download(file);
        if (!/^data:/.test(dataUrl)) throw new Error('No content');
        file.dataUrl = dataUrl;
        delete file.contentMissing;
        added.push(file);
      } catch {
        failed.push(file);
      }
      done += 1;
      onProgress?.(done, files.length);
    }
  };
  await Promise.all(Array.from({ length: Math.min(DOWNLOADS_AT_ONCE, files.length) }, worker));
  listMissingFiles(backup);
  return { added, failed };
}

/** Takes the content of these files out of the backup again (they stay in the cloud). */
export function dropContent(backup: Backup, files: Attachment[]): void {
  for (const file of files) {
    file.dataUrl = '';
    if (file.storagePath) file.contentMissing = 1;
  }
  listMissingFiles(backup);
}

/** Whether text can go into JSON as it is: no quote, backslash or control character. */
function plainJsonText(text: string): boolean {
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code < 0x20 || code === 0x22 || code === 0x5c) return false;
  }
  return true;
}

/** One record as JSON; a file's content is a part of its own, not copied into a longer text. */
function recordParts(table: DataTable, record: Record<string, unknown>): string[] {
  const { dataUrl } = record;
  if (table !== 'attachments' || typeof dataUrl !== 'string' || dataUrl === '') {
    return [JSON.stringify(record)];
  }
  const rest = { ...record };
  delete rest.dataUrl;
  const tail = JSON.stringify(rest);
  const content = plainJsonText(dataUrl) ? ['"', dataUrl, '"'] : [JSON.stringify(dataUrl)];
  return ['{"dataUrl":', ...content, tail === '{}' ? '}' : `,${tail.slice(1)}`];
}

/**
 * The backup file's text in parts, so that no single text holds it all (a
 * browser limits how long one text can be).
 */
export function backupParts(backup: Backup): string[] {
  const { data, missingFiles, ...head } = backup;
  const start = JSON.stringify(head);
  const parts = [start === '{}' ? '{"data":{' : `${start.slice(0, -1)},"data":{`];
  DATA_TABLES.forEach((table, i) => {
    parts.push(`${i ? ',' : ''}${JSON.stringify(table)}:[`);
    (data[table] ?? []).forEach((record, j) => {
      if (j) parts.push(',');
      parts.push(...recordParts(table, record));
    });
    parts.push(']');
  });
  parts.push('}');
  if (missingFiles?.length) parts.push(',"missingFiles":', JSON.stringify(missingFiles));
  parts.push('}');
  return parts;
}

/** Characters of the backup file, worked out without writing it. */
export function backupSize(backup: Backup): number {
  return backupParts(backup).reduce((size, part) => size + part.length, 0);
}

/** The backup as a file to download (JSON). */
export function backupFile(backup: Backup): Blob {
  return new Blob(backupParts(backup), { type: 'application/json' });
}

export function backupFileName(company?: Pick<Company, 'name'>): string {
  const stamp = new Date().toISOString().slice(0, 10);
  // Letters and digits only, so the name saves the same everywhere.
  const slug = (company?.name ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
  return `${FILE_PREFIX}-backup${slug ? `-${slug}` : ''}-${stamp}.json`;
}

export function parseBackup(text: string): Backup {
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    throw new BackupError(t('This file is not a valid backup (it is not JSON).'));
  }
  const result = backupSchema.safeParse(json);
  if (!result.success) {
    throw new BackupError(
      t('This file is not a {app} backup, or it is damaged.', { app: suiteName() }),
    );
  }
  // A version that adds tables keeps the format: their records would be
  // left out without a word.
  if (result.data.format > BACKUP_FORMAT || hasUnknownRecords(json)) {
    throw new BackupError(
      t('This backup was made by a newer version of the app. Please update first.'),
    );
  }
  return result.data as Backup;
}

/** Whether the backup has records of a table this version doesn't know. */
function hasUnknownRecords(json: unknown): boolean {
  const data = (json as { data?: Record<string, unknown> }).data ?? {};
  const known = new Set<string>(DATA_TABLES);
  return Object.entries(data).some(
    ([name, rows]) => !known.has(name) && Array.isArray(rows) && rows.length > 0,
  );
}

export function summarizeBackup(backup: Backup): Record<DataTable, number> {
  return Object.fromEntries(DATA_TABLES.map((t) => [t, backup.data[t].length])) as Record<
    DataTable,
    number
  >;
}

/** What restoring a backup on this device touches, for the screens to say before. */
export interface RestoreImpact {
  /** Changes made here that have not reached the cloud yet (Replace loses them). */
  unsent: number;
  /** Companies of the backup that this device keeps in the cloud. */
  inCloud: Company[];
}

export async function restoreImpact(backup: Backup): Promise<RestoreImpact> {
  const linked = new Set(await db.syncState.toCollection().primaryKeys());
  return {
    unsent: await unsentChanges(),
    inCloud: (backup.data.companies as unknown as Company[]).filter((c) => linked.has(c.id)),
  };
}

export interface RestoreResult {
  /** Records written from the backup. */
  added: number;
  /** Merge: records already on this device, kept as they are. */
  kept: number;
  /** Merge: files here without their content that took it from the backup. */
  filled: number;
}

type Rows = Record<string, unknown>[];
type WritableTable = {
  bulkAdd: (rows: unknown[]) => Promise<unknown>;
  bulkPut: (rows: unknown[]) => Promise<unknown>;
  where: (index: string) => {
    anyOf: (keys: string[]) => { primaryKeys: () => Promise<unknown[]> };
  };
};

/** One row per id (a damaged file may repeat one). */
function uniqueRows(rows: Rows): Rows {
  const seen = new Set<unknown>();
  return rows.filter((r) => !seen.has(r.id) && seen.add(r.id));
}

/**
 * Restores a backup.
 *
 * - "replace" deletes everything on this device first. Companies kept in the
 *   cloud stay there: this device stops syncing them (its copy becomes a
 *   company on this device only), so nothing is deleted in the cloud. It is
 *   refused while changes have not reached the cloud yet
 *   (UnsentChangesError), unless `force` is given after the person agreed.
 * - "merge" adds only the records this device doesn't have; every record
 *   already here is kept as it is. Balances of invoices and bills, order
 *   progress and stock are then worked out again where the backup's records
 *   meet this device's. For a company kept in the cloud the added records go
 *   to the team like any other change. Files here without their content
 *   (left in the cloud, or lost) take it from the backup when it is the same
 *   file (see `fillContent`).
 *
 * `sanitizeLogo` lets the caller re-encode images (it must return a safe data
 * URL or null).
 */
export async function importBackup(
  backup: Backup,
  mode: 'replace' | 'merge',
  sanitizeLogo?: (logo: string) => Promise<string | null>,
  { force = false }: { force?: boolean } = {},
): Promise<RestoreResult> {
  const companies = backup.data.companies as unknown as Company[];
  if (sanitizeLogo) {
    for (const c of companies) {
      if (c.branding?.logo) {
        try {
          c.branding.logo = await sanitizeLogo(c.branding.logo);
        } catch {
          c.branding.logo = null;
        }
      }
    }
  }
  // Merge: the backup's files that were here already, perhaps without content.
  let filesHere = new Set<unknown>();
  const result = await db.transaction(
    'rw',
    [...DATA_TABLES.map((t) => db[t]), ...SYNC_TABLES(), db.meta],
    async () => {
      const result: RestoreResult = { added: 0, kept: 0, filled: 0 };
      if (mode === 'replace') {
        await assertNothingUnsent(undefined, force);
        // The counters of the companies here: numbers given since the backup
        // was made are never given again (D12).
        const counters = new Map(
          (await db.companies.toArray()).map((c) => [c.id, c.numbering] as const),
        );
        // Companies kept in the cloud stay there: this device stops syncing them
        // before its copy is replaced, so nothing is deleted in the cloud.
        for (const table of SYNC_TABLES()) await table.clear();
        for (const table of DATA_TABLES) await db[table].clear();
        for (const table of DATA_TABLES) {
          const rows = uniqueRows(backup.data[table]);
          // Dexie's typing is per table; the rows were validated above.
          if (rows.length) await (db[table] as unknown as WritableTable).bulkPut(rows);
          result.added += rows.length;
        }
        await keepCounters(counters);
      } else {
        // A company still coming down from the cloud doesn't have all its
        // records here yet: the backup's older copies would be taken for this
        // device's changes and sent over the cloud's newer ones.
        for (const company of companies) {
          const link = await db.syncState.get(company.id);
          if (link && link.status !== 'ready') {
            throw new BackupError(
              t(
                '{company} is still coming down from the cloud. Merge the backup once it’s ready.',
                {
                  company: company.name,
                },
              ),
            );
          }
        }
        const before = new Set(await db.companies.toCollection().primaryKeys());
        const added = {} as Record<DataTable, Rows>;
        for (const table of DATA_TABLES) {
          const rows = uniqueRows(backup.data[table]);
          const store = db[table] as unknown as WritableTable;
          const here = rows.length
            ? new Set(
                await store
                  .where(':id')
                  .anyOf(rows.map((r) => String(r.id)))
                  .primaryKeys(),
              )
            : new Set<unknown>();
          added[table] = rows.filter((r) => !here.has(r.id));
          if (table === 'attachments') filesHere = here;
          if (added[table].length) await store.bulkAdd(added[table]);
          result.added += added[table].length;
          result.kept += rows.length - added[table].length;
        }
        await settleMerged(added, before);
      }
      // Backups made before accounting existed have no chart of accounts.
      await seedMissingCharts(db);
      const current = await getMeta<string | null>(CURRENT_COMPANY_KEY, null);
      const exists = current ? await db.companies.get(current) : undefined;
      if (!exists && companies[0]) await setMeta(CURRENT_COMPANY_KEY, companies[0].id);
      return result;
    },
  );
  if (filesHere.size) result.filled = await fillContent(backup, filesHere);
  return result;
}

/**
 * After a backup replaced what was here: each company that was here keeps
 * the higher of its counters and the backup's (the backup's patterns), so a
 * number given after the backup was made, and perhaps printed, isn't given
 * again. A backup restored on another device can't know them. A rule whose
 * reset was changed here since the backup keeps this device's rule: its
 * counter and the backup's count different series.
 */
async function keepCounters(counters: Map<ID, Company['numbering'] | undefined>): Promise<void> {
  for (const company of await db.companies.toArray()) {
    const here = counters.get(company.id);
    if (!here || !company.numbering) continue;
    const restored = { ...company.numbering };
    for (const key of Object.keys(restored) as (keyof typeof restored)[]) {
      const mine = here[key];
      const theirs = restored[key];
      if (mine && theirs && (mine.reset ?? '') !== (theirs.reset ?? '')) {
        Object.assign(restored, { [key]: mine });
      }
    }
    const numbering = mergeNumbering(here, restored);
    if (numbering && JSON.stringify(numbering) !== JSON.stringify(company.numbering)) {
      await db.companies.put({ ...company, numbering });
    }
  }
}

/**
 * Merge: files that are on this device without their content (left in the
 * cloud, or lost) take it from the backup when it is the same file: the
 * backup's content has the content hash of the file here, or the file here
 * has no hash to compare with. The content is what this device keeps for
 * itself, so this is not a change sent to the cloud.
 */
async function fillContent(backup: Backup, filesHere: Set<unknown>): Promise<number> {
  let filled = 0;
  for (const file of backup.data.attachments as unknown as Attachment[]) {
    if (!filesHere.has(file.id)) continue;
    const { dataUrl } = file;
    if (typeof dataUrl !== 'string' || !dataUrl.startsWith('data:')) continue;
    // One at a time: the content of the files here is not all read at once.
    const here = await db.attachments.get(file.id);
    if (!here || here.dataUrl || here.companyId !== file.companyId) continue;
    // The hash of the content itself, not the one the backup's record says.
    const hash = here.contentHash;
    if (hash && (await hashOf(dataUrl)) !== hash) continue;
    try {
      const done = await db.transaction('rw', db.attachments, async () => {
        // Content this device keeps for itself: nothing to send to the team.
        markRemote();
        const now = await db.attachments.get(file.id);
        // Changed meanwhile (downloaded, replaced): left as it is.
        if (!now || now.dataUrl || now.companyId !== here.companyId) return false;
        if (now.contentHash !== hash) return false;
        const next: Attachment = { ...now, dataUrl };
        delete next.contentMissing;
        await db.attachments.put(next);
        return true;
      });
      if (done) filled += 1;
    } catch {
      // No room for it on this device, for example: the file stays as it
      // was, and the records the merge added stay too.
    }
  }
  return filled;
}

/** The content hash of a data URL, or null when it can't be read. */
async function hashOf(dataUrl: string): Promise<string | null> {
  try {
    return await contentHash(dataUrlToBlob(dataUrl));
  } catch {
    return null;
  }
}

/** Tables whose records the stock levels and costs are worked out from. */
const STOCK_TABLES: DataTable[] = [
  'documents',
  'stockEntries',
  'stockIssues',
  'landedCosts',
  'stockMovements',
  'products',
  'warehouses',
];

/**
 * After a merge, works out again what is stored with the records it comes
 * from, for companies that were already on this device (a company that
 * arrives whole from the backup is consistent as it is): the balance and
 * status of invoices, bills and credit notes, order progress and stock.
 */
async function settleMerged(added: Record<DataTable, Rows>, before: Set<string>): Promise<void> {
  const known = (r: Record<string, unknown>) => before.has(String(r.companyId));
  const documents = new Set<ID>();
  for (const doc of added.documents) if (known(doc)) documents.add(String(doc.id));
  for (const payment of added.payments as unknown as Payment[]) {
    if (!before.has(payment.companyId)) continue;
    for (const id of payment.documentIds ?? []) documents.add(id);
    for (const allocation of payment.allocations ?? []) documents.add(allocation.documentId);
    if (payment.creditId) documents.add(payment.creditId);
  }
  if (documents.size) {
    await recalculateDocuments(documents);
    await refreshOrdersFor(documents);
  }
  const stock = new Set<ID>();
  for (const table of STOCK_TABLES) {
    for (const r of added[table]) if (known(r)) stock.add(String(r.companyId));
  }
  for (const companyId of stock) {
    if (await keepsStock(companyId)) await rebuildStock(companyId);
  }
}

/** Whether the company has stock to keep in step (stock items or movements). */
async function keepsStock(companyId: ID): Promise<boolean> {
  if ((await db.stockMovements.where('companyId').equals(companyId).count()) > 0) return true;
  return (
    (await db.products
      .where('companyId')
      .equals(companyId)
      .filter((p) => p.kind === 'stock')
      .count()) > 0
  );
}

export async function markBackedUp(): Promise<void> {
  await setMeta(LAST_BACKUP_KEY, new Date().toISOString());
}

/**
 * Removes every record (all companies) from this browser. Companies kept in
 * the cloud stay there; this device just stops syncing them. Refused while
 * changes have not reached the cloud yet (UnsentChangesError), unless
 * `force` is given after the person agreed to lose them.
 */
export async function wipeAllData({ force = false }: { force?: boolean } = {}): Promise<void> {
  await db.transaction(
    'rw',
    [...DATA_TABLES.map((t) => db[t]), ...SYNC_TABLES(), db.meta],
    async () => {
      await assertNothingUnsent(undefined, force);
      for (const table of SYNC_TABLES()) await table.clear();
      for (const table of DATA_TABLES) await db[table].clear();
      await db.meta.clear();
    },
  );
}
