import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import Dexie from 'dexie';
import { db, DATA_TABLES, InvoiceDatabase } from './db';
import { exportBackup, importBackup, parseBackup, summarizeBackup } from './backup';
import { setupCompany } from './records';
import type { StaffingCosting } from './types';

/**
 * Database version 17: manpower costings (#3), empty until the costing is
 * switched on. A device's data from version 16 is kept, and backups made
 * before it still restore. Invented names and amounts only.
 */

const NAME = 'version-16-device';

/** The tables and indexes of version 16, as the version before this one left them. */
const VERSION_16 = {
  companies: 'id, name',
  clients: 'id, companyId, name, number',
  products: 'id, companyId, name, [companyId+sku]',
  taxRates: 'id, companyId',
  documents:
    'id, companyId, [companyId+type], [companyId+type+number], clientId, issueDate, status, recurringId, sourceId',
  payments: 'id, companyId, clientId, date, creditId, *documentIds',
  recurring: 'id, companyId, clientId, nextIssueDate',
  activities: 'id, companyId, [companyId+at], entityId, clientId, documentId',
  meta: 'key',
  accounts: 'id, companyId, [companyId+code], [companyId+role]',
  journals: 'id, companyId, [companyId+date], [companyId+number]',
  expenses: 'id, companyId, [companyId+date], vendorId, accountId',
  attachments: 'id, companyId, ownerId, [ownerId+name], [companyId+contentMissing], docKey',
  vatReturns: 'id, companyId, [companyId+periodStart]',
  bankTransactions: 'id, companyId, accountId, date, fingerprint, importId',
  securityCheques: 'id, companyId, clientId, status',
  employees: 'id, companyId, [companyId+number], status',
  complianceDocuments: 'id, companyId, employeeId, expiryDate, clientId, vehicleId',
  renewals: 'id, companyId, documentKey, employeeId, expenseId',
  complianceMarks: 'id, companyId, [companyId+key]',
  peopleSettings: 'id, companyId',
  payRuns: 'id, companyId, [companyId+period], status',
  payrollSettings: 'id, companyId',
  leaveRecords: 'id, companyId, employeeId',
  staffLoans: 'id, companyId, employeeId',
  finalSettlements: 'id, companyId, employeeId',
  warehouses: 'id, companyId',
  stockMovements:
    'id, companyId, [companyId+productId], [companyId+date], sourceId, documentId, warehouseId',
  stockEntries: 'id, companyId, [companyId+date]',
  landedCosts: 'id, companyId, billId, targetBillId',
  assets: 'id, companyId, status, billId',
  depreciationRuns: 'id, companyId, [companyId+period]',
  yearEnds: 'id, companyId, [companyId+yearEnd]',
  chequeLayouts: 'id, companyId, bank',
  vehicles: 'id, companyId, plate',
  approvals: 'id, companyId, [companyId+status], subjectId, kind',
  letterTemplates: 'id, companyId, kind',
  employeeLetters: 'id, companyId, employeeId, [companyId+issuedOn], templateId, status',
  outbox: '++seq, companyId, [companyId+parked], [table+id]',
  syncState: 'companyId',
  syncRevs: '[table+id], companyId',
  fileQueue: '++seq, companyId',
};

/** The synced tables of version 16, as a link noted them when it pulled. */
const V16_DATA_TABLES = DATA_TABLES.filter(
  (name) => name !== 'staffingCostings' && name !== 'stockIssues',
);

let opened: InvoiceDatabase | null = null;

beforeEach(async () => {
  await db.delete();
  await db.open();
  await Dexie.delete(NAME);
});

afterEach(async () => {
  opened?.close();
  opened = null;
  await Dexie.delete(NAME);
});

/** A device on version 16 with a quote, a letter and a cloud link. */
async function version16Device(): Promise<void> {
  const old = new Dexie(NAME);
  old.version(16).stores(VERSION_16);
  await old.open();
  await old.table('companies').put({ id: 'co-1', name: 'Test Guarding' });
  await old.table('documents').put({
    id: 'qt-1',
    companyId: 'co-1',
    type: 'quote',
    number: 'QT-0001',
    clientId: 'cl-1',
    status: 'draft',
    issueDate: '2026-12-01',
  });
  await old.table('employeeLetters').put({ id: 'let-1', companyId: 'co-1', employeeId: 'e-1' });
  await old
    .table('syncState')
    .put({ companyId: 'co-1', userId: 'u-1', cursor: 42, tables: [...V16_DATA_TABLES] });
  await old.table('outbox').add({ companyId: 'co-1', table: 'documents', id: 'qt-1', parked: 0 });
  await old.table('meta').put({ key: 'currentCompanyId', value: 'co-1' });
  old.close();
}

const costing = (companyId: string, extra: Partial<StaffingCosting> = {}): StaffingCosting => ({
  id: 'cost-1',
  companyId,
  name: 'Made-up tower',
  clientId: 'cl-1',
  quoteId: 'qt-1',
  status: 'quoted',
  posts: [],
  overheadPercent: 10,
  marginPercent: 15,
  notes: '',
  createdAt: '2026-12-01T08:00:00.000Z',
  updatedAt: '2026-12-01T08:00:00.000Z',
  ...extra,
});

describe('version 16 → 17', () => {
  it('keeps every record, change waiting to be sent and link', async () => {
    await version16Device();
    opened = new InvoiceDatabase(NAME);
    await opened.open();
    expect(opened.verno).toBeGreaterThanOrEqual(17);
    expect(await opened.companies.get('co-1')).toMatchObject({ name: 'Test Guarding' });
    expect(await opened.documents.get('qt-1')).toMatchObject({ number: 'QT-0001' });
    expect(await opened.employeeLetters.count()).toBe(1);
    expect(await opened.outbox.count()).toBe(1);
    // Its tables don't have the new one, so the next sync catches it up.
    const link = await opened.syncState.get('co-1');
    expect(link).toMatchObject({ cursor: 42 });
    expect(link?.tables).not.toContain('staffingCostings');
    expect(await opened.meta.get('currentCompanyId')).toMatchObject({ value: 'co-1' });
  });

  it('adds the costings table, empty, found by company, customer, quote and status', async () => {
    await version16Device();
    opened = new InvoiceDatabase(NAME);
    await opened.open();
    expect(await opened.staffingCostings.count()).toBe(0);
    await opened.staffingCostings.put(costing('co-1'));
    expect(await opened.staffingCostings.where('companyId').equals('co-1').count()).toBe(1);
    expect(await opened.staffingCostings.where('clientId').equals('cl-1').count()).toBe(1);
    expect(await opened.staffingCostings.where('quoteId').equals('qt-1').count()).toBe(1);
    expect(await opened.staffingCostings.where('status').equals('quoted').count()).toBe(1);
    // A quote made from it keeps its id; older quotes have none.
    await opened.documents.update('qt-1', { costingId: 'cost-1' });
    expect(await opened.documents.get('qt-1')).toMatchObject({ costingId: 'cost-1' });
  });
});

describe('backups and the costings table', () => {
  it('restores a backup made before it', async () => {
    const company = await setupCompany({ name: 'Before' });
    const older = JSON.parse(JSON.stringify(await exportBackup()));
    delete older.data.staffingCostings;
    await db.delete();
    await db.open();
    const parsed = parseBackup(JSON.stringify(older));
    expect(parsed.data.staffingCostings).toEqual([]);
    await importBackup(parsed, 'replace');
    expect(await db.companies.get(company.id)).toMatchObject({ name: 'Before' });
    expect(summarizeBackup(parsed).staffingCostings).toBe(0);
  });

  it('keeps its records, and the quote’s link to them', async () => {
    const company = await setupCompany({ name: 'After' });
    await db.staffingCostings.put(costing(company.id));
    const text = JSON.stringify(await exportBackup(company.id));
    await db.delete();
    await db.open();
    await importBackup(parseBackup(text), 'replace');
    expect(await db.staffingCostings.get('cost-1')).toMatchObject({
      name: 'Made-up tower',
      quoteId: 'qt-1',
    });
    expect(Object.keys(summarizeBackup(parseBackup(text)))).toEqual([...DATA_TABLES]);
  });
});
