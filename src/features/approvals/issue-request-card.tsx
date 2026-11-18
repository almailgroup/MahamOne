import { useState, type ReactNode } from 'react';
import { Link } from 'react-router';
import { useLiveQuery } from 'dexie-react-hooks';
import { Check, RotateCcw, Undo2, X } from 'lucide-react';
import { toast } from 'sonner';
import { db } from '@/db/db';
import { cancelApproval, decideApproval } from '@/db/approvals';
import { issueRequestProblem, issueShortfall, requestedIssue } from '@/db/stock-issues';
import type { ApprovalRequest } from '@/db/types';
import { useFormat } from '@/app/company';
import { currentLanguage, t } from '@/i18n';
import { localName } from '@/i18n/names';
import { Badge } from '@/components/ui/misc';
import { Button } from '@/components/ui/button';
import { useCloud } from '@/cloud/store';
import { approve, carryOut } from './decide';
import { useDecisionUnsent } from './hooks';
import { kindLabel, statusMeta } from './labels';
import { ReasonDialog } from './reason-dialog';

function nameOf(id: string | null, names: Map<string, string>, kept?: string): string {
  if (!id) return kept || t('A team member');
  return kept || names.get(id) || t('A team member');
}

/**
 * One request to issue items to an employee: who issued what to whom, from
 * which warehouse, and what the person may do with it: confirm or reject it
 * (approvers), take it back (whoever asked), carry it out again.
 */
export function IssueRequestCard({
  request,
  names,
  approver,
  userId,
  showSubject = false,
  extra,
}: {
  request: ApprovalRequest;
  names: Map<string, string>;
  approver: boolean;
  /** The person's account in the cloud. */
  userId: string | null;
  /** Links to the issue (in the inbox). */
  showSubject?: boolean;
  extra?: ReactNode;
}) {
  const fmt = useFormat();
  const [busy, setBusy] = useState<string | null>(null);
  const [rejecting, setRejecting] = useState(false);
  const meta = statusMeta(request.status);
  const issue = requestedIssue(request);
  const pending = request.status === 'pending';
  const mine = userId !== null && request.requestedBy === userId;
  const ar = currentLanguage() === 'ar';
  const warehouse = useLiveQuery(
    () => (issue ? db.warehouses.get(issue.warehouseId) : undefined),
    [issue?.warehouseId],
  );
  // Whether the warehouse still holds what is asked, for the approver.
  const shortfall = useLiveQuery(
    () => (approver && pending ? issueShortfall(request) : Promise.resolve(null)),
    [approver, pending, request.id, request.status],
  );
  // What keeps it from being confirmed: an item that isn't a stock item, a
  // quantity that isn't positive.
  const problem = useLiveQuery(
    () =>
      approver && (pending || request.status === 'approved')
        ? issueRequestProblem(request)
        : Promise.resolve(null),
    [approver, pending, request.id, request.status],
  );
  const { manager } = useCloud();
  // Confirmed here, and not in the cloud yet: recorded once it is.
  const unsent = useDecisionUnsent(request.id);

  const run = async (key: string, work: () => Promise<unknown>, done: string) => {
    setBusy(key);
    try {
      const outcome = await work();
      if (outcome === 'waiting') {
        toast.success(t('Confirmed. It is recorded once this device has synced.'));
      } else {
        toast.success(done);
      }
    } catch (error) {
      toast.error(error instanceof Error ? error.message : t('Something went wrong.'));
      throw error;
    } finally {
      setBusy(null);
    }
  };

  if (!issue) {
    return (
      <p className="text-sm text-slate-600">
        {t(kindLabel(request.kind))} · {t(meta.label)}
      </p>
    );
  }
  const recipient = issue.recipient;
  const who = (ar && recipient.nameAr) || recipient.name;
  const title = (ar && recipient.jobTitleAr) || recipient.jobTitle;
  const link = showSubject ? `/inventory/issues/${request.subjectId}` : null;

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        {link ? (
          <Link to={link} className="font-medium text-slate-900 hover:underline">
            {t(kindLabel(request.kind))}
          </Link>
        ) : (
          <span className="font-medium text-slate-900">{t(kindLabel(request.kind))}</span>
        )}
        <Badge tone={meta.tone}>{t(meta.label)}</Badge>
        {request.expired ? <Badge tone="gray">{t('Expired')}</Badge> : null}
      </div>
      <p className="text-sm text-slate-800">
        {t('{issuer} issued to {name}:', {
          issuer: nameOf(request.requestedBy, names, request.requestedByName),
          name: title ? `${who} (${title})` : who,
        })}
      </p>
      <ul className="space-y-1 text-sm">
        {issue.lines.map((line) => (
          <li key={line.id} className="flex items-baseline gap-2">
            <span className="tabular w-10 shrink-0 text-end font-medium text-slate-900">
              {fmt.quantity(line.quantity)}
            </span>
            <bdi dir="auto" className="text-slate-800">
              {(ar && line.nameAr) || line.name}
            </bdi>
            {line.unit ? <span className="text-xs text-slate-500">{line.unit}</span> : null}
          </li>
        ))}
      </ul>
      <dl className="grid gap-x-6 gap-y-1 text-sm sm:grid-cols-3">
        <div className="flex justify-between gap-3 sm:block">
          <dt className="text-xs text-slate-500">{t('From warehouse')}</dt>
          <dd className="text-slate-800">{warehouse ? localName(warehouse) : '—'}</dd>
        </div>
        <div className="flex justify-between gap-3 sm:block">
          <dt className="text-xs text-slate-500">{t('Date')}</dt>
          <dd className="text-slate-800">{fmt.date(issue.date)}</dd>
        </div>
        {recipient.number ? (
          <div className="flex justify-between gap-3 sm:block">
            <dt className="text-xs text-slate-500">{t('Employee number')}</dt>
            <dd className="tabular text-slate-800">{recipient.number}</dd>
          </div>
        ) : null}
      </dl>
      <p className="text-xs text-slate-500">
        {t('Asked by {name} · {date}', {
          name: nameOf(request.requestedBy, names, request.requestedByName),
          date: fmt.dateTime(request.requestedAt),
        })}
      </p>
      {request.reason ? (
        <p
          dir="auto"
          className="rounded-md bg-slate-50 px-3 py-2 text-sm whitespace-pre-line text-slate-700"
        >
          {request.reason}
        </p>
      ) : null}
      {problem ? (
        <p role="alert" className="text-sm text-red-700">
          {problem}
        </p>
      ) : null}
      {shortfall && !problem ? (
        <p role="alert" className="text-sm text-amber-700">
          {shortfall}{' '}
          {t('Confirming it takes the stock below zero; send more stock to the warehouse first.')}
        </p>
      ) : null}
      {request.decidedAt && !pending ? (
        <p className="text-xs text-slate-500">
          {t('{status} by {name} · {date}', {
            status: t(meta.label),
            name: nameOf(request.decidedBy, names),
            date: fmt.dateTime(request.decidedAt),
          })}
          {request.decisionNote ? (
            <>
              {' · '}
              <bdi dir="auto">{request.decisionNote}</bdi>
            </>
          ) : null}
        </p>
      ) : null}
      {request.status === 'approved' ? (
        <p className="text-xs text-amber-700">
          {unsent
            ? t('Confirmed. It is recorded once this device has synced.')
            : t(
                'Confirmed, but not recorded yet on this device. Carry it out again, or reject it if it can’t be recorded.',
              )}
        </p>
      ) : null}
      {extra}

      <div className="flex flex-wrap gap-2">
        {pending && approver ? (
          <>
            <Button
              size="sm"
              loading={busy === 'approve'}
              disabled={busy !== null || Boolean(problem)}
              onClick={() =>
                void run(
                  'approve',
                  () => approve(request.id, manager),
                  t('Confirmed: the items are issued'),
                ).catch(() => undefined)
              }
            >
              <Check /> {t('Confirm')}
            </Button>
            <Button
              size="sm"
              variant="outline"
              disabled={busy !== null}
              onClick={() => setRejecting(true)}
            >
              <X /> {t('Reject')}
            </Button>
          </>
        ) : null}
        {pending && mine && !approver ? (
          <Button
            size="sm"
            variant="outline"
            loading={busy === 'cancel'}
            disabled={busy !== null}
            onClick={() =>
              void run('cancel', () => cancelApproval(request.id), t('Request taken back')).catch(
                () => undefined,
              )
            }
          >
            <Undo2 /> {t('Take back')}
          </Button>
        ) : null}
        {request.status === 'approved' && approver ? (
          <>
            <Button
              size="sm"
              variant="outline"
              loading={busy === 'apply'}
              disabled={busy !== null || Boolean(problem)}
              onClick={() =>
                void run(
                  'apply',
                  () => carryOut(request.id, manager),
                  t('Confirmed: the items are issued'),
                ).catch(() => undefined)
              }
            >
              <RotateCcw /> {t('Carry it out again')}
            </Button>
            <Button
              size="sm"
              variant="outline"
              disabled={busy !== null}
              onClick={() => setRejecting(true)}
            >
              <X /> {t('Reject')}
            </Button>
          </>
        ) : null}
      </div>

      {rejecting ? (
        <ReasonDialog
          open
          onOpenChange={setRejecting}
          title={t('Reject these items?')}
          description={t('Nothing leaves the warehouse. Whoever asked sees why.')}
          label={t('Note for whoever asked')}
          required={false}
          confirmLabel={t('Reject')}
          danger
          onConfirm={(note) =>
            run('reject', () => decideApproval(request.id, 'rejected', note), t('Rejected'))
          }
        />
      ) : null}
    </div>
  );
}
