import type { ReactNode } from 'react';
import {
  ArrowDown,
  ArrowUp,
  Copy,
  GripVertical,
  Heading,
  ListPlus,
  MoreHorizontal,
  Plus,
  Trash2,
} from 'lucide-react';
import type {
  DocumentLanguage,
  ItemCondition,
  LineItem,
  Product,
  TaxLine,
  TaxRate,
} from '@/db/types';
import { isRtlLanguage } from '@/pdf/labels';
import { useCompany } from '@/app/company';
import { matchUnit } from '@/lib/units';
import { t } from '@/i18n';
import { taxLineOf, type CalcLineResult } from '@/lib/calc';
import { cn } from '@/lib/cn';
import { newHeading, newLineItem } from '@/db/documents';
import { Button } from '@/components/ui/button';
import { Input, NumberInput, Select, Textarea } from '@/components/ui/form';
import {
  DropdownContent,
  DropdownItem,
  DropdownMenu,
  DropdownSeparator,
  DropdownTrigger,
} from '@/components/ui/overlay';
import { ItemNameInput } from './item-name-input';
import { TaxSelect } from './tax-select';
import { useInventory } from '@/apps/books/features/inventory/use-inventory';
import { useWarehouseAccess } from '@/features/inventory/issues';
import { StockLineHint, type StockUse } from '@/apps/books/features/inventory/stock-hint';
import { StockSuggestion } from '@/apps/books/features/inventory/stock-suggestion';

function MiniLabel({ children }: { children: ReactNode }) {
  return (
    <span className="mb-1 block text-xs font-medium text-slate-500 @xl:hidden">{children}</span>
  );
}

function FieldLabel({ children }: { children: ReactNode }) {
  return <span className="mb-1 block text-xs font-medium text-slate-500">{children}</span>;
}

export function DiscountInput({
  value,
  type,
  onChange,
  currencySymbol,
  ariaLabel,
}: {
  value: number;
  type: 'percent' | 'amount';
  onChange: (value: number, type: 'percent' | 'amount') => void;
  currencySymbol: string;
  ariaLabel?: string;
}) {
  return (
    <div className="flex">
      <NumberInput
        aria-label={ariaLabel ?? t('Discount')}
        value={value}
        onValueChange={(v) => onChange(v, type)}
        allowNegative={false}
        className="rounded-e-none"
      />
      <button
        type="button"
        onClick={() => onChange(value, type === 'percent' ? 'amount' : 'percent')}
        className="h-9 min-w-9 rounded-e-lg border border-s-0 border-slate-300 bg-slate-50 px-2 text-xs font-semibold text-slate-600 hover:bg-slate-100"
        title={type === 'percent' ? t('Switch to a fixed amount') : t('Switch to a percentage')}
      >
        {type === 'percent' ? '%' : currencySymbol}
      </button>
    </div>
  );
}

export function LineItemsEditor({
  items,
  onChange,
  lines,
  products,
  taxRates,
  showTaxes,
  defaultTaxes,
  currencySymbol,
  formatMoney,
  formatPrice,
  language,
  prices = true,
  stockUse = 'sell',
}: {
  items: LineItem[];
  onChange: (items: LineItem[]) => void;
  lines: CalcLineResult[];
  products: Product[];
  taxRates: TaxRate[];
  showTaxes: boolean;
  defaultTaxes: TaxLine[];
  currencySymbol: string;
  formatMoney: (amount: number) => string;
  formatPrice: (amount: number) => string;
  /** Language the document prints in; Arabic names are asked for unless it is not Arabic. */
  language?: DocumentLanguage;
  /** False for delivery notes: quantities, units and serial numbers only. */
  prices?: boolean;
  /** Stock items show what is in stock; selling more than that is flagged. */
  stockUse?: StockUse;
}) {
  const inventory = useInventory();
  const warehouseAccess = useWarehouseAccess();
  const company = useCompany();
  const showArabic =
    language === undefined || isRtlLanguage(language) || items.some((i) => i.nameAr?.trim());
  /** Lines selling goods can carry their condition and serial number. */
  const hasGoodsDetails = (item: LineItem) =>
    item.condition !== undefined || (prices && item.serialNumber !== undefined);
  const update = (index: number, patch: Partial<LineItem>) =>
    onChange(items.map((item, i) => (i === index ? { ...item, ...patch } : item)));
  const remove = (index: number) => onChange(items.filter((_, i) => i !== index));
  const move = (index: number, delta: number) => {
    const target = index + delta;
    if (target < 0 || target >= items.length) return;
    const next = [...items];
    [next[index], next[target]] = [next[target], next[index]];
    onChange(next);
  };
  const duplicate = (index: number) => {
    const next = [...items];
    next.splice(index + 1, 0, { ...items[index], id: newLineItem().id });
    onChange(next);
  };
  const insertHeading = (index: number) => {
    const next = [...items];
    next.splice(index, 0, newHeading());
    onChange(next);
  };

  const pickProduct = (index: number, product: Product) => {
    const taxes = product.taxRateIds
      .map((id) => taxRates.find((t) => t.id === id))
      .filter((t): t is TaxRate => Boolean(t))
      .map(taxLineOf);
    update(index, {
      productId: product.id,
      name: product.name,
      nameAr: product.nameAr ?? '',
      // Arabic documents use the Arabic description when there is one.
      description:
        language === 'ar' && product.descriptionAr?.trim()
          ? product.descriptionAr
          : product.description,
      unitPrice: product.unitPrice,
      unit: product.unit,
      // Arabic documents print the unit's Arabic name.
      unitId: product.unitId,
      // Printed in the SKU column when the design shows one.
      sku: product.sku.trim() || undefined,
      taxes: showTaxes ? (product.taxRateIds.length ? taxes : items[index].taxes) : [],
    });
  };

  const serialInput = (item: LineItem, index: number) => (
    <Input
      aria-label={t('Item {number} serial number', { number: index + 1 })}
      dir="ltr"
      value={item.serialNumber ?? ''}
      onChange={(e) => update(index, { serialNumber: e.target.value })}
      placeholder={t('Serial or IMEI number')}
    />
  );
  const conditionSelect = (item: LineItem, index: number) => (
    <Select
      aria-label={t('Item {number} condition', { number: index + 1 })}
      value={item.condition ?? ''}
      onChange={(e) =>
        update(index, {
          condition: (e.target.value || null) as ItemCondition | null,
        })
      }
    >
      <option value="">{t('Not shown')}</option>
      <option value="new">{t('New')}</option>
      <option value="used">{t('Used')}</option>
    </Select>
  );

  // Container queries: the layout follows the editor's width, not the screen's,
  // because the live preview takes part of the screen.
  return (
    <div className="@container">
      <div className="hidden grid-cols-12 gap-3 px-3 pb-2 text-xs font-medium tracking-wide text-slate-500 uppercase @xl:grid">
        {prices ? (
          <>
            <span className="col-span-5 ps-5">{t('Item')}</span>
            <span className="col-span-2 text-end">{t('Qty')}</span>
            <span className="col-span-2 text-end">{t('Price')}</span>
            <span className="col-span-3 pe-9 text-end">{t('Amount')}</span>
          </>
        ) : (
          <>
            <span className="col-span-7 ps-5">{t('Item')}</span>
            <span className="col-span-2 text-end">{t('Qty')}</span>
            <span className="col-span-3 pe-9">{t('Unit')}</span>
          </>
        )}
      </div>

      <ol className="space-y-2">
        {items.map((item, index) => {
          const menu = (
            <DropdownMenu>
              <DropdownTrigger asChild>
                <Button
                  variant="ghost"
                  size="icon-sm"
                  aria-label={t('Line {number} actions', { number: index + 1 })}
                >
                  <MoreHorizontal />
                </Button>
              </DropdownTrigger>
              <DropdownContent>
                <DropdownItem
                  icon={<ArrowUp />}
                  disabled={index === 0}
                  onSelect={() => move(index, -1)}
                >
                  {t('Move up')}
                </DropdownItem>
                <DropdownItem
                  icon={<ArrowDown />}
                  disabled={index === items.length - 1}
                  onSelect={() => move(index, 1)}
                >
                  {t('Move down')}
                </DropdownItem>
                <DropdownItem icon={<Copy />} onSelect={() => duplicate(index)}>
                  {t('Duplicate')}
                </DropdownItem>
                <DropdownItem icon={<Heading />} onSelect={() => insertHeading(index)}>
                  {t('Insert heading above')}
                </DropdownItem>
                {items[index].kind === 'item' ? (
                  <DropdownItem
                    icon={<ListPlus />}
                    onSelect={() =>
                      update(
                        index,
                        hasGoodsDetails(items[index])
                          ? { condition: undefined, ...(prices ? { serialNumber: undefined } : {}) }
                          : { condition: null, serialNumber: items[index].serialNumber ?? '' },
                      )
                    }
                  >
                    {prices
                      ? hasGoodsDetails(items[index])
                        ? t('Remove condition and serial no.')
                        : t('Add condition and serial no.')
                      : hasGoodsDetails(items[index])
                        ? t('Remove condition')
                        : t('Add condition')}
                  </DropdownItem>
                ) : null}
                <DropdownSeparator />
                <DropdownItem icon={<Trash2 />} danger onSelect={() => remove(index)}>
                  {t('Remove')}
                </DropdownItem>
              </DropdownContent>
            </DropdownMenu>
          );

          if (item.kind === 'heading') {
            return (
              <li
                key={item.id}
                className="flex items-start gap-2 rounded-lg border border-dashed border-slate-300 bg-slate-50/70 p-3"
              >
                <GripVertical
                  className="mt-2.5 hidden size-4 shrink-0 text-slate-300 @xl:block"
                  aria-hidden
                />
                <div className="flex-1 space-y-2">
                  <Input
                    aria-label={t('Section heading')}
                    value={item.name}
                    onChange={(e) => update(index, { name: e.target.value })}
                    placeholder={t('Section heading, e.g. “Print production”')}
                    className="font-semibold"
                  />
                  {showArabic ? (
                    <Input
                      aria-label={t('Section heading in Arabic')}
                      dir="rtl"
                      lang="ar"
                      value={item.nameAr ?? ''}
                      onChange={(e) => update(index, { nameAr: e.target.value })}
                      placeholder={t('Heading in Arabic')}
                      className="font-semibold"
                    />
                  ) : null}
                  <Input
                    aria-label={t('Section note')}
                    value={item.description}
                    onChange={(e) => update(index, { description: e.target.value })}
                    placeholder={t('Optional note')}
                    className="h-8 text-xs"
                  />
                </div>
                {menu}
              </li>
            );
          }

          const nameInput = (
            <div className="flex items-start gap-2">
              <GripVertical
                className="mt-2.5 hidden size-4 shrink-0 text-slate-300 @xl:block"
                aria-hidden
              />
              <div className="min-w-0 flex-1">
                <ItemNameInput
                  ariaLabel={t('Item {number} name', { number: index + 1 })}
                  value={item.name}
                  onChange={(name) => update(index, { name, productId: null, sku: undefined })}
                  products={products}
                  onPick={(p) => pickProduct(index, p)}
                  formatPrice={formatPrice}
                  stockOf={(p) =>
                    inventory ? <StockSuggestion inventory={inventory} product={p} /> : null
                  }
                />
                {inventory && item.productId ? (
                  <StockLineHint
                    inventory={inventory}
                    line={item}
                    lines={items}
                    use={stockUse}
                    onWarehouseChange={(warehouseId) => update(index, { warehouseId })}
                    subWarehouses={!warehouseAccess?.offered || warehouseAccess.manages}
                  />
                ) : null}
              </div>
            </div>
          );
          const quantityInput = (
            <NumberInput
              aria-label={t('Item {number} quantity', { number: index + 1 })}
              value={item.quantity}
              onValueChange={(quantity) => update(index, { quantity })}
            />
          );
          const unitInput = (
            <Input
              aria-label={t('Item {number} unit', { number: index + 1 })}
              value={item.unit}
              onChange={(e) =>
                update(index, {
                  unit: e.target.value,
                  // A unit typed over is the list's only when it names one of them.
                  unitId: company.items?.units
                    ? (matchUnit(e.target.value, company) ?? undefined)
                    : undefined,
                })
              }
              placeholder={t('pcs, hrs…')}
              className={prices ? 'text-end' : undefined}
            />
          );
          const details = (
            <>
              {showArabic ? (
                <Input
                  aria-label={t('Arabic name of item {number}', { number: index + 1 })}
                  dir="rtl"
                  lang="ar"
                  value={item.nameAr ?? ''}
                  onChange={(e) => update(index, { nameAr: e.target.value })}
                  placeholder={t('Name in Arabic (optional)')}
                />
              ) : null}
              <Textarea
                aria-label={t('Item {number} description', { number: index + 1 })}
                value={item.description}
                onChange={(e) => update(index, { description: e.target.value })}
                placeholder={t('Description (optional)')}
                rows={1}
                className="min-h-9 resize-y py-1.5 text-sm"
              />
            </>
          );

          if (!prices) {
            // Delivery notes: what goes out, how many and which serial numbers.
            return (
              <li
                key={item.id}
                className="bg-surface rounded-lg border border-slate-200 p-3 shadow-xs"
              >
                <div className="grid grid-cols-12 gap-x-3 gap-y-2">
                  <div className="col-span-12 @xl:col-span-7">{nameInput}</div>
                  <div className="col-span-5 @xl:col-span-2">
                    <MiniLabel>{t('Qty')}</MiniLabel>
                    {quantityInput}
                  </div>
                  <div className="col-span-7 flex items-start gap-1 @xl:col-span-3">
                    <div className="min-w-0 flex-1">
                      <MiniLabel>{t('Unit')}</MiniLabel>
                      {unitInput}
                    </div>
                    <div className="hidden @xl:block">{menu}</div>
                  </div>
                  <div className="col-span-12 space-y-2 @xl:col-span-7 @xl:ps-6">{details}</div>
                  <label className="col-span-12 @xl:col-span-5">
                    <FieldLabel>{t('Serial no.')}</FieldLabel>
                    {serialInput(item, index)}
                  </label>
                  {item.condition !== undefined ? (
                    <label className="col-span-12 @xl:col-span-5 @xl:col-start-8">
                      <FieldLabel>{t('Condition')}</FieldLabel>
                      {conditionSelect(item, index)}
                    </label>
                  ) : null}
                </div>
                <div className="mt-2 flex justify-end @xl:hidden">{menu}</div>
              </li>
            );
          }

          const line = lines[index];
          return (
            <li
              key={item.id}
              className="bg-surface rounded-lg border border-slate-200 p-3 shadow-xs"
            >
              <div className="grid grid-cols-12 gap-x-3 gap-y-2">
                <div className="col-span-12 @xl:col-span-5">{nameInput}</div>
                <div className="col-span-4 @xl:col-span-2">
                  <MiniLabel>{t('Qty')}</MiniLabel>
                  {quantityInput}
                </div>
                <div className="col-span-4 @xl:col-span-2">
                  <MiniLabel>{t('Price')}</MiniLabel>
                  <NumberInput
                    aria-label={t('Item {number} unit price', { number: index + 1 })}
                    value={item.unitPrice}
                    onValueChange={(unitPrice) => update(index, { unitPrice })}
                  />
                </div>
                <div className="col-span-4 flex items-start justify-end gap-1 @xl:col-span-3">
                  <div className="min-w-0 flex-1 text-end">
                    <MiniLabel>{t('Amount')}</MiniLabel>
                    <p
                      className="tabular truncate pt-2 text-sm font-semibold text-slate-900"
                      aria-label={t('Item {number} amount', { number: index + 1 })}
                    >
                      {formatMoney(line?.net ?? 0)}
                    </p>
                  </div>
                  <div className="hidden @xl:block">{menu}</div>
                </div>

                <div
                  className={cn(
                    'col-span-12 space-y-2 @xl:col-span-5 @xl:ps-6',
                    // Condition and serial number sit beside the description.
                    hasGoodsDetails(item) && '@xl:row-span-2',
                  )}
                >
                  {details}
                </div>
                <div className="col-span-4 @xl:col-span-2">
                  <FieldLabel>{t('Unit')}</FieldLabel>
                  {unitInput}
                </div>
                <div className="col-span-4 @xl:col-span-2">
                  <FieldLabel>{t('Discount')}</FieldLabel>
                  <DiscountInput
                    ariaLabel={t('Item {number} discount', { number: index + 1 })}
                    value={item.discount}
                    type={item.discountType}
                    currencySymbol={currencySymbol}
                    onChange={(discount, discountType) => update(index, { discount, discountType })}
                  />
                </div>
                <div className={cn('col-span-4 @xl:col-span-3', !showTaxes && 'invisible')}>
                  <FieldLabel>{t('Tax')}</FieldLabel>
                  <TaxSelect
                    value={item.taxes}
                    onChange={(taxes) => update(index, { taxes })}
                    rates={taxRates}
                  />
                </div>
                {hasGoodsDetails(item) ? (
                  <>
                    <label className="col-span-5 @xl:col-span-2 @xl:col-start-6">
                      <FieldLabel>{t('Condition')}</FieldLabel>
                      {conditionSelect(item, index)}
                    </label>
                    <label className="col-span-7 @xl:col-span-5">
                      <FieldLabel>{t('Serial no.')}</FieldLabel>
                      {serialInput(item, index)}
                    </label>
                  </>
                ) : null}
              </div>
              <div className="mt-2 flex justify-end @xl:hidden">{menu}</div>
            </li>
          );
        })}
      </ol>

      <div className="mt-3 flex flex-wrap gap-2">
        <Button
          variant="outline"
          size="sm"
          onClick={() => onChange([...items, newLineItem(showTaxes ? defaultTaxes : [])])}
        >
          <Plus /> {t('Add item')}
        </Button>
        <Button variant="ghost" size="sm" onClick={() => onChange([...items, newHeading()])}>
          <Heading /> {t('Add section heading')}
        </Button>
      </div>
    </div>
  );
}
