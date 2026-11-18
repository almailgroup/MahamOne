import {
  Boxes,
  Shirt,
  ClipboardCheck,
  ClipboardList,
  House,
  Package,
  Receipt,
  Settings,
  ShoppingCart,
  Truck,
  Warehouse,
} from 'lucide-react';
import { CREATE_ACTIONS as A } from '@/features/shell/create';
import { msg } from '@/i18n';
import type { SuiteApp } from '@/suite/types';

/**
 * Maham Inventory (مهام إنفنتوري), in the split layout only
 * (Company.appLayout): items and stock, warehouses, counts and landed costs,
 * taken out of Maham Books, with the purchase orders, bills, vendors and
 * delivery notes that move stock. Purchases stay with Maham Books
 * (finance), and delivery notes with Maham Sales: opened from here they keep
 * this sidebar. The pages are Books' own, at the addresses they have always
 * had. Who opens it, and the owner's limits on it, are Books'
 * (src/suite/apps.ts).
 */
export const INVENTORY: SuiteApp = {
  id: 'inventory',
  name: 'Maham Inventory',
  nameAr: 'مهام إنفنتوري',
  description: msg('Items, stock, warehouses and stock counts.'),
  icon: Boxes,
  tone: 'teal',
  home: '/inventory',
  owns: ['products', 'inventory'],
  shares: ['purchase-orders', 'bills', 'vendors', 'delivery-notes'],
  nav: [
    { kind: 'link', to: '/', label: msg('Home'), icon: House, end: true },
    {
      kind: 'link',
      to: '/inventory',
      label: msg('Stock and warehouses'),
      icon: Warehouse,
      keywords: 'stock on hand adjustments landed costs',
    },
    {
      kind: 'link',
      to: '/inventory/issues',
      label: msg('Issued items'),
      icon: Shirt,
      keywords: 'uniforms custody employees guards sub-warehouse',
    },
    {
      kind: 'link',
      to: '/products',
      label: msg('Products & services'),
      icon: Package,
      keywords: 'items sku labels',
    },
    {
      kind: 'link',
      to: '/inventory/count',
      label: msg('Stock count'),
      icon: ClipboardCheck,
      keywords: 'stocktake',
    },
    {
      kind: 'link',
      to: '/purchase-orders',
      label: msg('Purchase orders'),
      icon: ShoppingCart,
      keywords: 'lpo',
    },
    { kind: 'link', to: '/bills', label: msg('Bills'), icon: Receipt },
    { kind: 'link', to: '/vendors', label: msg('Vendors'), icon: Truck, keywords: 'suppliers' },
    { kind: 'link', to: '/delivery-notes', label: msg('Delivery notes'), icon: ClipboardList },
  ],
  footer: [{ to: '/settings', label: msg('Settings'), icon: Settings }],
  create: [
    {
      label: msg('Inventory'),
      column: 1,
      actions: [A.product, A.stock_adjustment, A.stock_issue],
    },
  ],
  tools: [
    { to: '/inventory', label: msg('Stock and warehouses'), icon: Warehouse, keywords: 'stock' },
    { to: '/inventory/issues', label: msg('Issued items'), icon: Shirt, keywords: 'uniforms' },
    { to: '/products', label: msg('Products & services'), icon: Package, keywords: 'items' },
    { to: '/inventory/count', label: msg('Stock count'), icon: ClipboardCheck },
    { to: '/purchase-orders', label: msg('Purchase orders'), icon: ShoppingCart, keywords: 'lpo' },
  ],
  tabs: [
    { to: '/', label: msg('Home'), icon: House, end: true },
    { to: '/inventory', label: msg('Stock'), icon: Warehouse },
    { to: '/products', label: msg('Products'), icon: Package },
  ],
  // Books' own: these are Books' pages and records.
  access: {
    device: 'manage',
    owner: 'manage',
    admin: 'manage',
    accountant: 'manage',
    staff: 'edit',
    viewer: 'view',
  },
};
