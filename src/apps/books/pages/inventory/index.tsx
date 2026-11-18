import { useMemo, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router';
import { useLiveQuery } from 'dexie-react-hooks';
import {
  ArrowLeftRight,
  Boxes,
  ClipboardList,
  MoreHorizontal,
  PackagePlus,
  Pencil,
  Plus,
  RefreshCw,
  Search,
  ShipWheel,
  SlidersHorizontal,
  Star,
  Archive,
  ArchiveRestore,
  CornerDownRight,
  Send,
  Shirt,
  Warehouse as WarehouseIcon,
} from 'lucide-react';
import { toast } from 'sonner';
import { db } from '@/db/db';
import { createWarehouse, rebuildStock, saveWarehouse } from '@/db/inventory';
import type { Warehouse } from '@/db/types';
import { useCompany, useFormat } from '@/app/company';
import { fromMinor, toMinor, dec, round } from '@/lib/money';
import { t, tp } from '@/i18n';
import { localName } from '@/i18n/names';
import { Button, ButtonLink } from '@/components/ui/button';
import {
  Badge,
  Card,
  EmptyState,
  PageHeader,
  Segmented,
  Spinner,
  Stat,
} from '@/components/ui/misc';
import { Input, Select } from '@/components/ui/form';
import {
  DropdownContent,
  DropdownItem,
  DropdownMenu,
  DropdownSeparator,
  DropdownTrigger,
} from '@/components/ui/overlay';
import { ENTRY_LABELS, REASON_LABELS } from '@/apps/books/features/inventory/labels';
import {
  isLowStock,
  onHand,
  useInventory,
  useUnitAmount,
} from '@/apps/books/features/inventory/use-inventory';
import { WarehouseDialog } from '@/apps/books/features/inventory/warehouse-dialog';
import { useWarehouseAccess, warehousePath } from '@/features/inventory/issues';

type Tab = 'stock' | 'history' | 'warehouses' | 'landed-costs';
const TABS: Tab[] = ['stock', 'history', 'warehouses', 'landed-costs'];

export default function InventoryPage() {
  const company = useCompany();
  const fmt = useFormat();
  const unitAmount = useUnitAmount();
  const navigate = useNavigate();
  const [params, setParams] = useSearchParams();
  const tab: Tab = TABS.includes(params.get('tab') as Tab) ? (params.get('tab') as Tab) : 'stock';
  const [warehouseId, setWarehouseId] = useState('');
  const [query, setQuery] = useState('');
  const [editing, setEditing] = useState<Warehouse | null>(null);
  const [rebuilding, setRebuilding] = useState(false);
  const inventory = useInventory();
  const access = useWarehouseAccess();
  const records = useLiveQuery(async () => {
    const [entries, landedCosts, bills] = await Promise.all([
      db.stockEntries.where('companyId').equals(company.id).toArray(),
      db.landedCosts.where('companyId').equals(company.id).toArray(),
      db.documents.where('[companyId+type]').equals([company.id, 'bill']).toArray(),
    ]);
    return {
      entries: entries.sort(
        (a, b) => b.date.localeCompare(a.date) || b.number.localeCompare(a.number),
      ),
      landedCosts: landedCosts.sort((a, b) => b.number.localeCompare(a.number)),
      bills: new Map(bills.map((d) => [d.id, d])),
    };
  }, [company.id]);

  const items = useMemo(() => {
    if (!inventory) return [];
    const q = query.trim().toLowerCase();
    return inventory.stockItems
      .filter((p) => !p.archived || (inventory.levels.get(p.id)?.quantity ?? 0) !== 0)
      .filter(
        (p) =>
          !q || `${p.name} ${p.nameAr ?? ''} ${p.sku} ${p.barcode ?? ''}`.toLowerCase().includes(q),
      )
      .sort((a, b) => localName(a).localeCompare(localName(b)));
  }, [inventory, query]);

  if (!inventory || !records || !access) {
    return <Spinner className="py-24" label={t('Loading…')} />;
  }

  const p = inventory.precision;
  const activeWarehouses = inventory.warehouses.filter((w) => !w.archived);
  // Main warehouses, each followed by its sub-warehouses.
  const ordered = inventory.warehouses
    .filter((w) => !w.parentId || !inventory.warehouses.some((m) => m.id === w.parentId))
    .flatMap((main) => [main, ...inventory.warehouses.filter((w) => w.parentId === main.id)]);
  // The sub-warehouses the person looks after (and may issue from).
  const mine = access.offered
    ? inventory.warehouses.filter(
        (w) => w.parentId && !w.archived && w.keeper?.userId && w.keeper.userId === access.userId,
      )
    : [];
  const subsOffered = access.offered && access.manages;
  const warehouseName = (id: string | null | undefined) =>
    localName(inventory.warehouses.find((w) => w.id === id)) || '—';
  const totalValue = inventory.stockItems.reduce(
    (sum, item) => sum + toMinor(inventory.levels.get(item.id)?.value ?? 0, p),
    0,
  );
  const inStock = inventory.stockItems.filter(
    (item) => (inventory.levels.get(item.id)?.quantity ?? 0) > 0,
  ).length;
  const low = inventory.stockItems.filter(
    (item) => !item.archived && isLowStock(item, inventory.levels.get(item.id)),
  ).length;
  const landedTotals = new Map<string, number>();
  for (const m of inventory.movements) {
    if (m.sourceType !== 'landed_cost') continue;
    landedTotals.set(
      m.sourceId,
      (landedTotals.get(m.sourceId) ?? 0) + toMinor(m.sourceValue ?? 0, p),
    );
  }

  const tabs: { value: Tab; label: string; count: number }[] = [
    { value: 'stock', label: t('Stock'), count: items.length },
    { value: 'history', label: t('Adjustments'), count: records.entries.length },
    { value: 'warehouses', label: t('Warehouses'), count: activeWarehouses.length },
    { value: 'landed-costs', label: t('Landed costs'), count: records.landedCosts.length },
  ];
  const setTab = (next: Tab) => setParams(next === 'stock' ? {} : { tab: next }, { replace: true });
  const recalculate = async () => {
    setRebuilding(true);
    try {
      await rebuildStock(company.id);
      toast.success(t('Stock recalculated'));
    } catch (e) {
      toast.error(e instanceof Error ? e.message : t('Could not save.'));
    } finally {
      setRebuilding(false);
    }
  };
  const updateWarehouse = async (w: Warehouse, patch: Partial<Warehouse>) => {
    try {
      await saveWarehouse({ ...w, ...patch });
    } catch (e) {
      toast.error(e instanceof Error ? e.message : t('Could not save.'));
    }
  };

  return (
    <div>
      <PageHeader
        title={t('Inventory')}
        description={t('Stock on hand, its value and every movement, by warehouse.')}
        actions={
          <>
            <ButtonLink to="/inventory/adjustments/new" variant="outline">
              <SlidersHorizontal /> {t('Adjust stock')}
            </ButtonLink>
            <ButtonLink to="/inventory/count">
              <ClipboardList /> {t('Stock count')}
            </ButtonLink>
            <DropdownMenu>
              <DropdownTrigger asChild>
                <Button variant="outline" size="icon" aria-label={t('More actions')}>
                  <MoreHorizontal />
                </Button>
              </DropdownTrigger>
              <DropdownContent align="end">
                <DropdownItem
                  icon={<ArrowLeftRight />}
                  disabled={activeWarehouses.length < 2}
                  onSelect={() => navigate('/inventory/adjustments/new?kind=transfer')}
                >
                  {t('Transfer stock')}
                </DropdownItem>
                <DropdownItem
                  icon={<PackagePlus />}
                  onSelect={() => navigate('/inventory/adjustments/new?kind=opening')}
                >
                  {t('Record opening stock')}
                </DropdownItem>
                <DropdownItem
                  icon={<ShipWheel />}
                  onSelect={() => navigate('/inventory/landed-costs/new')}
                >
                  {t('Allocate landed costs')}
                </DropdownItem>
                <DropdownSeparator />
                <DropdownItem
                  icon={<RefreshCw />}
                  disabled={rebuilding}
                  onSelect={() => void recalculate()}
                >
                  {t('Recalculate stock')}
                </DropdownItem>
              </DropdownContent>
            </DropdownMenu>
          </>
        }
      />

      {mine.length > 0 ? (
        <Card className="mb-6">
          <ul className="divide-y divide-slate-100">
            {mine.map((w) => (
              <li key={w.id} className="flex flex-wrap items-center gap-3 px-4 py-3">
                <Shirt className="size-5 shrink-0 text-slate-400" />
                <div className="min-w-0 flex-1">
                  <p className="font-medium text-slate-900">
                    {t('You look after {warehouse}', { warehouse: localName(w) })}
                  </p>
                  <p className="text-xs text-slate-500">
                    {t(
                      'Issue uniforms and other items from it to employees. Each issue waits for an approver.',
                    )}
                  </p>
                </div>
                <ButtonLink to={`/inventory/issues/new?warehouse=${w.id}`} size="sm">
                  <Shirt /> {t('Issue items')}
                </ButtonLink>
              </li>
            ))}
          </ul>
        </Card>
      ) : null}

      <div className="mb-6 grid gap-4 sm:grid-cols-3">
        <Stat
          label={t('Stock value')}
          value={fmt.money(fromMinor(totalValue, p))}
          hint={t('At weighted average cost')}
        />
        <Stat
          label={t('Items in stock')}
          value={fmt.quantity(inStock)}
          hint={tp(inventory.stockItems.length, '{count} stock item', '{count} stock items')}
        />
        <Stat
          label={t('Low stock')}
          value={fmt.quantity(low)}
          tone={low ? 'danger' : 'default'}
          hint={
            low ? (
              <Link to="/reports/low-stock" className="text-primary-700 hover:underline">
                {t('See what to reorder')}
              </Link>
            ) : (
              t('Nothing to reorder')
            )
          }
        />
      </div>

      <Card>
        <div className="flex flex-col gap-3 border-b border-slate-100 px-4 py-3 lg:flex-row lg:items-center lg:justify-between">
          <Select
            aria-label={t('Show')}
            value={tab}
            onChange={(e) => setTab(e.target.value as Tab)}
            className="sm:hidden"
          >
            {tabs.map((o) => (
              <option key={o.value} value={o.value}>
                {o.label} ({fmt.quantity(o.count)})
              </option>
            ))}
          </Select>
          <div className="hidden sm:block">
            <Segmented value={tab} onChange={setTab} options={tabs} />
          </div>
          {tab === 'stock' && inventory.stockItems.length > 0 ? (
            <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
              {activeWarehouses.length > 1 ? (
                <Select
                  aria-label={t('Warehouse')}
                  value={warehouseId}
                  onChange={(e) => setWarehouseId(e.target.value)}
                  className="sm:w-52"
                >
                  <option value="">{t('All warehouses')}</option>
                  {ordered.map((w) => (
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
                  placeholder={t('Search items…')}
                  aria-label={t('Search items')}
                  className="ps-9"
                />
              </div>
            </div>
          ) : null}
          {tab === 'warehouses' ? (
            <div className="flex flex-wrap gap-2">
              {subsOffered && inventory.defaultWarehouse ? (
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() =>
                    setEditing(
                      createWarehouse(company.id, { parentId: inventory.defaultWarehouse!.id }),
                    )
                  }
                >
                  <CornerDownRight /> {t('New sub-warehouse')}
                </Button>
              ) : null}
              <Button
                variant="outline"
                size="sm"
                onClick={() => setEditing(createWarehouse(company.id))}
              >
                <Plus /> {t('New warehouse')}
              </Button>
            </div>
          ) : null}
          {tab === 'landed-costs' ? (
            <ButtonLink to="/inventory/landed-costs/new" variant="outline" size="sm">
              <Plus /> {t('Allocate landed costs')}
            </ButtonLink>
          ) : null}
        </div>

        {tab === 'stock' ? (
          inventory.stockItems.length === 0 ? (
            <EmptyState
              icon={<Boxes />}
              title={t('No stock items yet')}
              description={t(
                'Mark the goods you keep as stock items. Bills bring them in, invoices take them out, and the cost of sales follows.',
              )}
              action={
                <ButtonLink to="/products?new=1&kind=stock">
                  <Plus /> {t('New stock item')}
                </ButtonLink>
              }
            />
          ) : items.length === 0 ? (
            <p className="px-4 py-10 text-center text-sm text-slate-500">{t('Nothing matches.')}</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="border-b border-slate-100 bg-slate-50/60 text-xs text-slate-500">
                  <tr>
                    <th className="w-full px-4 py-2.5 text-start font-medium">{t('Item')}</th>
                    <th className="px-3 py-2.5 text-end font-medium">{t('On hand')}</th>
                    <th className="hidden px-3 py-2.5 text-end font-medium md:table-cell">
                      {t('Average cost')}
                    </th>
                    <th className="hidden px-3 py-2.5 text-end font-medium sm:table-cell">
                      {t('Value')}
                    </th>
                    <th className="hidden px-4 py-2.5 text-end font-medium lg:table-cell">
                      {t('Reorder level')}
                    </th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {items.map((item) => {
                    const level = inventory.levels.get(item.id);
                    const quantity = onHand(level, warehouseId || null);
                    const value = warehouseId
                      ? round(dec(quantity).times(dec(level?.unitCost ?? 0)), p)
                      : (level?.value ?? 0);
                    const isLow = !item.archived && isLowStock(item, level);
                    return (
                      <tr
                        key={item.id}
                        onClick={() => navigate(`/reports/stock-movements?item=${item.id}`)}
                        className="cursor-pointer hover:bg-slate-50"
                      >
                        <td className="max-w-0 px-4 py-2.5">
                          <Link
                            to={`/reports/stock-movements?item=${item.id}`}
                            onClick={(e) => e.stopPropagation()}
                            className="block truncate font-medium text-slate-900 hover:underline"
                          >
                            {localName(item)}
                          </Link>
                          <span className="flex items-center gap-1.5 text-xs text-slate-500">
                            <span className="truncate">{item.sku || item.unit || '—'}</span>
                            {isLow ? <Badge tone="red">{t('Low stock')}</Badge> : null}
                            {quantity < 0 ? <Badge tone="amber">{t('Below zero')}</Badge> : null}
                          </span>
                        </td>
                        <td
                          className={`tabular px-3 py-2.5 text-end whitespace-nowrap ${quantity < 0 ? 'text-red-600' : 'text-slate-900'}`}
                        >
                          {fmt.quantity(quantity)}
                          {item.unit ? <span className="text-slate-500"> {item.unit}</span> : null}
                        </td>
                        <td className="tabular hidden px-3 py-2.5 text-end whitespace-nowrap text-slate-600 md:table-cell">
                          {unitAmount(level?.unitCost ?? 0)}
                        </td>
                        <td className="tabular hidden px-3 py-2.5 text-end font-medium whitespace-nowrap text-slate-900 sm:table-cell">
                          {fmt.money(value)}
                        </td>
                        <td className="tabular hidden px-4 py-2.5 text-end text-slate-600 lg:table-cell">
                          {item.reorderLevel ? fmt.quantity(item.reorderLevel) : '—'}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )
        ) : null}

        {tab === 'history' ? (
          records.entries.length === 0 ? (
            <EmptyState
              icon={<SlidersHorizontal />}
              title={t('No adjustments yet')}
              description={t(
                'Opening stock, write-offs, count differences and transfers between warehouses show here.',
              )}
              action={
                <ButtonLink to="/inventory/adjustments/new" variant="outline">
                  <SlidersHorizontal /> {t('Adjust stock')}
                </ButtonLink>
              }
            />
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="border-b border-slate-100 bg-slate-50/60 text-xs text-slate-500">
                  <tr>
                    <th className="px-4 py-2.5 text-start font-medium">{t('Number')}</th>
                    <th className="px-3 py-2.5 text-start font-medium">{t('Date')}</th>
                    <th className="hidden px-3 py-2.5 text-start font-medium sm:table-cell">
                      {t('Type')}
                    </th>
                    <th className="hidden px-3 py-2.5 text-start font-medium md:table-cell">
                      {t('Warehouse')}
                    </th>
                    <th className="px-4 py-2.5 text-start font-medium">{t('Status')}</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {records.entries.map((entry) => (
                    <tr
                      key={entry.id}
                      onClick={() => navigate(`/inventory/entries/${entry.id}`)}
                      className="cursor-pointer hover:bg-slate-50"
                    >
                      <td className="px-4 py-2.5">
                        <Link
                          to={`/inventory/entries/${entry.id}`}
                          onClick={(e) => e.stopPropagation()}
                          className="tabular font-medium text-slate-900 hover:underline"
                        >
                          {entry.number}
                        </Link>
                        <span className="block text-xs text-slate-500 sm:hidden">
                          {t(ENTRY_LABELS[entry.kind])}
                        </span>
                      </td>
                      <td className="px-3 py-2.5 whitespace-nowrap text-slate-600">
                        {fmt.date(entry.date)}
                      </td>
                      <td className="hidden px-3 py-2.5 text-slate-700 sm:table-cell">
                        {t(ENTRY_LABELS[entry.kind])}
                        {entry.reason ? (
                          <span className="text-slate-500">
                            {' '}
                            · {t(REASON_LABELS[entry.reason])}
                          </span>
                        ) : null}
                      </td>
                      <td className="hidden px-3 py-2.5 text-slate-600 md:table-cell">
                        {entry.kind === 'transfer'
                          ? `${warehouseName(entry.warehouseId)} → ${warehouseName(entry.toWarehouseId)}`
                          : warehouseName(entry.warehouseId)}
                      </td>
                      <td className="px-4 py-2.5">
                        {entry.status === 'void' ? (
                          <Badge tone="gray">{t('Void')}</Badge>
                        ) : (
                          <Badge tone="green">{t('Posted')}</Badge>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )
        ) : null}

        {tab === 'warehouses' ? (
          <ul className="divide-y divide-slate-100">
            {ordered.map((w) => {
              const units = inventory.stockItems.reduce(
                (sum, item) => sum + onHand(inventory.levels.get(item.id), w.id),
                0,
              );
              const sub = Boolean(w.parentId);
              const parent = inventory.warehouses.find((m) => m.id === w.parentId);
              // Stock is sent from the main warehouse; only those who manage
              // warehouses move a sub-warehouse's stock directly.
              const sendable =
                sub &&
                parent &&
                !parent.archived &&
                !w.archived &&
                (access.manages || !access.offered);
              // Staff change no sub-warehouse once the server keeps them.
              const editable = !(sub && access.offered && !access.manages);
              const issues = Boolean(sub) && access.issuesFrom(w);
              const menu =
                editable ||
                sendable ||
                issues ||
                (subsOffered && !sub && !w.archived) ||
                (!w.isDefault && !w.archived && !sub);
              const keeper = w.keeper?.name
                ? w.keeper.jobTitle
                  ? `${w.keeper.name} (${w.keeper.jobTitle})`
                  : w.keeper.name
                : '';
              return (
                <li
                  key={w.id}
                  className={`flex items-center gap-3 py-3 pe-4 ${sub ? 'ps-10' : 'ps-4'}`}
                >
                  {sub ? (
                    <CornerDownRight className="size-5 shrink-0 text-slate-300" />
                  ) : (
                    <WarehouseIcon className="size-5 shrink-0 text-slate-400" />
                  )}
                  <div className="min-w-0 flex-1">
                    <p className="flex flex-wrap items-center gap-2 font-medium text-slate-900">
                      <span className="truncate">{localName(w)}</span>
                      {w.isDefault ? (
                        <Badge tone="blue">
                          {inventory.warehouses.some((s) => s.parentId === w.id)
                            ? t('Main warehouse')
                            : t('Default')}
                        </Badge>
                      ) : null}
                      {sub ? <Badge tone="gray">{t('Sub-warehouse')}</Badge> : null}
                      {w.archived ? <Badge tone="gray">{t('Archived')}</Badge> : null}
                    </p>
                    <p className="truncate text-xs text-slate-500">
                      {[
                        keeper ? t('Looked after by {name}', { name: keeper }) : '',
                        w.address,
                        t('{quantity} units on hand', { quantity: fmt.quantity(units) }),
                      ]
                        .filter(Boolean)
                        .join(' · ')}
                    </p>
                  </div>
                  {sendable ? (
                    <ButtonLink
                      to={`/inventory/adjustments/new?kind=transfer&from=${parent!.id}&to=${w.id}`}
                      variant="outline"
                      size="sm"
                      className="hidden sm:inline-flex"
                    >
                      <Send /> {t('Send stock')}
                    </ButtonLink>
                  ) : null}
                  {issues ? (
                    <ButtonLink
                      to={`/inventory/issues/new?warehouse=${w.id}`}
                      variant="outline"
                      size="sm"
                      className="hidden sm:inline-flex"
                    >
                      <Shirt /> {t('Issue items')}
                    </ButtonLink>
                  ) : null}
                  {menu ? (
                    <DropdownMenu>
                      <DropdownTrigger asChild>
                        <Button
                          variant="ghost"
                          size="icon-sm"
                          aria-label={t('Actions for {name}', { name: localName(w) })}
                        >
                          <MoreHorizontal />
                        </Button>
                      </DropdownTrigger>
                      <DropdownContent align="end">
                        {editable ? (
                          <DropdownItem icon={<Pencil />} onSelect={() => setEditing(w)}>
                            {t('Edit')}
                          </DropdownItem>
                        ) : null}
                        {sendable ? (
                          <DropdownItem
                            icon={<Send />}
                            onSelect={() =>
                              navigate(
                                `/inventory/adjustments/new?kind=transfer&from=${parent!.id}&to=${w.id}`,
                              )
                            }
                          >
                            {t('Send stock')}
                          </DropdownItem>
                        ) : null}
                        {issues ? (
                          <DropdownItem
                            icon={<Shirt />}
                            onSelect={() => navigate(`/inventory/issues/new?warehouse=${w.id}`)}
                          >
                            {t('Issue items')}
                          </DropdownItem>
                        ) : null}
                        {subsOffered && !sub && !w.archived ? (
                          <DropdownItem
                            icon={<CornerDownRight />}
                            onSelect={() =>
                              setEditing(createWarehouse(company.id, { parentId: w.id }))
                            }
                          >
                            {t('Add a sub-warehouse')}
                          </DropdownItem>
                        ) : null}
                        {!w.isDefault && !w.archived && !sub ? (
                          <DropdownItem
                            icon={<Star />}
                            onSelect={() => void updateWarehouse(w, { isDefault: true })}
                          >
                            {t('Make default')}
                          </DropdownItem>
                        ) : null}
                        {!w.isDefault && editable ? (
                          <DropdownItem
                            icon={w.archived ? <ArchiveRestore /> : <Archive />}
                            onSelect={() => void updateWarehouse(w, { archived: !w.archived })}
                          >
                            {w.archived ? t('Restore') : t('Archive')}
                          </DropdownItem>
                        ) : null}
                      </DropdownContent>
                    </DropdownMenu>
                  ) : null}
                </li>
              );
            })}
          </ul>
        ) : null}

        {tab === 'landed-costs' ? (
          records.landedCosts.length === 0 ? (
            <EmptyState
              icon={<ShipWheel />}
              title={t('No landed costs yet')}
              description={t(
                'Add customs duty, freight, clearing and insurance from a bill to the cost of the goods they brought in.',
              )}
              action={
                <ButtonLink to="/inventory/landed-costs/new" variant="outline">
                  <Plus /> {t('Allocate landed costs')}
                </ButtonLink>
              }
            />
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="border-b border-slate-100 bg-slate-50/60 text-xs text-slate-500">
                  <tr>
                    <th className="px-4 py-2.5 text-start font-medium">{t('Number')}</th>
                    <th className="px-3 py-2.5 text-start font-medium">{t('Charges')}</th>
                    <th className="hidden px-3 py-2.5 text-start font-medium sm:table-cell">
                      {t('Goods')}
                    </th>
                    <th className="px-3 py-2.5 text-end font-medium">{t('Amount')}</th>
                    <th className="hidden px-4 py-2.5 text-start font-medium md:table-cell">
                      {t('Status')}
                    </th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {records.landedCosts.map((cost) => {
                    const amount = landedTotals.get(cost.id);
                    return (
                      <tr
                        key={cost.id}
                        onClick={() => navigate(`/inventory/landed-costs/${cost.id}`)}
                        className="cursor-pointer hover:bg-slate-50"
                      >
                        <td className="px-4 py-2.5">
                          <Link
                            to={`/inventory/landed-costs/${cost.id}`}
                            onClick={(e) => e.stopPropagation()}
                            className="tabular font-medium text-slate-900 hover:underline"
                          >
                            {cost.number}
                          </Link>
                        </td>
                        <td className="tabular px-3 py-2.5 text-slate-700">
                          {records.bills.get(cost.billId)?.number ?? '—'}
                        </td>
                        <td className="tabular hidden px-3 py-2.5 text-slate-700 sm:table-cell">
                          {records.bills.get(cost.targetBillId)?.number ?? '—'}
                        </td>
                        <td className="tabular px-3 py-2.5 text-end whitespace-nowrap">
                          {amount === undefined ? '—' : fmt.money(fromMinor(amount, p))}
                        </td>
                        <td className="hidden px-4 py-2.5 md:table-cell">
                          {cost.status === 'void' ? (
                            <Badge tone="gray">{t('Void')}</Badge>
                          ) : (
                            <Badge tone="green">{t('Allocated')}</Badge>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )
        ) : null}
      </Card>
      {editing ? (
        <WarehouseDialog key={editing.id} warehouse={editing} onClose={() => setEditing(null)} />
      ) : null}
    </div>
  );
}
