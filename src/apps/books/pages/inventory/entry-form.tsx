import { useMemo, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router';
import { Plus, Trash2 } from 'lucide-react';
import { toast } from 'sonner';
import { recordStockEntry } from '@/db/inventory';
import type { AdjustmentReason, ID, StockEntryKind } from '@/db/types';
import { useCompany, useFormat } from '@/app/company';
import { stockLevels } from '@/lib/inventory/costing';
import { dec, fromMinor, toMinor } from '@/lib/money';
import { today } from '@/lib/dates';
import { shortId } from '@/lib/ids';
import { cn } from '@/lib/cn';
import { msg, t } from '@/i18n';
import { localName } from '@/i18n/names';
import { Button } from '@/components/ui/button';
import { Card, CardBody, CardHeader, PageHeader, Segmented, Spinner } from '@/components/ui/misc';
import { Field, Input, NumberInput, Select } from '@/components/ui/form';
import { Combobox } from '@/components/ui/combobox';
import {
  ADJUSTMENT_REASONS,
  ENTRY_LABELS,
  REASON_LABELS,
} from '@/apps/books/features/inventory/labels';
import { useInventory } from '@/apps/books/features/inventory/use-inventory';
import { useWarehouseAccess } from '@/features/inventory/issues';
import { DateField } from '@/components/ui/date-field';

interface Row {
  key: string;
  productId: ID;
  /** Adjustments: the change (+/−). Opening stock and transfers: the quantity. */
  quantity: number;
  unitCost: number;
}

const KINDS: StockEntryKind[] = ['adjustment', 'transfer', 'opening'];

const TITLES: Record<StockEntryKind, string> = {
  adjustment: msg('Adjust stock'),
  transfer: msg('Transfer stock'),
  opening: msg('Record opening stock'),
};

const SAVE_LABELS: Record<StockEntryKind, string> = {
  adjustment: msg('Post adjustment'),
  transfer: msg('Post transfer'),
  opening: msg('Record opening stock'),
};

/** Opening stock, an adjustment (with a reason) or a transfer between warehouses. */
export default function StockEntryForm() {
  const company = useCompany();
  const fmt = useFormat();
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const inventory = useInventory();
  const initialKind = params.get('kind');
  const [kind, setKind] = useState<StockEntryKind>(
    KINDS.includes(initialKind as StockEntryKind) ? (initialKind as StockEntryKind) : 'adjustment',
  );
  const [date, setDate] = useState(today());
  // Send stock: a transfer from the main warehouse to a sub-warehouse.
  const [warehouseId, setWarehouseId] = useState(params.get('from') ?? '');
  const [toWarehouseId, setToWarehouseId] = useState(params.get('to') ?? '');
  const access = useWarehouseAccess();
  const [reason, setReason] = useState<AdjustmentReason>('damaged');
  const [reference, setReference] = useState('');
  const [notes, setNotes] = useState('');
  const [rows, setRows] = useState<Row[]>(() => [
    { key: shortId(), productId: params.get('item') ?? '', quantity: 0, unitCost: 0 },
  ]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const levels = useMemo(
    () => (inventory ? stockLevels(inventory.movements, inventory.precision, date) : null),
    [inventory, date],
  );

  if (!inventory || !levels || !access) return <Spinner className="py-24" label={t('Loading…')} />;

  const p = inventory.precision;
  // A sub-warehouse's stock is changed directly by the owner, an admin or
  // an accountant only (the cloud refuses anyone else).
  const active = inventory.warehouses.filter(
    (w) => !w.archived && (access.manages || !access.offered || !w.parentId),
  );
  const from = active.some((w) => w.id === warehouseId)
    ? warehouseId
    : inventory.defaultWarehouse?.id || active[0]?.id || '';
  const to = active.some((w) => w.id === toWarehouseId && w.id !== from)
    ? toWarehouseId
    : active.find((w) => w.id !== from)?.id || '';
  const items = inventory.stockItems.filter((i) => !i.archived);
  const itemOptions = items
    .map((i) => ({
      value: i.id,
      label: localName(i),
      detail: [i.sku, i.unit].filter(Boolean).join(' · '),
      keywords: `${i.name} ${i.nameAr ?? ''} ${i.barcode ?? ''}`,
    }))
    .sort((a, b) => a.label.localeCompare(b.label));
  const product = (id: ID) => inventory.stockItems.find((i) => i.id === id);
  const available = (id: ID, warehouse: ID) => levels.get(id)?.byWarehouse.get(warehouse) ?? 0;
  const average = (id: ID) => {
    const level = levels.get(id);
    return level && level.quantity > 0 ? level.unitCost : (product(id)?.costPrice ?? 0);
  };
  const update = (key: string, patch: Partial<Row>) =>
    setRows((list) => list.map((r) => (r.key === key ? { ...r, ...patch } : r)));
  const pick = (key: string, productId: ID) =>
    update(key, { productId, unitCost: product(productId)?.costPrice ?? 0 });

  const value = rows.reduce((sum, r) => {
    if (!r.productId || !r.quantity) return sum;
    const unit = kind === 'opening' ? r.unitCost : average(r.productId);
    return sum + toMinor(dec(r.quantity).times(dec(unit)), p);
  }, 0);

  const save = async () => {
    const lines = rows.filter((r) => r.productId && r.quantity !== 0);
    if (lines.length === 0) {
      setError(t('Add at least one item with a quantity.'));
      return;
    }
    setSaving(true);
    try {
      const entry = await recordStockEntry(company.id, {
        kind,
        date,
        warehouseId: from,
        toWarehouseId: kind === 'transfer' ? to : null,
        reason: kind === 'adjustment' ? reason : null,
        reference,
        notes,
        lines: lines.map((r) => ({
          productId: r.productId,
          quantity: r.quantity,
          unitCost: kind === 'opening' ? r.unitCost : null,
        })),
      });
      toast.success(t('{number} saved', { number: entry.number }));
      navigate(`/inventory/entries/${entry.id}`, { replace: true });
    } catch (e) {
      toast.error(e instanceof Error ? e.message : t('Could not save.'));
      setSaving(false);
    }
  };

  const quantityLabel =
    kind === 'adjustment'
      ? t('Quantity change')
      : kind === 'transfer'
        ? t('Quantity to move')
        : t('Quantity');

  return (
    <div className="mx-auto max-w-4xl">
      <PageHeader
        breadcrumb={
          <Link to="/inventory?tab=history" className="hover:text-slate-700">
            {t('Inventory')}
          </Link>
        }
        title={t(TITLES[kind])}
        description={
          kind === 'adjustment'
            ? t('Write off damaged or expired goods, or correct the quantity after a count.')
            : kind === 'transfer'
              ? t('Move stock from one warehouse to another. Its value stays the same.')
              : t('Stock you had before you started using Maham Books, valued at its cost.')
        }
      />

      <div className="space-y-6">
        <Card>
          <CardBody className="space-y-4">
            <Select
              aria-label={t('Type')}
              value={kind}
              onChange={(e) => setKind(e.target.value as StockEntryKind)}
              className="sm:hidden"
            >
              {KINDS.map((k) => (
                <option key={k} value={k}>
                  {t(ENTRY_LABELS[k])}
                </option>
              ))}
            </Select>
            <div className="hidden sm:block">
              <Segmented
                value={kind}
                onChange={setKind}
                options={KINDS.map((k) => ({ value: k, label: t(ENTRY_LABELS[k]) }))}
              />
            </div>
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <Field label={t('Date')}>
                {(id) => <DateField id={id} value={date} onChange={(iso) => iso && setDate(iso)} />}
              </Field>
              <Field label={kind === 'transfer' ? t('From warehouse') : t('Warehouse')}>
                {(id) => (
                  <Select id={id} value={from} onChange={(e) => setWarehouseId(e.target.value)}>
                    {active.map((w) => (
                      <option key={w.id} value={w.id}>
                        {localName(w)}
                      </option>
                    ))}
                  </Select>
                )}
              </Field>
              {kind === 'transfer' ? (
                <Field label={t('To warehouse')}>
                  {(id) => (
                    <Select id={id} value={to} onChange={(e) => setToWarehouseId(e.target.value)}>
                      {active
                        .filter((w) => w.id !== from)
                        .map((w) => (
                          <option key={w.id} value={w.id}>
                            {localName(w)}
                          </option>
                        ))}
                    </Select>
                  )}
                </Field>
              ) : null}
              {kind === 'adjustment' ? (
                <Field label={t('Reason')}>
                  {(id) => (
                    <Select
                      id={id}
                      value={reason}
                      onChange={(e) => setReason(e.target.value as AdjustmentReason)}
                    >
                      {ADJUSTMENT_REASONS.map((r) => (
                        <option key={r} value={r}>
                          {t(REASON_LABELS[r])}
                        </option>
                      ))}
                    </Select>
                  )}
                </Field>
              ) : null}
              <Field label={t('Reference')} optional>
                {(id) => (
                  <Input id={id} value={reference} onChange={(e) => setReference(e.target.value)} />
                )}
              </Field>
            </div>
            {kind === 'transfer' && active.length < 2 ? (
              <p className="rounded-md bg-amber-50 px-3 py-2 text-sm text-amber-800">
                {t('Add a second warehouse to move stock between them.')}{' '}
                <Link to="/inventory?tab=warehouses" className="font-medium underline">
                  {t('Warehouses')}
                </Link>
              </p>
            ) : null}
          </CardBody>
        </Card>

        <Card>
          <CardHeader
            title={t('Stock items')}
            description={
              error ? (
                <span className="text-red-600">{error}</span>
              ) : kind === 'adjustment' ? (
                t('Enter the change, or the quantity there should be.')
              ) : undefined
            }
          />
          {items.length === 0 ? (
            <p className="px-5 py-8 text-center text-sm text-slate-500">
              {t('No stock items yet.')}{' '}
              <Link to="/products?new=1&kind=stock" className="text-primary-700 font-medium">
                {t('New stock item')}
              </Link>
            </p>
          ) : (
            <ol className="divide-y divide-slate-100">
              {rows.map((row, index) => {
                const item = product(row.productId);
                const here = row.productId ? available(row.productId, from) : 0;
                const short = kind === 'transfer' && row.quantity > here;
                return (
                  <li key={row.key} className="grid grid-cols-12 gap-3 px-4 py-3 sm:px-5">
                    <div className="col-span-12 md:col-span-5">
                      <span className="mb-1 block text-xs font-medium text-slate-500">
                        {t('Item')}
                      </span>
                      <Combobox
                        ariaLabel={t('Item {number}', { number: index + 1 })}
                        value={row.productId || null}
                        onChange={(id) => pick(row.key, id)}
                        options={itemOptions}
                        placeholder={t('Choose an item…')}
                        searchPlaceholder={t('Search items…')}
                      />
                      {item ? (
                        <p className="mt-1 text-xs text-slate-500">
                          {t('{quantity} on hand', {
                            quantity: `${fmt.quantity(here)}${item.unit ? ` ${item.unit}` : ''}`,
                          })}
                        </p>
                      ) : null}
                    </div>
                    <div className="col-span-6 md:col-span-3">
                      <span className="mb-1 block text-xs font-medium text-slate-500">
                        {quantityLabel}
                      </span>
                      <NumberInput
                        aria-label={t('Item {number} quantity', { number: index + 1 })}
                        value={row.quantity}
                        allowNegative={kind === 'adjustment'}
                        onValueChange={(quantity) => update(row.key, { quantity })}
                        className={cn(short && 'border-amber-400')}
                      />
                      {short ? (
                        <p className="mt-1 text-xs text-amber-700">
                          {t('Only {quantity} in this warehouse.', {
                            quantity: fmt.quantity(here),
                          })}
                        </p>
                      ) : null}
                    </div>
                    {kind === 'adjustment' ? (
                      <div className="col-span-5 md:col-span-3">
                        <span className="mb-1 block text-xs font-medium text-slate-500">
                          {t('New quantity')}
                        </span>
                        <NumberInput
                          aria-label={t('Item {number} new quantity', { number: index + 1 })}
                          value={dec(here).plus(dec(row.quantity)).toNumber()}
                          onValueChange={(counted) =>
                            update(row.key, { quantity: dec(counted).minus(dec(here)).toNumber() })
                          }
                          disabled={!row.productId}
                        />
                      </div>
                    ) : kind === 'opening' ? (
                      <div className="col-span-5 md:col-span-3">
                        <span className="mb-1 block text-xs font-medium text-slate-500">
                          {t('Unit cost')}
                        </span>
                        <NumberInput
                          aria-label={t('Item {number} unit cost', { number: index + 1 })}
                          value={row.unitCost}
                          allowNegative={false}
                          onValueChange={(unitCost) => update(row.key, { unitCost })}
                        />
                      </div>
                    ) : (
                      <div className="col-span-5 md:col-span-3" />
                    )}
                    <div className="col-span-1 flex items-end justify-end pb-0.5">
                      <Button
                        variant="ghost"
                        size="icon-sm"
                        aria-label={t('Remove item {number}', { number: index + 1 })}
                        disabled={rows.length <= 1}
                        onClick={() => setRows((list) => list.filter((r) => r.key !== row.key))}
                      >
                        <Trash2 />
                      </Button>
                    </div>
                  </li>
                );
              })}
            </ol>
          )}
          <div className="flex flex-col gap-3 border-t border-slate-100 px-4 py-3 sm:flex-row sm:items-center sm:justify-between sm:px-5">
            <Button
              variant="outline"
              size="sm"
              onClick={() =>
                setRows((list) => [
                  ...list,
                  { key: shortId(), productId: '', quantity: 0, unitCost: 0 },
                ])
              }
            >
              <Plus /> {t('Add stock item')}
            </Button>
            {kind !== 'transfer' ? (
              <p className="text-sm text-slate-600">
                {kind === 'opening'
                  ? t('Value of the opening stock: {amount}', {
                      amount: fmt.money(fromMinor(value, p)),
                    })
                  : t('Value of the change, at average cost: {amount}', {
                      amount: fmt.money(fromMinor(value, p)),
                    })}
              </p>
            ) : null}
          </div>
        </Card>

        <Card>
          <CardBody>
            <Field label={t('Notes')} optional>
              {(id) => <Input id={id} value={notes} onChange={(e) => setNotes(e.target.value)} />}
            </Field>
          </CardBody>
        </Card>

        <div className="flex flex-wrap justify-end gap-2">
          <Button variant="ghost" onClick={() => navigate(-1)}>
            {t('Cancel')}
          </Button>
          <Button
            onClick={save}
            loading={saving}
            disabled={kind === 'transfer' && active.length < 2}
          >
            {t(SAVE_LABELS[kind])}
          </Button>
        </div>
      </div>
    </div>
  );
}
