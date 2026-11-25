// Runs the web's own rules over many inputs and writes what they answer, for
// the Swift port's parity tests (ios/MahamKit/Tests/MahamKitTests/WebFixtures.swift).
import { writeFileSync } from 'node:fs';
import { stableId } from '../../../src/lib/ids.ts';
import {
  allocateFrom,
  allocateNumber,
  currentCounter,
  formatNumber,
  periodKey,
  previewNumber,
  writtenBy,
} from '../../../src/lib/numbering.ts';
import {
  bankFromIban,
  findBank,
  formatHijri,
  formatIban,
  isValidCardNumber,
  isValidCivilId,
  isValidIban,
  kuwaitHolidays,
  normalizeKuwaitPhone,
  placeName,
} from '../../../src/lib/kuwait.ts';
import { kuwaitProfile, cashLimit } from '../../../src/lib/kuwait-rules.ts';
import { formatAddressLines, isAddressEmpty } from '../../../src/lib/geo.ts';
import { matchUnit, unitText, findUnit, unitChoices } from '../../../src/lib/units.ts';
import { regionDefaults } from '../../../src/lib/regions.ts';
import {
  createClient,
  createCompany,
  createDocument,
  createProduct,
  createRecurring,
  createTaxRate,
  defaultEmailTemplatesAr,
  defaultNotes,
} from '../../../src/db/defaults.ts';
import * as R from '../../../src/cloud/roles.ts';

/** JSON with sorted keys (UTF-16 order), as WebJS.json writes it in Swift. */
function canon(v: unknown): string {
  if (v === undefined) return 'undefined';
  if (v === null) return 'null';
  if (Array.isArray(v)) return '[' + v.map((x) => (x === undefined ? 'null' : canon(x))).join(',') + ']';
  if (typeof v === 'object') {
    const o = v as Record<string, unknown>;
    return (
      '{' +
      Object.keys(o)
        .filter((k) => o[k] !== undefined)
        .sort()
        .map((k) => JSON.stringify(k) + ':' + canon(o[k]))
        .join(',') +
      '}'
    );
  }
  return JSON.stringify(v);
}
const hash = (v: unknown) => stableId(canon(v)).slice(4, 16);
const bits = (values: boolean[]) => values.map((b) => (b ? '1' : '0')).join('');
/** Drops undefined, as JSON does. */
const plain = <T>(v: T): T => (v === undefined ? (null as T) : JSON.parse(JSON.stringify(v)));

const out: Record<string, unknown> = {};

// ------------------------------------------------------------------ ids
{
  const inputs = [
    '',
    'a',
    'hello',
    'company-type:trading',
    'approval-payment:9b2f6c1e-1d2a-4c55-8f6e-0a1b2c3d4e5f',
    'tpl-1:emp-1:probation_end:2026-10-01',
    'co-1|doc-1|out:prod-1:wh-1|0',
    'co-1|doc-1|out:prod-1:wh-1|1',
    'شركة الخليج للتجارة',
    'emoji 😀 and 𝄞 clef',
    'x'.repeat(1000),
    'Ünïcödé — “quotes” ‘and’ \u0000 nul',
  ];
  out.stableId = inputs.map((t) => [t, stableId(t)]);
}

// ------------------------------------------------------------- numbering
{
  const patterns = [
    'INV-{year}-{counter}',
    '{client}/{yy}{month}{day}/{counter}',
    'Q-',
    '',
    '   ',
    '{foo}-{counter}',
    '{COUNTER}-{Year}',
    'SKU-{counter}',
    'P.{yy}{month}-{counter}',
    '{{counter}}',
    '{constructor}-{counter}',
    '{__proto__}{counter}',
    'A{year}{yy}{month}{day}{client}',
    '  HR-{year}-{counter}  ',
    '{ counter }',
    'كود-{counter}',
  ];
  const paddings = [0, 1, 3, 4, 5, 12, 20, -1, 2.7];
  const dates = ['2026-03-09', '2026-01-01', '', '2026', '2026-1-5', '1999-12-31-extra'];
  const counters = [1, 7, 12, 123456];
  const format: unknown[] = [];
  for (const pattern of patterns)
    for (const padding of paddings)
      for (const date of dates.slice(0, 4))
        format.push(formatNumber({ pattern, padding }, 7, date, 'C-01'));
  for (const counter of counters)
    for (const date of dates)
      format.push(formatNumber({ pattern: 'INV-{year}-{counter}', padding: 4 }, counter, date));
  out.numberingFormat = format;

  const texts = ['SKU-00004', ' sku-123456 ', 'SKU-04', 'GL-01', 'SKU-00004-B', 'P.2610-007', 'PX2610-007', 'INV-2026-0007', 'inv-2026-0007', 'C-01/260309/012', 'x/260309/012', '/260309/012', '{foo}-1', '{FOO}-1', 'Q-03', '3', '00012', 'كود-0001', 'HR-2026-0001'];
  const written: boolean[] = [];
  for (const pattern of patterns)
    for (const padding of [1, 3, 4, 5])
      for (const text of texts) written.push(writtenBy({ pattern, padding }, text));
  out.numberingPatterns = patterns;
  out.numberingTexts = texts;
  out.numberingWrittenBy = bits(written);

  const rules: Record<string, unknown>[] = [
    { pattern: 'INV-{year}-{counter}', next: 40, padding: 4, reset: 'yearly', period: '2025' },
    { pattern: 'INV-{year}-{counter}', next: 40, padding: 4, reset: 'yearly', period: '2026' },
    { pattern: 'X', next: 9, padding: 4, reset: 'monthly', period: '2026-04' },
    { pattern: 'X', next: 9, padding: 4, reset: 'monthly', period: '2026-05' },
    { pattern: 'X', next: 9, padding: 4, reset: 'never', period: '2020' },
    { pattern: 'X', next: 0, padding: 4, reset: 'never', period: '' },
    { pattern: 'X', next: -3, padding: 4, reset: 'never', period: '' },
    { pattern: 'X', next: 7.9, padding: 4, reset: 'never', period: '' },
    { pattern: 'X', padding: 4, reset: 'never', period: '' },
    { pattern: 'X', next: null, padding: 4, reset: 'never', period: '' },
    { pattern: 'X', next: '12', padding: 4, reset: 'never', period: '' },
    { pattern: 'X', next: 5, padding: 4, reset: 'weekly', period: '2026' },
    { pattern: 'X', next: 5, padding: 4, reset: 'weekly', period: '' },
    { pattern: 'X', next: 5, padding: 4, period: '2026' },
    { pattern: 'X', next: 5, padding: 4, reset: 'yearly', period: 2026 },
    { pattern: 'X', next: 5, padding: 4, reset: 'yearly' },
  ];
  const counter: unknown[] = [];
  for (const rule of rules)
    for (const date of ['2026-05-02', '2026-04-30', '2025-12-31'])
      counter.push([rule, date, currentCounter(rule as never, date), periodKey((rule as { reset: never }).reset, date)]);
  out.numberingCounter = counter;

  const allocate: unknown[] = [];
  const taken = ['INV-2026-0003', 'inv-2026-0004', 'INV-2026-0006', 'X0001', 'X0002'];
  const lower = new Set(taken.map((t) => t.toLowerCase()));
  for (const rule of [
    { pattern: 'INV-{year}-{counter}', next: 3, padding: 4, reset: 'yearly', period: '2026', extra: 'kept' },
    { pattern: 'INV-{year}-{counter}', next: 3, padding: 4, reset: 'yearly', period: '2025' },
    { pattern: 'X', next: 1, padding: 4, reset: 'never', period: '' },
    { pattern: 'X', next: 1, padding: 4, reset: 'monthly', period: '2026-05' },
  ]) {
    for (const reserved of [null, { counter: 5, period: '2026' }, { counter: 1, period: '2026' }, { counter: 9, period: '' }, { counter: 2, period: '2026-06' }]) {
      const date = '2026-06-01';
      const a = reserved
        ? allocateFrom(rule as never, date, (n) => lower.has(n.toLowerCase()), 'C-9', reserved)
        : allocateNumber(rule as never, date, (n) => lower.has(n.toLowerCase()), 'C-9');
      allocate.push([rule, date, reserved, a.number, a.rule]);
    }
  }
  out.numberingAllocate = allocate;
  out.numberingPreview = [
    previewNumber({ pattern: 'INV-{year}-{counter}', next: 12, padding: 4, reset: 'never', period: '' }, '2026-02-01'),
    previewNumber({ pattern: '{client}-{counter}', next: 2, padding: 3, reset: 'never', period: '' }, '2026-02-01'),
  ];
}

// ---------------------------------------------------------------- kuwait
{
  const ibans = [
    'KW81CBKU0000000000001234560101',
    'kw81 cbku 0000 0000 0000 1234 5601 01',
    'KW82CBKU0000000000001234560101',
    'KW81CBKU000000000000123456010',
    'GB82WEST12345698765432',
    'GB82-WEST-1234-5698-7654-32',
    'KW12NBOK0000000000001000372151',
    'DE89370400440532013000',
    'FR1420041010050500013M02606',
    'NL91ABNA0417164300',
    'XX00',
    '',
    'KW',
    'SA0380000000608010167519',
    'AE070331234567890123456',
    'KW81 CBKU 0000\t0000 0000 1234 5601 01',
    'ab12cdefghijklmnop',
  ];
  out.iban = ibans.map((s) => [s, isValidIban(s), formatIban(s), bankFromIban(s)?.code ?? null]);

  const civil: unknown[] = [];
  let seed = 12345;
  const rand = () => {
    seed = (seed * 1103515245 + 12345) % 2147483648;
    return seed;
  };
  for (let i = 0; i < 400; i++) {
    const century = rand() % 2 === 0 ? '2' : '3';
    const yy = String(rand() % 100).padStart(2, '0');
    const mm = String(rand() % 14).padStart(2, '0');
    const dd = String(rand() % 33).padStart(2, '0');
    const rest = String(rand() % 10000).padStart(4, '0');
    const base = century + yy + mm + dd + rest;
    civil.push([base + String(rand() % 10), isValidCivilId(base + String(rand() % 10))]);
  }
  // Ones that are valid, worked out with the weights.
  for (const base of ['28501011235', '29002290001', '30002290001', '29902280002', '30512310003', '20002290004']) {
    const weights = [2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2];
    const sum = weights.reduce((s, w, i) => s + w * Number(base[i]), 0);
    for (let d = 0; d < 10; d++) civil.push([base + d, isValidCivilId(base + d)]);
    civil.push([' ' + base.slice(0, 6) + ' ' + base.slice(6) + ((11 - (sum % 11)) % 10), isValidCivilId(' ' + base.slice(0, 6) + ' ' + base.slice(6) + ((11 - (sum % 11)) % 10))]);
  }
  for (const s of ['1234', '', '285010112350', '485010112350', '2850101123a0', '٢٨٥٠١٠١١٢٣٥٠']) civil.push([s, isValidCivilId(s)]);
  // Recompute the pairs (the random ones above call it twice with different digits).
  out.civilIds = civil.map(([s]) => s);
  out.civilId = bits(civil.map(([s]) => isValidCivilId(s as string)));

  out.phone = [
    '+965 9988 7766', '0096522445566', '55667788', '12345678', '96555667788', '965556677', '+96555667788',
    '(+965) 6123-4567', '٩٩٨٨٧٧٦٦', '4123 4567', '2123456', '+965 1234 5678', '00965 9988 7766 ext',
    '+9659988776', '96599887766',
  ].map((s) => [s, normalizeKuwaitPhone(s)]);

  out.card = [
    '4111111111111111', '4111 1111 1111 1111', '4111-1111-1111-1112', '378282246310005', '6011111111111117',
    '123456789012', '12345678901', '1234567890123456789', '12345678901234567890', '', '0000000000000',
  ].map((s) => [s, isValidCardNumber(s)]);

  out.bank = [
    'NBK', 'nbk', 'National Bank of Kuwait', 'بنك الكويت الوطني', 'KFH', 'بيتك', 'Bait Al Tamweel', 'bait-al-tamweel',
    'ABK', 'الأهلي', 'الاهلي', 'Al Ahli', 'CBK', 'التجاري', 'Warba', 'وربه', 'وربة', 'KIB', 'Gulf', 'GBK',
    'NBOKKWKW', 'brgn', '  Burgan!! ', 'unknown', '', '---',
  ].map((s) => [s, findBank(s)?.code ?? null]);

  out.place = ['Salmiya', 'salmiya', 'السالمية', ' Hawalli ', 'HA', 'ha', 'حولي', 'Capital', 'العاصمة', 'Somewhere', '', 'Kuwait City', 'Mubarak Al-Kabeer', 'JA'].map(
    (s) => [s, placeName(s, 'en'), placeName(s, 'ar')],
  );

  const holidays: Record<string, unknown> = {};
  for (let y = 2020; y <= 2035; y++) holidays[y] = kuwaitHolidays(y).map((h) => [h.date, h.name.en, h.name.ar]);
  out.holidays = holidays;

  const hijri: unknown[] = [];
  for (let t = Date.UTC(2020, 0, 1); t < Date.UTC(2032, 0, 1); t += 86_400_000 * 29) {
    const d = new Date(t).toISOString().slice(0, 10);
    hijri.push([d, formatHijri(d, 'en'), formatHijri(d, 'ar')]);
  }
  for (const d of ['1990-02-28', '1950-07-15', '2077-11-17', '2026-13-01', '2026-02-30', '26-01-01', '2026-10-3'])
    hijri.push([d, formatHijri(d, 'en'), formatHijri(d, 'ar')]);
  out.hijri = hijri;

  out.kuwaitProfile = [
    [{}, kuwaitProfile({})],
    [{ kuwait: { legalForm: 'kscc', capital: 5000, extra: true } }, kuwaitProfile({ kuwait: { legalForm: 'kscc', capital: 5000, extra: true } } as never)],
    [{ kuwait: null }, kuwaitProfile({ kuwait: null } as never)],
  ];
  out.cashLimit = ['general', 'health', 'vehicles', 'real_estate', 'later', 'constructor'].map((a) => [a, cashLimit(a as never) ?? null]);
}

// ------------------------------------------------------------ geo, units
{
  const addresses = [
    { line1: 'Al Hamra Tower', line2: '', city: 'Salmiya', state: 'Hawalli', postalCode: '22001', country: 'KW', block: '3', street: '12', avenue: '', building: '15', floor: '2', unit: '5', paci: '12345678' },
    { line1: '', line2: '', city: 'السالمية', state: 'HA', postalCode: '', country: ' kw ', block: ' 3 ' },
    { line1: '', line2: '', city: '', state: '', postalCode: '', country: 'KW' },
    { line1: '1 Main St', line2: 'Suite 2', city: 'Springfield', state: 'IL', postalCode: '62701', country: 'US' },
    { line1: '10 Downing St', line2: '', city: 'London', state: '', postalCode: 'SW1A 2AA', country: 'GB' },
    { line1: 'Unter den Linden 1', line2: '', city: 'Berlin', state: 'Berlin', postalCode: '10117', country: 'DE' },
    { line1: 'x', line2: '', city: '', state: '', postalCode: '', country: '' },
  ];
  out.addresses = addresses.map((a) => [
    a,
    formatAddressLines(a as never, 'en', false),
    formatAddressLines(a as never, 'ar-KW', false),
    (a.country.trim().toUpperCase() === 'KW' || a.country === '') ? formatAddressLines(a as never, 'en', true) : null,
    (a.country.trim().toUpperCase() === 'KW') ? formatAddressLines(a as never, 'ar', true) : null,
    isAddressEmpty(a as never),
  ]);

  const unitTexts: string[] = [];
  for (const t of ['pc', 'PCS', 'Pcs.', ' piece ', 'قطعة', 'قطعه', 'قِطْعَة', 'قطـعة', 'kg', 'KGS.', '..kg..', 'كيلو', 'Ltr', 'LITRE', 'l', 'm', 'mtrs', 'أمتار', 'امتار', 'hours', 'h', 'ساعات', 'ساعه', 'mo', 'شهور', 'set', 'sets', 'أطقم', 'اطقم', 'roll', '', '   ', '.', 'ｐｃｓ', 'Ｂｏｘ', 'box  es', 'BOXES', 'bx', 'علب', 'علبه', 'رحلة', 'رحله', 'trip', 'day', 'أيام', 'ايام', 'كغ', 'كجم', 'each', 'ea', 'no', 'nos']) unitTexts.push(t);
  const own = { items: { units: true, customUnits: [{ id: 'u-roll', name: 'roll', nameAr: 'لفة' }, { id: 'u-old', name: 'bag', nameAr: 'كيس', archived: true }, { id: 'u-ar', name: ' ', nameAr: ' كرتونة ' }, { id: 'u-pc', name: 'PC', nameAr: '' }] } };
  out.units = unitTexts.map((t) => [t, matchUnit(t), matchUnit(t, own as never)]);
  out.unitsCompany = own;
  out.unitText = [
    ['box', 'box', 'ar'], ['Boxes', 'box', 'ar-en'], ['carton', 'box', 'ar'], ['pcs', null, 'ar'], ['roll', 'u-roll', 'ar'],
    ['لفه', 'u-roll', 'ar'], ['كرتونة', 'u-ar', 'ar'], ['كرتونة', 'u-ar', 'en'], ['x', 'u-old', 'ar'], ['bag', 'u-old', 'ar'], ['pc', 'u-pc', 'ar'],
  ].map(([unit, unitId, lang]) => [unit, unitId, lang, unitText(own as never, { unit: unit as string, unitId: unitId as string }, lang as never)]);
  out.unitChoices = unitChoices(own as never).map((u) => [u.id, u.name, u.nameAr]);
  out.findUnit = ['u-ar', 'u-old', 'pcs', 'nothing'].map((id) => [id, findUnit(own as never, id)?.name ?? null]);

  out.regions = ['KW', 'kw', 'US', 'DE', 'XX', '', 'ng', 'CH'].map((c) => [c, regionDefaults(c)]);
}

// --------------------------------------------------------------- defaults
{
  const fix = (r: Record<string, unknown>) => {
    const copy = { ...r, id: 'ID', createdAt: 'STAMP', updatedAt: 'STAMP' } as Record<string, unknown>;
    if ('issueDate' in copy) copy.issueDate = 'TODAY';
    if ('startDate' in copy) copy.startDate = 'TODAY';
    if ('nextIssueDate' in copy) copy.nextIssueDate = 'TODAY';
    return hash(copy);
  };
  out.defaults = {
    company: fix(createCompany() as never),
    companyUS: fix(createCompany({ locale: 'en-US', language: 'en', name: 'Acme' }) as never),
    companyAr: fix(createCompany({ locale: 'ar-KW', language: 'ar' }) as never),
    companyNull: fix(createCompany({ locale: null, language: null } as never) as never),
    companyCA: fix(createCompany({ locale: 'fr-CA' }) as never),
    client: fix(createClient('co-1') as never),
    clientOver: fix(createClient('co-1', { name: 'Gulf Pearl', currency: 'USD', extra: 1 } as never) as never),
    product: fix(createProduct('co-1') as never),
    taxRate: fix(createTaxRate('co-1', { name: 'VAT', rate: 5 }) as never),
    invoice: fix(createDocument('co-1', 'invoice') as never),
    bill: fix(createDocument('co-1', 'bill', { currency: 'USD' }) as never),
    recurring: fix(createRecurring('co-1') as never),
    emailAr: hash(defaultEmailTemplatesAr()),
    notes: ['en', 'ar', 'ar-en', 'fr'].map((l) => [l, defaultNotes(l as never)]),
  };
  out.stamps = [0, 1, 999, 1764067440123, 1764067440999, -1, -86400001, 253402300799999, 1e12 + 0.9].map((ms) => [ms, new Date(ms).toISOString()]);
}

// ------------------------------------------------------------------ roles
{
  // companyBooksChanged (super-admin-sql.test.ts)
  const rule = (extra: Record<string, unknown> = {}) => ({ pattern: 'INV-{counter}', next: 1, padding: 4, reset: 'never', ...extra });
  const base = { id: 'c', name: 'Acme', numbering: { invoice: rule(), employee: rule({ pattern: 'E' }) }, accounting: { lockDate: null, template: 'kuwait' }, payment: { bankDetails: 'NBK' } };
  const books: Record<string, unknown>[] = [
    base,
    { ...base, name: 'Changed' },
    { ...base, holidays: [{ date: '2026-02-25' }] },
    { ...base, accounting: { lockDate: '2026-12-31', template: 'kuwait' } },
    { ...base, accounting: { template: 'kuwait' } },
    { ...base, accounting: undefined },
    { ...base, accounting: null },
    { ...base, payment: { bankDetails: 'KFH' } },
    { ...base, defaults: { numberOnIssue: true } },
    { ...base, taxesEnabled: true },
    { ...base, numbering: { invoice: rule({ next: 9, period: '2026' }), employee: rule() } },
    { ...base, numbering: { invoice: rule({ pattern: 'X' }), employee: rule({ pattern: 'E' }) } },
    { ...base, numbering: { invoice: rule(), employee: rule({ pattern: 'EMP' }) } },
    { ...base, numbering: { invoice: rule(), employee: rule(), journal: rule({ pattern: 'MJ' }) } },
    { ...base, numbering: { invoice: 'odd' } },
    { ...base, numbering: null },
    { ...base, kuwait: { licenceNumber: 'L-1', wamdPhone: '' } },
    { ...base, kuwait: { licenceNumber: 'L-2' } },
    { ...base, kuwait: { licenceNumber: 'L-1', wamdPhone: null } },
    { ...base, kuwait: { licenceNumber: 'L-1', wamdPhone: '+965 9871 2046' } },
    { ...base, kuwait: { wamdPhone: '+965 9999 9999' } },
    { ...base, kuwait: { wamdPhone: 99999999 } },
    { ...base, kuwait: 'odd' },
    { ...base, kuwait: ['+965 9999 9999'] },
    { ...base, kuwait: null },
    { ...base, bankAccount: { bank: 'NBOK', iban: 'KW00' } },
    { ...base, bankAccount: { bank: 'NBOK', iban: 'KW99' } },
    { ...base, emailTemplates: { invoice: { subject: 'Invoice', body: 'Pay at {paymentLink}' } } },
    { ...base, emailTemplates: { invoice: { subject: 'Invoice', body: 'Pay elsewhere' } } },
    { ...base, labels: { invoice: 'Bill' } },
    { ...base, numbering: ['x'] },
    { ...base, numbering: { invoice: null, employee: rule() } },
  ];
  const booksBits: boolean[] = [];
  const staffBits: boolean[] = [];
  for (const before of books) for (const after of books) {
    booksBits.push(R.companyBooksChanged(before, after));
    staffBits.push(R.staffCompanyChangeOk(before, after));
  }
  out.booksSamples = hash(books.map(plain));
  out.booksChanged = bits(booksBits);
  out.staffCompanyOk = bits(staffBits);

  // Documents (approvals-sql.test.ts)
  const invoice = (id: string, extra: Record<string, unknown> = {}) => ({
    id, companyId: 'c', type: 'invoice', number: `INV-${id}`, status: 'sent', clientId: 'cl-1', issueDate: '2026-10-01', dueDate: '2026-10-31', poNumber: '', currency: 'KWD',
    items: [{ id: 'line-1', kind: 'item', productId: null, name: 'Guarding, October', description: '', quantity: 2, unit: '', unitPrice: 150, discount: 0, discountType: 'percent', taxes: [] }],
    discount: 0, discountType: 'percent', taxes: [], charges: [], pricesIncludeTax: false, deposit: 0, depositDueDate: null, notes: '', terms: 'Payment within 30 days.', footer: '', privateNotes: '', templateId: null,
    totals: { subtotal: 300, discount: 0, taxTotal: 0, total: 300, paid: 0, balance: 300 }, sentAt: '2026-10-01T08:00:00.000Z', paidAt: null, sourceId: null, convertedToId: null, recurringId: null, archived: false,
    createdAt: '2026-10-01T08:00:00.000Z', updatedAt: '2026-10-01T08:00:00.000Z', ...extra,
  });
  const inv = invoice('inv-1');
  const link = (url: unknown) => ({ paymentLink: { provider: 'tap', url, expiresAt: null } });
  const docs: (Record<string, unknown> | null)[] = [
    null,
    inv,
    { ...inv, items: [{ ...inv.items[0], unitPrice: 120 }] },
    { ...inv, clientId: 'cl-2' },
    { ...inv, status: 'void' },
    { ...inv, status: 'draft' },
    { ...inv, status: 'paid', totals: { ...inv.totals, paid: 300, balance: 0 }, paidAt: '2026-10-05' },
    { ...inv, privateNotes: 'internal', posting: { taxExempt: false } },
    { ...inv, ...link('https://pay.example.com/a') },
    { ...inv, ...link('https://pay.example.com/b') },
    { ...inv, paymentLink: null },
    { ...inv, type: 'credit', number: 'CN-1' },
    { ...inv, type: 'quote', number: 'QUO-1' },
    { ...inv, number: '', status: 'sent' },
    { ...inv, number: '  ', status: 'draft' },
    { ...inv, type: 'credit', number: '', status: 'void' },
    { ...inv, items: [{ ...inv.items[0], sku: null, nameAr: 'حراسة' }] },
    { ...inv, notes: null },
    {},
  ];
  const ruleSets: (Record<string, unknown> | null)[] = [
    null,
    {},
    { documentTypes: ['invoice', 'credit'], voidInsteadOfDelete: true, expireDays: 14 },
    { documentTypes: ['invoice'] },
    { documentTypes: 'invoice' },
    { documentTypes: ['quote'], voidInsteadOfDelete: false },
  ];
  const companies = [{ defaults: { numberOnIssue: true } }, { defaults: { numberOnIssue: false } }, {}];
  let docBits = '';
  for (const rules of ruleSets) for (const before of docs) for (const after of docs) {
    const needs = R.documentChangeNeedsApproval(rules, before, after);
    const linkNeeds = R.paymentLinkNeedsApprover(rules, before, after);
    const kept = after ? canon(R.keepPaymentLink(rules, before, after as Record<string, unknown>)) !== canon(after) : false;
    docBits += bits([needs, linkNeeds, kept]);
  }
  let deleteCodes = '';
  const code = (k: string | null) => (k === null ? '-' : k[0]);
  for (const rules of ruleSets) for (const doc of docs) for (const table of ['documents', 'approvals', 'payments'])
    deleteCodes += code(R.deleteKeptBy(rules, table, doc, true)) + code(R.deleteKeptBy(rules, table, doc, false)) + (R.rulesKeepRecord(rules, table, doc) ? '1' : '0');
  let numberBits = '';
  for (const company of companies) for (const before of docs) for (const after of docs) numberBits += R.issuesWithoutNumber(company, before, after) ? '1' : '0';
  out.docSamples = hash(docs.map(plain));
  out.ruleSets = ruleSets;
  out.companies = companies;
  out.docBits = docBits;
  out.deleteCodes = deleteCodes;
  out.numberBits = numberBits;
  out.invoiceContent = docs.map((d) => hash(R.invoiceContent(d)));
  out.invoiceContentBase = R.invoiceContent(inv);

  // Cheques (cheque-approvals-sql.test.ts)
  const cheque = (id: string, extra: Record<string, unknown> = {}) => {
    const { cheque: details, ...rest } = extra as { cheque?: Record<string, unknown> };
    return {
      id, companyId: 'c', direction: 'out', clientId: 'vendor-1', number: `PAYM-${id}`, date: '2026-10-05', amount: 250, currency: 'KWD', accountId: 'acc-2150', method: 'cheque', reference: '000101', notes: '',
      allocations: [{ documentId: 'bill-1', amount: 250 }], documentIds: ['bill-1'], creditId: null,
      cheque: { number: '000101', bank: 'BRGN', date: '2026-10-20', drawer: 'Made-up Supplies Co.', status: 'held', ...details },
      postingRules: 2, createdAt: '2026-10-05T08:00:00.000Z', updatedAt: '2026-10-05T08:00:00.000Z', ...rest,
    };
  };
  const security = (id: string, extra: Record<string, unknown> = {}) => ({
    id, companyId: 'c', direction: 'out', clientId: null, number: '000555', bank: 'KFHO', date: null, amount: 1000, currency: 'KWD', drawer: 'Made-up Landlord', purpose: 'Rent deposit, office 4', notes: '', status: 'held', returnedOn: null, cashedOn: null, paymentId: null,
    createdAt: '2026-10-05T08:00:00.000Z', updatedAt: '2026-10-05T08:00:00.000Z', ...extra,
  });
  const cb = cheque('p-1');
  const edits: Record<string, unknown>[] = [
    { ...cb, amount: 2500 }, { ...cb, currency: 'USD', exchangeRate: 0.307 }, { ...cb, exchangeRate: 2 }, { ...cb, date: '2026-09-01' }, { ...cb, clientId: 'vendor-2' },
    { ...cb, cheque: { ...cb.cheque, drawer: 'Someone Else' } }, { ...cb, cheque: { ...cb.cheque, number: '000999' } }, { ...cb, cheque: { ...cb.cheque, bank: 'NBOK' } },
    { ...cb, cheque: { ...cb.cheque, date: '2026-12-31' } }, { ...cb, cheque: { ...cb.cheque, drawerCivilId: '290010112345' } }, { ...cb, direction: 'in' },
    { ...cb, method: 'bank_transfer', cheque: null }, { ...cb, accountId: 'acc-petty-cash' },
  ];
  const life: Record<string, unknown>[] = [
    { ...cb, notes: 'Handed to the courier' }, { ...cb, allocations: [], documentIds: [] },
    { ...cb, cheque: { ...cb.cheque, status: 'cleared', clearedOn: '2026-10-21', bankAccountId: 'acc-bank', clearingJournalId: 'jr-1' } },
    { ...cb, voided: true, voidReason: 'Insufficient funds', voidedOn: '2026-10-22', cheque: { ...cb.cheque, status: 'returned', returnedOn: '2026-10-22' } },
    { ...cb, voided: true, voidReason: 'Given back', voidedOn: '2026-10-22', cheque: { ...cb.cheque, status: 'cancelled' } },
    { ...cb, cheque: { ...cb.cheque, printedAt: '2026-10-06T09:00:00.000Z', printCount: 1, printedLayoutId: 'preset-BRGN', crossed: true } },
    { ...cb, reference: '000102', cheque: { ...cb.cheque, number: '000102', printCount: 1, spoiledLeaves: [{ number: '000101', at: '2026-10-06T09:00:00.000Z', reason: 'Jammed' }] } },
    { ...cb, reference: '000102', cheque: { ...cb.cheque, number: '000102', spoiledLeaves: [{ number: ' 000101 ' }] } },
    { ...cb, reference: '000102', cheque: { ...cb.cheque, number: '000102', spoiledLeaves: [{ number: 101 }] } },
    { ...cb, reference: '000102', cheque: { ...cb.cheque, number: '000102', spoiledLeaves: ['000101', null, { number: null }] } },
    { ...cb, postingRules: 3, updatedAt: '2026-10-07T08:00:00.000Z' }, { ...cb, exchangeRate: 1 },
    { ...cb, cheque: { ...cb.cheque, drawerCivilId: '' } },
  ];
  const pairs: [unknown, unknown][] = [
    ...edits.map((e): [unknown, unknown] => [cb, e]),
    ...life.map((e): [unknown, unknown] => [cb, e]),
    [null, cb], [cb, null], [{ ...cb, accountId: null }, cb], [{ ...cb, accountId: undefined }, cb], [{ ...cb, accountId: '' }, cb], [cb, { ...cb, accountId: null }],
    [null, { ...cb, direction: 'in' }], [null, { ...cb, method: 'bank_transfer', cheque: null }], [{ ...cb, cheque: { ...cb.cheque, number: 101 } }, { ...cb, cheque: { ...cb.cheque, number: '000102', spoiledLeaves: [{ number: '101' }] } }],
    [{ ...cb, direction: 'in' }, { ...cb, direction: 'in', amount: 1 }], [{ ...cb, cheque: [] }, { ...cb, cheque: [] }],
  ];
  const chequeRules: unknown[] = [
    { documentTypes: ['invoice'], expireDays: 14, cheques: { issued: true, securityOut: true, received: false } },
    { cheques: { received: true } }, { cheques: {} }, { cheques: 'yes' }, { documentTypes: ['invoice'] }, null,
  ];
  const given = security('s-1');
  const secPairs: [unknown, unknown][] = [[null, given], [given, { ...given, amount: 1 }], [given, { ...given, status: 'returned' }], [null, { ...given, direction: 'in' }], [given, null], [given, { ...given, drawerCivilId: '' }], [{ ...given, drawerCivilId: '' }, { ...given, drawerCivilId: '290' }]];
  let chequeBits = '';
  for (const rules of chequeRules) {
    for (const [before, after] of pairs) chequeBits += R.chequeChangeNeedsApprover(rules as never, 'payments', before as never, after as never) ? '1' : '0';
    for (const [before, after] of secPairs) chequeBits += R.chequeChangeNeedsApprover(rules as never, 'securityCheques', before as never, after as never) ? '1' : '0';
    chequeBits += R.chequeChangeNeedsApprover(rules as never, 'documents', cb, null) ? '1' : '0';
  }
  out.chequePairs = hash(pairs.map(([a, b]) => [plain(a), plain(b)]));
  out.securityPairs = hash(secPairs.map(([a, b]) => [plain(a), plain(b)]));
  out.chequeRules = chequeRules;
  out.chequeBits = chequeBits;
  const chequeSamples = [cb, { ...cb, exchangeRate: 1 }, { ...cb, exchangeRate: null, direction: undefined }, { ...cb, cheque: { ...cb.cheque, drawerCivilId: '' } }, { ...cb, cheque: null, method: 'cash' }, { ...cb, accountId: null }, {}];
  out.chequeContent = chequeSamples.map((s) => hash(R.chequeContent(s)));
  out.securityContent = [given, security('s-2', { drawerCivilId: '' }), {}].map((s) => hash(R.securityChequeContent(s)));

  // Approval requests (approvals-sql.test.ts, payroll-approval-roles.test.ts)
  const NOW = '2026-10-22T08:00:00.000Z';
  const users: [string, boolean, boolean][] = [['owner', true, true], ['deputy', true, false], ['accountant', false, false], ['requester', false, false]];
  const asked = (id: string, extra: Record<string, unknown> = {}, payroll = false) => ({
    id, companyId: 'c', kind: payroll ? 'payroll' : 'invoice_void', subjectTbl: payroll ? 'payRuns' : 'documents', subjectId: 'inv-1', subjectNumber: 'INV-1',
    before: { status: 'sent' }, after: { status: 'void' }, reason: 'Entered twice.', status: 'pending', requestedBy: 'requester', requestedByName: 'Made-up Staff',
    requestedAt: '2026-10-02T08:00:00.000Z', decidedBy: null, decidedAt: null, decisionNote: '', createdAt: '2026-10-02T08:00:00.000Z', updatedAt: '2026-10-02T08:00:00.000Z', ...extra,
  });
  const afters: Record<string, unknown>[] = [
    { expired: true, resultId: 'pay-x', extra: 'x' },
    { status: 'cancelled', resultId: 'pay-x', note: 'x' },
    { status: 'cancelled', expired: true },
    { status: 'approved', decisionNote: 'Fine.', resultId: 'pay-x' },
    { status: 'applied', resultId: 'pay-1', expired: true },
    { status: 'rejected', decisionNote: 'No.' },
    { status: 'pending', decidedBy: 'requester' },
    { status: 'maybe' },
    { requestedBy: 'owner', after: { status: 'draft' }, decidedBy: 'owner' },
    { status: 5 },
    { status: null, updatedAt: '2026-10-03T08:00:00.000Z' },
  ];
  const approvals: unknown[] = [];
  const staffWho = { userId: 'requester', approver: false, owner: false, now: NOW };
  const ownerWho = { userId: 'owner', approver: true, owner: true, now: NOW };
  for (const payrollKind of [false, true]) {
    for (const payroll of payrollKind ? [{ on: true, poster: true }, { on: true, poster: false }, { on: false, poster: true }, undefined] : [undefined]) {
      for (const [user, approver, owner] of users) {
        const who = { userId: user, approver, owner, now: NOW };
        let n = 0;
        for (const start of ['pending', 'approved', 'applied', 'rejected']) {
          for (const change of afters) {
            n += 1;
            const id = `g-${n}`;
            const first = R.guardApprovalWrite(undefined, asked(id, {}, payrollKind), staffWho, payroll);
            let before = 'data' in first ? first.data : null;
            if (start !== 'pending' && before) {
              const decided = R.guardApprovalWrite(before, asked(id, { status: start }, payrollKind), ownerWho, payroll);
              before = 'data' in decided ? decided.data : before;
            }
            const data = asked(id, { status: before?.status, ...change }, payrollKind);
            const result = R.guardApprovalWrite(before, data, who, payroll);
            approvals.push(hash(before) + ('refused' in result ? result.refused : hash(result.data)));
          }
        }
        for (const status of ['pending', 'approved', 'applied', 'cancelled', undefined]) {
          n += 1;
          const data = asked(`g-${n}`, { status, decidedBy: 'owner', decidedAt: '2026-10-02T09:00:00.000Z', resultId: 'pay-x', expired: true }, payrollKind);
          const result = R.guardApprovalWrite(undefined, data, who, payroll);
          approvals.push('refused' in result ? result.refused : hash(result.data));
        }
      }
    }
  }
  out.approvals = approvals;

  // Pay run decisions
  const req = { id: 'req-1', kind: 'payroll', subjectTbl: 'payRuns', subjectId: 'run-1', status: 'pending', requestedBy: 'deputy', after: { runUpdatedAt: '2026-10-20T08:00:00.000Z' } };
  const run = { id: 'run-1', updatedAt: '2026-10-20T08:00:00.000Z' };
  const befores = [null, req, { ...req, requestedBy: 'boss' }, { ...req, status: 'approved' }, { ...req, status: 'rejected' }, { ...req, status: undefined }, { ...req, requestedBy: 'shut' }, { ...req, after: 'x' }, { ...req, status: 7 }];
  const statuses = [undefined, 'pending', 'approved', 'rejected', 'cancelled', 'applied', 'odd', null];
  const whos = [
    { userId: 'deputy', owner: false }, { userId: 'boss', owner: true }, { userId: 'other', owner: false },
    { userId: 'shut', owner: false, peopleShut: true }, { userId: 'shut', owner: true, peopleShut: true }, { userId: 'deputy', owner: false, peopleShut: true },
  ];
  const runs = [run, { ...run, updatedAt: '2026-10-21T08:00:00.000Z' }, null, { id: 'run-1' }];
  let payrollCodes = '';
  for (const before of befores) for (const status of statuses) for (const who of whos) for (const r of runs) {
    const after = before ? { ...before, status } : { ...req, status };
    const refusal = R.payrollDecisionRefusal(before, after, who, r);
    payrollCodes += refusal === null ? '-' : ({ self: 'S', stale: 't', people: 'p' } as Record<string, string>)[refusal];
  }
  out.payrollSamples = hash([befores.map(plain), statuses.map((s) => (s === undefined ? '__missing__' : s)), whos, runs.map(plain)]);
  out.payrollCodes = payrollCodes;

  // Letters
  const draft = { id: 'let-1', status: 'draft', number: '', body: 'Text' };
  const issued = { ...draft, status: 'issued', number: 'HR-2026-0001', body: 'Done' };
  const letters: (Record<string, unknown> | null)[] = [
    null, draft, { ...draft, body: 'Other' }, issued, { ...issued, body: 'Other' }, { ...issued, status: 'void', voidReason: 'Wrong', voidedOn: '2026-10-21' },
    { ...issued, printedAt: '2026-10-22T08:00:00.000Z', updatedAt: 'u' }, { ...issued, printedAt: '2026-10-22T09:00:00.000Z' }, { ...issued, number: 'HR-2026-0002' },
    { ...issued, status: undefined }, { ...issued, status: null }, { ...issued, status: 'void', voidReason: 'Other', voidedOn: null, updatedAt: null }, { id: 'let-2' }, { ...issued, printedAt: 5 },
  ];
  let letterCodes = '';
  const letterKeeps: string[] = [];
  for (const before of letters) for (const after of letters) {
    for (const issuer of [false, true]) {
      const r = R.letterWriteRefusal(before, after, issuer);
      letterCodes += r === null ? '-' : r === 'issued' ? 'd' : 'r';
    }
    if (after) letterKeeps.push(hash(R.keepIssuedLetter(before, after)));
  }
  out.letters = hash(letters.map(plain));
  out.letterCodes = letterCodes;
  out.letterKeeps = letterKeeps;
  out.letterContent = letters.map((l) => hash(R.letterContent(l)));
  out.letterKept = bits(letters.map((l) => R.letterKept(l)));

  // Warehouses
  const keeper = { userId: 'keeper', name: ' Made-up Keeper ', jobTitle: 'Storekeeper' };
  const warehouses: Record<string, Record<string, unknown>> = {
    main: { id: 'main', name: 'Main' },
    sub: { id: 'sub', name: 'Van 1', parentId: 'main', keeper },
    subOld: { id: 'subOld', parentId: 'main', keeper, archived: true },
    subNoKeeper: { id: 'subNoKeeper', parentId: 'main' },
    kept: { id: 'kept', keeper: { userId: 'keeper', name: 'Made-up Keeper', jobTitle: '' } },
    odd: { id: 'odd', parentId: '', keeper: null },
  };
  const find = (id: string) => warehouses[id] ?? null;
  const members = [
    { role: 'owner', userId: 'boss', approver: true }, { role: 'admin', userId: 'admin', approver: false }, { role: 'accountant', userId: 'acc', approver: true },
    { role: 'staff', userId: 'keeper', approver: false }, { role: 'staff', userId: 'other', approver: false }, { role: 'viewer', userId: 'keeper', approver: false },
    { role: null, userId: null, approver: false }, { role: 'staff', userId: '', approver: true },
  ];
  const doc = (lines: Record<string, unknown>[], extra: Record<string, unknown> = {}) => ({ id: 'd', type: 'invoice', status: 'sent', items: lines, ...extra });
  const line = (id: string, warehouseId: unknown, quantity: unknown = 1) => ({ id, productId: 'p-1', warehouseId, quantity });
  const rows: Record<string, (Record<string, unknown> | null)[]> = {
    warehouses: [null, ...Object.values(warehouses), { id: 'main', name: 'Renamed' }],
    stockEntries: [null, { id: 'e', warehouseId: 'main' }, { id: 'e', warehouseId: 'sub' }, { id: 'e', warehouseId: 'main', toWarehouseId: 'sub' }, { id: 'e', warehouseId: 'nowhere' }, { id: 'e', toWarehouseId: 'kept' }],
    stockIssues: [null, { id: 'i', warehouseId: 'sub' }],
    documents: [
      null, doc([line('l1', 'main')]), doc([line('l1', 'sub')]), doc([line('l1', 'sub', 2)]), doc([line('l2', 'sub'), line('l1', 'sub')]), doc([line('l1', 'sub'), line('l2', 'sub')]),
      doc([line('l1', 'sub')], { status: 'void' }), doc([line('l1', 'sub')], { type: 'bill' }), doc([line('l1', 'sub', null)]), doc([line('l1', 'subOld', 1.5)]), doc([]), { id: 'd' },
      doc([line('é', 'sub'), line('e', 'sub'), line('𝄞', 'sub'), line('￿', 'sub')]),
    ],
    approvals: [
      null, { id: 'a', kind: 'stock_issue', after: { warehouseId: 'sub' } }, { id: 'a', kind: 'stock_issue', after: { warehouseId: 'subOld' } },
      { id: 'a', kind: 'stock_issue', after: { warehouseId: 'main' } }, { id: 'a', kind: 'stock_issue', after: { warehouseId: 'kept' } }, { id: 'a', kind: 'invoice_void', after: {} },
      { id: 'a', kind: 'stock_issue' },
    ],
    clients: [null, { id: 'c' }],
  };
  let warehouseCodes = '';
  for (const member of members) for (const [table, samples] of Object.entries(rows)) for (const before of samples) for (const after of samples) {
    const r = R.warehouseWriteRefusal(member as never, table, before, after, find);
    warehouseCodes += r === null ? '-' : r[0];
  }
  out.warehouseSamples = hash([warehouses, members, Object.entries(rows).map(([t, s]) => [t, s.map(plain)])]);
  out.warehouseCodes = warehouseCodes;
  out.subWarehouseLines = rows.documents.map((d) => R.subWarehouseLines(d, find));
  out.issuers = members.flatMap((m) => Object.keys(warehouses).map((w) => [m.role, m.userId, w, R.issuesFromWarehouse(m.role as never, m.userId, find(w)), R.issuerName(m.userId, find(w))]));

  // Writing records, limits, apps
  const perms = [undefined, { apps: { books: 'view', compliance: 'none', people: 'edit' } }, { apps: { people: 'view' } }, { apps: { books: 'none', crm: 'view' } }];
  const tables = ['companies', 'clients', 'documents', 'journals', 'employees', 'payRuns', 'complianceDocuments', 'renewals', 'vehicles', 'attachments', 'activities', 'approvals', 'stockIssues', 'later'];
  const records = [{}, { kind: 'payroll' }, { kind: 'transfer' }, { employeeId: 'emp-1' }, { employeeId: '' }, { ownerId: 'emp-1' }, { ownerId: 'inv-1' }, { ownerId: 'veh-1' }, { ownerId: 'nobody' }];
  const owners: Record<string, Record<string, unknown>> = { employees: { 'emp-1': { id: 'emp-1' } }, documents: { 'inv-1': { id: 'inv-1' } }, vehicles: { 'veh-1': { id: 'veh-1' } } };
  const lookup = (t: string, id: string) => owners[t]?.[id] ?? null;
  let appCodes = '';
  for (const table of tables) for (const record of records) {
    const app = (a: string | null) => (a === null ? '-' : a === 'compliance' ? 'C' : a[0]);
    appCodes += app(R.recordApp(table, record, lookup));
    appCodes += app(R.recordApp(table, record));
  }
  let limitBits = '';
  for (const role of ['owner', 'admin', 'accountant', 'staff', 'viewer', null]) for (const p of perms) {
    for (const table of tables) for (const record of records) limitBits += R.limitBlocksWrite(role as never, p as never, table, record, lookup) ? '1' : '0';
    limitBits += R.hasLimits(role as never, p as never) ? '1' : '0';
    limitBits += R.canPostPayroll(role as never, p as never) ? '1' : '0';
  }
  let writeBits = '';
  for (const role of ['owner', 'admin', 'accountant', 'staff', 'viewer', null]) for (const table of tables) for (const record of records)
    writeBits += R.canWriteRecord(role as never, table, record, lookup) ? '1' : '0';
  out.limitSamples = hash([perms.map((p) => p ?? null), tables, records, owners]);
  out.appCodes = appCodes;
  out.limitBits = limitBits;
  out.writeBits = writeBits;
}

writeFileSync(new URL('./fixtures.json', import.meta.url), JSON.stringify(out));
it('wrote the fixtures', () => {});
