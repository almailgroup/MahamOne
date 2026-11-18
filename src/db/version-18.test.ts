import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import Dexie from 'dexie';
import { db, DATA_TABLES, InvoiceDatabase } from './db';
import { exportBackup, importBackup, parseBackup, summarizeBackup } from './backup';
import { setupCompany } from './records';
import type { StockIssue } from './types';

/**
 * Database version 18: items issued to employees (uniforms from a
 * sub-warehouse), empty until someone issues items. A device's data from
 * version 17 is kept, and backups made before it still restore. Invented
 * names only.
 */

const NAME = 'version-17-device';

/** The tables and indexes of version 17, as the version before this one left them. */
const VERSION_17 = {
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
  staffingCostings: 'id, companyId, clientId, quoteId, status',
  outbox: '++seq, companyId, [companyId+parked], [table+id]',
  syncState: 'companyId',
  syncRevs: '[table+id], companyId',
  fileQueue: '++seq, companyId',
};

/** The synced tables of version 17, as a link noted them when it pulled. */
const V17_DATA_TABLES = DATA_TABLES.filter((name) => name !== 'stockIssues');

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

/** A device on version 17 with a warehouse, a costing and a cloud link. */
async function version17Device(): Promise<void> {
  const old = new Dexie(NAME);
  old.version(17).stores(VERSION_17);
  await old.open();
  await old.table('companies').put({ id: 'co-1', name: 'Test Guarding' });
  await old.table('warehouses').put({ id: 'wh-1', companyId: 'co-1', name: 'Main store' });
  await old.table('staffingCostings').put({ id: 'cost-1', companyId: 'co-1', status: 'draft' });
  await old
    .table('syncState')
    .put({ companyId: 'co-1', userId: 'u-1', cursor: 42, tables: [...V17_DATA_TABLES] });
  await old.table('outbox').add({ companyId: 'co-1', table: 'warehouses', id: 'wh-1', parked: 0 });
  old.close();
}

const issued = (companyId: string, extra: Partial<StockIssue> = {}): StockIssue => ({
  id: 'iss-1',
  companyId,
  number: 'ISS-0001',
  date: '2026-11-03',
  warehouseId: 'wh-2',
  recipient: {
    employeeId: 'emp-1',
    number: 'E-0001',
    name: 'Made-up Guard',
    jobTitle: 'Security Guard',
  },
  issuedBy: null,
  issuedByName: 'Made-up Keeper',
  requestId: null,
  approvedBy: null,
  approvedByName: '',
  approvedAt: null,
  lines: [{ id: 'l1', productId: 'p-1', name: 'Trouser', unit: 'pcs', quantity: 1 }],
  notes: '',
  status: 'posted',
  createdAt: '2026-11-03T08:00:00.000Z',
  updatedAt: '2026-11-03T08:00:00.000Z',
  ...extra,
});

describe('version 17 → 18', () => {
  it('keeps every record, change waiting to be sent and link', async () => {
    await version17Device();
    opened = new InvoiceDatabase(NAME);
    await opened.open();
    expect(opened.verno).toBeGreaterThanOrEqual(18);
    expect(await opened.companies.get('co-1')).toMatchObject({ name: 'Test Guarding' });
    expect(await opened.warehouses.get('wh-1')).toMatchObject({ name: 'Main store' });
    expect(await opened.staffingCostings.count()).toBe(1);
    expect(await opened.outbox.count()).toBe(1);
    // Its tables don't have the new one, so the next sync catches it up.
    const link = await opened.syncState.get('co-1');
    expect(link).toMatchObject({ cursor: 42 });
    expect(link?.tables).not.toContain('stockIssues');
  });

  it('adds the issues table, empty, found by company, date, warehouse and employee', async () => {
    await version17Device();
    opened = new InvoiceDatabase(NAME);
    await opened.open();
    expect(await opened.stockIssues.count()).toBe(0);
    await opened.stockIssues.put(issued('co-1'));
    expect(await opened.stockIssues.where('companyId').equals('co-1').count()).toBe(1);
    expect(
      await opened.stockIssues.where('[companyId+date]').equals(['co-1', '2026-11-03']).count(),
    ).toBe(1);
    expect(await opened.stockIssues.where('warehouseId').equals('wh-2').count()).toBe(1);
    expect(await opened.stockIssues.where('recipient.employeeId').equals('emp-1').count()).toBe(1);
  });
});

describe('backups and the issues table', () => {
  it('restores a backup made before it', async () => {
    const company = await setupCompany({ name: 'Before' });
    const older = JSON.parse(JSON.stringify(await exportBackup()));
    delete older.data.stockIssues;
    await db.delete();
    await db.open();
    const parsed = parseBackup(JSON.stringify(older));
    expect(parsed.data.stockIssues).toEqual([]);
    await importBackup(parsed, 'replace');
    expect(await db.companies.get(company.id)).toMatchObject({ name: 'Before' });
    expect(summarizeBackup(parsed).stockIssues).toBe(0);
  });

  it('keeps its records', async () => {
    const company = await setupCompany({ name: 'After' });
    await db.stockIssues.put(issued(company.id));
    const text = JSON.stringify(await exportBackup(company.id));
    await db.delete();
    await db.open();
    await importBackup(parseBackup(text), 'replace');
    expect(await db.stockIssues.get('iss-1')).toMatchObject({
      number: 'ISS-0001',
      recipient: { name: 'Made-up Guard' },
    });
    expect(Object.keys(summarizeBackup(parseBackup(text)))).toEqual([...DATA_TABLES]);
  });
});
