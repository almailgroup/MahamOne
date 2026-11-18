import { Link } from 'react-router';
import { useLiveQuery } from 'dexie-react-hooks';
import { Shirt } from 'lucide-react';
import { db } from '@/db/db';
import type { Employee } from '@/db/types';
import { useCompany, useFormat } from '@/app/company';
import { dec } from '@/lib/money';
import { currentLanguage, t } from '@/i18n';
import { Badge, Card, CardHeader, EmptyState, Spinner } from '@/components/ui/misc';
import { ButtonLink } from '@/components/ui/button';
import {
  ISSUE_STATES,
  useIssueRows,
  useWarehouseAccess,
  warehousePath,
} from '@/features/inventory/issues';

/**
 * The items issued to an employee (uniforms, shoes, badges): what they hold
 * now, item by item, and every issue with its date, warehouse and status.
 */
export function IssuedItemsTab({ employee }: { employee: Employee }) {
  const company = useCompany();
  const fmt = useFormat();
  const rows = useIssueRows(employee.id);
  const access = useWarehouseAccess();
  const warehouses = useLiveQuery(
    () => db.warehouses.where('companyId').equals(company.id).toArray(),
    [company.id],
  );
  const ar = currentLanguage() === 'ar';
  if (!rows || !warehouses || !access) return <Spinner className="py-16" label={t('Loading…')} />;

  // What they hold: the items of every issue kept and not void.
  const held = new Map<string, { name: string; unit: string; quantity: number }>();
  for (const row of rows) {
    if (row.state !== 'posted') continue;
    for (const line of row.issue.lines) {
      const name = (ar && line.nameAr) || line.name;
      const found = held.get(line.productId);
      held.set(line.productId, {
        name,
        unit: line.unit,
        quantity: dec(found?.quantity ?? 0)
          .plus(line.quantity)
          .toNumber(),
      });
    }
  }
  const canIssue = warehouses.some((w) => access.issuesFrom(w));
  const issueLink = `/inventory/issues/new?employee=${employee.id}`;

  if (rows.length === 0) {
    return (
      <Card>
        <EmptyState
          icon={<Shirt />}
          title={t('No items issued yet')}
          description={t('Uniforms and other items issued to this employee show here.')}
          action={
            canIssue ? (
              <ButtonLink to={issueLink} variant="outline">
                <Shirt /> {t('Issue items')}
              </ButtonLink>
            ) : undefined
          }
        />
      </Card>
    );
  }

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader
          title={t('Items held')}
          description={t('Everything issued to them and confirmed, item by item.')}
          actions={
            canIssue ? (
              <ButtonLink to={issueLink} size="sm" variant="outline">
                <Shirt /> {t('Issue items')}
              </ButtonLink>
            ) : undefined
          }
        />
        {held.size === 0 ? (
          <p className="px-5 py-6 text-sm text-slate-500">{t('Nothing confirmed yet.')}</p>
        ) : (
          <ul className="divide-y divide-slate-100">
            {[...held.values()]
              .sort((a, b) => a.name.localeCompare(b.name))
              .map((item) => (
                <li key={item.name} className="flex items-baseline gap-3 px-5 py-2.5 text-sm">
                  <span className="tabular w-12 shrink-0 text-end font-medium text-slate-900">
                    {fmt.quantity(item.quantity)}
                  </span>
                  <bdi dir="auto" className="text-slate-800">
                    {item.name}
                  </bdi>
                  {item.unit ? <span className="text-xs text-slate-500">{item.unit}</span> : null}
                </li>
              ))}
          </ul>
        )}
      </Card>
      <Card>
        <CardHeader title={t('Issued items')} />
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="border-b border-slate-100 bg-slate-50/60 text-xs text-slate-500">
              <tr>
                <th className="px-5 py-2.5 text-start font-medium">{t('Date')}</th>
                <th className="px-3 py-2.5 text-start font-medium">{t('Items')}</th>
                <th className="hidden px-3 py-2.5 text-start font-medium md:table-cell">
                  {t('Warehouse')}
                </th>
                <th className="px-5 py-2.5 text-start font-medium">{t('Status')}</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {rows.map((row) => {
                const state = ISSUE_STATES[row.state];
                return (
                  <tr key={row.id}>
                    <td className="px-5 py-2.5 whitespace-nowrap">
                      <Link
                        to={`/inventory/issues/${row.id}`}
                        className="font-medium text-slate-900 hover:underline"
                      >
                        {fmt.date(row.issue.date)}
                      </Link>
                      <span className="tabular block text-xs text-slate-500">
                        {row.issue.number || '—'}
                      </span>
                    </td>
                    <td className="px-3 py-2.5 text-slate-700">
                      {row.issue.lines.map((line) => (
                        <bdi key={line.id} dir="auto" className="block">
                          {fmt.quantity(line.quantity)} {(ar && line.nameAr) || line.name}
                        </bdi>
                      ))}
                    </td>
                    <td className="hidden px-3 py-2.5 text-slate-600 md:table-cell">
                      {warehousePath(
                        warehouses.find((w) => w.id === row.issue.warehouseId),
                        warehouses,
                      )}
                    </td>
                    <td className="px-5 py-2.5">
                      <Badge tone={state.tone}>{t(state.label)}</Badge>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </Card>
    </div>
  );
}
