// The web's own outputs for the accounting writes (Maham One's Accounting,
// Banking and VAT): the chart of accounts, manual journals, the year-end
// close, fixed assets and depreciation, bank statement lines, transfers and
// VAT returns. Each scenario seeds a company with the web's own functions,
// then runs one write; the Swift side (WriteAccountingTests.swift) runs the
// port named by `input.op` on `before` and compares every table.
//
// From the repository root:
//   npx vitest run --config ios/scripts/web-fixtures/writes.gen.config.mjs writes-accounting
import { vi } from 'vitest';
vi.mock('@/lib/ids', async (load) => ({ ...(await load<typeof import('@/lib/ids')>()), ...(await import('./writes-ids')).fixedIds() }));
// (writes-setup.ts also leaves the outbox out, so the ids count only the records the web writes.)
import { scenario, writeFixtures, type Scenario } from './writes-harness';
import { db } from '@/db/db';
import { createClient } from '@/db/defaults';
import { saveClient, setupCompany } from '@/db/records';
import { draftDocument, saveDocument } from '@/db/documents';
import {
  closeYear,
  createAccount,
  createJournal,
  deleteAccount,
  deleteJournal,
  loadLedger,
  newJournalLine,
  reopenYear,
  reverseJournal,
  roleMap,
  saveAccount,
  saveJournal,
} from '@/db/accounting';
import {
  createAsset,
  disposeAsset,
  reverseDepreciationRun,
  runDepreciation,
  saveAsset,
  undoDisposal,
  voidAsset,
} from '@/db/assets';
import {
  createFromTransaction,
  deleteTransaction,
  ignoreTransaction,
  importStatement,
  matchTransaction,
  saveTransfer,
  unmatchTransaction,
} from '@/db/banking';
import { computeVatReturn, fileVatReturn, recordVatPayment, undoVatReturn } from '@/db/vat';
import { vatAccountTotals } from '@/lib/accounting/vat';
import { loadLanguage, t } from '@/i18n';

/* eslint-disable @typescript-eslint/no-explicit-any */
type Any = any;

const out: Scenario[] = [];
const NOW = '2026-12-15T08:00:00.000Z';

/** A copy of what the action is asked, so the fixture keeps it as given. */
const copy = <T,>(value: T): T => JSON.parse(JSON.stringify(value)) as T;

/**
 * One scenario: `seed` builds the books with the web's functions and fills
 * `input` (the op and its arguments, as the Swift side runs them); `action`
 * runs the write from a copy of `input`.
 */
async function add(
  name: string,
  seed: (s: Any, input: Any) => Promise<void>,
  action: (input: Any, s: Any) => Promise<unknown>,
  options: { now?: string; arabic?: boolean } = {},
) {
  const s: Any = {};
  const input: Any = {};
  out.push(
    await scenario(
      name,
      {
        now: options.now ?? NOW,
        userId: 'u-1',
        userName: 'Sample Owner',
        input,
        seed: async () => {
          await seed(s, input);
          // The browser's own settings (the company open) are not company records.
          await db.meta.clear();
          if (options.arabic) {
            // Read in Arabic: what the web writes in the interface language is Arabic.
            await loadLanguage('ar');
            input.language = 'ar';
            input.arabic = Object.fromEntries(WORDS.map((key) => [key, t(key)]));
          }
        },
      },
      () => action(copy(input), s),
    ),
  );
  if (options.arabic) await loadLanguage('en');
}

/** The words the accounting writes store or refuse with, for scenarios read in Arabic. */
const WORDS = [
  'Reversal of {number}',
  'Transfer to statutory reserve',
  'Transfer to voluntary reserve',
  'KFAS contribution',
  'Zakat',
  'National Labour Support Tax',
  'Income tax',
  'KFAS, Zakat, NLST and income tax for {year}',
  'Transfers to reserves for {year}',
  'Purchase of {asset}',
  'Opening balance of {asset}',
  'Depreciation to {date}',
  'Gain on disposal',
  'Loss on disposal',
  'Disposal of {asset}',
  'Depreciation for {month}',
  'Reversal of depreciation for {month}',
  'Transfer from {from} to {to}',
  'From {account}',
  'To {account}',
  'Bank transaction',
  'VAT on sales',
  'VAT on purchases',
  'VAT for the period',
  'VAT return {start} to {end}',
  'Reference {reference}',
  'VAT payment {start} to {end}',
  'VAT refund {start} to {end}',
  'Fixed assets',
  'Year-end close',
  'Payments',
  'Payroll',
  'Retentions',
  'This entry is managed in {place}. Change it there.',
  'The books are locked up to {date}. Change the lock date in Settings → Accounting to edit earlier transactions.',
  'Depreciation has already been run for {month}. Undo that run first.',
  'Depreciation has been posted up to {date}. Choose a later date or undo those runs first.',
  'Debits and credits must be equal.',
];

async function arabicScenarios() {
  const arabic = { arabic: true };
  await add(
    'read in Arabic: a depreciation run',
    async (s, input) => {
      await kuwait(s);
      await saveAsset(laptop(s));
      await saveAsset(laptop(s, { name: 'Car', cost: 9000, usefulLifeMonths: 60, depreciationStart: '2026-01-16' }));
      Object.assign(input, { op: 'runDepreciation', companyId: s.company.id, period: '2026-03' });
    },
    (input) => runDepreciation(input.companyId, input.period),
    arabic,
  );
  await add(
    'read in Arabic: a run undone',
    async (s, input) => {
      await kuwait(s);
      await saveAsset(laptop(s));
      const run = (await runDepreciation(s.company.id, '2026-02')).run!;
      Object.assign(input, { op: 'reverseDepreciationRun', id: run.id });
    },
    (input) => reverseDepreciationRun(input.id),
    arabic,
  );
  await add(
    'read in Arabic: months out of order',
    async (s, input) => {
      await kuwait(s);
      await saveAsset(laptop(s));
      await runDepreciation(s.company.id, '2026-05');
      Object.assign(input, { op: 'runDepreciation', companyId: s.company.id, period: '2026-04' });
    },
    (input) => runDepreciation(input.companyId, input.period),
    arabic,
  );
  await add(
    'read in Arabic: money moved between accounts with Arabic names',
    async (s, input) => {
      await kuwait(s);
      Object.assign(input, { op: 'saveTransfer', companyId: s.company.id, from: s.code('1000').id, to: s.code('1010').id, date: '2026-10-06', amount: 25 });
    },
    (input) => saveTransfer(input),
    arabic,
  );
  await add(
    'read in Arabic: a journal of a locked period',
    async (s, input) => {
      await kuwait(s);
      await lockBooks(s.company.id, '2026-06-30');
      input.op = 'saveJournal';
      input.journal = journal(s, '2026-06-30', [['6060', 5, 0], ['1000', 0, 5]]);
    },
    (input) => saveJournal(input.journal),
    arabic,
  );
  await add(
    'read in Arabic: a year closed',
    async (s, input) => {
      await holding(s);
      Object.assign(input, { op: 'closeYear', companyId: s.company.id }, copy(CLOSE_2026));
    },
    (input) => closeYear(input.companyId, input),
    { now: '2027-01-20T08:00:00.000Z', arabic: true },
  );
  await add(
    'read in Arabic: an asset bought and one sold',
    async (s, input) => {
      await kuwait(s);
      const asset = await saveAsset(laptop(s));
      await runDepreciation(s.company.id, '2026-02');
      Object.assign(input, { op: 'disposeAsset', id: asset.id, date: '2026-03-15', proceeds: 1000, depositAccountId: s.code('1000').id });
    },
    (input) => disposeAsset(input.id, input),
    arabic,
  );
  await add(
    'read in Arabic: an asset owned before',
    async (s, input) => {
      await kuwait(s);
      input.op = 'saveAsset';
      input.asset = laptop(s, OPENING);
    },
    (input) => saveAsset(input.asset),
    arabic,
  );
  await add(
    'read in Arabic: a statement line recorded against another account',
    async (s, input) => {
      await kuwait(s);
      const { transactions } = await importStatement(s.company.id, s.code('1000').id, [line('2026-10-07', -12.5, '')], '');
      Object.assign(input, { op: 'createFromTransaction', id: transactions[0].id, action: { kind: 'account', accountId: s.code('6170').id } });
    },
    (input) => createFromTransaction(input.id, input.action),
    { now: '2026-10-20T08:00:00.000Z', arabic: true },
  );
  await add(
    'read in Arabic: a VAT return filed and paid',
    async (s, input) => {
      await quarter(s, input);
      Object.assign(input, { op: 'fileVatReturn', companyId: s.company.id, period: Q4, filedOn: '2027-01-15', reference: 'HMRC-9', lock: false });
    },
    (input) => fileVatReturn(input.companyId, input.period, input),
    { now: '2027-01-20T08:00:00.000Z', arabic: true },
  );
  await add(
    'read in Arabic: a journal reversed',
    async (s, input) => {
      await kuwait(s);
      const saved = await saveJournal(journal(s, '2026-05-01', [['6060', 75.25, 0], ['1000', 0, 75.25]]));
      input.op = 'reverseJournal';
      input.id = saved.id;
    },
    async (input) => reverseJournal((await db.journals.get(input.id))!),
    arabic,
  );
  await add(
    'read in Arabic: an entry fixed assets made',
    async (s, input) => {
      await kuwait(s);
      input.op = 'saveJournal';
      input.journal = journal(s, '2026-05-31', [['6900', 5, 0], ['1530', 0, 5]], { kind: 'depreciation' });
    },
    (input) => saveJournal(input.journal),
    arabic,
  );
}

async function accounts(companyId: string) {
  return db.accounts.where('companyId').equals(companyId).toArray();
}

/** A Kuwaiti company on the Kuwait chart, with its accounts by code and role. */
async function kuwait(s: Any, extra: Any = {}) {
  s.company = await setupCompany({ name: 'Gulf Trading', ...extra });
  const list = await accounts(s.company.id);
  s.code = (c: string) => list.find((a) => a.code === c)!;
  s.role = (r: string) => list.find((a) => a.role === r)!;
  return s.company;
}

/** A company on the standard chart (no Kuwait codes): spec accounts are found by name or made. */
async function generic(s: Any) {
  s.company = await setupCompany({
    name: 'Atlas Inc',
    currency: 'USD',
    locale: 'en-US',
    address: { line1: '', line2: '', city: '', state: '', postalCode: '', country: 'US' },
  });
  const list = await accounts(s.company.id);
  s.code = (c: string) => list.find((a) => a.code === c)!;
  s.role = (r: string) => list.find((a) => a.role === r)!;
  return s.company;
}

/** A UK company registered for VAT, charging 20%. */
async function british(s: Any) {
  s.company = await setupCompany(
    {
      name: 'Northwind Mail Services',
      currency: 'GBP',
      locale: 'en-GB',
      taxIdLabel: 'VAT No.',
      taxId: 'GB 123 4567 89',
      address: { line1: '', line2: '', city: 'Manchester', state: '', postalCode: 'M1 2AB', country: 'GB' },
    } as Any,
    [{ name: 'VAT', rate: 20, kind: 'standard' } as Any],
  );
  const list = await accounts(s.company.id);
  s.code = (c: string) => list.find((a) => a.code === c)!;
  s.role = (r: string) => list.find((a) => a.role === r)!;
  return s.company;
}

async function lockBooks(companyId: string, lockDate: string) {
  const company = (await db.companies.get(companyId))!;
  await db.companies.put({ ...company, accounting: { ...company.accounting!, lockDate } });
}

const journal = (s: Any, date: string, lines: [string, number, number][], extra: Any = {}) =>
  createJournal(s.company.id, {
    date,
    status: 'posted',
    lines: lines.map(([code, debit, credit]) => newJournalLine({ accountId: s.code(code).id, debit, credit })),
    ...extra,
  });

/* -------------------------------------------------------------------------- */
/* Chart of accounts                                                          */
/* -------------------------------------------------------------------------- */

async function chartScenarios() {
  await add(
    'a new bank account with its bank details tidied',
    async (s, input) => {
      await kuwait(s);
      input.op = 'saveAccount';
      input.account = createAccount(s.company.id, {
        code: ' 1015 ',
        name: ' Gulf Bank current ',
        nameAr: ' بنك الخليج ',
        type: 'asset_cash',
        description: 'Main account',
        bank: { institution: ' Gulf Bank ', accountNumber: ' 0123 ', iban: 'kw81cbku0000000000001234560101', bic: ' gulbkwkw ' },
      });
    },
    (input) => saveAccount(input.account),
  );
  await add(
    'a new account without bank details or an Arabic name',
    async (s, input) => {
      await kuwait(s);
      input.op = 'saveAccount';
      input.account = createAccount(s.company.id, {
        code: '6950',
        name: 'Office plants',
        nameAr: '   ',
        type: 'expense',
        bank: { institution: ' ', accountNumber: '', iban: '', bic: '' },
      });
    },
    (input) => saveAccount(input.account),
  );
  await add(
    'an account renamed',
    async (s, input) => {
      await kuwait(s);
      input.op = 'saveAccount';
      input.account = { ...s.code('6110'), name: 'Marketing', description: 'Ads and events' };
    },
    (input) => saveAccount(input.account),
  );
  await add(
    'an account archived',
    async (s, input) => {
      await kuwait(s);
      input.op = 'saveAccount';
      input.account = { ...s.code('6130'), archived: true };
    },
    (input) => saveAccount(input.account),
  );
  await add(
    'a system account renamed keeps its type',
    async (s, input) => {
      await kuwait(s);
      input.op = 'saveAccount';
      input.account = { ...s.role('bank'), name: 'NBK current account', code: '1001' };
    },
    (input) => saveAccount(input.account),
  );
  const refusals: [string, (s: Any) => Any][] = [
    ['an account without a name', (s) => createAccount(s.company.id, { code: '6951', name: '  ' })],
    ['an account without a code', (s) => createAccount(s.company.id, { code: ' ', name: 'Plants' })],
    [
      'an account with an IBAN that is not valid',
      (s) =>
        createAccount(s.company.id, {
          code: '1016',
          name: 'Second bank',
          type: 'asset_cash',
          bank: { institution: '', accountNumber: '', iban: 'KW81 CBKU 0000 0000 0000 1234 5601 02', bic: '' },
        }),
    ],
    ['an account with a code in use', (s) => createAccount(s.company.id, { code: '1000', name: 'Another bank' })],
    ['a system account given another type', (s) => ({ ...s.role('bank'), type: 'asset_current' })],
    ['a system account archived', (s) => ({ ...s.role('cash'), archived: true })],
  ];
  for (const [name, make] of refusals) {
    await add(
      name,
      async (s, input) => {
        await kuwait(s);
        input.op = 'saveAccount';
        input.account = make(s);
      },
      (input) => saveAccount(input.account),
    );
  }
  await add(
    'an account never used is deleted',
    async (s, input) => {
      await kuwait(s);
      const account = await saveAccount(createAccount(s.company.id, { code: '6960', name: 'Spare' }));
      input.op = 'deleteAccount';
      input.id = account.id;
    },
    (input) => deleteAccount(input.id),
  );
  await add(
    'a system account is not deleted',
    async (s, input) => {
      await kuwait(s);
      input.op = 'deleteAccount';
      input.id = s.role('cash').id;
    },
    (input) => deleteAccount(input.id),
  );
  await add(
    'an account a journal uses is not deleted',
    async (s, input) => {
      await kuwait(s);
      await saveJournal(journal(s, '2026-03-01', [['6110', 50, 0], ['1000', 0, 50]]));
      input.op = 'deleteAccount';
      input.id = s.code('6110').id;
    },
    (input) => deleteAccount(input.id),
  );
}

/* -------------------------------------------------------------------------- */
/* Manual journals                                                            */
/* -------------------------------------------------------------------------- */

async function journalScenarios() {
  await add(
    'a new journal numbered from the rule, empty lines left out',
    async (s, input) => {
      await kuwait(s);
      input.op = 'saveJournal';
      input.journal = journal(s, '2026-03-10', [['1000', 500, 0], ['3000', 0, 500], ['6000', 0, 0]], {
        reference: 'Owner investment',
        notes: 'Paid in by the owner',
      });
    },
    (input) => saveJournal(input.journal),
  );
  await add(
    'a draft journal with its own number',
    async (s, input) => {
      await kuwait(s);
      input.op = 'saveJournal';
      input.journal = journal(s, '2026-03-10', [['6060', 250.5, 0], ['1000', 0, 250.5]], {
        number: '  OB-1 ',
        status: 'draft',
      });
    },
    (input) => saveJournal(input.journal),
  );
  await add(
    'an edited journal keeps its number',
    async (s, input) => {
      await kuwait(s);
      const saved = await saveJournal(journal(s, '2026-03-10', [['6060', 100, 0], ['1000', 0, 100]]));
      input.op = 'saveJournal';
      input.journal = { ...saved, reference: 'March rent', lines: [{ ...saved.lines[0], debit: 120 }, { ...saved.lines[1], credit: 120 }] };
    },
    (input) => saveJournal(input.journal),
  );
  await add(
    'numbering skips a number typed by hand',
    async (s, input) => {
      await kuwait(s);
      await saveJournal(journal(s, '2026-02-01', [['6060', 10, 0], ['1000', 0, 10]], { number: 'je-2026-0001' }));
      input.op = 'saveJournal';
      input.journal = journal(s, '2026-04-01', [['6060', 20, 0], ['1000', 0, 20]]);
    },
    (input) => saveJournal(input.journal),
  );
  await add(
    'a difference under a fils balances',
    async (s, input) => {
      await kuwait(s);
      input.op = 'saveJournal';
      input.journal = journal(s, '2026-05-01', [['6060', 0.1, 0], ['6070', 0.2, 0], ['1000', 0, 0.3004]]);
    },
    (input) => saveJournal(input.journal),
  );
  await add(
    'a half fils does not balance',
    async (s, input) => {
      await kuwait(s);
      input.op = 'saveJournal';
      input.journal = journal(s, '2026-05-01', [['6060', 1.0005, 0], ['1000', 0, 1.001]]);
    },
    (input) => saveJournal(input.journal),
  );
  await add(
    'dollars: half a cent of difference does not balance',
    async (s, input) => {
      await generic(s);
      const list = await accounts(s.company.id);
      input.op = 'saveJournal';
      input.journal = createJournal(s.company.id, {
        date: '2026-05-01',
        lines: [
          newJournalLine({ accountId: list.find((a) => a.role === 'expense')!.id, debit: 10.005 }),
          newJournalLine({ accountId: list.find((a) => a.role === 'bank')!.id, credit: 10.01 }),
        ],
      });
    },
    (input) => saveJournal(input.journal),
  );
  const refused: [string, [string, number, number][]][] = [
    ['a negative amount', [['6060', -5, 0], ['1000', 0, -5]]],
    ['a line with a debit and a credit', [['6060', 5, 5], ['1000', 0, 0], ['3000', 0, 5]]],
    ['a journal with one line', [['6060', 5, 0]]],
    ['debits and credits that differ', [['6060', 5, 0], ['1000', 0, 4]]],
  ];
  for (const [name, lines] of refused) {
    await add(
      `a journal refused: ${name}`,
      async (s, input) => {
        await kuwait(s);
        input.op = 'saveJournal';
        input.journal = journal(s, '2026-05-01', lines);
      },
      (input) => saveJournal(input.journal),
    );
  }
  await add(
    'a journal refused: an account of no company',
    async (s, input) => {
      await kuwait(s);
      input.op = 'saveJournal';
      input.journal = createJournal(s.company.id, {
        date: '2026-05-01',
        lines: [newJournalLine({ accountId: s.code('6060').id, debit: 5 }), newJournalLine({ accountId: 'gone', credit: 5 })],
      });
    },
    (input) => saveJournal(input.journal),
  );
  await add(
    'a journal refused: dated in a locked period',
    async (s, input) => {
      await kuwait(s);
      await lockBooks(s.company.id, '2026-06-30');
      input.op = 'saveJournal';
      input.journal = journal(s, '2026-06-30', [['6060', 5, 0], ['1000', 0, 5]]);
    },
    (input) => saveJournal(input.journal),
  );
  await add(
    'a journal refused: moved out of a locked period',
    async (s, input) => {
      await kuwait(s);
      const saved = await saveJournal(journal(s, '2026-05-01', [['6060', 5, 0], ['1000', 0, 5]]));
      await lockBooks(s.company.id, '2026-05-31');
      input.op = 'saveJournal';
      input.journal = { ...saved, date: '2026-07-01' };
    },
    (input) => saveJournal(input.journal),
  );
  await add(
    'a journal refused: one fixed assets made',
    async (s, input) => {
      await kuwait(s);
      input.op = 'saveJournal';
      input.journal = journal(s, '2026-05-31', [['6900', 5, 0], ['1530', 0, 5]], { kind: 'depreciation' });
    },
    (input) => saveJournal(input.journal),
  );
  await add(
    'a transfer journal saved by hand',
    async (s, input) => {
      await kuwait(s);
      input.op = 'saveJournal';
      input.journal = journal(s, '2026-05-31', [['1010', 40, 0], ['1000', 0, 40]], { kind: 'transfer' });
    },
    (input) => saveJournal(input.journal),
  );
  await add(
    'a journal deleted',
    async (s, input) => {
      await kuwait(s);
      const saved = await saveJournal(journal(s, '2026-05-01', [['6060', 5, 0], ['1000', 0, 5]]));
      input.op = 'deleteJournal';
      input.id = saved.id;
    },
    (input) => deleteJournal(input.id),
  );
  await add(
    'a journal of a locked period is not deleted',
    async (s, input) => {
      await kuwait(s);
      const saved = await saveJournal(journal(s, '2026-05-01', [['6060', 5, 0], ['1000', 0, 5]]));
      await lockBooks(s.company.id, '2026-05-01');
      input.op = 'deleteJournal';
      input.id = saved.id;
    },
    (input) => deleteJournal(input.id),
  );
  await add(
    'a year-end journal is not deleted',
    async (s, input) => {
      await kuwait(s);
      const saved = await saveJournal(journal(s, '2025-12-31', [['3300', 5, 0], ['3200', 0, 5]], { kind: 'year_end' }), {
        system: true,
      });
      input.op = 'deleteJournal';
      input.id = saved.id;
    },
    (input) => deleteJournal(input.id),
  );
  await add(
    'a journal reversed',
    async (s, input) => {
      await kuwait(s);
      const saved = await saveJournal(
        journal(s, '2026-05-01', [['6060', 75.25, 0], ['1000', 0, 75.25]], { reference: 'May rent' }),
      );
      input.op = 'reverseJournal';
      input.id = saved.id;
    },
    async (input) => reverseJournal((await db.journals.get(input.id))!),
  );
  await add(
    'a journal reversed on another date',
    async (s, input) => {
      await kuwait(s);
      const saved = await saveJournal(journal(s, '2026-05-01', [['6060', 75.25, 0], ['1000', 0, 75.25]]));
      input.op = 'reverseJournal';
      input.id = saved.id;
      input.date = '2026-06-01';
      input.reference = 'Booked twice';
    },
    async (input) => reverseJournal((await db.journals.get(input.id))!, { date: input.date, reference: input.reference }),
  );
}

/* -------------------------------------------------------------------------- */
/* Year-end close                                                             */
/* -------------------------------------------------------------------------- */

/** As the year-end test sets it up: capital, a reserve from earlier years, 3,000 profit this year. */
async function holding(s: Any) {
  await kuwait(s, {
    kuwait: {
      legalForm: 'kscc',
      licenceNumber: '',
      activity: 'general',
      foreignOwnershipPercent: 0,
      capital: 10000,
      pamFileNumber: '',
      pifssEmployerNumber: '',
      mofTaxCardNumber: '',
      kcciNumber: '',
      digitalCommerceNumber: '',
      wamdPhone: '',
    },
  });
  await saveJournal(journal(s, '2025-01-01', [['1000', 14800, 0], ['3000', 0, 10000], ['3200', 0, 4800]]));
  await saveJournal(journal(s, '2026-06-30', [['1000', 3000, 0], ['4100', 0, 3000]]));
}

const CLOSE_2026 = {
  yearStart: '2026-01-01',
  yearEnd: '2026-12-31',
  profitBeforeLevies: 3000,
  lines: [
    { kind: 'statutory_reserve', base: 3000, rate: 10, amount: 200 },
    { kind: 'voluntary_reserve', base: 3000, rate: 0, amount: 0 },
    { kind: 'kfas', base: 2800, rate: 1, amount: 28 },
    { kind: 'zakat', base: 3000, rate: 1, amount: 30.0004 },
  ],
  lock: true,
};

async function yearEndScenarios() {
  const now = { now: '2027-01-20T08:00:00.000Z' };
  await add(
    'a year closed and locked',
    async (s, input) => {
      await holding(s);
      Object.assign(input, { op: 'closeYear', companyId: s.company.id }, copy(CLOSE_2026));
    },
    (input) => closeYear(input.companyId, input),
    now,
  );
  await add(
    'a year closed without locking',
    async (s, input) => {
      await holding(s);
      Object.assign(input, { op: 'closeYear', companyId: s.company.id }, copy(CLOSE_2026), { lock: false });
    },
    (input) => closeYear(input.companyId, input),
    now,
  );
  await add(
    'a year closed with levies only, locked on from an earlier lock date',
    async (s, input) => {
      await holding(s);
      await lockBooks(s.company.id, '2026-06-29');
      Object.assign(input, {
        op: 'closeYear',
        companyId: s.company.id,
        yearStart: '2026-01-01',
        yearEnd: '2026-12-31',
        profitBeforeLevies: 3000.0004,
        lines: [
          { kind: 'nlst', base: 3000, rate: 2.5, amount: 75 },
          { kind: 'income_tax', base: 300.0006, rate: 15, amount: 45 },
        ],
        lock: true,
      });
    },
    (input) => closeYear(input.companyId, input),
    now,
  );
  await add(
    'a year closed on the standard chart makes the reserve and levy accounts',
    async (s, input) => {
      await generic(s);
      Object.assign(input, { op: 'closeYear', companyId: s.company.id }, copy(CLOSE_2026));
    },
    (input) => closeYear(input.companyId, input),
    now,
  );
  await add(
    'a year closed twice is refused',
    async (s, input) => {
      await holding(s);
      await closeYear(s.company.id, { ...CLOSE_2026, lock: false });
      Object.assign(input, { op: 'closeYear', companyId: s.company.id }, copy(CLOSE_2026));
    },
    (input) => closeYear(input.companyId, input),
    now,
  );
  await add(
    'an earlier year closed after a later one is refused',
    async (s, input) => {
      await holding(s);
      await closeYear(s.company.id, { ...CLOSE_2026, lock: false });
      Object.assign(input, {
        op: 'closeYear',
        companyId: s.company.id,
        yearStart: '2025-01-01',
        yearEnd: '2025-12-31',
        profitBeforeLevies: 0,
        lines: [],
        lock: false,
      });
    },
    (input) => closeYear(input.companyId, input),
    now,
  );
  await add(
    'a negative levy is refused',
    async (s, input) => {
      await holding(s);
      Object.assign(input, { op: 'closeYear', companyId: s.company.id }, copy(CLOSE_2026), {
        lines: [{ kind: 'kfas', base: 2800, rate: 1, amount: -28 }],
      });
    },
    (input) => closeYear(input.companyId, input),
    now,
  );
  await add(
    'a locked year is not closed',
    async (s, input) => {
      await holding(s);
      await lockBooks(s.company.id, '2026-12-31');
      Object.assign(input, { op: 'closeYear', companyId: s.company.id }, copy(CLOSE_2026));
    },
    (input) => closeYear(input.companyId, input),
    now,
  );
  await add(
    'a chart without retained earnings is not closed',
    async (s, input) => {
      await holding(s);
      await db.accounts.delete(s.role('retained_earnings').id);
      Object.assign(input, { op: 'closeYear', companyId: s.company.id }, copy(CLOSE_2026));
    },
    (input) => closeYear(input.companyId, input),
    now,
  );
  await add(
    'a closed year reopened',
    async (s, input) => {
      await holding(s);
      const close = await closeYear(s.company.id, { ...CLOSE_2026, lock: false });
      input.op = 'reopenYear';
      input.id = close.id;
    },
    (input) => reopenYear(input.id),
    now,
  );
  await add(
    'a locked year is not reopened',
    async (s, input) => {
      await holding(s);
      const close = await closeYear(s.company.id, CLOSE_2026);
      input.op = 'reopenYear';
      input.id = close.id;
    },
    (input) => reopenYear(input.id),
    now,
  );
  await add(
    'a year is reopened after the later ones',
    async (s, input) => {
      await holding(s);
      const first = await closeYear(s.company.id, {
        yearStart: '2025-01-01',
        yearEnd: '2025-12-31',
        profitBeforeLevies: 0,
        lines: [],
        lock: false,
      });
      await closeYear(s.company.id, { ...CLOSE_2026, lock: false });
      input.op = 'reopenYear';
      input.id = first.id;
    },
    (input) => reopenYear(input.id),
    now,
  );
}

/* -------------------------------------------------------------------------- */
/* Fixed assets                                                               */
/* -------------------------------------------------------------------------- */

function laptop(s: Any, overrides: Any = {}) {
  return createAsset(s.company.id, {
    name: 'Laptops',
    nameAr: ' أجهزة حاسب محمول ',
    assetAccountId: s.code('1520').id,
    accumulatedAccountId: s.code('1530').id,
    expenseAccountId: s.code('6900').id,
    purchaseDate: '2026-01-01',
    depreciationStart: '2026-01-01',
    cost: 1200,
    usefulLifeMonths: 12,
    source: 'purchase',
    paidFromAccountId: s.code('1000').id,
    ...overrides,
  });
}

const OPENING = {
  source: 'opening',
  paidFromAccountId: null,
  purchaseDate: '2024-01-01',
  depreciationStart: '2024-01-01',
  cost: 6000,
  usefulLifeMonths: 60,
  openingDepreciation: 2400,
  openingDepreciationDate: '2025-12-31',
};

async function serverBill(s: Any, accountCode = '1520', status = 'sent') {
  const vendor = await saveClient(
    createClient(s.company.id, { name: 'X-cite', isCustomer: false, isVendor: true }),
  );
  const draft = await draftDocument(s.company, 'bill', vendor);
  draft.issueDate = '2026-03-10';
  draft.items[0] = {
    ...draft.items[0],
    name: 'Server',
    quantity: 2,
    unitPrice: 450.25,
    discount: 10,
    discountType: 'percent',
    taxes: [],
    accountId: s.code(accountCode).id,
  };
  return saveDocument({ ...draft, status } as Any);
}

async function assetScenarios() {
  await add(
    'an asset bought from the bank, numbered',
    async (s, input) => {
      await kuwait(s);
      input.op = 'saveAsset';
      input.asset = laptop(s, { number: ' ' });
    },
    (input) => saveAsset(input.asset),
  );
  await add(
    'a second asset takes the next number',
    async (s, input) => {
      await kuwait(s);
      await saveAsset(laptop(s, { number: 'FA-0009' }));
      input.op = 'saveAsset';
      input.asset = laptop(s, { name: ' Printer ', cost: 300.5004, salvageValue: 20 });
    },
    (input) => saveAsset(input.asset),
  );
  await add(
    'an asset owned before, with depreciation already charged',
    async (s, input) => {
      await kuwait(s);
      input.op = 'saveAsset';
      input.asset = laptop(s, OPENING);
    },
    (input) => saveAsset(input.asset),
  );
  await add(
    'an asset owned before, nothing charged yet',
    async (s, input) => {
      await kuwait(s);
      input.op = 'saveAsset';
      input.asset = laptop(s, { ...OPENING, openingDepreciation: 0, openingDepreciationDate: '2025-12-31' });
    },
    (input) => saveAsset(input.asset),
  );
  await add(
    'a declining balance asset keeps its rate',
    async (s, input) => {
      await kuwait(s);
      input.op = 'saveAsset';
      input.asset = laptop(s, { method: 'declining_balance', decliningRate: 30, usefulLifeMonths: 60 });
    },
    (input) => saveAsset(input.asset),
  );
  const refused: [string, (s: Any) => Any][] = [
    ['no name', (s) => laptop(s, { name: ' ' })],
    ['no fixed asset account', (s) => laptop(s, { assetAccountId: s.code('6000').id })],
    ['no accumulated depreciation account', (s) => laptop(s, { accumulatedAccountId: s.code('6000').id })],
    ['the same account twice', (s) => laptop(s, { accumulatedAccountId: s.code('1520').id })],
    ['no expense account', (s) => laptop(s, { expenseAccountId: s.code('1000').id })],
    ['no dates', (s) => laptop(s, { purchaseDate: '2026-02-30' })],
    ['depreciation before the purchase', (s) => laptop(s, { depreciationStart: '2025-12-31' })],
    ['no cost', (s) => laptop(s, { cost: 0.0004 })],
    ['salvage as much as the cost', (s) => laptop(s, { salvageValue: 1200 })],
    ['a life in part months', (s) => laptop(s, { usefulLifeMonths: 12.5 })],
    ['a yearly rate over 100%', (s) => laptop(s, { method: 'declining_balance', decliningRate: 150 })],
    ['more depreciation charged than there is', (s) => laptop(s, { ...OPENING, openingDepreciation: 6000.5 })],
    ['depreciation charged on a new purchase', (s) => laptop(s, { openingDepreciation: 100, openingDepreciationDate: '2026-02-01' })],
    ['no date for the depreciation charged', (s) => laptop(s, { ...OPENING, openingDepreciationDate: null })],
    ['depreciation charged ending before it starts', (s) => laptop(s, { ...OPENING, openingDepreciationDate: '2023-12-31' })],
    ['paid from an account that holds no money', (s) => laptop(s, { paidFromAccountId: s.code('1520').id })],
    ['a number in use', (s) => laptop(s, { number: 'FA-0001' })],
  ];
  for (const [name, make] of refused) {
    await add(
      `an asset refused: ${name}`,
      async (s, input) => {
        await kuwait(s);
        if (name === 'a number in use') await saveAsset(laptop(s));
        input.op = 'saveAsset';
        input.asset = make(s);
      },
      (input) => saveAsset(input.asset),
    );
  }
  await add(
    'an asset made from a bill line, its cost not posted again',
    async (s, input) => {
      await kuwait(s);
      const bill = await serverBill(s);
      input.op = 'saveAsset';
      input.asset = laptop(s, {
        name: 'Server',
        source: 'bill',
        paidFromAccountId: s.code('1000').id,
        billId: bill.id,
        billLineId: bill.items[0].id,
        cost: 810.45,
        purchaseDate: '2026-03-10',
        depreciationStart: '2026-03-10',
      });
    },
    (input) => saveAsset(input.asset),
  );
  await add(
    'an asset refused: a bill line already made into an asset',
    async (s, input) => {
      await kuwait(s);
      const bill = await serverBill(s);
      const made = { source: 'bill', paidFromAccountId: null, billId: bill.id, billLineId: bill.items[0].id, purchaseDate: '2026-03-10', depreciationStart: '2026-03-10' };
      await saveAsset(laptop(s, made));
      input.op = 'saveAsset';
      input.asset = laptop(s, made);
    },
    (input) => saveAsset(input.asset),
  );
  await add(
    'an asset refused: the bill booked the line elsewhere',
    async (s, input) => {
      await kuwait(s);
      const bill = await serverBill(s, '1540');
      input.op = 'saveAsset';
      input.asset = laptop(s, { source: 'bill', billId: bill.id, billLineId: bill.items[0].id, purchaseDate: '2026-03-10', depreciationStart: '2026-03-10' });
    },
    (input) => saveAsset(input.asset),
  );
  await add(
    'an asset refused: a draft bill',
    async (s, input) => {
      await kuwait(s);
      const bill = await serverBill(s, '1520', 'draft');
      input.op = 'saveAsset';
      input.asset = laptop(s, { source: 'bill', billId: bill.id, billLineId: bill.items[0].id, purchaseDate: '2026-03-10', depreciationStart: '2026-03-10' });
    },
    (input) => saveAsset(input.asset),
  );
  await add(
    'an asset refused: a line of the bill that is not an asset',
    async (s, input) => {
      await kuwait(s);
      const bill = await serverBill(s, '6000');
      input.op = 'saveAsset';
      input.asset = laptop(s, { source: 'bill', billId: bill.id, billLineId: bill.items[0].id, purchaseDate: '2026-03-10', depreciationStart: '2026-03-10' });
    },
    (input) => saveAsset(input.asset),
  );
  await add(
    'an asset moved: its purchase entry follows',
    async (s, input) => {
      await kuwait(s);
      const asset = await saveAsset(laptop(s));
      input.op = 'saveAsset';
      input.asset = { ...asset, location: 'Head office', cost: 1250, purchaseDate: '2026-01-05', depreciationStart: '2026-01-05' };
    },
    (input) => saveAsset(input.asset),
  );
  await add(
    'an asset of a locked period keeps its entry when only its details change',
    async (s, input) => {
      await kuwait(s);
      const asset = await saveAsset(laptop(s));
      await lockBooks(s.company.id, '2026-06-30');
      input.op = 'saveAsset';
      input.asset = { ...asset, location: 'Warehouse', custodian: 'Ahmad', notes: 'Moved in July' };
    },
    (input) => saveAsset(input.asset),
  );
  await add(
    'an asset of a locked period refused when its cost changes',
    async (s, input) => {
      await kuwait(s);
      const asset = await saveAsset(laptop(s));
      await lockBooks(s.company.id, '2026-06-30');
      input.op = 'saveAsset';
      input.asset = { ...asset, cost: 1300 };
    },
    (input) => saveAsset(input.asset),
  );
  await add(
    'an asset bought now said to be owned before: the entry is replaced',
    async (s, input) => {
      await kuwait(s);
      const asset = await saveAsset(laptop(s));
      input.op = 'saveAsset';
      input.asset = { ...asset, ...OPENING };
    },
    (input) => saveAsset(input.asset),
  );
  await add(
    'an asset with depreciation keeps its figures',
    async (s, input) => {
      await kuwait(s);
      const asset = await saveAsset(laptop(s));
      await runDepreciation(s.company.id, '2026-01');
      input.op = 'saveAsset';
      input.asset = { ...asset, cost: 1500 };
    },
    (input) => saveAsset(input.asset),
  );
  await add(
    'an asset with depreciation can still be renamed',
    async (s, input) => {
      await kuwait(s);
      const asset = await saveAsset(laptop(s));
      await runDepreciation(s.company.id, '2026-01');
      input.op = 'saveAsset';
      input.asset = { ...(await db.assets.get(asset.id))!, name: 'Laptops (sales team)', nameAr: '' };
    },
    (input) => saveAsset(input.asset),
  );
  await add(
    'an asset voided',
    async (s, input) => {
      await kuwait(s);
      const asset = await saveAsset(laptop(s));
      input.op = 'voidAsset';
      input.id = asset.id;
    },
    (input) => voidAsset(input.id),
  );
  await add(
    'an asset with depreciation is not voided',
    async (s, input) => {
      await kuwait(s);
      const asset = await saveAsset(laptop(s));
      await runDepreciation(s.company.id, '2026-01');
      input.op = 'voidAsset';
      input.id = asset.id;
    },
    (input) => voidAsset(input.id),
  );
  await add(
    'a void asset is not changed',
    async (s, input) => {
      await kuwait(s);
      const asset = await saveAsset(laptop(s));
      await voidAsset(asset.id);
      input.op = 'saveAsset';
      input.asset = { ...(await db.assets.get(asset.id))!, name: 'Back again' };
    },
    (input) => saveAsset(input.asset),
  );

  // Depreciation runs.
  await add(
    'a depreciation run for two assets, one from the middle of the month',
    async (s, input) => {
      await kuwait(s);
      await saveAsset(laptop(s));
      await saveAsset(laptop(s, { name: 'Car', cost: 9000, usefulLifeMonths: 60, depreciationStart: '2026-01-16' }));
      Object.assign(input, { op: 'runDepreciation', companyId: s.company.id, period: '2026-01' });
    },
    (input) => runDepreciation(input.companyId, input.period),
  );
  await add(
    'a month run again changes nothing',
    async (s, input) => {
      await kuwait(s);
      await saveAsset(laptop(s));
      await runDepreciation(s.company.id, '2026-01');
      Object.assign(input, { op: 'runDepreciation', companyId: s.company.id, period: '2026-01' });
    },
    (input) => runDepreciation(input.companyId, input.period),
  );
  await add(
    'a skipped month is caught up',
    async (s, input) => {
      await kuwait(s);
      await saveAsset(laptop(s));
      await saveAsset(laptop(s, { name: 'Desks', cost: 800.75, usefulLifeMonths: 36, method: 'declining_balance', decliningRate: null, salvageValue: 50 }));
      await runDepreciation(s.company.id, '2026-01');
      Object.assign(input, { op: 'runDepreciation', companyId: s.company.id, period: '2026-03' });
    },
    (input) => runDepreciation(input.companyId, input.period),
  );
  await add(
    'months are run in order',
    async (s, input) => {
      await kuwait(s);
      await saveAsset(laptop(s));
      await runDepreciation(s.company.id, '2026-03');
      Object.assign(input, { op: 'runDepreciation', companyId: s.company.id, period: '2026-02' });
    },
    (input) => runDepreciation(input.companyId, input.period),
  );
  await add(
    'a locked month is not run',
    async (s, input) => {
      await kuwait(s);
      await saveAsset(laptop(s));
      await lockBooks(s.company.id, '2026-02-28');
      Object.assign(input, { op: 'runDepreciation', companyId: s.company.id, period: '2026-02' });
    },
    (input) => runDepreciation(input.companyId, input.period),
  );
  await add(
    'a run after the lock catches up the locked months',
    async (s, input) => {
      await kuwait(s);
      await saveAsset(laptop(s));
      await lockBooks(s.company.id, '2026-02-28');
      Object.assign(input, { op: 'runDepreciation', companyId: s.company.id, period: '2026-03' });
    },
    (input) => runDepreciation(input.companyId, input.period),
  );
  await add(
    'a month not started is not run',
    async (s, input) => {
      await kuwait(s);
      await saveAsset(laptop(s));
      Object.assign(input, { op: 'runDepreciation', companyId: s.company.id, period: '2027-01' });
    },
    (input) => runDepreciation(input.companyId, input.period),
  );
  await add(
    'a month that is not one is refused',
    async (s, input) => {
      await kuwait(s);
      Object.assign(input, { op: 'runDepreciation', companyId: s.company.id, period: '2026-1' });
    },
    (input) => runDepreciation(input.companyId, input.period),
  );
  await add(
    'nothing to charge makes no run',
    async (s, input) => {
      await kuwait(s);
      await saveAsset(laptop(s, { purchaseDate: '2026-06-01', depreciationStart: '2026-06-01' }));
      Object.assign(input, { op: 'runDepreciation', companyId: s.company.id, period: '2026-03' });
    },
    (input) => runDepreciation(input.companyId, input.period),
  );
  await add(
    'the last month of the life charges what is left',
    async (s, input) => {
      await kuwait(s);
      await saveAsset(laptop(s, { cost: 1000, usefulLifeMonths: 7, salvageValue: 0.001 }));
      await runDepreciation(s.company.id, '2026-05');
      Object.assign(input, { op: 'runDepreciation', companyId: s.company.id, period: '2026-11' });
    },
    (input) => runDepreciation(input.companyId, input.period),
  );
  await add(
    'an asset owned before depreciates over the life left',
    async (s, input) => {
      await kuwait(s);
      await saveAsset(laptop(s, OPENING));
      Object.assign(input, { op: 'runDepreciation', companyId: s.company.id, period: '2026-01' });
    },
    (input) => runDepreciation(input.companyId, input.period),
  );
  await add(
    'the latest run undone',
    async (s, input) => {
      await kuwait(s);
      await saveAsset(laptop(s));
      await runDepreciation(s.company.id, '2026-01');
      const feb = (await runDepreciation(s.company.id, '2026-02')).run!;
      input.op = 'reverseDepreciationRun';
      input.id = feb.id;
    },
    (input) => reverseDepreciationRun(input.id),
  );
  await add(
    'an earlier run is not undone',
    async (s, input) => {
      await kuwait(s);
      await saveAsset(laptop(s));
      const jan = (await runDepreciation(s.company.id, '2026-01')).run!;
      await runDepreciation(s.company.id, '2026-02');
      input.op = 'reverseDepreciationRun';
      input.id = jan.id;
    },
    (input) => reverseDepreciationRun(input.id),
  );
  await add(
    'a run of an asset disposed of since is not undone',
    async (s, input) => {
      await kuwait(s);
      const asset = await saveAsset(laptop(s));
      const jan = (await runDepreciation(s.company.id, '2026-01')).run!;
      await disposeAsset(asset.id, { date: '2026-02-10', proceeds: 0, depositAccountId: null });
      input.op = 'reverseDepreciationRun';
      input.id = jan.id;
    },
    (input) => reverseDepreciationRun(input.id),
  );
  await add(
    'a run of a locked month is not undone',
    async (s, input) => {
      await kuwait(s);
      await saveAsset(laptop(s));
      const jan = (await runDepreciation(s.company.id, '2026-01')).run!;
      await lockBooks(s.company.id, '2026-01-31');
      input.op = 'reverseDepreciationRun';
      input.id = jan.id;
    },
    (input) => reverseDepreciationRun(input.id),
  );

  // Disposal.
  await add(
    'an asset sold at a gain, depreciation charged to the day',
    async (s, input) => {
      await kuwait(s);
      const asset = await saveAsset(laptop(s));
      await runDepreciation(s.company.id, '2026-01');
      await runDepreciation(s.company.id, '2026-02');
      Object.assign(input, { op: 'disposeAsset', id: asset.id, date: '2026-03-15', proceeds: 1000, depositAccountId: s.code('1000').id, notes: ' Sold to staff ' });
    },
    (input) => disposeAsset(input.id, input),
  );
  await add(
    'an asset scrapped at a loss',
    async (s, input) => {
      await kuwait(s);
      const asset = await saveAsset(laptop(s));
      await runDepreciation(s.company.id, '2026-06');
      Object.assign(input, { op: 'disposeAsset', id: asset.id, date: '2026-06-30', proceeds: 0, depositAccountId: null });
    },
    (input) => disposeAsset(input.id, input),
  );
  await add(
    'an asset sold on the standard chart makes the disposal account',
    async (s, input) => {
      await generic(s);
      const list = await accounts(s.company.id);
      const fixed = list.filter((a) => a.type === 'asset_fixed');
      const asset = await saveAsset(
        createAsset(s.company.id, {
          name: 'Van',
          assetAccountId: fixed[0].id,
          accumulatedAccountId: fixed[1].id,
          expenseAccountId: list.find((a) => a.type === 'expense_depreciation' || a.role === 'expense')!.id,
          purchaseDate: '2026-01-01',
          depreciationStart: '2026-01-01',
          cost: 24000,
          usefulLifeMonths: 48,
          source: 'purchase',
          paidFromAccountId: list.find((a) => a.role === 'bank')!.id,
        }),
      );
      Object.assign(input, { op: 'disposeAsset', id: asset.id, date: '2026-04-20', proceeds: 21333.33, depositAccountId: list.find((a) => a.role === 'bank')!.id });
    },
    (input) => disposeAsset(input.id, input),
  );
  const refusedDisposals: [string, Any][] = [
    ['before the last run', { date: '2026-02-10', proceeds: 0, depositAccountId: null }],
    ['before it was bought', { date: '2025-12-31', proceeds: 0, depositAccountId: null }],
    ['without a date', { date: '2026-13-01', proceeds: 0, depositAccountId: null }],
    ['at a negative price', { date: '2026-03-15', proceeds: -1, depositAccountId: null }],
    ['sold with nowhere for the money', { date: '2026-03-15', proceeds: 500, depositAccountId: null }],
    ['sold into an expense account', { date: '2026-03-15', proceeds: 500, depositCode: '6000' }],
    ['in a locked period', { date: '2026-03-15', proceeds: 0, depositAccountId: null, lock: '2026-03-31' }],
  ];
  for (const [name, args] of refusedDisposals) {
    await add(
      `a disposal refused: ${name}`,
      async (s, input) => {
        await kuwait(s);
        const asset = await saveAsset(laptop(s));
        await runDepreciation(s.company.id, '2026-02');
        if (args.lock) await lockBooks(s.company.id, args.lock);
        Object.assign(input, {
          op: 'disposeAsset',
          id: asset.id,
          date: args.date,
          proceeds: args.proceeds,
          depositAccountId: args.depositCode ? s.code(args.depositCode).id : args.depositAccountId,
        });
      },
      (input) => disposeAsset(input.id, input),
    );
  }
  await add(
    'a disposal undone',
    async (s, input) => {
      await kuwait(s);
      const asset = await saveAsset(laptop(s));
      await runDepreciation(s.company.id, '2026-06');
      await disposeAsset(asset.id, { date: '2026-06-30', proceeds: 0, depositAccountId: null });
      input.op = 'undoDisposal';
      input.id = asset.id;
    },
    (input) => undoDisposal(input.id),
  );
  await add(
    'a disposed asset is not voided',
    async (s, input) => {
      await kuwait(s);
      const asset = await saveAsset(laptop(s));
      await disposeAsset(asset.id, { date: '2026-01-10', proceeds: 0, depositAccountId: null });
      input.op = 'voidAsset';
      input.id = asset.id;
    },
    (input) => voidAsset(input.id),
  );
}

/* -------------------------------------------------------------------------- */
/* Banking                                                                    */
/* -------------------------------------------------------------------------- */

const line = (date: string, amount: number, description: string, extra: Any = {}) => ({
  date,
  description,
  reference: '',
  amount,
  balance: null,
  ...extra,
});

const LINES = [
  line('2026-10-01', -3.2, '  Coffee  '),
  line('2026-10-01', -3.2, 'COFFEE'),
  line('2026-10-02', 100.0004, 'Deposit\tfrom   client', { reference: ' DEP-1 ', balance: 1093.6004, valueDate: '2026-10-03' }),
];

const FORMAT = { kind: 'csv', headerRow: 2, mapping: { date: 0, description: 1, amount: 3 }, preset: 'signed', columns: ['Date', 'Details', 'Ref', 'Amount'] };

async function bankingScenarios() {
  const now = { now: '2026-10-20T08:00:00.000Z' };
  await add(
    'a statement imported from a file',
    async (s, input) => {
      await british(s);
      Object.assign(input, { op: 'importStatement', companyId: s.company.id, accountId: s.role('bank').id, lines: LINES, fileName: 'oct.csv' });
    },
    (input) => importStatement(input.companyId, input.accountId, input.lines, input.fileName),
    now,
  );
  await add(
    'an overlapping statement adds only the new line',
    async (s, input) => {
      await british(s);
      await importStatement(s.company.id, s.role('bank').id, LINES, 'oct.csv');
      Object.assign(input, {
        op: 'importStatement',
        companyId: s.company.id,
        accountId: s.role('bank').id,
        lines: [...LINES, line('2026-10-03', -10, 'Parking')],
        fileName: '',
      });
    },
    (input) => importStatement(input.companyId, input.accountId, input.lines, input.fileName),
    now,
  );
  await add(
    'a statement of lines already imported adds nothing',
    async (s, input) => {
      await british(s);
      await importStatement(s.company.id, s.role('bank').id, LINES, 'oct.csv');
      Object.assign(input, { op: 'importStatement', companyId: s.company.id, accountId: s.role('bank').id, lines: LINES.slice(0, 1), fileName: 'again.csv' });
    },
    (input) => importStatement(input.companyId, input.accountId, input.lines, input.fileName),
    now,
  );
  await add(
    'a statement remembered with its layout',
    async (s, input) => {
      await british(s);
      Object.assign(input, { op: 'importStatement', companyId: s.company.id, accountId: s.role('bank').id, lines: LINES.slice(2), fileName: 'oct.xlsx', hasFormat: true, format: FORMAT });
    },
    (input) => importStatement(input.companyId, input.accountId, input.lines, input.fileName, input.format),
    now,
  );
  await add(
    'a statement read the same way writes no layout again',
    async (s, input) => {
      await british(s);
      await importStatement(s.company.id, s.role('bank').id, [], 'sep.xlsx', FORMAT as Any);
      Object.assign(input, { op: 'importStatement', companyId: s.company.id, accountId: s.role('bank').id, lines: LINES.slice(0, 1), fileName: 'oct.xlsx', hasFormat: true, format: { columns: FORMAT.columns, preset: 'signed', mapping: { amount: 3, description: 1, date: 0 }, headerRow: 2, kind: 'csv' } });
    },
    (input) => importStatement(input.companyId, input.accountId, input.lines, input.fileName, input.format),
    now,
  );
  await add(
    'a statement layout forgotten',
    async (s, input) => {
      await british(s);
      await importStatement(s.company.id, s.role('bank').id, [], 'sep.xlsx', FORMAT as Any);
      Object.assign(input, { op: 'importStatement', companyId: s.company.id, accountId: s.role('bank').id, lines: LINES.slice(0, 1), fileName: 'oct.xlsx', hasFormat: true, format: null });
    },
    (input) => importStatement(input.companyId, input.accountId, input.lines, input.fileName, input.format),
    now,
  );
  await add(
    'a statement for an account of another company is refused',
    async (s, input) => {
      await british(s);
      Object.assign(input, { op: 'importStatement', companyId: s.company.id, accountId: 'elsewhere', lines: LINES, fileName: 'oct.csv' });
    },
    (input) => importStatement(input.companyId, input.accountId, input.lines, input.fileName),
    now,
  );

  /** Two statement lines and a transfer and journal in the books to match them with. */
  const books = async (s: Any) => {
    await british(s);
    const { transactions } = await importStatement(s.company.id, s.role('bank').id, [line('2026-10-04', -200, 'CASH WITHDRAWAL'), line('2026-10-05', 75, 'Refund', { reference: 'RF-9' })], '');
    s.lines = transactions;
    s.transfer = await saveTransfer({ companyId: s.company.id, from: s.role('bank').id, to: s.role('cash').id, date: '2026-10-04', amount: 200 });
  };
  await add(
    'a statement line matched',
    async (s, input) => {
      await books(s);
      Object.assign(input, { op: 'matchTransaction', id: s.lines[0].id, match: { source: 'journal', id: s.transfer.id } });
    },
    (input) => matchTransaction(input.id, input.match),
    now,
  );
  await add(
    'an entry matched to one line only',
    async (s, input) => {
      await books(s);
      await matchTransaction(s.lines[0].id, { source: 'journal', id: s.transfer.id });
      Object.assign(input, { op: 'matchTransaction', id: s.lines[1].id, match: { source: 'journal', id: s.transfer.id } });
    },
    (input) => matchTransaction(input.id, input.match),
    now,
  );
  await add(
    'a statement line unmatched',
    async (s, input) => {
      await books(s);
      await matchTransaction(s.lines[0].id, { source: 'journal', id: s.transfer.id });
      Object.assign(input, { op: 'unmatchTransaction', id: s.lines[0].id });
    },
    (input) => unmatchTransaction(input.id),
    now,
  );
  await add(
    'a statement line ignored',
    async (s, input) => {
      await books(s);
      await matchTransaction(s.lines[1].id, { source: 'journal', id: s.transfer.id });
      Object.assign(input, { op: 'ignoreTransaction', id: s.lines[1].id, ignored: true });
    },
    (input) => ignoreTransaction(input.id, input.ignored),
    now,
  );
  await add(
    'an ignored line restored',
    async (s, input) => {
      await books(s);
      await ignoreTransaction(s.lines[1].id, true);
      Object.assign(input, { op: 'ignoreTransaction', id: s.lines[1].id, ignored: false });
    },
    (input) => ignoreTransaction(input.id, input.ignored),
    now,
  );
  await add(
    'a statement line that is gone is not matched',
    async (s, input) => {
      await books(s);
      Object.assign(input, { op: 'unmatchTransaction', id: 'gone' });
    },
    (input) => unmatchTransaction(input.id),
    now,
  );
  await add(
    'a statement line deleted',
    async (s, input) => {
      await books(s);
      Object.assign(input, { op: 'deleteTransaction', id: s.lines[1].id });
    },
    (input) => deleteTransaction(input.id),
    now,
  );
  await add(
    'money moved between two accounts',
    async (s, input) => {
      await british(s);
      Object.assign(input, { op: 'saveTransfer', companyId: s.company.id, from: s.role('bank').id, to: s.role('cash').id, date: '2026-10-06', amount: 150.255 });
    },
    (input) => saveTransfer(input),
    now,
  );
  await add(
    'money moved with a reference',
    async (s, input) => {
      await british(s);
      Object.assign(input, { op: 'saveTransfer', companyId: s.company.id, from: s.role('credit_card').id, to: s.role('bank').id, date: '2026-10-06', amount: 80, reference: '  Card top-up ' });
    },
    (input) => saveTransfer(input),
    now,
  );
  const refusedTransfers: [string, (s: Any) => Any][] = [
    ['to the same account', (s) => ({ from: s.role('bank').id, to: s.role('bank').id, amount: 10 })],
    ['of nothing', (s) => ({ from: s.role('bank').id, to: s.role('cash').id, amount: 0 })],
    ['from an account that is gone', (s) => ({ from: 'gone', to: s.role('cash').id, amount: 10 })],
  ];
  for (const [name, make] of refusedTransfers) {
    await add(
      `a transfer refused: ${name}`,
      async (s, input) => {
        await british(s);
        Object.assign(input, { op: 'saveTransfer', companyId: s.company.id, date: '2026-10-06' }, make(s));
      },
      (input) => saveTransfer(input),
      now,
    );
  }
  await add(
    'a cash withdrawal on the statement recorded as a transfer',
    async (s, input) => {
      await books(s);
      Object.assign(input, { op: 'createFromTransaction', id: s.lines[0].id, action: { kind: 'transfer', otherAccountId: s.role('cash').id } });
    },
    (input) => createFromTransaction(input.id, input.action),
    now,
  );
  await add(
    'a refund on the statement recorded against another account',
    async (s, input) => {
      await books(s);
      Object.assign(input, { op: 'createFromTransaction', id: s.lines[1].id, action: { kind: 'account', accountId: s.role('expense').id } });
    },
    (input) => createFromTransaction(input.id, input.action),
    now,
  );
  await add(
    'a bank charge on the statement without a reference',
    async (s, input) => {
      await british(s);
      const { transactions } = await importStatement(s.company.id, s.role('bank').id, [line('2026-10-07', -12.5, 'Monthly account fee')], '');
      Object.assign(input, { op: 'createFromTransaction', id: transactions[0].id, action: { kind: 'account', accountId: s.role('bank_fees').id } });
    },
    (input) => createFromTransaction(input.id, input.action),
    now,
  );
}

/* -------------------------------------------------------------------------- */
/* VAT returns                                                                */
/* -------------------------------------------------------------------------- */

const VAT = { name: 'VAT', rate: 20, kind: 'standard' };
const Q4 = { start: '2026-10-01', end: '2026-12-31' };

async function issue(s: Any, contact: Any, type: string, issueDate: string, unitPrice: number) {
  const draft = await draftDocument(s.company, type as Any, contact);
  return saveDocument({
    ...draft,
    issueDate,
    dueDate: issueDate,
    status: 'sent',
    items: [{ ...draft.items[0], name: 'Work', quantity: 1, unitPrice, taxes: [VAT] }],
  } as Any);
}

/** A UK company's quarter: a sale and a purchase, and the return the books give. */
async function quarter(s: Any, input: Any, sale = 1200, purchase = 300) {
  await british(s);
  const client = await saveClient(createClient(s.company.id, { name: 'Brightside Retail Group' }));
  const vendor = await saveClient(createClient(s.company.id, { name: 'PaperMill Supplies Ltd', isCustomer: false, isVendor: true }));
  if (sale) await issue(s, client, 'invoice', '2026-10-11', sale);
  if (purchase) await issue(s, vendor, 'bill', '2026-10-21', purchase);
  await figures(s, input, Q4);
}

/** The return the books give now, as the Swift side is handed it. */
async function figures(s: Any, input: Any, period: Any) {
  const company = (await db.companies.get(s.company.id))!;
  const result = await computeVatReturn(company, period);
  const { accounts: list, lines } = await loadLedger(company);
  const totals = vatAccountTotals(lines, period, roleMap(list));
  input.figures = {
    boxes: result.boxes.map((b: Any) => ({ id: b.id, label: b.label, amount: b.amount, ...(b.vat !== undefined ? { vat: b.vat } : {}) })),
    net: result.net,
    output: totals.output,
    input: totals.input,
  };
}

async function vatScenarios() {
  const now = { now: '2027-01-20T08:00:00.000Z' };
  const file = (input: Any) => fileVatReturn(input.companyId, input.period, input);
  await add(
    'a VAT return filed and the quarter locked',
    async (s, input) => {
      await quarter(s, input);
      Object.assign(input, { op: 'fileVatReturn', companyId: s.company.id, period: Q4, filedOn: '2027-01-15', reference: ' HMRC-123 ', lock: true });
    },
    file,
    now,
  );
  await add(
    'a VAT return filed without locking',
    async (s, input) => {
      await quarter(s, input);
      Object.assign(input, { op: 'fileVatReturn', companyId: s.company.id, period: Q4, filedOn: '2027-01-15', reference: '', lock: false });
    },
    file,
    now,
  );
  await add(
    'a VAT return to reclaim, the period locked already',
    async (s, input) => {
      await quarter(s, input, 100, 900);
      await lockBooks(s.company.id, '2027-01-05');
      Object.assign(input, { op: 'fileVatReturn', companyId: s.company.id, period: Q4, filedOn: '2027-01-15', reference: 'R-2', lock: true });
    },
    file,
    now,
  );
  await add(
    'a VAT return with nothing to move',
    async (s, input) => {
      await quarter(s, input, 0, 0);
      Object.assign(input, { op: 'fileVatReturn', companyId: s.company.id, period: Q4, filedOn: '2027-01-15', reference: '', lock: true });
    },
    file,
    now,
  );
  await add(
    'a VAT return filed twice is refused',
    async (s, input) => {
      await quarter(s, input);
      await fileVatReturn(s.company.id, Q4, { filedOn: '2027-01-15', reference: '', lock: false });
      await figures(s, input, Q4);
      Object.assign(input, { op: 'fileVatReturn', companyId: s.company.id, period: Q4, filedOn: '2027-01-16', reference: '', lock: false });
    },
    file,
    now,
  );
  await add(
    'a VAT return refused without VAT accounts',
    async (s, input) => {
      await quarter(s, input);
      await db.accounts.delete(s.role('tax_settlement').id);
      await figures(s, input, Q4);
      Object.assign(input, { op: 'fileVatReturn', companyId: s.company.id, period: Q4, filedOn: '2027-01-15', reference: '', lock: false });
    },
    file,
    now,
  );
  await add(
    'a VAT return undone',
    async (s, input) => {
      await quarter(s, input);
      const record = await fileVatReturn(s.company.id, Q4, { filedOn: '2027-01-15', reference: '', lock: false });
      Object.assign(input, { op: 'undoVatReturn', id: record.id });
    },
    (input) => undoVatReturn(input.id),
    now,
  );
  await add(
    'a VAT return of a locked period is not undone',
    async (s, input) => {
      await quarter(s, input);
      const record = await fileVatReturn(s.company.id, Q4, { filedOn: '2027-01-15', reference: '', lock: true });
      Object.assign(input, { op: 'undoVatReturn', id: record.id });
    },
    (input) => undoVatReturn(input.id),
    now,
  );
  await add(
    'a VAT return undone with its payment',
    async (s, input) => {
      await quarter(s, input);
      const record = await fileVatReturn(s.company.id, Q4, { filedOn: '2027-01-15', reference: '', lock: false });
      await recordVatPayment(record.id, { date: '2027-02-07', accountId: s.role('bank').id });
      Object.assign(input, { op: 'undoVatReturn', id: record.id });
    },
    (input) => undoVatReturn(input.id),
    now,
  );
  await add(
    'a VAT payment recorded',
    async (s, input) => {
      await quarter(s, input);
      const record = await fileVatReturn(s.company.id, Q4, { filedOn: '2027-01-15', reference: '', lock: true });
      Object.assign(input, { op: 'recordVatPayment', id: record.id, date: '2027-02-07', accountId: s.role('bank').id });
    },
    (input) => recordVatPayment(input.id, input),
    now,
  );
  await add(
    'a VAT refund recorded',
    async (s, input) => {
      await quarter(s, input, 100, 900);
      const record = await fileVatReturn(s.company.id, Q4, { filedOn: '2027-01-15', reference: '', lock: false });
      Object.assign(input, { op: 'recordVatPayment', id: record.id, date: '2027-02-07', accountId: s.role('bank').id });
    },
    (input) => recordVatPayment(input.id, input),
    now,
  );
  await add(
    'a VAT payment recorded twice is refused',
    async (s, input) => {
      await quarter(s, input);
      const record = await fileVatReturn(s.company.id, Q4, { filedOn: '2027-01-15', reference: '', lock: false });
      await recordVatPayment(record.id, { date: '2027-02-07', accountId: s.role('bank').id });
      Object.assign(input, { op: 'recordVatPayment', id: record.id, date: '2027-02-08', accountId: s.role('bank').id });
    },
    (input) => recordVatPayment(input.id, input),
    now,
  );
  await add(
    'a VAT return with nothing to pay has no payment',
    async (s, input) => {
      await quarter(s, input, 0, 0);
      const record = await fileVatReturn(s.company.id, Q4, { filedOn: '2027-01-15', reference: '', lock: false });
      Object.assign(input, { op: 'recordVatPayment', id: record.id, date: '2027-02-07', accountId: s.role('bank').id });
    },
    (input) => recordVatPayment(input.id, input),
    now,
  );
  await add(
    'the entry closing a VAT return is not edited by hand',
    async (s, input) => {
      await quarter(s, input);
      const record = await fileVatReturn(s.company.id, Q4, { filedOn: '2027-01-15', reference: '', lock: false });
      input.op = 'saveJournal';
      input.journal = { ...(await db.journals.get(record.journalId!))!, reference: 'Changed' };
    },
    (input) => saveJournal(input.journal),
    now,
  );
  await add(
    'the entry closing a VAT return is not deleted by hand',
    async (s, input) => {
      await quarter(s, input);
      const record = await fileVatReturn(s.company.id, Q4, { filedOn: '2027-01-15', reference: '', lock: false });
      input.op = 'deleteJournal';
      input.id = record.journalId;
    },
    (input) => deleteJournal(input.id),
    now,
  );
}

it('accounting', async () => {
  await chartScenarios();
  await journalScenarios();
  await yearEndScenarios();
  await assetScenarios();
  await bankingScenarios();
  await vatScenarios();
  await arabicScenarios();
  writeFixtures('accounting', out);
  const failed = out.filter((x) => x.error).map((x) => `${x.name}: ${x.error}`);
  console.log(`${out.length} scenarios, ${failed.length} refused:\n  ${failed.join('\n  ')}`);
});
