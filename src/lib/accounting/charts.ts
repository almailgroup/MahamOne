import type { Account, AccountRole, AccountType, ChartTemplateId } from '@/db/types';

export interface ChartAccount {
  code: string;
  name: string;
  /** Arabic name, shown when the interface or a report is in Arabic. */
  nameAr?: string;
  type: AccountType;
  role?: AccountRole;
}

type Row = [code: string, name: string, type: AccountType, role?: AccountRole];

const rows = (list: Row[]): ChartAccount[] =>
  list.map(([code, name, type, role]) => ({ code, name, type, ...(role ? { role } : {}) }));

/** Works for most countries: plain names, 4-digit codes. */
const GENERIC = rows([
  ['1000', 'Bank account', 'asset_cash', 'bank'],
  ['1010', 'Cash on hand', 'asset_cash', 'cash'],
  ['1100', 'Accounts receivable', 'asset_receivable', 'receivable'],
  ['1200', 'Inventory', 'asset_current'],
  ['1300', 'Prepaid expenses', 'asset_prepayments'],
  ['1350', 'Sales tax receivable (input tax)', 'asset_current', 'input_tax'],
  ['1400', 'Other current assets', 'asset_current'],
  ['1500', 'Equipment', 'asset_fixed'],
  ['1510', 'Accumulated depreciation – equipment', 'asset_fixed'],
  ['1600', 'Vehicles', 'asset_fixed'],
  ['1610', 'Accumulated depreciation – vehicles', 'asset_fixed'],
  ['1700', 'Other non-current assets', 'asset_non_current'],
  ['2000', 'Accounts payable', 'liability_payable', 'payable'],
  ['2050', 'Company credit card', 'liability_credit_card', 'credit_card'],
  ['2100', 'Sales tax collected (output tax)', 'liability_current', 'output_tax'],
  ['2110', 'Sales tax payable', 'liability_current', 'tax_settlement'],
  ['2200', 'Accrued expenses', 'liability_current'],
  ['2300', 'Payroll liabilities', 'liability_current'],
  ['2400', 'Customer deposits', 'liability_current'],
  ['2500', 'Loans payable', 'liability_non_current'],
  ['3000', "Owner's capital", 'equity', 'capital'],
  ['3100', "Owner's drawings", 'equity', 'drawings'],
  ['3200', 'Retained earnings', 'equity', 'retained_earnings'],
  ['3900', 'Opening balance equity', 'equity', 'opening_balance'],
  ['4000', 'Sales', 'income', 'sales'],
  ['4100', 'Service income', 'income'],
  ['4200', 'Shipping & delivery income', 'income', 'charges'],
  ['4500', 'Other income', 'income_other'],
  ['4510', 'Interest income', 'income_other'],
  ['5000', 'Cost of goods sold', 'expense_direct_cost', 'cost_of_sales'],
  ['5100', 'Subcontractors', 'expense_direct_cost'],
  ['6000', 'General expenses', 'expense', 'expense'],
  ['6010', 'Advertising & marketing', 'expense'],
  ['6020', 'Bank fees & charges', 'expense', 'bank_fees'],
  ['6030', 'Office supplies', 'expense'],
  ['6040', 'Rent', 'expense'],
  ['6050', 'Utilities', 'expense'],
  ['6060', 'Telephone & internet', 'expense'],
  ['6070', 'Software & subscriptions', 'expense'],
  ['6080', 'Travel', 'expense'],
  ['6090', 'Meals & entertainment', 'expense'],
  ['6100', 'Professional fees', 'expense'],
  ['6110', 'Insurance', 'expense'],
  ['6120', 'Postage & shipping', 'expense'],
  ['6130', 'Printing & stationery', 'expense'],
  ['6140', 'Repairs & maintenance', 'expense'],
  ['6150', 'Salaries & wages', 'expense'],
  ['6160', 'Payroll taxes & benefits', 'expense'],
  ['6170', 'Vehicle expenses', 'expense'],
  ['6180', 'Training', 'expense'],
  ['6190', 'Bad debts', 'expense'],
  ['6900', 'Depreciation', 'expense_depreciation'],
  ['7000', 'Exchange gain or loss', 'expense_other', 'fx'],
  ['7100', 'Interest expense', 'expense_other'],
  ['7200', 'Income tax', 'expense_other'],
]);

/** United Kingdom: VAT control accounts and the familiar UK layout. */
const UK = rows([
  ['0010', 'Freehold property', 'asset_fixed'],
  ['0020', 'Plant and machinery', 'asset_fixed'],
  ['0021', 'Plant and machinery – depreciation', 'asset_fixed'],
  ['0030', 'Office equipment', 'asset_fixed'],
  ['0031', 'Office equipment – depreciation', 'asset_fixed'],
  ['0050', 'Motor vehicles', 'asset_fixed'],
  ['0051', 'Motor vehicles – depreciation', 'asset_fixed'],
  ['1001', 'Stock', 'asset_current'],
  ['1100', 'Trade debtors', 'asset_receivable', 'receivable'],
  ['1103', 'Prepayments', 'asset_prepayments'],
  ['1104', 'Other debtors', 'asset_current'],
  ['1200', 'Bank current account', 'asset_cash', 'bank'],
  ['1210', 'Bank deposit account', 'asset_cash'],
  ['1230', 'Petty cash', 'asset_cash', 'cash'],
  ['2100', 'Trade creditors', 'liability_payable', 'payable'],
  ['2105', 'Company credit card', 'liability_credit_card', 'credit_card'],
  ['2109', 'Accruals', 'liability_current'],
  ['2200', 'VAT on sales', 'liability_current', 'output_tax'],
  ['2201', 'VAT on purchases', 'asset_current', 'input_tax'],
  ['2202', 'VAT liability (HMRC)', 'liability_current', 'tax_settlement'],
  ['2210', 'PAYE and NI', 'liability_current'],
  ['2220', 'Net wages', 'liability_current'],
  ['2230', 'Pension contributions', 'liability_current'],
  ['2300', "Directors' loan account", 'liability_current'],
  ['2320', 'Corporation tax', 'liability_current'],
  ['2400', 'Bank loans', 'liability_non_current'],
  ['3000', 'Share capital', 'equity', 'capital'],
  ['3100', 'Dividends and drawings', 'equity', 'drawings'],
  ['3200', 'Retained earnings', 'equity', 'retained_earnings'],
  ['3900', 'Opening balances', 'equity', 'opening_balance'],
  ['4000', 'Sales', 'income', 'sales'],
  ['4010', 'Sales – services', 'income'],
  ['4900', 'Delivery and other charges', 'income', 'charges'],
  ['4910', 'Other income', 'income_other'],
  ['4920', 'Bank interest received', 'income_other'],
  ['5000', 'Cost of sales', 'expense_direct_cost', 'cost_of_sales'],
  ['5100', 'Subcontractors', 'expense_direct_cost'],
  ['5200', 'Postage and carriage', 'expense_direct_cost'],
  ['6000', 'Wages and salaries', 'expense'],
  ['6010', "Employer's NI", 'expense'],
  ['6020', 'Pension costs', 'expense'],
  ['7000', 'Rent and rates', 'expense'],
  ['7100', 'Light, heat and power', 'expense'],
  ['7200', 'Insurance', 'expense'],
  ['7300', 'Repairs and maintenance', 'expense'],
  ['7400', 'Travel and subsistence', 'expense'],
  ['7450', 'Motor expenses', 'expense'],
  ['7500', 'Printing, postage and stationery', 'expense'],
  ['7550', 'Telephone and internet', 'expense'],
  ['7600', 'Software and subscriptions', 'expense'],
  ['7700', 'Advertising and marketing', 'expense'],
  ['7800', 'Accountancy and legal fees', 'expense'],
  ['7900', 'Bank charges', 'expense', 'bank_fees'],
  ['7910', 'Card processing fees', 'expense'],
  ['8000', 'General expenses', 'expense', 'expense'],
  ['8100', 'Bad debts', 'expense'],
  ['8150', 'Entertainment', 'expense'],
  ['8200', 'Depreciation', 'expense_depreciation'],
  ['8300', 'Exchange gains and losses', 'expense_other', 'fx'],
  ['8400', 'Interest paid', 'expense_other'],
  ['8900', 'Corporation tax charge', 'expense_other'],
]);

/** United Arab Emirates: VAT input/output and common UAE accounts. */
const UAE = rows([
  ['1000', 'Bank account', 'asset_cash', 'bank'],
  ['1010', 'Petty cash', 'asset_cash', 'cash'],
  ['1100', 'Accounts receivable', 'asset_receivable', 'receivable'],
  ['1150', 'Post-dated cheques received', 'asset_current'],
  ['1200', 'Inventory', 'asset_current'],
  ['1300', 'Prepaid expenses', 'asset_prepayments'],
  ['1310', 'Security deposits', 'asset_current'],
  ['1350', 'VAT input (recoverable)', 'asset_current', 'input_tax'],
  ['1500', 'Property, plant and equipment', 'asset_fixed'],
  ['1510', 'Accumulated depreciation', 'asset_fixed'],
  ['1600', 'Right-of-use assets', 'asset_non_current'],
  ['2000', 'Accounts payable', 'liability_payable', 'payable'],
  ['2050', 'Company credit card', 'liability_credit_card', 'credit_card'],
  ['2100', 'VAT output', 'liability_current', 'output_tax'],
  ['2110', 'VAT payable (FTA)', 'liability_current', 'tax_settlement'],
  ['2150', 'Post-dated cheques issued', 'liability_current'],
  ['2200', 'Accrued expenses', 'liability_current'],
  ['2300', 'Salaries payable', 'liability_current'],
  ['2310', 'End of service benefits', 'liability_non_current'],
  ['2400', 'Customer advances', 'liability_current'],
  ['2500', 'Long-term loans', 'liability_non_current'],
  ['3000', 'Share capital', 'equity', 'capital'],
  ['3100', "Owner's current account", 'equity', 'drawings'],
  ['3200', 'Retained earnings', 'equity', 'retained_earnings'],
  ['3300', 'Statutory reserve', 'equity'],
  ['3900', 'Opening balance equity', 'equity', 'opening_balance'],
  ['4000', 'Sales', 'income', 'sales'],
  ['4100', 'Service revenue', 'income'],
  ['4200', 'Delivery charges income', 'income', 'charges'],
  ['4500', 'Other income', 'income_other'],
  ['5000', 'Cost of sales', 'expense_direct_cost', 'cost_of_sales'],
  ['6000', 'General and administrative expenses', 'expense', 'expense'],
  ['6010', 'Salaries and allowances', 'expense'],
  ['6020', 'Rent', 'expense'],
  ['6030', 'Utilities', 'expense'],
  ['6040', 'Telephone and internet', 'expense'],
  ['6050', 'Marketing and advertising', 'expense'],
  ['6060', 'Professional fees', 'expense'],
  ['6070', 'Government fees and visas', 'expense'],
  ['6080', 'Travel', 'expense'],
  ['6090', 'Office supplies', 'expense'],
  ['6100', 'Repairs and maintenance', 'expense'],
  ['6110', 'Insurance', 'expense'],
  ['6120', 'Bank charges', 'expense', 'bank_fees'],
  ['6130', 'Software and subscriptions', 'expense'],
  ['6140', 'Postage and courier', 'expense'],
  ['6900', 'Depreciation', 'expense_depreciation'],
  ['7000', 'Exchange gain or loss', 'expense_other', 'fx'],
  ['7100', 'Finance costs', 'expense_other'],
  ['7200', 'Corporate tax', 'expense_other'],
]);

type BilingualRow = [
  code: string,
  name: string,
  nameAr: string,
  type: AccountType,
  role?: AccountRole,
];

const bilingual = (list: BilingualRow[]): ChartAccount[] =>
  list.map(([code, name, nameAr, type, role]) => ({
    code,
    name,
    nameAr,
    type,
    ...(role ? { role } : {}),
  }));

/**
 * Kuwait: IFRS layout with English and Arabic names. Includes the accounts
 * Kuwaiti businesses use every day: KNET settlements, post-dated cheques, 5%
 * contract retentions, PIFSS, end-of-service indemnity, the statutory reserve
 * and the KFAS, Zakat and NLST levies of shareholding companies. There is no
 * VAT in Kuwait; the tax accounts stay unused unless taxes are switched on.
 */
const KUWAIT = bilingual([
  ['1000', 'Bank – current account', 'البنك – الحساب الجاري', 'asset_cash', 'bank'],
  ['1010', 'Petty cash', 'العهدة النقدية', 'asset_cash', 'cash'],
  ['1020', 'KNET and card settlements', 'تسويات كي نت والبطاقات', 'asset_current'],
  ['1030', 'Cheques under collection', 'شيكات تحت التحصيل', 'asset_current'],
  ['1100', 'Accounts receivable', 'الذمم المدينة', 'asset_receivable', 'receivable'],
  ['1110', 'Retentions receivable', 'محتجزات مدينة', 'asset_current'],
  ['1150', 'Post-dated cheques received', 'شيكات آجلة مستلمة', 'asset_current'],
  ['1200', 'Inventory', 'المخزون', 'asset_current'],
  ['1300', 'Prepaid expenses', 'مصروفات مدفوعة مقدماً', 'asset_prepayments'],
  ['1310', 'Refundable deposits', 'تأمينات مستردة', 'asset_current'],
  ['1320', 'Staff advances', 'سلف الموظفين', 'asset_current'],
  ['1350', 'Input tax recoverable', 'ضريبة مدخلات قابلة للاسترداد', 'asset_current', 'input_tax'],
  ['1500', 'Furniture and fixtures', 'الأثاث والتجهيزات', 'asset_fixed'],
  ['1510', 'Accumulated depreciation – furniture', 'مجمع إهلاك الأثاث والتجهيزات', 'asset_fixed'],
  ['1520', 'Office equipment and computers', 'المعدات المكتبية والحاسب الآلي', 'asset_fixed'],
  ['1530', 'Accumulated depreciation – equipment', 'مجمع إهلاك المعدات', 'asset_fixed'],
  ['1540', 'Vehicles', 'السيارات', 'asset_fixed'],
  ['1550', 'Accumulated depreciation – vehicles', 'مجمع إهلاك السيارات', 'asset_fixed'],
  ['1560', 'Leasehold improvements', 'تحسينات على عقارات مستأجرة', 'asset_fixed'],
  ['1570', 'Accumulated depreciation – improvements', 'مجمع إهلاك التحسينات', 'asset_fixed'],
  ['1600', 'Right-of-use assets', 'أصول حق الاستخدام', 'asset_non_current'],
  [
    '1610',
    'Accumulated depreciation – right-of-use assets',
    'مجمع إهلاك أصول حق الاستخدام',
    'asset_non_current',
  ],
  ['1700', 'Intangible assets', 'الأصول غير الملموسة', 'asset_non_current'],
  [
    '1710',
    'Accumulated amortisation – intangible assets',
    'مجمع إطفاء الأصول غير الملموسة',
    'asset_non_current',
  ],
  ['2000', 'Accounts payable', 'الذمم الدائنة', 'liability_payable', 'payable'],
  ['2010', 'Retentions payable', 'محتجزات دائنة', 'liability_current'],
  ['2050', 'Company credit card', 'بطاقة ائتمان الشركة', 'liability_credit_card', 'credit_card'],
  ['2100', 'Output tax', 'ضريبة المخرجات', 'liability_current', 'output_tax'],
  ['2110', 'Tax payable', 'الضريبة المستحقة', 'liability_current', 'tax_settlement'],
  ['2150', 'Post-dated cheques issued', 'شيكات آجلة صادرة', 'liability_current'],
  ['2200', 'Accrued expenses', 'مصروفات مستحقة', 'liability_current'],
  ['2300', 'Salaries payable', 'رواتب مستحقة', 'liability_current'],
  ['2310', 'PIFSS payable', 'التأمينات الاجتماعية المستحقة', 'liability_current'],
  ['2320', 'Leave salary provision', 'مخصص الإجازات', 'liability_current'],
  ['2400', 'Customer advances', 'دفعات مقدمة من العملاء', 'liability_current'],
  ['2500', 'KFAS payable', 'حصة مؤسسة الكويت للتقدم العلمي المستحقة', 'liability_current'],
  ['2510', 'Zakat payable', 'الزكاة المستحقة', 'liability_current'],
  ['2520', 'NLST payable', 'ضريبة دعم العمالة الوطنية المستحقة', 'liability_current'],
  ['2530', 'Income tax payable', 'ضريبة الدخل المستحقة', 'liability_current'],
  ['2550', 'Due to partners', 'مستحق للشركاء', 'liability_current'],
  ['2600', 'Lease liabilities', 'التزامات عقود الإيجار', 'liability_non_current'],
  [
    '2700',
    'End-of-service indemnity provision',
    'مخصص مكافأة نهاية الخدمة',
    'liability_non_current',
  ],
  ['2800', 'Bank loans and financing', 'قروض وتمويلات بنكية', 'liability_non_current'],
  ['3000', 'Capital', 'رأس المال', 'equity', 'capital'],
  ['3100', "Partners' current accounts", 'الحسابات الجارية للشركاء', 'equity', 'drawings'],
  ['3200', 'Statutory reserve', 'الاحتياطي الإجباري', 'equity'],
  ['3210', 'Voluntary reserve', 'الاحتياطي الاختياري', 'equity'],
  ['3300', 'Retained earnings', 'الأرباح المرحلة', 'equity', 'retained_earnings'],
  ['3900', 'Opening balance equity', 'أرصدة افتتاحية', 'equity', 'opening_balance'],
  ['4000', 'Sales', 'المبيعات', 'income', 'sales'],
  ['4100', 'Service revenue', 'إيرادات الخدمات', 'income'],
  ['4150', 'Contract revenue', 'إيرادات العقود', 'income'],
  ['4200', 'Delivery charges income', 'إيرادات التوصيل', 'income', 'charges'],
  ['4500', 'Other income', 'إيرادات أخرى', 'income_other'],
  ['4520', 'Gain or loss on disposal of assets', 'أرباح وخسائر استبعاد الأصول', 'income_other'],
  ['5000', 'Cost of sales', 'تكلفة المبيعات', 'expense_direct_cost', 'cost_of_sales'],
  ['5100', 'Subcontractor costs', 'تكاليف مقاولي الباطن', 'expense_direct_cost'],
  ['5200', 'Customs duty and freight', 'الرسوم الجمركية والشحن', 'expense_direct_cost'],
  ['5300', 'Inventory adjustments', 'تسويات المخزون', 'expense_direct_cost'],
  ['6000', 'General and administrative expenses', 'مصروفات عمومية وإدارية', 'expense', 'expense'],
  ['6010', 'Salaries and wages', 'الرواتب والأجور', 'expense'],
  ['6020', 'Allowances', 'البدلات', 'expense'],
  ['6030', 'PIFSS – employer share', 'حصة صاحب العمل في التأمينات الاجتماعية', 'expense'],
  ['6040', 'End-of-service indemnity', 'مكافأة نهاية الخدمة', 'expense'],
  ['6050', 'Leave salary', 'رواتب الإجازات', 'expense'],
  ['6060', 'Rent', 'الإيجار', 'expense'],
  ['6070', 'Electricity and water', 'الكهرباء والماء', 'expense'],
  ['6080', 'Telephone and internet', 'الهاتف والإنترنت', 'expense'],
  [
    '6090',
    'Government fees, visas and residency',
    'الرسوم الحكومية والتأشيرات والإقامات',
    'expense',
  ],
  ['6100', 'Commercial licence and chamber fees', 'رسوم الرخصة التجارية والغرفة', 'expense'],
  ['6110', 'Marketing and advertising', 'الدعاية والإعلان', 'expense'],
  ['6120', 'Professional and audit fees', 'الأتعاب المهنية ورسوم التدقيق', 'expense'],
  ['6130', 'Travel', 'السفر', 'expense'],
  ['6140', 'Stationery and printing', 'القرطاسية والمطبوعات', 'expense'],
  ['6150', 'Repairs and maintenance', 'الإصلاح والصيانة', 'expense'],
  ['6160', 'Insurance', 'التأمين', 'expense'],
  ['6170', 'Bank charges', 'العمولات والمصاريف البنكية', 'expense', 'bank_fees'],
  ['6180', 'KNET and card fees', 'عمولات كي نت والبطاقات', 'expense'],
  ['6190', 'Software and subscriptions', 'البرامج والاشتراكات', 'expense'],
  ['6200', 'Vehicle expenses', 'مصروفات السيارات', 'expense'],
  ['6210', 'Postage and courier', 'البريد والتوصيل', 'expense'],
  ['6220', 'Hospitality', 'الضيافة', 'expense'],
  ['6230', 'Bad debts', 'الديون المعدومة', 'expense'],
  ['6900', 'Depreciation', 'الإهلاك', 'expense_depreciation'],
  ['7000', 'Exchange gain or loss', 'أرباح وخسائر فروق العملة', 'expense_other', 'fx'],
  ['7100', 'Finance costs', 'تكاليف التمويل', 'expense_other'],
  ['7200', 'KFAS contribution', 'حصة مؤسسة الكويت للتقدم العلمي', 'expense_other'],
  ['7210', 'Zakat', 'الزكاة', 'expense_other'],
  ['7220', 'National Labour Support Tax', 'ضريبة دعم العمالة الوطنية', 'expense_other'],
  ['7230', 'Income tax', 'ضريبة الدخل', 'expense_other'],
]);

export const CHART_TEMPLATES: Record<ChartTemplateId, { name: string; accounts: ChartAccount[] }> =
  {
    kw: { name: 'Kuwait', accounts: KUWAIT },
    generic: { name: 'Standard', accounts: GENERIC },
    uk: { name: 'United Kingdom', accounts: UK },
    ae: { name: 'United Arab Emirates', accounts: UAE },
  };

/** Kuwait is the default; the others remain for companies created before. */
export function chartTemplateFor(country: string): ChartTemplateId {
  if (country === 'GB') return 'uk';
  if (country === 'AE') return 'ae';
  if (country === 'KW' || !country) return 'kw';
  return 'generic';
}

/* -------------------------------------------------------------------------- */
/* Accounts the app looks up by code                                          */
/* -------------------------------------------------------------------------- */

/**
 * Accounts some postings and statements need that have no role: reserves,
 * levies, depreciation. Kuwait charts are matched by code; charts started from
 * another template by name. When none matches, the account is created.
 */
export interface AccountSpec {
  code: string;
  name: string;
  nameAr: string;
  type: AccountType;
  /** Recognises the account by its English name in other charts. */
  match: RegExp;
}

const spec = (
  code: string,
  name: string,
  nameAr: string,
  type: AccountType,
  match: RegExp,
): AccountSpec => ({ code, name, nameAr, type, match });

export const ACCOUNT_SPECS = {
  statutoryReserve: spec(
    '3200',
    'Statutory reserve',
    'الاحتياطي الإجباري',
    'equity',
    /statutory|legal reserve/i,
  ),
  voluntaryReserve: spec(
    '3210',
    'Voluntary reserve',
    'الاحتياطي الاختياري',
    'equity',
    /voluntary|general reserve/i,
  ),
  depreciation: spec(
    '6900',
    'Depreciation',
    'الإهلاك',
    'expense_depreciation',
    /depreciation|amorti[sz]ation/i,
  ),
  disposal: spec(
    '4520',
    'Gain or loss on disposal of assets',
    'أرباح وخسائر استبعاد الأصول',
    'income_other',
    /disposal|sale of (fixed )?assets/i,
  ),
  financeCosts: spec(
    '7100',
    'Finance costs',
    'تكاليف التمويل',
    'expense_other',
    /finance cost|interest (expense|paid)|loan interest/i,
  ),
  kfas: spec(
    '7200',
    'KFAS contribution',
    'حصة مؤسسة الكويت للتقدم العلمي',
    'expense_other',
    /kfas/i,
  ),
  kfasPayable: spec(
    '2500',
    'KFAS payable',
    'حصة مؤسسة الكويت للتقدم العلمي المستحقة',
    'liability_current',
    /kfas/i,
  ),
  zakat: spec('7210', 'Zakat', 'الزكاة', 'expense_other', /zakat/i),
  zakatPayable: spec('2510', 'Zakat payable', 'الزكاة المستحقة', 'liability_current', /zakat/i),
  nlst: spec(
    '7220',
    'National Labour Support Tax',
    'ضريبة دعم العمالة الوطنية',
    'expense_other',
    /nlst|labou?r support/i,
  ),
  nlstPayable: spec(
    '2520',
    'NLST payable',
    'ضريبة دعم العمالة الوطنية المستحقة',
    'liability_current',
    /nlst|labou?r support/i,
  ),
  incomeTax: spec('7230', 'Income tax', 'ضريبة الدخل', 'expense_other', /income tax/i),
  incomeTaxPayable: spec(
    '2530',
    'Income tax payable',
    'ضريبة الدخل المستحقة',
    'liability_current',
    /income tax/i,
  ),
  retentionsReceivable: spec(
    '1110',
    'Retentions receivable',
    'محتجزات مدينة',
    'asset_current',
    /retentions? (receivable|held by customers)/i,
  ),
  retentionsPayable: spec(
    '2010',
    'Retentions payable',
    'محتجزات دائنة',
    'liability_current',
    /retentions? (payable|held from vendors)/i,
  ),
  endOfService: spec(
    '2700',
    'End-of-service indemnity provision',
    'مخصص مكافأة نهاية الخدمة',
    'liability_non_current',
    /end.of.service|indemnity|gratuity/i,
  ),
  inventory: spec('1200', 'Inventory', 'المخزون', 'asset_current', /inventor|stock/i),
  /** Used only when the chart has no cost of sales account for automatic postings. */
  costOfSales: spec(
    '5000',
    'Cost of sales',
    'تكلفة المبيعات',
    'expense_direct_cost',
    /cost of (sales|goods)/i,
  ),
  inventoryAdjustments: spec(
    '5300',
    'Inventory adjustments',
    'تسويات المخزون',
    'expense_direct_cost',
    /(inventory|stock) (adjustment|write)/i,
  ),
  /** Uniforms and other stock handed to employees (see db/stock-issues.ts). */
  issuedItems: spec(
    '6240',
    'Items issued to employees',
    'مواد مصروفة للموظفين',
    'expense',
    /uniform|issued to (employees|staff)/i,
  ),
} satisfies Record<string, AccountSpec>;

export type AccountSpecKey = keyof typeof ACCOUNT_SPECS;

/**
 * The company's account for a spec, or undefined. Kuwait charts match by
 * code (accounts may have been renamed); others by name. Accounts used for
 * automatic postings (with a role) never match.
 */
export function findSpecAccount(
  accounts: Account[],
  key: AccountSpecKey,
  template: ChartTemplateId,
): Account | undefined {
  const s: AccountSpec = ACCOUNT_SPECS[key];
  const candidates = accounts
    .filter((a) => a.type === s.type && !a.role)
    .sort((a, b) => Number(a.archived) - Number(b.archived));
  if (template === 'kw') {
    const byCode = candidates.find((a) => a.code === s.code);
    if (byCode) return byCode;
  }
  return (
    candidates.find((a) => a.name.trim().toLowerCase() === s.name.toLowerCase()) ??
    candidates.find((a) => a.nameAr?.trim() === s.nameAr) ??
    candidates.find((a) => s.match.test(a.name))
  );
}

/** A code for a new account: the spec's own when free, else the next free one after it. */
export function freeCode(accounts: Pick<Account, 'code'>[], wanted: string): string {
  const taken = new Set(accounts.map((a) => a.code));
  if (!taken.has(wanted)) return wanted;
  const base = Number(wanted);
  if (!Number.isFinite(base)) {
    let i = 2;
    while (taken.has(`${wanted}-${i}`)) i += 1;
    return `${wanted}-${i}`;
  }
  const width = wanted.length;
  let next = base + 1;
  while (taken.has(String(next).padStart(width, '0'))) next += 1;
  return String(next).padStart(width, '0');
}
