import type { LucideIcon } from 'lucide-react';
import {
  Armchair,
  ArrowDownLeft,
  ArrowUpRight,
  Calculator,
  ClipboardList,
  FileClock,
  FileMinus,
  FileText,
  IdCard,
  MailPlus,
  NotebookPen,
  Package,
  PackageCheck,
  PackagePlus,
  Receipt,
  ReceiptText,
  Repeat,
  ScrollText,
  Shirt,
  ShoppingCart,
  Truck,
  Users,
  Wallet,
} from 'lucide-react';
import { msg } from '@/i18n';

/** Something that can be created from the New menu, the phone's + sheet or the palette. */
export interface CreateAction {
  id: string;
  /** Menu label, e.g. "Invoice". */
  label: string;
  /** Palette label, e.g. "New invoice". */
  command: string;
  to: string;
  icon: LucideIcon;
  keywords?: string;
  /** Offered only while manpower costing is in effect (#3): available, and switched on. */
  costingOnly?: boolean;
}

export interface CreateGroup {
  label: string;
  actions: CreateAction[];
}

/**
 * Everything that can be created, by id. Apps list them in their manifests'
 * groups (src/apps/<app>/manifest.ts); an action listed by two apps (a quote,
 * in Books and in CRM) shows once.
 */
export const CREATE_ACTIONS = {
  invoice: {
    id: 'invoice',
    label: msg('Invoice'),
    command: msg('New invoice'),
    to: '/invoices/new',
    icon: FileText,
  },
  quote: {
    id: 'quote',
    label: msg('Quote'),
    command: msg('New quote'),
    to: '/quotes/new',
    icon: ScrollText,
    keywords: 'estimate',
  },
  proforma: {
    id: 'proforma',
    label: msg('Proforma invoice'),
    command: msg('New proforma invoice'),
    to: '/proformas/new',
    icon: FileClock,
  },
  sales_order: {
    id: 'sales_order',
    label: msg('Sales order'),
    command: msg('New sales order'),
    to: '/sales-orders/new',
    icon: ClipboardList,
  },
  delivery_note: {
    id: 'delivery_note',
    label: msg('Delivery note'),
    command: msg('New delivery note'),
    to: '/delivery-notes/new',
    icon: PackageCheck,
  },
  credit: {
    id: 'credit',
    label: msg('Credit note'),
    command: msg('New credit note'),
    to: '/credits/new',
    icon: FileMinus,
  },
  recurring: {
    id: 'recurring',
    label: msg('Recurring invoice'),
    command: msg('New recurring invoice'),
    to: '/recurring/new',
    icon: Repeat,
  },
  payment_in: {
    id: 'payment_in',
    label: msg('Payment received'),
    command: msg('Record payment received'),
    to: '/payments/new',
    icon: ArrowDownLeft,
    keywords: 'receipt cheque knet',
  },
  bill: {
    id: 'bill',
    label: msg('Bill'),
    command: msg('New bill'),
    to: '/bills/new',
    icon: Receipt,
  },
  expense: {
    id: 'expense',
    label: msg('Expense'),
    command: msg('Record expense'),
    to: '/expenses?new=1',
    icon: Wallet,
  },
  purchase_order: {
    id: 'purchase_order',
    label: msg('Purchase order'),
    command: msg('New purchase order'),
    to: '/purchase-orders/new',
    icon: ShoppingCart,
    keywords: 'lpo',
  },
  payment_out: {
    id: 'payment_out',
    label: msg('Payment made'),
    command: msg('Record payment made'),
    to: '/payments-made/new',
    icon: ArrowUpRight,
  },
  vendor_credit: {
    id: 'vendor_credit',
    label: msg('Vendor credit'),
    command: msg('New vendor credit'),
    to: '/vendor-credits/new',
    icon: ReceiptText,
  },
  client: {
    id: 'client',
    label: msg('Client'),
    command: msg('New client'),
    to: '/clients/new',
    icon: Users,
    keywords: 'customer',
  },
  vendor: {
    id: 'vendor',
    label: msg('Vendor'),
    command: msg('New vendor'),
    to: '/vendors/new',
    icon: Truck,
    keywords: 'supplier',
  },
  product: {
    id: 'product',
    label: msg('Product or service'),
    command: msg('New product or service'),
    to: '/products?new=1',
    icon: Package,
    keywords: 'item',
  },
  employee: {
    id: 'employee',
    label: msg('Employee'),
    command: msg('New employee'),
    to: '/employees/new',
    icon: IdCard,
  },
  // Employee letters (#19): the Letters page says when they are off.
  letter: {
    id: 'letter',
    label: msg('Employee letter'),
    command: msg('New employee letter'),
    to: '/people/letters?new=1',
    icon: MailPlus,
    keywords: 'salary certificate experience employment warning noc',
  },
  // Manpower costing (#3): offered once it is on (and the cloud has it).
  costing: {
    id: 'costing',
    label: msg('Manpower costing'),
    command: msg('New manpower costing'),
    to: '/people/costing?new=1',
    icon: Calculator,
    keywords: 'quotation pricing guards cleaners rate card manpower',
    costingOnly: true,
  },
  journal: {
    id: 'journal',
    label: msg('Manual journal'),
    command: msg('New manual journal'),
    to: '/journals/new',
    icon: NotebookPen,
  },
  asset: {
    id: 'asset',
    label: msg('Fixed asset'),
    command: msg('New fixed asset'),
    to: '/assets/new',
    icon: Armchair,
  },
  stock_adjustment: {
    id: 'stock_adjustment',
    label: msg('Stock adjustment'),
    command: msg('New stock adjustment'),
    to: '/inventory/adjustments/new',
    icon: PackagePlus,
  },
  stock_issue: {
    id: 'stock_issue',
    label: msg('Items to an employee'),
    command: msg('Issue items to an employee'),
    to: '/inventory/issues/new',
    icon: Shirt,
    keywords: 'uniform custody guard',
  },
} satisfies Record<string, CreateAction>;
