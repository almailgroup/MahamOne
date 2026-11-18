import { afterEach, describe, expect, it } from 'vitest';
import { loadLanguage } from '@/i18n';
import type { ChangeEvent } from '@/cloud/api';
import {
  describeChange,
  groupChanges,
  MAX_CHANGE_EMAILS_A_DAY,
  notifyDecision,
  type NotifyState,
} from './changes';

afterEach(async () => {
  await loadLanguage('en');
});

let seq = 0;
function change(overrides: Partial<ChangeEvent> = {}): ChangeEvent {
  seq += 1;
  return {
    id: seq,
    at: '2026-10-06T07:00:00.000Z',
    actor: 'user-staff',
    actorName: 'Made-up Staff',
    subjectName: '',
    kind: 'document',
    op: 'update',
    tbl: 'documents',
    recordId: `doc-${seq}`,
    count: 1,
    important: false,
    private: false,
    summary: {},
    unread: true,
    ...overrides,
  };
}

const money = { money: (a: number, c: string) => `${a.toFixed(3)} ${c}`, date: (d: string) => d };

describe('an expiry reminder in Updates (#18)', () => {
  const reminder = (summary: Record<string, unknown>, extra: Partial<ChangeEvent> = {}) =>
    change({
      kind: 'document_expiry',
      actor: null,
      actorName: '',
      tbl: 'complianceDocuments',
      recordId: 'licence',
      summary,
      ...extra,
    });

  it('says what is due, by nobody', () => {
    expect(
      describeChange(
        reminder({ what: 'expiring', type: 'commercial_licence', date: '2026-12-01', title: '' }),
        money,
      ),
    ).toEqual({
      actor: 'Someone in the team',
      text: 'Commercial licence expires on 2026-12-01',
      detail: '',
      important: false,
      named: true,
    });
    expect(
      describeChange(
        reminder({
          what: 'expired',
          type: 'vehicle_registration',
          date: '2026-10-01',
          name: '18/62417',
        }),
        money,
      ).text,
    ).toBe('Vehicle registration · 18/62417 expired on 2026-10-01');
    expect(
      describeChange(reminder({ what: 'noscan', type: 'other', title: 'Site lease' }), money).text,
    ).toBe('Site lease: the new copy is not uploaded yet');
  });

  it("names nobody for an employee's paper or a confidential one", async () => {
    const employee = reminder(
      { what: 'expiring', type: 'residency', date: '2026-10-31', employee: true },
      { private: true, tbl: 'employees', recordId: 'emp-1' },
    );
    expect(describeChange(employee, money).text).toBe(
      'An employee’s residency expires on 2026-10-31',
    );
    expect(
      describeChange(
        reminder({ what: 'expired', type: 'customer_cost', date: '2026-10-01' }, { private: true }),
        money,
      ).text,
    ).toBe('A confidential document expired on 2026-10-01');
    await loadLanguage('ar');
    expect(describeChange(employee, money).text).toBe(
      'تنتهي صلاحية الإقامة لأحد الموظفين في 2026-10-31',
    );
  });
});

describe('a change in words', () => {
  it('says what was done to what, with the customer and the amount', () => {
    const voided = change({
      important: true,
      summary: {
        what: 'voided',
        type: 'invoice',
        number: 'INV-0042',
        total: 120,
        currency: 'KWD',
        client: 'Made-up Hotel',
        clientAr: 'فندق تجريبي',
      },
    });
    expect(describeChange(voided, money)).toEqual({
      actor: 'Made-up Staff',
      text: 'Voided invoice INV-0042',
      detail: 'Made-up Hotel · 120.000 KWD',
      important: true,
    });
    const edited = change({ summary: { what: 'edited', type: 'credit', number: 'CN-7' } });
    expect(describeChange(edited).text).toBe('Edited credit note CN-7 after it was issued');
    const cheque = change({
      tbl: 'payments',
      kind: 'cheque',
      summary: { what: 'returned', cheque: '100200', amount: 250, currency: 'KWD' },
    });
    expect(describeChange(cheque, money)).toMatchObject({
      text: 'Marked cheque 100200 as returned',
      detail: '250.000 KWD',
    });
  });

  it('counts a fold of ordinary changes', () => {
    expect(
      describeChange(change({ tbl: 'clients', kind: 'contact', count: 12, op: 'mixed' })).text,
    ).toBe('12 changes to customers and vendors');
    expect(
      describeChange(change({ count: 3, summary: { what: 'added', type: 'quote' } })).text,
    ).toBe('3 changes to quotes');
  });

  it('names who was changed in the team, and the settings that changed', () => {
    const role = change({
      kind: 'member',
      tbl: 'company_members',
      subjectName: 'Made-up Accountant',
      summary: { reason: 'role', role: 'admin', before: 'accountant' },
    });
    expect(describeChange(role).text).toBe('Made Made-up Accountant admin');
    const left = change({
      kind: 'member',
      tbl: 'company_members',
      actor: 'user-x',
      subjectName: 'Made-up X',
      summary: { reason: 'left', user: 'user-x' },
    });
    expect(describeChange(left)).toMatchObject({ text: 'Made-up X left the team', named: true });
    // Their own role, as they handed the company over: said once.
    const handedOver = change({
      kind: 'member',
      tbl: 'company_members',
      actor: 'user-x',
      subjectName: 'Made-up X',
      summary: { reason: 'role', role: 'admin', before: 'owner', user: 'user-x' },
    });
    expect(describeChange(handedOver)).toMatchObject({
      text: 'Made-up X became admin',
      named: true,
    });
    const joined = change({
      kind: 'member',
      tbl: 'company_members',
      actor: 'user-y',
      subjectName: 'Made-up Y',
      summary: { reason: 'joined', role: 'accountant', user: 'user-y' },
    });
    expect(describeChange(joined)).toMatchObject({
      text: 'Made-up Y joined the team as accountant',
      named: true,
    });
    expect(describeChange(role).named).toBeUndefined();
    const settings = change({
      kind: 'settings',
      tbl: 'companies',
      summary: { what: 'settings', changes: ['lockDate', 'numbering'], lockDate: '2026-09-30' },
    });
    expect(describeChange(settings, money).text).toBe(
      'Moved the lock date to 2026-09-30 · Changed the numbering',
    );
  });

  it('never shows names or amounts of payroll and people data', () => {
    const run = change({
      tbl: 'payRuns',
      kind: 'people',
      private: true,
      important: true,
      summary: { what: 'approved', status: 'approved', period: '2026-10' },
    });
    expect(describeChange(run, money)).toMatchObject({
      text: 'Approved the pay run for 2026-10',
      detail: '',
    });
    // Even a summary that had them would not show them.
    const employee = change({
      tbl: 'employees',
      kind: 'people',
      private: true,
      summary: { what: 'added', name: 'Made-up Person', amount: 900, currency: 'KWD' },
    });
    expect(describeChange(employee, money)).toMatchObject({ text: 'Added employee', detail: '' });
  });

  it('reads in Arabic, with the Arabic names', async () => {
    await loadLanguage('ar');
    const voided = change({
      actorName: '',
      summary: {
        what: 'voided',
        type: 'invoice',
        number: 'INV-1',
        client: 'Made-up Hotel',
        clientAr: 'فندق تجريبي',
      },
    });
    expect(describeChange(voided)).toMatchObject({
      actor: 'أحد أعضاء الفريق',
      text: 'إبطال فاتورة INV-1',
      detail: 'فندق تجريبي',
    });
    expect(describeChange(change({ count: 2, tbl: 'clients', kind: 'contact' })).text).toBe(
      'تغييران على العملاء والموردون',
    );
  });
});

describe('items issued to employees', () => {
  const asked = (what: string) =>
    change({
      tbl: 'approvals',
      kind: 'approval',
      actorName: 'Ahmed Saleh',
      important: true,
      summary: {
        what,
        request: 'stock_issue',
        subject: 'stockIssues',
        number: '',
        status: what === 'requested' ? 'pending' : what,
        name: 'Mohammed Ahmed',
        nameAr: 'محمد أحمد',
        jobTitle: 'Security Guard',
        jobTitleAr: 'حارس أمن',
        items: [
          { quantity: 1, name: 'Trouser', nameAr: 'بنطلون' },
          { quantity: 1, name: 'T-shirt', nameAr: 'قميص' },
          { quantity: 1, name: 'Jacket' },
        ],
      },
    });

  it('says who issued what to whom, waiting for approval, and the decision', () => {
    expect(describeChange(asked('requested'))).toEqual({
      actor: 'Ahmed Saleh',
      text: 'Issued 1 Trouser, 1 T-shirt, 1 Jacket to Mohammed Ahmed (Security Guard), waiting for approval',
      detail: '',
      important: true,
    });
    expect(describeChange(asked('approved')).text).toBe(
      'Confirmed the items issued to Mohammed Ahmed (Security Guard): 1 Trouser, 1 T-shirt, 1 Jacket',
    );
    expect(describeChange(asked('rejected')).text).toBe(
      'Turned down the items to issue to Mohammed Ahmed (Security Guard): 1 Trouser, 1 T-shirt, 1 Jacket',
    );
    const kept = change({
      tbl: 'stockIssues',
      kind: 'item',
      summary: {
        what: 'added',
        number: 'ISS-0001',
        name: 'Mohammed Ahmed',
        items: [{ quantity: 2, name: 'Shoes' }],
      },
    });
    expect(describeChange(kept).text).toBe('Recorded 2 Shoes issued to Mohammed Ahmed');
  });

  it('reads in Arabic, with the Arabic names', async () => {
    await loadLanguage('ar');
    expect(describeChange(asked('requested')).text).toContain('محمد أحمد (حارس أمن)');
    expect(describeChange(asked('requested')).text).toContain('1 بنطلون، 1 قميص، 1 Jacket');
  });
});

describe('the changes of an email, by person', () => {
  it('lists important changes each and counts the rest by kind', () => {
    const groups = groupChanges([
      change({ actor: 'b', actorName: 'B', kind: 'contact', count: 4 }),
      change({ actor: 'a', actorName: 'A', important: true }),
      change({ actor: 'a', actorName: 'A', kind: 'contact', count: 2 }),
      change({ actor: 'a', actorName: 'A', kind: 'contact', count: 1 }),
    ]);
    expect(groups.map((g) => [g.actor, g.important.length, g.others, g.total])).toEqual([
      ['B', 0, [{ kind: 'contact', count: 4 }], 4],
      ['A', 1, [{ kind: 'contact', count: 3 }], 4],
    ]);
  });
});

describe('when to email', () => {
  const state = (overrides: Partial<NotifyState> = {}): NotifyState => ({
    immediateKinds: ['document', 'cheque'],
    digest: 'daily',
    digestOn: null,
    sentOn: null,
    sentCount: 0,
    lastSentMs: null,
    ...overrides,
  });
  const noon = { date: '2026-10-06', hour: 12 };
  const early = { date: '2026-10-06', hour: 7 };
  const now = Date.parse('2026-10-06T09:00:00Z');
  const urgent = [{ important: true, kind: 'document' }];
  const ordinary = [{ important: false, kind: 'contact' }];

  it('sends important changes of the chosen kinds at once', () => {
    expect(notifyDecision(urgent, state(), early, now).send).toBe('immediate');
    expect(notifyDecision(urgent, state({ immediateKinds: ['cheque'] }), early, now).send).toBe(
      null,
    );
    // Not chosen: it waits for the summary.
    expect(notifyDecision(urgent, state({ immediateKinds: [] }), noon, now).send).toBe('daily');
  });

  it('keeps one email every 15 minutes and 20 a day', () => {
    const recent = state({ lastSentMs: now - 10 * 60_000, sentOn: noon.date, sentCount: 1 });
    expect(notifyDecision(urgent, recent, noon, now).send).toBeNull();
    expect(notifyDecision(urgent, recent, noon, now + 5 * 60_000).send).toBe('immediate');
    const full = state({ sentOn: noon.date, sentCount: MAX_CHANGE_EMAILS_A_DAY });
    expect(notifyDecision(urgent, full, noon, now).send).toBeNull();
    // A new day, a new count.
    expect(notifyDecision(urgent, full, { date: '2026-10-07', hour: 0 }, now).send).toBe(
      'immediate',
    );
  });

  it('sums up the rest once a day from 8:00, or lets it go with the summary off', () => {
    expect(notifyDecision(ordinary, state(), early, now)).toEqual({
      send: null,
      letGo: false,
      summaryDone: false,
    });
    expect(notifyDecision(ordinary, state(), noon, now)).toEqual({
      send: 'daily',
      letGo: false,
      summaryDone: true,
    });
    expect(notifyDecision(ordinary, state({ digestOn: noon.date }), noon, now).send).toBeNull();
    expect(notifyDecision(ordinary, state({ digest: 'off' }), noon, now)).toEqual({
      send: null,
      letGo: true,
      summaryDone: true,
    });
  });
});
