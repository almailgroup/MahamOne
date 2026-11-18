import { Link, useParams } from 'react-router';
import { useLiveQuery } from 'dexie-react-hooks';
import { Ban, Shirt } from 'lucide-react';
import { toast } from 'sonner';
import { db } from '@/db/db';
import { voidStockIssue } from '@/db/stock-issues';
import { useCompany, useFormat } from '@/app/company';
import { useCloudLink } from '@/cloud/hooks';
import { canSeePeople } from '@/cloud/roles';
import { currentLanguage, t } from '@/i18n';
import { localName } from '@/i18n/names';
import { Button } from '@/components/ui/button';
import { Badge, Card, CardBody, EmptyState, PageHeader, Spinner } from '@/components/ui/misc';
import { useConfirm } from '@/components/ui/overlay';
import { IssueRequestCard } from '@/features/approvals/issue-request-card';
import { useMemberNames } from '@/features/approvals/hooks';
import {
  ISSUE_STATES,
  recipientLabel,
  useIssueRows,
  useWarehouseAccess,
  warehousePath,
} from '@/features/inventory/issues';

/** Items issued to an employee, or asked for: what, to whom, from where, who issued and confirmed. */
export default function StockIssueView() {
  const { id = '' } = useParams();
  const company = useCompany();
  const fmt = useFormat();
  const access = useWarehouseAccess();
  const link = useCloudLink(company.id);
  const rows = useIssueRows();
  const warehouses = useLiveQuery(
    () => db.warehouses.where('companyId').equals(company.id).toArray(),
    [company.id],
  );
  const confirm = useConfirm();
  const row = rows?.find((r) => r.id === id);
  const names = useMemberNames(company.id, link, Boolean(row));
  const ar = currentLanguage() === 'ar';

  if (!rows || !warehouses || !access || link === undefined) {
    return <Spinner className="py-24" label={t('Loading…')} />;
  }
  const breadcrumb = (
    <Link to="/inventory/issues" className="hover:text-slate-700">
      {t('Issued items')}
    </Link>
  );
  if (!row) {
    return (
      <div className="mx-auto max-w-3xl">
        <PageHeader breadcrumb={breadcrumb} title={t('Issued items')} />
        <Card>
          <EmptyState
            icon={<Shirt />}
            title={t('Not found')}
            description={t('These items issued are not on this device.')}
          />
        </Card>
      </div>
    );
  }

  const { issue, request } = row;
  const state = ISSUE_STATES[row.state];
  const kept = row.state === 'posted' || row.state === 'void';
  const warehouse = warehouses.find((w) => w.id === issue.warehouseId);
  const seesPeople = !link || canSeePeople(link.role);
  const voidIssue = async () => {
    const ok = await confirm({
      title: t('Void {number}?', { number: issue.number }),
      description: t(
        'The items stay on record as void, their stock comes back to the warehouse and their cost leaves the books.',
      ),
      confirmLabel: t('Void'),
      danger: true,
    });
    if (!ok) return;
    try {
      await voidStockIssue(issue.id);
      toast.success(t('{number} voided', { number: issue.number }));
    } catch (e) {
      toast.error(e instanceof Error ? e.message : t('Could not save.'));
    }
  };
  const nameOf = (userId: string | null, kept?: string) =>
    kept || (userId ? names.get(userId) : '') || t('A team member');

  return (
    <div className="mx-auto max-w-3xl">
      <PageHeader
        breadcrumb={breadcrumb}
        title={
          issue.number ? t('Items issued {number}', { number: issue.number }) : t('Items to issue')
        }
        description={recipientLabel(issue.recipient)}
        actions={
          kept && row.state === 'posted' && access.approver ? (
            <Button variant="outline" onClick={() => void voidIssue()}>
              <Ban /> {t('Void')}
            </Button>
          ) : undefined
        }
      />
      <div className="space-y-6">
        {!kept && request ? (
          <Card>
            <CardBody>
              <IssueRequestCard
                request={request}
                names={names}
                approver={access.approver}
                userId={access.userId}
              />
            </CardBody>
          </Card>
        ) : (
          <Card>
            <CardBody className="space-y-4">
              <div className="flex flex-wrap items-center gap-2">
                <Badge tone={state.tone}>{t(state.label)}</Badge>
                {issue.voidedAt ? (
                  <span className="text-xs text-slate-500">
                    {t('Voided on {date}', { date: fmt.dateTime(issue.voidedAt) })}
                  </span>
                ) : null}
              </div>
              <dl className="grid gap-x-6 gap-y-3 text-sm sm:grid-cols-2">
                <div>
                  <dt className="text-xs text-slate-500">{t('Issued to')}</dt>
                  <dd className="text-slate-900">
                    {seesPeople ? (
                      <Link
                        to={`/employees/${issue.recipient.employeeId}?tab=issued`}
                        className="text-primary-700 font-medium hover:underline"
                      >
                        <bdi dir="auto">{recipientLabel(issue.recipient)}</bdi>
                      </Link>
                    ) : (
                      <bdi dir="auto">{recipientLabel(issue.recipient)}</bdi>
                    )}
                    {issue.recipient.number ? (
                      <span className="tabular block text-xs text-slate-500">
                        {issue.recipient.number}
                      </span>
                    ) : null}
                  </dd>
                </div>
                <div>
                  <dt className="text-xs text-slate-500">{t('Date')}</dt>
                  <dd className="text-slate-900">{fmt.date(issue.date)}</dd>
                </div>
                <div>
                  <dt className="text-xs text-slate-500">{t('From warehouse')}</dt>
                  <dd className="text-slate-900">{warehousePath(warehouse, warehouses)}</dd>
                </div>
                <div>
                  <dt className="text-xs text-slate-500">{t('Issued by')}</dt>
                  <dd className="text-slate-900">
                    <bdi dir="auto">{nameOf(issue.issuedBy, issue.issuedByName)}</bdi>
                  </dd>
                </div>
                {issue.approvedAt ? (
                  <div className="sm:col-span-2">
                    <dt className="text-xs text-slate-500">{t('Confirmed by')}</dt>
                    <dd className="text-slate-900">
                      {t('{name} · {date}', {
                        name: nameOf(issue.approvedBy, issue.approvedByName),
                        date: fmt.dateTime(issue.approvedAt),
                      })}
                    </dd>
                  </div>
                ) : null}
              </dl>
              {issue.notes ? (
                <p
                  dir="auto"
                  className="rounded-md bg-slate-50 px-3 py-2 text-sm whitespace-pre-line text-slate-700"
                >
                  {issue.notes}
                </p>
              ) : null}
            </CardBody>
          </Card>
        )}

        <Card>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="border-b border-slate-100 bg-slate-50/60 text-xs text-slate-500">
                <tr>
                  <th className="w-full px-4 py-2.5 text-start font-medium">{t('Item')}</th>
                  <th className="px-4 py-2.5 text-end font-medium">{t('Quantity')}</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {issue.lines.map((line) => (
                  <tr key={line.id}>
                    <td className="px-4 py-2.5 text-slate-900">
                      <bdi dir="auto">{(ar && line.nameAr) || line.name}</bdi>
                    </td>
                    <td className="tabular px-4 py-2.5 text-end whitespace-nowrap text-slate-900">
                      {fmt.quantity(line.quantity)}
                      {line.unit ? <span className="text-slate-500"> {line.unit}</span> : null}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
        {warehouse ? (
          <p className="text-xs text-slate-500">
            {t('Stock of {warehouse}:', { warehouse: localName(warehouse) })}{' '}
            <Link to="/inventory" className="text-primary-700 hover:underline">
              {t('Inventory')}
            </Link>
          </p>
        ) : null}
      </div>
    </div>
  );
}
