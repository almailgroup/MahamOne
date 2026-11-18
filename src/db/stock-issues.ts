import { db } from './db';
import { logActivity } from './activity';
import { assertUnlocked } from './accounting';
import { activityAuthor } from './author';
import { nowStamp } from './defaults';
import {
  ensureIssueAccounts,
  isSubWarehouse,
  nextStockNumber,
  stockTables,
  syncIssueStock,
} from './inventory';
import type {
  ApprovalRequest,
  Company,
  ID,
  ISODate,
  IssueRecipient,
  StockIssue,
  Warehouse,
} from './types';
import { isStockItem } from '@/lib/inventory/sources';
import { dec } from '@/lib/money';
import { newId, shortId } from '@/lib/ids';
import { linkHasFeature } from '@/cloud/features';
import { isApprover, issuesFromWarehouse, managesWarehouses as managerRole } from '@/cloud/roles';
import type { CloudLink } from '@/cloud/types';
import { msg, t } from '@/i18n';

/**
 * Items issued to employees: uniforms, trousers, shoes, badges handed from a
 * (sub-)warehouse to a security guard. Whoever looks after a sub-warehouse
 * issues from it; the issue waits for an approver (an approval request of
 * kind `stock_issue`, carrying the issue as it would be kept), and only once
 * it is confirmed is it kept as a stock issue: its stock leaves the
 * warehouse and its cost is booked as an expense. An approver who issues
 * items records them at once.
 */

export class StockIssueError extends Error {}

const PREFIX = 'ISS';

/**
 * Whether the person sets up sub-warehouses and changes their stock
 * directly: the owner, an admin or an accountant, and everyone in a company
 * kept on this device.
 */
export function managesWarehouses(link: CloudLink | null | undefined): boolean {
  return !link || managerRole(link.role);
}

/**
 * Whether the person may issue items from a warehouse in use: those who
 * manage warehouses from any, anyone else from the sub-warehouse they look
 * after (as the cloud checks, almailbooks.issues_from).
 */
export function issuesFrom(
  warehouse: Pick<Warehouse, 'parentId' | 'keeper' | 'archived'> | null | undefined,
  link: CloudLink | null | undefined,
): boolean {
  if (!warehouse || warehouse.archived) return false;
  if (!link) return true;
  return (
    link.role !== 'viewer' &&
    (managerRole(link.role) ||
      (isSubWarehouse(warehouse) && issuesFromWarehouse(link.role, link.userId, warehouse)))
  );
}

/** Whether a company offers issuing to employees: in the cloud once its server has it. */
export function issuesOffered(link: CloudLink | null | undefined): boolean {
  return linkHasFeature(link ?? null, 'stock_issues');
}

/** Whether a request asks for items to be issued. */
export function isStockIssueRequest(
  request: Pick<ApprovalRequest, 'kind' | 'subjectTbl'> | null | undefined,
): boolean {
  return request?.kind === 'stock_issue' && request.subjectTbl === 'stockIssues';
}

/** The issue a request carries, as it was sent, or null when it carries none. */
export function requestedIssue(request: ApprovalRequest): StockIssue | null {
  const after = request.after as Partial<StockIssue> | null | undefined;
  if (!isStockIssueRequest(request) || !after) return null;
  if (typeof after.warehouseId !== 'string' || !after.recipient || !Array.isArray(after.lines)) {
    return null;
  }
  return {
    ...(after as StockIssue),
    id: request.subjectId,
    companyId: request.companyId,
  };
}

/** Key of an item in a warehouse, for the quantities below. */
export const stockKey = (warehouseId: ID, productId: ID) => `${warehouseId}|${productId}`;

/** Requests whose items are not issued yet: waiting, or confirmed and not recorded yet. */
const WAITING = new Set<ApprovalRequest['status']>(['pending', 'approved']);

/**
 * Quantities asked for and not issued yet, by warehouse and item: waiting
 * for an approver, or confirmed and not recorded yet. They can't be issued
 * twice. `except` leaves one request out (the one being decided).
 */
export function waitingQuantities(requests: ApprovalRequest[], except?: ID): Map<string, number> {
  const waiting = new Map<string, number>();
  for (const request of requests) {
    if (!WAITING.has(request.status) || request.id === except) continue;
    const issue = requestedIssue(request);
    if (!issue) continue;
    for (const line of issue.lines) {
      const key = stockKey(issue.warehouseId, line.productId);
      waiting.set(
        key,
        dec(waiting.get(key) ?? 0)
          .plus(line.quantity)
          .toNumber(),
      );
    }
  }
  return waiting;
}

/**
 * Requests of items issued not recorded yet, in a company: waiting for an
 * approver, or confirmed and not carried out yet (on the approver's device
 * before it syncs, or stopped by a locked period).
 */
export async function waitingIssueRequests(companyId: ID): Promise<ApprovalRequest[]> {
  const requests = (
    await db.approvals
      .where('[companyId+status]')
      .anyOf([
        [companyId, 'pending'],
        [companyId, 'approved'],
      ])
      .toArray()
  ).filter(isStockIssueRequest);
  const approved = requests.filter((r) => r.status === 'approved');
  if (approved.length === 0) return requests;
  const kept = await db.stockIssues.bulkGet(approved.map((r) => r.subjectId));
  const recorded = new Set(kept.flatMap((issue) => (issue ? [issue.id] : [])));
  return requests.filter((r) => r.status !== 'approved' || !recorded.has(r.subjectId));
}

/** Stock of each item in a warehouse now, from its movements. */
export async function warehouseStock(companyId: ID, warehouseId: ID): Promise<Map<ID, number>> {
  const movements = await db.stockMovements.where('warehouseId').equals(warehouseId).toArray();
  const stock = new Map<ID, number>();
  for (const m of movements) {
    if (m.companyId !== companyId) continue;
    stock.set(
      m.productId,
      dec(stock.get(m.productId) ?? 0)
        .plus(m.quantity)
        .toNumber(),
    );
  }
  return stock;
}

/** What issuing items asks for. */
export interface IssueInput {
  date: ISODate;
  warehouseId: ID;
  recipient: IssueRecipient;
  lines: { productId: ID; quantity: number }[];
  notes: string;
}

/** Who issues the items, as the issue names them. */
export interface Issuer {
  /** Their account; null in a company kept on this device. */
  userId: string | null;
  name: string;
}

/**
 * The issue as it would be kept, checked: stock items of the company, from a
 * warehouse that is in use, to an employee, in quantities the warehouse
 * still has once the issues waiting for an approver are taken off.
 */
async function buildIssue(
  company: Company,
  input: IssueInput,
  issuer: Issuer,
  waiting: Map<string, number>,
): Promise<StockIssue> {
  assertUnlocked(company, input.date);
  const warehouse = await db.warehouses.get(input.warehouseId);
  if (!warehouse || warehouse.companyId !== company.id || warehouse.archived) {
    throw new StockIssueError(t('Choose the warehouse the items come from.'));
  }
  const recipient = input.recipient;
  if (!recipient?.employeeId || !recipient.name.trim()) {
    throw new StockIssueError(t('Choose the employee who receives the items.'));
  }
  // The same item twice is one line.
  const quantities = new Map<ID, number>();
  for (const line of input.lines) {
    if (!line.productId || !(line.quantity !== 0)) continue;
    if (!(line.quantity > 0)) throw new StockIssueError(t('Quantities must be positive.'));
    quantities.set(
      line.productId,
      dec(quantities.get(line.productId) ?? 0)
        .plus(line.quantity)
        .toNumber(),
    );
  }
  if (quantities.size === 0) throw new StockIssueError(t('Add at least one item with a quantity.'));
  const ids = [...quantities.keys()];
  const products = await db.products.bulkGet(ids);
  if (products.some((p) => !p || p.companyId !== company.id || !isStockItem(p) || p.archived)) {
    throw new StockIssueError(t('Only stock items can be issued.'));
  }
  const stock = await warehouseStock(company.id, warehouse.id);
  for (const [index, id] of ids.entries()) {
    const product = products[index]!;
    const left = dec(stock.get(id) ?? 0)
      .minus(waiting.get(stockKey(warehouse.id, id)) ?? 0)
      .toNumber();
    if (dec(quantities.get(id)!).greaterThan(left)) {
      throw new StockIssueError(
        t('Only {quantity} of {item} left in {warehouse} to issue.', {
          quantity: Math.max(0, left),
          item: product.name,
          warehouse: warehouse.name,
        }),
      );
    }
  }
  const stamp = nowStamp();
  return {
    id: newId(),
    companyId: company.id,
    number: '',
    date: input.date,
    warehouseId: warehouse.id,
    recipient: {
      employeeId: recipient.employeeId,
      number: recipient.number.trim(),
      name: recipient.name.trim(),
      nameAr: recipient.nameAr?.trim() ?? '',
      jobTitle: recipient.jobTitle.trim(),
      jobTitleAr: recipient.jobTitleAr?.trim() ?? '',
    },
    issuedBy: issuer.userId,
    issuedByName: issuer.name.trim().slice(0, 200),
    requestId: null,
    approvedBy: null,
    approvedByName: '',
    approvedAt: null,
    lines: ids.map((id, index) => ({
      id: shortId(),
      productId: id,
      name: products[index]!.name,
      nameAr: products[index]!.nameAr ?? '',
      unit: products[index]!.unit,
      quantity: quantities.get(id)!,
    })),
    notes: input.notes.trim(),
    status: 'posted',
    voidedAt: null,
    createdAt: stamp,
    updatedAt: stamp,
  };
}

/** "1 Trouser, 2 T-shirts", for messages and notifications. */
export function issueSummary(issue: Pick<StockIssue, 'lines'>, arabic = false): string {
  return issue.lines
    .map((l) => `${l.quantity} ${(arabic && l.nameAr) || l.name}`)
    .join(arabic ? '، ' : ', ');
}

const LOG = {
  recorded: msg('Items issued to {name}: {items}'),
  voided: msg('Items issued {number} voided'),
};

/**
 * Keeps a confirmed issue: numbered now, its stock leaves the warehouse and
 * its cost is booked. Runs inside a transaction that includes
 * `stockTables()`.
 */
async function keepIssue(company: Company, issue: StockIssue): Promise<StockIssue> {
  assertUnlocked(company, issue.date);
  await ensureIssueAccounts(company);
  const taken = (await db.stockIssues.where('companyId').equals(company.id).toArray()).map(
    (i) => i.number,
  );
  const kept: StockIssue = {
    ...issue,
    number: nextStockNumber(PREFIX, taken),
    status: 'posted',
    updatedAt: nowStamp(),
  };
  await db.stockIssues.put(kept);
  await syncIssueStock(company, kept);
  await logActivity(company.id, 'stock', kept.id, 'posted', {
    text: LOG.recorded,
    vars: { name: kept.recipient.name, items: issueSummary(kept) },
    arabic: { name: kept.recipient.nameAr || kept.recipient.name, items: issueSummary(kept, true) },
  });
  return kept;
}

/**
 * Issues items to an employee. An approver (everyone in a company kept on
 * this device) records them at once; anyone else who may issue from the
 * warehouse sends them for approval. Returns what was made.
 */
export async function issueStock(
  companyId: ID,
  input: IssueInput,
  issuer: Issuer,
): Promise<{ issue: StockIssue | null; request: ApprovalRequest | null }> {
  const link = (await db.syncState.get(companyId)) ?? null;
  if (!issuesOffered(link)) {
    throw new StockIssueError(
      t('Issuing items needs the latest database update. Ask the owner to run it.'),
    );
  }
  const approver = !link || isApprover(link.role, link.approver);
  return db.transaction('rw', [...stockTables(), db.approvals], async () => {
    const company = await db.companies.get(companyId);
    if (!company) throw new StockIssueError(t('Company not found'));
    const warehouse = await db.warehouses.get(input.warehouseId);
    if (!issuesFrom(warehouse, link)) {
      throw new StockIssueError(
        t('You can only issue items from the sub-warehouse you look after.'),
      );
    }
    const waiting = waitingQuantities(await waitingIssueRequests(companyId));
    const issue = await buildIssue(company, input, issuer, waiting);
    if (approver) {
      const kept = await keepIssue(company, {
        ...issue,
        approvedBy: issuer.userId,
        approvedByName: issue.issuedByName,
        approvedAt: issue.createdAt,
      });
      return { issue: kept, request: null };
    }
    const request: ApprovalRequest = {
      id: newId(),
      companyId,
      kind: 'stock_issue',
      subjectTbl: 'stockIssues',
      subjectId: issue.id,
      // Numbered once confirmed.
      subjectNumber: '',
      before: null,
      after: issue as unknown as Record<string, unknown>,
      reason: issue.notes,
      status: 'pending',
      // The cloud stamps both with its own.
      requestedBy: link?.userId ?? '',
      ...(issue.issuedByName ? { requestedByName: issue.issuedByName } : {}),
      requestedAt: issue.createdAt,
      decidedBy: null,
      decidedAt: null,
      decisionNote: '',
      createdAt: issue.createdAt,
      updatedAt: issue.createdAt,
    };
    await db.approvals.add(request);
    await logActivity(companyId, 'stock', issue.id, 'approval:asked', {
      text: msg('Items to issue to {name} sent for approval: {items}'),
      vars: { name: issue.recipient.name, items: issueSummary(issue) },
      arabic: {
        name: issue.recipient.nameAr || issue.recipient.name,
        items: issueSummary(issue, true),
      },
    });
    return { issue: null, request };
  });
}

/**
 * Carries out a confirmed request on this (the approver's) device: the
 * issue is kept as it was sent, under the request's id for it, so two
 * approver devices make the one issue. A period locked meanwhile stops it
 * with a message: the request stays approved, to be carried out again or
 * rejected. Returns the issue's id.
 */
export async function applyStockIssueRequest(request: ApprovalRequest): Promise<ID> {
  await db.transaction('rw', [...stockTables(), db.approvals], async () => {
    const issue = await checkedRequest(request);
    // Kept already (carried out on another device of an approver).
    if (!issue) return;
    const company = await db.companies.get(request.companyId);
    if (!company) throw new StockIssueError(t('Company not found'));
    const approver = activityAuthor(company.id);
    await keepIssue(company, {
      ...issue,
      issuedBy: request.requestedBy || issue.issuedBy,
      issuedByName: request.requestedByName || issue.issuedByName,
      requestId: request.id,
      approvedBy: request.decidedBy ?? approver?.id ?? null,
      approvedByName: approver?.name ?? '',
      approvedAt: request.decidedAt ?? nowStamp(),
    });
  });
  return request.subjectId;
}

/**
 * The issue a request asks for, checked before it is kept: stock items of
 * the company in positive quantities, from one of its warehouses, each line
 * named as the item is (not as the request says). Null when it is kept
 * already, by this request; an error when it can't be kept.
 */
async function checkedRequest(request: ApprovalRequest): Promise<StockIssue | null> {
  const proposal = requestedIssue(request);
  if (!proposal) {
    throw new StockIssueError(t('This version of the app can’t carry out this request.'));
  }
  const kept = await db.stockIssues.get(request.subjectId);
  if (kept) {
    if (kept.requestId === request.id) return null;
    throw new StockIssueError(
      t('These items are already on record under another request. Reject this one.'),
    );
  }
  const warehouse = await db.warehouses.get(proposal.warehouseId);
  if (!warehouse || warehouse.companyId !== request.companyId) {
    throw new StockIssueError(t('Choose the warehouse the items come from.'));
  }
  if (!proposal.recipient?.employeeId || !String(proposal.recipient.name ?? '').trim()) {
    throw new StockIssueError(t('Choose the employee who receives the items.'));
  }
  if (proposal.lines.length === 0) {
    throw new StockIssueError(t('Add at least one item with a quantity.'));
  }
  const products = await db.products.bulkGet(proposal.lines.map((l) => l.productId));
  const lines = proposal.lines.map((line, index) => {
    const product = products[index];
    if (!product || product.companyId !== request.companyId || !isStockItem(product)) {
      throw new StockIssueError(t('Only stock items can be issued.'));
    }
    const quantity: unknown = line.quantity;
    if (typeof quantity !== 'number' || !Number.isFinite(quantity) || !(quantity > 0)) {
      throw new StockIssueError(t('Quantities must be positive.'));
    }
    return {
      id: typeof line.id === 'string' && line.id ? line.id : `line-${index + 1}`,
      productId: product.id,
      name: product.name,
      nameAr: product.nameAr ?? '',
      unit: product.unit,
      quantity,
    };
  });
  return { ...proposal, lines };
}

/**
 * Why an approver can't confirm a request to issue items (see
 * checkedRequest), or null when they can.
 */
export async function issueRequestProblem(request: ApprovalRequest): Promise<string | null> {
  try {
    await checkedRequest(request);
    return null;
  } catch (error) {
    if (error instanceof StockIssueError) return error.message;
    throw error;
  }
}

/**
 * Before an approver confirms a request: the warehouse still holds what it
 * asks for. Returns the shortfall as a message, or null when there is none
 * (the approver may still confirm; the stock then goes below zero).
 */
export async function issueShortfall(request: ApprovalRequest): Promise<string | null> {
  const issue = requestedIssue(request);
  if (!issue) return null;
  const [stock, warehouse, waiting] = await Promise.all([
    warehouseStock(request.companyId, issue.warehouseId),
    db.warehouses.get(issue.warehouseId),
    waitingIssueRequests(request.companyId).then((r) => waitingQuantities(r, request.id)),
  ]);
  for (const line of issue.lines) {
    const left = dec(stock.get(line.productId) ?? 0)
      .minus(waiting.get(stockKey(issue.warehouseId, line.productId)) ?? 0)
      .toNumber();
    if (dec(line.quantity).greaterThan(left)) {
      return t('{warehouse} has only {quantity} of {item} left.', {
        warehouse: warehouse?.name ?? '',
        quantity: Math.max(0, left),
        item: line.name,
      });
    }
  }
  return null;
}

/**
 * Voids a kept issue (approvers only): it stays on record and its stock
 * comes back to the warehouse.
 */
export async function voidStockIssue(id: ID): Promise<void> {
  const issue = await db.stockIssues.get(id);
  if (!issue || issue.status === 'void') return;
  const link = (await db.syncState.get(issue.companyId)) ?? null;
  if (link && !isApprover(link.role, link.approver)) {
    throw new StockIssueError(t('Only an approver voids items issued.'));
  }
  await db.transaction('rw', stockTables(), async () => {
    const current = await db.stockIssues.get(id);
    if (!current || current.status === 'void') return;
    const company = await db.companies.get(current.companyId);
    if (!company) return;
    assertUnlocked(company, current.date);
    const stamp = nowStamp();
    const voided: StockIssue = { ...current, status: 'void', voidedAt: stamp, updatedAt: stamp };
    await db.stockIssues.put(voided);
    await syncIssueStock(company, voided);
    await logActivity(company.id, 'stock', id, 'void', {
      text: LOG.voided,
      vars: { number: current.number },
    });
  });
}
