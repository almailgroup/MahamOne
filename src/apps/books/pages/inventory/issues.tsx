import { useMemo, useState } from 'react';
import { Link, useNavigate } from 'react-router';
import { Plus, Search, Shirt } from 'lucide-react';
import { useFormat } from '@/app/company';
import { issueSummary } from '@/db/stock-issues';
import { currentLanguage, t } from '@/i18n';
import { ButtonLink } from '@/components/ui/button';
import { Badge, Card, EmptyState, PageHeader, Segmented, Spinner } from '@/components/ui/misc';
import { Input, Select } from '@/components/ui/form';
import { useInventory } from '@/apps/books/features/inventory/use-inventory';
import {
  ISSUE_STATES,
  recipientLabel,
  useIssueRows,
  useWarehouseAccess,
  warehousePath,
  type IssueRow,
} from '@/features/inventory/issues';

type Show = 'all' | 'waiting' | 'issued' | 'other';

const matches = (row: IssueRow, show: Show) =>
  show === 'all' ||
  (show === 'waiting' && (row.state === 'waiting' || row.state === 'approved')) ||
  (show === 'issued' && row.state === 'posted') ||
  (show === 'other' && ['void', 'rejected', 'cancelled'].includes(row.state));

/**
 * Items issued to employees and the issues waiting for an approver: who
 * received what, from which warehouse, and when.
 */
export default function StockIssuesPage() {
  const fmt = useFormat();
  const navigate = useNavigate();
  const inventory = useInventory();
  const access = useWarehouseAccess();
  const rows = useIssueRows();
  const [show, setShow] = useState<Show>('all');
  const [warehouseId, setWarehouseId] = useState('');
  const [query, setQuery] = useState('');
  const ar = currentLanguage() === 'ar';

  const shown = useMemo(() => {
    const q = query.trim().toLowerCase();
    return (rows ?? []).filter(
      (row) =>
        matches(row, show) &&
        (!warehouseId || row.issue.warehouseId === warehouseId) &&
        (!q ||
          [
            row.issue.number,
            row.issue.recipient.name,
            row.issue.recipient.nameAr ?? '',
            row.issue.recipient.number,
            row.issue.recipient.jobTitle,
            ...row.issue.lines.flatMap((l) => [l.name, l.nameAr ?? '']),
          ]
            .join(' ')
            .toLowerCase()
            .includes(q)),
    );
  }, [rows, show, warehouseId, query]);

  if (!inventory || !access || !rows) return <Spinner className="py-24" label={t('Loading…')} />;

  const canIssue = inventory.warehouses.some((w) => access.issuesFrom(w));
  const waiting = rows.filter((r) => r.state === 'waiting').length;
  const used = new Set(rows.map((r) => r.issue.warehouseId));

  return (
    <div>
      <PageHeader
        title={t('Issued items')}
        description={t('Uniforms and other items handed to employees, and who confirmed them.')}
        actions={
          canIssue ? (
            <ButtonLink to="/inventory/issues/new">
              <Plus /> {t('Issue items')}
            </ButtonLink>
          ) : undefined
        }
      />
      <Card>
        <div className="flex flex-col gap-3 border-b border-slate-100 px-4 py-3 lg:flex-row lg:items-center lg:justify-between">
          <Segmented
            value={show}
            onChange={setShow}
            options={[
              { value: 'all', label: t('All'), count: rows.length },
              { value: 'waiting', label: t('Waiting for approval'), count: waiting },
              { value: 'issued', label: t('Issued') },
              { value: 'other', label: t('Void or rejected') },
            ]}
          />
          <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
            {used.size > 1 ? (
              <Select
                aria-label={t('Warehouse')}
                value={warehouseId}
                onChange={(e) => setWarehouseId(e.target.value)}
                className="sm:w-56"
              >
                <option value="">{t('All warehouses')}</option>
                {inventory.warehouses
                  .filter((w) => used.has(w.id))
                  .map((w) => (
                    <option key={w.id} value={w.id}>
                      {warehousePath(w, inventory.warehouses)}
                    </option>
                  ))}
              </Select>
            ) : null}
            <div className="relative sm:w-56">
              <Search className="pointer-events-none absolute start-3 top-1/2 size-4 -translate-y-1/2 text-slate-400" />
              <Input
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder={t('Search employees or items…')}
                aria-label={t('Search employees or items')}
                className="ps-9"
              />
            </div>
          </div>
        </div>
        {rows.length === 0 ? (
          <EmptyState
            icon={<Shirt />}
            title={t('No items issued yet')}
            description={t(
              'Uniforms, shoes and badges handed to employees show here, with who issued them and who confirmed them.',
            )}
            action={
              canIssue ? (
                <ButtonLink to="/inventory/issues/new">
                  <Plus /> {t('Issue items')}
                </ButtonLink>
              ) : undefined
            }
          />
        ) : shown.length === 0 ? (
          <p className="px-4 py-10 text-center text-sm text-slate-500">{t('Nothing matches.')}</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="border-b border-slate-100 bg-slate-50/60 text-xs text-slate-500">
                <tr>
                  <th className="px-4 py-2.5 text-start font-medium">{t('Date')}</th>
                  <th className="px-3 py-2.5 text-start font-medium">{t('Issued to')}</th>
                  <th className="hidden px-3 py-2.5 text-start font-medium md:table-cell">
                    {t('Items')}
                  </th>
                  <th className="hidden px-3 py-2.5 text-start font-medium lg:table-cell">
                    {t('Warehouse')}
                  </th>
                  <th className="px-4 py-2.5 text-start font-medium">{t('Status')}</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {shown.map((row) => {
                  const state = ISSUE_STATES[row.state];
                  const to = `/inventory/issues/${row.id}`;
                  return (
                    <tr
                      key={row.id}
                      onClick={() => navigate(to)}
                      className="cursor-pointer hover:bg-slate-50"
                    >
                      <td className="px-4 py-2.5 whitespace-nowrap">
                        <Link
                          to={to}
                          onClick={(e) => e.stopPropagation()}
                          className="font-medium text-slate-900 hover:underline"
                        >
                          {fmt.date(row.issue.date)}
                        </Link>
                        <span className="tabular block text-xs text-slate-500">
                          {row.issue.number || '—'}
                        </span>
                      </td>
                      <td className="max-w-0 px-3 py-2.5">
                        <bdi className="block truncate text-slate-900" dir="auto">
                          {recipientLabel(row.issue.recipient)}
                        </bdi>
                        <span className="block truncate text-xs text-slate-500 md:hidden">
                          {issueSummary(row.issue, ar)}
                        </span>
                      </td>
                      <td className="hidden max-w-0 px-3 py-2.5 text-slate-700 md:table-cell">
                        <bdi className="block truncate" dir="auto">
                          {issueSummary(row.issue, ar)}
                        </bdi>
                      </td>
                      <td className="hidden px-3 py-2.5 text-slate-600 lg:table-cell">
                        {warehousePath(
                          inventory.warehouses.find((w) => w.id === row.issue.warehouseId),
                          inventory.warehouses,
                        )}
                      </td>
                      <td className="px-4 py-2.5">
                        <Badge tone={state.tone}>{t(state.label)}</Badge>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </div>
  );
}
