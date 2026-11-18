import Dexie, { type Table } from 'dexie';
import type {
  Account,
  Activity,
  Attachment,
  Client,
  Expense,
  Company,
  InvoiceDocument,
  KeyValue,
  ManualJournal,
  Payment,
  Product,
  RecurringProfile,
  TaxRate,
  VatReturnRecord,
  BankTransaction,
  ComplianceDocument,
  ComplianceMark,
  DocumentRenewal,
  Employee,
  PeopleSettings,
  SecurityCheque,
  FixedAsset,
  DepreciationRun,
  YearEndClose,
  PayRun,
  PayrollSettings,
  LeaveRecord,
  StaffLoan,
  FinalSettlement,
  Warehouse,
  StockMovement,
  StockEntry,
  LandedCost,
  ChequeLayout,
  Vehicle,
  ApprovalRequest,
  LetterTemplate,
  EmployeeLetter,
  StaffingCosting,
  StockIssue,
} from './types';
import { DATABASE_NAME } from '@/lib/brand';
import { seedMissingCharts } from './chart-setup';
import { outboxMiddleware } from '@/cloud/outbox';
import type { CloudLink, FileTask, OutboxEntry, SyncRev } from '@/cloud/types';

/**
 * All data lives in the browser's IndexedDB, so the app works offline and
 * runs from any static host.
 */
export class InvoiceDatabase extends Dexie {
  companies!: Table<Company, string>;
  clients!: Table<Client, string>;
  products!: Table<Product, string>;
  taxRates!: Table<TaxRate, string>;
  documents!: Table<InvoiceDocument, string>;
  payments!: Table<Payment, string>;
  recurring!: Table<RecurringProfile, string>;
  activities!: Table<Activity, string>;
  accounts!: Table<Account, string>;
  journals!: Table<ManualJournal, string>;
  expenses!: Table<Expense, string>;
  attachments!: Table<Attachment, string>;
  vatReturns!: Table<VatReturnRecord, string>;
  bankTransactions!: Table<BankTransaction, string>;
  employees!: Table<Employee, string>;
  complianceDocuments!: Table<ComplianceDocument, string>;
  renewals!: Table<DocumentRenewal, string>;
  complianceMarks!: Table<ComplianceMark, string>;
  peopleSettings!: Table<PeopleSettings, string>;
  securityCheques!: Table<SecurityCheque, string>;
  assets!: Table<FixedAsset, string>;
  depreciationRuns!: Table<DepreciationRun, string>;
  yearEnds!: Table<YearEndClose, string>;
  payRuns!: Table<PayRun, string>;
  payrollSettings!: Table<PayrollSettings, string>;
  leaveRecords!: Table<LeaveRecord, string>;
  staffLoans!: Table<StaffLoan, string>;
  finalSettlements!: Table<FinalSettlement, string>;
  warehouses!: Table<Warehouse, string>;
  stockMovements!: Table<StockMovement, string>;
  stockEntries!: Table<StockEntry, string>;
  landedCosts!: Table<LandedCost, string>;
  chequeLayouts!: Table<ChequeLayout, string>;
  vehicles!: Table<Vehicle, string>;
  approvals!: Table<ApprovalRequest, string>;
  letterTemplates!: Table<LetterTemplate, string>;
  employeeLetters!: Table<EmployeeLetter, string>;
  staffingCostings!: Table<StaffingCosting, string>;
  stockIssues!: Table<StockIssue, string>;
  meta!: Table<KeyValue, string>;
  // Cloud sync bookkeeping (see src/cloud): never exported or restored.
  outbox!: Table<OutboxEntry, number>;
  syncState!: Table<CloudLink, string>;
  syncRevs!: Table<SyncRev, [string, string]>;
  fileQueue!: Table<FileTask, number>;

  constructor(name = DATABASE_NAME) {
    super(name);
    this.version(1).stores({
      companies: 'id, name',
      clients: 'id, companyId, name, number',
      products: 'id, companyId, name',
      taxRates: 'id, companyId',
      documents:
        'id, companyId, [companyId+type], [companyId+type+number], clientId, issueDate, status, recurringId',
      payments: 'id, companyId, clientId, date, creditId, *documentIds',
      recurring: 'id, companyId, clientId, nextIssueDate',
      activities: 'id, companyId, [companyId+at], entityId, clientId, documentId',
      meta: 'key',
    });
    // Accounting: chart of accounts and manual journals.
    this.version(2).stores({
      accounts: 'id, companyId, [companyId+code], [companyId+role]',
      journals: 'id, companyId, [companyId+date], [companyId+number]',
    });
    // Purchases: expenses and receipt attachments.
    this.version(3).stores({
      expenses: 'id, companyId, [companyId+date], vendorId, accountId',
      attachments: 'id, companyId, ownerId',
    });
    // VAT returns as filed.
    this.version(4).stores({
      vatReturns: 'id, companyId, [companyId+periodStart]',
    });
    // Imported bank statements.
    this.version(5).stores({
      bankTransactions: 'id, companyId, accountId, date, fingerprint, importId',
    });
    // Security (guarantee) cheques, kept off the ledger.
    this.version(6).stores({
      securityCheques: 'id, companyId, clientId, status',
    });
    // People and compliance: employees, the documents register and statutory deadlines.
    this.version(7).stores({
      employees: 'id, companyId, [companyId+number], status',
      complianceDocuments: 'id, companyId, employeeId, expiryDate',
      renewals: 'id, companyId, documentKey, employeeId, expenseId',
      complianceMarks: 'id, companyId, [companyId+key]',
      peopleSettings: 'id, companyId',
    });
    // Payroll: pay runs, leave, staff loans and final settlements.
    this.version(8).stores({
      payRuns: 'id, companyId, [companyId+period], status',
      payrollSettings: 'id, companyId',
      leaveRecords: 'id, companyId, employeeId',
      staffLoans: 'id, companyId, employeeId',
      finalSettlements: 'id, companyId, employeeId',
    });
    // Inventory: warehouses, stock movements, stock entries and landed costs.
    this.version(9).stores({
      warehouses: 'id, companyId',
      stockMovements:
        'id, companyId, [companyId+productId], [companyId+date], sourceId, documentId, warehouseId',
      stockEntries: 'id, companyId, [companyId+date]',
      landedCosts: 'id, companyId, billId, targetBillId',
    });
    // Fixed asset register, monthly depreciation runs and closed financial years.
    this.version(10).stores({
      assets: 'id, companyId, status, billId',
      depreciationRuns: 'id, companyId, [companyId+period]',
      yearEnds: 'id, companyId, [companyId+yearEnd]',
    });
    // Orders: a sales or purchase order finds the invoices, bills and delivery
    // notes created from it by their source.
    this.version(13).stores({
      documents:
        'id, companyId, [companyId+type], [companyId+type+number], clientId, issueDate, status, recurringId, sourceId',
    });
    // Cloud: companies kept in the cloud, changes waiting to be sent, the
    // server version of each record and files waiting to be removed.
    this.version(14).stores({
      outbox: '++seq, companyId, [companyId+parked], [table+id]',
      syncState: 'companyId',
      syncRevs: '[table+id], companyId',
      fileQueue: '++seq, companyId',
    });
    // Attachments found by owner and name, and those whose content is still
    // in the cloud, without reading every file.
    this.version(15).stores({
      attachments: 'id, companyId, ownerId, [ownerId+name], [companyId+contentMissing]',
    });
    // Cheque layouts, vehicles, approval requests and employee letters (empty
    // until the features that write them are switched on), and finding
    // register papers by customer or vehicle, items by SKU and files by what
    // they are a copy of.
    this.version(16).stores({
      chequeLayouts: 'id, companyId, bank',
      vehicles: 'id, companyId, plate',
      approvals: 'id, companyId, [companyId+status], subjectId, kind',
      letterTemplates: 'id, companyId, kind',
      employeeLetters: 'id, companyId, employeeId, [companyId+issuedOn], templateId, status',
      complianceDocuments: 'id, companyId, employeeId, expiryDate, clientId, vehicleId',
      products: 'id, companyId, name, [companyId+sku]',
      attachments: 'id, companyId, ownerId, [ownerId+name], [companyId+contentMissing], docKey',
    });
    // Manpower costings of Maham People (#3), empty until the costing is
    // switched on.
    this.version(17).stores({
      staffingCostings: 'id, companyId, clientId, quoteId, status',
    });
    // Items issued from a warehouse to employees (uniforms, shoes, badges),
    // kept once an approver confirms them.
    this.version(18).stores({
      stockIssues: 'id, companyId, [companyId+date], warehouseId, recipient.employeeId',
    });
    // Every change to a company kept in the cloud is queued for the server.
    this.use(outboxMiddleware(DATA_TABLES));
  }
}

export const DATA_TABLES = [
  'companies',
  'clients',
  'products',
  'taxRates',
  'documents',
  'payments',
  'recurring',
  'activities',
  'accounts',
  'journals',
  'expenses',
  'attachments',
  'vatReturns',
  'bankTransactions',
  'employees',
  'complianceDocuments',
  'renewals',
  'complianceMarks',
  'peopleSettings',
  'securityCheques',
  'assets',
  'depreciationRuns',
  'yearEnds',
  'payRuns',
  'payrollSettings',
  'leaveRecords',
  'staffLoans',
  'finalSettlements',
  'warehouses',
  'stockMovements',
  'stockEntries',
  'landedCosts',
  'chequeLayouts',
  'vehicles',
  'approvals',
  'letterTemplates',
  'employeeLetters',
  'staffingCostings',
  'stockIssues',
] as const;

export type DataTable = (typeof DATA_TABLES)[number];

const ALL_TABLES: string[] = [...DATA_TABLES, 'meta'];
/** Tables every build of the app has had; used to recognise its databases. */
const CORE_TABLES = ['companies', 'clients', 'documents', 'payments', 'meta'];

/**
 * Data saved by an earlier build may sit in a database with another name
 * (the database is named after the app). When this database has no company
 * yet, the first database on this site with the same tables and some data is
 * copied in and then deleted.
 */
async function adoptEarlierDatabase(target: Dexie): Promise<void> {
  if (typeof indexedDB === 'undefined' || typeof indexedDB.databases !== 'function') return;
  if ((await target.table('companies').count()) > 0) return;
  const names = (await indexedDB.databases())
    .map((info) => info.name)
    .filter((name): name is string => Boolean(name) && name !== target.name);
  for (const name of names) {
    const earlier = new Dexie(name);
    try {
      await earlier.open();
      const tables = new Set(earlier.tables.map((table) => table.name));
      if (!CORE_TABLES.every((table) => tables.has(table))) continue;
      if ((await earlier.table('companies').count()) === 0) continue;
      const copied = ALL_TABLES.filter((table) => tables.has(table));
      const rows = await Promise.all(copied.map((table) => earlier.table(table).toArray()));
      await target.transaction('rw', ALL_TABLES, async () => {
        for (const [i, table] of copied.entries()) await target.table(table).bulkPut(rows[i]);
      });
      earlier.close();
      // Not awaited: a tab still running the earlier build delays the delete.
      void Dexie.delete(name).catch(() => undefined);
      return;
    } catch {
      // Unreadable or not ours: leave it untouched.
    } finally {
      earlier.close();
    }
  }
}

export const db = new InvoiceDatabase();
// Runs on every open, before any other query.
db.on(
  'ready',
  async (vipDb) => {
    await adoptEarlierDatabase(vipDb);
    await vipDb.transaction('rw', ['companies', 'accounts'], () => seedMissingCharts(vipDb));
  },
  true,
);

export async function getMeta<T>(key: string, fallback: T): Promise<T> {
  const row = await db.meta.get(key);
  return row === undefined ? fallback : (row.value as T);
}

export async function setMeta(key: string, value: unknown): Promise<void> {
  await db.meta.put({ key, value });
}
