import { useEffect, useMemo, useState } from 'react';
import { isStockIssueRequest } from '@/db/stock-issues';
import { IssueRequestCard } from './issue-request-card';
import { useLiveQuery } from 'dexie-react-hooks';
import { ClipboardCheck } from 'lucide-react';
import { db } from '@/db/db';
import { expirePending, requestShownTo } from '@/db/approvals';
import type { ApprovalRequest, Client, InvoiceDocument } from '@/db/types';
import { useCompany } from '@/app/company';
import { msg, t } from '@/i18n';
import { Card, EmptyState, Segmented, Spinner } from '@/components/ui/misc';
import { useApprovalView, useCaughtUp, useMemberNames } from './hooks';
import { ApprovalRequestCard } from './request-card';
import { ChequeRequestCard } from './cheque-request-card';
import { isChequeRequest } from '@/db/cheque-rules';
import { isLetterApproval, isPayrollApproval } from '@/cloud/roles';
import { PayrollRequestCard } from '@/features/payroll/approval-panel';
import { LetterRequestCard } from '@/features/people/letter-dialog';

type Tab = 'waiting' | 'decided' | 'mine';

const TABS: { value: Tab; label: string }[] = [
  { value: 'waiting', label: msg('Waiting') },
  { value: 'mine', label: msg('Asked by me') },
  { value: 'decided', label: msg('Decided') },
];

/** Decided requests shown, the latest first. */
const DECIDED_SHOWN = 100;

/**
 * The company's approval requests: those waiting (approvers decide them
 * here), the person's own, and the latest decided. Requests that waited
 * longer than the rules allow are cancelled when an approver opens it.
 */
export function ApprovalsInbox() {
  const company = useCompany();
  const view = useApprovalView(company);
  const names = useMemberNames(company.id, view.link);
  const [tab, setTab] = useState<Tab>('waiting');
  const userId = view.link?.userId ?? null;

  const caughtUp = useCaughtUp(company.id);
  useEffect(() => {
    if (view.approver && caughtUp) void expirePending(company.id).catch(() => undefined);
  }, [company.id, view.approver, caughtUp]);

  const all = useLiveQuery(
    () => db.approvals.where('companyId').equals(company.id).toArray(),
    [company.id],
  );
  // Requests about People data stay out of sight of a member the owner gave no access to it.
  const requests = useMemo(
    () => all?.filter((r) => requestShownTo(r, view.link)),
    [all, view.link],
  );
  const ids = useMemo(() => [...new Set((requests ?? []).map((r) => r.subjectId))], [requests]);
  const docs = useLiveQuery(
    async () =>
      new Map(
        (await db.documents.bulkGet(ids))
          .filter((d): d is InvoiceDocument => Boolean(d))
          .map((d) => [d.id, d]),
      ),
    [ids.join(' ')],
  );
  const clients = useLiveQuery(
    async () =>
      new Map<string, Client>(
        (await db.clients.where('companyId').equals(company.id).toArray()).map((c) => [c.id, c]),
      ),
    [company.id],
  );

  const shown = useMemo(() => {
    if (!requests) return null;
    const newest = (a: ApprovalRequest, b: ApprovalRequest) =>
      (b.decidedAt ?? b.requestedAt).localeCompare(a.decidedAt ?? a.requestedAt);
    if (tab === 'waiting') {
      return requests
        .filter((r) => r.status === 'pending')
        .sort((a, b) => a.requestedAt.localeCompare(b.requestedAt));
    }
    if (tab === 'mine') return requests.filter((r) => r.requestedBy === userId).sort(newest);
    return requests
      .filter((r) => r.status !== 'pending')
      .sort(newest)
      .slice(0, DECIDED_SHOWN);
  }, [requests, tab, userId]);

  const waiting = requests?.filter((r) => r.status === 'pending').length ?? 0;

  if (!shown || !docs || !clients) return <Spinner className="py-24" label={t('Loading…')} />;
  return (
    <Card>
      <div className="border-b border-slate-100 p-4">
        <Segmented
          value={tab}
          onChange={setTab}
          options={TABS.map((o) => ({
            value: o.value,
            label: t(o.label),
            count: o.value === 'waiting' ? waiting : undefined,
          }))}
        />
      </div>
      {shown.length === 0 ? (
        <EmptyState
          icon={<ClipboardCheck />}
          title={tab === 'waiting' ? t('Nothing is waiting for approval.') : t('No requests yet.')}
          description={
            view.approver
              ? t('Changes that need your approval show here.')
              : t('Changes you send for approval show here until they are decided.')
          }
        />
      ) : (
        <ul className="divide-y divide-slate-100">
          {shown.map((request) => (
            <li key={request.id} className="px-5 py-4">
              {isPayrollApproval(request) ? (
                <PayrollRequestCard
                  request={request}
                  names={names}
                  approver={view.approver}
                  link={view.link}
                  showSubject
                />
              ) : isLetterApproval(request) ? (
                <LetterRequestCard request={request} names={names} showSubject />
              ) : isStockIssueRequest(request) ? (
                <IssueRequestCard
                  request={request}
                  names={names}
                  approver={view.approver}
                  userId={userId}
                  showSubject
                />
              ) : isChequeRequest(request) ? (
                <ChequeRequestCard
                  request={request}
                  clients={clients}
                  names={names}
                  approver={view.approver}
                  userId={userId}
                  showSubject
                />
              ) : (
                <ApprovalRequestCard
                  request={request}
                  doc={docs.get(request.subjectId)}
                  clients={clients}
                  names={names}
                  approver={view.approver}
                  userId={userId}
                  showSubject
                />
              )}
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}
