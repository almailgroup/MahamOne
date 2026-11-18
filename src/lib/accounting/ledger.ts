import type {
  AccountRole,
  DocumentType,
  Expense,
  ID,
  ISODate,
  InvoiceDocument,
  ManualJournal,
  Payment,
  PostingSnapshot,
  StockEntry,
  StockIssue,
  StockMovement,
  TaxKind,
  TaxLine,
} from '@/db/types';
import { computeDocument } from '@/lib/document-calc';
import { isReverseCharge, taxKind } from '@/lib/calc';
import { Decimal, dec, toMinor } from '@/lib/money';
import { postsToLedger } from '@/lib/document-types';
import { interpolate, msg, t, type Vars } from '@/i18n';

/**
 * The general ledger is derived from the business documents: every issued
 * invoice, credit note, bill, vendor credit, payment, expense and posted manual
 * journal turns into balanced
 * debit/credit lines here. Nothing is stored twice, so the books always match
 * the documents; the lock date protects closed periods.
 *
 * Stock: bill and vendor credit lines of stock items post to inventory; the
 * stock movements (costed at the weighted average, see lib/inventory) post
 * the cost of sales of invoices and credit notes, opening stock and
 * adjustments, so the inventory account always equals the stock valuation.
 */

export type LedgerSource =
  | 'invoice'
  | 'credit'
  | 'bill'
  | 'vendor_credit'
  | 'payment'
  | 'expense'
  | 'journal'
  | 'stock'
  | 'issue';

/**
 * What a line means for VAT returns (like Odoo's tax tags): the value of
 * a sale or purchase, or the tax on it, and how that tax is reported.
 */
export interface VatTag {
  flow: 'sale' | 'purchase';
  part: 'base' | 'tax';
  /** `none` when no tax was chosen for the line. */
  kind: TaxKind | 'none';
  rate: number;
}

export interface LedgerLine {
  date: ISODate;
  accountId: ID;
  /** Company-currency minor units; positive is a debit, negative a credit. */
  amount: number;
  source: LedgerSource;
  sourceId: ID;
  /** Document number shown in reports, e.g. "INV-2026-0001". */
  number: string;
  contactId: ID | null;
  /** In English; show it with `lineDescription` so generated wording is translated. */
  description: string;
  /** Wording the ledger made up ("Invoice {number}"), to show in the reader's language. */
  label?: LedgerLabel;
  vat?: VatTag;
  /** Part of the entry that closes a VAT return; later returns leave it out. */
  settlement?: boolean;
}

export interface LedgerProblem {
  source: LedgerSource;
  sourceId: ID;
  number: string;
  /** In English; show it with `problemText`. */
  message: string;
  label?: LedgerLabel;
}

/**
 * Text written by the ledger: an English key (marked with `msg`) and its
 * values. `terms` names values that are English keys themselves.
 */
export interface LedgerLabel {
  text: string;
  vars?: Record<string, string>;
  terms?: string[];
}

type Translate = (text: string, vars?: Vars) => string;

function labelText(label: LedgerLabel, translate: Translate): string {
  const vars = { ...label.vars };
  for (const term of label.terms ?? []) if (vars[term]) vars[term] = translate(vars[term]);
  return translate(label.text, vars);
}

/** A line's description in the interface language, or a report's (`translate`). */
export function lineDescription(
  line: Pick<LedgerLine, 'description' | 'label'>,
  translate: Translate = t,
): string {
  return line.label ? labelText(line.label, translate) : line.description;
}

/** A problem in the interface language, or a report's (`translate`). */
export function problemText(
  problem: Pick<LedgerProblem, 'message' | 'label'>,
  translate: Translate = t,
): string {
  return problem.label ? labelText(problem.label, translate) : problem.message;
}

/** Description of a generated line: the English text and its label. */
function described(text: string, vars: Record<string, string>) {
  return { description: interpolate(text, vars), label: { text, vars } };
}

/** An entry that cannot be posted; `label` is its message for the reader. */
export class LedgerError extends Error {
  constructor(
    message: string,
    readonly label: LedgerLabel,
  ) {
    super(message);
  }
}

export interface LedgerContext {
  companyCurrency: string;
  /** Minor-unit digits of the company currency. */
  precision: number;
  /** Account used for each automatic posting. */
  roles: Partial<Record<AccountRole, ID>>;
  /** Accounts that exist (and may be used); overrides pointing elsewhere fall back. */
  accountIds: Set<ID>;
  productAccounts: Map<ID, ID | null | undefined>;
  taxExempt: (clientId: ID) => boolean;
  /** All documents by id, so payments can use the invoice's exchange rate. */
  documents: Map<ID, InvoiceDocument>;
  /** Missing until the company tracks stock. */
  stock?: StockLedgerContext;
  /**
   * 1110 Retentions receivable and 2010 Retentions payable (looked up by
   * spec, they have no role). Without one, a retention stays on the
   * receivable (payable).
   */
  retentionAccounts?: { receivable?: ID | null; payable?: ID | null };
  /**
   * What each payment and credit application clears from a document in
   * another currency, in company-currency minor units (see
   * `documentClearing`). Without it each part is converted on its own.
   */
  clearing?: Map<string, number>;
}

/** Accounts and items the stock postings need (see lib/inventory/accounts.ts). */
export interface StockLedgerContext {
  /** Stock items: their bill and vendor credit lines post to inventory. */
  products: Set<ID>;
  inventoryAccountId: ID | null;
  costOfSalesAccountId: ID | null;
  adjustmentAccountId: ID | null;
  /** Where items issued to employees are booked; missing until an issue needs it. */
  issuedItemsAccountId?: ID | null;
  /** Bill lines and charges allocated as landed costs, as "billId:lineId". */
  landedCostLines: Set<string>;
}

/** What the stock postings read from a movement. */
export type StockMovementPosting = Pick<
  StockMovement,
  'value' | 'sourceValue' | 'sourceType' | 'sourceId' | 'documentId'
>;

export class UnbalancedEntryError extends LedgerError {
  constructor(message: string) {
    super(message, { text: msg('This entry does not balance.') });
  }
}

/** What the accounts of each role hold, for "no account is set up" problems. */
const ROLE_NAMES: Record<AccountRole, string> = {
  receivable: msg('Money owed by clients'),
  payable: msg('Money owed to vendors'),
  bank: msg('Bank'),
  cash: msg('Cash payments'),
  credit_card: msg('Company card'),
  sales: msg('Sales'),
  charges: msg('Delivery and other charges'),
  output_tax: msg('Tax charged on sales'),
  input_tax: msg('Tax paid on purchases'),
  tax_settlement: msg('VAT owed to (or due from) the tax office'),
  fx: msg('Exchange gains and losses'),
  capital: msg('Owner or share capital'),
  drawings: msg('Drawings'),
  retained_earnings: msg('Retained earnings'),
  opening_balance: msg('Opening balances'),
  cost_of_sales: msg('Cost of sales'),
  expense: msg('Expenses'),
  bank_fees: msg('Bank charges'),
};

/** Company-currency value of one unit of the document currency. */
export function rateOf(
  item: { currency: string; exchangeRate?: number },
  ctx: Pick<LedgerContext, 'companyCurrency'>,
): number {
  if (item.currency === ctx.companyCurrency) return 1;
  const rate = item.exchangeRate;
  return rate && Number.isFinite(rate) && rate > 0 ? rate : 1;
}

export function needsRate(
  item: { currency: string; exchangeRate?: number },
  ctx: Pick<LedgerContext, 'companyCurrency'>,
): boolean {
  if (item.currency === ctx.companyCurrency) return false;
  return !(item.exchangeRate && Number.isFinite(item.exchangeRate) && item.exchangeRate > 0);
}

/**
 * Documents that are part of the books (issued, not void). Quotes, proformas,
 * sales and purchase orders and delivery notes never are.
 */
export function isPosted(doc: Pick<InvoiceDocument, 'type' | 'status'>): boolean {
  if (!postsToLedger(doc.type)) return false;
  return doc.status !== 'draft' && doc.status !== 'void';
}

/**
 * Whether a document posts without tax: as fixed when it was issued, or
 * (documents issued before that was kept) as its contact is now.
 */
export function postingTaxExempt(
  doc: Pick<InvoiceDocument, 'clientId' | 'posting'>,
  taxExempt: (clientId: ID) => boolean,
): boolean {
  if (doc.posting) return doc.posting.taxExempt;
  return doc.clientId ? taxExempt(doc.clientId) : false;
}

/**
 * What a document posts with, fixed when it is issued: its contact's tax
 * exemption and, on sales documents, the income account of each line's
 * product (lines with an account of their own keep it).
 */
export function postingSnapshot(
  doc: Pick<InvoiceDocument, 'type' | 'items'>,
  taxExempt: boolean,
  productAccounts: Map<ID, ID | null | undefined>,
): PostingSnapshot {
  const accounts: Record<ID, ID> = {};
  if (doc.type === 'invoice' || doc.type === 'credit') {
    for (const item of doc.items) {
      const account = item.productId ? productAccounts.get(item.productId) : null;
      if (item.kind !== 'heading' && account) accounts[item.id] = account;
    }
  }
  return { taxExempt, accounts };
}

function role(ctx: LedgerContext, name: AccountRole, fallback?: AccountRole): ID {
  const id = ctx.roles[name] ?? (fallback ? ctx.roles[fallback] : undefined);
  if (!id) {
    throw new LedgerError(`No account is set up for "${name}".`, {
      text: msg('No account is set up for “{account}”. Choose one in the accounting settings.'),
      vars: { account: ROLE_NAMES[name] },
      terms: ['account'],
    });
  }
  return id;
}

function usable(ctx: LedgerContext, id: ID | null | undefined): ID | null {
  return id && ctx.accountIds.has(id) ? id : null;
}

/**
 * Splits `total` minor units over weights. Each share is rounded and the
 * remainder goes to the largest weight, so the parts always add up exactly.
 */
export function allocate(total: number, weights: Decimal[]): number[] {
  if (weights.length === 0) return [];
  const sum = weights.reduce((acc, w) => acc.plus(w), new Decimal(0));
  if (sum.isZero()) return weights.map((_, i) => (i === 0 ? total : 0));
  const parts = weights.map((w) => toMinor(dec(total).times(w).dividedBy(sum), 0));
  const diff = total - parts.reduce((a, b) => a + b, 0);
  if (diff !== 0) {
    let largest = 0;
    weights.forEach((w, i) => {
      if (w.abs().gt(weights[largest].abs())) largest = i;
    });
    parts[largest] += diff;
  }
  return parts;
}

function balanced(lines: LedgerLine[]): boolean {
  return lines.reduce((acc, l) => acc + l.amount, 0) === 0;
}

/** "VAT 5% reverse charge": the tax keeps its own name. */
function reverseCharge(tax: { name: string; rate: number }) {
  return described(msg('{tax} {rate}% reverse charge'), {
    tax: tax.name,
    rate: String(tax.rate),
  });
}

function rateProblem(currency: string) {
  return {
    message: `No exchange rate for ${currency}; 1:1 was used.`,
    label: { text: msg('No exchange rate for {currency}; 1:1 was used.'), vars: { currency } },
  };
}

type PostedType = 'invoice' | 'credit' | 'bill' | 'vendor_credit';

/** How each document type posts: the partner account side and default accounts. */
const POSTING: Record<
  PostedType,
  {
    partner: AccountRole;
    tax: AccountRole;
    line: AccountRole;
    charges: AccountRole;
    sign: 1 | -1;
    /** Description of the entry, e.g. "Invoice {number}". */
    numbered: string;
  }
> = {
  // Sales: debit receivable, credit income and output tax.
  invoice: {
    partner: 'receivable',
    tax: 'output_tax',
    line: 'sales',
    charges: 'charges',
    sign: 1,
    numbered: msg('Invoice {number}'),
  },
  credit: {
    partner: 'receivable',
    tax: 'output_tax',
    line: 'sales',
    charges: 'charges',
    sign: -1,
    numbered: msg('Credit note {number}'),
  },
  // Purchases: credit payable, debit expenses and input tax.
  bill: {
    partner: 'payable',
    tax: 'input_tax',
    line: 'expense',
    charges: 'expense',
    sign: -1,
    numbered: msg('Bill {number}'),
  },
  vendor_credit: {
    partner: 'payable',
    tax: 'input_tax',
    line: 'expense',
    charges: 'expense',
    sign: 1,
    numbered: msg('Vendor credit {number}'),
  },
};

function isPostedType(type: DocumentType): type is PostedType {
  return postsToLedger(type);
}

interface WeighedEntry {
  /** Line or charge id. */
  id: ID;
  kind: 'item' | 'charge';
  /** Index in `items` or `charges`. */
  index: number;
  /** Share of the net amount (after the document discount, without tax). */
  weight: Decimal;
  taxes: TaxLine[];
  label: string;
}

/**
 * The document's total, taxes and net amount in company-currency minor units,
 * and the weight of each line and charge in that net amount: its share after
 * the document discount, without tax (prices that include tax have it backed out).
 */
function weighDocument(
  doc: InvoiceDocument,
  ctx: Pick<LedgerContext, 'companyCurrency' | 'precision' | 'taxExempt'>,
) {
  const exempt = postingTaxExempt(doc, ctx.taxExempt);
  const result = computeDocument(doc, { taxExempt: exempt });
  const rate = rateOf(doc, ctx);
  const p = ctx.precision;

  const total = toMinor(dec(result.total).times(rate), p);
  // Held back by the customer (or from the vendor) until it is released.
  const retention = toMinor(dec(result.retention).times(rate), p);
  const taxes = result.taxes.map((t) => ({ ...t, minor: toMinor(dec(t.amount).times(rate), p) }));
  // Reverse charge is not part of the total: it never reduces the income.
  const chargedTaxes = taxes.filter((t) => t.kind !== 'reverse_charge');
  const reverseTaxes = taxes.filter((t) => t.kind === 'reverse_charge');
  const income = total - chargedTaxes.reduce((acc, t) => acc + t.minor, 0);

  const ratio =
    result.subtotal === 0
      ? new Decimal(1)
      : dec(result.subtotal).minus(dec(result.discount)).dividedBy(dec(result.subtotal));
  const rateSum = (list: { rate: number }[]) =>
    list
      .reduce((acc, t) => acc.plus(dec(t.rate)), new Decimal(0))
      .dividedBy(100)
      .plus(1);
  const docTaxes = exempt ? [] : doc.taxes;
  const entries: WeighedEntry[] = [];
  doc.items.forEach((item, i) => {
    if (item.kind === 'heading') return;
    const taxesOnLine = exempt ? [] : [...item.taxes, ...docTaxes];
    let weight = dec(result.lines[i].net).times(ratio);
    const charged = taxesOnLine.filter((t) => !isReverseCharge(t));
    if (doc.pricesIncludeTax && charged.length) weight = weight.dividedBy(rateSum(charged));
    entries.push({
      id: item.id,
      kind: 'item',
      index: i,
      weight,
      taxes: taxesOnLine,
      label: item.name,
    });
  });
  doc.charges.forEach((charge, i) => {
    const taxesOnCharge = exempt ? [] : charge.taxes;
    let weight = dec(charge.amount);
    const charged = taxesOnCharge.filter((t) => !isReverseCharge(t));
    if (doc.pricesIncludeTax && charged.length) weight = weight.dividedBy(rateSum(charged));
    entries.push({
      id: charge.id,
      kind: 'charge',
      index: i,
      weight,
      taxes: taxesOnCharge,
      label: charge.label,
    });
  });
  return { exempt, total, retention, chargedTaxes, reverseTaxes, income, entries };
}

/**
 * Net amount of each line and charge of a document, in company-currency
 * minor units (after the document discount, without tax). The parts add up
 * to the document's net amount exactly. Stock lines of bills post these
 * amounts to inventory, and their stock movements take the same values.
 */
export function documentLineParts(
  doc: InvoiceDocument,
  ctx: Pick<LedgerContext, 'companyCurrency' | 'precision' | 'taxExempt'>,
): Map<ID, number> {
  const w = weighDocument(doc, ctx);
  const parts = allocate(
    w.income,
    w.entries.map((e) => e.weight),
  );
  return new Map(w.entries.map((e, i) => [e.id, parts[i]]));
}

/** Lines (and charges) of a bill or vendor credit that post to inventory. */
function stockEntryIds(doc: InvoiceDocument, entries: WeighedEntry[], ctx: LedgerContext): Set<ID> {
  const stock = ctx.stock;
  const ids = new Set<ID>();
  if (!stock || (doc.type !== 'bill' && doc.type !== 'vendor_credit')) return ids;
  for (const e of entries) {
    const productId = e.kind === 'item' ? doc.items[e.index].productId : null;
    if (
      (productId && stock.products.has(productId)) ||
      stock.landedCostLines.has(`${doc.id}:${e.id}`)
    ) {
      ids.add(e.id);
    }
  }
  return ids;
}

function inventoryAccount(ctx: LedgerContext): ID {
  const id = usable(ctx, ctx.stock?.inventoryAccountId);
  if (!id) {
    throw new LedgerError('No inventory account is set up.', {
      text: msg('No inventory account is set up.'),
    });
  }
  return id;
}

function costOfSalesAccount(ctx: LedgerContext): ID {
  return usable(ctx, ctx.stock?.costOfSalesAccountId) ?? role(ctx, 'cost_of_sales');
}

/** Ledger lines of an invoice, credit note, bill or vendor credit. */
export function postDocument(doc: InvoiceDocument, ctx: LedgerContext): LedgerLine[] {
  if (!isPosted(doc) || !isPostedType(doc.type)) return [];
  const rule = POSTING[doc.type];
  const sales = rule.partner === 'receivable';
  // Sign of the partner (receivable/payable) line; the other lines take the opposite.
  const sign = rule.sign;
  const w = weighDocument(doc, ctx);
  const exempt = w.exempt;
  const flow = sales ? 'sale' : 'purchase';
  // The base lines are grouped by account and by how their tax is reported.
  const tagOf = (taxes: TaxLine[]): VatTag => {
    const first = taxes.find((t) => !isReverseCharge(t)) ?? taxes[0];
    if (first) return { flow, part: 'base', kind: taxKind(first), rate: first.rate };
    // Sales to tax-exempt clients (exports, charities) are reported as zero-rated.
    return { flow, part: 'base', kind: exempt && sales ? 'zero' : 'none', rate: 0 };
  };
  const groups = new Map<
    string,
    { accountId: ID; weight: Decimal; minor: number; label: string; vat: VatTag }
  >();
  const add = (accountId: ID, weight: Decimal, minor: number, label: string, taxes: TaxLine[]) => {
    const vat = tagOf(taxes);
    const key = `${accountId}|${vat.kind}|${vat.rate}`;
    const g = groups.get(key);
    if (g) {
      g.weight = g.weight.plus(weight);
      g.minor += minor;
    } else groups.set(key, { accountId, weight, minor, label, vat });
  };
  // With stock lines, every line takes its own exact part, so the inventory
  // posted equals the value of the stock received.
  const stockIds = stockEntryIds(doc, w.entries, ctx);
  const parts = stockIds.size
    ? allocate(
        w.income,
        w.entries.map((e) => e.weight),
      )
    : null;
  w.entries.forEach((e, i) => {
    let account: ID;
    if (stockIds.has(e.id)) account = inventoryAccount(ctx);
    else if (e.kind === 'charge') account = role(ctx, rule.charges, rule.line);
    else {
      const item = doc.items[e.index];
      // The product's income account as it was when the document was issued.
      const productAccount = doc.posting
        ? doc.posting.accounts[item.id]
        : item.productId
          ? ctx.productAccounts.get(item.productId)
          : null;
      account =
        usable(ctx, item.accountId) ??
        (sales ? usable(ctx, productAccount) : null) ??
        role(ctx, rule.line);
    }
    add(account, e.weight, parts ? parts[i] : 0, e.label, e.taxes);
  });
  if (groups.size === 0) add(role(ctx, rule.line), new Decimal(1), w.income, '', []);

  const base = {
    date: doc.issueDate,
    source: doc.type as LedgerSource,
    sourceId: doc.id,
    number: doc.number,
    contactId: doc.clientId || null,
  };
  const named = described(rule.numbered, { number: doc.number });
  // A retention held back by the customer (or from the vendor) is not due
  // yet: it waits in retentions receivable (payable) until it is released.
  const retentionAccount = usable(
    ctx,
    sales ? ctx.retentionAccounts?.receivable : ctx.retentionAccounts?.payable,
  );
  const retained =
    retentionAccount && w.retention > 0 ? Math.min(w.retention, Math.max(w.total, 0)) : 0;
  const lines: LedgerLine[] = [
    {
      ...base,
      accountId: role(ctx, rule.partner),
      amount: sign * (w.total - retained),
      ...named,
    },
  ];
  if (retained > 0 && retentionAccount) {
    lines.push({
      ...base,
      accountId: retentionAccount,
      amount: sign * retained,
      ...described(msg('Retention {number}'), { number: doc.number }),
    });
  }
  const entries = [...groups.values()];
  const amounts = parts
    ? entries.map((g) => g.minor)
    : allocate(
        w.income,
        entries.map((g) => g.weight),
      );
  amounts.forEach((minor, i) => {
    const g = entries[i];
    lines.push({
      ...base,
      accountId: g.accountId,
      amount: -sign * minor,
      ...(entries.length > 1 && g.label ? { description: g.label } : named),
      vat: g.vat,
    });
  });
  for (const t of w.chargedTaxes) {
    lines.push({
      ...base,
      accountId: role(ctx, rule.tax),
      amount: -sign * t.minor,
      description: `${t.name} ${t.rate}%`,
      vat: { flow, part: 'tax', kind: t.kind, rate: t.rate },
    });
  }
  // Reverse charge on a purchase: the buyer owes the VAT and reclaims it at
  // once (input and output tax). On a sale the customer accounts for it.
  if (!sales) {
    for (const t of w.reverseTaxes) {
      const vat: VatTag = { flow, part: 'tax', kind: 'reverse_charge', rate: t.rate };
      const text = reverseCharge(t);
      lines.push(
        { ...base, accountId: role(ctx, 'input_tax'), amount: -sign * t.minor, ...text, vat },
        { ...base, accountId: role(ctx, 'output_tax'), amount: sign * t.minor, ...text, vat },
      );
    }
  }
  const kept = lines.filter((l) => l.amount !== 0);
  if (!balanced(kept)) {
    throw new UnbalancedEntryError(`${named.description} does not balance`);
  }
  return kept;
}

/**
 * Whether a document has lines that move stock or post to inventory, so its
 * stock postings must be checked even when it has no movements.
 */
function touchesStock(doc: InvoiceDocument, ctx: LedgerContext): boolean {
  const stock = ctx.stock;
  if (!stock) return false;
  return (
    doc.items.some((i) => i.kind === 'item' && i.productId && stock.products.has(i.productId)) ||
    [...doc.items, ...doc.charges].some((l) => stock.landedCostLines.has(`${doc.id}:${l.id}`))
  );
}

/**
 * Stock postings of a document. Invoices and credit notes: cost of sales
 * against inventory, at the value of their movements. Bills and vendor
 * credits post their stock lines to inventory themselves; when the stock
 * moved at another value (stock received into negative quantities, a landed
 * cost on goods already sold, a vendor credit above the stock's value) the
 * difference goes to cost of sales.
 */
export function postDocumentStock(
  doc: InvoiceDocument,
  movements: StockMovementPosting[],
  ctx: LedgerContext,
): LedgerLine[] {
  if (!isPosted(doc) || !isPostedType(doc.type) || !ctx.stock) return [];
  const p = ctx.precision;
  const moved = movements.reduce((acc, m) => acc + toMinor(m.value, p), 0);
  let expected = 0;
  if (doc.type === 'bill' || doc.type === 'vendor_credit') {
    const w = weighDocument(doc, ctx);
    const ids = stockEntryIds(doc, w.entries, ctx);
    if (ids.size) {
      const parts = allocate(
        w.income,
        w.entries.map((e) => e.weight),
      );
      const posted = w.entries.reduce((acc, e, i) => acc + (ids.has(e.id) ? parts[i] : 0), 0);
      expected = -POSTING[doc.type].sign * posted;
    }
  }
  const difference = moved - expected;
  if (difference === 0) return [];
  const base = {
    date: doc.issueDate,
    source: doc.type as LedgerSource,
    sourceId: doc.id,
    number: doc.number,
    contactId: doc.clientId || null,
  };
  const text = described(
    doc.type === 'invoice' || doc.type === 'credit'
      ? msg('Cost of sales {number}')
      : msg('Stock cost difference {number}'),
    { number: doc.number },
  );
  return [
    { ...base, accountId: inventoryAccount(ctx), amount: difference, ...text },
    { ...base, accountId: costOfSalesAccount(ctx), amount: -difference, ...text },
  ];
}

/**
 * Ledger lines of opening stock (against opening balance equity) and stock
 * adjustments (against inventory adjustments). Transfers between warehouses
 * stay in the same inventory account and post nothing.
 */
export function postStockEntry(
  entry: StockEntry,
  movements: StockMovementPosting[],
  ctx: LedgerContext,
): LedgerLine[] {
  if (entry.status !== 'posted' || entry.kind === 'transfer') return [];
  const p = ctx.precision;
  const moved = movements.reduce((acc, m) => acc + toMinor(m.value, p), 0);
  const base = {
    date: entry.date,
    source: 'stock' as const,
    sourceId: entry.id,
    number: entry.number,
    contactId: null,
  };
  const inventory = inventoryAccount(ctx);
  let lines: LedgerLine[];
  if (entry.kind === 'opening') {
    // Opening stock is valued as entered; stock that had already gone below
    // zero takes its cost from it, and the difference is cost of sales.
    const nominal = movements.reduce((acc, m) => acc + toMinor(m.sourceValue ?? m.value, p), 0);
    const text = described(msg('Opening stock {number}'), { number: entry.number });
    lines = [
      { ...base, accountId: inventory, amount: moved, ...text },
      { ...base, accountId: role(ctx, 'opening_balance'), amount: -nominal, ...text },
      { ...base, accountId: costOfSalesAccount(ctx), amount: nominal - moved, ...text },
    ];
  } else {
    const adjustments = usable(ctx, ctx.stock?.adjustmentAccountId);
    if (!adjustments) {
      throw new LedgerError('No inventory adjustments account is set up.', {
        text: msg('No inventory adjustments account is set up.'),
      });
    }
    const text = described(msg('Stock adjustment {number}'), { number: entry.number });
    lines = [
      { ...base, accountId: inventory, amount: moved, ...text },
      { ...base, accountId: adjustments, amount: -moved, ...text },
    ];
  }
  const kept = lines.filter((l) => l.amount !== 0);
  if (!balanced(kept)) {
    throw new UnbalancedEntryError(`Stock entry ${entry.number} does not balance`);
  }
  return kept;
}

/**
 * Ledger lines of items issued to an employee: their cost leaves inventory
 * and is booked as an expense (items issued to employees). Void issues post
 * nothing.
 */
export function postStockIssue(
  issue: StockIssue,
  movements: StockMovementPosting[],
  ctx: LedgerContext,
): LedgerLine[] {
  if (issue.status !== 'posted') return [];
  const moved = movements.reduce((acc, m) => acc + toMinor(m.value, ctx.precision), 0);
  if (moved === 0) return [];
  const expense = usable(ctx, ctx.stock?.issuedItemsAccountId);
  if (!expense) {
    throw new LedgerError('No account is set up for items issued to employees.', {
      text: msg('No account is set up for items issued to employees.'),
    });
  }
  const base = {
    date: issue.date,
    source: 'issue' as const,
    sourceId: issue.id,
    number: issue.number,
    contactId: null,
  };
  const text = described(msg('Items issued {number} to {name}'), {
    number: issue.number,
    name: issue.recipient.name,
  });
  const lines = [
    { ...base, accountId: inventoryAccount(ctx), amount: moved, ...text },
    { ...base, accountId: expense, amount: -moved, ...text },
  ];
  if (!balanced(lines)) {
    throw new UnbalancedEntryError(`Stock issue ${issue.number} does not balance`);
  }
  return lines;
}

/**
 * Date a returned or cancelled cheque is reversed in the books, or null for
 * any other payment. The payment keeps its entries on its own date and the
 * reversal goes on the day the cheque came back (or was cancelled), so
 * closed periods never change. Cheques voided before reversals were dated
 * have no void date and leave the books altogether.
 */
export function chequeReversalDate(
  payment: Pick<Payment, 'voided' | 'voidedOn' | 'cheque'>,
): ISODate | null {
  const status = payment.cheque?.status;
  if (!payment.voided || (status !== 'returned' && status !== 'cancelled')) return null;
  return payment.voidedOn ?? null;
}

/**
 * Ledger lines of a payment received from a client or made to a vendor.
 * Credit-note applications move no money; they only post the exchange
 * difference when the credit and the invoice were booked at different
 * rates. A returned or cancelled cheque stays on its date and is reversed
 * on the day it came back; any other void payment leaves the books.
 *
 * The money side is the account stored on the payment (the clearing account
 * for KNET and cards, post-dated cheques for cheques) or, for payments
 * without one, bank or cash by method. A provider fee is an expense taken
 * out of that same account on the payment date.
 */
export function postPayment(payment: Payment, ctx: LedgerContext): LedgerLine[] {
  if (payment.method === 'credit_note') {
    // Applications saved before exchange differences were posted move nothing.
    return postsUnderCurrentRules(payment) ? postCreditApplication(payment, ctx) : [];
  }
  const reversedOn = chequeReversalDate(payment);
  if (payment.voided && !reversedOn) return [];
  const out = payment.direction === 'out';
  const p = ctx.precision;
  const rate = rateOf(payment, ctx);
  const received = toMinor(dec(payment.amount).times(rate), p);
  if (received === 0) return [];

  // Receivable (or payable) is cleared at each document's own rate; any
  // difference is an exchange gain or loss.
  let cleared = 0;
  let allocated = new Decimal(0);
  for (const a of payment.allocations) {
    const doc = ctx.documents.get(a.documentId);
    cleared +=
      ctx.clearing?.get(clearingKey(payment.id, a.documentId)) ??
      toMinor(dec(a.amount).times(doc ? rateOf(doc, ctx) : rate), p);
    allocated = allocated.plus(dec(a.amount));
  }
  const unapplied = dec(payment.amount).minus(allocated);
  if (unapplied.gt(0)) cleared += toMinor(unapplied.times(rate), p);

  const cashLike = payment.method === 'cash' || payment.method === 'cod';
  const bank = usable(ctx, payment.accountId) ?? role(ctx, cashLike ? 'cash' : 'bank', 'bank');
  const base = {
    date: payment.date,
    source: 'payment' as const,
    sourceId: payment.id,
    number: payment.number,
    contactId: payment.clientId || null,
  };
  const named = described(msg('Payment {number}'), { number: payment.number });
  // Money in: debit bank, credit receivable. Money out: debit payable, credit bank.
  const flow = out ? -1 : 1;
  const lines: LedgerLine[] = [
    { ...base, accountId: bank, amount: flow * received, ...named },
    {
      ...base,
      accountId: role(ctx, out ? 'payable' : 'receivable'),
      amount: -flow * cleared,
      ...named,
    },
  ];
  const fx = received - cleared;
  if (fx !== 0) {
    lines.push({
      ...base,
      accountId: role(ctx, 'fx'),
      amount: -flow * fx,
      ...described(msg('Exchange difference {number}'), { number: payment.number }),
    });
  }
  const fee = !out && payment.fee ? toMinor(dec(payment.fee).times(rate), p) : 0;
  if (fee > 0) {
    const text = described(msg('Fee {number}'), { number: payment.number });
    lines.push(
      {
        ...base,
        accountId: usable(ctx, payment.feeAccountId) ?? role(ctx, 'bank_fees', 'expense'),
        amount: fee,
        ...text,
      },
      { ...base, accountId: bank, amount: -fee, ...text },
    );
  }
  const kept = lines.filter((l) => l.amount !== 0);
  if (!balanced(kept)) throw new UnbalancedEntryError(`Payment ${payment.number} does not balance`);
  if (!reversedOn) return kept;
  const reversal = described(
    payment.cheque?.status === 'cancelled'
      ? msg('Cheque {cheque} cancelled ({number})')
      : msg('Cheque {cheque} returned ({number})'),
    { cheque: payment.cheque?.number ?? '', number: payment.number },
  );
  return [
    ...kept,
    ...kept.map((l) => ({ ...l, date: reversedOn, amount: -l.amount, ...reversal })),
  ];
}

/**
 * Posting rules of payments saved with this version: a credit applied at
 * another rate than its invoice posts the exchange difference, and
 * documents in other currencies are cleared cumulatively (see
 * `documentClearing`). Payments saved earlier have no rules number and keep
 * posting as they did, so closed periods never change by themselves.
 */
export const PAYMENT_POSTING_RULES = 2;

/** Whether a payment was saved under the current posting rules. */
export function postsUnderCurrentRules(payment: Pick<Payment, 'postingRules'>): boolean {
  return (payment.postingRules ?? 1) >= PAYMENT_POSTING_RULES;
}

/** Key of what a payment (or credit application) clears from one document. */
function clearingKey(paymentId: ID, documentId: ID, side: 'document' | 'credit' = 'document') {
  return side === 'credit' ? `${paymentId}|${documentId}|credit` : `${paymentId}|${documentId}`;
}

/**
 * A credit note (vendor credit) applied to an invoice (bill) moves no money.
 * When the two were booked at different rates, the credit clears its own
 * share of the receivable (payable) at its rate and the invoice's at the
 * invoice's rate: the difference is an exchange gain or loss, so nothing is
 * left on the receivable once both are settled.
 */
function postCreditApplication(payment: Payment, ctx: LedgerContext): LedgerLine[] {
  const credit = payment.creditId ? ctx.documents.get(payment.creditId) : undefined;
  if (!credit || payment.voided) return [];
  const out = payment.direction === 'out';
  const p = ctx.precision;
  let difference = 0;
  for (const a of payment.allocations) {
    const doc = ctx.documents.get(a.documentId);
    if (!doc) continue;
    const creditSide =
      ctx.clearing?.get(clearingKey(payment.id, a.documentId, 'credit')) ??
      toMinor(dec(a.amount).times(rateOf(credit, ctx)), p);
    const documentSide =
      ctx.clearing?.get(clearingKey(payment.id, a.documentId)) ??
      toMinor(dec(a.amount).times(rateOf(doc, ctx)), p);
    // Sales: the credit note's credit is cleared (a debit), the invoice's debit
    // (a credit). Purchases the other way round.
    difference += out ? documentSide - creditSide : creditSide - documentSide;
  }
  if (difference === 0) return [];
  const base = {
    date: payment.date,
    source: 'payment' as const,
    sourceId: payment.id,
    number: payment.number,
    contactId: payment.clientId || null,
  };
  const text = described(msg('Exchange difference {number}'), { number: payment.number });
  return [
    { ...base, accountId: role(ctx, out ? 'payable' : 'receivable'), amount: difference, ...text },
    { ...base, accountId: role(ctx, 'fx'), amount: -difference, ...text },
  ];
}

/**
 * Company-currency value (minor units) each payment and credit application
 * clears from a document in another currency. Like retention releases, the
 * parts are converted cumulatively in date order, so a document settled in
 * instalments at its own rate is cleared to the last fils. A returned or
 * cancelled cheque gives back exactly what it cleared; on its day it comes
 * before what is received (a replacement cheque), unless what it reverses
 * was received that same day: then it comes straight after it. Either way
 * a document settled again is cleared to the last fils. Payments saved
 * before these rules (`postsUnderCurrentRules`) keep converting each part
 * on its own, as they always did. Keys: see `clearingKey` ("…|credit" is
 * what an application clears from its credit note). Documents in the
 * company currency convert exactly and need none.
 */
export function documentClearing(
  payments: Payment[],
  ctx: Pick<LedgerContext, 'companyCurrency' | 'precision' | 'documents'>,
): Map<string, number> {
  interface Part {
    date: ISODate;
    /**
     * Order on the same day: reversals of earlier days' receipts (0), then
     * receipts in the order they were recorded, each followed by its
     * reversal if it came back that same day (1).
     */
    rank: 0 | 1;
    order: string;
    key: string;
    amount: Decimal;
    /** What a payment saved before these rules cleared, converted alone. */
    own?: number;
    /** The part a reversal gives back. */
    reverses?: string;
  }
  const byDocument = new Map<ID, Part[]>();
  const foreign = (documentId: ID) => {
    const doc = ctx.documents.get(documentId);
    return doc && doc.currency !== ctx.companyCurrency ? doc : undefined;
  };
  const add = (documentId: ID, part: Part) => {
    const list = byDocument.get(documentId);
    if (list) list.push(part);
    else byDocument.set(documentId, [part]);
  };
  const alone = (amount: number, doc: InvoiceDocument) =>
    toMinor(dec(amount).times(rateOf(doc, ctx)), ctx.precision);
  for (const payment of payments) {
    const reversedOn = chequeReversalDate(payment);
    if (payment.voided && !reversedOn) continue;
    const current = postsUnderCurrentRules(payment);
    const order = `${payment.createdAt}|${payment.id}`;
    const credit =
      payment.method === 'credit_note' && payment.creditId ? foreign(payment.creditId) : undefined;
    for (const a of payment.allocations) {
      const key = clearingKey(payment.id, a.documentId);
      const doc = foreign(a.documentId);
      if (doc) {
        add(doc.id, {
          date: payment.date,
          rank: 1,
          order,
          key,
          amount: dec(a.amount),
          ...(current ? {} : { own: alone(a.amount, doc) }),
        });
        if (reversedOn) {
          add(doc.id, {
            date: reversedOn,
            rank: reversedOn === payment.date ? 1 : 0,
            order,
            key: `${key}|reversal`,
            amount: dec(a.amount).negated(),
            reverses: key,
          });
        }
      }
      if (credit) {
        add(credit.id, {
          date: payment.date,
          rank: 1,
          order,
          key: clearingKey(payment.id, a.documentId, 'credit'),
          amount: dec(a.amount),
          ...(current ? {} : { own: alone(a.amount, credit) }),
        });
      }
    }
  }
  const out = new Map<string, number>();
  for (const [documentId, parts] of byDocument) {
    const rate = rateOf(ctx.documents.get(documentId)!, ctx);
    parts.sort(
      (a, b) =>
        a.date.localeCompare(b.date) ||
        a.rank - b.rank ||
        a.order.localeCompare(b.order) ||
        Number(a.reverses !== undefined) - Number(b.reverses !== undefined) ||
        a.key.localeCompare(b.key),
    );
    let total = new Decimal(0);
    let cleared = 0;
    for (const part of parts) {
      total = total.plus(part.amount);
      const minor =
        part.reverses !== undefined
          ? -(out.get(part.reverses) ?? 0)
          : (part.own ?? toMinor(total.times(rate), ctx.precision) - cleared);
      cleared += minor;
      out.set(part.key, minor);
    }
  }
  return out;
}

/** Ledger lines of an expense: the category and input tax, paid from a money account. */
export function postExpense(expense: Expense, ctx: LedgerContext): LedgerLine[] {
  const p = ctx.precision;
  const rate = rateOf(expense, ctx);
  const total = toMinor(dec(expense.amount).times(rate), p);
  if (total === 0) return [];
  // The amount includes the charged tax: tax = total − total / (1 + Σ rates).
  // Reverse charge comes on top, worked out on what was paid without tax.
  const valid = expense.taxes.filter((t) => t.name.trim() && Number.isFinite(t.rate));
  const charged = valid.filter((t) => !isReverseCharge(t));
  const reverse = valid.filter((t) => isReverseCharge(t));
  const rateSum = charged.reduce((acc, t) => acc.plus(dec(t.rate)), new Decimal(0));
  const net = rateSum.isZero() ? dec(total) : dec(total).dividedBy(rateSum.dividedBy(100).plus(1));
  const taxTotal = total - toMinor(net, 0);
  const perTax = allocate(
    taxTotal,
    charged.map((t) => dec(t.rate)),
  );
  const first = charged[0] ?? reverse[0];
  const base = {
    date: expense.date,
    source: 'expense' as const,
    sourceId: expense.id,
    number: expense.number,
    contactId: expense.vendorId,
  };
  const named = expense.description
    ? { description: expense.description }
    : described(msg('Expense {number}'), { number: expense.number });
  const lines: LedgerLine[] = [
    {
      ...base,
      accountId: usable(ctx, expense.accountId) ?? role(ctx, 'expense'),
      amount: total - taxTotal,
      ...named,
      vat: {
        flow: 'purchase',
        part: 'base',
        kind: first ? taxKind(first) : 'none',
        rate: first?.rate ?? 0,
      },
    },
    ...charged.map((t, i) => ({
      ...base,
      accountId: role(ctx, 'input_tax'),
      amount: perTax[i],
      description: `${t.name} ${t.rate}%`,
      vat: { flow: 'purchase' as const, part: 'tax' as const, kind: taxKind(t), rate: t.rate },
    })),
    {
      ...base,
      accountId: usable(ctx, expense.paidFromAccountId) ?? role(ctx, 'bank'),
      amount: -total,
      ...named,
    },
  ];
  for (const t of reverse) {
    const minor = toMinor(
      dec(total - taxTotal)
        .times(dec(t.rate))
        .dividedBy(100),
      0,
    );
    const vat: VatTag = { flow: 'purchase', part: 'tax', kind: 'reverse_charge', rate: t.rate };
    const text = reverseCharge(t);
    lines.push(
      { ...base, accountId: role(ctx, 'input_tax'), amount: minor, ...text, vat },
      { ...base, accountId: role(ctx, 'output_tax'), amount: -minor, ...text, vat },
    );
  }
  return lines.filter((l) => l.amount !== 0);
}

/** Ledger lines of a posted manual journal. */
export function postJournal(journal: ManualJournal, ctx: LedgerContext): LedgerLine[] {
  if (journal.status !== 'posted') return [];
  const lines = journal.lines
    .map((l) => ({
      date: journal.date,
      accountId: l.accountId,
      amount: toMinor(l.debit, ctx.precision) - toMinor(l.credit, ctx.precision),
      source: 'journal' as const,
      sourceId: journal.id,
      number: journal.number,
      contactId: l.contactId,
      ...(l.description || journal.reference
        ? { description: l.description || journal.reference }
        : described(msg('Journal {number}'), { number: journal.number })),
      ...(journal.vatReturnId ? { settlement: true } : {}),
    }))
    .filter((l) => l.amount !== 0);
  if (!balanced(lines))
    throw new UnbalancedEntryError(`Journal ${journal.number} does not balance`);
  return lines;
}

/**
 * Builds the ledger for a company. Documents that can't be posted (for
 * example a missing account) are reported as problems instead of failing.
 */
export function buildLedger(
  data: {
    documents: InvoiceDocument[];
    payments: Payment[];
    journals: ManualJournal[];
    expenses?: Expense[];
    /** Stock movements, entries and issues; their postings need `ctx.stock`. */
    stock?: { movements: StockMovementPosting[]; entries: StockEntry[]; issues?: StockIssue[] };
  },
  ctx: LedgerContext,
): { lines: LedgerLine[]; problems: LedgerProblem[] } {
  const lines: LedgerLine[] = [];
  const problems: LedgerProblem[] = [];
  const attempt = (source: LedgerSource, id: ID, number: string, post: () => LedgerLine[]) => {
    try {
      lines.push(...post());
    } catch (error) {
      problems.push({
        source,
        sourceId: id,
        number,
        message: error instanceof Error ? error.message : String(error),
        ...(error instanceof LedgerError ? { label: error.label } : {}),
      });
    }
  };
  for (const doc of data.documents) {
    if (!isPosted(doc) || !isPostedType(doc.type)) continue;
    if (needsRate(doc, ctx)) {
      problems.push({
        source: doc.type,
        sourceId: doc.id,
        number: doc.number,
        ...rateProblem(doc.currency),
      });
    }
    attempt(doc.type, doc.id, doc.number, () => postDocument(doc, ctx));
  }
  if (data.stock && ctx.stock) {
    const byDocument = new Map<ID, StockMovementPosting[]>();
    const byEntry = new Map<ID, StockMovementPosting[]>();
    const byIssue = new Map<ID, StockMovementPosting[]>();
    const add = (map: Map<ID, StockMovementPosting[]>, key: ID, m: StockMovementPosting) => {
      const list = map.get(key);
      if (list) list.push(m);
      else map.set(key, [m]);
    };
    for (const m of data.stock.movements) {
      if (m.sourceType === 'opening' || m.sourceType === 'adjustment') add(byEntry, m.sourceId, m);
      else if (m.sourceType === 'issue') add(byIssue, m.sourceId, m);
      else if (m.documentId) add(byDocument, m.documentId, m);
    }
    for (const doc of data.documents) {
      if (!isPosted(doc) || !isPostedType(doc.type)) continue;
      const moved = byDocument.get(doc.id);
      if (!moved && !touchesStock(doc, ctx)) continue;
      attempt(doc.type, doc.id, doc.number, () => postDocumentStock(doc, moved ?? [], ctx));
    }
    for (const entry of data.stock.entries) {
      attempt('stock', entry.id, entry.number, () =>
        postStockEntry(entry, byEntry.get(entry.id) ?? [], ctx),
      );
    }
    for (const issue of data.stock.issues ?? []) {
      attempt('issue', issue.id, issue.number, () =>
        postStockIssue(issue, byIssue.get(issue.id) ?? [], ctx),
      );
    }
  }
  // Documents in other currencies are cleared cumulatively, to the last fils.
  const payCtx: LedgerContext = ctx.clearing
    ? ctx
    : { ...ctx, clearing: documentClearing(data.payments, ctx) };
  for (const payment of data.payments) {
    const posted = !payment.voided || chequeReversalDate(payment) !== null;
    if (payment.method !== 'credit_note' && posted && needsRate(payment, ctx)) {
      problems.push({
        source: 'payment',
        sourceId: payment.id,
        number: payment.number,
        ...rateProblem(payment.currency),
      });
    }
    attempt('payment', payment.id, payment.number, () => postPayment(payment, payCtx));
  }
  for (const expense of data.expenses ?? []) {
    if (needsRate(expense, ctx)) {
      problems.push({
        source: 'expense',
        sourceId: expense.id,
        number: expense.number,
        ...rateProblem(expense.currency),
      });
    }
    attempt('expense', expense.id, expense.number, () => postExpense(expense, ctx));
  }
  for (const journal of data.journals) {
    attempt('journal', journal.id, journal.number, () => postJournal(journal, ctx));
  }
  lines.sort((a, b) => a.date.localeCompare(b.date) || a.number.localeCompare(b.number));
  return { lines, problems };
}
