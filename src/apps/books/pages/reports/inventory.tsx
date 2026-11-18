import { useMemo, useState, type ReactNode } from 'react';
import { Link, useSearchParams } from 'react-router';
import { CheckCircle2, Download, ShoppingCart, TriangleAlert } from 'lucide-react';
import { useLiveQuery } from 'dexie-react-hooks';
import { db } from '@/db/db';
import { accountingSettings } from '@/db/chart-setup';
import type { ID, Product, StockIssue } from '@/db/types';
import { useCompany, useFormat } from '@/app/company';
import { useCloudLink } from '@/cloud/hooks';
import { useMemberNames } from '@/features/approvals/hooks';
import { compareMovements, stockLevels } from '@/lib/inventory/costing';
import { stockAccounts } from '@/lib/inventory/sources';
import { downloadCsv } from '@/lib/csv';
import { today } from '@/lib/dates';
import { dec, fromMinor, round, toMinor } from '@/lib/money';
import { currentLanguage, t } from '@/i18n';
import { localName } from '@/i18n/names';
import { Button, ButtonLink } from '@/components/ui/button';
import { Badge, Card, EmptyState, Spinner } from '@/components/ui/misc';
import { Select } from '@/components/ui/form';
import { Combobox } from '@/components/ui/combobox';
import { MOVEMENT_LABELS, movementLink } from '@/apps/books/features/inventory/labels';
import {
  isLowStock,
  useInventory,
  useUnitAmount,
  type InventoryData,
} from '@/apps/books/features/inventory/use-inventory';
import { useLedger } from '@/apps/books/features/accounting/use-ledger';
import { isolate } from '@/apps/books/features/reports/report-language';
import { DateField } from '@/components/ui/date-field';

export type InventoryReportId =
  'stock-on-hand' | 'stock-valuation' | 'stock-movements' | 'low-stock' | 'issued-items';

export const INVENTORY_REPORTS: InventoryReportId[] = [
  'stock-on-hand',
  'stock-valuation',
  'stock-movements',
  'low-stock',
  'issued-items',
];

function Th({ children, end }: { children: ReactNode; end?: boolean }) {
  return (
    <th
      className={`px-4 py-3 text-xs font-medium tracking-wide whitespace-nowrap text-slate-500 uppercase ${end ? 'text-end' : 'text-start'}`}
    >
      {children}
    </th>
  );
}

function Td({ children, end, strong }: { children: ReactNode; end?: boolean; strong?: boolean }) {
  return (
    <td
      className={`px-4 py-2.5 whitespace-nowrap ${end ? 'tabular text-end' : ''} ${strong ? 'font-semibold text-slate-900' : 'text-slate-700'}`}
    >
      {children}
    </td>
  );
}

function Toolbar({ children, onExport }: { children?: ReactNode; onExport?: () => void }) {
  return (
    <div className="mb-4 flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
      <div className="flex flex-wrap items-end gap-2">{children}</div>
      {onExport ? (
        <Button variant="outline" onClick={onExport}>
          <Download /> {t('Export CSV')}
        </Button>
      ) : null}
    </div>
  );
}

function DateInput({
  label,
  value,
  onChange,
  required,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  required?: boolean;
}) {
  return (
    <label className="block">
      <span className="mb-1 block text-xs font-medium text-slate-500">{label}</span>
      <DateField
        value={value}
        onChange={(iso) => (iso || !required) && onChange(iso)}
        className="w-40"
      />
    </label>
  );
}

const itemName = (item: Product | undefined) => (item ? localName(item) : '—');

/** Stock on hand by warehouse, valuation at a date, movements of an item and low stock. */
export function InventoryReports({ report }: { report: InventoryReportId }) {
  const inventory = useInventory();
  if (!inventory) return <Spinner className="py-24" label={t('Loading…')} />;
  if (inventory.stockItems.length === 0) {
    return (
      <Card>
        <EmptyState
          title={t('No stock items yet')}
          description={t(
            'Mark the goods you keep as stock items. Bills bring them in, invoices take them out, and the cost of sales follows.',
          )}
          action={<ButtonLink to="/products?new=1&kind=stock">{t('New stock item')}</ButtonLink>}
        />
      </Card>
    );
  }
  if (report === 'stock-on-hand') return <StockOnHand inventory={inventory} />;
  if (report === 'stock-valuation') return <StockValuation inventory={inventory} />;
  if (report === 'stock-movements') return <ItemMovements inventory={inventory} />;
  if (report === 'issued-items') return <IssuedItems inventory={inventory} />;
  return <LowStock inventory={inventory} />;
}

/**
 * Items issued to employees, line by line: who received which item, how
 * many, when, from which warehouse, who issued and who confirmed it. Void
 * issues and those still waiting for approval are left out.
 */
function IssuedItems({ inventory }: { inventory: InventoryData }) {
  const company = useCompany();
  const fmt = useFormat();
  const issues = useLiveQuery(
    () => db.stockIssues.where('companyId').equals(company.id).toArray(),
    [company.id],
  );
  const [warehouseId, setWarehouseId] = useState('');
  const [employeeId, setEmployeeId] = useState('');
  const [itemId, setItemId] = useState('');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const link = useCloudLink(company.id);
  // Who issued and confirmed each, by their account when no name was kept.
  const names = useMemberNames(company.id, link, Boolean(issues?.length));
  const ar = currentLanguage() === 'ar';
  if (!issues) return <Spinner className="py-24" label={t('Loading…')} />;
  const issuer = (i: StockIssue) =>
    i.issuedByName || (i.issuedBy ? (names.get(i.issuedBy) ?? '') : '');
  const approver = (i: StockIssue) =>
    i.approvedByName || (i.approvedBy ? (names.get(i.approvedBy) ?? '') : '');

  const kept = issues.filter((i) => i.status === 'posted');
  // The employees and items of the issues themselves: no People data needed.
  const people = new Map(kept.map((i) => [i.recipient.employeeId, i.recipient]));
  const things = new Map(kept.flatMap((i) => i.lines.map((l) => [l.productId, l] as const)));
  const rows = kept
    .filter(
      (i) =>
        (!warehouseId || i.warehouseId === warehouseId) &&
        (!employeeId || i.recipient.employeeId === employeeId) &&
        (!from || i.date >= from) &&
        (!to || i.date <= to),
    )
    .sort((a, b) => b.date.localeCompare(a.date) || b.number.localeCompare(a.number))
    .flatMap((issue) =>
      issue.lines.filter((l) => !itemId || l.productId === itemId).map((line) => ({ issue, line })),
    );
  const total = rows.reduce((sum, r) => sum.plus(r.line.quantity), dec(0)).toNumber();
  const warehouseName = (id: ID) => localName(inventory.warehouses.find((w) => w.id === id));
  const person = (r: (typeof rows)[number]['issue']['recipient']) => {
    const name = (ar && r.nameAr) || r.name;
    const title = (ar && r.jobTitleAr) || r.jobTitle;
    return title ? `${name} (${title})` : name;
  };

  const exportCsv = () =>
    downloadCsv(
      'issued-items',
      [
        t('Date'),
        t('Number'),
        t('Employee number'),
        t('Employee'),
        t('Job title'),
        t('Item'),
        t('Quantity'),
        t('Unit'),
        t('Warehouse'),
        t('Issued by'),
        t('Confirmed by'),
      ],
      rows.map(({ issue, line }) => [
        issue.date,
        issue.number,
        issue.recipient.number,
        (ar && issue.recipient.nameAr) || issue.recipient.name,
        (ar && issue.recipient.jobTitleAr) || issue.recipient.jobTitle,
        (ar && line.nameAr) || line.name,
        line.quantity,
        line.unit,
        warehouseName(issue.warehouseId),
        issuer(issue),
        approver(issue),
      ]),
    );

  return (
    <div>
      <Toolbar onExport={rows.length ? exportCsv : undefined}>
        <label className="block w-56">
          <span className="mb-1 block text-xs font-medium text-slate-500">{t('Employee')}</span>
          <Combobox
            ariaLabel={t('Employee')}
            value={employeeId}
            onChange={setEmployeeId}
            options={[
              { value: '', label: t('All employees') },
              ...[...people.values()]
                .sort((a, b) => a.name.localeCompare(b.name))
                .map((r) => ({
                  value: r.employeeId,
                  label: person(r),
                  detail: r.number,
                  keywords: `${r.name} ${r.nameAr ?? ''} ${r.number}`,
                })),
            ]}
            placeholder={t('All employees')}
            searchPlaceholder={t('Search employees…')}
          />
        </label>
        <label className="block w-48">
          <span className="mb-1 block text-xs font-medium text-slate-500">{t('Item')}</span>
          <Select value={itemId} onChange={(e) => setItemId(e.target.value)}>
            <option value="">{t('All items')}</option>
            {[...things.values()]
              .sort((a, b) => a.name.localeCompare(b.name))
              .map((l) => (
                <option key={l.productId} value={l.productId}>
                  {(ar && l.nameAr) || l.name}
                </option>
              ))}
          </Select>
        </label>
        {inventory.warehouses.length > 1 ? (
          <label className="block w-48">
            <span className="mb-1 block text-xs font-medium text-slate-500">{t('Warehouse')}</span>
            <Select value={warehouseId} onChange={(e) => setWarehouseId(e.target.value)}>
              <option value="">{t('All warehouses')}</option>
              {inventory.warehouses.map((w) => (
                <option key={w.id} value={w.id}>
                  {localName(w)}
                </option>
              ))}
            </Select>
          </label>
        ) : null}
        <DateInput label={t('From')} value={from} onChange={setFrom} />
        <DateInput label={t('To')} value={to} onChange={setTo} />
      </Toolbar>
      <Card className="overflow-hidden">
        {rows.length === 0 ? (
          <EmptyState
            title={t('No items issued')}
            description={t('Items issued to employees and confirmed show here, line by line.')}
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="border-b border-slate-100 bg-slate-50/60">
                <tr>
                  <Th>{t('Date')}</Th>
                  <Th>{t('Employee')}</Th>
                  <Th>{t('Item')}</Th>
                  <Th end>{t('Quantity')}</Th>
                  <Th>{t('Warehouse')}</Th>
                  <Th>{t('Issued by')}</Th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {rows.map(({ issue, line }) => (
                  <tr key={`${issue.id}-${line.id}`}>
                    <Td>
                      <Link
                        to={`/inventory/issues/${issue.id}`}
                        className="text-primary-700 hover:underline"
                      >
                        {fmt.date(issue.date)}
                      </Link>
                      <span className="tabular block text-xs text-slate-500">{issue.number}</span>
                    </Td>
                    <Td>
                      <bdi dir="auto">{person(issue.recipient)}</bdi>
                      <span className="tabular block text-xs text-slate-500">
                        {issue.recipient.number}
                      </span>
                    </Td>
                    <Td>
                      <bdi dir="auto">{(ar && line.nameAr) || line.name}</bdi>
                    </Td>
                    <Td end strong>
                      {fmt.quantity(line.quantity)}
                      {line.unit ? (
                        <span className="font-normal text-slate-500"> {line.unit}</span>
                      ) : null}
                    </Td>
                    <Td>{warehouseName(issue.warehouseId)}</Td>
                    <Td>
                      <bdi dir="auto">{issuer(issue) || '—'}</bdi>
                    </Td>
                  </tr>
                ))}
              </tbody>
              <tfoot className="border-t border-slate-200 bg-slate-50/60">
                <tr>
                  <Td strong>{t('Total')}</Td>
                  <Td>{''}</Td>
                  <Td>{''}</Td>
                  <Td end strong>
                    {fmt.quantity(total)}
                  </Td>
                  <Td>{''}</Td>
                  <Td>{''}</Td>
                </tr>
              </tfoot>
            </table>
          </div>
        )}
      </Card>
    </div>
  );
}

function StockOnHand({ inventory }: { inventory: InventoryData }) {
  const fmt = useFormat();
  const [asAt, setAsAt] = useState(today());
  const levels = useMemo(
    () => stockLevels(inventory.movements, inventory.precision, asAt),
    [inventory, asAt],
  );
  const warehouses = inventory.warehouses.filter(
    (w) => !w.archived || [...levels.values()].some((l) => l.byWarehouse.get(w.id)),
  );
  const items = inventory.stockItems
    .filter((i) => !i.archived || levels.get(i.id)?.quantity)
    .sort((a, b) => localName(a).localeCompare(localName(b)));
  const p = inventory.precision;
  const total = items.reduce((sum, i) => sum + toMinor(levels.get(i.id)?.value ?? 0, p), 0);

  const exportCsv = () =>
    downloadCsv(
      `stock-on-hand-${asAt}`,
      [t('SKU'), t('Item'), ...warehouses.map((w) => localName(w)), t('Total'), t('Value')],
      items.map((i) => {
        const level = levels.get(i.id);
        return [
          i.sku,
          localName(i),
          ...warehouses.map((w) => level?.byWarehouse.get(w.id) ?? 0),
          level?.quantity ?? 0,
          level?.value ?? 0,
        ];
      }),
    );

  return (
    <div>
      <Toolbar onExport={exportCsv}>
        <DateInput label={t('As at')} value={asAt} onChange={setAsAt} required />
      </Toolbar>
      <Card className="overflow-hidden">
        <div className="border-b border-slate-100 px-4 py-3 text-sm text-slate-500">
          {t('Quantity of each stock item by warehouse, at the end of {date}.', {
            date: isolate(fmt.date(asAt)),
          })}
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="border-b border-slate-100">
              <tr>
                <Th>{t('Item')}</Th>
                {warehouses.map((w) => (
                  <Th key={w.id} end>
                    {localName(w)}
                  </Th>
                ))}
                {warehouses.length > 1 ? <Th end>{t('Total')}</Th> : null}
                <Th end>{t('Value')}</Th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {items.map((i) => {
                const level = levels.get(i.id);
                return (
                  <tr key={i.id}>
                    <Td>
                      <Link
                        to={`/reports/stock-movements?item=${i.id}`}
                        className="hover:text-primary-700 font-medium text-slate-900"
                      >
                        {localName(i)}
                      </Link>
                      {i.sku ? <span className="ms-2 text-xs text-slate-500">{i.sku}</span> : null}
                    </Td>
                    {warehouses.map((w) => {
                      const q = level?.byWarehouse.get(w.id) ?? 0;
                      return (
                        <Td key={w.id} end>
                          <span
                            className={q === 0 ? 'text-slate-300' : q < 0 ? 'text-red-600' : ''}
                          >
                            {fmt.quantity(q)}
                          </span>
                        </Td>
                      );
                    })}
                    {warehouses.length > 1 ? (
                      <Td end strong>
                        {fmt.quantity(level?.quantity ?? 0)}
                      </Td>
                    ) : null}
                    <Td end>{fmt.money(level?.value ?? 0)}</Td>
                  </tr>
                );
              })}
            </tbody>
            <tfoot className="border-t-2 border-slate-200 bg-slate-50/60">
              <tr>
                <Td strong>{t('Total')}</Td>
                {warehouses.map((w) => (
                  <Td key={w.id} end>
                    {''}
                  </Td>
                ))}
                {warehouses.length > 1 ? <Td end>{''}</Td> : null}
                <Td end strong>
                  {fmt.money(fromMinor(total, p))}
                </Td>
              </tr>
            </tfoot>
          </table>
        </div>
      </Card>
    </div>
  );
}

function StockValuation({ inventory }: { inventory: InventoryData }) {
  const company = useCompany();
  const fmt = useFormat();
  const unitAmount = useUnitAmount();
  const ledger = useLedger();
  const [asAt, setAsAt] = useState(today());
  const levels = useMemo(
    () => stockLevels(inventory.movements, inventory.precision, asAt),
    [inventory, asAt],
  );
  const p = inventory.precision;
  const items = inventory.stockItems
    .filter((i) => levels.get(i.id)?.quantity || levels.get(i.id)?.value)
    .sort((a, b) => localName(a).localeCompare(localName(b)));
  const total = items.reduce((sum, i) => sum + toMinor(levels.get(i.id)?.value ?? 0, p), 0);
  const account = ledger
    ? stockAccounts(ledger.accounts, accountingSettings(company).template).inventory
    : undefined;
  const books =
    ledger && account
      ? ledger.lines
          .filter((l) => l.accountId === account.id && l.date <= asAt)
          .reduce((sum, l) => sum + l.amount, 0)
      : null;

  const exportCsv = () =>
    downloadCsv(
      `stock-valuation-${asAt}`,
      [t('SKU'), t('Item'), t('Quantity'), t('Average cost'), t('Value')],
      items.map((i) => {
        const level = levels.get(i.id);
        return [i.sku, localName(i), level?.quantity ?? 0, level?.unitCost ?? 0, level?.value ?? 0];
      }),
    );

  return (
    <div>
      <Toolbar onExport={exportCsv}>
        <DateInput label={t('As at')} value={asAt} onChange={setAsAt} required />
      </Toolbar>
      <Card className="overflow-hidden">
        <div className="border-b border-slate-100 px-4 py-3 text-sm text-slate-500">
          {t('Stock valued at weighted average cost (IAS 2), at the end of {date}.', {
            date: isolate(fmt.date(asAt)),
          })}
        </div>
        {items.length === 0 ? (
          <p className="px-6 py-12 text-center text-sm text-slate-500">
            {t('No stock on that date.')}
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="border-b border-slate-100">
                <tr>
                  <Th>{t('Item')}</Th>
                  <Th end>{t('Quantity')}</Th>
                  <Th end>{t('Average cost')}</Th>
                  <Th end>{t('Value')}</Th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {items.map((i) => {
                  const level = levels.get(i.id);
                  return (
                    <tr key={i.id}>
                      <Td>
                        <span className="font-medium text-slate-900">{localName(i)}</span>
                      </Td>
                      <Td end>
                        {fmt.quantity(level?.quantity ?? 0)}
                        {i.unit ? <span className="text-slate-500"> {i.unit}</span> : null}
                      </Td>
                      <Td end>{unitAmount(level?.unitCost ?? 0)}</Td>
                      <Td end strong>
                        {fmt.money(level?.value ?? 0)}
                      </Td>
                    </tr>
                  );
                })}
              </tbody>
              <tfoot className="border-t-2 border-slate-200 bg-slate-50/60">
                <tr>
                  <Td strong>{t('Total')}</Td>
                  <Td end>{''}</Td>
                  <Td end>{''}</Td>
                  <Td end strong>
                    {fmt.money(fromMinor(total, p))}
                  </Td>
                </tr>
              </tfoot>
            </table>
          </div>
        )}
      </Card>
      {books !== null && account ? (
        <Card className="mt-4">
          <div className="flex flex-col gap-2 px-4 py-3 text-sm sm:flex-row sm:items-center sm:justify-between">
            <span className="text-slate-600">
              {t('Balance of {account} in the books: {amount}', {
                account: `${account.code} ${localName(account)}`,
                amount: fmt.money(fromMinor(books, p)),
              })}
            </span>
            {books === total ? (
              <Badge tone="green">
                <CheckCircle2 className="me-1 inline size-3.5" />
                {t('Agrees with the books')}
              </Badge>
            ) : (
              <Badge tone="amber">
                <TriangleAlert className="me-1 inline size-3.5" />
                {t('Difference of {amount}', { amount: fmt.money(fromMinor(books - total, p)) })}
              </Badge>
            )}
          </div>
        </Card>
      ) : null}
    </div>
  );
}

function ItemMovements({ inventory }: { inventory: InventoryData }) {
  const fmt = useFormat();
  const unitAmount = useUnitAmount();
  const [params, setParams] = useSearchParams();
  const items = inventory.stockItems
    .slice()
    .sort((a, b) => localName(a).localeCompare(localName(b)));
  const itemId = params.get('item') ?? items[0]?.id ?? '';
  const [warehouseId, setWarehouseId] = useState('');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const item = items.find((i) => i.id === itemId);
  const p = inventory.precision;

  const rows = itemRows();
  function itemRows() {
    const all = inventory.movements
      .filter((m) => m.productId === itemId && (!warehouseId || m.warehouseId === warehouseId))
      .sort(compareMovements);
    let quantity = dec(0);
    let value = 0;
    let opening: { quantity: number; value: number } | null = null;
    const shown = [];
    for (const m of all) {
      if (to && m.date > to) break;
      if (from && m.date < from) {
        quantity = quantity.plus(dec(m.quantity));
        value += toMinor(m.value, p);
        continue;
      }
      if (from && !opening) opening = { quantity: quantity.toNumber(), value };
      quantity = quantity.plus(dec(m.quantity));
      value += toMinor(m.value, p);
      shown.push({ movement: m, quantity: quantity.toNumber(), value });
    }
    if (from && !opening) opening = { quantity: quantity.toNumber(), value };
    return { shown, opening, closing: { quantity: quantity.toNumber(), value } };
  }

  const warehouseName = (id: ID) => localName(inventory.warehouses.find((w) => w.id === id));
  const unit = item?.unit ? ` ${item.unit}` : '';

  const exportCsv = () =>
    downloadCsv(
      `stock-movements-${item?.sku || item?.name || itemId}`,
      [
        t('Date'),
        t('Type'),
        t('Number'),
        t('Warehouse'),
        t('In'),
        t('Out'),
        t('Unit cost'),
        t('Value'),
        t('Quantity after'),
        t('Value after'),
      ],
      rows.shown.map(({ movement: m, quantity, value }) => [
        m.date,
        t(MOVEMENT_LABELS[m.sourceType]),
        m.number,
        warehouseName(m.warehouseId),
        m.quantity > 0 ? m.quantity : '',
        m.quantity < 0 ? -m.quantity : '',
        m.unitCost,
        m.value,
        quantity,
        warehouseId ? '' : fromMinor(value, p),
      ]),
    );

  return (
    <div>
      <Toolbar onExport={item ? exportCsv : undefined}>
        <label className="block w-64">
          <span className="mb-1 block text-xs font-medium text-slate-500">{t('Item')}</span>
          <Combobox
            ariaLabel={t('Item')}
            value={itemId || null}
            onChange={(id) => setParams({ item: id }, { replace: true })}
            options={items.map((i) => ({
              value: i.id,
              label: localName(i),
              detail: i.sku,
              keywords: `${i.name} ${i.nameAr ?? ''} ${i.barcode ?? ''}`,
            }))}
            placeholder={t('Choose an item…')}
            searchPlaceholder={t('Search items…')}
          />
        </label>
        {inventory.warehouses.length > 1 ? (
          <label className="block w-48">
            <span className="mb-1 block text-xs font-medium text-slate-500">{t('Warehouse')}</span>
            <Select value={warehouseId} onChange={(e) => setWarehouseId(e.target.value)}>
              <option value="">{t('All warehouses')}</option>
              {inventory.warehouses.map((w) => (
                <option key={w.id} value={w.id}>
                  {localName(w)}
                </option>
              ))}
            </Select>
          </label>
        ) : null}
        <DateInput label={t('From')} value={from} onChange={setFrom} />
        <DateInput label={t('To')} value={to} onChange={setTo} />
      </Toolbar>
      <Card className="overflow-hidden">
        <div className="border-b border-slate-100 px-4 py-3 text-sm text-slate-500">
          {warehouseId
            ? t('Every movement of {item} in {warehouse}.', {
                item: itemName(item),
                warehouse: warehouseName(warehouseId),
              })
            : t('Every movement of {item}, with the quantity and value after each one.', {
                item: itemName(item),
              })}
        </div>
        {rows.shown.length === 0 && !rows.opening ? (
          <p className="px-6 py-12 text-center text-sm text-slate-500">
            {t('No movements in this period.')}
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="border-b border-slate-100">
                <tr>
                  <Th>{t('Date')}</Th>
                  <Th>{t('Type')}</Th>
                  {inventory.warehouses.length > 1 && !warehouseId ? (
                    <Th>{t('Warehouse')}</Th>
                  ) : null}
                  <Th end>{t('In')}</Th>
                  <Th end>{t('Out')}</Th>
                  <Th end>{t('Unit cost')}</Th>
                  <Th end>{t('Value')}</Th>
                  <Th end>{t('On hand')}</Th>
                  {warehouseId ? null : <Th end>{t('Stock value')}</Th>}
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {rows.opening ? (
                  <tr className="bg-slate-50/60">
                    <Td>{fmt.date(from)}</Td>
                    <Td strong>{t('Balance before')}</Td>
                    {inventory.warehouses.length > 1 && !warehouseId ? <Td>{''}</Td> : null}
                    <Td end>{''}</Td>
                    <Td end>{''}</Td>
                    <Td end>{''}</Td>
                    <Td end>{''}</Td>
                    <Td end strong>
                      {fmt.quantity(rows.opening.quantity)}
                      {unit}
                    </Td>
                    {warehouseId ? null : (
                      <Td end strong>
                        {fmt.money(fromMinor(rows.opening.value, p))}
                      </Td>
                    )}
                  </tr>
                ) : null}
                {rows.shown.map(({ movement: m, quantity, value }) => (
                  <tr key={m.id}>
                    <Td>{fmt.date(m.date)}</Td>
                    <Td>
                      <Link
                        to={movementLink(m)}
                        className="hover:text-primary-700 font-medium text-slate-900"
                      >
                        {t(MOVEMENT_LABELS[m.sourceType])}{' '}
                        <span className="tabular">{m.number}</span>
                      </Link>
                    </Td>
                    {inventory.warehouses.length > 1 && !warehouseId ? (
                      <Td>{warehouseName(m.warehouseId)}</Td>
                    ) : null}
                    <Td end>{m.quantity > 0 ? fmt.quantity(m.quantity) : ''}</Td>
                    <Td end>{m.quantity < 0 ? fmt.quantity(-m.quantity) : ''}</Td>
                    <Td end>{unitAmount(m.unitCost)}</Td>
                    <Td end>
                      <span className={m.value < 0 ? 'text-red-600' : ''}>
                        {fmt.money(m.value)}
                      </span>
                    </Td>
                    <Td end strong>
                      {fmt.quantity(quantity)}
                    </Td>
                    {warehouseId ? null : <Td end>{fmt.money(fromMinor(value, p))}</Td>}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </div>
  );
}

function LowStock({ inventory }: { inventory: InventoryData }) {
  const fmt = useFormat();
  const company = useCompany();
  const vendors = useLiveQuery(
    () => db.clients.where('companyId').equals(company.id).toArray(),
    [company.id],
  );
  const low = inventory.stockItems
    .filter((i) => !i.archived && isLowStock(i, inventory.levels.get(i.id)))
    .sort((a, b) => localName(a).localeCompare(localName(b)));
  const tracked = inventory.stockItems.filter(
    (i) => !i.archived && i.reorderLevel !== null && i.reorderLevel !== undefined,
  );
  const suggested = (i: Product) =>
    Math.max(
      0,
      round(
        dec(i.reorderLevel ?? 0)
          .times(2)
          .minus(dec(inventory.levels.get(i.id)?.quantity ?? 0)),
        6,
      ),
    );
  const groups = new Map<string, Product[]>();
  for (const i of low) {
    const key = i.preferredVendorId ?? '';
    groups.set(key, [...(groups.get(key) ?? []), i]);
  }
  const vendorName = (id: string) =>
    id
      ? localName(vendors?.find((v) => v.id === id)) || t('Unknown vendor')
      : t('No preferred vendor');
  const orderLink = (vendorId: string, list: Product[]) => {
    const query = new URLSearchParams();
    if (vendorId) query.set('vendor', vendorId);
    query.set('items', list.map((i) => `${i.id}:${suggested(i)}`).join(','));
    return `/purchase-orders/new?${query.toString()}`;
  };

  const exportCsv = () =>
    downloadCsv(
      `low-stock-${today()}`,
      [t('SKU'), t('Item'), t('On hand'), t('Reorder level'), t('Suggested order'), t('Vendor')],
      low.map((i) => [
        i.sku,
        localName(i),
        inventory.levels.get(i.id)?.quantity ?? 0,
        i.reorderLevel ?? '',
        suggested(i),
        i.preferredVendorId ? vendorName(i.preferredVendorId) : '',
      ]),
    );

  if (!vendors) return <Spinner className="py-24" label={t('Loading…')} />;

  return (
    <div>
      <Toolbar onExport={low.length ? exportCsv : undefined} />
      <Card className="overflow-hidden">
        <div className="border-b border-slate-100 px-4 py-3 text-sm text-slate-500">
          {t(
            'Stock items at or below their reorder level. The suggested order brings them to twice the reorder level.',
          )}
        </div>
        {low.length === 0 ? (
          <p className="px-6 py-12 text-center text-sm text-slate-500">
            {tracked.length
              ? t('Nothing is at or below its reorder level.')
              : t('Set a reorder level on your stock items to see what to reorder.')}
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="border-b border-slate-100">
                <tr>
                  <Th>{t('Item')}</Th>
                  <Th end>{t('On hand')}</Th>
                  <Th end>{t('Reorder level')}</Th>
                  <Th end>{t('Suggested order')}</Th>
                </tr>
              </thead>
              {[...groups].map(([vendorId, list]) => (
                <tbody
                  key={vendorId}
                  className="divide-y divide-slate-100 border-b border-slate-100"
                >
                  <tr className="bg-slate-50/60">
                    <td colSpan={4} className="px-4 py-2">
                      <div className="flex flex-wrap items-center justify-between gap-2">
                        <span className="font-semibold text-slate-900">{vendorName(vendorId)}</span>
                        <ButtonLink to={orderLink(vendorId, list)} variant="outline" size="sm">
                          <ShoppingCart /> {t('Create purchase order')}
                        </ButtonLink>
                      </div>
                    </td>
                  </tr>
                  {list.map((i) => {
                    const onHand = inventory.levels.get(i.id)?.quantity ?? 0;
                    return (
                      <tr key={i.id}>
                        <Td>
                          <Link
                            to={`/reports/stock-movements?item=${i.id}`}
                            className="hover:text-primary-700 font-medium text-slate-900"
                          >
                            {localName(i)}
                          </Link>
                          {i.sku ? (
                            <span className="ms-2 text-xs text-slate-500">{i.sku}</span>
                          ) : null}
                        </Td>
                        <Td end>
                          <span className={onHand <= 0 ? 'font-medium text-red-600' : ''}>
                            {fmt.quantity(onHand)}
                          </span>
                        </Td>
                        <Td end>{fmt.quantity(i.reorderLevel ?? 0)}</Td>
                        <Td end strong>
                          {fmt.quantity(suggested(i))}
                          {i.unit ? (
                            <span className="font-normal text-slate-500"> {i.unit}</span>
                          ) : null}
                        </Td>
                      </tr>
                    );
                  })}
                </tbody>
              ))}
            </table>
          </div>
        )}
      </Card>
    </div>
  );
}
