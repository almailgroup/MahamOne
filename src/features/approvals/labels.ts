import { msg } from '@/i18n';
import { lookup } from '@/lib/known';
import type { StatusTone } from '@/lib/status';
import type { ApprovalKind, ApprovalStatus } from '@/db/types';

/** What each kind of request asks for (English keys). */
export const KIND_LABELS: Record<ApprovalKind, string> = {
  invoice_edit: msg('Change to an issued document'),
  invoice_void: msg('Void'),
  invoice_unvoid: msg('Restore from void'),
  cheque_create: msg('New cheque'),
  cheque_edit: msg('Change to a cheque'),
  cheque_delete: msg('Cheque deleted'),
  cheque_replace: msg('Cheque replaced'),
  security_cheque_cash: msg('Security cheque cashed'),
  payroll: msg('Pay run'),
  letter: msg('Employee letter'),
  stock_issue: msg('Items issued'),
};

/** A kind this version doesn't know (made by a newer one) reads as a request. */
export function kindLabel(kind: string): string {
  return lookup(KIND_LABELS, kind, msg('Approval request'));
}

export const STATUS_META: Record<ApprovalStatus, { label: string; tone: StatusTone }> = {
  pending: { label: msg('Waiting for approval'), tone: 'amber' },
  approved: { label: msg('Approved'), tone: 'blue' },
  rejected: { label: msg('Rejected'), tone: 'red' },
  cancelled: { label: msg('Cancelled'), tone: 'gray' },
  applied: { label: msg('Approved and done'), tone: 'green' },
};

export function statusMeta(status: string): { label: string; tone: StatusTone } {
  return lookup(STATUS_META, status, { label: msg('Approval request'), tone: 'gray' });
}
