import { lazy } from 'react';
import type { RouteObject } from 'react-router';
import { Bare } from '@/app/route-shell';
import { AppGate } from '@/suite/app-gate';
import type { DocumentType, PurchaseDocumentType } from '@/db/types';

/** Maham Books' pages. Their URLs are the ones they have always had. */

const Dashboard = lazy(() => import('./pages/dashboard'));
const DocumentList = lazy(() => import('./pages/documents/list'));
const DocumentEditor = lazy(() => import('./pages/documents/editor'));
const DocumentView = lazy(() => import('./pages/documents/view'));
const ClientList = lazy(() => import('./pages/clients/list'));
const ClientDetail = lazy(() => import('./pages/clients/detail'));
const ClientFormPage = lazy(() => import('./pages/clients/form'));
const Products = lazy(() => import('./pages/products'));
const ItemLabelsPrint = lazy(() => import('./pages/products/item-labels-print'));
const Inventory = lazy(() => import('./pages/inventory/index'));
const StockEntryForm = lazy(() => import('./pages/inventory/entry-form'));
const StockEntryView = lazy(() => import('./pages/inventory/entry-view'));
const StockIssues = lazy(() => import('./pages/inventory/issues'));
const StockIssueForm = lazy(() => import('./pages/inventory/issue-form'));
const StockIssueView = lazy(() => import('./pages/inventory/issue-view'));
const StockCount = lazy(() => import('./pages/inventory/count'));
const StockCountPrint = lazy(() => import('./pages/inventory/count-print'));
const LandedCostForm = lazy(() => import('./pages/inventory/landed-cost-form'));
const LandedCostView = lazy(() => import('./pages/inventory/landed-cost-view'));
const PaymentList = lazy(() => import('./pages/payments/list'));
const PaymentDetail = lazy(() => import('./pages/payments/detail'));
const PaymentForm = lazy(() => import('./pages/payments/form'));
const PaymentVoucher = lazy(() => import('./pages/payments/voucher'));
const ChequeRegister = lazy(() => import('./pages/cheques/index'));
const ChequeRegisterPrint = lazy(() => import('./pages/cheques/print'));
const ChequePrint = lazy(() => import('./pages/cheques/cheque-print'));
const ChequeLayouts = lazy(() => import('./pages/cheques/layouts'));
const ChequeTestPrint = lazy(() => import('./pages/cheques/test-print'));
const RecurringList = lazy(() => import('./pages/recurring/list'));
const RecurringEditor = lazy(() => import('./pages/recurring/editor'));
const Reports = lazy(() => import('./pages/reports/index'));
const Templates = lazy(() => import('./pages/templates'));
const ChartOfAccounts = lazy(() => import('./pages/accounting/chart'));
const Journals = lazy(() => import('./pages/accounting/journals'));
const JournalEditor = lazy(() => import('./pages/accounting/journal-editor'));
const BillEditor = lazy(() => import('./pages/purchases/bill-editor'));
const BillView = lazy(() => import('./pages/purchases/bill-view'));
const Expenses = lazy(() => import('./pages/purchases/expenses'));
const Vat = lazy(() => import('./pages/accounting/vat'));
const Banking = lazy(() => import('./pages/banking/index'));
const Assets = lazy(() => import('./pages/assets/index'));
const AssetForm = lazy(() => import('./pages/assets/form'));
const AssetDetail = lazy(() => import('./pages/assets/detail'));
const YearEnd = lazy(() => import('./pages/accounting/year-end'));

// Sales documents: one list, editor and page for invoices, quotes, credit
// notes, proforma invoices, sales orders and delivery notes.
const documentRoutes = (path: string, type: Exclude<DocumentType, PurchaseDocumentType>) => [
  { path, element: <DocumentList key={type} type={type} /> },
  { path: `${path}/new`, element: <DocumentEditor key={`${type}-new`} type={type} /> },
  { path: `${path}/:id`, element: <DocumentView key={type} type={type} /> },
  { path: `${path}/:id/edit`, element: <DocumentEditor key={type} type={type} /> },
];

// Bills, vendor credits and purchase orders: the same list as sales documents,
// their own editor and page.
const purchaseRoutes = (path: string, type: PurchaseDocumentType) => [
  { path, element: <DocumentList key={type} type={type} /> },
  { path: `${path}/new`, element: <BillEditor key={`${type}-new`} type={type} /> },
  { path: `${path}/:id`, element: <BillView key={type} type={type} /> },
  { path: `${path}/:id/edit`, element: <BillEditor key={type} type={type} /> },
];

const contactRoutes = (path: string, kind: 'customer' | 'vendor') => [
  { path, element: <ClientList key={kind} kind={kind} /> },
  { path: `${path}/new`, element: <ClientFormPage key={`${kind}-new`} kind={kind} /> },
  { path: `${path}/:id`, element: <ClientDetail key={kind} kind={kind} /> },
  { path: `${path}/:id/edit`, element: <ClientFormPage key={kind} kind={kind} /> },
];

const paymentRoutes = (path: string, direction: 'in' | 'out') => [
  { path, element: <PaymentList key={direction} direction={direction} /> },
  { path: `${path}/new`, element: <PaymentForm key={`${direction}-new`} direction={direction} /> },
  { path: `${path}/:id`, element: <PaymentDetail key={direction} direction={direction} /> },
  { path: `${path}/:id/edit`, element: <PaymentForm key={direction} direction={direction} /> },
];

/**
 * Print views: vouchers, cheques and the cheque register, the count sheet and
 * item labels, without the navigation.
 */
export const booksPrintRoutes: RouteObject[] = [
  {
    path: 'payments/:id/voucher',
    element: (
      <Bare>
        <PaymentVoucher key="in" direction="in" />
      </Bare>
    ),
  },
  {
    path: 'payments-made/:id/voucher',
    element: (
      <Bare>
        <PaymentVoucher key="out" direction="out" />
      </Bare>
    ),
  },
  {
    path: 'expenses/:id/voucher',
    element: (
      <Bare>
        <PaymentVoucher key="expense" direction="out" source="expense" />
      </Bare>
    ),
  },
  {
    path: 'cheques/print',
    element: (
      <Bare>
        <ChequeRegisterPrint />
      </Bare>
    ),
  },
  {
    path: 'payments-made/:id/cheque',
    element: (
      <Bare>
        <ChequePrint />
      </Bare>
    ),
  },
  {
    path: 'cheques/test-print',
    element: (
      <Bare>
        <ChequeTestPrint />
      </Bare>
    ),
  },
  {
    path: 'inventory/count/print',
    element: (
      <Bare>
        <StockCountPrint />
      </Bare>
    ),
  },
  {
    path: 'products/labels',
    element: (
      <Bare>
        <ItemLabelsPrint />
      </Bare>
    ),
  },
];

/**
 * Pages inside the shell, view only for someone the owner limited to that
 * (see AppGate).
 */
export const booksRoutes: RouteObject[] = (
  [
    { path: 'books', element: <Dashboard /> },
    ...documentRoutes('invoices', 'invoice'),
    ...documentRoutes('quotes', 'quote'),
    ...documentRoutes('credits', 'credit'),
    ...documentRoutes('proformas', 'proforma'),
    ...documentRoutes('sales-orders', 'sales_order'),
    ...documentRoutes('delivery-notes', 'delivery_note'),
    { path: 'recurring', element: <RecurringList /> },
    { path: 'recurring/new', element: <RecurringEditor /> },
    { path: 'recurring/:id', element: <RecurringEditor /> },
    ...paymentRoutes('payments', 'in'),
    { path: 'cheques', element: <ChequeRegister /> },
    { path: 'cheques/layouts', element: <ChequeLayouts /> },
    ...contactRoutes('clients', 'customer'),
    ...contactRoutes('vendors', 'vendor'),
    ...purchaseRoutes('bills', 'bill'),
    ...purchaseRoutes('vendor-credits', 'vendor_credit'),
    ...purchaseRoutes('purchase-orders', 'purchase_order'),
    ...paymentRoutes('payments-made', 'out'),
    { path: 'expenses', element: <Expenses /> },
    { path: 'products', element: <Products /> },
    { path: 'inventory', element: <Inventory /> },
    { path: 'inventory/adjustments/new', element: <StockEntryForm /> },
    { path: 'inventory/entries/:id', element: <StockEntryView /> },
    { path: 'inventory/issues', element: <StockIssues /> },
    { path: 'inventory/issues/new', element: <StockIssueForm /> },
    { path: 'inventory/issues/:id', element: <StockIssueView /> },
    { path: 'inventory/count', element: <StockCount /> },
    { path: 'inventory/landed-costs/new', element: <LandedCostForm /> },
    { path: 'inventory/landed-costs/:id', element: <LandedCostView /> },
    { path: 'reports', element: <Reports /> },
    { path: 'reports/:report', element: <Reports /> },
    { path: 'accounts', element: <ChartOfAccounts /> },
    { path: 'journals', element: <Journals /> },
    { path: 'journals/new', element: <JournalEditor key="new" /> },
    { path: 'journals/:id', element: <JournalEditor /> },
    { path: 'assets', element: <Assets /> },
    { path: 'assets/new', element: <AssetForm key="new" /> },
    { path: 'assets/:id', element: <AssetDetail /> },
    { path: 'assets/:id/edit', element: <AssetForm /> },
    { path: 'year-end', element: <YearEnd /> },
    { path: 'banking', element: <Banking /> },
    { path: 'banking/:accountId', element: <Banking /> },
    { path: 'vat', element: <Vat /> },
    { path: 'vat/:start', element: <Vat /> },
    { path: 'templates', element: <Templates /> },
  ] as RouteObject[]
).map((route) => ({ ...route, element: <AppGate app="books">{route.element}</AppGate> }));
