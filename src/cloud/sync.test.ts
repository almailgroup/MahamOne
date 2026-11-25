import { beforeEach, describe, expect, it } from 'vitest';
import { db, DATA_TABLES } from '@/db/db';
import { createClient } from '@/db/defaults';
import { saveClient, setupCompany } from '@/db/records';
import { draftDocument, saveDocument } from '@/db/documents';
import { createPayment, savePayment } from '@/db/payments';
import { addAttachment } from '@/db/purchases';
import { createEmployee, deleteEmployee, saveEmployee } from '@/db/people';
import {
  createComplianceDocument,
  deleteComplianceDocument,
  saveComplianceDocument,
} from '@/db/renewals';
import type { Company, InvoiceDocument } from '@/db/types';
import type { CloudApi, PushChange } from './api';
import { FakeCloud } from './testing/fake-cloud';
import {
  applyRole,
  cleanupFiles,
  deleteFromCloud,
  downloadMissingFiles,
  fetchAttachmentContent,
  isDemoCompany,
  startDownload,
  startUpload,
  syncCompany,
  type SyncContext,
  type SyncProgress,
} from './sync';
import { mergeNumbering, mergeNumberingRule } from './numbering';
import { markRemote } from './outbox';

const OWNER = 'user-owner';
const PNG =
  'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

let server: FakeCloud;
let ctx: SyncContext;

beforeEach(async () => {
  await db.delete();
  await db.open();
  server = new FakeCloud();
  ctx = { api: server.client(OWNER), userId: OWNER };
});

/** A device starting afresh: same account, empty browser. */
async function newDevice(userId = OWNER): Promise<SyncContext> {
  await db.delete();
  await db.open();
  return { api: server.client(userId), userId };
}

async function companyWithInvoice(): Promise<{ company: Company; invoice: InvoiceDocument }> {
  const company = await setupCompany({ name: 'Al Mail Trading' });
  const client = await saveClient(createClient(company.id, { name: 'Gulf Pearl Hotel' }));
  const draft = await draftDocument(company, 'invoice', client);
  draft.items[0] = { ...draft.items[0], name: 'Installation', quantity: 2, unitPrice: 150.25 };
  const invoice = await saveDocument({ ...draft, status: 'sent' });
  return { company: (await db.companies.get(company.id))!, invoice };
}

async function uploaded() {
  const made = await companyWithInvoice();
  await startUpload(made.company.id, ctx);
  await syncCompany(made.company.id, ctx);
  return made;
}

/** Records this device has for the company, by table. */
async function localRecords(companyId: string) {
  const all: Record<string, Record<string, unknown>[]> = {};
  for (const name of DATA_TABLES) {
    const rows =
      name === 'companies'
        ? [await db.companies.get(companyId)]
        : await db.table(name).where('companyId').equals(companyId).toArray();
    all[name] = rows.filter(Boolean) as Record<string, unknown>[];
  }
  return all;
}

/** Records the server keeps for the company, by table. */
function serverRecords(companyId: string) {
  const all: Record<string, Record<string, unknown>[]> = {};
  for (const name of DATA_TABLES) all[name] = server.rows(companyId, name).map((r) => r.data);
  return all;
}

const byId = (rows: Record<string, unknown>[]) =>
  Object.fromEntries(rows.map((r) => [String(r.id), r]));

function spy(api: CloudApi, onPush: (changes: PushChange[]) => void): CloudApi {
  return {
    ...api,
    pushRecords: (company, changes) => {
      onPush(changes);
      return api.pushRecords(company, changes);
    },
  };
}

describe('upload', () => {
  it('copies every record of a company to the cloud in batches, with progress', async () => {
    const { company } = await companyWithInvoice();
    const batches: number[] = [];
    const progress: SyncProgress[] = [];
    ctx = {
      ...ctx,
      api: spy(ctx.api, (changes) => batches.push(changes.length)),
      onProgress: (p) => progress.push(p),
    };
    await startUpload(company.id, ctx);
    const queued = await db.outbox.count();
    expect(queued).toBeGreaterThan(50);
    expect((await db.syncState.get(company.id))?.status).toBe('uploading');
    await syncCompany(company.id, ctx);

    expect(await db.outbox.count()).toBe(0);
    expect((await db.syncState.get(company.id))?.status).toBe('ready');
    expect(Math.max(...batches)).toBeLessThanOrEqual(200);
    expect(batches.reduce((a, b) => a + b, 0)).toBe(queued);
    expect(progress.at(-1)).toMatchObject({ kind: 'upload', done: queued, total: queued });
    const local = await localRecords(company.id);
    const remote = serverRecords(company.id);
    for (const name of DATA_TABLES) {
      expect(byId(remote[name]), name).toEqual(byId(local[name]));
    }
    // Whether the account already has it in the cloud is asked first.
    expect(server.calls.slice(0, 2)).toEqual([`${OWNER} myCompanies`, `${OWNER} createCompany`]);
  });

  it('never takes the demo company to the cloud', async () => {
    const company = await setupCompany({ name: 'Demo' });
    await db.companies.update(company.id, { demo: true });
    await expect(startUpload(company.id, ctx)).rejects.toThrow(
      'The demo company stays on this device.',
    );
    expect(isDemoCompany({ email: 'accounts@rawdat-alkhaleej.example' })).toBe(true);
    expect(server.companies.size).toBe(0);
  });
});

describe('download', () => {
  it('brings a company to another device, storing the company itself last', async () => {
    const { company } = await uploaded();
    const before = serverRecords(company.id);
    const device = await newDevice();
    let companyDuringDownload: unknown = 'not checked';
    let pulls = 0;
    const api = device.api;
    device.pullPage = 40;
    device.api = {
      ...api,
      pullRecords: async (id, since, limit) => {
        pulls += 1;
        if (pulls === 2) companyDuringDownload = await db.companies.get(company.id);
        return api.pullRecords(id, since, limit);
      },
    };
    await startDownload({ id: company.id, name: company.name, role: 'owner' }, device);
    await syncCompany(company.id, device);
    expect(companyDuringDownload).toBeUndefined();
    expect(pulls).toBeGreaterThan(2);
    const local = await localRecords(company.id);
    for (const name of DATA_TABLES) expect(byId(local[name]), name).toEqual(byId(before[name]));
    expect((await db.syncState.get(company.id))?.status).toBe('ready');
    // What came from the cloud is not sent back.
    expect(await db.outbox.count()).toBe(0);
  });

  it('finishes when deletes newer than its first page were purged', async () => {
    // More records than one page, and a delete over 30 days old that the
    // cloud has forgotten. Every page after the first is older than what
    // was purged, and the cloud can't tell such a page from a device that
    // was away, so it answers "resync" to all of them.
    const { company } = await uploaded();
    const owner = server.client(OWNER);
    const item = (id: string) => ({
      tbl: 'products',
      id,
      data: { id, companyId: company.id, name: `Item ${id}`, unitPrice: 1 },
    });
    for (let i = 0; i < 12; i++) await owner.pushRecords(company.id, [item(`p${i}`)]);
    await owner.pushRecords(company.id, [item('gone')]);
    await owner.pushRecords(company.id, [{ tbl: 'products', id: 'gone', deleted: true }]);
    server.purgeMarkers(company.id);
    await owner.pushRecords(company.id, [item('later')]);
    const before = serverRecords(company.id);

    const device = await newDevice();
    device.pullPage = 5;
    await startDownload({ id: company.id, name: company.name, role: 'owner' }, device);
    await syncCompany(company.id, device);
    const local = await localRecords(company.id);
    for (const name of DATA_TABLES) expect(byId(local[name]), name).toEqual(byId(before[name]));
    expect(await db.products.get('gone')).toBeUndefined();
    expect((await db.syncState.get(company.id))?.status).toBe('ready');
    expect(await db.outbox.count()).toBe(0);

    // From then on it pulls as usual, deletes included.
    await owner.pushRecords(company.id, [item('newest')]);
    await owner.pushRecords(company.id, [{ tbl: 'products', id: 'p3', deleted: true }]);
    await syncCompany(company.id, device);
    expect(await db.products.get('newest')).toBeDefined();
    expect(await db.products.get('p3')).toBeUndefined();
  });
});

describe('changes from other devices', () => {
  it('arrive page by page, deletes included, and the cursor moves on', async () => {
    const { company, invoice } = await uploaded();
    const other = server.client(OWNER);
    const client = server.rows(company.id, 'clients')[0].data;
    const extra = Array.from({ length: 5 }, (_, i) => ({
      tbl: 'products',
      id: `p${i}`,
      data: { id: `p${i}`, companyId: company.id, name: `Item ${i}`, unitPrice: 1 },
    }));
    await other.pushRecords(company.id, [
      ...extra,
      {
        tbl: 'clients',
        id: String(client.id),
        data: { ...client, name: 'Gulf Pearl Hotel – Salmiya' },
      },
      { tbl: 'documents', id: invoice.id, deleted: true },
    ]);
    const cursor = (await db.syncState.get(company.id))!.cursor;
    await syncCompany(company.id, ctx);
    expect(await db.products.where('companyId').equals(company.id).count()).toBe(5);
    expect((await db.clients.get(String(client.id)))?.name).toBe('Gulf Pearl Hotel – Salmiya');
    expect(await db.documents.get(invoice.id)).toBeUndefined();
    expect((await db.syncState.get(company.id))!.cursor).toBeGreaterThan(cursor);
    expect(await db.outbox.count()).toBe(0);
  });

  it('never overwrite a change waiting on this device: it is sent, wins and is noted', async () => {
    const { company } = await uploaded();
    const client = (await db.clients.where('companyId').equals(company.id).first())!;
    // Another device renames the client...
    await server
      .client(OWNER)
      .pushRecords(company.id, [
        { tbl: 'clients', id: client.id, data: { ...client, name: 'Their name' }, base_rev: 1 },
      ]);
    // ...while this one, offline, changed the phone number.
    await saveClient({ ...client, phone: '+965 2222 3333' });
    const result = await syncCompany(company.id, ctx);
    expect(result.conflicts).toBe(1);
    const kept = server.record(company.id, 'clients', client.id)!;
    expect(kept.phone).toBe('+965 2222 3333');
    expect((await db.clients.get(client.id))?.phone).toBe('+965 2222 3333');
    const log = await db.activities.filter((a) => a.action === 'sync_conflict').toArray();
    expect(log).toHaveLength(1);
    expect(log[0].message).toContain('The version saved on this device was kept.');
  });

  it('bring back a record deleted elsewhere while it was changed here', async () => {
    const { company } = await uploaded();
    const client = (await db.clients.where('companyId').equals(company.id).first())!;
    await server
      .client(OWNER)
      .pushRecords(company.id, [{ tbl: 'clients', id: client.id, deleted: true }]);
    await saveClient({ ...client, notes: 'Still a customer' });
    await syncCompany(company.id, ctx);
    expect(await db.clients.get(client.id)).toBeDefined();
    expect(server.record(company.id, 'clients', client.id)?.notes).toBe('Still a customer');
  });

  it('keep document numbers from the cloud even when the company has unsent changes', async () => {
    const { company } = await uploaded();
    const remote = server.record(company.id, 'companies', company.id)!;
    const numbering = remote.numbering as Company['numbering'];
    await server.client(OWNER).pushRecords(company.id, [
      {
        tbl: 'companies',
        id: company.id,
        data: {
          ...remote,
          numbering: { ...numbering, invoice: { ...numbering.invoice, next: 40 } },
        },
      },
    ]);
    // A change here to the company that is not sent yet (offline).
    await db.companies.update(company.id, { phone: '+965 2200 0000' });
    server.offline = true;
    await expect(syncCompany(company.id, ctx)).rejects.toMatchObject({ code: 'offline' });
    server.offline = false;
    await syncCompany(company.id, ctx);
    const local = (await db.companies.get(company.id))!;
    expect(local.numbering.invoice.next).toBe(40);
    expect(local.phone).toBe('+965 2200 0000');
    expect(server.record(company.id, 'companies', company.id)?.phone).toBe('+965 2200 0000');
  });
});

describe('when things go wrong', () => {
  it('keeps every change while offline and sends them later', async () => {
    const { company } = await uploaded();
    server.offline = true;
    await saveClient(createClient(company.id, { name: 'Made offline' }));
    const waiting = await db.outbox.count();
    await expect(syncCompany(company.id, ctx)).rejects.toMatchObject({ code: 'offline' });
    expect(await db.outbox.count()).toBe(waiting);
    expect((await db.syncState.get(company.id))?.lastError).toBe('offline');
    server.offline = false;
    await syncCompany(company.id, ctx);
    expect(await db.outbox.count()).toBe(0);
    expect(server.rows(company.id, 'clients').map((r) => r.data.name)).toContain('Made offline');
  });

  it('parks a change the server refuses and sends the rest', async () => {
    const { company } = await uploaded();
    // The server knows better: this person is staff now.
    server.addMember(company.id, OWNER, 'staff');
    const account = (await db.accounts.where('companyId').equals(company.id).first())!;
    await db.accounts.put({ ...account, name: 'Renamed by staff' });
    await saveClient(createClient(company.id, { name: 'Allowed for staff' }));
    const result = await syncCompany(company.id, ctx);
    expect(result.parked).toBe(1);
    const parked = await db.outbox.where('[companyId+parked]').equals([company.id, 1]).toArray();
    expect(parked).toEqual([
      expect.objectContaining({ table: 'accounts', id: account.id, error: 'permission' }),
    ]);
    expect(server.rows(company.id, 'clients').map((r) => r.data.name)).toContain(
      'Allowed for staff',
    );
    expect(server.record(company.id, 'accounts', account.id)?.name).toBe(account.name);
  });

  it('retries on a server error without losing anything', async () => {
    const { company } = await uploaded();
    await saveClient(createClient(company.id, { name: 'Later' }));
    server.failNext('pushRecords', 'server');
    await expect(syncCompany(company.id, ctx)).rejects.toMatchObject({
      code: 'server',
      retryable: true,
    });
    await syncCompany(company.id, ctx);
    expect(server.rows(company.id, 'clients').map((r) => r.data.name)).toContain('Later');
  });

  it('stops syncing a company the person no longer belongs to', async () => {
    const { company } = await uploaded();
    server.members.get(company.id)!.delete(OWNER);
    await expect(syncCompany(company.id, ctx)).rejects.toMatchObject({ code: 'not_member' });
    expect((await db.syncState.get(company.id))?.status).toBe('removed');
    // Its copy stays, read only, until the person decides.
    await expect(saveClient(createClient(company.id, { name: 'X' }))).rejects.toThrow(
      'This company is no longer shared with you',
    );
  });
});

describe('full resync', () => {
  it('keeps only what the cloud still has (and unsent changes), then brings in the rest', async () => {
    const { company } = await uploaded();
    const clients = await db.clients.where('companyId').equals(company.id).toArray();
    const gone = await saveClient(createClient(company.id, { name: 'Deleted elsewhere' }));
    await syncCompany(company.id, ctx);
    // Long ago, another device deleted it and the cloud forgot the delete.
    await server
      .client(OWNER)
      .pushRecords(company.id, [{ tbl: 'clients', id: gone.id, deleted: true }]);
    await server.client(OWNER).pushRecords(company.id, [
      {
        tbl: 'products',
        id: 'new-item',
        data: { id: 'new-item', companyId: company.id, name: 'New', unitPrice: 1 },
      },
    ]);
    server.purgeMarkers(company.id);
    // Meanwhile this device made a change it has not sent.
    const mine = await saveClient(createClient(company.id, { name: 'Made here' }));
    server.offline = true;
    await expect(syncCompany(company.id, ctx)).rejects.toBeDefined();
    server.offline = false;
    // Pretend the device was last in sync long ago.
    await db.syncState.update(company.id, { cursor: 1 });
    await syncCompany(company.id, ctx);

    expect(await db.clients.get(gone.id)).toBeUndefined();
    expect(await db.clients.get(mine.id)).toBeDefined();
    expect(server.record(company.id, 'clients', mine.id)).toBeDefined();
    expect(await db.products.get('new-item')).toBeDefined();
    for (const client of clients) expect(await db.clients.get(client.id)).toBeDefined();
    // And the next sync is an ordinary one.
    const calls = server.calls.length;
    await syncCompany(company.id, ctx);
    expect(server.calls.slice(calls).some((c) => c.endsWith('recordIds'))).toBe(false);
  });
});

describe('files', () => {
  const PNG =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

  it('go to Storage, and the record carries only where they are', async () => {
    const { company, invoice } = await uploaded();
    const file = await addAttachment(company.id, invoice.id, {
      name: 'receipt.png',
      type: 'image/png',
      dataUrl: PNG,
    });
    await syncCompany(company.id, ctx);
    const path = `${company.id}/${file.id}`;
    expect(server.files.has(path)).toBe(true);
    const remote = server.record(company.id, 'attachments', file.id)!;
    expect(remote).toMatchObject({ dataUrl: '', storagePath: path });
    expect(String(remote.contentHash)).toMatch(/^[0-9a-f]{64}$/);
    const local = (await db.attachments.get(file.id))!;
    expect(local).toMatchObject({
      dataUrl: PNG,
      storagePath: path,
      contentHash: remote.contentHash,
    });
    // Syncing again does not upload it again.
    const uploads = server.calls.filter((c) => c.endsWith('uploadFile')).length;
    await db.attachments.update(file.id, { name: 'receipt-1.png' });
    await syncCompany(company.id, ctx);
    expect(server.calls.filter((c) => c.endsWith('uploadFile')).length).toBe(uploads);

    // Another device gets the small ones with the sync, large ones when opened.
    const device = await newDevice();
    await startDownload({ id: company.id, name: company.name, role: 'owner' }, device);
    await syncCompany(company.id, device);
    expect((await db.attachments.get(file.id))?.dataUrl).toBe('');
    // Marked, so missing files are found without reading every file; the
    // mark stays on this device.
    expect((await db.attachments.get(file.id))?.contentMissing).toBe(1);
    await db.attachments.update(file.id, { name: 'receipt-2.png' });
    await syncCompany(company.id, device);
    expect(server.record(company.id, 'attachments', file.id)).toMatchObject({
      name: 'receipt-2.png',
      dataUrl: '',
      storagePath: path,
    });
    expect(server.record(company.id, 'attachments', file.id)).not.toHaveProperty('contentMissing');
    await downloadMissingFiles(company.id, device, 10);
    expect((await db.attachments.get(file.id))?.dataUrl).toBe('');
    await downloadMissingFiles(company.id, device, 1_000_000);
    expect((await db.attachments.get(file.id))?.dataUrl).toBe(PNG);
    expect(await db.attachments.get(file.id)).not.toHaveProperty('contentMissing');
    await db.transaction('rw', db.attachments, async () => {
      markRemote();
      await db.attachments.update(file.id, { dataUrl: '' });
    });
    expect(await fetchAttachmentContent((await db.attachments.get(file.id))!, device)).toBe(PNG);
    expect(await db.outbox.count()).toBe(0);
  });

  it('are removed from Storage with their record, and retried until they are', async () => {
    const { company, invoice } = await uploaded();
    const a = await addAttachment(company.id, invoice.id, {
      name: 'a.png',
      type: 'image/png',
      dataUrl: PNG,
    });
    const b = await addAttachment(company.id, invoice.id, {
      name: 'b.png',
      type: 'image/png',
      dataUrl: PNG,
    });
    await syncCompany(company.id, ctx);
    await db.attachments.delete(a.id);
    await syncCompany(company.id, ctx);
    expect(server.files.has(`${company.id}/${a.id}`)).toBe(false);
    expect(server.record(company.id, 'attachments', a.id)).toBeUndefined();

    server.storageDown = true;
    await db.attachments.delete(b.id);
    await syncCompany(company.id, ctx);
    expect(server.record(company.id, 'attachments', b.id)).toBeUndefined();
    expect(server.files.has(`${company.id}/${b.id}`)).toBe(true);
    expect(await db.fileQueue.toArray()).toEqual([
      expect.objectContaining({ path: `${company.id}/${b.id}`, attempts: 1 }),
    ]);
    await syncCompany(company.id, ctx);
    expect((await db.fileQueue.toArray())[0].attempts).toBe(2);
    server.storageDown = false;
    await syncCompany(company.id, ctx);
    expect(await db.fileQueue.count()).toBe(0);
    expect(server.files.has(`${company.id}/${b.id}`)).toBe(false);
  });

  it('can be added and removed by staff, who never reach an employee’s scan', async () => {
    const STAFF = 'user-staff';
    const { company, invoice } = await uploaded();
    const employee = await saveEmployee(createEmployee(company.id, { name: 'Rajesh Kumar' }));
    const scan = await addAttachment(company.id, employee.id, {
      name: 'civil-id.png',
      type: 'image/png',
      dataUrl: PNG,
    });
    await syncCompany(company.id, ctx);
    const scanPath = `${company.id}/${scan.id}`;
    expect(server.files.has(scanPath)).toBe(true);

    server.addMember(company.id, STAFF, 'staff');
    const staff = await newDevice(STAFF);
    await startDownload({ id: company.id, name: company.name, role: 'staff' }, staff);
    await syncCompany(company.id, staff);
    expect(await db.attachments.get(scan.id)).toBeUndefined();

    // A receipt: the file goes up before its record, then both are there.
    const receipt = await addAttachment(company.id, invoice.id, {
      name: 'receipt.png',
      type: 'image/png',
      dataUrl: PNG,
    });
    await syncCompany(company.id, staff);
    const path = `${company.id}/${receipt.id}`;
    expect(server.files.get(path)?.owner).toBe(STAFF);
    expect(server.record(company.id, 'attachments', receipt.id)).toMatchObject({
      storagePath: path,
    });
    expect(await db.outbox.count()).toBe(0);

    // Deleted: the record goes, then the file, with nothing left to retry.
    await db.attachments.delete(receipt.id);
    await syncCompany(company.id, staff);
    expect(server.record(company.id, 'attachments', receipt.id)).toBeUndefined();
    expect(server.files.has(path)).toBe(false);
    expect(await db.fileQueue.count()).toBe(0);

    // The employee's scan stays out of reach.
    await expect(staff.api.downloadFile(scanPath)).rejects.toMatchObject({ code: 'invalid' });
    await expect(
      staff.api.uploadFile(scanPath, new Blob(['x']), 'image/png'),
    ).rejects.toMatchObject({ code: 'permission' });
    await staff.api.removeFiles([scanPath]);
    expect(server.files.has(scanPath)).toBe(true);
    expect((await staff.api.listFiles(company.id)).map((f) => f.path)).not.toContain(scanPath);
  });

  it('keep activity about an employee’s document from staff once the document is deleted', async () => {
    const STAFF = 'user-staff';
    const { company } = await uploaded();
    const employee = await saveEmployee(createEmployee(company.id, { name: 'Test Guard Eleven' }));
    const licence = await saveComplianceDocument(
      createComplianceDocument(company.id, {
        type: 'driving_licence',
        ownerType: 'employee',
        employeeId: employee.id,
        expiryDate: '2027-01-31',
      }),
    );
    await deleteComplianceDocument(licence.id);
    const about = await db.activities.where('entityId').equals(licence.id).toArray();
    const deleted = about.find((a) => a.action === 'deleted')!;
    expect(deleted).toMatchObject({ message: 'Document Driving licence deleted' });
    expect(about.every((a) => a.employeeId === employee.id)).toBe(true);
    await syncCompany(company.id, ctx);
    expect(server.record(company.id, 'activities', deleted.id)?._private).toBe(true);

    server.addMember(company.id, STAFF, 'staff');
    const staff = await newDevice(STAFF);
    await startDownload({ id: company.id, name: company.name, role: 'staff' }, staff);
    await syncCompany(company.id, staff);
    const seen = await db.activities.where('companyId').equals(company.id).toArray();
    expect(seen.length).toBeGreaterThan(0);
    expect(seen.filter((a) => a.entityId === licence.id)).toEqual([]);
    expect(JSON.stringify(seen)).not.toContain('Driving licence');
  });

  it('left behind are cleaned up, except those still on their way', async () => {
    const { company } = await uploaded();
    const hour = 60 * 60 * 1000;
    server.files.set(`${company.id}/orphan`, {
      blob: new Blob(['x']),
      createdAt: new Date(Date.now() - 2 * hour).toISOString(),
      owner: OWNER,
    });
    server.files.set(`${company.id}/arriving`, {
      blob: new Blob(['x']),
      createdAt: new Date().toISOString(),
      owner: 'user-staff',
    });
    expect(await cleanupFiles(company.id, ctx)).toBe(1);
    expect([...server.files.keys()]).toEqual([`${company.id}/arriving`]);
  });
});

describe('derived data', () => {
  it('works out balances again after a payment made on another device', async () => {
    const { company, invoice } = await uploaded();
    const payment = createPayment(company.id, {
      clientId: invoice.clientId,
      amount: 300.5,
      date: invoice.issueDate,
      allocations: [{ documentId: invoice.id, amount: 300.5 }],
      documentIds: [invoice.id],
      number: 'PAY-0001',
    });
    // The other device's payment arrives without the invoice's new balance.
    await server
      .client(OWNER)
      .pushRecords(company.id, [
        { tbl: 'payments', id: payment.id, data: payment as unknown as Record<string, unknown> },
      ]);
    await syncCompany(company.id, ctx);
    const local = (await db.documents.get(invoice.id))!;
    expect(local.status).toBe('paid');
    expect(local.totals.balance).toBe(0);
    // ...and the corrected invoice goes to the cloud for everyone.
    expect(server.record(company.id, 'documents', invoice.id)?.status).toBe('paid');
  });

  it('agrees on the same stock movements on every device', async () => {
    const { company } = await uploaded();
    await savePayment(
      createPayment(company.id, {
        clientId: (await db.clients.where('companyId').equals(company.id).first())!.id,
        amount: 10,
        date: '2026-10-01',
        allocations: [],
      }),
    );
    await syncCompany(company.id, ctx);
    expect(await db.outbox.count()).toBe(0);
    // A second sync with nothing new sends nothing: the work done after a pull is stable.
    const pushes = server.calls.filter((c) => c.endsWith('pushRecords')).length;
    await syncCompany(company.id, ctx);
    expect(server.calls.filter((c) => c.endsWith('pushRecords')).length).toBe(pushes);
  });
});

describe('roles', () => {
  it('take payroll and people data off a device whose role no longer sees them', async () => {
    const { company } = await uploaded();
    await saveEmployee(createEmployee(company.id, { name: 'Rajesh Kumar', basicSalary: 450 }));
    await syncCompany(company.id, ctx);
    await applyRole(company.id, 'staff');
    expect(await db.employees.where('companyId').equals(company.id).count()).toBe(0);
    expect(
      await db.activities
        .where('companyId')
        .equals(company.id)
        .filter((a) => a.entity === 'employee')
        .count(),
    ).toBe(0);
    // Nothing of it is deleted in the cloud.
    expect(await db.outbox.count()).toBe(0);
    expect(server.rows(company.id, 'employees')).toHaveLength(1);
    // Promoted again: everything comes back.
    server.addMember(company.id, OWNER, 'accountant');
    await applyRole(company.id, 'accountant');
    await syncCompany(company.id, ctx);
    expect(await db.employees.where('companyId').equals(company.id).count()).toBe(1);
  });
});

describe('deleting an employee', () => {
  it('removes them, their documents, renewals, files and activity from the cloud too', async () => {
    const { company } = await uploaded();
    const employee = await saveEmployee(createEmployee(company.id, { name: 'Rajesh Kumar' }));
    const licence = await saveComplianceDocument(
      createComplianceDocument(company.id, {
        type: 'driving_licence',
        ownerType: 'employee',
        employeeId: employee.id,
      }),
    );
    const files = [
      await addAttachment(company.id, employee.id, {
        name: 'c.png',
        type: 'image/png',
        dataUrl: PNG,
      }),
      await addAttachment(company.id, licence.id, {
        name: 'l.png',
        type: 'image/png',
        dataUrl: PNG,
      }),
    ];
    await syncCompany(company.id, ctx);
    expect(server.rows(company.id, 'employees')).toHaveLength(1);
    expect(server.files.size).toBe(2);
    // Files of employees are marked private for the server.
    expect(server.record(company.id, 'attachments', files[0].id)?._private).toBe(true);

    await deleteEmployee(employee.id);
    await syncCompany(company.id, ctx);

    expect(server.rows(company.id, 'employees')).toHaveLength(0);
    expect(server.rows(company.id, 'complianceDocuments')).toHaveLength(0);
    expect(server.rows(company.id, 'attachments')).toHaveLength(0);
    expect(server.files.size).toBe(0);
    const activity = server.rows(company.id, 'activities').map((r) => r.data);
    expect(JSON.stringify(activity)).not.toContain('Rajesh');
    expect(activity.filter((a) => a.entityId === employee.id)).toEqual([
      expect.objectContaining({ action: 'deleted', messageVars: { number: employee.number } }),
    ]);
    expect(await db.outbox.count()).toBe(0);
  });
});

describe('deleting a company in the cloud', () => {
  it('removes its files, then the company, then this device’s copy', async () => {
    const { company, invoice } = await uploaded();
    await addAttachment(company.id, invoice.id, {
      name: 'r.png',
      type: 'image/png',
      dataUrl: 'data:image/png;base64,AAAA',
    });
    await syncCompany(company.id, ctx);
    expect(server.files.size).toBe(1);
    await deleteFromCloud(company.id, ctx);
    expect(server.files.size).toBe(0);
    expect(server.companies.has(company.id)).toBe(false);
    expect(await db.companies.get(company.id)).toBeUndefined();
    expect(await db.syncState.count()).toBe(0);
    expect(await db.outbox.count()).toBe(0);
  });

  it('stops if a file cannot be removed, keeping the company', async () => {
    const { company, invoice } = await uploaded();
    await addAttachment(company.id, invoice.id, {
      name: 'r.png',
      type: 'image/png',
      dataUrl: 'data:image/png;base64,AAAA',
    });
    await syncCompany(company.id, ctx);
    server.storageDown = true;
    await expect(deleteFromCloud(company.id, ctx)).rejects.toMatchObject({ code: 'server' });
    expect(server.companies.has(company.id)).toBe(true);
    expect(await db.companies.get(company.id)).toBeDefined();
  });
});

describe('document numbers', () => {
  const rule = (
    next: number,
    period = '2026',
    reset: 'yearly' | 'never' | 'monthly' = 'yearly',
  ) => ({
    pattern: 'INV-{counter}',
    next,
    padding: 4,
    reset,
    period,
  });

  it('never go back', () => {
    expect(mergeNumberingRule(rule(10), rule(8))?.next).toBe(10);
    expect(mergeNumberingRule(rule(8), rule(10))?.next).toBe(10);
    expect(mergeNumberingRule(rule(40, '2026'), rule(2, '2027'))).toMatchObject({
      next: 2,
      period: '2027',
    });
    expect(mergeNumberingRule(rule(2, '2027'), rule(41, '2026'))).toMatchObject({
      next: 2,
      period: '2027',
    });
    // A new reset is a settings change: taken as sent.
    expect(mergeNumberingRule(rule(9, '2026'), rule(1, '', 'never'))).toMatchObject({
      next: 1,
      reset: 'never',
    });
    expect(mergeNumbering({ invoice: rule(5) }, { quote: rule(3) })).toEqual({
      invoice: rule(5),
      quote: rule(3),
    });
  });
});
