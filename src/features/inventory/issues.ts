import { useEffect, useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { db } from '@/db/db';
import {
  issuesFrom,
  issuesOffered,
  isStockIssueRequest,
  managesWarehouses,
  requestedIssue,
} from '@/db/stock-issues';
import type {
  ApprovalRequest,
  Employee,
  ID,
  IssueRecipient,
  StockIssue,
  Warehouse,
} from '@/db/types';
import { useCompany } from '@/app/company';
import { useCloudLink } from '@/cloud/hooks';
import { useCloud } from '@/cloud/store';
import { cloudError } from '@/cloud/api';
import { canSeePeople, isApprover } from '@/cloud/roles';
import { isCurrent } from '@/lib/hr/employees';
import { currentLanguage, msg, t } from '@/i18n';
import { localName } from '@/i18n/names';

/** What the person may do with sub-warehouses and items issued, in the current company. */
export interface WarehouseAccess {
  /** Sub-warehouses and issuing are offered: the server has them, or the company is on this device. */
  offered: boolean;
  /** Sets up sub-warehouses and changes their stock directly. */
  manages: boolean;
  /** Confirms items issued (and voids them). */
  approver: boolean;
  /** The person's account; null in a company kept on this device. */
  userId: string | null;
  /** Whether the person may issue items from a warehouse. */
  issuesFrom: (warehouse: Warehouse | null | undefined) => boolean;
}

export function useWarehouseAccess(): WarehouseAccess | undefined {
  const company = useCompany();
  const link = useCloudLink(company.id);
  if (link === undefined) return undefined;
  const offered = issuesOffered(link);
  return {
    offered,
    manages: managesWarehouses(link),
    approver: !link || isApprover(link.role, link.approver),
    userId: link?.userId ?? null,
    issuesFrom: (warehouse) => offered && issuesFrom(warehouse, link),
  };
}

/** An employee as an issue names them. */
export function recipientOf(e: Employee): IssueRecipient {
  return {
    employeeId: e.id,
    number: e.number,
    name: e.name,
    nameAr: e.nameAr ?? '',
    jobTitle: e.jobTitle,
    jobTitleAr: e.jobTitleAr ?? '',
  };
}

/** The name of whoever receives items, in the interface language, with their job title. */
export function recipientLabel(
  recipient: Pick<IssueRecipient, 'name' | 'nameAr' | 'jobTitle' | 'jobTitleAr'>,
): string {
  const ar = currentLanguage() === 'ar';
  const name = (ar && recipient.nameAr) || recipient.name;
  const title = (ar && recipient.jobTitleAr) || recipient.jobTitle;
  return title ? `${name} (${title})` : name;
}

/**
 * Who items can be issued to, as the cloud last gave them, by account and
 * company: a keeper who goes offline still chooses. In memory only, never
 * stored, and forgotten once the cloud refuses that account.
 */
const lastRecipients = new Map<string, IssueRecipient[]>();

/**
 * Who items can be issued to: the current employees. Members who see People
 * have them on this device; whoever looks after a sub-warehouse asks the
 * cloud for their names and titles only (stock_issue_recipients).
 */
export function useIssueRecipients(): {
  recipients: IssueRecipient[] | undefined;
  error: string;
} {
  const company = useCompany();
  const link = useCloudLink(company.id);
  const { api } = useCloud();
  const local = link === null || (link !== undefined && canSeePeople(link.role));
  const employees = useLiveQuery(
    async () =>
      local ? await db.employees.where('companyId').equals(company.id).toArray() : undefined,
    [company.id, local],
  );
  const known = link !== undefined;
  const key = link ? `${link.userId} ${company.id}` : '';
  const [remote, setRemote] = useState<IssueRecipient[] | undefined>(undefined);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    if (local || !known || !api) return;
    let cancelled = false;
    api
      .stockIssueRecipients(company.id)
      .then((rows) => {
        const list = rows.map((r) => ({
          employeeId: r.id,
          number: r.number,
          name: r.name,
          nameAr: r.nameAr,
          jobTitle: r.jobTitle,
          jobTitleAr: r.jobTitleAr,
        }));
        lastRecipients.set(key, list);
        if (cancelled) return;
        setFailed(false);
        setRemote(list);
      })
      .catch((error: unknown) => {
        if (cloudError(error).code === 'permission') lastRecipients.delete(key);
        if (!cancelled) setFailed(true);
      });
    return () => {
      cancelled = true;
    };
  }, [api, company.id, key, known, local]);
  if (local) {
    return {
      recipients: employees
        ?.filter(isCurrent)
        .sort((a, b) => localName(a).localeCompare(localName(b)))
        .map(recipientOf),
      error: '',
    };
  }
  // The list the cloud last gave while the app is open, when it can't answer now.
  const recipients = (failed ? undefined : remote) ?? lastRecipients.get(key);
  const error =
    known && (!api || failed) && !recipients
      ? t('Connect to the internet to see who items can be issued to.')
      : '';
  return { recipients, error };
}

/** Where an issue stands: waiting for an approver, kept, or not kept. */
export type IssueState = 'waiting' | 'approved' | 'posted' | 'void' | 'rejected' | 'cancelled';

/** An issue as the lists show it: one kept, or one asked for. */
export interface IssueRow {
  /** The issue's id (a request's is the issue it would make). */
  id: ID;
  issue: StockIssue;
  request: ApprovalRequest | null;
  state: IssueState;
}

/**
 * The company's items issued and the requests to issue them, newest first.
 * A request that was carried out shows as the issue it made.
 */
export function useIssueRows(employeeId?: ID): IssueRow[] | undefined {
  const company = useCompany();
  return useLiveQuery(async () => {
    const [issues, requests] = await Promise.all([
      employeeId
        ? db.stockIssues.where('recipient.employeeId').equals(employeeId).toArray()
        : db.stockIssues.where('companyId').equals(company.id).toArray(),
      db.approvals.where('kind').equals('stock_issue').toArray(),
    ]);
    const kept = new Set(issues.map((i) => i.id));
    const bySubject = new Map(requests.map((r) => [r.subjectId, r]));
    const rows: IssueRow[] = issues
      .filter((i) => i.companyId === company.id)
      .map((issue) => ({
        id: issue.id,
        issue,
        request: bySubject.get(issue.id) ?? null,
        state: issue.status === 'void' ? 'void' : 'posted',
      }));
    for (const request of requests) {
      if (request.companyId !== company.id || !isStockIssueRequest(request)) continue;
      if (kept.has(request.subjectId)) continue;
      const issue = requestedIssue(request);
      if (!issue || (employeeId && issue.recipient.employeeId !== employeeId)) continue;
      const state: IssueState =
        request.status === 'pending'
          ? 'waiting'
          : request.status === 'approved' || request.status === 'applied'
            ? 'approved'
            : request.status;
      rows.push({ id: issue.id, issue, request, state });
    }
    return rows.sort(
      (a, b) =>
        b.issue.date.localeCompare(a.issue.date) ||
        b.issue.createdAt.localeCompare(a.issue.createdAt),
    );
  }, [company.id, employeeId]);
}

/** How each state reads, with its colour (translate where shown). */
export const ISSUE_STATES: Record<
  IssueState,
  { label: string; tone: 'amber' | 'blue' | 'green' | 'gray' | 'red' }
> = {
  waiting: { label: msg('Waiting for approval'), tone: 'amber' },
  approved: { label: msg('Confirmed'), tone: 'blue' },
  posted: { label: msg('Issued'), tone: 'green' },
  void: { label: msg('Void'), tone: 'gray' },
  rejected: { label: msg('Rejected'), tone: 'red' },
  cancelled: { label: msg('Taken back'), tone: 'gray' },
};

/** A warehouse's name, with the main warehouse it belongs to: "Main store › Ahmed’s store". */
export function warehousePath(warehouse: Warehouse | undefined, all: Warehouse[]): string {
  if (!warehouse) return '—';
  const parent = warehouse.parentId ? all.find((w) => w.id === warehouse.parentId) : undefined;
  return parent ? `${localName(parent)} › ${localName(warehouse)}` : localName(warehouse);
}
