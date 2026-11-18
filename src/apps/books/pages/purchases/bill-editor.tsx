import { useEffect, useEffectEvent, useMemo, useState } from 'react';
import { Link, useNavigate, useParams, useSearchParams } from 'react-router';
import { useLiveQuery } from 'dexie-react-hooks';
import { Plus, Trash2 } from 'lucide-react';
import { toast } from 'sonner';
import { db } from '@/db/db';
import {
  defaultTaxes as loadDefaultTaxes,
  draftDocument,
  DuplicateNumberError,
  isNumberTaken,
  newLineItem,
  saveDocument,
  suggestNumber,
} from '@/db/documents';
import { roleMap } from '@/db/accounting';
import { isVendor } from '@/db/purchases';
import type { InvoiceDocument, LineItem, PurchaseDocumentType, TaxLine } from '@/db/types';
import {
  DOCUMENT_LABELS,
  DOCUMENT_ROUTES,
  documentNoun,
  useCompany,
  useFormat,
} from '@/app/company';
import { computeDocument, documentTaxExempt } from '@/lib/document-calc';
import { addDaysISO, daysBetween } from '@/lib/dates';
import { currencySymbol } from '@/lib/format';
import { issuedStatus } from '@/lib/status';
import { cn } from '@/lib/cn';
import { t } from '@/i18n';
import { Button } from '@/components/ui/button';
import { Card, CardBody, CardHeader, Spinner } from '@/components/ui/misc';
import { Field, Input, NumberInput, Select, Textarea } from '@/components/ui/form';
import { Combobox } from '@/components/ui/combobox';
import { CurrencySelect } from '@/components/fields';
import { retentionDefaults } from '@/lib/retention';
import { TotalsPanel } from '@/apps/books/features/editor/totals-panel';
import { TaxSelect } from '@/apps/books/features/editor/tax-select';
import { ClientDialog } from '@/features/clients/client-dialog';
import { contactOptions } from '@/features/clients/contact-option';
import { categoryOptions, useAccounts } from '@/apps/books/features/accounting/account-pickers';
import { AttachmentList, useDraftAttachments } from '@/features/purchases/attachments';
import { ItemNameInput } from '@/apps/books/features/editor/item-name-input';
import { useInventory } from '@/apps/books/features/inventory/use-inventory';
import { useWarehouseAccess } from '@/features/inventory/issues';
import { StockLineHint } from '@/apps/books/features/inventory/stock-hint';
import { StockSuggestion } from '@/apps/books/features/inventory/stock-suggestion';
import { accountingSettings } from '@/db/chart-setup';
import { stockAccounts } from '@/lib/inventory/sources';
import { formatUnitPrice } from '@/lib/format';
import { useUnsavedGuard } from '@/hooks/use-unsaved-guard';
import { StickyActions } from '@/components/ui/sticky-actions';
import { DateField } from '@/components/ui/date-field';

const PAYMENT_TERMS = [0, 7, 14, 15, 30, 45, 60, 90];

/** Six columns when stacked (phones); one row per line from 48rem of card width. */
const LINE_GRID =
  'grid grid-cols-6 items-start gap-x-3 gap-y-2 @3xl:grid-cols-[minmax(0,1.25fr)_minmax(0,1.6fr)_5rem_7rem_9rem_7.5rem_2.25rem] @3xl:px-4';

function MiniLabel({ children }: { children: React.ReactNode }) {
  return (
    <span className="mb-1 block text-xs font-medium text-slate-500 @3xl:hidden">{children}</span>
  );
}

type SaveIntent = 'draft' | 'open';

/** The vendor's own number for this document. */
function referenceLabel(type: PurchaseDocumentType): string {
  if (type === 'bill') return t("Vendor's invoice number");
  if (type === 'vendor_credit') return t("Vendor's credit note number");
  return t("Vendor's quote number");
}

function Editor({
  type,
  initial,
  isNew,
  defaultTaxes,
}: {
  type: PurchaseDocumentType;
  initial: InvoiceDocument;
  isNew: boolean;
  defaultTaxes: TaxLine[];
}) {
  const navigate = useNavigate();
  const company = useCompany();
  const fmt = useFormat();
  const labels = DOCUMENT_LABELS[type];
  const base = DOCUMENT_ROUTES[type];
  const order = type === 'purchase_order';

  const [doc, setDoc] = useState(initial);
  const [numberHint, setNumberHint] = useState('');
  const [errors, setErrors] = useState<{ vendor?: string; number?: string; items?: string }>({});
  const [saving, setSaving] = useState<SaveIntent | null>(null);
  const [vendorDialog, setVendorDialog] = useState<{ open: boolean; name: string }>({
    open: false,
    name: '',
  });
  const attachments = useDraftAttachments(doc.id);

  const clients = useLiveQuery(
    () => db.clients.where('companyId').equals(company.id).toArray(),
    [company.id],
  );
  const taxRates = useLiveQuery(
    () => db.taxRates.where('companyId').equals(company.id).toArray(),
    [company.id],
  );
  const accounts = useAccounts();
  const inventory = useInventory();
  const warehouseAccess = useWarehouseAccess();

  const vendor = useMemo(
    () => clients?.find((c) => c.id === doc.clientId) ?? null,
    [clients, doc.clientId],
  );
  const result = useMemo(
    () =>
      computeDocument(doc, { paid: doc.totals.paid, taxExempt: documentTaxExempt(doc, vendor) }),
    [doc, vendor],
  );

  // Suggested number for new documents (assigned for real on save).
  const currentCompany = useEffectEvent(() => company);
  const hasNumber = Boolean(doc.number);
  useEffect(() => {
    if (hasNumber) return;
    let cancelled = false;
    void suggestNumber(currentCompany(), type, doc.issueDate, vendor?.number ?? '').then((n) => {
      if (!cancelled) setNumberHint(n);
    });
    return () => {
      cancelled = true;
    };
  }, [doc.issueDate, hasNumber, type, vendor?.number]);

  const dirty = JSON.stringify(doc) !== JSON.stringify(initial) || attachments.dirty;
  const allowNavigation = useUnsavedGuard(dirty && saving === null);

  if (!clients || !taxRates || !accounts || !inventory) {
    return <Spinner className="py-24" label={t('Loading…')} />;
  }

  const roles = roleMap(accounts);
  const defaultAccount = roles.expense ?? '';
  // Stock items always post to inventory.
  const inventoryAccount =
    stockAccounts(accounts, accountingSettings(company).template).inventory?.id ?? null;
  const stockItem = (line: LineItem) =>
    inventory.stockItems.find((p) => p.id === line.productId) ?? null;
  const options = categoryOptions(accounts, [
    ...doc.items.map((i) => i.accountId),
    inventoryAccount,
  ]);

  const update = (patch: Partial<InvoiceDocument>) => setDoc((d) => ({ ...d, ...patch }));
  const updateLine = (id: string, patch: Partial<LineItem>) =>
    setDoc((d) => ({ ...d, items: d.items.map((i) => (i.id === id ? { ...i, ...patch } : i)) }));
  const money = (amount: number) => fmt.money(amount, doc.currency);
  const symbol = currencySymbol(doc.currency, fmt.locale);
  const termsDays = doc.dueDate ? daysBetween(doc.issueDate, doc.dueDate) : null;
  const termsValue =
    termsDays === null ? 'none' : PAYMENT_TERMS.includes(termsDays) ? String(termsDays) : 'custom';
  const lines = doc.items.filter((i) => i.kind === 'item');

  const selectVendor = (vendorId: string) => {
    const picked = clients.find((c) => c.id === vendorId);
    setErrors((e) => ({ ...e, vendor: undefined }));
    setDoc((d) => {
      const next: InvoiceDocument = { ...d, clientId: vendorId };
      // Another vendor: it is entered with that vendor's tax exemption.
      if (vendorId !== d.clientId) delete next.posting;
      if (picked) {
        if (isNew || d.totals.paid === 0) next.currency = picked.currency || company.currency;
        if (type === 'bill' && isNew) {
          next.dueDate = addDaysISO(
            d.issueDate,
            picked.paymentTermsDays ?? company.defaults.paymentTermsDays,
          );
          Object.assign(next, retentionDefaults(picked, type, d.issueDate));
        }
      }
      return next;
    });
  };

  const save = async (intent: SaveIntent) => {
    const found: typeof errors = {};
    if (!doc.clientId) found.vendor = t('Choose the vendor.');
    const hasContent = lines.some((i) => i.name.trim() || i.unitPrice !== 0);
    if (!hasContent) found.items = t('Add at least one line.');
    if (doc.number.trim() && (await isNumberTaken(company.id, type, doc.number, doc.id))) {
      found.number = t('This number is already used.');
    }
    setErrors(found);
    if (Object.keys(found).length) {
      toast.error(t('Please fix the highlighted fields.'));
      return;
    }
    setSaving(intent);
    try {
      const saved = await saveDocument({
        ...doc,
        // Saving takes a draft out of the office: an open bill, an issued order.
        status:
          intent === 'draft'
            ? 'draft'
            : doc.status === 'draft'
              ? (issuedStatus(type) ?? doc.status)
              : doc.status,
        items: doc.items.filter((i) => i.name.trim() || i.unitPrice !== 0),
        charges: doc.charges.filter((c) => c.label.trim() || c.amount !== 0),
      });
      await attachments.commit(company.id);
      toast.success(
        t('{document} {number} saved', { document: t(labels.singular), number: saved.number }),
      );
      allowNavigation();
      navigate(`${base}/${saved.id}`);
    } catch (error) {
      if (error instanceof DuplicateNumberError)
        setErrors({ number: t('This number is already used.') });
      toast.error(error instanceof Error ? error.message : t('Could not save.'));
      setSaving(null);
    }
  };

  const vendorOptions = contactOptions(
    clients.filter((c) => (isVendor(c) && !c.archived) || c.id === doc.clientId),
  );

  const actions = (
    <div className="flex flex-wrap items-center gap-2">
      <Button variant="ghost" onClick={() => navigate(-1)}>
        {t('Cancel')}
      </Button>
      {doc.status === 'draft' ? (
        <Button
          variant="outline"
          onClick={() => void save('draft')}
          loading={saving === 'draft'}
          disabled={saving !== null}
        >
          {t('Save as draft')}
        </Button>
      ) : null}
      <Button
        onClick={() => void save('open')}
        loading={saving === 'open'}
        disabled={saving !== null}
      >
        {t('Save')}
      </Button>
    </div>
  );

  const columns = [
    { key: 'category', label: t('Category') },
    { key: 'description', label: t('Description') },
    { key: 'qty', label: t('Qty'), end: true },
    { key: 'rate', label: t('Price'), end: true },
    { key: 'tax', label: t('Tax') },
    { key: 'amount', label: t('Amount'), end: true },
  ];

  return (
    <div className="mx-auto max-w-6xl">
      <div className="mb-6 flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="mb-1 text-sm text-slate-500">
            <Link to={base} className="hover:text-slate-700">
              {t(labels.plural)}
            </Link>
          </p>
          <h1 className="text-2xl font-semibold tracking-tight text-slate-900">
            {isNew
              ? t(labels.create)
              : t('Edit {document} {number}', { document: documentNoun(type), number: doc.number })}
          </h1>
        </div>
        <StickyActions>{actions}</StickyActions>
      </div>

      <div className="space-y-6">
        <Card>
          <CardBody className="grid gap-4 md:grid-cols-2">
            <Field label={t('Vendor')} error={errors.vendor} className="md:col-span-2">
              {(fid) => (
                <Combobox
                  id={fid}
                  value={doc.clientId || null}
                  onChange={selectVendor}
                  options={vendorOptions}
                  placeholder={t('Choose a vendor…')}
                  searchPlaceholder={t('Search vendors…')}
                  onCreate={(name) => setVendorDialog({ open: true, name })}
                  createLabel={t('New vendor')}
                />
              )}
            </Field>
            <Field label={referenceLabel(type)} optional>
              {(fid) => (
                <Input
                  id={fid}
                  value={doc.vendorReference ?? ''}
                  onChange={(e) => update({ vendorReference: e.target.value })}
                  placeholder={t('As printed on their document')}
                />
              )}
            </Field>
            <Field
              label={t(labels.numberLabel)}
              error={errors.number}
              hint={isNew && !doc.number ? t('Your own number, assigned when saved.') : undefined}
            >
              {(fid) => (
                <Input
                  id={fid}
                  value={doc.number}
                  placeholder={numberHint}
                  onChange={(e) => {
                    update({ number: e.target.value });
                    setErrors((x) => ({ ...x, number: undefined }));
                  }}
                  aria-invalid={Boolean(errors.number)}
                />
              )}
            </Field>
            <Field label={type === 'bill' ? t('Bill date') : order ? t('Order date') : t('Date')}>
              {(fid) => (
                <DateField
                  id={fid}
                  value={doc.issueDate}
                  onChange={(iso) => {
                    const value = iso;
                    if (!value) return;
                    update({
                      issueDate: value,
                      dueDate:
                        doc.dueDate && termsDays !== null
                          ? addDaysISO(value, termsDays)
                          : doc.dueDate,
                    });
                  }}
                />
              )}
            </Field>
            {type === 'bill' ? (
              <Field label={t('Due date')}>
                {(fid) => (
                  <div className="flex flex-wrap gap-2">
                    <Select
                      aria-label={t('Payment terms')}
                      value={termsValue}
                      onChange={(e) => {
                        const v = e.target.value;
                        if (v === 'none') update({ dueDate: null });
                        else if (v !== 'custom')
                          update({ dueDate: addDaysISO(doc.issueDate, Number(v)) });
                      }}
                      className="w-36"
                    >
                      <option value="none">{t('No due date')}</option>
                      {PAYMENT_TERMS.map((d) => (
                        <option key={d} value={d}>
                          {d === 0 ? t('Due on receipt') : t('Net {days}', { days: d })}
                        </option>
                      ))}
                      <option value="custom">{t('Custom')}</option>
                    </Select>
                    <DateField
                      id={fid}
                      value={doc.dueDate ?? ''}
                      onChange={(iso) => update({ dueDate: iso || null })}
                      className="min-w-36 flex-1"
                    />
                  </div>
                )}
              </Field>
            ) : null}
            {order ? (
              <>
                <Field label={t('Delivery date')} optional>
                  {(fid) => (
                    <DateField
                      id={fid}
                      value={doc.deliveryDate ?? ''}
                      onChange={(iso) => update({ deliveryDate: iso || null })}
                    />
                  )}
                </Field>
                <Field label={t('Deliver to')} optional>
                  {(fid) => (
                    <Input
                      id={fid}
                      value={doc.deliveryPlace ?? ''}
                      placeholder={t('Site, warehouse or address')}
                      onChange={(e) => update({ deliveryPlace: e.target.value })}
                    />
                  )}
                </Field>
              </>
            ) : (
              <Field label={t('PO / reference')} optional>
                {(fid) => (
                  <Input
                    id={fid}
                    value={doc.poNumber}
                    onChange={(e) => update({ poNumber: e.target.value })}
                  />
                )}
              </Field>
            )}
            <Field
              label={t('Currency')}
              hint={
                doc.totals.paid !== 0
                  ? t('Payments or credits are recorded on it, so its currency stays.')
                  : undefined
              }
            >
              {(fid) => (
                <CurrencySelect
                  id={fid}
                  value={doc.currency}
                  onChange={(currency) => update({ currency })}
                  disabled={doc.totals.paid !== 0}
                />
              )}
            </Field>
            {doc.currency !== company.currency && !order ? (
              <Field
                label={t('Exchange rate')}
                hint={t('1 {currency} = {rate} {base}, used for your books', {
                  currency: doc.currency,
                  rate: doc.exchangeRate || '?',
                  base: company.currency,
                })}
              >
                {(fid) => (
                  <NumberInput
                    id={fid}
                    value={doc.exchangeRate ?? 0}
                    onValueChange={(exchangeRate) => update({ exchangeRate })}
                    allowNegative={false}
                  />
                )}
              </Field>
            ) : null}
          </CardBody>
        </Card>

        <Card>
          <CardHeader
            title={t('Lines')}
            description={
              errors.items ? (
                <span className="text-red-600">{errors.items}</span>
              ) : order ? (
                t('What you are ordering. The categories carry over to the bill.')
              ) : (
                t('Each line goes to an expense or asset account in your books.')
              )
            }
          />
          {/* Container queries: a table on wide cards, stacked fields on phones. */}
          <div className="@container">
            <div className={cn(LINE_GRID, 'hidden border-b border-slate-100 py-2.5 @3xl:grid')}>
              {columns.map((column) => (
                <span
                  key={column.key}
                  className={cn(
                    'text-xs font-medium tracking-wide text-slate-500 uppercase',
                    column.end && 'text-end',
                  )}
                >
                  {column.label}
                </span>
              ))}
            </div>
            <ol className="space-y-3 px-4 py-3 @3xl:space-y-0 @3xl:divide-y @3xl:divide-slate-100 @3xl:p-0">
              {doc.items.map((item, index) =>
                item.kind === 'heading' ? null : (
                  <li
                    key={item.id}
                    className={cn(
                      LINE_GRID,
                      'rounded-lg border border-slate-200 p-3 @3xl:rounded-none @3xl:border-0 @3xl:py-2',
                    )}
                  >
                    <div className="col-span-6 @3xl:col-span-1">
                      <MiniLabel>{t('Category')}</MiniLabel>
                      <Combobox
                        ariaLabel={t('Line {number} category', { number: index + 1 })}
                        value={
                          (stockItem(item) ? inventoryAccount : item.accountId) ||
                          defaultAccount ||
                          null
                        }
                        onChange={(accountId) => updateLine(item.id, { accountId })}
                        options={options}
                        placeholder={t('Choose a category…')}
                        searchPlaceholder={t('Search accounts…')}
                        disabled={Boolean(stockItem(item))}
                      />
                    </div>
                    <div className="col-span-6 space-y-2 @3xl:col-span-1">
                      <MiniLabel>{t('Description')}</MiniLabel>
                      <ItemNameInput
                        ariaLabel={t('Line {number} description', { number: index + 1 })}
                        value={item.name}
                        onChange={(name) => {
                          // Typed over a stock item: the line is a plain expense again.
                          updateLine(item.id, {
                            name,
                            productId: null,
                            sku: undefined,
                            ...(stockItem(item) ? { accountId: defaultAccount } : {}),
                          });
                          setErrors((x) => ({ ...x, items: undefined }));
                        }}
                        products={inventory.products}
                        onPick={(product) => {
                          const stock = product.kind === 'stock';
                          updateLine(item.id, {
                            productId: product.id,
                            name: product.name,
                            nameAr: product.nameAr ?? '',
                            unit: product.unit,
                            unitId: product.unitId,
                            // Purchase orders print it in the SKU column when the design shows one.
                            sku: product.sku.trim() || undefined,
                            unitPrice: product.costPrice || item.unitPrice,
                            accountId: stock ? inventoryAccount : item.accountId,
                          });
                          setErrors((x) => ({ ...x, items: undefined }));
                        }}
                        formatPrice={(amount) =>
                          formatUnitPrice(
                            amount,
                            company.currency,
                            fmt.locale,
                            company.currencyDisplay ?? 'local',
                          )
                        }
                        priceOf={(product) => product.costPrice ?? 0}
                        stockOf={(product) => (
                          <StockSuggestion inventory={inventory} product={product} />
                        )}
                      />
                      {order ? (
                        <Input
                          aria-label={t('Arabic name of line {number}', { number: index + 1 })}
                          dir="rtl"
                          lang="ar"
                          value={item.nameAr ?? ''}
                          onChange={(e) => updateLine(item.id, { nameAr: e.target.value })}
                          placeholder={t('Name in Arabic (optional)')}
                        />
                      ) : null}
                      {stockItem(item) ? (
                        <StockLineHint
                          inventory={inventory}
                          line={item}
                          lines={doc.items}
                          use={type === 'bill' ? 'receive' : 'sell'}
                          onWarehouseChange={(warehouseId) => updateLine(item.id, { warehouseId })}
                          subWarehouses={!warehouseAccess?.offered || warehouseAccess.manages}
                        />
                      ) : null}
                    </div>
                    <div className="col-span-2 @3xl:col-span-1">
                      <MiniLabel>{t('Qty')}</MiniLabel>
                      <NumberInput
                        aria-label={t('Line {number} quantity', { number: index + 1 })}
                        value={item.quantity}
                        onValueChange={(quantity) => updateLine(item.id, { quantity })}
                      />
                    </div>
                    <div className="col-span-2 @3xl:col-span-1">
                      <MiniLabel>{t('Price')}</MiniLabel>
                      <NumberInput
                        aria-label={t('Line {number} rate', { number: index + 1 })}
                        value={item.unitPrice}
                        onValueChange={(unitPrice) => {
                          updateLine(item.id, { unitPrice });
                          setErrors((x) => ({ ...x, items: undefined }));
                        }}
                      />
                    </div>
                    <div className="col-span-2 @3xl:col-span-1">
                      <MiniLabel>{t('Tax')}</MiniLabel>
                      <TaxSelect
                        value={item.taxes}
                        onChange={(taxes) => updateLine(item.id, { taxes })}
                        rates={taxRates}
                      />
                    </div>
                    <p
                      className="tabular col-span-5 self-center text-end font-medium text-slate-900 @3xl:col-span-1 @3xl:self-start @3xl:pt-2"
                      aria-label={t('Line {number} amount', { number: index + 1 })}
                    >
                      {money(result.lines[index]?.net ?? 0)}
                    </p>
                    <div className="col-span-1 flex justify-end">
                      <Button
                        variant="ghost"
                        size="icon-sm"
                        aria-label={t('Remove line {number}', { number: index + 1 })}
                        disabled={lines.length <= 1}
                        onClick={() => update({ items: doc.items.filter((i) => i.id !== item.id) })}
                      >
                        <Trash2 />
                      </Button>
                    </div>
                  </li>
                ),
              )}
            </ol>
          </div>
          <div className="border-t border-slate-100 px-4 py-3">
            <Button
              variant="outline"
              size="sm"
              onClick={() =>
                update({
                  items: [
                    ...doc.items,
                    {
                      ...newLineItem(lines[lines.length - 1]?.taxes ?? defaultTaxes),
                      accountId: lines[lines.length - 1]?.accountId ?? defaultAccount,
                    },
                  ],
                })
              }
            >
              <Plus /> {t('Add line')}
            </Button>
          </div>
        </Card>

        <div className="grid gap-6 lg:grid-cols-2">
          <Card>
            <CardHeader
              title={t('Attachments')}
              description={
                type === 'bill'
                  ? t('A photo or PDF of the bill you received.')
                  : type === 'vendor_credit'
                    ? t('A photo or PDF of the credit note you received.')
                    : t('Quotes or other files for this order.')
              }
            />
            <CardBody>
              <AttachmentList
                files={attachments.files}
                onAdd={attachments.add}
                onRemove={attachments.remove}
              />
            </CardBody>
          </Card>
          <Card className="-order-1 lg:order-none">
            <CardHeader title={t('Totals')} />
            <CardBody>
              <TotalsPanel
                doc={doc}
                onChange={update}
                result={result}
                taxRates={taxRates}
                showDocumentTaxes={false}
                showLineTaxes
                defaultTaxes={defaultTaxes}
                currencySymbol={symbol}
                money={money}
                percent={fmt.percent}
                taxExempt={documentTaxExempt(doc, vendor)}
                contact={vendor}
              />
            </CardBody>
          </Card>
          <Card className="lg:col-span-2">
            <CardHeader title={order ? t('Notes & terms') : t('Notes')} />
            <CardBody className="space-y-4">
              {order ? (
                <>
                  <Field label={t('Notes')} hint={t('Shown on the document.')}>
                    {(fid) => (
                      <Textarea
                        id={fid}
                        value={doc.notes}
                        onChange={(e) => update({ notes: e.target.value })}
                        rows={2}
                      />
                    )}
                  </Field>
                  <Field label={t('Terms & conditions')}>
                    {(fid) => (
                      <Textarea
                        id={fid}
                        value={doc.terms}
                        onChange={(e) => update({ terms: e.target.value })}
                        rows={3}
                      />
                    )}
                  </Field>
                </>
              ) : null}
              <Field
                label={order ? t('Private notes') : t('Notes')}
                hint={order ? t('Only visible to you, never printed.') : t('Only visible to you.')}
              >
                {(fid) => (
                  <Textarea
                    id={fid}
                    value={doc.privateNotes}
                    onChange={(e) => update({ privateNotes: e.target.value })}
                    rows={2}
                  />
                )}
              </Field>
            </CardBody>
          </Card>
        </div>

        <div className="hidden justify-end border-t border-slate-200 pt-4 lg:flex">{actions}</div>
      </div>

      {vendorDialog.open ? (
        <ClientDialog
          open
          kind="vendor"
          onOpenChange={(open) => setVendorDialog((s) => ({ ...s, open }))}
          company={company}
          initialName={vendorDialog.name}
          onSaved={(saved) => selectVendor(saved.id)}
        />
      ) : null}
    </div>
  );
}

/** New or existing bill, vendor credit or purchase order. */
export default function BillEditorPage({ type }: { type: PurchaseDocumentType }) {
  const { id } = useParams();
  const [searchParams] = useSearchParams();
  const company = useCompany();
  const labels = DOCUMENT_LABELS[type];
  const [state, setState] = useState<{ doc: InvoiceDocument; taxes: TaxLine[] } | 'missing' | null>(
    null,
  );
  const currentCompany = useEffectEvent(() => company);

  // Load once per route, never while the user is editing.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const current = currentCompany();
      const taxes = await loadDefaultTaxes(current);
      let doc: InvoiceDocument | undefined;
      if (id) {
        doc = await db.documents.get(id);
        if (!doc || doc.companyId !== current.id || doc.type !== type) {
          if (!cancelled) setState('missing');
          return;
        }
      } else {
        const vendorId = searchParams.get('client');
        const vendor = vendorId ? await db.clients.get(vendorId) : undefined;
        const expense = (
          await db.accounts.where('[companyId+role]').equals([current.id, 'expense']).first()
        )?.id;
        const draft = await draftDocument(current, type, vendor ?? null);
        doc = {
          ...draft,
          items: draft.items.map((i) => ({ ...i, accountId: expense })),
        };
      }
      if (!cancelled) setState({ doc, taxes });
    })();
    return () => {
      cancelled = true;
    };
  }, [id, type, company.id, searchParams]);

  if (state === 'missing') {
    return (
      <Card className="p-10 text-center">
        <p className="text-slate-600">{t('This document could not be found.')}</p>
        <Link
          to={DOCUMENT_ROUTES[type]}
          className="text-primary-700 mt-4 inline-block text-sm font-medium"
        >
          {t('Back to {list}', { list: t(labels.plural).toLowerCase() })}
        </Link>
      </Card>
    );
  }
  if (!state) return <Spinner className="py-24" label={t('Loading…')} />;
  return (
    <Editor
      key={state.doc.id}
      type={type}
      initial={state.doc}
      isNew={!id}
      defaultTaxes={state.taxes}
    />
  );
}
