import { Boxes, TriangleAlert } from 'lucide-react';
import type { ID, LineItem } from '@/db/types';
import { useFormat } from '@/app/company';
import { dec } from '@/lib/money';
import { cn } from '@/lib/cn';
import { t } from '@/i18n';
import { localName } from '@/i18n/names';
import { onHand, type InventoryData } from './use-inventory';

/**
 * How a document uses stock: selling (invoices; vendor credits return goods
 * to the vendor) takes it out, receiving (bills, credit notes) brings it in.
 */
export type StockUse = 'sell' | 'receive';

/** The warehouse a line uses: its own when it still exists, else the default one. */
export function lineWarehouse(
  inventory: InventoryData,
  line: Pick<LineItem, 'warehouseId'>,
): ID | null {
  const own = inventory.warehouses.find((w) => w.id === line.warehouseId && !w.archived);
  return own?.id ?? inventory.defaultWarehouse?.id ?? null;
}

/**
 * Quantity a line can take: what is in its warehouse plus what this line had
 * already taken out when the document was saved before.
 */
function availableFor(inventory: InventoryData, line: LineItem, warehouseId: ID | null): number {
  const level = inventory.levels.get(line.productId ?? '');
  const own = inventory.movements
    .filter(
      (m) =>
        m.lineId === line.id &&
        m.productId === line.productId &&
        m.warehouseId === warehouseId &&
        (m.sourceType === 'invoice' || m.sourceType === 'vendor_credit'),
    )
    .reduce((sum, m) => sum.plus(dec(m.quantity)), dec(0));
  return dec(onHand(level, warehouseId)).minus(own).toNumber();
}

/** Stock on hand under a stock item's line, the warehouse it uses, and a warning when short. */
export function StockLineHint({
  inventory,
  line,
  lines,
  use,
  onWarehouseChange,
  subWarehouses = true,
}: {
  inventory: InventoryData;
  line: LineItem;
  /** All lines of the document, so lines of the same item count together. */
  lines: LineItem[];
  use: StockUse;
  onWarehouseChange: (warehouseId: ID | null) => void;
  /** Whether lines may use sub-warehouses (see useWarehouseAccess). */
  subWarehouses?: boolean;
}) {
  const fmt = useFormat();
  const product = inventory.stockItems.find((p) => p.id === line.productId);
  if (!product) return null;
  const warehouseId = lineWarehouse(inventory, line);
  // A sub-warehouse's stock moves on a document only for the owner, an
  // admin or an accountant (the cloud refuses anyone else); the line's own
  // warehouse stays in the list.
  const warehouses = inventory.warehouses.filter(
    (w) => !w.archived && (subWarehouses || !w.parentId || w.id === warehouseId),
  );
  const available = availableFor(inventory, line, warehouseId);
  const requested = lines
    .filter(
      (l) =>
        l.kind === 'item' &&
        l.productId === line.productId &&
        lineWarehouse(inventory, l) === warehouseId,
    )
    .reduce((sum, l) => sum.plus(dec(l.quantity)), dec(0))
    .toNumber();
  const short = use === 'sell' && requested > available;
  const quantity = `${fmt.quantity(available)}${product.unit ? ` ${product.unit}` : ''}`;
  const Icon = short ? TriangleAlert : Boxes;

  return (
    <div className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs">
      <span
        className={cn(
          'inline-flex items-center gap-1',
          short ? 'font-medium text-amber-700' : 'text-slate-500',
        )}
        role={short ? 'alert' : undefined}
      >
        <Icon className="size-3.5 shrink-0" aria-hidden />
        {short
          ? t('Only {quantity} in stock', { quantity })
          : t('{quantity} in stock', { quantity })}
      </span>
      {warehouses.length > 1 ? (
        <label className="inline-flex items-center gap-1 text-slate-500">
          <span>{use === 'sell' ? t('from') : t('into')}</span>
          <select
            value={warehouseId ?? ''}
            onChange={(e) =>
              onWarehouseChange(
                e.target.value === inventory.defaultWarehouse?.id ? null : e.target.value,
              )
            }
            className="hover:text-primary-700 rounded border-0 bg-transparent py-0 ps-0 pe-5 text-xs font-medium text-slate-700 focus:ring-2"
            aria-label={t('Warehouse')}
          >
            {warehouses.map((w) => (
              <option key={w.id} value={w.id}>
                {localName(w)}
              </option>
            ))}
          </select>
        </label>
      ) : null}
    </div>
  );
}
