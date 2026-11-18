import type {
  AdjustmentReason,
  ProductKind,
  StockEntryKind,
  StockMovement,
  StockSourceType,
} from '@/db/types';
import { msg } from '@/i18n';

/** English text, translated where it is shown. */
export const KIND_LABELS: Record<ProductKind, { label: string; plural: string; hint: string }> = {
  service: {
    label: msg('Service'),
    plural: msg('Services'),
    hint: msg('Work you do, such as delivery, printing or installation.'),
  },
  non_stock: {
    label: msg('Non-stock item'),
    plural: msg('Non-stock items'),
    hint: msg('Goods you buy or sell without counting them in stock.'),
  },
  stock: {
    label: msg('Stock item'),
    plural: msg('Stock items'),
    hint: msg('Goods you keep in stock: quantity on hand, average cost and cost of sales.'),
  },
};

export const PRODUCT_KINDS: ProductKind[] = ['service', 'non_stock', 'stock'];

export const REASON_LABELS: Record<AdjustmentReason, string> = {
  damaged: msg('Damaged'),
  expired: msg('Expired'),
  count: msg('Count difference'),
  other: msg('Other'),
};

export const ADJUSTMENT_REASONS: AdjustmentReason[] = ['damaged', 'expired', 'count', 'other'];

export const ENTRY_LABELS: Record<StockEntryKind, string> = {
  opening: msg('Opening stock'),
  adjustment: msg('Stock adjustment'),
  transfer: msg('Stock transfer'),
};

export const MOVEMENT_LABELS: Record<StockSourceType, string> = {
  bill: msg('Bill'),
  vendor_credit: msg('Vendor credit'),
  invoice: msg('Invoice'),
  credit: msg('Credit note'),
  adjustment: msg('Stock adjustment'),
  opening: msg('Opening stock'),
  transfer: msg('Stock transfer'),
  landed_cost: msg('Landed cost'),
  issue: msg('Items issued'),
};

const DOCUMENT_ROUTES: Partial<Record<StockSourceType, string>> = {
  bill: '/bills',
  vendor_credit: '/vendor-credits',
  invoice: '/invoices',
  credit: '/credits',
};

/** Page showing what a movement came from. */
export function movementLink(m: Pick<StockMovement, 'sourceType' | 'sourceId'>): string {
  if (m.sourceType === 'landed_cost') return `/inventory/landed-costs/${m.sourceId}`;
  if (m.sourceType === 'issue') return `/inventory/issues/${m.sourceId}`;
  const route = DOCUMENT_ROUTES[m.sourceType];
  return route ? `${route}/${m.sourceId}` : `/inventory/entries/${m.sourceId}`;
}
