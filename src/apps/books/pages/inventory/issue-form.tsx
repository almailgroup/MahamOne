import { useMemo, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router';
import { useLiveQuery } from 'dexie-react-hooks';
import { Plus, Send, Shirt, Trash2 } from 'lucide-react';
import { toast } from 'sonner';
import { issueStock, stockKey, waitingIssueRequests, waitingQuantities } from '@/db/stock-issues';
import type { ID } from '@/db/types';
import { useCompany, useFormat } from '@/app/company';
import { useCloud } from '@/cloud/store';
import { useCloudLink } from '@/cloud/hooks';
import { stockLevels } from '@/lib/inventory/costing';
import { today } from '@/lib/dates';
import { dec } from '@/lib/money';
import { shortId } from '@/lib/ids';
import { cn } from '@/lib/cn';
import { t } from '@/i18n';
import { localName } from '@/i18n/names';
import { Button } from '@/components/ui/button';
import { Card, CardBody, CardHeader, EmptyState, PageHeader, Spinner } from '@/components/ui/misc';
import { Field, NumberInput, Select, Textarea } from '@/components/ui/form';
import { Combobox } from '@/components/ui/combobox';
import { DateField } from '@/components/ui/date-field';
import { useInventory } from '@/apps/books/features/inventory/use-inventory';
import {
  recipientLabel,
  useIssueRecipients,
  useWarehouseAccess,
  warehousePath,
} from '@/features/inventory/issues';

interface Row {
  key: string;
  productId: ID;
  quantity: number;
}

/**
 * Issues items (uniforms, shoes, badges) from a warehouse to an employee.
 * Whoever looks after a sub-warehouse sends them for approval; an approver
 * issues them at once. The stock leaves the warehouse once confirmed.
 */
export default function StockIssueForm() {
  const company = useCompany();
  const fmt = useFormat();
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const inventory = useInventory();
  const access = useWarehouseAccess();
  const link = useCloudLink(company.id);
  const { user } = useCloud();
  const { recipients, error: recipientsError } = useIssueRecipients();
  const waiting = useLiveQuery(
    async () => waitingQuantities(await waitingIssueRequests(company.id)),
    [company.id],
  );
  const [warehouseId, setWarehouseId] = useState(params.get('warehouse') ?? '');
  const [date, setDate] = useState(today());
  const [employeeId, setEmployeeId] = useState(params.get('employee') ?? '');
  const [notes, setNotes] = useState('');
  const [rows, setRows] = useState<Row[]>(() => [{ key: shortId(), productId: '', quantity: 1 }]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const levels = useMemo(
    () => (inventory ? stockLevels(inventory.movements, inventory.precision) : null),
    [inventory],
  );

  if (!inventory || !levels || !access || !waiting) {
    return <Spinner className="py-24" label={t('Loading…')} />;
  }

  // Warehouses the person may issue from; a sub-warehouse they look after first.
  const sources = inventory.warehouses
    .filter((w) => access.issuesFrom(w))
    .sort((a, b) => Number(Boolean(b.parentId)) - Number(Boolean(a.parentId)));
  const from = sources.some((w) => w.id === warehouseId) ? warehouseId : (sources[0]?.id ?? '');
  const warehouse = inventory.warehouses.find((w) => w.id === from);
  const left = (productId: ID) =>
    dec(levels.get(productId)?.byWarehouse.get(from) ?? 0)
      .minus(waiting.get(stockKey(from, productId)) ?? 0)
      .toNumber();
  const items = inventory.stockItems.filter((i) => !i.archived);
  const itemOptions = items
    .map((i) => ({
      value: i.id,
      label: localName(i),
      detail: t('{quantity} left', { quantity: fmt.quantity(Math.max(0, left(i.id))) }),
      keywords: `${i.name} ${i.nameAr ?? ''} ${i.sku} ${i.barcode ?? ''}`,
    }))
    .sort((a, b) => a.label.localeCompare(b.label));
  const product = (id: ID) => inventory.stockItems.find((i) => i.id === id);
  const people = (recipients ?? []).map((r) => ({
    value: r.employeeId,
    label: recipientLabel(r),
    detail: r.number,
    keywords: `${r.name} ${r.nameAr ?? ''} ${r.jobTitle} ${r.number}`,
  }));
  const update = (key: string, patch: Partial<Row>) =>
    setRows((list) => list.map((r) => (r.key === key ? { ...r, ...patch } : r)));
  // Lines of the same item count together.
  const asked = (productId: ID) =>
    rows
      .filter((r) => r.productId === productId)
      .reduce((sum, r) => sum.plus(r.quantity || 0), dec(0))
      .toNumber();

  // Who the issue names as having issued it: whoever looks after the
  // sub-warehouse, with their job title, when it is them.
  const keeper = warehouse?.keeper;
  const mine = keeper && (!link || keeper.userId === link.userId) && keeper.name;
  const issuerName = mine
    ? `${keeper.name}${keeper.jobTitle ? ` (${keeper.jobTitle})` : ''}`
    : user?.fullName || user?.email || '';

  const save = async () => {
    const recipient = recipients?.find((r) => r.employeeId === employeeId);
    if (!recipient) {
      setError(t('Choose the employee who receives the items.'));
      return;
    }
    const lines = rows.filter((r) => r.productId && r.quantity > 0);
    if (lines.length === 0) {
      setError(t('Add at least one item with a quantity.'));
      return;
    }
    setSaving(true);
    try {
      const { issue, request } = await issueStock(
        company.id,
        {
          date,
          warehouseId: from,
          recipient,
          lines: lines.map((r) => ({ productId: r.productId, quantity: r.quantity })),
          notes,
        },
        { userId: link?.userId ?? null, name: issuerName },
      );
      toast.success(
        issue
          ? t('{number} issued', { number: issue.number })
          : t('Sent for approval. The stock leaves the warehouse once it is confirmed.'),
      );
      navigate(`/inventory/issues/${issue?.id ?? request!.subjectId}`, { replace: true });
    } catch (e) {
      toast.error(e instanceof Error ? e.message : t('Could not save.'));
      setSaving(false);
    }
  };

  const header = (
    <PageHeader
      breadcrumb={
        <Link to="/inventory/issues" className="hover:text-slate-700">
          {t('Issued items')}
        </Link>
      }
      title={t('Issue items')}
      description={
        access.approver
          ? t(
              'Hand uniforms and other items to an employee. The stock leaves the warehouse at once.',
            )
          : t(
              'Hand uniforms and other items to an employee. An approver confirms it, then the stock leaves your warehouse.',
            )
      }
    />
  );

  if (!access.offered || sources.length === 0) {
    return (
      <div className="mx-auto max-w-4xl">
        {header}
        <Card>
          <EmptyState
            icon={<Shirt />}
            title={t('There is no warehouse you can issue items from')}
            description={
              access.offered
                ? t(
                    'The owner, an admin or an accountant sets up sub-warehouses and who issues items from them.',
                  )
                : t('Issuing items needs the latest database update. Ask the owner to run it.')
            }
          />
        </Card>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-4xl">
      {header}
      <div className="space-y-6">
        <Card>
          <CardBody className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <Field label={t('From warehouse')}>
              {(id) => (
                <Select id={id} value={from} onChange={(e) => setWarehouseId(e.target.value)}>
                  {sources.map((w) => (
                    <option key={w.id} value={w.id}>
                      {warehousePath(w, inventory.warehouses)}
                    </option>
                  ))}
                </Select>
              )}
            </Field>
            <Field label={t('Date')}>
              {(id) => <DateField id={id} value={date} onChange={(iso) => iso && setDate(iso)} />}
            </Field>
            <Field
              label={t('Issued to')}
              error={recipientsError || (error && !employeeId ? error : '')}
              className="sm:col-span-2 lg:col-span-1"
            >
              {(id) => (
                <Combobox
                  id={id}
                  value={employeeId || null}
                  onChange={(value) => {
                    setEmployeeId(value);
                    setError('');
                  }}
                  options={people}
                  placeholder={recipients ? t('Choose an employee…') : t('Loading…')}
                  searchPlaceholder={t('Search employees…')}
                  emptyText={t('No matches')}
                  disabled={!recipients}
                />
              )}
            </Field>
          </CardBody>
        </Card>

        <Card>
          <CardHeader
            title={t('Items')}
            description={
              error && employeeId ? <span className="text-red-600">{error}</span> : undefined
            }
          />
          <ol className="divide-y divide-slate-100">
            {rows.map((row, index) => {
              const item = product(row.productId);
              const here = row.productId ? left(row.productId) : 0;
              const short = Boolean(row.productId) && asked(row.productId) > here;
              return (
                <li key={row.key} className="grid grid-cols-12 gap-3 px-4 py-3 sm:px-5">
                  <div className="col-span-12 md:col-span-7">
                    <span className="mb-1 block text-xs font-medium text-slate-500">
                      {t('Item')}
                    </span>
                    <Combobox
                      ariaLabel={t('Item {number}', { number: index + 1 })}
                      value={row.productId || null}
                      onChange={(productId) => update(row.key, { productId })}
                      options={itemOptions}
                      placeholder={t('Choose an item…')}
                      searchPlaceholder={t('Search items…')}
                    />
                    {item ? (
                      <p className="mt-1 text-xs text-slate-500">
                        {t('{quantity} left in {warehouse}', {
                          quantity: `${fmt.quantity(Math.max(0, here))}${item.unit ? ` ${item.unit}` : ''}`,
                          warehouse: warehouse ? localName(warehouse) : '',
                        })}
                      </p>
                    ) : null}
                  </div>
                  <div className="col-span-9 md:col-span-4">
                    <span className="mb-1 block text-xs font-medium text-slate-500">
                      {t('Quantity')}
                    </span>
                    <NumberInput
                      aria-label={t('Item {number} quantity', { number: index + 1 })}
                      value={row.quantity}
                      onValueChange={(quantity) => update(row.key, { quantity })}
                      className={cn(short && 'border-amber-400')}
                    />
                    {short ? (
                      <p className="mt-1 text-xs text-amber-700" role="alert">
                        {t('Only {quantity} left to issue.', {
                          quantity: fmt.quantity(Math.max(0, here)),
                        })}
                      </p>
                    ) : null}
                  </div>
                  <div className="col-span-3 flex items-end justify-end md:col-span-1">
                    <Button
                      variant="ghost"
                      size="icon"
                      aria-label={t('Remove item {number}', { number: index + 1 })}
                      disabled={rows.length === 1}
                      onClick={() => setRows((list) => list.filter((r) => r.key !== row.key))}
                    >
                      <Trash2 />
                    </Button>
                  </div>
                </li>
              );
            })}
          </ol>
          <div className="border-t border-slate-100 px-4 py-3 sm:px-5">
            <Button
              variant="outline"
              size="sm"
              onClick={() =>
                setRows((list) => [...list, { key: shortId(), productId: '', quantity: 1 }])
              }
            >
              <Plus /> {t('Add an item')}
            </Button>
          </div>
        </Card>

        <Card>
          <CardBody>
            <Field label={t('Notes')} optional>
              {(id) => (
                <Textarea
                  id={id}
                  rows={2}
                  value={notes}
                  onChange={(e) => setNotes(e.target.value)}
                  placeholder={t('e.g. New joiner, replacement for a torn jacket')}
                />
              )}
            </Field>
          </CardBody>
        </Card>

        <div className="flex justify-end gap-2">
          <Button variant="outline" onClick={() => navigate(-1)}>
            {t('Cancel')}
          </Button>
          <Button onClick={() => void save()} loading={saving}>
            {access.approver ? (
              <>
                <Shirt /> {t('Issue items')}
              </>
            ) : (
              <>
                <Send /> {t('Send for approval')}
              </>
            )}
          </Button>
        </div>
      </div>
    </div>
  );
}
