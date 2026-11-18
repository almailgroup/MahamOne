import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { db } from '@/db/db';
import { createProduct } from '@/db/defaults';
import { setupCompany } from '@/db/records';
import {
  createWarehouse,
  ensureDefaultWarehouse,
  recordStockEntry,
  saveItem,
  saveWarehouse,
} from '@/db/inventory';
import { issueStock } from '@/db/stock-issues';
import { FakeCloud } from './testing/fake-cloud';
import { FEATURES_RECHECK_MS, startUpload, syncCompany, type SyncContext } from './sync';

/**
 * Items issued to employees and the sync: a server without
 * 20261210000000_warehouse_issues.sql gets neither the issues nor their
 * stock movements (another device would find no source for those and take
 * them out); they wait on the device until it has the file, then go.
 * Invented names only.
 */

const OWNER = 'user-owner';
const BEFORE = [
  'tables_v16',
  'super_admin',
  'approvals',
  'cheque_approvals',
  'change_feed',
  'payroll_approvals',
  'document_alerts',
  'employee_letters',
  'staffing_costings',
  'ai_assistant',
];

let server: FakeCloud;
let ctx: SyncContext;

beforeEach(async () => {
  await db.delete();
  await db.open();
  server = new FakeCloud();
  server.features = [...BEFORE, 'stock_issues'];
  ctx = { api: server.client(OWNER), userId: OWNER };
});

afterEach(() => vi.restoreAllMocks());

const parked = (companyId: string) =>
  db.outbox.where('[companyId+parked]').equals([companyId, 1]).toArray();

describe('a server without the warehouses file', () => {
  it('gets neither the items issued nor their stock movements until it has it; then they go', async () => {
    // Issued in a company kept on this device, then uploaded to an older server.
    const company = await setupCompany({ name: 'Made-up Guarding' });
    const main = await ensureDefaultWarehouse(company.id);
    const store = await saveWarehouse(
      createWarehouse(company.id, { name: 'East store', parentId: main.id }),
    );
    const jacket = await saveItem(
      createProduct(company.id, { name: 'Jacket', kind: 'stock', unit: 'pcs' }),
    );
    await recordStockEntry(company.id, {
      kind: 'opening',
      date: '2026-11-01',
      warehouseId: store.id,
      reference: '',
      notes: '',
      lines: [{ productId: jacket.id, quantity: 5, unitCost: 9 }],
    });
    const { issue } = await issueStock(
      company.id,
      {
        date: '2026-11-03',
        warehouseId: store.id,
        recipient: {
          employeeId: 'emp-1',
          number: 'E-0001',
          name: 'Made-up Guard',
          jobTitle: 'Security Guard',
        },
        lines: [{ productId: jacket.id, quantity: 1 }],
        notes: '',
      },
      { userId: null, name: 'Owner' },
    );
    const movements = await db.stockMovements.where('sourceId').equals(issue!.id).toArray();
    expect(movements).toHaveLength(1);

    server.features = [...BEFORE];
    await startUpload(company.id, ctx);
    await syncCompany(company.id, ctx);
    expect(server.record(company.id, 'stockIssues', issue!.id)).toBeUndefined();
    expect(server.record(company.id, 'stockMovements', movements[0].id)).toBeUndefined();
    // The opening stock is an ordinary entry and goes, with its movement.
    expect(server.rows(company.id, 'stockEntries')).toHaveLength(1);
    expect(server.rows(company.id, 'stockMovements').map((r) => r.data.sourceType)).toEqual([
      'opening',
    ]);
    const waiting = await parked(company.id);
    expect(waiting.every((e) => e.error === 'server_outdated')).toBe(true);
    expect(waiting.map((e) => e.table).sort()).toEqual(['stockIssues', 'stockMovements']);

    // Asked again later, it still hasn't the file: they keep waiting.
    vi.spyOn(Date, 'now').mockReturnValue(Date.now() + FEATURES_RECHECK_MS + 1000);
    await syncCompany(company.id, ctx);
    expect((await parked(company.id)).length).toBe(waiting.length);

    // The owner runs the file.
    server.features = [...BEFORE, 'stock_issues'];
    vi.spyOn(Date, 'now').mockReturnValue(Date.now() + 2 * FEATURES_RECHECK_MS + 2000);
    await syncCompany(company.id, ctx);
    await syncCompany(company.id, ctx);
    expect(server.record(company.id, 'stockIssues', issue!.id)).toMatchObject({
      number: 'ISS-0001',
    });
    expect(server.record(company.id, 'stockMovements', movements[0].id)).toMatchObject({
      sourceType: 'issue',
    });
    expect(await parked(company.id)).toEqual([]);
  });
});
