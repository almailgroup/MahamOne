// The web's own outputs for the suite's write ports (MahamKit/Write/Suite):
// the documents register, renewals and new copies, compliance marks, the
// register's extras and purposes, vehicles, the company's settings, tax
// rates and files. Every scenario runs the web's real function; the Swift
// side (Tests/MahamKitTests/WriteSuiteTests.swift) runs the port named by
// `input.fn` with the same arguments and compares every table.
//
// From the repository root:
//   npx vitest run --config ios/scripts/web-fixtures/writes.gen.config.mjs writes-suite
import { vi } from 'vitest';
vi.mock('@/lib/ids', async (load) => ({
  ...(await load<typeof import('@/lib/ids')>()),
  ...(await import('./writes-ids')).fixedIds(),
}));
// The outbox names each transaction's changes with a short id (its group),
// which takes the next fixed id at the first write of every transaction:
// this device's bookkeeping, which the iPhone's sync engine does its own way.
// Left out, so the ids count the records the web writes and nothing else.
vi.mock('@/cloud/outbox', async (load) => ({
  ...(await load<typeof import('@/cloud/outbox')>()),
  outboxMiddleware: () => ({ stack: 'dbcore', name: 'NoOutbox', create: () => ({}) }),
}));
import { scenario, writeFixtures, type Scenario, type Tables } from './writes-harness';
import { db } from '@/db/db';
import {
  addDocumentPurpose,
  addNewCopy,
  clearComplianceMark,
  deleteComplianceDocument,
  makeDocumentConfidential,
  markComplianceDone,
  markNewCopy,
  renewDocument,
  saveComplianceDocument,
  saveDocumentPurposes,
  setDocumentArchived,
  setDocumentPurposeArchived,
  setRegisterExtras,
  type RenewInput,
} from '@/db/renewals';
import { deleteVehicle, linkVehiclePapers, saveVehicle, setVehicleArchived } from '@/db/vehicles';
import { setFileFinder } from '@/db/files';
import { deleteTaxRate, saveCompany, saveTaxRate } from '@/db/records';
import { addAttachment, removeAttachment } from '@/db/purchases';
import { createClient, createCompany, createTaxRate } from '@/db/defaults';
import { chartAccounts, defaultAccountingSettings } from '@/db/chart-setup';
import { withTaxes } from '@/features/company/taxes';
import { withAppLayout } from '@/pages/settings/app-layout';
import { withAiSwitch } from '@/features/ai/availability';
import { withSameAsInvoices, withTypeDesign } from '@/pdf/template-resolve';
import { companyTypeOptions, withTidyProfile } from '@/features/company/company-types';
import type { Company, ComplianceDocument, Vehicle } from '@/db/types';

const NOW = '2026-11-28T09:00:00.000Z';
const OLD = '2026-01-05T08:00:00.000Z';
const CO = 'co-1';
const USER = { userId: 'u-1', userName: 'Sample Owner' };

/** Renewals' scenarios have the chart of accounts; the others leave it out (smaller fixtures). */
let withChart = false;

/** A Kuwaiti company, with its chart (accounts named acc-<code>) while `withChart`. */
function kuwaitCompany(overrides: Partial<Company> = {}): Tables {
  const company = createCompany({
    id: CO,
    name: 'Blue Harbour Trading',
    nameAr: 'الميناء الأزرق للتجارة',
    createdAt: OLD,
    updatedAt: OLD,
    ...overrides,
  });
  company.accounting = overrides.accounting ?? defaultAccountingSettings(company.address.country);
  const accounts = chartAccounts(CO, company.accounting.template).map((a) => ({
    ...a,
    id: `acc-${a.code}`,
    createdAt: OLD,
    updatedAt: OLD,
  }));
  return withChart ? { companies: [company], accounts } : { companies: [company] };
}

function employee(id: string, overrides: Record<string, unknown> = {}) {
  return {
    id,
    companyId: CO,
    number: 'E-001',
    name: 'Ravi Kumar',
    nameAr: 'رافي كومار',
    nationality: 'IN',
    category: 'expat',
    status: 'active',
    civilId: '290010112345',
    passportNumber: 'P111',
    passportExpiry: '2026-12-03',
    residencyNumber: '18/2024/55',
    residencyExpiry: '2026-12-18',
    photoId: null,
    createdAt: OLD,
    updatedAt: OLD,
    ...overrides,
  };
}

function doc(id: string, overrides: Partial<ComplianceDocument> = {}): ComplianceDocument {
  return {
    id,
    companyId: CO,
    type: 'commercial_licence',
    title: '',
    number: 'CL-1',
    issuer: '',
    issueDate: '2025-01-10',
    expiryDate: '2026-12-28',
    renewalCost: 0,
    reminderDays: null,
    ownerType: 'company',
    employeeId: null,
    ownerName: '',
    notes: '',
    archived: false,
    createdAt: OLD,
    updatedAt: OLD,
    ...overrides,
  };
}

function vehicle(id: string, plate: string, overrides: Partial<Vehicle> = {}): Vehicle {
  return {
    id,
    companyId: CO,
    plate,
    make: 'Toyota',
    model: 'Hiace',
    year: 2022,
    chassisNumber: '',
    assetId: null,
    driverEmployeeId: null,
    notes: '',
    archived: false,
    createdAt: OLD,
    updatedAt: OLD,
    ...overrides,
  };
}

function file(id: string, ownerId: string, overrides: Record<string, unknown> = {}) {
  return {
    id,
    companyId: CO,
    ownerId,
    name: 'scan.pdf',
    type: 'application/pdf',
    size: 12,
    dataUrl: 'data:application/pdf;base64,AAAA',
    createdAt: OLD,
    ...overrides,
  };
}

function activity(id: string, entityId: string, overrides: Record<string, unknown> = {}) {
  return {
    id,
    companyId: CO,
    at: OLD,
    entity: 'compliance',
    entityId,
    clientId: null,
    documentId: null,
    action: 'created',
    message: 'Document added',
    ...overrides,
  };
}

/** The company's link to the cloud, with what its server has. */
function cloudLink(features: string[]) {
  return {
    companyId: CO,
    userId: 'u-1',
    role: 'owner',
    status: 'ready',
    cursor: 0,
    name: 'Blue Harbour Trading',
    linkedAt: OLD,
    lastSyncAt: null,
    lastError: null,
    lastErrorAt: null,
    features,
  };
}

function merge(...parts: Tables[]): Tables {
  const out: Tables = {};
  for (const part of parts) {
    for (const [table, rows] of Object.entries(part)) out[table] = [...(out[table] ?? []), ...rows];
  }
  return out;
}

const SYNC = ['syncState', 'outbox', 'syncRevs'];

/**
 * One scenario. `cloud` keeps the company in the cloud (with these server
 * features); the link and the outbox are this device's bookkeeping, left
 * out of the tables compared.
 */
async function run(
  name: string,
  before: Tables,
  input: Record<string, unknown>,
  action: () => Promise<unknown>,
  options: { cloud?: string[]; now?: string } = {},
): Promise<Scenario> {
  const tables = options.cloud ? merge(before, { syncState: [cloudLink(options.cloud)] }) : before;
  const s = await scenario(
    name,
    { now: options.now ?? NOW, before: tables, input: { ...input, cloud: options.cloud ?? null }, ...USER },
    action,
  );
  for (const table of SYNC) {
    delete s.before[table];
    delete s.after[table];
  }
  return s;
}

const out: Scenario[] = [];
const V16 = ['tables_v16'];

it('suite', async () => {
  const base = () => kuwaitCompany();
  const extras = () => kuwaitCompany({ registerExtras: true } as Partial<Company>);

  // ---------------------------------------------------------------------- //
  // The documents register

  const licence = doc('00000f01-0000-4000-8000-000000000000', {
    title: '  Main licence ',
    number: ' CL-77 ',
    issuer: ' MOCI ',
    renewalCost: 12.34567,
    reminderDays: [7, 30, 30, 0, 60],
    createdAt: NOW,
    updatedAt: NOW,
  });
  out.push(
    await run('adds a commercial licence, tidied', base(), { fn: 'saveDocument', doc: licence }, () =>
      saveComplianceDocument(licence),
    ),
  );
  {
    const stored = doc('d-1');
    const edited = { ...stored, number: 'CL-2', notes: 'Renewed early', reminderDays: [] };
    out.push(
      await run(
        'edits a document',
        merge(base(), { complianceDocuments: [stored] }),
        { fn: 'saveDocument', doc: edited },
        () => saveComplianceDocument(edited),
      ),
    );
  }
  {
    const bad = doc('d-2', { issueDate: '2026-05-01', expiryDate: '2026-04-01' });
    out.push(
      await run('refuses an expiry before the issue date', base(), { fn: 'saveDocument', doc: bad }, () =>
        saveComplianceDocument(bad),
      ),
    );
    const civil = doc('d-3', { type: 'civil_id', ownerType: 'employee', employeeId: 'emp-1' });
    out.push(
      await run(
        'refuses an employee’s own paper',
        merge(base(), { employees: [employee('emp-1')] }),
        { fn: 'saveDocument', doc: civil },
        () => saveComplianceDocument(civil),
      ),
    );
    const nobody = doc('d-4', { type: 'health_insurance', ownerType: 'employee', employeeId: 'emp-9' });
    out.push(
      await run('refuses an employee of another company', base(), { fn: 'saveDocument', doc: nobody }, () =>
        saveComplianceDocument(nobody),
      ),
    );
    const insurance = doc('d-5', {
      type: 'health_insurance',
      ownerType: 'employee',
      employeeId: 'emp-1',
      ownerName: 'kept?',
    });
    out.push(
      await run(
        'keeps an employee’s health insurance, logged as theirs',
        merge(base(), { employees: [employee('emp-1')] }),
        { fn: 'saveDocument', doc: insurance },
        () => saveComplianceDocument(insurance),
      ),
    );
  }
  {
    const client = { ...createClient(CO, { name: 'Gulf Star Hotel' }), id: 'cl-1', createdAt: OLD, updatedAt: OLD };
    const contract = doc('d-6', {
      type: 'client_contract',
      ownerType: 'other',
      clientId: 'cl-1',
      title: 'Guarding contract',
      ownerName: '',
    });
    out.push(
      await run(
        'keeps a customer’s paper under Other with the customer’s name',
        merge(extras(), { clients: [client] }),
        { fn: 'saveDocument', doc: contract },
        () => saveComplianceDocument(contract),
      ),
    );
    const noCustomer = doc('d-7', { type: 'client_contract', ownerType: 'other', title: 'X', clientId: null });
    out.push(
      await run('refuses a customer contract without its customer', extras(), { fn: 'saveDocument', doc: noCustomer }, () =>
        saveComplianceDocument(noCustomer),
      ),
    );
    const untitled = doc('d-8', { type: 'company_contract', title: '  ' });
    out.push(
      await run('asks for a contract’s title', extras(), { fn: 'saveDocument', doc: untitled }, () =>
        saveComplianceDocument(untitled),
      ),
    );
    const otherCompany = doc('d-9', { type: 'other', ownerType: 'other', clientId: 'cl-x' });
    out.push(
      await run('refuses another company’s customer', extras(), { fn: 'saveDocument', doc: otherCompany }, () =>
        saveComplianceDocument(otherCompany),
      ),
    );
  }
  {
    const van = vehicle('veh-1', '12/34567');
    const registration = doc('d-10', {
      type: 'vehicle_registration',
      ownerType: 'vehicle',
      vehicleId: 'veh-1',
      ownerName: 'old name',
      licenceClass: 'B',
    });
    out.push(
      await run(
        'keeps a vehicle’s paper with its plate',
        merge(extras(), { vehicles: [van] }),
        { fn: 'saveDocument', doc: registration },
        () => saveComplianceDocument(registration),
      ),
    );
    const plateless = doc('d-11', { type: 'vehicle_insurance', ownerType: 'vehicle', ownerName: ' ' });
    out.push(
      await run('asks for the vehicle’s plate', base(), { fn: 'saveDocument', doc: plateless }, () =>
        saveComplianceDocument(plateless),
      ),
    );
    const driving = doc('d-12', {
      type: 'driving_licence',
      ownerType: 'employee',
      employeeId: 'emp-1',
      licenceClass: ' Light ',
      purposeId: 'p-1',
    });
    const purposes = kuwaitCompany({
      registerExtras: true,
      documentPurposes: [{ id: 'p-1', name: 'Tender', nameAr: 'مناقصة' }],
    } as Partial<Company>);
    out.push(
      await run(
        'keeps a driving licence’s class and its purpose',
        merge(purposes, { employees: [employee('emp-1')] }),
        { fn: 'saveDocument', doc: driving },
        () => saveComplianceDocument(driving),
      ),
    );
    const unknownPurpose = doc('d-13', { purposeId: 'p-9' });
    out.push(
      await run('refuses a purpose not on the list', purposes, { fn: 'saveDocument', doc: unknownPurpose }, () =>
        saveComplianceDocument(unknownPurpose),
      ),
    );
  }
  {
    const sheet = doc('d-14', {
      type: 'customer_cost',
      ownerType: 'other',
      clientId: 'cl-1',
      title: 'Guards’ pay',
      confidential: true,
    });
    const client = { ...createClient(CO, { name: 'Gulf Star Hotel' }), id: 'cl-1', createdAt: OLD, updatedAt: OLD };
    out.push(
      await run(
        'waits for the server to keep a cost sheet confidential',
        merge(extras(), { clients: [client] }),
        { fn: 'saveDocument', doc: sheet },
        () => saveComplianceDocument(sheet),
        { cloud: [] },
      ),
    );
    out.push(
      await run(
        'adds a confidential cost sheet in the cloud',
        merge(extras(), { clients: [client] }),
        { fn: 'saveDocument', doc: sheet },
        () => saveComplianceDocument(sheet),
        { cloud: V16 },
      ),
    );
    const stored = doc('d-15');
    out.push(
      await run(
        'refuses to save a document in the cloud with the mark',
        merge(extras(), { complianceDocuments: [stored] }),
        { fn: 'saveDocument', doc: { ...stored, confidential: true } },
        () => saveComplianceDocument({ ...stored, confidential: true }),
        { cloud: V16 },
      ),
    );
  }
  {
    // On this device only: saved with the mark, its fees lose its details.
    const stored = doc('d-16', { number: 'CL-16', title: 'Head office licence' });
    const renewal = {
      id: 'r-16',
      companyId: CO,
      documentKey: 'doc:d-16',
      documentId: 'd-16',
      employeeId: null,
      type: 'commercial_licence',
      renewedOn: '2026-01-10',
      previousExpiry: '2026-01-15',
      newExpiry: '2026-12-28',
      fee: 120,
      expenseId: 'x-16',
      note: 'Paid at MOCI',
      number: 'CL-15',
      createdAt: OLD,
    };
    const expense = {
      id: 'x-16',
      companyId: CO,
      number: 'EXP-2026-0001',
      date: '2026-01-10',
      vendorId: null,
      accountId: 'acc-6100',
      description: 'Head office licence renewal',
      amount: 120,
      taxes: [],
      currency: 'KWD',
      paidFromAccountId: null,
      reference: 'CL-15',
      notes: 'Paid at MOCI',
      createdAt: OLD,
      updatedAt: OLD,
    };
    out.push(
      await run(
        'marks a document confidential on this device, its fees without its details',
        merge(extras(), { complianceDocuments: [stored], renewals: [renewal], expenses: [expense] }),
        { fn: 'saveDocument', doc: { ...stored, confidential: true } },
        () => saveComplianceDocument({ ...stored, confidential: true }),
      ),
    );
    out.push(
      await run(
        'makes a document confidential on this device',
        merge(extras(), { complianceDocuments: [stored], renewals: [renewal], expenses: [expense] }),
        { fn: 'makeConfidential', doc: { ...stored, notes: 'Private' }, removedFiles: [] },
        () => makeDocumentConfidential({ ...stored, notes: 'Private' }),
      ),
    );
    out.push(
      await run(
        'makes a document confidential in the cloud under new ids',
        merge(extras(), {
          complianceDocuments: [stored],
          renewals: [{ ...renewal, newCopyId: 'f-2' }],
          expenses: [expense],
          attachments: [
            file('f-1', 'd-16'),
            file('f-2', 'd-16', { docKey: 'doc:d-16', validUntil: '2026-12-28', storagePath: 'co-1/f-2', contentHash: 'h' }),
            file('f-3', 'r-16'),
            file('f-4', 'd-16'),
          ],
          activities: [activity('a-1', 'd-16'), activity('a-2', 'r-16', { action: 'renewed' })],
        }),
        { fn: 'makeConfidential', doc: { ...stored, title: 'Head office licence (private)' }, removedFiles: ['f-4'] },
        () =>
          makeDocumentConfidential({ ...stored, title: 'Head office licence (private)' }, { removedFiles: ['f-4'] }),
        { cloud: V16 },
      ),
    );
    out.push(
      await run(
        'waits for files kept in the cloud only',
        merge(extras(), {
          complianceDocuments: [stored],
          attachments: [file('f-1', 'd-16', { dataUrl: '', storagePath: 'co-1/f-1', contentMissing: 1 })],
        }),
        { fn: 'makeConfidential', doc: stored, removedFiles: [] },
        () => makeDocumentConfidential(stored),
        { cloud: V16 },
      ),
    );
  }
  {
    const stored = doc('d-17', { employeeId: null });
    out.push(
      await run(
        'archives a document',
        merge(base(), { complianceDocuments: [stored] }),
        { fn: 'setArchived', id: 'd-17', archived: true },
        () => setDocumentArchived('d-17', true),
      ),
    );
    out.push(
      await run(
        'restores a document',
        merge(base(), { complianceDocuments: [{ ...stored, archived: true }] }),
        { fn: 'setArchived', id: 'd-17', archived: false },
        () => setDocumentArchived('d-17', false),
      ),
    );
    out.push(
      await run(
        'deletes a document with its files',
        merge(base(), {
          complianceDocuments: [stored],
          attachments: [file('f-5', 'd-17'), file('f-6', 'other')],
        }),
        { fn: 'deleteDocument', id: 'd-17' },
        () => deleteComplianceDocument('d-17'),
      ),
    );
    out.push(
      await run(
        'keeps a renewed document',
        merge(base(), {
          complianceDocuments: [stored],
          renewals: [
            {
              id: 'r-17',
              companyId: CO,
              documentKey: 'doc:d-17',
              documentId: 'd-17',
              employeeId: null,
              type: 'commercial_licence',
              renewedOn: '2026-01-10',
              previousExpiry: null,
              newExpiry: '2026-12-28',
              fee: 0,
              expenseId: null,
              note: '',
              number: 'CL-1',
              createdAt: OLD,
            },
          ],
        }),
        { fn: 'deleteDocument', id: 'd-17' },
        () => deleteComplianceDocument('d-17'),
      ),
    );
    out.push(
      await run(
        'deletes a confidential document, its activity marked private',
        merge(extras(), {
          complianceDocuments: [{ ...stored, confidential: true }],
          activities: [activity('a-3', 'd-17'), activity('a-4', 'd-17', { confidential: true })],
        }),
        { fn: 'deleteDocument', id: 'd-17' },
        () => deleteComplianceDocument('d-17'),
      ),
    );
    out.push(
      await run('does nothing for a document that is gone', base(), { fn: 'deleteDocument', id: 'd-404' }, () =>
        deleteComplianceDocument('d-404'),
      ),
    );
  }

  // ---------------------------------------------------------------------- //
  // Marks, extras and purposes

  out.push(
    await run(
      'marks a deadline as done',
      base(),
      { fn: 'markDone', key: 'pifss:2026-11', label: 'PIFSS contributions for November' },
      () => markComplianceDone(CO, 'pifss:2026-11', { label: 'PIFSS contributions for November' }),
    ),
  );
  out.push(
    await run(
      'marks a deadline done on a day, with a note',
      base(),
      { fn: 'markDone', key: 'audit:2025-12-31', doneOn: '2026-03-30', note: '  Filed by the auditor ' },
      () => markComplianceDone(CO, 'audit:2025-12-31', { doneOn: '2026-03-30', note: '  Filed by the auditor ' }),
    ),
  );
  {
    const mark = { id: `${CO}:pifss:2026-11`, companyId: CO, key: 'pifss:2026-11', doneOn: '2026-11-15', note: '', createdAt: OLD };
    out.push(
      await run(
        'marks a deadline as not done',
        merge(base(), { complianceMarks: [mark] }),
        { fn: 'clearMark', key: 'pifss:2026-11', label: 'PIFSS' },
        () => clearComplianceMark(CO, 'pifss:2026-11', 'PIFSS'),
      ),
    );
    out.push(
      await run('does nothing for a deadline not done', base(), { fn: 'clearMark', key: 'pifss:2026-10' }, () =>
        clearComplianceMark(CO, 'pifss:2026-10'),
      ),
    );
  }
  out.push(await run('switches the register’s extras on', base(), { fn: 'setRegisterExtras', on: true }, () => setRegisterExtras(CO, true)));
  out.push(await run('leaves the extras off when they are off', base(), { fn: 'setRegisterExtras', on: false }, () => setRegisterExtras(CO, false)));
  out.push(await run('switches the file finder on', base(), { fn: 'setFileFinder', on: true }, () => setFileFinder(CO, true)));
  {
    const company = kuwaitCompany({
      registerExtras: true,
      documentPurposes: [
        { id: 'p-1', name: 'Tender', nameAr: 'مناقصة' },
        { id: 'p-2', name: 'Bank facility', nameAr: '' },
        { id: 'p-3', name: 'Site A', nameAr: '' },
      ],
    } as Partial<Company>);
    const edited = [
      { id: 'p-1', name: '  Tender   bids ', nameAr: ' مناقصة ' },
      { id: 'p-2', name: '', nameAr: '', archived: true },
      { id: 'p-new', name: '', nameAr: 'موقع ب' },
      { id: 'p-empty', name: ' ', nameAr: '' },
    ];
    out.push(
      await run('saves the purposes as edited', company, { fn: 'savePurposes', list: edited }, () =>
        saveDocumentPurposes(CO, edited),
      ),
    );
    const twice = [
      { id: 'p-1', name: 'Tender', nameAr: '' },
      { id: 'p-x', name: 'TENDER', nameAr: '' },
    ];
    out.push(
      await run('refuses a purpose named twice', company, { fn: 'savePurposes', list: twice }, () =>
        saveDocumentPurposes(CO, twice),
      ),
    );
    const same = [{ id: 'p-1', name: 'Tender', nameAr: 'مناقصة' }];
    out.push(
      await run('changes nothing when the purposes are as they were', company, { fn: 'savePurposes', list: same }, () =>
        saveDocumentPurposes(CO, same),
      ),
    );
    out.push(
      await run('adds a purpose', company, { fn: 'addPurpose', name: ' Ministry  visit ', nameAr: 'زيارة' }, () =>
        addDocumentPurpose(CO, { name: ' Ministry  visit ', nameAr: 'زيارة' }),
      ),
    );
    out.push(
      await run('finds a purpose by its Arabic name', company, { fn: 'addPurpose', name: '', nameAr: 'مناقصة' }, () =>
        addDocumentPurpose(CO, { name: '', nameAr: 'مناقصة' }),
      ),
    );
    const archived = kuwaitCompany({
      documentPurposes: [{ id: 'p-1', name: 'Tender', nameAr: '', archived: true }],
    } as Partial<Company>);
    out.push(
      await run('restores an archived purpose added again', archived, { fn: 'addPurpose', name: 'tender', nameAr: '' }, () =>
        addDocumentPurpose(CO, { name: 'tender' }),
      ),
    );
    out.push(
      await run('asks for the purpose’s name', company, { fn: 'addPurpose', name: '  ', nameAr: '' }, () =>
        addDocumentPurpose(CO, { name: '  ' }),
      ),
    );
    out.push(
      await run('archives a purpose', company, { fn: 'setPurposeArchived', id: 'p-2', archived: true }, () =>
        setDocumentPurposeArchived(CO, 'p-2', true),
      ),
    );
    out.push(
      await run('refuses a purpose not found', company, { fn: 'setPurposeArchived', id: 'p-9', archived: true }, () =>
        setDocumentPurposeArchived(CO, 'p-9', true),
      ),
    );
  }

  // ---------------------------------------------------------------------- //
  // Renewals

  withChart = true;

  const renewal = async (name: string, before: Tables, input: Omit<RenewInput, 'companyId'>, now = NOW) =>
    run(name, before, { fn: 'renew', ...input }, () => renewDocument({ companyId: CO, ...input }), { now });

  out.push(
    await renewal('renews an employee’s residency with its fee in 6090', merge(base(), { employees: [employee('emp-1')] }), {
      key: 'emp:emp-1:residency',
      newExpiry: '2027-12-18',
      renewedOn: '2026-11-28',
      fee: { amount: 10.0004, accountId: null, paidFromAccountId: null },
      note: ' Renewed at the residency office ',
    }),
  );
  out.push(
    await renewal(
      'renews a passport paid in cash, with its new number',
      merge(base(), { employees: [employee('emp-1')] }),
      {
        key: 'emp:emp-1:passport',
        newExpiry: '2036-12-03',
        renewedOn: '2026-11-28',
        number: ' P222 ',
        fee: { amount: 25.5, accountId: null, paidFromAccountId: 'acc-1010', reference: ' R-9 ' },
      },
    ),
  );
  {
    const stored = doc('d-20', { number: 'CL-20', renewalCost: 100 });
    out.push(
      await renewal('renews a commercial licence into 6100', merge(base(), { complianceDocuments: [stored] }), {
        key: 'doc:d-20',
        newExpiry: '2028-12-28',
        renewedOn: '2026-11-28',
        fee: { amount: 120, accountId: null, paidFromAccountId: null, reference: '' },
        note: 'Paid online',
      }),
    );
    out.push(
      await renewal('renews without a fee', merge(base(), { complianceDocuments: [stored] }), {
        key: 'doc:d-20',
        newExpiry: '2029-12-28',
        renewedOn: '2026-11-28',
        number: 'CL-21',
        fee: { amount: 0, accountId: null, paidFromAccountId: null },
      }),
    );
    const numbered = kuwaitCompany();
    (numbered.companies[0] as Company).numbering.expense = { pattern: 'EXP-{counter}', next: 4, padding: 3, reset: 'never', period: '' };
    out.push(
      await renewal(
        'numbers the fee after the numbers taken, in the category chosen',
        merge(numbered, {
          complianceDocuments: [stored],
          expenses: [
            {
              id: 'x-1',
              companyId: CO,
              number: 'exp-004',
              date: '2026-11-01',
              vendorId: null,
              accountId: 'acc-6100',
              description: 'x',
              amount: 1,
              taxes: [],
              currency: 'KWD',
              paidFromAccountId: null,
              reference: '',
              notes: '',
              createdAt: OLD,
              updatedAt: OLD,
            },
          ],
        }),
        {
          key: 'doc:d-20',
          newExpiry: '2028-12-28',
          renewedOn: '2026-11-28',
          fee: { amount: 50, accountId: 'acc-6120', paidFromAccountId: null },
        },
      ),
    );
    const van = doc('d-21', {
      type: 'vehicle_registration',
      ownerType: 'vehicle',
      ownerName: '12/34567',
      title: 'Van registration',
      number: 'VR-1',
    });
    out.push(
      await renewal('renews a vehicle’s paper, named in the fee', merge(base(), { complianceDocuments: [van] }), {
        key: 'doc:d-21',
        newExpiry: '2027-12-28',
        renewedOn: '2026-11-28',
        fee: { amount: 15, accountId: null, paidFromAccountId: null },
      }),
    );
    out.push(
      await renewal(
        'renews a confidential paper without naming it in the fee',
        merge(extras(), { complianceDocuments: [{ ...van, confidential: true }] }),
        {
          key: 'doc:d-21',
          newExpiry: '2027-12-28',
          renewedOn: '2026-11-28',
          fee: { amount: 15, accountId: null, paidFromAccountId: null, reference: 'R-1' },
          note: 'private',
        },
      ),
    );
    out.push(
      await renewal(
        'keeps the new copy with the document',
        merge(base(), { complianceDocuments: [stored] }),
        {
          key: 'doc:d-20',
          newExpiry: '2028-12-28',
          renewedOn: '2026-11-28',
          copy: { name: 'licence.pdf', type: 'application/pdf', dataUrl: 'data:application/pdf;base64,QUJDRA==' },
        },
      ),
    );
    out.push(
      await renewal(
        'finds the new copy filed before the renewal',
        merge(base(), {
          complianceDocuments: [stored],
          attachments: [
            file('f-7', 'd-20', { docKey: 'doc:d-20', validUntil: '2027-01-01' }),
            file('f-8', 'd-20', { docKey: 'doc:d-20', validUntil: '2028-12-28' }),
          ],
        }),
        { key: 'doc:d-20', newExpiry: '2028-12-28', renewedOn: '2026-11-28' },
      ),
    );
    out.push(
      await renewal('refuses an earlier expiry date', merge(base(), { complianceDocuments: [stored] }), {
        key: 'doc:d-20',
        newExpiry: '2026-12-01',
        renewedOn: '2026-11-28',
      }),
    );
    const locked = kuwaitCompany({
      accounting: { ...defaultAccountingSettings('KW'), lockDate: '2026-11-30' },
    } as Partial<Company>);
    out.push(
      await renewal('refuses a fee in a locked period', merge(locked, { complianceDocuments: [stored] }), {
        key: 'doc:d-20',
        newExpiry: '2028-12-28',
        renewedOn: '2026-11-28',
        fee: { amount: 10, accountId: null, paidFromAccountId: null },
      }),
    );
    out.push(
      await renewal('refuses a document not found', base(), {
        key: 'doc:d-404',
        newExpiry: '2028-12-28',
        renewedOn: '2026-11-28',
      }),
    );
  }
  {
    const ae = kuwaitCompany({
      address: { line1: '', line2: '', city: '', state: '', postalCode: '', country: 'AE' },
      currency: 'AED',
      locale: 'en-AE',
    } as Partial<Company>);
    out.push(
      await renewal('creates the fee account in a company on another chart', merge(ae, { employees: [employee('emp-1')] }), {
        key: 'emp:emp-1:residency',
        newExpiry: '2027-12-18',
        renewedOn: '2026-11-28',
        fee: { amount: 100, accountId: null, paidFromAccountId: null },
      }),
    );
  }

  // New copies

  withChart = false;
  {
    const stored = doc('d-30');
    const renewalRow = {
      id: 'r-30',
      companyId: CO,
      documentKey: 'doc:d-30',
      documentId: 'd-30',
      employeeId: null,
      type: 'commercial_licence',
      renewedOn: '2026-11-01',
      previousExpiry: '2025-12-28',
      newExpiry: '2026-12-28',
      fee: 0,
      expenseId: null,
      note: '',
      number: 'CL-1',
      createdAt: OLD,
    };
    const tables = merge(base(), { complianceDocuments: [stored], renewals: [renewalRow], attachments: [file('f-9', 'd-30')] });
    out.push(
      await run('marks a file as the renewed paper’s new copy', tables, {
        fn: 'markNewCopy',
        fileId: 'f-9',
        tag: { docKey: 'doc:d-30', validUntil: '2026-12-28' },
      }, () => markNewCopy('f-9', { docKey: 'doc:d-30', validUntil: '2026-12-28' })),
    );
    const linked = merge(base(), {
      complianceDocuments: [stored],
      renewals: [{ ...renewalRow, newCopyId: 'f-9' }],
      attachments: [file('f-9', 'd-30', { docKey: 'doc:d-30', validUntil: '2026-12-28' })],
    });
    out.push(
      await run('unmarks a file, which stops being the new copy', linked, { fn: 'markNewCopy', fileId: 'f-9', tag: null }, () =>
        markNewCopy('f-9', null),
      ),
    );
    out.push(
      await run('refuses a file not found', base(), { fn: 'markNewCopy', fileId: 'f-404', tag: null }, () =>
        markNewCopy('f-404', null),
      ),
    );
    out.push(
      await run(
        'adds a new copy',
        merge(base(), { complianceDocuments: [stored], renewals: [renewalRow] }),
        {
          fn: 'addNewCopy',
          ownerId: 'd-30',
          file: { name: 'new.jpg', type: 'image/jpeg', dataUrl: 'data:image/jpeg;base64,/9j/4AAQ' },
          tag: { docKey: 'doc:d-30', validUntil: '2027-01-01' },
        },
        () =>
          addNewCopy(CO, 'd-30', { name: 'new.jpg', type: 'image/jpeg', dataUrl: 'data:image/jpeg;base64,/9j/4AAQ' }, {
            docKey: 'doc:d-30',
            validUntil: '2027-01-01',
          }),
      ),
    );
  }

  // ---------------------------------------------------------------------- //
  // Vehicles

  {
    const fresh = vehicle('00000f02-0000-4000-8000-000000000000', '  12 / 34567 ', {
      make: ' Toyota ',
      model: ' Hi  ace ',
      year: 2022.7,
      chassisNumber: ' jt123 ',
      notes: ' White van ',
      driverEmployeeId: 'emp-1',
      assetId: 'as-1',
      createdAt: NOW,
      updatedAt: NOW,
    });
    const asset = { id: 'as-1', companyId: CO, number: 'FA-1', name: 'Van', status: 'active', createdAt: OLD, updatedAt: OLD };
    out.push(
      await run(
        'adds a vehicle, tidied',
        merge(extras(), { employees: [employee('emp-1')], assets: [asset] }),
        { fn: 'saveVehicle', vehicle: fresh },
        () => saveVehicle(fresh),
        { cloud: V16 },
      ),
    );
    const stored = vehicle('veh-1', '12/34567');
    const papers = [
      doc('d-40', { type: 'vehicle_registration', ownerType: 'vehicle', vehicleId: 'veh-1', ownerName: '12/34567' }),
      doc('d-41', { type: 'vehicle_insurance', ownerType: 'vehicle', vehicleId: 'veh-2', ownerName: '99/1' }),
    ];
    out.push(
      await run(
        'gives its papers the new plate',
        merge(extras(), { vehicles: [stored], complianceDocuments: papers }),
        { fn: 'saveVehicle', vehicle: { ...stored, plate: '12/99999' } },
        () => saveVehicle({ ...stored, plate: '12/99999' }),
      ),
    );
    const twin = vehicle('veh-3', '12-34567');
    out.push(
      await run(
        'refuses a plate another vehicle has',
        merge(extras(), { vehicles: [stored] }),
        { fn: 'saveVehicle', vehicle: twin },
        () => saveVehicle(twin),
      ),
    );
    const old = vehicle('veh-4', 'A1', { year: 1900 });
    out.push(await run('refuses a year before 1950', extras(), { fn: 'saveVehicle', vehicle: old }, () => saveVehicle(old)));
    const driver = vehicle('veh-5', 'A2', { driverEmployeeId: 'emp-9' });
    out.push(await run('refuses a driver not of the company', extras(), { fn: 'saveVehicle', vehicle: driver }, () => saveVehicle(driver)));
    const noAsset = vehicle('veh-6', 'A3', { assetId: 'as-9' });
    out.push(await run('refuses an asset not of the company', extras(), { fn: 'saveVehicle', vehicle: noAsset }, () => saveVehicle(noAsset)));
    const blank = vehicle('veh-7', '   ');
    out.push(await run('asks for the plate', extras(), { fn: 'saveVehicle', vehicle: blank }, () => saveVehicle(blank)));
    out.push(
      await run(
        'waits for the server to have vehicles',
        extras(),
        { fn: 'saveVehicle', vehicle: vehicle('veh-8', 'A4') },
        () => saveVehicle(vehicle('veh-8', 'A4')),
        { cloud: [] },
      ),
    );
    out.push(
      await run(
        'archives a vehicle',
        merge(extras(), { vehicles: [stored] }),
        { fn: 'setVehicleArchived', id: 'veh-1', archived: true },
        () => setVehicleArchived('veh-1', true),
      ),
    );
    out.push(
      await run(
        'keeps a vehicle with papers',
        merge(extras(), { vehicles: [stored], complianceDocuments: papers }),
        { fn: 'deleteVehicle', id: 'veh-1' },
        () => deleteVehicle('veh-1'),
      ),
    );
    out.push(
      await run(
        'deletes a vehicle added by mistake',
        merge(extras(), { vehicles: [stored] }),
        { fn: 'deleteVehicle', id: 'veh-1' },
        () => deleteVehicle('veh-1'),
      ),
    );
    const unlinked = [
      doc('d-50', { type: 'vehicle_registration', ownerType: 'vehicle', ownerName: '12 / 34567', createdAt: '2026-02-01T00:00:00.000Z' }),
      doc('d-51', { type: 'vehicle_insurance', ownerType: 'vehicle', ownerName: '12-34567', createdAt: '2026-03-01T00:00:00.000Z' }),
      doc('d-52', { type: 'vehicle_insurance', ownerType: 'vehicle', ownerName: ' Nissan  Patrol ', createdAt: '2026-01-01T00:00:00.000Z' }),
      doc('d-53', { type: 'vehicle_insurance', ownerType: 'vehicle', ownerName: 'B-77', createdAt: '2026-01-02T00:00:00.000Z' }),
      doc('d-54', { type: 'commercial_licence' }),
    ];
    out.push(
      await run(
        'links vehicle papers, adding the vehicles missing',
        merge(extras(), { vehicles: [vehicle('veh-9', 'b77')], complianceDocuments: unlinked }),
        { fn: 'linkVehiclePapers' },
        () => linkVehiclePapers(CO),
      ),
    );
  }

  // ---------------------------------------------------------------------- //
  // The company's settings and tax rates

  const companyRow = () => kuwaitCompany().companies[0] as Company;
  // `change` names the settings page's change, made from `from`: the Swift
  // side makes it too and checks it gives the company the web saved.
  const saveAs = async (
    name: string,
    change: Record<string, unknown>,
    edit: (c: Company) => Company,
    make: (c: Company) => Company,
  ) => {
    const before = kuwaitCompany();
    const from = edit(before.companies[0] as Company);
    const next = make(from);
    return run(name, before, { fn: 'saveCompany', company: next, change: { ...change, from } }, () => saveCompany(next));
  };
  const same = (c: Company) => c;
  out.push(
    await saveAs(
      'switches taxes on',
      { kind: 'taxes', on: true },
      (c) => ({ ...c, defaults: { ...c.defaults, lineTaxes: false, documentTaxes: false } }),
      (c) => withTaxes(c, true),
    ),
  );
  out.push(await saveAs('switches taxes off', { kind: 'taxes', on: false }, same, (c) => withTaxes(c, false)));
  out.push(await saveAs('gives Sales and Inventory their own apps', { kind: 'appLayout', on: true }, same, (c) => withAppLayout(c, true)));
  out.push(
    await saveAs(
      'puts Sales and Inventory back in Books',
      { kind: 'appLayout', on: false },
      (c) => ({ ...c, appLayout: 'split' }) as Company,
      (c) => withAppLayout(c, false),
    ),
  );
  out.push(await saveAs('switches the AI assistant on', { kind: 'ai', on: true }, same, (c) => withAiSwitch(c, true)));
  out.push(
    await saveAs(
      'switches the AI assistant off, keeping what else it has',
      { kind: 'ai', on: false },
      (c) => ({ ...c, ai: { on: true, model: 'fast' } }) as Company,
      (c) => withAiSwitch(c, false),
    ),
  );
  out.push(
    await saveAs('changes the quotes’ template', { kind: 'template', type: 'quote', templateId: 'elegant' }, same, (c) =>
      withTypeDesign(c, 'quote', { templateId: 'elegant' }),
    ),
  );
  out.push(
    await saveAs('changes the invoices’ template', { kind: 'template', type: 'invoice', templateId: 'bold' }, same, (c) =>
      withTypeDesign(c, 'invoice', { templateId: 'bold' }),
    ),
  );
  out.push(
    await saveAs(
      'prints credit notes like invoices again',
      { kind: 'sameAsInvoices', type: 'credit', same: true },
      (c) => withTypeDesign(withTypeDesign(c, 'credit', { templateId: 'mono' }), 'quote', { templateId: 'bold' }),
      (c) => withSameAsInvoices(c, 'credit', true),
    ),
  );
  out.push(
    await saveAs('gives quotes a design of their own', { kind: 'sameAsInvoices', type: 'quote', same: false }, same, (c) =>
      withSameAsInvoices(c, 'quote', false),
    ),
  );
  out.push(
    await saveAs(
      'tidies the profile: a built-in type typed by name, the legal form described',
      { kind: 'profile' },
      (c) =>
        ({
          ...c,
          name: 'Blue Harbour Security',
          companyType: { id: '', name: ' security  services ', nameAr: '' },
          kuwait: { ...(c.kuwait ?? {}), legalForm: 'other', legalFormOther: '  Branch   of a foreign company ' },
        }) as Company,
      (c) => withTidyProfile(c, companyTypeOptions([companyRow()])),
    ),
  );
  out.push(
    await saveAs(
      'tidies the profile: a new type, no description for a WLL',
      { kind: 'profile' },
      (c) =>
        ({
          ...c,
          companyType: { id: '', name: '  Facility   management ', nameAr: ' إدارة المرافق ' },
          kuwait: { ...(c.kuwait ?? {}), legalForm: 'wll', legalFormOther: 'left over' },
        }) as Company,
      (c) => withTidyProfile(c, companyTypeOptions([companyRow()])),
    ),
  );
  out.push(
    await saveAs(
      'tidies the profile: no type',
      { kind: 'profile' },
      (c) => ({ ...c, companyType: { id: 'x', name: ' ', nameAr: '' } }) as Company,
      (c) => withTidyProfile(c, companyTypeOptions([])),
    ),
  );
  {
    const rate = { ...createTaxRate(CO, { name: 'VAT', rate: 5, kind: 'standard' }), id: 'tr-1', createdAt: OLD, updatedAt: OLD };
    out.push(
      await run(
        'saves a tax rate, its name trimmed',
        merge(kuwaitCompany(), { taxRates: [rate] }),
        { fn: 'saveTaxRate', rate: { ...rate, name: ' VAT standard ', rate: 15 } },
        () => saveTaxRate({ ...rate, name: ' VAT standard ', rate: 15 }),
      ),
    );
    out.push(
      await run('adds a tax rate', kuwaitCompany(), { fn: 'addTaxRate', name: 'Tax' }, () =>
        saveTaxRate(createTaxRate(CO, { name: 'Tax', rate: 0, kind: 'zero' })),
      ),
    );
    const withDefault = kuwaitCompany();
    (withDefault.companies[0] as Company).defaults.defaultTaxRateIds = ['tr-1', 'tr-2'];
    out.push(
      await run(
        'deletes a tax rate, taken off the defaults and items',
        merge(withDefault, {
          taxRates: [rate, { ...rate, id: 'tr-2' }],
          products: [
            { id: 'pr-1', companyId: CO, name: 'Guarding hour', taxRateIds: ['tr-1'], createdAt: OLD, updatedAt: OLD },
            { id: 'pr-2', companyId: CO, name: 'Patrol', taxRateIds: ['tr-2'], createdAt: OLD, updatedAt: OLD },
          ],
        }),
        { fn: 'deleteTaxRate', id: 'tr-1' },
        () => deleteTaxRate('tr-1'),
      ),
    );
  }

  // ---------------------------------------------------------------------- //
  // Files

  out.push(
    await run(
      'adds a file to a document',
      merge(base(), { complianceDocuments: [doc('d-60')] }),
      { fn: 'addAttachment', ownerId: 'd-60', file: { name: 'scan.png', type: 'image/png', dataUrl: 'data:image/png;base64,iVBORw0KGgoAAA' } },
      () => addAttachment(CO, 'd-60', { name: 'scan.png', type: 'image/png', dataUrl: 'data:image/png;base64,iVBORw0KGgoAAA' }),
    ),
  );
  out.push(
    await run(
      'removes an employee’s photo with its file',
      merge(base(), { employees: [employee('emp-1', { photoId: 'f-10' })], attachments: [file('f-10', 'emp-1')] }),
      { fn: 'removeAttachment', id: 'f-10' },
      () => removeAttachment('f-10'),
    ),
  );
  out.push(
    await run(
      'removes an item’s picture with its file',
      merge(base(), {
        products: [{ id: 'pr-3', companyId: CO, name: 'Radio', imageIds: ['f-11'], createdAt: OLD, updatedAt: OLD }],
        attachments: [file('f-11', 'pr-3', { type: 'image/jpeg' })],
      }),
      { fn: 'removeAttachment', id: 'f-11' },
      () => removeAttachment('f-11'),
    ),
  );

  writeFixtures('suite', out);
  const refused = out.filter((s) => s.error).map((s) => `${s.name}: ${s.error}`);
  console.log(`${out.length} scenarios; refused:\n  ${refused.join('\n  ')}`);
  await db.delete();
});
