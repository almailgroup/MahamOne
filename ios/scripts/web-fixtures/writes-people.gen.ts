// The web's own outputs for the People and payroll write ports (MahamKit/Write/People):
// employees, departments, People and payroll settings, leave reasons, leave records
// and openings, staff loans, pay runs (with salary approval), final settlements,
// letters and their templates, and manpower costings. Every name and amount is
// invented. From the repository root:
//   npx vitest run --config ios/scripts/web-fixtures/writes.gen.config.mjs writes-people
import { vi } from 'vitest';
vi.mock('@/lib/ids', async (load) => ({
  ...(await load<typeof import('@/lib/ids')>()),
  ...(await import('./writes-ids')).fixedIds(),
}));
import { scenario, writeFixtures, type Scenario } from './writes-harness';
import { db } from '@/db/db';
import { setupCompany } from '@/db/records';
import {
  addDepartment,
  addDepartmentsInUse,
  assignDepartment,
  createEmployee,
  deleteEmployee,
  getPeopleSettings,
  mergeDepartment,
  newAllowance,
  removeEmployeePhoto,
  saveEmployee,
  savePeopleSettings,
  setDepartmentArchived,
  setEmployeePhoto,
  setGroupSearch,
  setLeaveOpening,
  updateDepartment,
} from '@/db/people';
import { setLeaveOpeningForEveryone, setLeaveOpeningsFromSheet } from '@/db/leave-openings';
import {
  approvePayRun,
  cancelLeaveRecord,
  cancelStaffLoan,
  createLeaveRecord,
  createPayRun,
  createStaffLoan,
  deletePayRun,
  getPayrollSettings,
  payPayRun,
  paySettlement,
  postSettlement,
  refreshPayRun,
  reopenPayRun,
  reverseSettlement,
  saveLeaveReasonSettings,
  saveLeaveRecord,
  savePayrollSettings,
  saveStaffLoan,
  settlementDefaults,
  settlementSetup,
  undoPayRunPayment,
  updateLeaveReasons,
  updatePayLine,
  updatePayRun,
} from '@/db/payroll';
import { requestPayrollApproval } from '@/db/payroll-approvals';
import {
  deleteLetterDraft,
  draftFromTemplate,
  issueLetter,
  markLettersPrinted,
  newTemplate,
  requestLetterIssue,
  restoreDefaultWording,
  saveLetterDraft,
  saveTemplate,
  setLettersOn,
  setTemplateArchived,
  voidLetter,
} from '@/db/letters';
import {
  deleteCosting,
  newCosting,
  saveCosting,
  saveCostingSettings,
  setCostingStatus,
  setCostingsOn,
} from '@/db/costings';
import { defaultTemplateId } from '@/lib/hr/letter-templates';
import { newPost } from '@/lib/hr/costing';
import type { Company, Employee, LeaveReason, PayRun, StaffingCosting } from '@/db/types';

const NOW = '2026-11-28T09:00:00.000Z';
const IBAN = 'KW81CBKU0000000000001234560101';

/** What the seeds made, for the actions and the inputs. */
let C = '';
let K: Employee;
let X: Employee;

interface Input {
  fn: string;
  args: Record<string, unknown>;
  /** The person's link to the company as the action starts (\`db.syncState\`, not in the dumped tables). */
  link?: unknown;
}

const out: Scenario[] = [];

/** A scenario: `seed` builds what it starts from, `act` fills in the input and runs the web's function. */
async function add(
  name: string,
  options: {
    seed?: () => Promise<void>;
    userId?: string;
    userName?: string;
    role?: string;
    now?: string;
  },
  fn: string,
  act: (args: Record<string, unknown>) => Promise<unknown>,
): Promise<void> {
  const input: Input = { fn, args: {} };
  out.push(
    await scenario(
      name,
      {
        now: options.now ?? NOW,
        seed: options.seed,
        input,
        userId: options.userId,
        userName: options.userName,
        role: options.role,
      },
      async () => {
        input.link = (await db.syncState.get(C)) ?? null;
        return act(input.args);
      },
    ),
  );
}

/* -------------------------------------------------------------------------- */
/* Seeds                                                                      */
/* -------------------------------------------------------------------------- */

async function company(): Promise<Company> {
  const c = await setupCompany({ name: 'Sample Trading' });
  C = c.id;
  // Only the accounts payroll posts to and pays from, to keep the fixtures small.
  const kept = new Set(['1000', '1010', '1320', '2300', '2310', '2320', '2700', '4500', '6010', '6020', '6030', '6040', '6050']);
  const others = (await db.accounts.toArray()).filter((a) => !kept.has(a.code)).map((a) => a.id);
  await db.accounts.bulkDelete(others);
  return c;
}

/** A Kuwaiti hired in 2019 (KD 3,000 a month) and an expatriate who joined on 16 September 2026. */
async function staff(): Promise<void> {
  await company();
  K = await saveEmployee(
    createEmployee(C, {
      name: 'Sample Kuwaiti',
      nameAr: 'موظف كويتي',
      category: 'kuwaiti',
      nationality: 'KW',
      hireDate: '2019-01-01',
      basicSalary: 2600,
      allowances: [newAllowance({ name: 'Social allowance', amount: 400 })],
      iban: IBAN,
      jobTitle: 'Manager',
      department: 'Head Office',
    }),
  );
  X = await saveEmployee(
    createEmployee(C, {
      name: 'Sample Expat',
      category: 'expat',
      nationality: 'IN',
      hireDate: '2026-09-16',
      basicSalary: 450,
      allowances: [newAllowance({ name: 'Housing', amount: 60, countsForEos: false })],
      iban: IBAN,
      jobTitle: 'Guard',
      department: 'Security',
    }),
  );
}

async function setCompany(change: (c: Company) => Company): Promise<void> {
  const c = (await db.companies.get(C))!;
  await db.companies.put(change(c));
}

async function runOf(period: string): Promise<PayRun> {
  return (await db.payRuns.toArray()).find((r) => r.period === period)!;
}

/** The cloud link of a member of the company, with the server's features. */
async function link(role: string, userId: string, approver = false): Promise<void> {
  await db.syncState.put({
    companyId: C,
    userId,
    role,
    status: 'ready',
    cursor: 1,
    name: 'Sample Trading',
    linkedAt: '2026-11-01T09:00:00.000Z',
    lastSyncAt: null,
    lastError: null,
    lastErrorAt: null,
    features: ['payroll_approvals', 'employee_letters', 'staffing_costings'],
    approver,
  } as never);
}

const REASONS: LeaveReason[] = [
  { id: 'r-emergency', name: ' Emergency leave ', nameAr: 'إجازة طارئة', base: 'unpaid', pay: 'full', maxDaysPerYear: 6.555 },
  { id: 'r-half', name: 'Study leave', nameAr: 'إجازة دراسية', base: 'bereavement', pay: 'half', noteRequired: true },
  { id: 'r-comp', name: 'Days in lieu', nameAr: 'أيام بدل', base: 'unpaid', pay: 'balance', categories: ['expat', 'expat', 'nobody' as never] },
  { id: 'r-annual', name: 'Travel', nameAr: 'سفر', base: 'unpaid', pay: 'annual', maxDaysPerYear: 0 },
];

async function reasonsOn(): Promise<void> {
  await saveLeaveReasonSettings(C, { leaveReasons: REASONS, leaveReasonsOn: true });
}

/** September's pay run, approved. */
async function september(): Promise<PayRun> {
  return approvePayRun((await createPayRun(C, '2026-09')).id);
}

async function lettersOn(): Promise<void> {
  await setLettersOn(C, true);
}

/** A template of the company's own that prints nothing the platform's country names decide. */
async function ownTemplate(language: 'ar' | 'en' | 'ar-en' = 'ar-en') {
  const tpl = newTemplate(C, 'custom');
  return saveTemplate({
    ...tpl,
    name: ' Bank letter ',
    nameAr: 'خطاب للبنك',
    language,
    subjectEn: 'Salary letter {letter.number}',
    subjectAr: 'خطاب راتب {letter.number}',
    bodyEn:
      '{letter.addressee}\r\n\r\n\r\n\r\n{employee.title} {employee.name} ({employee.number}) works for {company.name} as {employee.jobTitle} in {employee.department}   \nsince {employee.hireDate}, for {service.length}.\nSalary: {salary.basic} + {salary.allowances} = {salary.total} ({salary.totalWords})\nDated {letter.date}. {letter.purpose} {unknown.field}',
    bodyAr:
      '{letter.addressee}\n\nيعمل {employee.title} {employee.name} ({employee.number}) لدى {company.name} بوظيفة {employee.jobTitle} في {employee.department}\nمنذ {employee.hireDate}، مدة {service.length}.\nالراتب: {salary.total} ({salary.totalWords})\nبتاريخ {letter.date}.',
    signatoryName: ' Sample Signatory ',
    signatoryTitle: 'HR manager',
    showStamp: false,
    autoOn: ['joining', 'joining', 'nothing' as never],
  });
}

async function draftFor(employee: Employee, language: 'ar' | 'en' | 'ar-en' = 'ar-en') {
  const tpl = await ownTemplate(language);
  return saveLetterDraft({
    ...draftFromTemplate(tpl, employee.id),
    addressee: 'Sample Bank',
    purpose: '  a loan  ',
  });
}

/* -------------------------------------------------------------------------- */
/* Scenarios                                                                  */
/* -------------------------------------------------------------------------- */

it('people and payroll writes', async () => {
  // ---------------------------------------------------------------- employees
  {
    let input: Employee;
    await add(
      'a new employee gets the next number, and amounts to the fils',
      {
        seed: async () => {
          await company();
          input = createEmployee(C, {
            name: '  Sample Person ',
            nameAr: ' شخص ',
            jobTitle: ' Clerk ',
            department: ' Admin ',
            civilId: '2900 1011 2345',
            iban: 'kw81 cbku 0000 0000 0000 1234 5601 01',
            accountNumber: '١٢٣-٤٥ 6',
            phone: '9999 1234',
            email: ' person@example.com ',
            basicSalary: 450.1234,
            permitSalary: -5,
            birthDate: '',
            gender: 'other' as never,
            allowances: [
              newAllowance({ name: ' Transport ', amount: 25.0005 }),
              newAllowance({ name: '', amount: 0 }),
            ],
            contractType: 'unlimited',
            contractEnd: '2027-01-01',
            stateless: true,
          });
        },
      },
      'saveEmployee',
      async (args) => {
        args.employee = input;
        await saveEmployee(input);
      },
    );
  }
  await add(
    'an employee changed',
    { seed: staff },
    'saveEmployee',
    async (args) => {
      const changed = { ...X, basicSalary: 475, jobTitle: 'Senior guard', annualLeaveDays: 45.555, annualLeaveDaysFrom: '2026-10-01' };
      args.employee = changed;
      args.expectedUpdatedAt = X.updatedAt;
      await saveEmployee(changed, { expectedUpdatedAt: X.updatedAt });
    },
  );
  await add(
    'an employee marked as left, today',
    { seed: staff },
    'saveEmployee',
    async (args) => {
      const changed = { ...X, status: 'left' as const, leavingDate: null, leavingReason: 'resignation' as const };
      args.employee = changed;
      await saveEmployee(changed);
    },
  );
  await add('refused: no name', { seed: staff }, 'saveEmployee', async (args) => {
    const changed = { ...X, name: '   ' };
    args.employee = changed;
    await saveEmployee(changed);
  });
  await add('refused: a number already used', { seed: staff }, 'saveEmployee', async (args) => {
    const changed = { ...X, number: K.number.toLowerCase() };
    args.employee = changed;
    await saveEmployee(changed);
  });
  await add('refused: changed somewhere else', { seed: staff }, 'saveEmployee', async (args) => {
    args.employee = X;
    args.expectedUpdatedAt = '2020-01-01T00:00:00.000Z';
    await saveEmployee(X, { expectedUpdatedAt: '2020-01-01T00:00:00.000Z' });
  });
  await add('refused: fewer than 30 days of leave a year', { seed: staff }, 'saveEmployee', async (args) => {
    const changed = { ...X, annualLeaveDays: 25 };
    args.employee = changed;
    await saveEmployee(changed);
  });
  await add('own leave days removed, and their date with them', { seed: staff }, 'saveEmployee', async (args) => {
    const changed = { ...X, annualLeaveDays: 0, annualLeaveDaysFrom: '2026-10-01', stateless: true };
    args.employee = changed;
    await saveEmployee(changed);
  });
  await add(
    'leave brought forward',
    { seed: staff, userId: 'u-owner', userName: 'Sample Owner' },
    'setLeaveOpening',
    async (args) => {
      Object.assign(args, { employeeId: X.id, date: '2026-10-01', days: 3.456 });
      await setLeaveOpening(X.id, { date: '2026-10-01', days: 3.456 });
    },
  );
  await add('refused: leave brought forward without days', { seed: staff }, 'setLeaveOpening', async (args) => {
    Object.assign(args, { employeeId: X.id, date: '2026-10-01', days: -1 });
    await setLeaveOpening(X.id, { date: '2026-10-01', days: -1 });
  });
  await add(
    'a photo given, replacing the one before',
    {
      seed: async () => {
        await staff();
        await setEmployeePhoto(X.id, { name: 'old.png', dataUrl: 'data:image/jpeg;base64,AAAA' });
      },
    },
    'setEmployeePhoto',
    async (args) => {
      Object.assign(args, { employeeId: X.id, name: 'Portrait.HEIC', dataUrl: 'data:image/jpeg;base64,/9j/4AAQSkZJRg==' });
      await setEmployeePhoto(X.id, { name: 'Portrait.HEIC', dataUrl: 'data:image/jpeg;base64,/9j/4AAQSkZJRg==' });
    },
  );
  await add(
    'a photo removed',
    {
      seed: async () => {
        await staff();
        await setEmployeePhoto(X.id, { name: 'old.jpg', dataUrl: 'data:image/jpeg;base64,AAAA' });
      },
    },
    'removeEmployeePhoto',
    async (args) => {
      args.employeeId = X.id;
      await removeEmployeePhoto(X.id);
    },
  );
  await add(
    'an employee deleted with their file',
    {
      seed: async () => {
        await staff();
        await setEmployeePhoto(X.id, { name: 'p.jpg', dataUrl: 'data:image/jpeg;base64,AAAA' });
      },
    },
    'deleteEmployee',
    async (args) => {
      args.id = X.id;
      await deleteEmployee(X.id);
    },
  );
  await add(
    'refused: deleting an employee with payroll history',
    {
      seed: async () => {
        await staff();
        await saveLeaveRecord(createLeaveRecord(C, X.id, { type: 'unpaid', start: '2026-11-01', end: '2026-11-02' }));
      },
    },
    'deleteEmployee',
    async (args) => {
      args.id = X.id;
      await deleteEmployee(X.id);
    },
  );

  // -------------------------------------------------------------- departments
  await add('a department added', { seed: staff }, 'addDepartment', async (args) => {
    Object.assign(args, { name: '  Head   Office ', nameAr: ' الإدارة ' });
    await addDepartment(C, { name: '  Head   Office ', nameAr: ' الإدارة ' });
  });
  await add(
    'departments added from the employees',
    {
      seed: async () => {
        await staff();
        await saveEmployee(createEmployee(C, { name: 'Sample Third', department: 'security ', hireDate: '2026-01-01' }));
        await saveEmployee(createEmployee(C, { name: 'Sample Fourth', department: 'Security', hireDate: '2026-01-01' }));
        await addDepartment(C, { name: 'Head Office', nameAr: 'الإدارة' });
      },
    },
    'addDepartmentsInUse',
    async () => {
      await addDepartmentsInUse(C);
    },
  );
  await add(
    'a department renamed, with its employees',
    {
      seed: async () => {
        await staff();
        await addDepartment(C, { name: 'Security', nameAr: 'الأمن' });
      },
    },
    'updateDepartment',
    async (args) => {
      const id = (await getPeopleSettings(C)).departments![0].id;
      Object.assign(args, { id, name: 'Guarding', nameAr: 'الحراسة' });
      await updateDepartment(C, id, { name: 'Guarding', nameAr: 'الحراسة' });
    },
  );
  await add(
    'refused: a department name already used',
    {
      seed: async () => {
        await staff();
        await addDepartment(C, { name: 'Security', nameAr: 'الأمن' });
        await addDepartment(C, { name: 'Head Office', nameAr: 'الإدارة' });
      },
    },
    'updateDepartment',
    async (args) => {
      const id = (await getPeopleSettings(C)).departments![0].id;
      Object.assign(args, { id, name: 'Security', nameAr: 'الإدارة' });
      await updateDepartment(C, id, { name: 'Security', nameAr: 'الإدارة' });
    },
  );
  await add(
    'a department archived',
    {
      seed: async () => {
        await staff();
        await addDepartment(C, { name: 'Security', nameAr: 'الأمن' });
      },
    },
    'setDepartmentArchived',
    async (args) => {
      const id = (await getPeopleSettings(C)).departments![0].id;
      Object.assign(args, { id, archived: true });
      await setDepartmentArchived(C, id, true);
    },
  );
  await add(
    'a spelling merged into a department',
    {
      seed: async () => {
        await staff();
        await addDepartment(C, { name: 'Head Office', nameAr: 'الإدارة' });
      },
    },
    'mergeDepartment',
    async (args) => {
      const id = (await getPeopleSettings(C)).departments![0].id;
      Object.assign(args, { from: ' security', intoId: id });
      await mergeDepartment(C, ' security', id);
    },
  );
  await add(
    'employees put in a department',
    {
      seed: async () => {
        await staff();
        await addDepartment(C, { name: 'Finance', nameAr: 'المالية' });
      },
    },
    'assignDepartment',
    async (args) => {
      Object.assign(args, { employeeIds: [K.id, X.id, 'missing'], name: 'المالية' });
      await assignDepartment(C, [K.id, X.id, 'missing'], 'المالية');
    },
  );

  // ------------------------------------------------------------ People settings
  await add('People settings saved, tidy', { seed: staff }, 'savePeopleSettings', async (args) => {
    const settings = {
      ...(await getPeopleSettings(C)),
      kuwaitizationTarget: 33.333,
      eosDailyDivisor: 30.4,
      reminderDays: [7, 30, 30, -1, 90, 60, 14, 3],
      auditFilingMonths: 0,
      pifssDueDay: 40,
      reminderDaysByType: { passport: [180, 90, 30], residency: [] },
      expiredRepeatDays: 7,
      newCopyGraceDays: 14,
      letters: true,
      groupSearch: true,
    };
    args.settings = settings;
    await savePeopleSettings(settings);
  });
  await add('the search across companies turned on', { seed: staff }, 'setGroupSearch', async (args) => {
    args.on = true;
    await setGroupSearch(C, true);
  });

  // ----------------------------------------------------------- payroll settings
  await add('payroll settings saved, tidy', { seed: staff }, 'savePayrollSettings', async (args) => {
    const settings = {
      ...(await getPayrollSettings(C)),
      dailyDivisor: 30.6,
      rateBase: 'other' as never,
      pifss: [
        { from: '2027-01-01', employer: 12.34567, employee: 120, cap: 3000.0004 },
        { from: '2026-01-01', employer: 11.5, employee: 10.5, cap: 0 },
        { from: 'bad', employer: 1, employee: 1, cap: 1 },
      ],
      gcc: [
        { country: 'sa', employer: 12, employee: 10, cap: 45000 },
        { country: 'XX', employer: 1, employee: 1, cap: null },
      ],
      minimumWage: 75.12345,
      payDay: 45,
      accounts: { salaries: '', nothing: 'x' } as never,
      pamFileNumber: ' 12/345 ',
      salaryFile: { preset: 'custom', columns: ['iban', 'amount', 'iban', 'nothing' as never], header: false, periodFormat: 'yyyy-mm' as const },
      leaveAccrualPause: { from: 'never' },
    };
    args.settings = settings;
    await savePayrollSettings(settings);
  });
  await add('a leave policy saved', { seed: staff }, 'savePayrollSettings', async (args) => {
    const settings = {
      ...(await getPayrollSettings(C)),
      leavePolicy: {
        annualDays: [
          { from: '2027-01-01', days: 45.555 },
          { from: '2026-07-01', days: 40 },
          { from: 'someday', days: 50 },
        ],
        firstYearMonths: 12,
        carryForwardMax: 0,
        counting: 'calendar' as const,
      },
    };
    args.settings = settings;
    await savePayrollSettings(settings);
  });
  await add('refused: a leave policy under 30 days', { seed: staff }, 'savePayrollSettings', async (args) => {
    const settings = {
      ...(await getPayrollSettings(C)),
      leavePolicy: { annualDays: [{ from: '2026-07-01', days: 25 }], firstYearMonths: 9, carryForwardMax: null, counting: 'working' as const },
    };
    args.settings = settings;
    await savePayrollSettings(settings);
  });
  await add(
    'refused: changing how annual leave is counted once recorded',
    {
      seed: async () => {
        await staff();
        await saveLeaveRecord(createLeaveRecord(C, X.id, { start: '2026-11-01', end: '2026-11-04' }));
      },
    },
    'savePayrollSettings',
    async (args) => {
      const settings = {
        ...(await getPayrollSettings(C)),
        leavePolicy: { annualDays: [{ from: '2026-07-01', days: 30 }], firstYearMonths: 9, carryForwardMax: null, counting: 'calendar' as const },
      };
      args.settings = settings;
      await savePayrollSettings(settings);
    },
  );
  await add('leave reasons switched on', { seed: staff }, 'saveLeaveReasonSettings', async (args) => {
    const changes = { leaveReasons: REASONS, leaveReasonsOn: true, leaveAccrualPause: { from: '2026-01-01' } };
    args.changes = changes;
    await saveLeaveReasonSettings(C, changes);
  });
  await add(
    'refused: a reason leave is recorded with taken off the list',
    {
      seed: async () => {
        await staff();
        await reasonsOn();
        await saveLeaveRecord(createLeaveRecord(C, X.id, { reasonId: 'r-emergency', start: '2026-11-01', end: '2026-11-02' }));
      },
    },
    'updateLeaveReasons',
    async (args) => {
      const reasons = (await getPayrollSettings(C)).leaveReasons!.filter((r) => r.id !== 'r-emergency');
      args.reasons = reasons;
      await updateLeaveReasons(C, () => reasons);
    },
  );
  await add(
    'a reason archived',
    { seed: async () => { await staff(); await reasonsOn(); } },
    'updateLeaveReasons',
    async (args) => {
      const reasons = (await getPayrollSettings(C)).leaveReasons!.map((r) => (r.id === 'r-half' ? { ...r, archived: true } : r));
      args.reasons = reasons;
      await updateLeaveReasons(C, () => reasons);
    },
  );

  // -------------------------------------------------------------------- leave
  {
    let record: ReturnType<typeof createLeaveRecord>;
    await add(
      'unpaid leave in calendar days, a holiday included',
      {
        seed: async () => {
          await staff();
          await setCompany((c) => ({ ...c, holidays: [{ date: '2026-10-06', name: 'Bridge day', nameAr: 'يوم عطلة' }] }));
          record = createLeaveRecord(C, X.id, { type: 'unpaid', start: '2026-10-04', end: '2026-10-08', notes: ' visit ' });
        },
        userId: 'u-owner',
      },
      'saveLeaveRecord',
      async (args) => {
        args.record = record;
        await saveLeaveRecord(record);
      },
    );
    await add(
      'sick leave in working days, without the holiday',
      {
        seed: async () => {
          await staff();
          await setCompany((c) => ({ ...c, holidays: [{ date: '2026-10-06', name: 'Bridge day', nameAr: 'يوم عطلة' }] }));
          record = createLeaveRecord(C, K.id, { type: 'sick', start: '2026-10-01', end: '2026-10-25' });
        },
      },
      'saveLeaveRecord',
      async (args) => {
        args.record = record;
        await saveLeaveRecord(record);
      },
    );
    await add(
      'refused: leave on weekends only',
      { seed: async () => { await staff(); record = createLeaveRecord(C, X.id, { start: '2026-10-09', end: '2026-10-10' }); } },
      'saveLeaveRecord',
      async (args) => {
        args.record = record;
        await saveLeaveRecord(record);
      },
    );
    await add(
      'refused: the last day before the first',
      { seed: async () => { await staff(); record = createLeaveRecord(C, X.id, { start: '2026-10-09', end: '2026-10-01' }); } },
      'saveLeaveRecord',
      async (args) => {
        args.record = record;
        await saveLeaveRecord(record);
      },
    );
    await add(
      'an opening balance replaces leave brought forward nobody confirmed',
      {
        seed: async () => {
          await staff();
          await db.employees.put({ ...X, leaveOpening: { date: '2026-09-16', days: 0, confirmed: false } });
          record = createLeaveRecord(C, X.id, { kind: 'opening', start: '2026-10-01', end: '2026-10-09', days: 4.567 });
        },
      },
      'saveLeaveRecord',
      async (args) => {
        args.record = record;
        await saveLeaveRecord(record);
      },
    );
    await add(
      'days added by hand to a reason paid from them',
      { seed: async () => { await staff(); await reasonsOn(); record = createLeaveRecord(C, X.id, { kind: 'adjustment', reasonId: 'r-comp', start: '2026-11-01', days: 2 }); } },
      'saveLeaveRecord',
      async (args) => {
        args.record = record;
        await saveLeaveRecord(record);
      },
    );
    await add(
      'leave on half pay of a reason',
      {
        seed: async () => {
          await staff();
          await reasonsOn();
          record = createLeaveRecord(C, X.id, { type: 'sick', reasonId: 'r-half', start: '2026-11-01', end: '2026-11-05', notes: 'Exams', payPercent: 10 });
        },
      },
      'saveLeaveRecord',
      async (args) => {
        args.record = record;
        await saveLeaveRecord(record);
      },
    );
    await add(
      'refused: a reason that needs a note',
      { seed: async () => { await staff(); await reasonsOn(); record = createLeaveRecord(C, X.id, { reasonId: 'r-half', start: '2026-11-01', end: '2026-11-05' }); } },
      'saveLeaveRecord',
      async (args) => {
        args.record = record;
        await saveLeaveRecord(record);
      },
    );
    await add(
      'refused: a reason not for the employee’s category',
      { seed: async () => { await staff(); await reasonsOn(); record = createLeaveRecord(C, K.id, { kind: 'adjustment', reasonId: 'r-comp', start: '2026-11-01', days: 1 }); } },
      'saveLeaveRecord',
      async (args) => {
        args.record = record;
        await saveLeaveRecord(record);
      },
    );
    await add(
      'refused: leave that changes an approved pay run',
      {
        seed: async () => {
          await staff();
          await september();
          record = createLeaveRecord(C, X.id, { type: 'unpaid', start: '2026-09-20', end: '2026-09-22' });
        },
      },
      'saveLeaveRecord',
      async (args) => {
        args.record = record;
        await saveLeaveRecord(record);
      },
    );
    await add(
      'leave cancelled',
      {
        seed: async () => {
          await staff();
          record = await saveLeaveRecord(createLeaveRecord(C, X.id, { type: 'unpaid', start: '2026-11-01', end: '2026-11-03' }));
        },
      },
      'cancelLeaveRecord',
      async (args) => {
        args.id = record.id;
        await cancelLeaveRecord(record.id);
      },
    );
  }
  await add(
    'the same leave brought forward for everyone who needs it',
    {
      seed: async () => {
        await staff();
        await saveEmployee(createEmployee(C, { name: 'Sample Old Hand', hireDate: '2015-03-01', basicSalary: 300 }));
      },
    },
    'setLeaveOpeningForEveryone',
    async (args) => {
      Object.assign(args, { date: '2026-10-01', days: 12.5 });
      await setLeaveOpeningForEveryone(C, { date: '2026-10-01', days: 12.5 });
    },
  );
  await add(
    'each one’s leave brought forward from a spreadsheet',
    {
      seed: async () => {
        await staff();
        await saveLeaveRecord(createLeaveRecord(C, X.id, { kind: 'opening', start: '2026-10-15', days: 2 }));
      },
    },
    'setLeaveOpeningsFromSheet',
    async (args) => {
      const entries = [
        { employeeId: X.id, date: '2026-10-01', days: 7.25 },
        { employeeId: K.id, date: '2026-09-30', days: 20 },
        { employeeId: 'missing', date: '2026-09-30', days: 1 },
      ];
      args.entries = entries;
      await setLeaveOpeningsFromSheet(C, entries);
    },
  );

  // -------------------------------------------------------------------- loans
  {
    let loan: ReturnType<typeof createStaffLoan>;
    await add(
      'a loan paid from the bank',
      { seed: async () => { await staff(); loan = createStaffLoan(C, K.id, { date: '2026-09-05', amount: 500.0004, instalment: 200, firstPeriod: '2026-09', notes: ' car ' }); } },
      'saveStaffLoan',
      async (args) => {
        args.loan = loan;
        await saveStaffLoan(loan);
      },
    );
    await add(
      'a loan whose staff advances account was deleted makes it again',
      {
        seed: async () => {
          await staff();
          const advances = (await db.accounts.toArray()).find((a) => a.code === '1320')!;
          await db.accounts.put({ ...advances, code: '1320', archived: true });
          loan = createStaffLoan(C, X.id, { date: '2026-11-02', amount: 90, instalment: 30, firstPeriod: '2026-12' });
        },
        userId: 'u-owner',
        userName: 'Sample Owner',
      },
      'saveStaffLoan',
      async (args) => {
        args.loan = loan;
        await saveStaffLoan(loan);
      },
    );
    await add(
      'a loan’s instalment changed',
      {
        seed: async () => {
          await staff();
          const saved = await saveStaffLoan(createStaffLoan(C, K.id, { date: '2026-09-05', amount: 500, instalment: 200, firstPeriod: '2026-09' }));
          loan = { ...saved, amount: 9999, instalment: 125.5, firstPeriod: '2026-10', notes: ' later ' };
        },
      },
      'saveStaffLoan',
      async (args) => {
        args.loan = loan;
        await saveStaffLoan(loan);
      },
    );
    await add(
      'refused: an instalment over the loan',
      { seed: async () => { await staff(); loan = createStaffLoan(C, K.id, { date: '2026-09-05', amount: 100, instalment: 200, firstPeriod: '2026-09' }); } },
      'saveStaffLoan',
      async (args) => {
        args.loan = loan;
        await saveStaffLoan(loan);
      },
    );
    await add(
      'refused: a loan in the locked period',
      {
        seed: async () => {
          await staff();
          await setCompany((c) => ({ ...c, accounting: { ...c.accounting!, lockDate: '2026-09-30' } }));
          loan = createStaffLoan(C, K.id, { date: '2026-09-05', amount: 100, instalment: 20, firstPeriod: '2026-10' });
        },
      },
      'saveStaffLoan',
      async (args) => {
        args.loan = loan;
        await saveStaffLoan(loan);
      },
    );
    await add(
      'a loan cancelled',
      { seed: async () => { await staff(); loan = await saveStaffLoan(createStaffLoan(C, X.id, { amount: 100, instalment: 50, date: '2026-09-20' })); } },
      'cancelStaffLoan',
      async (args) => {
        args.id = loan.id;
        await cancelStaffLoan(loan.id);
      },
    );
    await add(
      'refused: cancelling a loan partly recovered',
      {
        seed: async () => {
          await staff();
          loan = await saveStaffLoan(createStaffLoan(C, K.id, { date: '2026-09-05', amount: 500, instalment: 200, firstPeriod: '2026-09' }));
          await september();
        },
      },
      'cancelStaffLoan',
      async (args) => {
        args.id = loan.id;
        await cancelStaffLoan(loan.id);
      },
    );
  }

  // ----------------------------------------------------------------- pay runs
  await add('a pay run prepared', { seed: staff, userId: 'u-owner', userName: 'Sample Owner' }, 'createPayRun', async (args) => {
    args.period = '2026-09';
    await createPayRun(C, '2026-09');
  });
  await add(
    'a pay run with leave, loans, a stateless employee and pay day 25',
    {
      seed: async () => {
        await staff();
        await savePayrollSettings({ ...(await getPayrollSettings(C)), payDay: 25 });
        await setCompany((c) => ({ ...c, holidays: [{ date: '2026-10-06', name: 'Bridge day', nameAr: 'يوم عطلة' }] }));
        await saveLeaveRecord(createLeaveRecord(C, X.id, { type: 'unpaid', start: '2026-10-04', end: '2026-10-08' }));
        await saveLeaveRecord(createLeaveRecord(C, K.id, { type: 'sick', start: '2026-10-01', end: '2026-10-25' }));
        await saveStaffLoan(createStaffLoan(C, K.id, { date: '2026-09-05', amount: 500, instalment: 200, firstPeriod: '2026-09' }));
        await saveEmployee(
          createEmployee(C, {
            name: 'Sample Stateless',
            category: 'expat',
            stateless: true,
            nationality: '',
            civilId: '',
            centralCardNumber: 'RC-2041',
            department: ' Security ',
            hireDate: '2020-01-01',
            basicSalary: 300,
            iban: '',
            accountNumber: '12345678',
          }),
        );
        await saveEmployee(createEmployee(C, { name: 'Sample Leaver', hireDate: '2020-01-01', basicSalary: 400, status: 'left', leavingDate: '2026-10-10' }));
        await saveEmployee(createEmployee(C, { name: 'Sample Gone', hireDate: '2020-01-01', basicSalary: 400, status: 'left', leavingDate: '2026-09-10' }));
      },
    },
    'createPayRun',
    async (args) => {
      args.period = '2026-10';
      await createPayRun(C, '2026-10');
    },
  );
  await add(
    'a pay run with the company’s reasons, half pay and from annual leave',
    {
      seed: async () => {
        await staff();
        await reasonsOn();
        await saveLeaveRecord(createLeaveRecord(C, X.id, { reasonId: 'r-half', start: '2026-10-04', end: '2026-10-08', notes: 'Exams' }));
        await saveLeaveRecord(createLeaveRecord(C, X.id, { reasonId: 'r-annual', start: '2026-10-11', end: '2026-10-12' }));
        await saveLeaveRecord(createLeaveRecord(C, K.id, { reasonId: 'r-emergency', start: '2026-10-13', end: '2026-10-13' }));
      },
    },
    'createPayRun',
    async (args) => {
      args.period = '2026-10';
      await createPayRun(C, '2026-10');
    },
  );
  await add(
    'a whole month of unpaid leave: the PIFSS share is owed',
    {
      seed: async () => {
        await staff();
        await saveLeaveRecord(createLeaveRecord(C, K.id, { type: 'unpaid', start: '2026-09-01', end: '2026-09-30' }));
      },
    },
    'createPayRun',
    async (args) => {
      args.period = '2026-09';
      await createPayRun(C, '2026-09');
    },
  );
  await add('refused: a second pay run for the month', { seed: async () => { await staff(); await createPayRun(C, '2026-09'); } }, 'createPayRun', async (args) => {
    args.period = '2026-09';
    await createPayRun(C, '2026-09');
  });
  await add('refused: a month nobody was paid in', { seed: staff }, 'createPayRun', async (args) => {
    args.period = '2018-12';
    await createPayRun(C, '2018-12');
  });
  await add(
    'a line changed: overtime, absence, an addition and a deduction',
    { seed: async () => { await staff(); await createPayRun(C, '2026-09'); } },
    'updatePayLine',
    async (args) => {
      const run = await runOf('2026-09');
      const line = run.lines[1];
      const changes = {
        overtime: { normal: 2, restDay: 1.005, holiday: -3 },
        absentDays: 99,
        adjustments: [
          { id: '', type: 'deduction' as const, amount: 5.0006, note: ' Uniform ' },
          { id: 'keep', type: 'other' as never, amount: 12.5, note: '' },
          { id: '', type: 'addition' as const, amount: 0, note: '' },
        ],
      };
      Object.assign(args, { runId: run.id, lineId: line.id, changes });
      await updatePayLine(run.id, line.id, changes);
    },
  );
  await add(
    'a loan recovery changed on a line',
    {
      seed: async () => {
        await staff();
        await saveStaffLoan(createStaffLoan(C, K.id, { date: '2026-09-05', amount: 500, instalment: 200, firstPeriod: '2026-09' }));
        await createPayRun(C, '2026-09');
      },
    },
    'updatePayLine',
    async (args) => {
      const run = await runOf('2026-09');
      const line = run.lines[0];
      const changes = { loans: [{ loanId: line.loans[0].loanId, amount: 150.0005 }, { loanId: 'other', amount: 3 }] };
      Object.assign(args, { runId: run.id, lineId: line.id, changes });
      await updatePayLine(run.id, line.id, changes);
    },
  );
  await add(
    'refused: changing a line of an approved run',
    { seed: async () => { await staff(); await september(); } },
    'updatePayLine',
    async (args) => {
      const run = await runOf('2026-09');
      Object.assign(args, { runId: run.id, lineId: run.lines[0].id, changes: { absentDays: 1 } });
      await updatePayLine(run.id, run.lines[0].id, { absentDays: 1 });
    },
  );
  await add(
    'a pay date and notes changed',
    { seed: async () => { await staff(); await createPayRun(C, '2026-09'); } },
    'updatePayRun',
    async (args) => {
      const run = await runOf('2026-09');
      const changes = { payDate: '2026-10-02', notes: '  paid late  ', deductionAccountId: null };
      Object.assign(args, { id: run.id, changes });
      await updatePayRun(run.id, changes);
    },
  );
  await add(
    'a draft brought up to date with new leave',
    {
      seed: async () => {
        await staff();
        await createPayRun(C, '2026-10');
        await saveLeaveRecord(createLeaveRecord(C, X.id, { type: 'unpaid', start: '2026-10-04', end: '2026-10-08' }));
        await saveEmployee({ ...(await db.employees.get(K.id))!, basicSalary: 2700 });
      },
    },
    'refreshPayRun',
    async (args) => {
      const run = await runOf('2026-10');
      args.id = run.id;
      await refreshPayRun(run.id);
    },
  );
  await add(
    'a draft up to date already stays as it is',
    { seed: async () => { await staff(); await createPayRun(C, '2026-10'); } },
    'refreshPayRun',
    async (args) => {
      const run = await runOf('2026-10');
      args.id = run.id;
      await refreshPayRun(run.id);
    },
  );
  await add('a draft deleted', { seed: async () => { await staff(); await createPayRun(C, '2026-09'); } }, 'deletePayRun', async (args) => {
    const run = await runOf('2026-09');
    args.id = run.id;
    await deletePayRun(run.id);
  });
  await add(
    'a pay run approved and posted, with the provisions',
    {
      seed: async () => {
        await staff();
        await saveStaffLoan(createStaffLoan(C, K.id, { date: '2026-09-05', amount: 500, instalment: 200, firstPeriod: '2026-09' }));
        const run = await createPayRun(C, '2026-09');
        await updatePayLine(run.id, run.lines[1].id, {
          overtime: { normal: 2, restDay: 0, holiday: 0 },
          adjustments: [{ id: '', type: 'deduction', amount: 5, note: 'Uniform' }],
        });
      },
      userId: 'u-owner',
      userName: 'Sample Owner',
    },
    'approvePayRun',
    async (args) => {
      const run = await runOf('2026-09');
      args.id = run.id;
      await approvePayRun(run.id);
    },
  );
  await add(
    'October approved: the provisions move by the change',
    {
      seed: async () => {
        await staff();
        await savePayrollSettings({ ...(await getPayrollSettings(C)), eosForInsured: true });
        await september();
        await createPayRun(C, '2026-10');
      },
    },
    'approvePayRun',
    async (args) => {
      const run = await runOf('2026-10');
      args.id = run.id;
      await approvePayRun(run.id);
    },
  );
  await add(
    'a pay run approved with the PIFSS share owed made a loan',
    {
      seed: async () => {
        await staff();
        await saveLeaveRecord(createLeaveRecord(C, K.id, { type: 'unpaid', start: '2026-09-01', end: '2026-09-30' }));
        await createPayRun(C, '2026-09');
      },
    },
    'approvePayRun',
    async (args) => {
      const run = await runOf('2026-09');
      args.id = run.id;
      await approvePayRun(run.id);
    },
  );
  await add(
    'a pay run without provisions, other deductions to a chosen account',
    {
      seed: async () => {
        await staff();
        await savePayrollSettings({ ...(await getPayrollSettings(C)), provisions: false });
        const run = await createPayRun(C, '2026-09');
        const income = (await db.accounts.toArray()).find((a) => a.code === '4500')!;
        await updatePayRun(run.id, { deductionAccountId: income.id });
        await updatePayLine(run.id, run.lines[0].id, { adjustments: [{ id: '', type: 'deduction', amount: 12, note: 'Fine' }] });
      },
    },
    'approvePayRun',
    async (args) => {
      const run = await runOf('2026-09');
      args.id = run.id;
      await approvePayRun(run.id);
    },
  );
  await add(
    'refused: approving in the locked period',
    {
      seed: async () => {
        await staff();
        await createPayRun(C, '2026-09');
        await setCompany((c) => ({ ...c, accounting: { ...c.accounting!, lockDate: '2026-09-30' } }));
      },
    },
    'approvePayRun',
    async (args) => {
      const run = await runOf('2026-09');
      args.id = run.id;
      await approvePayRun(run.id);
    },
  );
  await add(
    'refused: net pay below zero',
    {
      seed: async () => {
        await staff();
        const run = await createPayRun(C, '2026-09');
        await updatePayLine(run.id, run.lines[1].id, { adjustments: [{ id: '', type: 'deduction', amount: 900, note: 'Too much' }] });
      },
    },
    'approvePayRun',
    async (args) => {
      const run = await runOf('2026-09');
      args.id = run.id;
      await approvePayRun(run.id);
    },
  );
  await add('salaries paid from the bank', { seed: async () => { await staff(); await september(); } }, 'payPayRun', async (args) => {
    const run = await runOf('2026-09');
    Object.assign(args, { id: run.id, date: '2026-10-01', bankAccountId: null });
    await payPayRun(run.id, { date: '2026-10-01' });
  });
  await add('refused: paying a draft', { seed: async () => { await staff(); await createPayRun(C, '2026-09'); } }, 'payPayRun', async (args) => {
    const run = await runOf('2026-09');
    Object.assign(args, { id: run.id, date: '2026-10-01' });
    await payPayRun(run.id, { date: '2026-10-01' });
  });
  await add(
    'a payment undone',
    { seed: async () => { await staff(); const run = await september(); await payPayRun(run.id, { date: '2026-10-01' }); } },
    'undoPayRunPayment',
    async (args) => {
      const run = await runOf('2026-09');
      args.id = run.id;
      await undoPayRunPayment(run.id);
    },
  );
  await add('a pay run reopened', { seed: async () => { await staff(); await september(); } }, 'reopenPayRun', async (args) => {
    const run = await runOf('2026-09');
    args.id = run.id;
    await reopenPayRun(run.id);
  });
  await add(
    'a pay run reopened cancels the PIFSS share it recorded as owed',
    {
      seed: async () => {
        await staff();
        await saveLeaveRecord(createLeaveRecord(C, K.id, { type: 'unpaid', start: '2026-09-01', end: '2026-09-30' }));
        await september();
      },
    },
    'reopenPayRun',
    async (args) => {
      const run = await runOf('2026-09');
      args.id = run.id;
      await reopenPayRun(run.id);
    },
  );
  await add(
    'refused: reopening a paid run',
    { seed: async () => { await staff(); const run = await september(); await payPayRun(run.id, { date: '2026-10-01' }); } },
    'reopenPayRun',
    async (args) => {
      const run = await runOf('2026-09');
      args.id = run.id;
      await reopenPayRun(run.id);
    },
  );
  await add(
    'approved again after a reopen',
    { seed: async () => { await staff(); const run = await september(); await reopenPayRun(run.id); } },
    'approvePayRun',
    async (args) => {
      const run = await runOf('2026-09');
      args.id = run.id;
      await approvePayRun(run.id);
    },
  );
  await add(
    'refused: deleting a run approved before',
    { seed: async () => { await staff(); const run = await september(); await reopenPayRun(run.id); } },
    'deletePayRun',
    async (args) => {
      const run = await runOf('2026-09');
      args.id = run.id;
      await deletePayRun(run.id);
    },
  );
  await add(
    'a later loan recovers the PIFSS share owed, within 10% of the wage',
    {
      seed: async () => {
        await staff();
        await saveLeaveRecord(createLeaveRecord(C, K.id, { type: 'unpaid', start: '2026-09-01', end: '2026-09-30' }));
        await september();
      },
    },
    'createPayRun',
    async (args) => {
      args.period = '2026-10';
      await createPayRun(C, '2026-10');
    },
  );

  // ------------------------------------------------- the web's golden payroll
  await add(
    'the leave provision counts the policy only from its date, and an employee’s own days',
    {
      seed: async () => {
        await company();
        await saveEmployee(createEmployee(C, { name: 'Sample Guard', category: 'expat', nationality: 'IN', hireDate: '2026-01-01', basicSalary: 520, iban: IBAN }));
        await saveEmployee(createEmployee(C, { name: 'Sample Manager', category: 'expat', nationality: 'IN', hireDate: '2026-09-01', basicSalary: 520, iban: IBAN, annualLeaveDays: 60 }));
        await approvePayRun((await createPayRun(C, '2026-09')).id);
        await savePayrollSettings({
          ...(await getPayrollSettings(C)),
          leavePolicy: { annualDays: [{ from: '2026-10-01', days: 45 }], firstYearMonths: 9, carryForwardMax: 10, counting: 'working' },
        });
        await saveLeaveRecord(createLeaveRecord(C, (await db.employees.toArray()).find((e) => e.name === 'Sample Guard')!.id, { start: '2026-10-11', end: '2026-10-13' }));
        await createPayRun(C, '2026-10');
      },
    },
    'approvePayRun',
    async (args) => {
      const run = await runOf('2026-10');
      args.id = run.id;
      await approvePayRun(run.id);
    },
  );
  await add(
    'months of long unpaid leave earn no annual leave once the pause is on',
    {
      seed: async () => {
        await staff();
        await saveLeaveReasonSettings(C, { leaveAccrualPause: { from: '2026-01-01' } });
        await saveLeaveRecord(createLeaveRecord(C, K.id, { type: 'unpaid', start: '2026-07-05', end: '2026-07-30' }));
        await saveLeaveRecord(createLeaveRecord(C, K.id, { kind: 'opening', start: '2026-01-01', days: 12.5 }));
        await createPayRun(C, '2026-09');
      },
    },
    'approvePayRun',
    async (args) => {
      const run = await runOf('2026-09');
      args.id = run.id;
      await approvePayRun(run.id);
    },
  );
  await add(
    'a GCC national on their scheme, a domestic worker and someone paid by the day',
    {
      seed: async () => {
        await staff();
        await savePayrollSettings({
          ...(await getPayrollSettings(C)),
          gcc: [{ country: 'SA', employer: 12, employee: 10, cap: 4000 }],
          eosForInsured: true,
          minimumWage: 100,
        });
        await saveEmployee(createEmployee(C, { name: 'Sample Saudi', category: 'gcc', nationality: 'SA', hireDate: '2021-03-15', basicSalary: 1800.5, iban: IBAN, department: 'Head Office' }));
        await saveEmployee(createEmployee(C, { name: 'Sample Helper', category: 'domestic', nationality: 'PH', hireDate: '2022-01-10', basicSalary: 120, iban: IBAN }));
        await saveEmployee(createEmployee(C, { name: 'Sample Daily', category: 'expat', nationality: 'EG', payBasis: 'daily', hireDate: '2016-05-01', basicSalary: 90, permitSalary: 120, iban: '' }));
        await saveEmployee(createEmployee(C, { name: 'Sample Bahraini', category: 'gcc', nationality: 'BH', hireDate: '2025-01-01', basicSalary: 700, iban: IBAN }));
        await createPayRun(C, '2026-09');
      },
    },
    'approvePayRun',
    async (args) => {
      const run = await runOf('2026-09');
      args.id = run.id;
      await approvePayRun(run.id);
    },
  );
  {
    let form: Awaited<ReturnType<typeof settlementDefaults>>;
    const settle = async (name: string, reason: 'termination' | 'resignation' | 'dismissal' | 'death', leavingDate: string) => {
      const employee = (await db.employees.toArray()).find((e) => e.name === name)!;
      const [settings, people, leave, loans, runs, settlements] = await Promise.all([
        getPayrollSettings(C), getPeopleSettings(C), db.leaveRecords.toArray(), db.staffLoans.toArray(), db.payRuns.toArray(), db.finalSettlements.toArray(),
      ]);
      const setup = settlementSetup(employee, leavingDate, { settings, people, leave, loans, runs, settlements }, 3);
      return settlementDefaults(employee, leavingDate, reason, setup, 3);
    };
    await add(
      'a domestic worker settled with a month’s wage a year',
      {
        seed: async () => {
          await company();
          await saveEmployee(createEmployee(C, { name: 'Sample Helper', category: 'domestic', nationality: 'PH', hireDate: '2022-01-10', basicSalary: 120, allowances: [newAllowance({ name: 'Food', amount: 30, countsForEos: false })], iban: IBAN }));
          form = await settle('Sample Helper', 'termination', '2026-11-20');
        },
      },
      'postSettlement',
      async (args) => {
        args.form = form;
        await postSettlement(form);
      },
    );
    await add(
      'a resignation after two years, paid by the day, earns no indemnity',
      {
        seed: async () => {
          await company();
          await saveEmployee(createEmployee(C, { name: 'Sample Daily', category: 'expat', nationality: 'EG', payBasis: 'daily', hireDate: '2024-06-01', basicSalary: 260, iban: IBAN }));
          form = { ...(await settle('Sample Daily', 'resignation', '2026-11-27')), leaveDays: 3.5 };
        },
      },
      'postSettlement',
      async (args) => {
        args.form = form;
        await postSettlement(form);
      },
    );
    await add(
      'a Kuwaiti settled after seven years, with the PIFSS offset',
      {
        seed: async () => {
          await staff();
          await savePayrollSettings({ ...(await getPayrollSettings(C)), eosForInsured: true });
          await september();
          form = { ...(await settle('Sample Kuwaiti', 'resignation', '2026-10-31')), pifssOffset: 1500.0004, noticeMonths: 1 };
        },
      },
      'postSettlement',
      async (args) => {
        args.form = form;
        await postSettlement(form);
      },
    );
  }

  // ---------------------------------------------------------- salary approval
  const approvalsOn = async (role: string, userId: string, approver = false) => {
    await staff();
    await setCompany((c) => ({ ...c, approvalRules: { payroll: true } }));
    await link(role, userId, approver);
  };
  await add(
    'a pay run sent for the Super Admin’s approval',
    { seed: async () => { await approvalsOn('accountant', 'u-acc'); await createPayRun(C, '2026-09'); }, userId: 'u-acc', userName: 'Sample Accountant', role: 'accountant' },
    'requestPayrollApproval',
    async (args) => {
      const run = await runOf('2026-09');
      Object.assign(args, { runId: run.id, note: '  please  ', byName: ' Sample Accountant ' });
      await requestPayrollApproval(run.id, { note: '  please  ', byName: ' Sample Accountant ' });
    },
  );
  await add(
    'sent again: the request for the earlier version is taken back',
    {
      seed: async () => {
        await approvalsOn('accountant', 'u-acc');
        const run = await createPayRun(C, '2026-09');
        await requestPayrollApproval(run.id, { note: 'first' });
        await updatePayRun(run.id, { notes: 'changed' });
      },
      userId: 'u-acc',
      role: 'accountant',
    },
    'requestPayrollApproval',
    async (args) => {
      const run = await runOf('2026-09');
      Object.assign(args, { runId: run.id });
      await requestPayrollApproval(run.id);
    },
  );
  await add(
    'refused: approving without the Super Admin’s approval',
    { seed: async () => { await approvalsOn('accountant', 'u-acc'); await createPayRun(C, '2026-09'); }, userId: 'u-acc', role: 'accountant' },
    'approvePayRun',
    async (args) => {
      const run = await runOf('2026-09');
      args.id = run.id;
      await approvePayRun(run.id);
    },
  );
  await add(
    'approved as the Super Admin approved it, and the request marked done',
    {
      seed: async () => {
        await approvalsOn('accountant', 'u-acc');
        const run = await createPayRun(C, '2026-09');
        const request = await requestPayrollApproval(run.id);
        // Decided by the owner on their device; the accountant then posts.
        await link('owner', 'u-owner');
        await db.approvals.put({ ...request, status: 'approved', decidedBy: 'u-owner', decidedAt: '2026-11-27T10:00:00.000Z' });
        await link('accountant', 'u-acc');
      },
      userId: 'u-acc',
      role: 'accountant',
    },
    'approvePayRun',
    async (args) => {
      const run = await runOf('2026-09');
      args.id = run.id;
      await approvePayRun(run.id);
    },
  );
  await add(
    'the owner posts at once, carrying out the request waiting',
    {
      seed: async () => {
        await approvalsOn('accountant', 'u-acc');
        const run = await createPayRun(C, '2026-09');
        await requestPayrollApproval(run.id);
        await link('owner', 'u-owner');
      },
      userId: 'u-owner',
      role: 'owner',
    },
    'approvePayRun',
    async (args) => {
      const run = await runOf('2026-09');
      args.id = run.id;
      await approvePayRun(run.id);
    },
  );
  await add(
    'refused: a pay run that can’t be posted isn’t sent',
    {
      seed: async () => {
        await approvalsOn('accountant', 'u-acc');
        const run = await createPayRun(C, '2026-09');
        await updatePayLine(run.id, run.lines[1].id, { adjustments: [{ id: '', type: 'deduction', amount: 900, note: 'x' }] });
      },
      userId: 'u-acc',
      role: 'accountant',
    },
    'requestPayrollApproval',
    async (args) => {
      const run = await runOf('2026-09');
      args.runId = run.id;
      await requestPayrollApproval(run.id);
    },
  );

  // -------------------------------------------------------- final settlements
  const settlementSeed = async () => {
    await staff();
    X = await saveEmployee({ ...X, hireDate: '2020-01-01' });
    await saveStaffLoan(createStaffLoan(C, X.id, { date: '2026-08-01', amount: 300, instalment: 100, firstPeriod: '2026-12' }));
    await september();
  };
  const formFor = async (leavingDate: string, reason: 'termination' | 'resignation') => {
    const [settings, people, leave, loans, runs, settlements] = await Promise.all([
      getPayrollSettings(C),
      getPeopleSettings(C),
      db.leaveRecords.toArray(),
      db.staffLoans.toArray(),
      db.payRuns.toArray(),
      db.finalSettlements.toArray(),
    ]);
    const employee = (await db.employees.get(X.id))!;
    const setup = settlementSetup(employee, leavingDate, { settings, people, leave, loans, runs, settlements }, 3);
    return { ...settlementDefaults(employee, leavingDate, reason, setup, 3), leaveDays: 10, notes: ' handed over ', deductionNote: ' keys ' };
  };
  {
    let form: Awaited<ReturnType<typeof formFor>>;
    await add(
      'a final settlement posted: provisions released, the loan recovered, marked as left',
      { seed: async () => { await settlementSeed(); form = await formFor('2026-10-15', 'termination'); }, userId: 'u-owner' },
      'postSettlement',
      async (args) => {
        args.form = form;
        await postSettlement(form);
      },
    );
    await add(
      'a resignation settled with an indemnity entered by hand and other deductions',
      {
        seed: async () => {
          await settlementSeed();
          form = { ...(await formFor('2026-09-30', 'resignation')), indemnityOverride: 250.5, otherDeductions: 20, pifssOffset: 10 };
        },
      },
      'postSettlement',
      async (args) => {
        args.form = form;
        await postSettlement(form);
      },
    );
    await add(
      'refused: no reason for leaving',
      { seed: async () => { await settlementSeed(); form = { ...(await formFor('2026-10-15', 'termination')), reason: '' as never }; } },
      'postSettlement',
      async (args) => {
        args.form = form;
        await postSettlement(form);
      },
    );
    await add(
      'refused: the last salary when the month’s pay run pays it',
      { seed: async () => { await settlementSeed(); form = { ...(await formFor('2026-09-20', 'termination')), lastSalaryDays: 5 }; } },
      'postSettlement',
      async (args) => {
        args.form = form;
        await postSettlement(form);
      },
    );
    await add(
      'refused: a second settlement',
      { seed: async () => { await settlementSeed(); form = await formFor('2026-10-15', 'termination'); await postSettlement(form); } },
      'postSettlement',
      async (args) => {
        args.form = form;
        await postSettlement(form);
      },
    );
    await add(
      'refused: rehiring someone with a final settlement',
      { seed: async () => { await settlementSeed(); form = await formFor('2026-10-15', 'termination'); await postSettlement(form); } },
      'saveEmployee',
      async (args) => {
        const employee = { ...(await db.employees.get(X.id))!, status: 'active' as const };
        args.employee = employee;
        await saveEmployee(employee);
      },
    );
    await add(
      'a settlement paid',
      { seed: async () => { await settlementSeed(); await postSettlement(await formFor('2026-10-15', 'termination')); } },
      'paySettlement',
      async (args) => {
        const s = (await db.finalSettlements.toArray())[0];
        Object.assign(args, { id: s.id, date: '2026-10-20' });
        await paySettlement(s.id, { date: '2026-10-20' });
      },
    );
    await add(
      'a settlement’s payment undone',
      {
        seed: async () => {
          await settlementSeed();
          const s = await postSettlement(await formFor('2026-10-15', 'termination'));
          await paySettlement(s.id, { date: '2026-10-20' });
        },
      },
      'reverseSettlement',
      async (args) => {
        const s = (await db.finalSettlements.toArray())[0];
        args.id = s.id;
        await reverseSettlement(s.id);
      },
    );
    await add(
      'a settlement reversed',
      { seed: async () => { await settlementSeed(); await postSettlement(await formFor('2026-10-15', 'termination')); } },
      'reverseSettlement',
      async (args) => {
        const s = (await db.finalSettlements.toArray())[0];
        args.id = s.id;
        await reverseSettlement(s.id);
      },
    );
    await add(
      'a rehire once the settlement is reversed',
      {
        seed: async () => {
          await settlementSeed();
          const s = await postSettlement(await formFor('2026-10-15', 'termination'));
          await reverseSettlement(s.id);
        },
      },
      'saveEmployee',
      async (args) => {
        const employee = { ...(await db.employees.get(X.id))!, status: 'active' as const, leavingDate: '2026-10-15' };
        args.employee = employee;
        await saveEmployee(employee);
      },
    );
  }

  // ------------------------------------------------------------------ letters
  await add('letters turned on, with the letter rule', { seed: staff }, 'setLettersOn', async (args) => {
    args.on = true;
    await setLettersOn(C, true);
  });
  await add(
    'refused: an accountant turns letters on',
    { seed: async () => { await staff(); await link('accountant', 'u-acc'); }, userId: 'u-acc', role: 'accountant' },
    'setLettersOn',
    async (args) => {
      args.on = true;
      await setLettersOn(C, true);
    },
  );
  {
    let tpl: ReturnType<typeof newTemplate>;
    await add(
      'a template of the company’s own saved, tidy',
      { seed: async () => { await staff(); await lettersOn(); tpl = newTemplate(C, 'salary_transfer'); } },
      'saveTemplate',
      async (args) => {
        const template = { ...tpl, name: '  Transfer  to   bank ', bodyAr: ' نص\r\nالخطاب ', autoOn: ['leaving', 'leaving'] as never, privateFields: true, archived: 'yes' as never };
        args.template = template;
        await saveTemplate(template);
      },
    );
    await add(
      'refused: a template without the text of its language',
      { seed: async () => { await staff(); await lettersOn(); tpl = newTemplate(C, 'custom'); } },
      'saveTemplate',
      async (args) => {
        const template = { ...tpl, language: 'ar-en' as const, bodyEn: '  ' };
        args.template = template;
        await saveTemplate(template);
      },
    );
  }
  await add('a default template stored once changed', { seed: async () => { await staff(); await lettersOn(); } }, 'saveTemplate', async (args) => {
    const id = defaultTemplateId(C, 'warning');
    const template = {
      id,
      companyId: C,
      kind: 'warning' as const,
      name: 'Warning letter',
      nameAr: 'خطاب إنذار',
      language: 'en' as const,
      subjectEn: 'Warning',
      subjectAr: 'إنذار',
      bodyEn: 'To: {employee.name}\n{letter.purpose}',
      bodyAr: '',
      showStamp: true,
      showSignature: true,
      signatoryName: '',
      signatoryTitle: '',
      archived: false,
      createdAt: '',
      updatedAt: '',
    };
    args.template = template;
    await saveTemplate(template);
  });
  await add('a default template archived', { seed: async () => { await staff(); await lettersOn(); } }, 'setTemplateArchived', async (args) => {
    Object.assign(args, { id: defaultTemplateId(C, 'noc'), archived: true });
    await setTemplateArchived(C, defaultTemplateId(C, 'noc'), true);
  });
  await add(
    'a default template’s wording put back',
    {
      seed: async () => {
        await staff();
        await lettersOn();
        const id = defaultTemplateId(C, 'experience_certificate');
        const { getTemplate } = await import('@/db/letters');
        const tpl = (await getTemplate(C, id))!;
        await saveTemplate({ ...tpl, bodyAr: 'نص آخر', signatoryName: 'Sample Signatory', language: 'ar' });
      },
    },
    'restoreDefaultWording',
    async (args) => {
      args.id = defaultTemplateId(C, 'experience_certificate');
      await restoreDefaultWording(C, defaultTemplateId(C, 'experience_certificate'));
    },
  );
  {
    let draft: Awaited<ReturnType<typeof draftFromTemplate>>;
    await add(
      'a letter drafted',
      {
        seed: async () => {
          await staff();
          await lettersOn();
          const tpl = await ownTemplate();
          draft = { ...draftFromTemplate(tpl, K.id), addressee: '  Sample Bank  ', purpose: ' a loan\r\n ', bodyEn: 'English  \r\ntext ' };
        },
        userId: 'u-owner',
      },
      'saveLetterDraft',
      async (args) => {
        args.draft = draft;
        await saveLetterDraft(draft);
      },
    );
    await add(
      'refused: a letter while letters are off',
      { seed: async () => { await staff(); const tpl = newTemplate(C, 'custom'); draft = draftFromTemplate({ ...tpl, bodyAr: 'x' }, K.id); } },
      'saveLetterDraft',
      async (args) => {
        args.draft = draft;
        await saveLetterDraft(draft);
      },
    );
  }
  await add(
    'a draft changed, in English only',
    { seed: async () => { await staff(); await lettersOn(); await draftFor(K); } },
    'saveLetterDraft',
    async (args) => {
      const letter = (await db.employeeLetters.toArray())[0];
      const draft = { ...letter, language: 'en' as const, body: 'Changed {employee.name}', subject: 'New', trigger: 'joining' as const };
      args.draft = draft;
      await saveLetterDraft(draft);
    },
  );
  await add('a draft deleted', { seed: async () => { await staff(); await lettersOn(); await draftFor(K); } }, 'deleteLetterDraft', async (args) => {
    const letter = (await db.employeeLetters.toArray())[0];
    args.id = letter.id;
    await deleteLetterDraft(letter.id);
  });
  await add(
    'a letter issued in Arabic and English: numbered and frozen',
    {
      seed: async () => {
        await staff();
        await lettersOn();
        await addDepartment(C, { name: 'Head Office', nameAr: 'الإدارة' });
        await db.employees.put({ ...(await db.employees.get(K.id))!, gender: 'female' });
        await draftFor(K);
      },
    },
    'issueLetter',
    async (args) => {
      const letter = (await db.employeeLetters.toArray())[0];
      Object.assign(args, { id: letter.id, on: '2026-11-28' });
      await issueLetter(letter.id, '2026-11-28');
    },
  );
  await add(
    'a letter issued in English skips a number used',
    {
      seed: async () => {
        await staff();
        await lettersOn();
        await draftFor(X, 'en');
        const other = await draftFor(K, 'ar');
        await db.employeeLetters.put({ ...other, status: 'void', number: 'HR-2026-0001', issuedOn: '2026-11-01' });
      },
    },
    'issueLetter',
    async (args) => {
      const letter = (await db.employeeLetters.toArray()).find((l) => l.status === 'draft')!;
      Object.assign(args, { id: letter.id, on: '2026-11-20' });
      await issueLetter(letter.id, '2026-11-20');
    },
  );
  await add(
    'refused: a warning letter without what happened',
    {
      seed: async () => {
        await staff();
        await lettersOn();
        const { getTemplate } = await import('@/db/letters');
        const tpl = (await getTemplate(C, defaultTemplateId(C, 'warning')))!;
        await saveLetterDraft({ ...draftFromTemplate(tpl, X.id), purpose: ' ' });
      },
    },
    'issueLetter',
    async (args) => {
      const letter = (await db.employeeLetters.toArray())[0];
      Object.assign(args, { id: letter.id, on: '2026-11-28' });
      await issueLetter(letter.id, '2026-11-28');
    },
  );
  await add(
    'a letter voided',
    { seed: async () => { await staff(); await lettersOn(); const d = await draftFor(K, 'en'); await issueLetter(d.id, '2026-11-20'); } },
    'voidLetter',
    async (args) => {
      const letter = (await db.employeeLetters.toArray())[0];
      Object.assign(args, { id: letter.id, reason: '  wrong bank  ' });
      await voidLetter(letter.id, '  wrong bank  ');
    },
  );
  await add(
    'letters marked printed',
    { seed: async () => { await staff(); await lettersOn(); const d = await draftFor(K, 'en'); await issueLetter(d.id, '2026-11-20'); await draftFor(X, 'en'); } },
    'markLettersPrinted',
    async (args) => {
      const ids = (await db.employeeLetters.toArray()).map((l) => l.id);
      args.ids = ids;
      await markLettersPrinted(ids);
    },
  );
  await add(
    'an accountant asks an approver to issue a letter',
    {
      seed: async () => {
        await staff();
        await link('owner', 'u-owner');
        await lettersOn();
        await draftFor(K, 'en');
        await link('accountant', 'u-acc');
      },
      userId: 'u-acc',
      userName: 'Sample Accountant',
      role: 'accountant',
    },
    'requestLetterIssue',
    async (args) => {
      const letter = (await db.employeeLetters.toArray())[0];
      Object.assign(args, { id: letter.id, note: ' for the bank ', byName: 'Sample Accountant' });
      await requestLetterIssue(letter.id, { note: ' for the bank ', byName: 'Sample Accountant' });
    },
  );
  {
    let input: Employee;
    await add(
      'a new employee gets the drafts their templates ask for on joining',
      {
        seed: async () => {
          await staff();
          await lettersOn();
          await ownTemplate();
          input = createEmployee(C, { name: 'Sample Joiner', hireDate: '2026-12-01', basicSalary: 350 });
        },
      },
      'saveEmployee',
      async (args) => {
        args.employee = input;
        await saveEmployee(input);
      },
    );
  }
  await add(
    'a salary change and leaving, with drafts for each',
    {
      seed: async () => {
        await staff();
        await lettersOn();
        const tpl = await ownTemplate('en');
        await saveTemplate({ ...tpl, autoOn: ['salary_change'] });
        const other = newTemplate(C, 'experience_certificate');
        await saveTemplate({ ...other, autoOn: ['leaving'], language: 'en', bodyEn: 'Worked here' });
      },
    },
    'saveEmployee',
    async (args) => {
      const employee = { ...X, basicSalary: 500, status: 'left' as const, leavingDate: '2026-11-30', leavingReason: 'resignation' as const };
      args.employee = employee;
      await saveEmployee(employee);
    },
  );

  // ----------------------------------------------------------------- costings
  await add('the costing turned on', { seed: staff }, 'setCostingsOn', async (args) => {
    args.on = true;
    await setCostingsOn(C, true);
  });
  await add('the costing settings and rate card saved, tidy', { seed: staff }, 'saveCostingSettings', async (args) => {
    const input = {
      overheadPercent: 12.345,
      marginPercent: 95,
      rates: [
        { id: '', jobTitle: ' Guard ', jobTitleAr: ' حارس ', category: 'gcc' as const, nationality: ' sa ', basic: 300.0006, allowances: 50, eosAllowances: 60, otherCosts: -1, count: 2.6 },
        { id: 'r2', jobTitle: '', category: 'expat' as const, basic: 1, allowances: 0 },
        { id: 'r3', jobTitle: 'Cleaner', category: 'nobody' as never, basic: 150, allowances: 20, eosAllowances: 5 },
      ],
    };
    args.input = input;
    await saveCostingSettings(C, input);
  });
  {
    let costing: StaffingCosting;
    await add(
      'a costing priced and saved',
      {
        seed: async () => {
          await staff();
          await setCostingsOn(C, true);
          costing = {
            ...newCosting(C, { overheadPercent: 10, marginPercent: 15 }),
            name: '  Sample Mall guarding ',
            notes: 'Night shift',
            posts: [
              { ...newPost({ jobTitle: ' Guard ', jobTitleAr: ' حارس ', basic: 120, allowances: 30, otherCosts: 15 }), headcount: 4.4, hoursPerDay: 12, daysPerMonth: 30 },
              { ...newPost({ jobTitle: 'Supervisor', category: 'kuwaiti', basic: 900, allowances: 100, eosAllowances: 40 }), nationality: 'KW' },
              { ...newPost({ jobTitle: 'Driver', category: 'gcc', nationality: 'SA', basic: 70, allowances: 0 }), hoursPerDay: 9 },
            ],
          };
        },
      },
      'saveCosting',
      async (args) => {
        args.costing = costing;
        await saveCosting(costing);
      },
    );
    await add(
      'refused: a post without a job title',
      { seed: async () => { await staff(); costing = { ...newCosting(C, { overheadPercent: 10, marginPercent: 15 }), name: 'X', posts: [newPost()] }; } },
      'saveCosting',
      async (args) => {
        args.costing = costing;
        await saveCosting(costing);
      },
    );
    await add(
      'a costing marked as won',
      {
        seed: async () => {
          await staff();
          costing = await saveCosting({ ...newCosting(C, { overheadPercent: 10, marginPercent: 15 }), name: 'Sample site', posts: [{ ...newPost({ jobTitle: 'Cleaner', basic: 100 }) }] });
        },
      },
      'setCostingStatus',
      async (args) => {
        Object.assign(args, { id: costing.id, status: 'won' });
        await setCostingStatus(costing.id, 'won');
      },
    );
    await add(
      'a costing deleted',
      { seed: async () => { await staff(); costing = await saveCosting({ ...newCosting(C, { overheadPercent: 10, marginPercent: 15 }), name: 'Sample site' }); } },
      'deleteCosting',
      async (args) => {
        args.id = costing.id;
        await deleteCosting(costing.id);
      },
    );
    await add(
      'refused: staff make no costings',
      { seed: async () => { await staff(); await link('staff', 'u-staff'); costing = newCosting(C, { overheadPercent: 10, marginPercent: 15 }); costing.name = 'Sample'; }, userId: 'u-staff', role: 'staff' },
      'saveCosting',
      async (args) => {
        args.costing = costing;
        await saveCosting(costing);
      },
    );
  }

  writeFixtures('people', out);
  console.log(
    out.map((s) => `${s.name}: ${s.error ?? 'ok'}`).join('\n'),
  );
});
