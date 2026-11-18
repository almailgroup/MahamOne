import { msg, type Dictionary } from '@/i18n';
import type { DataTable } from '@/db/db';
import type { CloudErrorCode } from './api';

/** What a synced record is, in words (English keys). */
export const RECORD_LABELS: Record<DataTable, string> = {
  companies: msg('Company settings'),
  clients: msg('Contact'),
  products: msg('Item'),
  taxRates: msg('Tax rate'),
  documents: msg('Document'),
  payments: msg('Payment'),
  recurring: msg('Recurring invoice'),
  activities: msg('Activity entry'),
  accounts: msg('Account'),
  journals: msg('Journal'),
  expenses: msg('Expense'),
  attachments: msg('File'),
  vatReturns: msg('Tax return'),
  bankTransactions: msg('Bank statement line'),
  employees: msg('Employee'),
  complianceDocuments: msg('Document in the register'),
  renewals: msg('Renewal'),
  complianceMarks: msg('Compliance item'),
  peopleSettings: msg('People settings'),
  securityCheques: msg('Security cheque'),
  assets: msg('Fixed asset'),
  depreciationRuns: msg('Depreciation run'),
  yearEnds: msg('Year-end close'),
  payRuns: msg('Pay run'),
  payrollSettings: msg('Payroll settings'),
  leaveRecords: msg('Leave'),
  staffLoans: msg('Staff loan'),
  finalSettlements: msg('Final settlement'),
  warehouses: msg('Warehouse'),
  stockMovements: msg('Stock movement'),
  stockEntries: msg('Stock entry'),
  landedCosts: msg('Landed cost'),
  chequeLayouts: msg('Cheque layout'),
  vehicles: msg('Vehicle'),
  approvals: msg('Approval request'),
  letterTemplates: msg('Letter template'),
  employeeLetters: msg('Employee letter'),
  staffingCostings: msg('Manpower costing'),
  stockIssues: msg('Items issued'),
};

/** Why a change was refused, for the list of sync problems. */
export const PARKED_REASONS: Partial<Record<CloudErrorCode, string>> = {
  permission: msg('Your role can’t make this change.'),
  too_large: msg('Too large to sync.'),
  invalid: msg('The cloud did not accept it.'),
  server_outdated: msg(
    'The cloud needs the latest database script first. Ask the owner of the company to run it.',
  ),
  approval_required: msg('This change needs approval.'),
};

/**
 * The company settings a field of the company record belongs to, as Settings
 * names them. The first entry the field's path starts with wins.
 */
const COMPANY_SETTINGS: [path: string, label: string][] = [
  ['name', msg('Company name')],
  ['nameAr', msg('Arabic name')],
  ['legalName', msg('Legal name')],
  ['email', msg('Email')],
  ['phone', msg('Phone')],
  ['website', msg('Website')],
  ['taxIdLabel', msg('Tax number')],
  ['taxId', msg('Tax number')],
  ['registrationLabel', msg('Registration number')],
  ['registrationNumber', msg('Registration number')],
  ['kuwait', msg('Registration')],
  ['companyType', msg('Company type')],
  ['address', msg('Address')],
  ['currency', msg('Currency')],
  ['currencyDisplay', msg('Currency')],
  ['locale', msg('Regional settings')],
  ['dateFormat', msg('Date format')],
  ['holidays', msg('Public holidays')],
  ['language', msg('Document language')],
  ['branding', msg('Branding')],
  ['defaults.paymentTermsDays', msg('Due dates')],
  ['defaults.quoteValidDays', msg('Due dates')],
  ['defaults.pricesIncludeTax', msg('How taxes are applied')],
  ['defaults.lineTaxes', msg('How taxes are applied')],
  ['defaults.documentTaxes', msg('How taxes are applied')],
  ['defaults.defaultTaxRateIds', msg('How taxes are applied')],
  ['defaults.pageSize', msg('Currency and paper')],
  ['defaults', msg('Default text')],
  ['taxesEnabled', msg('Tax')],
  ['numbering', msg('Number formats')],
  ['payment', msg('Payment details for documents')],
  ['bankAccount', msg('Bank account')],
  ['labels', msg('Custom wording')],
  ['emailTemplates', msg('Email templates')],
  ['accounting.lockDate', msg('Lock date')],
  ['accounting.fiscalYearEnd', msg('Financial year')],
  ['accounting.vat', msg('VAT returns')],
  ['accounting', msg('Accounting')],
  ['openingBalances', msg('Opening balances')],
  ['links', msg('Links in the sidebar')],
  ['registerExtras', msg('Contracts, customers and vehicles')],
  ['documentPurposes', msg('Purposes of documents')],
  ['fileFinder', msg('Find files and papers')],
  ['items', msg('Items and units')],
  ['vouchers', msg('Receipt and payment vouchers')],
  ['chequePrinting', msg('Cheque printing')],
  ['dashboard', msg('Books dashboard')],
  ['appLayout', msg('App layout')],
  ['approvalRules', msg('Approvals')],
  ['ai', msg('AI assistant')],
];

/** The settings fields of the company record belong to, each once (English keys). */
export function companySettingLabels(paths: string[][]): string[] {
  const labels = paths.map((path) => {
    const field = path.join('.');
    const found = COMPANY_SETTINGS.find(
      ([prefix]) => field === prefix || field.startsWith(`${prefix}.`),
    );
    return found ? found[1] : msg('Other settings');
  });
  return [...new Set(labels)];
}

const arabicParts = import.meta.glob<{ default: Dictionary }>('../i18n/ar/*.ts');
let arabic: Promise<Dictionary> | null = null;

/**
 * Interface words (English keys) in Arabic, whatever language the app is in
 * now: a log entry keeps them for Arabic readers. A word without Arabic stays
 * as it is.
 */
export async function inArabic(words: string[]): Promise<string[]> {
  arabic ??= Promise.all(Object.values(arabicParts).map((load) => load())).then(
    (parts) => Object.assign({}, ...parts.map((part) => part.default)) as Dictionary,
    (error: unknown) => {
      arabic = null;
      throw error;
    },
  );
  const dictionary = await arabic;
  return words.map((word) => {
    const found = dictionary[word];
    return typeof found === 'string' ? found : (found?.other ?? word);
  });
}
