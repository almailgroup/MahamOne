import Dexie from 'dexie';
import { db } from './db';
import { logActivity } from './activity';
import { accountingSettings } from './chart-setup';
import { defaultNumbering, nowStamp } from './defaults';
import type {
  Account,
  AccountRole,
  Company,
  ID,
  ISODate,
  JournalLine,
  ManualJournal,
  YearEndClose,
  YearEndLine,
  YearEndLineKind,
} from './types';
import {
  buildLedger,
  type LedgerContext,
  type LedgerLine,
  type LedgerProblem,
} from '@/lib/accounting/ledger';
import {
  ACCOUNT_SPECS,
  findSpecAccount,
  freeCode,
  type AccountSpecKey,
} from '@/lib/accounting/charts';
import { ACCOUNTING_OWNED_KINDS, JOURNAL_KINDS } from '@/lib/accounting/journal-kinds';
import { stockLedgerContext } from '@/lib/inventory/sources';
import { financialYearLabel, YEAR_END_LABELS } from '@/lib/accounting/year-end';
import { currencyPrecision, dec, round } from '@/lib/money';
import { allocateNumber } from '@/lib/numbering';
import { newId } from '@/lib/ids';
import { today } from '@/lib/dates';
import { compactIban, formatIban, isValidIban } from '@/lib/kuwait';
import { interfaceLocale, msg, t } from '@/i18n';
import { formatDate } from '@/lib/format';

/* -------------------------------------------------------------------------- */
/* Lock date                                                                  */
/* -------------------------------------------------------------------------- */

export class LockedPeriodError extends Error {
  constructor(lockDate: ISODate, company?: Pick<Company, 'dateFormat' | 'locale'>) {
    const date = company
      ? formatDate(lockDate, company.dateFormat, interfaceLocale(company.locale))
      : lockDate;
    super(
      t(
        'The books are locked up to {date}. Change the lock date in Settings → Accounting to edit earlier transactions.',
        { date },
      ),
    );
  }
}

/** Throws when any of the dates falls on or before the company's lock date. */
export function assertUnlocked(company: Company, ...dates: (ISODate | null | undefined)[]): void {
  const lock = accountingSettings(company).lockDate;
  if (!lock) return;
  if (dates.some((d) => d && d <= lock)) throw new LockedPeriodError(lock, company);
}

/* -------------------------------------------------------------------------- */
/* Accounts                                                                   */
/* -------------------------------------------------------------------------- */

/** The account for each automatic posting (active accounts first). */
export function roleMap(accounts: Account[]): Partial<Record<AccountRole, ID>> {
  const roles: Partial<Record<AccountRole, ID>> = {};
  const ordered = [...accounts].sort((a, b) => Number(a.archived) - Number(b.archived));
  for (const a of ordered) if (a.role && !roles[a.role]) roles[a.role] = a.id;
  return roles;
}

export function createAccount(companyId: ID, overrides: Partial<Account> = {}): Account {
  const stamp = nowStamp();
  return {
    id: newId(),
    companyId,
    code: '',
    name: '',
    type: 'expense',
    description: '',
    role: null,
    bank: null,
    archived: false,
    createdAt: stamp,
    updatedAt: stamp,
    ...overrides,
  };
}

export class AccountError extends Error {}

/** Bank details as stored: the IBAN grouped in fours, the BIC in capitals. */
export function cleanBankDetails(bank: Account['bank']): Account['bank'] {
  if (!bank) return null;
  const iban = compactIban(bank.iban);
  const cleaned = {
    institution: bank.institution.trim(),
    accountNumber: bank.accountNumber.trim(),
    iban: iban ? formatIban(iban) : '',
    bic: bank.bic.trim().toUpperCase(),
  };
  return Object.values(cleaned).some(Boolean) ? cleaned : null;
}

export async function saveAccount(input: Account): Promise<Account> {
  return db.transaction('rw', [db.accounts, db.activities], async () => {
    const { nameAr: rawNameAr, ...rest } = input;
    const nameAr = rawNameAr?.trim();
    const account: Account = {
      ...rest,
      code: input.code.trim(),
      name: input.name.trim(),
      ...(nameAr ? { nameAr } : {}),
      bank: cleanBankDetails(input.bank),
    };
    if (!account.name) throw new AccountError(t('Enter a name for the account.'));
    if (!account.code) throw new AccountError(t('Enter a code for the account.'));
    if (account.bank?.iban && !isValidIban(account.bank.iban)) {
      throw new AccountError(t('The IBAN is not valid. Check it against a bank statement.'));
    }
    const sameCode = await db.accounts
      .where('[companyId+code]')
      .equals([account.companyId, account.code])
      .filter((a) => a.id !== account.id)
      .count();
    if (sameCode)
      throw new AccountError(
        t('Code {code} is already used by another account.', { code: account.code }),
      );
    const existing = await db.accounts.get(account.id);
    if (existing?.role && existing.type !== account.type) {
      throw new AccountError(
        t('The type of an account used for automatic postings cannot change.'),
      );
    }
    if (existing?.role && account.archived) {
      throw new AccountError(t('Accounts used for automatic postings cannot be archived.'));
    }
    account.updatedAt = nowStamp();
    await db.accounts.put(account);
    const vars = { code: account.code, name: account.name };
    const arabic = { name: account.nameAr };
    await logActivity(
      account.companyId,
      'account',
      account.id,
      existing ? 'updated' : 'created',
      existing
        ? { text: msg('Account {code} {name} updated'), vars, arabic }
        : { text: msg('Account {code} {name} created'), vars, arabic },
    );
    return account;
  });
}

/**
 * The company's account for a spec (statutory reserve, KFAS payable…),
 * created when the chart doesn't have it. Must run where the accounts and
 * activities tables are writable.
 */
export async function ensureSpecAccount(company: Company, key: AccountSpecKey): Promise<Account> {
  const accounts = await db.accounts.where('companyId').equals(company.id).toArray();
  const found = findSpecAccount(accounts, key, accountingSettings(company).template);
  if (found) return found;
  const spec = ACCOUNT_SPECS[key];
  const account = createAccount(company.id, {
    code: freeCode(accounts, spec.code),
    name: spec.name,
    nameAr: spec.nameAr,
    type: spec.type,
  });
  await db.accounts.add(account);
  await logActivity(company.id, 'account', account.id, 'created', {
    text: msg('Account {code} {name} created'),
    vars: { code: account.code, name: account.name },
    arabic: { name: account.nameAr },
  });
  return account;
}

/** Whether any transaction or setting refers to the account. */
export async function accountInUse(account: Account): Promise<boolean> {
  if (account.role) return true;
  const id = account.id;
  const [journals, payments, products, documents, expenses, assets] = await Promise.all([
    db.journals
      .where('companyId')
      .equals(account.companyId)
      .filter((j) => j.lines.some((l) => l.accountId === id))
      .count(),
    db.payments
      .where('companyId')
      .equals(account.companyId)
      .filter((p) => p.accountId === id)
      .count(),
    db.products
      .where('companyId')
      .equals(account.companyId)
      .filter((p) => p.incomeAccountId === id)
      .count(),
    db.documents
      .where('companyId')
      .equals(account.companyId)
      .filter(
        (d) =>
          d.items.some((i) => i.accountId === id) ||
          Object.values(d.posting?.accounts ?? {}).includes(id),
      )
      .count(),
    db.expenses
      .where('companyId')
      .equals(account.companyId)
      .filter((e) => e.accountId === id || e.paidFromAccountId === id)
      .count(),
    db.assets
      .where('companyId')
      .equals(account.companyId)
      .filter(
        (a) =>
          a.assetAccountId === id ||
          a.accumulatedAccountId === id ||
          a.expenseAccountId === id ||
          a.paidFromAccountId === id,
      )
      .count(),
  ]);
  return journals + payments + products + documents + expenses + assets > 0;
}

export async function deleteAccount(id: ID): Promise<void> {
  const account = await db.accounts.get(id);
  if (!account) return;
  if (await accountInUse(account)) {
    throw new AccountError(
      t('This account is used by transactions or settings. Archive it instead.'),
    );
  }
  await db.accounts.delete(id);
  await logActivity(account.companyId, 'account', id, 'deleted', {
    text: msg('Account {code} {name} deleted'),
    vars: { code: account.code, name: account.name },
    arabic: { name: account.nameAr },
  });
}

/* -------------------------------------------------------------------------- */
/* Manual journals                                                            */
/* -------------------------------------------------------------------------- */

export function newJournalLine(overrides: Partial<JournalLine> = {}): JournalLine {
  return {
    id: newId(),
    accountId: '',
    description: '',
    debit: 0,
    credit: 0,
    contactId: null,
    ...overrides,
  };
}

export function createJournal(
  companyId: ID,
  overrides: Partial<ManualJournal> = {},
): ManualJournal {
  const stamp = nowStamp();
  return {
    id: newId(),
    companyId,
    number: '',
    date: today(),
    reference: '',
    notes: '',
    status: 'posted',
    lines: [newJournalLine(), newJournalLine()],
    createdAt: stamp,
    updatedAt: stamp,
    ...overrides,
  };
}

export class JournalError extends Error {}

/** Totals of a journal in the company currency (debit, credit, difference). */
export function journalTotals(lines: JournalLine[], precision: number) {
  const debit = lines.reduce((acc, l) => acc.plus(dec(l.debit)), dec(0));
  const credit = lines.reduce((acc, l) => acc.plus(dec(l.credit)), dec(0));
  return {
    debit: round(debit, precision),
    credit: round(credit, precision),
    difference: round(debit.minus(credit), precision),
  };
}

export interface JournalWriteOptions {
  /**
   * Set by the part of the app that owns the entry (fixed assets, year-end):
   * entries it owns can only be changed through it.
   */
  system?: boolean;
}

/** Message for an entry that belongs to another part of the app. */
function ownedError(journal: ManualJournal): JournalError {
  const owner = journal.kind ? JOURNAL_KINDS[journal.kind]?.owner : null;
  return new JournalError(
    owner
      ? t('This entry is managed in {place}. Change it there.', { place: t(owner) })
      : t('This entry was made by Maham Books and cannot be changed here.'),
  );
}

function isProtected(journal: ManualJournal | undefined): boolean {
  return Boolean(journal?.kind && ACCOUNTING_OWNED_KINDS.includes(journal.kind));
}

export async function saveJournal(
  input: ManualJournal,
  options: JournalWriteOptions = {},
): Promise<ManualJournal> {
  return db.transaction('rw', [db.journals, db.companies, db.accounts, db.activities], async () => {
    const company = await db.companies.get(input.companyId);
    if (!company) throw new Error(t('Company not found'));
    const existing = await db.journals.get(input.id);
    assertUnlocked(company, input.date, existing?.date);
    if (existing?.vatReturnId) {
      throw new JournalError(t('This entry closes a VAT return. Undo the return to change it.'));
    }
    if (!options.system && (isProtected(existing) || isProtected(input))) {
      throw ownedError(existing ?? input);
    }

    const lines = input.lines.filter((l) => l.accountId && (l.debit !== 0 || l.credit !== 0));
    if (lines.some((l) => l.debit < 0 || l.credit < 0)) {
      throw new JournalError(t('Amounts must be positive. Use the other column to reverse.'));
    }
    if (lines.some((l) => l.debit !== 0 && l.credit !== 0)) {
      throw new JournalError(t('A line can have a debit or a credit, not both.'));
    }
    if (lines.length < 2)
      throw new JournalError(t('A journal needs at least two lines with amounts.'));
    const totals = journalTotals(lines, currencyPrecision(company.currency));
    if (totals.difference !== 0) throw new JournalError(t('Debits and credits must be equal.'));
    const accounts = await db.accounts.bulkGet(lines.map((l) => l.accountId));
    if (accounts.some((a) => !a || a.companyId !== company.id)) {
      throw new JournalError(t('Choose an account on every line.'));
    }

    let journal: ManualJournal = { ...input, lines, number: input.number.trim() };
    if (!journal.number) {
      const rule = company.numbering.journal ?? defaultNumbering().journal;
      const taken = new Set(
        (await db.journals.where('companyId').equals(company.id).toArray())
          .filter((j) => j.id !== journal.id)
          .map((j) => j.number.toLowerCase()),
      );
      const allocated = allocateNumber(rule, journal.date, (n) => taken.has(n.toLowerCase()));
      journal.number = allocated.number;
      await db.companies.put({
        ...company,
        numbering: { ...company.numbering, journal: allocated.rule },
      });
    }
    journal = { ...journal, updatedAt: nowStamp() };
    if (!existing) journal.createdAt = journal.updatedAt;
    await db.journals.put(journal);
    await logActivity(
      company.id,
      'journal',
      journal.id,
      existing ? 'updated' : 'created',
      existing
        ? { text: msg('Journal {number} updated'), vars: { number: journal.number } }
        : { text: msg('Journal {number} created'), vars: { number: journal.number } },
    );
    return journal;
  });
}

export async function deleteJournal(id: ID): Promise<void> {
  await db.transaction('rw', [db.journals, db.companies, db.activities], async () => {
    const journal = await db.journals.get(id);
    if (!journal) return;
    const company = await db.companies.get(journal.companyId);
    if (company) assertUnlocked(company, journal.date);
    if (journal.vatReturnId) {
      throw new JournalError(t('This entry closes a VAT return. Undo the return to remove it.'));
    }
    // Entries made by fixed assets or the year-end close are reversed, never deleted.
    if (isProtected(journal)) throw ownedError(journal);
    await db.journals.delete(id);
    await logActivity(journal.companyId, 'journal', id, 'deleted', {
      text: msg('Journal {number} deleted'),
      vars: { number: journal.number },
    });
  });
}

/**
 * Posts an entry that undoes `journal` (debits and credits swapped), so the
 * history stays in the books. Dated like the original unless a date is given.
 */
export async function reverseJournal(
  journal: ManualJournal,
  options: { date?: ISODate; reference?: string } = {},
): Promise<ManualJournal> {
  return saveJournal(
    createJournal(journal.companyId, {
      date: options.date ?? journal.date,
      reference: options.reference ?? t('Reversal of {number}', { number: journal.number }),
      notes: journal.reference,
      status: 'posted',
      kind: journal.kind,
      sourceId: journal.sourceId ?? null,
      reversalOf: journal.id,
      lines: journal.lines.map((l) =>
        newJournalLine({
          accountId: l.accountId,
          description: l.description,
          contactId: l.contactId,
          debit: l.credit,
          credit: l.debit,
        }),
      ),
    }),
    { system: true },
  );
}

/* -------------------------------------------------------------------------- */
/* Ledger                                                                     */
/* -------------------------------------------------------------------------- */

export interface CompanyLedger {
  accounts: Account[];
  lines: LedgerLine[];
  problems: LedgerProblem[];
  /** Manual and system journals, to tell what kind of entry a journal line comes from. */
  journals: ManualJournal[];
}

/** Builds the general ledger of a company from its documents, payments and journals. */
export async function loadLedger(company: Company): Promise<CompanyLedger> {
  const [accounts, documents, payments, journals, expenses, products, clients] = await Promise.all([
    db.accounts.where('companyId').equals(company.id).toArray(),
    db.documents.where('companyId').equals(company.id).toArray(),
    db.payments.where('companyId').equals(company.id).toArray(),
    db.journals.where('companyId').equals(company.id).toArray(),
    db.expenses.where('companyId').equals(company.id).toArray(),
    db.products.where('companyId').equals(company.id).toArray(),
    db.clients.where('companyId').equals(company.id).toArray(),
  ]);
  // A transaction without the stock tables (seeding demo data) has no stock to post.
  const outer = Dexie.currentTransaction;
  const stockTables = [db.stockMovements, db.stockEntries, db.landedCosts, db.stockIssues];
  const readable = !outer || stockTables.every((table) => outer.storeNames.includes(table.name));
  const [movements, entries, landedCosts, issues] = readable
    ? await Promise.all([
        db.stockMovements.where('companyId').equals(company.id).toArray(),
        db.stockEntries.where('companyId').equals(company.id).toArray(),
        db.landedCosts.where('companyId').equals(company.id).toArray(),
        db.stockIssues.where('companyId').equals(company.id).toArray(),
      ])
    : [[], [], [], []];
  const exempt = new Set(clients.filter((c) => c.taxExempt).map((c) => c.id));
  const byId = new Map(documents.map((d) => [d.id, d]));
  const template = accountingSettings(company).template;
  const ctx: LedgerContext = {
    companyCurrency: company.currency,
    precision: currencyPrecision(company.currency),
    roles: roleMap(accounts),
    accountIds: new Set(accounts.map((a) => a.id)),
    productAccounts: new Map(products.map((p) => [p.id, p.incomeAccountId])),
    taxExempt: (id) => exempt.has(id),
    documents: byId,
    stock: stockLedgerContext({ accounts, products, landedCosts, documents: byId, template }),
    retentionAccounts: {
      receivable: findSpecAccount(accounts, 'retentionsReceivable', template)?.id,
      payable: findSpecAccount(accounts, 'retentionsPayable', template)?.id,
    },
  };
  const { lines, problems } = buildLedger(
    { documents, payments, journals, expenses, stock: { movements, entries, issues } },
    ctx,
  );
  return { accounts, lines, problems, journals };
}

/* -------------------------------------------------------------------------- */
/* Year-end close                                                             */
/* -------------------------------------------------------------------------- */

export class YearEndError extends Error {}

/** Accounts each year-end line posts to: debit (expense or retained earnings) and credit. */
const YEAR_END_ACCOUNTS: Record<YearEndLineKind, [AccountSpecKey | 'retained', AccountSpecKey]> = {
  statutory_reserve: ['retained', 'statutoryReserve'],
  voluntary_reserve: ['retained', 'voluntaryReserve'],
  kfas: ['kfas', 'kfasPayable'],
  zakat: ['zakat', 'zakatPayable'],
  nlst: ['nlst', 'nlstPayable'],
  income_tax: ['incomeTax', 'incomeTaxPayable'],
};

export interface CloseYearInput {
  yearStart: ISODate;
  yearEnd: ISODate;
  profitBeforeLevies: number;
  /** Amounts in the company currency; lines with no amount are left out. */
  lines: { kind: YearEndLineKind; base: number; rate: number; amount: number }[];
  /** Set the lock date to the year end once posted. */
  lock: boolean;
}

/**
 * Closes a financial year: posts the levies (expense against the amount
 * payable) and the transfers from retained earnings to the reserves, dated
 * the last day of the year, and optionally locks the year.
 */
export async function closeYear(companyId: ID, input: CloseYearInput): Promise<YearEndClose> {
  return db.transaction(
    'rw',
    [db.companies, db.accounts, db.journals, db.activities, db.yearEnds],
    async () => {
      const company = await db.companies.get(companyId);
      if (!company) throw new YearEndError(t('Company not found'));
      const p = currencyPrecision(company.currency);
      const closes = (await db.yearEnds.where('companyId').equals(companyId).toArray()).filter(
        (c) => c.status === 'closed',
      );
      if (closes.some((c) => c.yearEnd === input.yearEnd)) {
        throw new YearEndError(t('This financial year is already closed.'));
      }
      if (closes.some((c) => c.yearEnd > input.yearEnd)) {
        throw new YearEndError(t('A later year is already closed. Years are closed in order.'));
      }
      if (input.lines.some((l) => !(l.amount >= 0))) {
        throw new YearEndError(t('Amounts can’t be negative.'));
      }
      assertUnlocked(company, input.yearEnd);
      const retained = roleMap(
        await db.accounts.where('companyId').equals(companyId).toArray(),
      ).retained_earnings;
      if (!retained) {
        throw new YearEndError(t('The chart of accounts has no retained earnings account.'));
      }

      const id = newId();
      const lines: YearEndLine[] = [];
      for (const line of input.lines) {
        const amount = round(line.amount, p);
        if (amount === 0) continue;
        const [debit, credit] = YEAR_END_ACCOUNTS[line.kind];
        lines.push({
          kind: line.kind,
          base: round(line.base, p),
          rate: line.rate,
          amount,
          debitAccountId:
            debit === 'retained' ? retained : (await ensureSpecAccount(company, debit)).id,
          creditAccountId: (await ensureSpecAccount(company, credit)).id,
        });
      }
      const label = financialYearLabel(input.yearStart, input.yearEnd);
      const journalIds: ID[] = [];
      const post = async (reference: string, entries: YearEndLine[]) => {
        if (entries.length === 0) return;
        const journalLines: JournalLine[] = [];
        for (const e of entries) {
          const description = t(YEAR_END_LABELS[e.kind]);
          journalLines.push(
            newJournalLine({ accountId: e.debitAccountId, debit: e.amount, description }),
            newJournalLine({ accountId: e.creditAccountId, credit: e.amount, description }),
          );
        }
        const journal = await saveJournal(
          createJournal(companyId, {
            date: input.yearEnd,
            kind: 'year_end',
            sourceId: id,
            reference,
            status: 'posted',
            lines: journalLines,
          }),
          { system: true },
        );
        journalIds.push(journal.id);
      };
      const isReserve = (l: YearEndLine) =>
        l.kind === 'statutory_reserve' || l.kind === 'voluntary_reserve';
      await post(
        t('KFAS, Zakat, NLST and income tax for {year}', { year: label }),
        lines.filter((l) => !isReserve(l)),
      );
      await post(t('Transfers to reserves for {year}', { year: label }), lines.filter(isReserve));

      const fresh = (await db.companies.get(companyId))!;
      const settings = accountingSettings(fresh);
      const lockedTo =
        input.lock && (!settings.lockDate || settings.lockDate < input.yearEnd)
          ? input.yearEnd
          : null;
      if (lockedTo) {
        await db.companies.put({
          ...fresh,
          accounting: { ...settings, lockDate: lockedTo },
          updatedAt: nowStamp(),
        });
      }
      const stamp = nowStamp();
      const close: YearEndClose = {
        id,
        companyId,
        yearStart: input.yearStart,
        yearEnd: input.yearEnd,
        profitBeforeLevies: round(input.profitBeforeLevies, p),
        lines,
        journalIds,
        lockedTo,
        status: 'closed',
        reversalJournalIds: [],
        createdAt: stamp,
        updatedAt: stamp,
      };
      await db.yearEnds.add(close);
      await logActivity(companyId, 'year_end', id, 'closed', {
        text: msg('Financial year {year} closed'),
        vars: { year: label },
      });
      return close;
    },
  );
}

/** Reopens a closed year: its entries are reversed. The year must not be locked. */
export async function reopenYear(id: ID): Promise<void> {
  await db.transaction(
    'rw',
    [db.companies, db.accounts, db.journals, db.activities, db.yearEnds],
    async () => {
      const close = await db.yearEnds.get(id);
      if (!close || close.status !== 'closed') return;
      const company = await db.companies.get(close.companyId);
      if (!company) throw new YearEndError(t('Company not found'));
      const later = (await db.yearEnds.where('companyId').equals(close.companyId).toArray()).find(
        (c) => c.status === 'closed' && c.yearEnd > close.yearEnd,
      );
      if (later) {
        throw new YearEndError(
          t('Reopen {year} first.', { year: financialYearLabel(later.yearStart, later.yearEnd) }),
        );
      }
      assertUnlocked(company, close.yearEnd);
      const reversalJournalIds: ID[] = [];
      for (const journalId of close.journalIds) {
        const journal = await db.journals.get(journalId);
        if (journal) reversalJournalIds.push((await reverseJournal(journal)).id);
      }
      await db.yearEnds.put({
        ...close,
        status: 'reopened',
        reversalJournalIds,
        updatedAt: nowStamp(),
      });
      await logActivity(close.companyId, 'year_end', id, 'reopened', {
        text: msg('Financial year {year} reopened'),
        vars: { year: financialYearLabel(close.yearStart, close.yearEnd) },
      });
    },
  );
}
