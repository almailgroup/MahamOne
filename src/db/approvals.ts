import Dexie from 'dexie';
import { db } from './db';
import { nowStamp } from './defaults';
import { logActivity } from './activity';
import type {
  ApprovalKind,
  ApprovalRequest,
  ApprovalRules,
  Company,
  ID,
  InvoiceDocument,
} from './types';
import { msg, t } from '@/i18n';
import { newId } from '@/lib/ids';
import { addDaysISO, today } from '@/lib/dates';
import {
  appLimit,
  approvalRulesOf,
  documentChangeNeedsApproval,
  INVOICE_CONTENT_FIELDS,
  invoiceContent,
  isApprover,
  isLetterApproval,
  isPayrollApproval,
  isPrivateRecord,
  deleteKeptBy,
  rulesCoverDocument,
  rulesCoverPayroll,
  sameData,
} from '@/cloud/roles';
import { linkHasFeature } from '@/cloud/features';
import type { CloudLink } from '@/cloud/types';

/**
 * The approvals service (D6 of docs/requirements-plan.md): a change only an
 * approver may make is saved as a request (table `approvals`) instead, and
 * carried out on the approver's device when they approve it. Approvers are
 * the company's owner (its Super Admin) and the admins or accountants the
 * owner allowed to approve (Settings → Team). The rules are the owner's
 * (Company.approvalRules, Settings → Approvals) and apply to companies kept
 * in the cloud only: a company kept on this device has nobody to ask.
 *
 * The cloud keeps the requests honest (records_guard in
 * 20261116000000_super_admin_approvals.sql): it stamps who asked and when,
 * lets only an approver decide, and keeps a decision made.
 */

/** A change that waits for an approver: send it with requestApproval instead. */
export class ApprovalRequiredError extends Error {
  constructor(
    /** What to ask for; null for a change that can't be asked for (back to draft). */
    readonly kind: ApprovalKind | null,
    readonly subject: InvoiceDocument,
    /** The document as it would have been saved. */
    readonly proposal: InvoiceDocument,
  ) {
    super(
      kind
        ? t('{number} is issued, so this change needs approval. Send it for approval instead.', {
            number: subject.number,
          })
        : t('{number} is issued, so only an approver can make this change.', {
            number: subject.number,
          }),
    );
    this.name = 'ApprovalRequiredError';
  }
}

export class ApprovalError extends Error {}

/** The rules in effect for a company: none for one kept on this device only (`link` null). */
export function rulesInEffect(
  company: Pick<Company, 'approvalRules'> | null | undefined,
  link: CloudLink | null | undefined,
): ApprovalRules | null {
  if (!link) return null;
  return approvalRulesOf(company) as ApprovalRules | null;
}

/**
 * Whether pay runs wait for the Super Admin's approval (#10) in this
 * company: one kept in the cloud, whose server has salary approval, with
 * the owner's switch on (Settings → Approvals → Pay runs).
 */
export function payrollApprovalOn(
  company: Pick<Company, 'approvalRules'> | null | undefined,
  link: CloudLink | null | undefined,
): boolean {
  return (
    Boolean(link) &&
    linkHasFeature(link ?? null, 'payroll_approvals') &&
    rulesCoverPayroll(rulesInEffect(company, link))
  );
}

/** The rules of Books (invoices, credit notes and cheques). */
const BOOKS_RULES = ['documentTypes', 'voidInsteadOfDelete', 'cheques'] as const;

/**
 * Whether the owner has turned approvals of Books on (Settings → Approvals):
 * the Approvals page is then in the Books sidebar, and invoices are corrected
 * by a new number (correctsByNewNumber). Kept once set, even when the rules
 * cover nothing any more, so earlier requests stay in reach. Rules the owner
 * set for pay runs only (#10) leave Books as it was.
 */
export function approvalsOn(company: Pick<Company, 'approvalRules'> | null | undefined): boolean {
  const rules = approvalRulesOf(company);
  if (!rules) return false;
  return BOOKS_RULES.some((key) => key in rules) || !('payroll' in rules);
}

/**
 * Whether the owner has turned salary approval on at some time (Settings →
 * Approvals → Pay runs): Approvals is then in the People sidebar, so earlier
 * requests stay in reach once it is off again.
 */
export function payrollApprovalsShown(
  company: Pick<Company, 'approvalRules'> | null | undefined,
): boolean {
  const rules = approvalRulesOf(company);
  return Boolean(rules && 'payroll' in rules);
}

/**
 * Whether corrections go by a new number (D12): voided with why, who and
 * when, and issued again in its place. Once the owner has turned approvals
 * or numbering on issue on; until then voiding is as it always was.
 */
export function correctsByNewNumber(
  company: Pick<Company, 'approvalRules' | 'defaults'> | null | undefined,
): boolean {
  return approvalsOn(company) || company?.defaults?.numberOnIssue === true;
}

/**
 * Whether the person is shown a request (the Approvals page, the counts of
 * the home page): one about People data (a pay run's, a letter's) is left
 * out for a member the owner gave no access to Maham People (#6, D16), as
 * the cloud leaves them out of its emails and of deciding pay runs.
 */
export function requestShownTo(
  request: Pick<ApprovalRequest, 'subjectTbl'>,
  link: CloudLink | null | undefined,
): boolean {
  if (!link) return true;
  return !(
    isPrivateRecord('approvals', request) &&
    appLimit(link.role, link.permissions, 'people') === 'none'
  );
}

/** Whether the person decides requests: everyone in a company kept on this device. */
export function approverOf(link: CloudLink | null | undefined): boolean {
  return !link || isApprover(link.role, link.approver);
}

/** Whether the person approves in this company (see approverOf). */
export async function isApproverIn(companyId: ID): Promise<boolean> {
  return approverOf(await db.syncState.get(companyId));
}

/** What kind of request a change of an issued document is. */
export function changeKind(before: InvoiceDocument, after: InvoiceDocument): ApprovalKind | null {
  if (after.status === 'void' && before.status !== 'void') return 'invoice_void';
  if (before.status === 'void' && after.status !== 'void' && after.status !== 'draft') {
    return 'invoice_unvoid';
  }
  if (after.status === 'draft') return null;
  return 'invoice_edit';
}

/**
 * Throws ApprovalRequiredError when storing `after` over `before` waits for
 * an approver: the person isn't one and the company's rules cover the
 * document (as the cloud would refuse it). `link` undefined: not known here
 * (called inside a larger transaction); the cloud's refusal then comes from
 * the change capture (src/cloud/outbox.ts).
 */
export function assertApproved(
  company: Pick<Company, 'approvalRules'> | null | undefined,
  link: CloudLink | null | undefined,
  before: InvoiceDocument,
  after: InvoiceDocument,
): void {
  if (link === undefined || approverOf(link)) return;
  const rules = rulesInEffect(company, link);
  if (!documentChangeNeedsApproval(rules, before, after)) return;
  throw new ApprovalRequiredError(changeKind(before, after), before, after);
}

/**
 * Whether the rules keep this person from deleting this document, as the
 * cloud does (can_delete_record): an issued invoice or credit note of a
 * type they cover is voided instead, by everyone with "Void instead of
 * delete" and otherwise by anyone but an approver, who asks for a void.
 */
export function voidsInsteadOfDeleting(
  company: Pick<Company, 'approvalRules'> | null | undefined,
  link: CloudLink | null | undefined,
  doc: Pick<InvoiceDocument, 'type' | 'status'>,
): boolean {
  return deleteKeptBy(rulesInEffect(company, link), 'documents', doc, approverOf(link)) !== null;
}

/** Whether issued documents of this type wait for an approver, for this person. */
export function waitsForApproval(
  company: Pick<Company, 'approvalRules'> | null | undefined,
  link: CloudLink | null | undefined,
  doc: Pick<InvoiceDocument, 'type' | 'status'>,
): boolean {
  if (approverOf(link) || doc.status === 'draft') return false;
  const rules = rulesInEffect(company, link);
  return rulesCoverDocument(rules, doc.type);
}

/* -------------------------------------------------------------------------- */
/* Requests                                                                   */
/* -------------------------------------------------------------------------- */

const LOG: Record<'asked' | 'cancelled' | 'approved' | 'rejected' | 'expired', string> = {
  asked: msg('Approval asked for on {number}'),
  cancelled: msg('Approval request on {number} cancelled'),
  approved: msg('Approval request on {number} approved'),
  rejected: msg('Approval request on {number} rejected'),
  expired: msg('Approval request on {number} expired'),
};

/** The same for cheques (#9): a cheque waits for confirmation, an approver confirms it. */
const CHEQUE_LOG: Record<keyof typeof LOG, string> = {
  asked: msg('Confirmation asked for cheque {number}'),
  cancelled: msg('Confirmation request for cheque {number} cancelled'),
  approved: msg('Cheque {number} confirmed'),
  rejected: msg('Cheque {number} not confirmed'),
  expired: msg('Confirmation request for cheque {number} expired'),
};

/** The same for pay runs (#10): the Super Admin's decision is a موافقة, not the posting. */
const PAYROLL_LOG: Record<keyof typeof LOG, string> = {
  asked: msg('Pay run {period} sent for approval'),
  cancelled: msg('Approval request for pay run {period} cancelled'),
  approved: msg('Approval given for pay run {period}'),
  rejected: msg('Approval refused for pay run {period}'),
  expired: msg('Approval request for pay run {period} expired'),
};

/** The same for letters (#19): an approver agrees to issue a letter (موافقة). */
const LETTER_LOG: Record<keyof typeof LOG, string> = {
  asked: msg('Letter sent for approval'),
  cancelled: msg('Approval request for a letter cancelled'),
  approved: msg('Approval given to issue a letter'),
  rejected: msg('Approval refused to issue a letter'),
  expired: msg('Approval request for a letter expired'),
};

/** The same for items issued to employees: an approver confirms them. */
const ISSUE_LOG: Record<keyof typeof LOG, string> = {
  asked: msg('Items to issue to {name} sent for approval'),
  cancelled: msg('Request to issue items to {name} cancelled'),
  approved: msg('Items issued to {name} confirmed'),
  rejected: msg('Items to issue to {name} not confirmed'),
  expired: msg('Request to issue items to {name} expired'),
};

/** The contact a cheque request is about, as far as this device knows it. */
async function chequeContact(request: ApprovalRequest): Promise<ID | null> {
  const after = (request.after ?? {}) as Record<string, unknown>;
  if (typeof after.clientId === 'string' && after.clientId) return after.clientId;
  const subject =
    request.subjectTbl === 'payments'
      ? await db.payments.get(request.subjectId)
      : await db.securityCheques.get(request.subjectId);
  return subject?.clientId || null;
}

/** Writes what happened to a request to the activity of the record it is about. */
export async function logRequest(request: ApprovalRequest, what: keyof typeof LOG): Promise<void> {
  if (isPayrollApproval(request)) {
    // Payroll activity: private, as the pay run is.
    await logActivity(request.companyId, 'payroll', request.subjectId, `approval:${what}`, {
      text: PAYROLL_LOG[what],
      vars: { period: request.subjectNumber },
    });
    return;
  }
  if (isLetterApproval(request)) {
    // About the employee: private, as the letter is.
    const employeeId = (request.after as { employeeId?: unknown } | null | undefined)?.employeeId;
    const about = typeof employeeId === 'string' && employeeId ? employeeId : null;
    await logActivity(
      request.companyId,
      'employee',
      about ?? request.subjectId,
      `approval:${what}`,
      { text: LETTER_LOG[what] },
      { employeeId: about },
    );
    return;
  }
  if (request.kind === 'stock_issue' && request.subjectTbl === 'stockIssues') {
    // The request itself was logged when it was sent (issueStock).
    if (what === 'asked') return;
    const recipient = (request.after as { recipient?: { name?: unknown; nameAr?: unknown } } | null)
      ?.recipient;
    const name = typeof recipient?.name === 'string' ? recipient.name : '';
    const nameAr =
      typeof recipient?.nameAr === 'string' && recipient.nameAr ? recipient.nameAr : name;
    await logActivity(request.companyId, 'stock', request.subjectId, `approval:${what}`, {
      text: ISSUE_LOG[what],
      vars: { name },
      arabic: { name: nameAr },
    });
    return;
  }
  if (request.subjectTbl === 'payments' || request.subjectTbl === 'securityCheques') {
    await logActivity(
      request.companyId,
      request.subjectTbl === 'payments' ? 'payment' : 'cheque',
      request.subjectId,
      `approval:${what}`,
      { text: CHEQUE_LOG[what], vars: { number: request.subjectNumber } },
      { clientId: await chequeContact(request) },
    );
    return;
  }
  if (request.subjectTbl !== 'documents') return;
  const doc = await db.documents.get(request.subjectId);
  await logActivity(
    request.companyId,
    doc?.type ?? 'invoice',
    request.subjectId,
    `approval:${what}`,
    { text: LOG[what], vars: { number: request.subjectNumber } },
    { clientId: doc?.clientId || null, documentId: request.subjectId },
  );
}

/** What writing a request and its activity reads and writes. */
export const REQUEST_TABLES = () => [
  db.approvals,
  db.documents,
  db.payments,
  db.securityCheques,
  db.activities,
];

/** A request for a new cheque payment: its scans wait with it, kept under the payment's id. */
function asksForNewCheque(request: ApprovalRequest): boolean {
  return request.subjectTbl === 'payments' && request.kind === 'cheque_create';
}

/**
 * A cheque that was never recorded keeps no files: the scans attached to a
 * request for a new cheque go once it is turned down, taken back or expired.
 * In a company kept in the cloud only once the cloud agrees and has no
 * payment for it (carryOutDecided): this device's copy of the request may be
 * older than a confirmation made on another device.
 */
async function dropUnusedFiles(requests: ApprovalRequest[]): Promise<void> {
  const unused = requests.filter(asksForNewCheque);
  if (unused.length === 0) return;
  await db.transaction('rw', [db.payments, db.attachments], async () => {
    for (const request of unused) {
      if (await db.payments.get(request.subjectId)) continue;
      await db.attachments.where('ownerId').equals(request.subjectId).delete();
    }
  });
}

/** The company's requests waiting for a decision, the oldest first. */
export async function pendingRequests(companyId: ID): Promise<ApprovalRequest[]> {
  const waiting = await db.approvals
    .where('[companyId+status]')
    .equals([companyId, 'pending'])
    .toArray();
  return waiting.sort((a, b) => a.requestedAt.localeCompare(b.requestedAt));
}

/** The request waiting on a record, if any. */
export async function pendingRequestFor(subjectId: ID): Promise<ApprovalRequest | undefined> {
  return db.approvals
    .where('subjectId')
    .equals(subjectId)
    .filter((r) => r.status === 'pending')
    .first();
}

/** The parts of a document an edit request carries: what it says, before and as proposed. */
function editParts(before: InvoiceDocument, after: InvoiceDocument) {
  return { before: invoiceContent(before), after: invoiceContent(after) };
}

/**
 * Sends a change of an issued document for approval: an edit (the document
 * as it would have been saved), a void or an un-void. One request waits on
 * a document at a time. Returns the request.
 */
export async function requestApproval(input: {
  kind: ApprovalKind;
  subject: InvoiceDocument;
  /** invoice_edit: the document as it would be saved. */
  proposal?: InvoiceDocument;
  reason: string;
  /** The name the team knows the person by, shown with the request. */
  byName?: string;
}): Promise<ApprovalRequest> {
  const { subject, kind } = input;
  const reason = input.reason.trim();
  if (!reason) throw new ApprovalError(t('Say why, for the approver.'));
  const link = await db.syncState.get(subject.companyId);
  return db.transaction('rw', REQUEST_TABLES(), async () => {
    if (await pendingRequestFor(subject.id)) {
      throw new ApprovalError(
        t('A request on {number} is already waiting for approval.', { number: subject.number }),
      );
    }
    let before: Record<string, unknown>;
    let after: Record<string, unknown>;
    if (kind === 'invoice_edit') {
      if (!input.proposal) throw new ApprovalError(t('Nothing to send for approval.'));
      ({ before, after } = editParts(subject, input.proposal));
      if (sameData(before, after)) throw new ApprovalError(t('Nothing has changed.'));
    } else if (kind === 'invoice_void') {
      before = { status: subject.status };
      after = { status: 'void', voidReason: reason };
    } else if (kind === 'invoice_unvoid') {
      before = { status: 'void' };
      after = { status: 'sent' };
    } else {
      throw new ApprovalError(t('Nothing to send for approval.'));
    }
    const now = nowStamp();
    const request: ApprovalRequest = {
      id: newId(),
      companyId: subject.companyId,
      kind,
      subjectTbl: 'documents',
      subjectId: subject.id,
      subjectNumber: subject.number,
      before,
      after,
      reason,
      status: 'pending',
      // The cloud stamps both with its own.
      requestedBy: link?.userId ?? '',
      ...(input.byName?.trim() ? { requestedByName: input.byName.trim().slice(0, 200) } : {}),
      requestedAt: now,
      decidedBy: null,
      decidedAt: null,
      decisionNote: '',
      createdAt: now,
      updatedAt: now,
    };
    await db.approvals.add(request);
    await logRequest(request, 'asked');
    return request;
  });
}

/** Takes a request back while it waits (whoever asked), or cancels it (an approver). */
export async function cancelApproval(id: ID): Promise<void> {
  const request = await db.approvals.get(id);
  if (!request) return;
  const link = await db.syncState.get(request.companyId);
  await db.transaction('rw', REQUEST_TABLES(), async () => {
    const current = await db.approvals.get(id);
    if (!current || current.status !== 'pending') return;
    const now = nowStamp();
    await db.approvals.put({
      ...current,
      status: 'cancelled',
      decidedBy: link?.userId ?? null,
      decidedAt: now,
      updatedAt: now,
    });
    await logRequest(current, 'cancelled');
  });
  // In the cloud, the sync that sends it tidies up (carryOutDecided).
  if (!link) await dropUnusedFiles([request]);
}

/**
 * An approver's decision. In a company kept on this device an approved
 * change is carried out at once (applyApproval). In one kept in the cloud
 * the cloud has the last word: the request may have been taken back, or
 * decided on another device, before this decision reaches it. The change is
 * then carried out once the cloud has taken the decision, by the sync that
 * sends it (carryOutDecided), on this device. When carrying it out fails
 * (the period is locked meanwhile, the number is taken), the request stays
 * approved and can be carried out again or rejected. Returns whether the
 * change was carried out now.
 */
export async function decideApproval(
  id: ID,
  decision: 'approved' | 'rejected',
  note = '',
): Promise<boolean> {
  const request = await db.approvals.get(id);
  // An approved request that could not be carried out may still be rejected.
  const turnedDown = request?.status === 'approved' && decision === 'rejected';
  if (!request || (request.status !== 'pending' && !turnedDown)) {
    throw new ApprovalError(t('This request has already been decided.'));
  }
  if (!(await isApproverIn(request.companyId))) {
    throw new ApprovalError(t('Only an approver decides approval requests.'));
  }
  const link = await db.syncState.get(request.companyId);
  if (decision === 'approved' && isPayrollApproval(request)) {
    await assertPayrollDecision(request, link);
  }
  if (decision === 'approved' && isLetterApproval(request)) {
    // Imported here: letters.ts uses this module for its requests.
    const { assertLetterRequest } = await import('./letters');
    await assertLetterRequest(request);
  }
  const now = nowStamp();
  await db.transaction('rw', REQUEST_TABLES(), async () => {
    await db.approvals.put({
      ...request,
      status: decision,
      decidedBy: link?.userId ?? null,
      decidedAt: now,
      decisionNote: note.trim(),
      updatedAt: now,
    });
    await logRequest(request, decision);
  });
  // In the cloud, the sync that sends the decision carries it out.
  if (link) return false;
  if (decision === 'approved') {
    await applyApproval(id);
    return true;
  }
  await dropUnusedFiles([request]);
  return false;
}

/**
 * With salary approval on, as the cloud refuses it (records_guard in
 * 20261130000000_people_alerts.sql): a member allowed to approve never
 * approves a pay run they sent themselves (the owner may), and a pay run is
 * approved only as it was sent.
 */
async function assertPayrollDecision(
  request: ApprovalRequest,
  link: CloudLink | null | undefined,
): Promise<void> {
  if (!link || !payrollApprovalOn(await db.companies.get(request.companyId), link)) return;
  if (request.requestedBy === link.userId && link.role !== 'owner') {
    throw new ApprovalError(
      t('Only the owner approves a pay run they sent for approval themselves.'),
    );
  }
  const run = await db.payRuns.get(request.subjectId);
  const asked = (request.after as { runUpdatedAt?: unknown } | null | undefined)?.runUpdatedAt;
  if (!run) {
    throw new ApprovalError(t('This pay run isn’t on this device yet. Let it sync, then decide.'));
  }
  if (run.updatedAt !== asked) {
    throw new ApprovalError(
      t(
        'The pay run on this device isn’t as it was sent for approval. Let the device sync; if it still differs, the pay run changed since: reject this request, and it can be sent again.',
      ),
    );
  }
}

/** Whether this device has a change of the request the cloud hasn't taken yet (or refused). */
export async function decisionUnsent(id: ID): Promise<boolean> {
  return (await db.outbox.where('[table+id]').equals(['approvals', id]).count()) > 0;
}

/**
 * What the sync does with the decisions this device sent, once the cloud has
 * taken them (src/cloud/sync.ts), with the request as the cloud keeps it:
 * one still approved is carried out here; a new cheque turned down, taken
 * back or expired leaves its scans only when the cloud has no payment for it
 * (`inCloud` asks; it answers true when it can't tell). Never throws: a
 * change that can't be carried out stays approved, to be carried out again
 * or rejected.
 */
export async function carryOutDecided(
  companyId: ID,
  ids: Iterable<ID>,
  inCloud: (table: 'payments', id: ID) => Promise<boolean>,
): Promise<void> {
  for (const id of new Set(ids)) {
    try {
      const request = await db.approvals.get(id);
      if (!request || request.companyId !== companyId) continue;
      // Changed again here meanwhile: the sync that sends that decides.
      if (await decisionUnsent(id)) continue;
      if (request.status === 'approved') {
        await applyApproval(id);
      } else if (
        (request.status === 'rejected' || request.status === 'cancelled') &&
        asksForNewCheque(request) &&
        !(await db.payments.get(request.subjectId)) &&
        !(await inCloud('payments', request.subjectId))
      ) {
        await dropUnusedFiles([request]);
      }
    } catch {
      // Stays approved, with Carry it out again on the request.
    }
  }
}

/**
 * The fields of an edit request carried onto the document as it is now: only
 * what the request changed, so changes made since (payments, other fields)
 * stay. Fields the proposal leaves out are removed.
 */
export function mergeProposal(
  current: InvoiceDocument,
  before: Record<string, unknown>,
  after: Record<string, unknown>,
): InvoiceDocument {
  const merged: Record<string, unknown> = { ...current };
  for (const field of INVOICE_CONTENT_FIELDS) {
    if (sameData(before[field], after[field])) continue;
    if (after[field] === undefined) delete merged[field];
    else merged[field] = structuredClone(after[field]);
  }
  return merged as unknown as InvoiceDocument;
}

/** Whether the document changed, in what it says, since the request was made. */
export function changedSinceAsked(request: ApprovalRequest, current: InvoiceDocument): boolean {
  if (request.kind !== 'invoice_edit' || !request.before) return false;
  return !sameData(invoiceContent(current), request.before);
}

/** Carries out an approved request on this (the approver's) device, and marks it applied. */
export async function applyApproval(id: ID): Promise<void> {
  const request = await db.approvals.get(id);
  if (!request || request.status !== 'approved') return;
  // A pay run's approval (#10) is carried out by whoever approves (posts) the
  // pay run, which marks the request done: nothing to do on this device.
  if (isPayrollApproval(request)) return;
  if (isLetterApproval(request)) {
    // Issued on this (the approver's) device, as it was sent (#19).
    const { applyLetterRequest } = await import('./letters');
    await applyLetterRequest(request);
    const done = await db.approvals.get(id);
    if (done?.status === 'approved') {
      await db.approvals.put({ ...done, status: 'applied', updatedAt: nowStamp() });
    }
    return;
  }
  if (request.kind === 'stock_issue' && request.subjectTbl === 'stockIssues') {
    // Kept on this (the approver's) device, as it was sent; stock-issues.ts
    // is imported here as it uses this module's requests.
    const { applyStockIssueRequest } = await import('./stock-issues');
    const resultId = await applyStockIssueRequest(request);
    const done = await db.approvals.get(id);
    if (done?.status === 'approved') {
      await db.approvals.put({ ...done, status: 'applied', resultId, updatedAt: nowStamp() });
    }
    return;
  }
  if (request.subjectTbl === 'payments' || request.subjectTbl === 'securityCheques') {
    // Imported here: the cheque functions use this module for their own checks.
    const { applyChequeRequest } = await import('./cheque-approvals');
    const resultId = await applyChequeRequest(request);
    const done = await db.approvals.get(id);
    if (done?.status === 'approved') {
      await db.approvals.put({
        ...done,
        status: 'applied',
        ...(resultId ? { resultId } : {}),
        updatedAt: nowStamp(),
      });
    }
    return;
  }
  if (request.subjectTbl !== 'documents') {
    throw new ApprovalError(t('This version of the app can’t carry out this request.'));
  }
  const doc = await db.documents.get(request.subjectId);
  if (!doc) throw new ApprovalError(t('The document of this request no longer exists.'));
  // Imported here: documents.ts uses this module for its own checks.
  const { saveDocument, setDocumentStatus } = await import('./documents');
  const after = request.after ?? {};
  if (request.kind === 'invoice_edit') {
    await saveDocument(mergeProposal(doc, request.before ?? {}, after));
  } else if (request.kind === 'invoice_void') {
    if (doc.status !== 'void') {
      await setDocumentStatus(doc.id, 'void', undefined, {
        voidReason: typeof after.voidReason === 'string' ? after.voidReason : request.reason,
      });
    }
  } else if (request.kind === 'invoice_unvoid') {
    if (doc.status === 'void') await setDocumentStatus(doc.id, 'sent');
  } else {
    throw new ApprovalError(t('This version of the app can’t carry out this request.'));
  }
  const fresh = await db.approvals.get(id);
  if (fresh?.status === 'approved') {
    await db.approvals.put({ ...fresh, status: 'applied', updatedAt: nowStamp() });
  }
}

/**
 * Cancels requests that waited longer than the company's rules allow
 * (expireDays). Done on approvers' devices, as the cloud lets only them
 * decide, and only for the requests the person is shown (requestShownTo): a
 * pay run's is left to approvers who see payroll, as the cloud refuses its
 * cancelling by a member the owner gave no access to People (#10, D16), and
 * the others expire all the same. Returns how many were cancelled.
 */
export async function expirePending(companyId: ID, on = today()): Promise<number> {
  if (Dexie.currentTransaction) return 0;
  const [company, link] = await Promise.all([
    db.companies.get(companyId),
    db.syncState.get(companyId),
  ]);
  const days = rulesInEffect(company, link)?.expireDays;
  if (!days || days <= 0 || !approverOf(link)) return 0;
  const waiting = await db.approvals
    .where('[companyId+status]')
    .equals([companyId, 'pending'])
    .toArray();
  const old = waiting.filter(
    (r) => addDaysISO(r.requestedAt.slice(0, 10), days) < on && requestShownTo(r, link),
  );
  if (old.length === 0) return 0;
  await db.transaction('rw', REQUEST_TABLES(), async () => {
    for (const request of old) {
      const now = nowStamp();
      await db.approvals.put({
        ...request,
        status: 'cancelled',
        decidedBy: link?.userId ?? null,
        decidedAt: now,
        expired: true,
        updatedAt: now,
      });
      await logRequest(request, 'expired');
    }
  });
  // Only in the cloud: the sync that sends it tidies up (carryOutDecided).
  return old.length;
}
