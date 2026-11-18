import type { DiscountType, TaxKind, TaxLine } from '@/lib/calc';
import type { CsvMapping } from '@/lib/banking/statement';
import type { PrintableDocumentType } from '@/lib/document-types';

export type { DiscountType, TaxKind, TaxLine };

export type ID = string;
/** Calendar date in `yyyy-MM-dd` form (no time zone). */
export type ISODate = string;
/** Full ISO 8601 timestamp. */
export type Timestamp = string;

export interface Address {
  line1: string;
  line2: string;
  /** Area in Kuwait (e.g. "Salmiya"), city elsewhere. */
  city: string;
  /** Governorate in Kuwait (e.g. "Hawalli"), state or region elsewhere. */
  state: string;
  postalCode: string;
  /** ISO 3166-1 alpha-2 code, e.g. "KW". */
  country: string;
  /** Kuwaiti addresses: block (قطعة). */
  block?: string;
  street?: string;
  /** Avenue (جادة). */
  avenue?: string;
  /** Building or house number. */
  building?: string;
  floor?: string;
  /** Office, flat or shop number. */
  unit?: string;
  /** PACI automated address number (الرقم الآلي للعنوان). */
  paci?: string;
}

/**
 * Sales documents (invoice, quote, credit note, proforma invoice, sales order,
 * delivery note) and purchase documents (bill, vendor credit, purchase order).
 * Only invoices, credit notes, bills and vendor credits are part of the books;
 * quotes, proformas, orders and delivery notes never post to the ledger.
 */
export type DocumentType =
  | 'invoice'
  | 'quote'
  | 'credit'
  | 'bill'
  | 'vendor_credit'
  | 'proforma'
  | 'sales_order'
  | 'purchase_order'
  | 'delivery_note';
/** Sales documents that have an email template of their own. */
export type SalesDocumentType = 'invoice' | 'quote' | 'credit';
/** Documents entered with the bill editor (vendor, category accounts). */
export type PurchaseDocumentType = 'bill' | 'vendor_credit' | 'purchase_order';
/** Documents that never post to the ledger and never count in sales or purchases. */
export type OrderDocumentType = 'proforma' | 'sales_order' | 'purchase_order' | 'delivery_note';

export type InvoiceStatus = 'draft' | 'sent' | 'partial' | 'paid' | 'void';
/** "converted": turned into a proforma invoice or a sales order. */
export type QuoteStatus = 'draft' | 'sent' | 'accepted' | 'declined' | 'invoiced' | 'converted';
export type CreditStatus = 'draft' | 'sent' | 'partial' | 'applied' | 'void';
/** "Expired" is shown for sent proformas past their valid-until date. */
export type ProformaStatus = 'draft' | 'sent' | 'accepted' | 'converted';
/** Invoicing progress is derived from the invoices created from the order. */
export type SalesOrderStatus =
  'draft' | 'confirmed' | 'partially_invoiced' | 'invoiced' | 'cancelled';
/** Billing progress is derived from the bills created from the order. */
export type PurchaseOrderStatus = 'draft' | 'issued' | 'partially_billed' | 'billed' | 'cancelled';
export type DeliveryNoteStatus = 'draft' | 'delivered' | 'cancelled';
export type DocumentStatus =
  | InvoiceStatus
  | QuoteStatus
  | CreditStatus
  | ProformaStatus
  | SalesOrderStatus
  | PurchaseOrderStatus
  | DeliveryNoteStatus;

/** How much of a sales order has been delivered (signed delivery notes). */
export type DeliveryStatus = 'not_delivered' | 'partially_delivered' | 'delivered';

/**
 * `product`: item codes (SKUs), given only when Company.items.autoSku is on.
 * `letter`: employee letters (#19), numbered when they are issued; company
 * records saved before have no rule for it (defaultNumbering's is used).
 */
export type NumberedEntity =
  | DocumentType
  | 'payment'
  | 'payment_made'
  | 'client'
  | 'journal'
  | 'expense'
  | 'employee'
  | 'product'
  | 'letter';

export type CounterReset = 'never' | 'yearly' | 'monthly';

export interface NumberingRule {
  /** e.g. "INV-{year}-{counter}". See lib/numbering.ts for placeholders. */
  pattern: string;
  /** Next counter value to use. */
  next: number;
  /** Minimum digits of the counter (zero padded). */
  padding: number;
  reset: CounterReset;
  /** Period key ("2026" or "2026-10") the counter was last used in; drives resets. */
  period: string;
}

export type DateFormat =
  | 'locale'
  | 'dd/MM/yyyy'
  | 'MM/dd/yyyy'
  | 'yyyy-MM-dd'
  | 'dd.MM.yyyy'
  | 'dd-MM-yyyy'
  | 'd MMM yyyy'
  | 'MMM d, yyyy';

export type PageSize = 'A4' | 'LETTER';

/**
 * Language used for the words printed on documents. `ar-en` is bilingual:
 * Arabic first (right to left), with English next to it.
 */
export type DocumentLanguage = 'ar-en' | 'ar' | 'en' | 'fr' | 'es' | 'de' | 'pt' | 'it' | 'nl';

export interface DocumentDefaults {
  /** Days between issue date and due date for new invoices. */
  paymentTermsDays: number;
  /** Days a quote stays valid. */
  quoteValidDays: number;
  invoiceNotes: string;
  invoiceTerms: string;
  quoteNotes: string;
  quoteTerms: string;
  creditNotes: string;
  creditTerms: string;
  footer: string;
  pricesIncludeTax: boolean;
  /** Show per-line tax selection in the editor. */
  lineTaxes: boolean;
  /** Show document-level (whole invoice) taxes in the editor. */
  documentTaxes: boolean;
  /** Tax rates applied automatically to new lines (line mode) or new documents (document mode). */
  defaultTaxRateIds: ID[];
  pageSize: PageSize;
  /** Print the total in words under the totals. Missing means on for Kuwaiti companies. */
  showAmountInWords?: boolean;
  /** Print the Hijri (Umm al-Qura) date next to the issue date. */
  showHijriDate?: boolean;
  /**
   * What the QR code on unpaid invoices opens: the payment link, or the
   * invoice's own pay page once online payments are set up. Missing is the
   * payment link. Whether it prints at all is `PaymentSettings.showQrCode`.
   */
  qrContent?: QrContent;
  /** A few lines new quotes start with, printed above the items. Missing means none. */
  quoteIntro?: string;
  /**
   * Invoices and credit notes get their number when they are issued, not
   * when a draft is first saved, so a draft deleted never uses one up.
   * Missing or false: drafts are numbered when first saved, as before.
   */
  numberOnIssue?: boolean;
}

/** What a printed QR code opens. */
export type QrContent = 'payment_link' | 'pay_page';

/** Ink of the printed signature: as uploaded, or recoloured to blue pen ink. */
export type SignatureInk = 'original' | 'blue';

export interface Branding {
  /** Hex color used as the accent in templates, e.g. "#4f46e5". */
  accentColor: string;
  /** Default template id (see pdf/templates). */
  templateId: string;
  /** Logo as a data URL (PNG/JPEG), stored locally. */
  logo: string | null;
  /** Font override; null uses the template's own font pairing. */
  fontId: string | null;
  /** Print a PAID / VOID stamp on settled or cancelled documents. */
  showStatusStamp: boolean;
  /** Company stamp (seal) image as a data URL, printed near the signature. */
  stamp?: string | null;
  /** Authorised signature image as a data URL. */
  signature?: string | null;
  /**
   * The signature's ink. With 'blue', `signature` holds the blue version,
   * made once when it was uploaded (so every version prints it as it is),
   * and `signatureOriginal` the upload. Missing is 'original'.
   */
  signatureInk?: SignatureInk;
  /** The signature as uploaded (at most 600 px), kept while it prints in blue. */
  signatureOriginal?: string | null;
  /** Layout of the company's documents (Templates). Missing prints as before. */
  layout?: DocumentLayout;
  /**
   * Types of document with a design of their own (quotes, credit notes).
   * A type missing here, and what its design leaves out, use the template,
   * colour and layout above.
   */
  byType?: Partial<Record<PrintableDocumentType, DocumentDesign>>;
}

/** How large the logo prints, against the size its template gives it. */
export type LogoSize = 'small' | 'medium' | 'large';

/**
 * The logo on a line of its own above the header: at the start (left in
 * English, right in Arabic), in the centre or at the end.
 */
export type LogoPosition = 'start' | 'center' | 'end';

/** Layout choices of a document design; each one missing prints as before. */
export interface DocumentLayout {
  /** Missing is medium: the template's own size. */
  logoSize?: LogoSize;
  /** Missing is where the template puts the logo. */
  logoPosition?: LogoPosition;
  /** A column with the SKU of lines picked from an item that has one. */
  showSku?: boolean;
  /** A picture beside each item that has one. */
  showItemImages?: boolean;
  /** Quotes and proformas: a box for the customer to accept, sign and date. */
  showAcceptance?: boolean;
}

/** A type of document's own design; what it leaves out follows the company's. */
export interface DocumentDesign {
  templateId?: string;
  /** Hex colour, e.g. "#0f766e". */
  accentColor?: string;
  /** Replaces the company's layout as a whole. */
  layout?: DocumentLayout;
}

export interface PaymentSettings {
  /** Free text shown on documents, e.g. bank name, IBAN, SWIFT. */
  bankDetails: string;
  /** Short instruction such as "Please quote the invoice number as reference." */
  instructions: string;
  /** Online payment link (Stripe Payment Link, PayPal.me, ...). */
  paymentLink: string;
  /** Print a QR code for the payment link on documents. */
  showQrCode: boolean;
}

export interface EmailTemplate {
  subject: string;
  body: string;
}

export interface EmailTemplates {
  invoice: EmailTemplate;
  quote: EmailTemplate;
  credit: EmailTemplate;
  reminder: EmailTemplate;
  payment: EmailTemplate;
}

/* -------------------------------------------------------------------------- */
/* Accounting                                                                 */
/* -------------------------------------------------------------------------- */

/**
 * What an account is. The type decides where it appears in the financial
 * statements, so reports never depend on account codes.
 */
export type AccountType =
  | 'asset_cash'
  | 'asset_receivable'
  | 'asset_current'
  | 'asset_prepayments'
  | 'asset_fixed'
  | 'asset_non_current'
  | 'liability_payable'
  | 'liability_credit_card'
  | 'liability_current'
  | 'liability_non_current'
  | 'equity'
  | 'income'
  | 'income_other'
  | 'expense_direct_cost'
  | 'expense'
  | 'expense_depreciation'
  | 'expense_other';

/** System accounts the app posts to automatically (one per role and company). */
export type AccountRole =
  | 'receivable'
  | 'payable'
  | 'bank'
  | 'cash'
  | 'credit_card'
  | 'sales'
  | 'charges'
  | 'output_tax'
  | 'input_tax'
  | 'tax_settlement'
  | 'fx'
  | 'capital'
  | 'drawings'
  | 'retained_earnings'
  | 'opening_balance'
  | 'cost_of_sales'
  | 'expense'
  | 'bank_fees';

export interface BankDetails {
  institution: string;
  accountNumber: string;
  iban: string;
  bic: string;
}

export interface Account {
  id: ID;
  companyId: ID;
  code: string;
  name: string;
  /** Arabic name, shown in the Arabic interface and Arabic reports. */
  nameAr?: string;
  type: AccountType;
  description: string;
  /** Set on the accounts the app posts to automatically. */
  role: AccountRole | null;
  /** Bank, cash and card accounts can hold the details printed on documents. */
  bank: BankDetails | null;
  /** How this account's statements are laid out, when an import was asked to remember it. */
  statementFormat?: StatementFormat;
  archived: boolean;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/**
 * A bank account's statement layout, remembered from an import so the next
 * statement is read the same way. Missing: the layout is guessed each time.
 */
export interface StatementFormat {
  /** The file it was read from; 'html' also covers Excel 2003 XML. 'pdf' is not read yet. */
  kind: 'csv' | 'xlsx' | 'html' | 'pdf';
  /** The row of the file the table started at (0 is the first). */
  headerRow: number;
  mapping: CsvMapping;
  /** The way amounts were shown (src/lib/banking/presets.ts). */
  preset?: string;
  /**
   * The column names, to find the table again when there are more or fewer
   * rows above it (the period, a second line of address).
   */
  columns?: string[];
}

export interface JournalLine {
  id: ID;
  accountId: ID;
  description: string;
  debit: number;
  credit: number;
  /** Client or vendor the line relates to (for receivable/payable accounts). */
  contactId: ID | null;
}

/** A manual journal entry in the company currency. */
export interface ManualJournal {
  id: ID;
  companyId: ID;
  number: string;
  date: ISODate;
  reference: string;
  notes: string;
  status: 'draft' | 'posted';
  lines: JournalLine[];
  /** Set on the entry that closes a VAT return (see VatReturn). */
  vatReturnId?: ID | null;
  /**
   * Set on entries the app makes itself (see JournalKind): transfers between
   * the company's own accounts, cheque clearings and returns, payroll,
   * depreciation, fixed assets and year-end entries. Entries owned by another
   * part of the app can only be changed there.
   */
  kind?: JournalKind;
  /** Payment the entry belongs to (cheque clearings and their reversals). */
  paymentId?: ID | null;
  /** Record the entry was made for (fixed asset, depreciation run, year-end close…). */
  sourceId?: ID | null;
  /** Entry this one reverses; reversals keep the history instead of deleting it. */
  reversalOf?: ID | null;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

export type ChartTemplateId = 'kw' | 'generic' | 'uk' | 'ae';

export interface AccountingSettings {
  /** Chart of accounts the company started from. */
  template: ChartTemplateId;
  /** Last day of the financial year, e.g. { month: 12, day: 31 }. */
  fiscalYearEnd: { month: number; day: number };
  /** Transactions dated on or before this date can't be added, changed or deleted. */
  lockDate: ISODate | null;
  /** Missing until VAT returns are set up; see vatSettings(). */
  vat?: VatSettings;
  /** Kuwaiti levies and statutory reserve rates; missing means the defaults (see levyRates()). */
  levies?: LevyRates;
}

export type VatFormat = 'uk' | 'ae' | 'generic';

export interface VatSettings {
  registered: boolean;
  /** Which return the boxes follow. */
  format: VatFormat;
  frequency: 'monthly' | 'quarterly';
  /** Month (1–12) a quarter starts in (the UK "stagger"). */
  startMonth: number;
  /** UAE: emirate code (AZ, DU, SH, AJ, UQ, RK, FU) the business is established in. */
  emirate: string | null;
}

/** Where a bank statement line was found in the books. */
export interface BankMatch {
  source: 'payment' | 'expense' | 'journal';
  id: ID;
}

/** A line of an imported bank statement. */
export interface BankTransaction {
  id: ID;
  companyId: ID;
  /** The bank, cash or card account the statement belongs to. */
  accountId: ID;
  date: ISODate;
  description: string;
  reference: string;
  /** Company currency; positive is money in, negative money out. */
  amount: number;
  /** Running balance after the line, when the statement gives it. */
  balance: number | null;
  /** The value date, when the statement gives one. */
  valueDate?: ISODate;
  /** Identifies the line so a statement imported twice adds nothing. */
  fingerprint: string;
  importId: ID;
  /** Order within the import, to keep same-day lines in statement order. */
  position: number;
  match: BankMatch | null;
  /** Left out of the reconciliation on purpose. */
  ignored: boolean;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/** A filed VAT return: the boxes as filed and the entry that closed it. */
export interface VatReturnRecord {
  id: ID;
  companyId: ID;
  periodStart: ISODate;
  periodEnd: ISODate;
  format: VatFormat;
  /** Minor units of `currency`, as filed. */
  boxes: { id: string; label: string; amount: number; vat?: number }[];
  /** Positive: paid to the tax office; negative: reclaimed. Minor units. */
  net: number;
  currency: string;
  filedOn: ISODate;
  /** Submission receipt or reference from the tax office. */
  reference: string;
  /** Manual journal moving the period's VAT to the VAT liability account. */
  journalId: ID | null;
  /** Manual journal recording the payment (or refund). */
  paymentJournalId: ID | null;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/** Legal form of a Kuwaiti business; decides statutory reserve and levies. */
export type LegalForm =
  | 'sole_proprietorship'
  | 'wll'
  | 'spc'
  | 'general_partnership'
  | 'limited_partnership'
  | 'kscc'
  | 'ksc_listed'
  | 'foreign_branch'
  | 'freelance'
  | 'other';

/** Business activity; some activities may not take cash (see lib/kuwait-rules.ts). */
export type BusinessActivity =
  | 'general'
  | 'health'
  | 'salon'
  | 'sports_club'
  | 'pest_control'
  | 'vehicles'
  | 'gold_jewellery'
  | 'real_estate';

/** Kuwaiti registration details. Missing on companies created before; see kuwaitProfile(). */
export interface KuwaitProfile {
  legalForm: LegalForm;
  /** What the legal form is, when it is "other". Kept for the records; nothing is computed from it. */
  legalFormOther?: string;
  /** Commercial licence number (رقم الرخصة التجارية). The CR number is registrationNumber. */
  licenceNumber: string;
  activity: BusinessActivity;
  /** Share of the company owned by non-GCC foreign shareholders, 0–100 (15% income tax). */
  foreignOwnershipPercent: number;
  /** Paid-up capital in the company currency (the statutory reserve stops at 50% of it). */
  capital: number;
  /** Public Authority for Manpower company file number. */
  pamFileNumber: string;
  /** PIFSS employer (social security) number. */
  pifssEmployerNumber: string;
  /** Ministry of Finance tax card number. */
  mofTaxCardNumber: string;
  /** Kuwait Chamber of Commerce and Industry membership number. */
  kcciNumber: string;
  /** MOCI digital commerce registration number (online sellers). */
  digitalCommerceNumber: string;
  /** Mobile number registered for WAMD instant payments. */
  wamdPhone: string;
}

/**
 * The bank account printed on documents. `payment.bankDetails` (the text the
 * documents print) is composed from it; see features/company/bank.ts.
 */
export interface CompanyBankAccount {
  /** First four letters of the SWIFT code of a Kuwaiti bank (KUWAIT_BANKS), or '' for another bank. */
  bankCode: string;
  /** Name of a bank that is not in the list. */
  bankName: string;
  accountName: string;
  /** Stored without spaces, upper case. */
  iban: string;
  accountNumber: string;
  swift: string;
  /** Free text printed after the account details. */
  extra: string;
}

/**
 * The company's line of business (security services, manpower supply,
 * trading…). Built-in types have fixed ids and others an id that follows
 * from the name, so the same type groups companies on every device (see
 * features/company/company-types.ts). Taxes and deadlines don't depend on it.
 */
export interface CompanyType {
  id: ID;
  name: string;
  nameAr?: string;
}

/** A public holiday as the company observes it (overrides the official estimates). */
export interface CompanyHoliday {
  date: ISODate;
  name: string;
  nameAr: string;
}

export interface Company {
  id: ID;
  name: string;
  /** Trade name in Arabic, printed on Arabic and bilingual documents. */
  nameAr?: string;
  legalName: string;
  email: string;
  phone: string;
  website: string;
  /** Label for the tax number, e.g. "VAT No.", "TRN", "EIN", "GST No.". */
  taxIdLabel: string;
  taxId: string;
  registrationLabel: string;
  registrationNumber: string;
  address: Address;
  currency: string;
  /**
   * "local" writes Kuwaiti dinars as KD / د.ك (the default in Kuwait),
   * "code" as KWD. Missing means "local".
   */
  currencyDisplay?: 'code' | 'local';
  /** BCP 47 locale used for number and date formatting, e.g. "en-KW". */
  locale: string;
  dateFormat: DateFormat;
  language: DocumentLanguage;
  branding: Branding;
  defaults: DocumentDefaults;
  numbering: Record<NumberedEntity, NumberingRule>;
  payment: PaymentSettings;
  /** Overrides for words printed on documents (see pdf/labels.ts). */
  labels: Record<string, string>;
  emailTemplates: EmailTemplates;
  /** Missing on companies created before accounting existed (see ensureAccounting). */
  accounting?: AccountingSettings;
  kuwait?: KuwaitProfile;
  /** Line of business, shown with the company's name. Missing until chosen. */
  companyType?: CompanyType;
  /**
   * The business charges tax (VAT or sales tax). Missing on companies created
   * before: they charge tax when they have tax rates (see taxesEnabled()).
   */
  taxesEnabled?: boolean;
  /** Bank account printed on documents; missing until set up. */
  bankAccount?: CompanyBankAccount;
  /**
   * Public holidays the company changed. Years without an entry use the
   * official estimates (kuwaitHolidays).
   */
  holidays?: CompanyHoliday[];
  /** Date the opening balances were imported as at, and the entries that hold them. */
  openingBalances?: { date: ISODate; journalIds: ID[] };
  /** The demo company: it stays on the device it was made on and never goes to the cloud. */
  demo?: boolean;
  /** The company's other tools (a task manager, an HR portal…), in the sidebar. */
  links?: CompanyLink[];
  /**
   * Contracts, customers' papers, vehicles and confidential documents in the
   * documents register (Compliance → Settings). Missing or false: the
   * register as before.
   */
  registerExtras?: boolean;
  /** What register documents are for (a tender, a site, a bank facility…); missing until one is added. */
  documentPurposes?: DocumentPurpose[];
  /**
   * The document finder (Compliance → Settings): the Files page, and search
   * over files, register papers, expenses, fixed assets and security
   * cheques. Missing or false: neither, as before.
   */
  fileFinder?: boolean;
  /** Receipt and payment vouchers; missing prints them as before. */
  vouchers?: VoucherSettings;
  /**
   * Units from a list, automatic item codes and item pictures; missing types
   * units and codes by hand and gives items no pictures, as before.
   */
  items?: ItemSettings;
  /**
   * Cheques issued can be printed onto the bank's leaves (Burgan Bank, KFH)
   * from the payment and the cheque register, with the layouts in Cheques →
   * Cheque layouts. Missing: cheques are written by hand, as before.
   */
  chequePrinting?: boolean;
  /** How the Books dashboard is laid out; missing shows it as before. */
  dashboard?: DashboardSettings;
  /**
   * How Maham One lays out its apps (Settings → Team), for everyone in the
   * company: 'split' takes Maham Sales (quotes, orders, invoices, payments
   * received, customers) and Maham Inventory (items and stock) out of Maham
   * Books, which keeps purchases, cheques, banking, accounting and reports
   * and lists invoices under Receivables. The same pages at the same
   * addresses either way. Missing (or a value this build doesn't know):
   * today's four apps.
   */
  appLayout?: 'split';
  /**
   * The owner's approval rules (Settings → Approvals), for companies kept in
   * the cloud. Missing (every company until the owner turns them on):
   * nothing waits for approval, as before. Only the owner changes them.
   */
  approvalRules?: ApprovalRules;
  /**
   * The AI assistant (Settings → AI assistant), for companies kept in the
   * cloud: an Ask AI button on every page, for everyone in the company who
   * is signed in. Only the owner or an admin changes it. Missing (every
   * company until one of them turns it on), or `on` missing or false: no
   * assistant, as before.
   */
  ai?: AiSettings;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/**
 * The company's AI assistant. In this first version it is sent only what
 * people type in the chat and where they are in the app, never records.
 */
export interface AiSettings {
  on?: boolean;
}

/**
 * What needs an approver (the owner, or a member the owner allowed to
 * approve). The cloud enforces it too (records_guard in
 * 20261116000000_super_admin_approvals.sql). Kept once set: switched off,
 * it covers no documents, and the requests made meanwhile stay decided.
 */
export interface ApprovalRules {
  /**
   * Types of document that, once issued, change, are voided or come back
   * from void only through an approver; anyone else sends the change for
   * approval. Missing or empty: none.
   */
  documentTypes?: DocumentType[];
  /** Issued documents of those types are voided, never deleted, and keep their numbers. */
  voidInsteadOfDelete?: boolean;
  /** Requests still waiting after this many days are cancelled. Missing: they wait. */
  expireDays?: number;
  /**
   * Cheques an approver confirms (#9): recorded by anyone else, a cheque of
   * these kinds is a request, not a payment, until an approver confirms it.
   * Missing: none, as before.
   */
  cheques?: ChequeApprovalRules;
  /**
   * Pay runs the Super Admin approves (#10): with it on, a pay run is
   * approved (posted, اعتماد) only once a request for it, as it stands, was
   * approved (موافقة) by the owner or a member the owner allowed to approve,
   * never by the member who sent it; the owner may post at once. Missing or
   * false: pay runs are approved as before.
   */
  payroll?: boolean;
}

/**
 * The kinds of cheque an approver confirms. The cloud enforces them too
 * (records_guard in 20261116000000_super_admin_approvals.sql). Missing or
 * false: that kind is recorded by anyone, as before.
 */
export interface ChequeApprovalRules {
  /** Cheques the company writes (payments made by cheque). */
  issued?: boolean;
  /** Security cheques the company hands over (given to someone). */
  securityOut?: boolean;
  /** Cheques the company receives. Waiting ones leave their invoices unpaid. */
  received?: boolean;
}

/** One of the company's purposes of documents (الغرض), chosen on a document in the register. */
export interface DocumentPurpose {
  id: ID;
  name: string;
  nameAr: string;
  /** No longer offered for new documents; those that have it keep it. */
  archived?: boolean;
}

/**
 * The Books dashboard. `overview` puts receivables next to payables, cash
 * flow, income and expense, top expenses, bank and card accounts and a
 * watchlist between the key figures and today's cards; missing (or
 * `classic`) is the dashboard as before. The period, the watchlist and the
 * hidden cards are each person's own and stay on the device.
 */
export interface DashboardSettings {
  layout?: 'classic' | 'overview';
}

/**
 * A unit of the company's own, besides the built-in ones (lib/units.ts). It
 * is kept when archived, so lines that have it still print its Arabic name.
 */
export interface CustomUnit {
  id: ID;
  name: string;
  nameAr: string;
  archived?: boolean;
}

/**
 * How items are set up. Only owners, admins and accountants change it (it is
 * part of the company record). Missing settings keep units and codes typed by
 * hand.
 */
export interface ItemSettings {
  /** Units are picked from a list (built-in and the company's own) with Arabic names. */
  units?: boolean;
  /** A new item saved without an SKU gets the next item code (numbering.product). */
  autoSku?: boolean;
  /** The company's own units. */
  customUnits?: CustomUnit[];
  /**
   * Items can have pictures (Product.imageIds), shown in Products and the
   * line picker, and printed on documents whose design shows item pictures.
   */
  images?: boolean;
}

/** A signature line at the foot of a voucher, labelled in both languages. */
export interface VoucherSignatureLine {
  /** Printed under the line; empty prints no English. */
  en: string;
  /** Printed under the English; empty prints no Arabic. */
  ar: string;
}

/**
 * Receipt and payment vouchers (سند قبض / سند صرف). They keep the payment
 * and expense numbers. Missing settings print vouchers as before: the three
 * standard signature lines, no stamp or signature.
 */
export interface VoucherSettings {
  /**
   * Print the company stamp and signature (in blue ink when the signature
   * is), and the company address. Never on a void voucher. Any member can
   * print a voucher, so this is off until the owner turns it on.
   */
  images?: boolean;
  /**
   * Signature lines for money received (`in`) and paid (`out`). The stamp
   * and signature print over the last line but one; the last is the other
   * party's. Missing uses the standard lines.
   */
  lines?: { in: VoucherSignatureLine[]; out: VoucherSignatureLine[] };
  /** Paper of the PDF: half a page (A5, landscape); missing is the documents' paper size. */
  paper?: 'A5';
}

/** A link in the sidebar to another tool; it opens in a new tab. */
export interface CompanyLink {
  id: ID;
  /** Name in the sidebar. */
  label: string;
  /** Name when the app is in Arabic; empty to use the name. */
  labelAr?: string;
  /** Web address: http or https only. */
  url: string;
  /** Under Integrations in the sidebar; missing for the list of links. */
  section?: 'integrations';
  /** The integration it was added as (Settings → Links), for its hint. */
  preset?: LinkPresetId;
  /**
   * The apps whose sidebar shows it (AppId values, kept as text so the apps
   * of a newer build survive); missing for every app.
   */
  apps?: string[];
}

/** The integrations Settings → Links adds with their names filled in. */
export type LinkPresetId = 'deema' | 'taly' | 'tahseel';

export interface ClientContact {
  id: ID;
  name: string;
  email: string;
  phone: string;
  /** Receives documents by email. */
  primary: boolean;
}

export interface Client {
  id: ID;
  companyId: ID;
  number: string;
  name: string;
  /** Name in Arabic, printed on Arabic and bilingual documents. */
  nameAr?: string;
  /** Civil ID of an individual customer or of a cheque drawer. */
  civilId?: string;
  contacts: ClientContact[];
  email: string;
  phone: string;
  website: string;
  taxId: string;
  address: Address;
  shippingAddress: Address | null;
  /** Overrides the company currency for this client's documents. */
  currency: string | null;
  /** Overrides the company payment terms (days). */
  paymentTermsDays: number | null;
  /** Overrides the company document language. */
  language: DocumentLanguage | null;
  /** Taxes are not applied to this client's documents. */
  taxExempt: boolean;
  /** Buys from you (shown under Clients). Missing means true for older records. */
  isCustomer?: boolean;
  /** Sells to you (shown under Vendors). */
  isVendor?: boolean;
  /** Internal notes, never printed. */
  notes: string;
  /**
   * Customers: the most they may owe at once, in the company currency (open
   * balance plus cheques not yet cleared). Missing or null means no limit.
   */
  creditLimit?: number | null;
  /** Customers: no new invoices or sales orders without an override. */
  creditHold?: boolean;
  /**
   * Share of each invoice (or bill) held back as a retention, e.g. 5 for the
   * 5% tax retention. Missing, null or 0 means none.
   */
  retentionPercent?: number | null;
  /** What the retention is waiting for; missing means 'tax'. */
  retentionKind?: RetentionKind;
  /**
   * Tax clearance certificates: the vendor's, or the company's own as given to
   * this customer. A valid one on the document date means nothing is retained.
   */
  clearanceCertificates?: ClearanceCertificate[];
  archived: boolean;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/**
 * Why money is held back from an invoice or bill: the 5% tax retention that
 * payers keep until the Ministry of Finance clearance certificate is shown,
 * or a contract retention kept until handover.
 */
export type RetentionKind = 'tax' | 'contract';

/** A Ministry of Finance tax clearance certificate (شهادة براءة ذمة ضريبية). */
export interface ClearanceCertificate {
  id: ID;
  number: string;
  issueDate: ISODate;
  /** Last day it is valid; null when it doesn't expire. */
  expiryDate: ISODate | null;
  notes?: string;
}

/**
 * Part of a retention paid back (released): it moves from retentions
 * receivable (or payable) back to the invoice (or bill) balance, so it can be
 * paid like any other amount. Undoing it posts a reversing entry.
 */
export interface RetentionRelease {
  id: ID;
  date: ISODate;
  /** In the document currency. */
  amount: number;
  /** What allowed the release: a clearance certificate or the handover. */
  basis: 'certificate' | 'handover';
  /** Certificate number, or a note about the handover. */
  reference: string;
  /** Entry moving the amount back to the receivable (or payable). */
  journalId: ID;
  /** Set when the release was undone. */
  reversedOn?: ISODate | null;
  reversalJournalId?: ID | null;
}

export interface TaxRate {
  id: ID;
  companyId: ID;
  name: string;
  rate: number;
  /** How it is reported on VAT returns; guessed from the rate when missing. */
  kind?: TaxKind;
  archived: boolean;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/**
 * What an item is: a service, goods bought and sold without tracking them in
 * stock, or a stock item with quantities on hand, a weighted average cost and
 * cost of sales.
 */
export type ProductKind = 'service' | 'non_stock' | 'stock';

export interface Product {
  id: ID;
  companyId: ID;
  sku: string;
  name: string;
  /** Name in Arabic, copied to document lines. */
  nameAr?: string;
  description: string;
  descriptionAr?: string;
  unitPrice: number;
  /** The unit as printed on documents. */
  unit: string;
  /**
   * The unit picked from the list (lib/units.ts), when units come from one:
   * Arabic documents print its Arabic name. Missing for units typed by hand.
   */
  unitId?: ID;
  taxRateIds: ID[];
  /** Income account for sales of this item; null uses the company's sales account. */
  incomeAccountId?: ID | null;
  /** Missing means a service (items saved before inventory existed). */
  kind?: ProductKind;
  /** Purchase cost of one unit (company currency): the rate on new bills and the opening stock. */
  costPrice?: number;
  /** Stock items: on hand at or below this quantity shows as low stock; null for no alert. */
  reorderLevel?: number | null;
  /** Vendor the item is usually bought from. */
  preferredVendorId?: ID | null;
  barcode?: string;
  /** Harmonized System code used by customs. */
  hsCode?: string;
  /**
   * Pictures of the item, the main one first: attachments owned by the item
   * (db/product-images.ts), at most five. Missing for items without any.
   */
  imageIds?: ID[];
  archived: boolean;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

export interface LineItem {
  id: ID;
  kind: 'item' | 'heading';
  productId: ID | null;
  name: string;
  /** Arabic name of the item, printed on Arabic and bilingual documents. */
  nameAr?: string;
  description: string;
  quantity: number;
  unit: string;
  /** The item's unit from the list (Product.unitId): Arabic documents print its Arabic name. */
  unitId?: ID;
  unitPrice: number;
  discount: number;
  discountType: DiscountType;
  /** Snapshot of the taxes at the time they were added. */
  taxes: TaxLine[];
  /** Ledger account override; null uses the product's or the company's default. */
  accountId?: ID | null;
  /** Condition of the goods sold (printed when set, as Kuwaiti invoices require). */
  condition?: ItemCondition | null;
  /** Serial or IMEI number of the item sold. */
  serialNumber?: string;
  /**
   * Line of the sales order, purchase order or invoice this line was copied
   * from; drives what is left to invoice, bill or deliver.
   */
  sourceLineId?: ID;
  /** Stock items: warehouse the goods leave from or arrive at; null uses the default one. */
  warehouseId?: ID | null;
  /** The item's SKU when the line was picked from it (printed in the SKU column). */
  sku?: string;
}

export type ItemCondition = 'new' | 'used';

export interface Charge {
  id: ID;
  label: string;
  amount: number;
  taxes: TaxLine[];
}

export interface DocumentTotals {
  subtotal: number;
  discount: number;
  taxTotal: number;
  total: number;
  paid: number;
  /** Amount due now: the total less the retention still held, payments and credits. */
  balance: number;
  /** Invoices and bills: amount held back as a retention (missing means none). */
  retention?: number;
}

export interface InvoiceDocument {
  id: ID;
  companyId: ID;
  type: DocumentType;
  number: string;
  status: DocumentStatus;
  clientId: ID;
  issueDate: ISODate;
  /** Due date for invoices, "valid until" for quotes. */
  dueDate: ISODate | null;
  poNumber: string;
  /** Bills: the supplier's own invoice number. */
  vendorReference?: string;
  currency: string;
  /** Company-currency value of 1 unit of `currency` (1 when they are the same). */
  exchangeRate?: number;
  items: LineItem[];
  discount: number;
  discountType: DiscountType;
  /** Document-level taxes applied to all items. */
  taxes: TaxLine[];
  charges: Charge[];
  pricesIncludeTax: boolean;
  /** Deposit / partial payment requested up front (0 = none). */
  deposit: number;
  depositDueDate: ISODate | null;
  notes: string;
  terms: string;
  footer: string;
  /** Internal notes, never printed. */
  privateNotes: string;
  /** Template override; null uses the company default. */
  templateId: string | null;
  /** Brand colour of this document; missing uses its type's or the company's. */
  accentColor?: string;
  /** Quotes: a few lines printed above the items, e.g. "Further to your request…". */
  intro?: string;
  /** Cached result of the calculation; recomputed on every save. */
  totals: DocumentTotals;
  sentAt: Timestamp | null;
  paidAt: Timestamp | null;
  /**
   * Document this one was created from: the quote or proforma of an invoice,
   * the order of an invoice, bill or delivery note, the invoice a credit note
   * or delivery note refers to. An order finds its invoices, bills and
   * delivery notes through this field (it is indexed).
   */
  sourceId: ID | null;
  /** The one document a quote or proforma was converted into. */
  convertedToId: ID | null;
  /** Recurring profile that generated this invoice. */
  recurringId: ID | null;
  /** Online payment link for this document (overrides the company's link). */
  paymentLink?: PaymentLink | null;
  /** When the goods or services are delivered (printed when set). */
  deliveryDate?: ISODate | null;
  /** Where the goods are delivered, e.g. a site or warehouse. */
  deliveryPlace?: string;
  /** Sales orders: how much has been delivered (kept up to date from the delivery notes). */
  deliveryStatus?: DeliveryStatus;
  /** Delivery notes: who signed for the goods. */
  receiverName?: string;
  /** Delivery notes: Civil ID number of the person who signed (optional). */
  receiverCivilId?: string;
  /**
   * Invoices and bills: share of the total held back as a retention (e.g. 5).
   * It is not due until released; missing or 0 means none.
   */
  retentionPercent?: number;
  retentionKind?: RetentionKind;
  /** Parts of the retention released so far, oldest first. */
  retentionReleases?: RetentionRelease[];
  /**
   * What an issued invoice, credit note, bill or vendor credit posts with,
   * fixed when it is issued (or saved as issued). Later changes to the
   * contact's tax exemption or a product's income account don't change it.
   * Documents issued before it existed have none and follow the settings.
   */
  posting?: PostingSnapshot;
  /** When it was voided, by whom (the account, in the cloud) and why. Missing on earlier voids. */
  voidedAt?: Timestamp | null;
  voidedBy?: string | null;
  voidReason?: string;
  /** The void document this one was issued to replace, and its number (printed on it). */
  replacesId?: ID | null;
  replacesNumber?: string;
  /** The document issued to replace this void one. */
  replacedById?: ID | null;
  /**
   * Quotes made from a manpower costing of Maham People (#3): its id only.
   * Nothing of the costing (its salaries, costs or margin) is copied to the
   * quote; the costing keeps the quote's id too (StaffingCosting.quoteId).
   */
  costingId?: ID | null;
  archived: boolean;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/** See `InvoiceDocument.posting`. */
export interface PostingSnapshot {
  /** The contact's tax exemption when the document was issued. */
  taxExempt: boolean;
  /** Sales documents: the income account of each line's product then, by line id. */
  accounts: Record<ID, ID>;
}

/** Payment providers that issue payment links in Kuwait. */
export type PaymentLinkProvider =
  'myfatoorah' | 'tap' | 'upayments' | 'hesabe' | 'ottu' | 'bank' | 'other';

export interface PaymentLink {
  provider: PaymentLinkProvider;
  url: string;
  /** Links from some providers stop working after a while. */
  expiresAt: ISODate | null;
}

/**
 * How money was paid. KNET (local debit cards), WAMD (instant transfer to a
 * mobile number), payment links, buy-now-pay-later and cash on delivery are
 * the everyday methods in Kuwait. PayPal, Stripe and mobile money are kept
 * for older records only.
 */
export type PaymentMethod =
  | 'bank_transfer'
  | 'knet'
  | 'wamd'
  | 'card'
  | 'cash'
  | 'cheque'
  | 'link'
  | 'bnpl'
  | 'cod'
  | 'paypal'
  | 'stripe'
  | 'mobile_money'
  | 'credit_note'
  | 'other';

/** Who collected a link or buy-now-pay-later payment. */
export type PaymentProvider = PaymentLinkProvider | 'taly' | 'deema' | 'tabby';

/**
 * Where a cheque is: in hand (or issued and not yet presented), deposited at
 * the bank, cleared, returned unpaid, or cancelled before it was presented.
 */
export type ChequeStatus = 'held' | 'deposited' | 'cleared' | 'returned' | 'cancelled';

/** A cheque received from a customer or issued to a vendor. */
export interface ChequeDetails {
  number: string;
  /** Bank code from KUWAIT_BANKS (e.g. "NBOK") or the bank's name. */
  bank: string;
  /** Date written on the cheque; a post-dated cheque has a later date than the payment. */
  date: ISODate;
  /** Who signed the cheque (received) or who it is payable to (issued). */
  drawer: string;
  drawerCivilId?: string;
  status: ChequeStatus;
  depositedOn?: ISODate | null;
  clearedOn?: ISODate | null;
  /** Bank account the cheque cleared into (received) or was paid from (issued). */
  bankAccountId?: ID | null;
  returnedOn?: ISODate | null;
  returnReason?: string;
  /** Journal moving the cheque from the post-dated cheques account to the bank. */
  clearingJournalId?: ID | null;
  /** Journal reversing the clearing when a cleared cheque came back. */
  reversalJournalId?: ID | null;
  /** Expense recording the bank's charge for a returned cheque. */
  returnChargeExpenseId?: ID | null;
  /** Payment recorded with the cheque that replaced this one. */
  replacedById?: ID | null;
  /** Payment whose cheque this one replaces. */
  replacesId?: ID | null;
  /**
   * When the cheque (issued) was printed onto its leaf and the print was
   * confirmed. A printed cheque is not printed again: its leaf is marked
   * spoiled first. Set by the cheque print page, never by the payment form.
   */
  printedAt?: Timestamp | null;
  /** Leaves printed for this cheque, spoiled ones included. */
  printCount?: number;
  /** The layout it was printed with (a built-in one is "preset-<bank>"). */
  printedLayoutId?: ID | null;
  /** What was printed on the leaf, as printed. */
  printedText?: ChequePrintedText | null;
  /** Printed crossed: "A/C payee only" (يصرف للمستفيد الأول). */
  crossed?: boolean;
  /** Leaves spoiled for this cheque, oldest first: each was destroyed and the cheque moved to the next. */
  spoiledLeaves?: SpoiledChequeLeaf[];
}

/** The text printed on a cheque leaf. */
export interface ChequePrintedText {
  date: string;
  payee: string;
  /** The amount in words, line by line. */
  words: string[];
  figures: string;
  /** The crossing, when the cheque was crossed. */
  crossing?: string;
  /** The version of the layout it was printed with. */
  layoutVersion: number;
  /** The number of the leaf it was printed on (missing on prints recorded before it was kept). */
  number?: string;
  /** The bank of that leaf, as on the cheque. */
  bank?: string;
  /** The vendor it was printed for: the payee is the vendor's name when Pay to is left empty. */
  vendorId?: ID;
  /** Pay to was typed when it was printed (missing when the payee was the vendor's name). */
  typedPayee?: boolean;
}

/** A cheque leaf that was spoiled: printed wrongly, printed before a change, or printed again. */
export interface SpoiledChequeLeaf {
  /** The number of the leaf. */
  number: string;
  at: Timestamp;
  /** Why, as written at the time. */
  reason: string;
  /** What was printed on it, when it was printed. */
  printedText?: ChequePrintedText | null;
}

export interface PaymentAllocation {
  documentId: ID;
  amount: number;
}

export interface Payment {
  id: ID;
  companyId: ID;
  /** Received from a client (default) or paid to a vendor. */
  direction?: 'in' | 'out';
  /** The client or vendor. */
  clientId: ID;
  number: string;
  date: ISODate;
  amount: number;
  currency: string;
  /** Company-currency value of 1 unit of `currency` (1 when they are the same). */
  exchangeRate?: number;
  /** Bank, cash or card account the money went into (or came out of); null picks one from the method. */
  accountId?: ID | null;
  method: PaymentMethod;
  /** Transaction / cheque reference. */
  reference: string;
  notes: string;
  allocations: PaymentAllocation[];
  /** Index helper: ids of the documents in `allocations`. */
  documentIds: ID[];
  /** Credit note consumed by this payment (method "credit_note"). */
  creditId: ID | null;
  /** Payment link or buy-now-pay-later provider. */
  provider?: PaymentProvider | null;
  /**
   * Fee kept by KNET, the card acquirer, the link or the buy-now-pay-later
   * provider, in the payment currency. Posted as an expense against the
   * account the payment went into.
   */
  fee?: number;
  /** Expense account for the fee (6180 KNET and card fees). */
  feeAccountId?: ID | null;
  cheque?: ChequeDetails | null;
  /**
   * A void payment stays on record (a returned or cancelled cheque) but no
   * longer counts towards the balances of its documents. A returned or
   * cancelled cheque keeps its entries and is reversed on `voidedOn`; any
   * other void payment leaves the books.
   */
  voided?: boolean;
  voidReason?: string;
  voidedOn?: ISODate | null;
  /**
   * The posting rules the payment was saved under (`PAYMENT_POSTING_RULES`
   * in the ledger). Payments saved before rules were numbered have none and
   * keep posting as they did, so closed periods never change by themselves;
   * saving one again moves it to the current rules.
   */
  postingRules?: number;
  /** The approval request it was confirmed by (a cheque the company's rules keep for approvers). */
  approvalId?: ID | null;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/** Status of a cheque held as a guarantee (never on the ledger). */
export type SecurityChequeStatus = 'held' | 'returned' | 'cashed';

/**
 * A security (guarantee) cheque, e.g. a tenant's rent deposit cheque. It is
 * kept in a memo register only; cashing it records a real payment.
 */
export interface SecurityCheque {
  id: ID;
  companyId: ID;
  /** Received from someone (default) or given to someone. */
  direction: 'in' | 'out';
  /** The client or vendor, when known. */
  clientId: ID | null;
  number: string;
  /** Bank code from KUWAIT_BANKS or the bank's name. */
  bank: string;
  /** Security cheques are often left undated. */
  date: ISODate | null;
  amount: number;
  currency: string;
  /** Who signed it (received) or who holds it (given). */
  drawer: string;
  drawerCivilId?: string;
  /** What it guarantees, e.g. "Rent deposit, flat 12". */
  purpose: string;
  notes: string;
  status: SecurityChequeStatus;
  returnedOn: ISODate | null;
  cashedOn: ISODate | null;
  /** Payment recorded when the cheque was cashed. */
  paymentId: ID | null;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/** A field's box on a cheque leaf, in millimetres from the leaf's top left corner. */
export interface ChequeBox {
  x: number;
  y: number;
  width: number;
  height: number;
}

/** How the date is written: 12/10/2026, or its digits spread over the leaf's date boxes. */
export type ChequeDateStyle = 'slashes' | 'boxes';

/** Where a bank's cheque leaf takes each field, for printing a cheque issued onto it. */
export interface ChequeLayout {
  id: ID;
  companyId: ID;
  /** Bank code from KUWAIT_BANKS (BRGN, KFHO…). */
  bank: string;
  name: string;
  nameAr?: string;
  /** Goes up with every change of the measurements; a print records the version it used. */
  version: number;
  /** The leaf, in millimetres. */
  size: { width: number; height: number };
  /** Moves every field at once, in millimetres (each printer also has its own, on its device). */
  offset: { x: number; y: number };
  fields: {
    date: ChequeBox;
    payee: ChequeBox;
    /** The amount in words, over two lines. */
    wordsLine1: ChequeBox;
    wordsLine2: ChequeBox;
    figures: ChequeBox;
    /** "A/C payee only", when the cheque is crossed. */
    crossing?: ChequeBox;
  };
  dateStyle: ChequeDateStyle;
  wordsLanguage: 'ar' | 'en';
  /** Printed before and around the figures so nothing can be added, e.g. "KD" and "**". */
  figures: { prefix: string; guard: string };
  /** Checked against a real leaf on the office printer. */
  calibrated: boolean;
  archived: boolean;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

export type Frequency =
  'weekly' | 'biweekly' | 'monthly' | 'bimonthly' | 'quarterly' | 'semiannually' | 'yearly';

export type RecurringStatus = 'active' | 'paused' | 'completed';

export type RecurringTemplate = Pick<
  InvoiceDocument,
  | 'currency'
  | 'items'
  | 'discount'
  | 'discountType'
  | 'taxes'
  | 'charges'
  | 'pricesIncludeTax'
  | 'poNumber'
  | 'notes'
  | 'terms'
  | 'footer'
  | 'privateNotes'
  | 'templateId'
> &
  /** Company-currency value of 1 unit of `currency`, given to each invoice. */
  Partial<Pick<InvoiceDocument, 'exchangeRate'>>;

export interface RecurringProfile {
  id: ID;
  companyId: ID;
  clientId: ID;
  /** Internal name, e.g. "Monthly mailing retainer". */
  name: string;
  frequency: Frequency;
  startDate: ISODate;
  /** Next date an invoice will be issued; null when completed. */
  nextIssueDate: ISODate | null;
  /** Number of invoices left to issue; null means no limit. */
  remainingCycles: number | null;
  /** Days between issue date and due date of generated invoices. */
  dueDays: number;
  /** Generated invoices are marked as sent instead of draft. */
  markSent: boolean;
  status: RecurringStatus;
  template: RecurringTemplate;
  issuedCount: number;
  lastIssuedAt: Timestamp | null;
  archived: boolean;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

export type ActivityEntity =
  | DocumentType
  | 'expense'
  | 'payment'
  | 'client'
  | 'product'
  | 'recurring'
  | 'company'
  | 'account'
  | 'journal'
  | 'vat_return'
  | 'bank'
  | 'employee'
  | 'compliance'
  | 'cheque'
  | 'asset'
  | 'year_end'
  | 'payroll'
  | 'stock'
  | 'approval'
  | 'member'
  /** A manpower costing (#3): private, like payroll. */
  | 'costing';

export interface Activity {
  id: ID;
  companyId: ID;
  at: Timestamp;
  entity: ActivityEntity;
  entityId: ID;
  /** Document or client the event relates to, for timelines. */
  clientId: ID | null;
  documentId: ID | null;
  /**
   * The employee an event about their documents or renewals concerns: such
   * an event stays private (people data) even after the document is gone.
   */
  employeeId?: ID | null;
  /**
   * The event concerns a register document marked confidential (or its
   * renewal), or a manpower costing: it stays private even after the
   * document or costing is gone.
   */
  confidential?: boolean;
  action: string;
  /** The message in English as it was logged. */
  message: string;
  /** Translation key and values, to show the message in the reader's language. */
  messageKey?: string;
  messageVars?: Record<string, string | number>;
  /** Amounts among the values, written in the reader's language when shown. */
  messageMoney?: Record<string, { amount: number; currency: string }>;
  /** Arabic names among the values (an account's, a client's), shown to Arabic readers. */
  messageVarsAr?: Record<string, string>;
  /**
   * The account that made the change, in a company kept in the cloud (D8);
   * missing for one kept on this device and for what older versions logged.
   */
  by?: string;
  /** Their name as the team knows it, to show without asking the cloud. */
  byName?: string;
}

/** Money spent without a bill: fuel, a train ticket, a software subscription. */
export interface Expense {
  id: ID;
  companyId: ID;
  number: string;
  date: ISODate;
  /** Who was paid, when known. */
  vendorId: ID | null;
  /** Who was paid when it isn't a vendor (a shop, a driver); printed on the voucher. */
  payee?: string;
  /** Expense category (an expense or asset account). */
  accountId: ID;
  description: string;
  /** Amount paid, including tax. */
  amount: number;
  /** Tax included in the amount (one rate in practice). */
  taxes: TaxLine[];
  currency: string;
  exchangeRate?: number;
  /** Bank, cash, card or owner account the money came from; null uses the bank. */
  paidFromAccountId: ID | null;
  reference: string;
  notes: string;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/** A file kept with a record, e.g. a receipt photo. Stored as a data URL so backups stay JSON. */
export interface Attachment {
  id: ID;
  companyId: ID;
  /** Record the file belongs to (bill, expense…); the only link to it. */
  ownerId: ID;
  name: string;
  type: string;
  size: number;
  /**
   * The content. Empty for a file kept in the cloud that this device has not
   * downloaded yet (see storagePath).
   */
  dataUrl: string;
  /** Where the content is in cloud storage ({companyId}/{id}), once uploaded. */
  storagePath?: string;
  /** SHA-256 of the content in cloud storage. */
  contentHash?: string;
  /**
   * This device only: set while the content is in the cloud but not here,
   * so such files are found without reading every file.
   */
  contentMissing?: 1;
  /**
   * What the file is a copy of: a register entry's key ("doc:<id>",
   * "emp:<employeeId>:<type>") or an issued letter ("letter:<id>").
   */
  docKey?: string;
  /** Last day the paper in the file is valid (the expiry printed on it). */
  validUntil?: ISODate | null;
  createdAt: Timestamp;
}

export interface KeyValue {
  key: string;
  value: unknown;
}

/* -------------------------------------------------------------------------- */
/* People and compliance                                                      */
/* -------------------------------------------------------------------------- */

/**
 * Kuwaitis and GCC nationals are insured with PIFSS and need no residency;
 * expatriates need an Article 18 residency and a PAM work permit; domestic
 * workers (Article 20) are outside Labour Law 6/2010.
 */
export type EmployeeCategory = 'kuwaiti' | 'gcc' | 'expat' | 'domestic';

export type EmployeeStatus = 'active' | 'on_leave' | 'left';

export type ContractType = 'unlimited' | 'fixed';

/** How the wage is paid; decides the end-of-service rates (Labour Law art. 51). */
export type PayBasis = 'monthly' | 'daily' | 'hourly' | 'piece';

export type LeavingReason =
  'resignation' | 'termination' | 'contract_end' | 'retirement' | 'dismissal' | 'death' | 'other';

export type Gender = 'male' | 'female';

export interface EmployeeAllowance {
  id: ID;
  name: string;
  nameAr?: string;
  /** Monthly amount in the company currency. */
  amount: number;
  /** Part of the wage the end-of-service indemnity is calculated on. */
  countsForEos: boolean;
}

/**
 * A person on the payroll and their personnel file (Labour Law art. 80). The
 * identity documents (Civil ID, passport, residency, work permit) and the
 * contract end date live here only; the documents register shows them
 * without copying them (see lib/compliance.ts, employeeDocuments).
 */
export interface Employee {
  id: ID;
  companyId: ID;
  number: string;
  name: string;
  nameAr?: string;
  /** ISO 3166-1 alpha-2 code; empty when not known. */
  nationality: string;
  category: EmployeeCategory;
  /** Empty or null when not known (older records don't have it). */
  birthDate?: ISODate | null;
  gender?: Gender | null;
  civilId: string;
  civilIdExpiry: ISODate | null;
  passportNumber: string;
  passportExpiry: ISODate | null;
  /** Residency article ("18" private sector, "20" domestic worker…); not for Kuwaitis. */
  residencyArticle: string;
  residencyNumber: string;
  residencyExpiry: ISODate | null;
  workPermitNumber: string;
  /** Job title registered with the Public Authority for Manpower. */
  pamJobTitle: string;
  /** Salary on the work permit (company currency). */
  permitSalary: number;
  workPermitExpiry: ISODate | null;
  /**
   * Stateless (Bedoon, غير محدد الجنسية), on top of the category 'expat' so
   * that older versions still show a label and pay the same (no PIFSS): no
   * residency is needed, a work permit is optional, and the Central Agency
   * review card is tracked instead. Missing or false: not stateless.
   */
  stateless?: boolean;
  /** Central Agency review card (بطاقة المراجعة) of stateless staff. */
  centralCardNumber?: string;
  centralCardExpiry?: ISODate | null;
  jobTitle: string;
  jobTitleAr?: string;
  /**
   * Drives for work, so needs a valid driving licence: true or false as set
   * on the employee's page. Missing or null: decided by the job title (see
   * requiresDrivingLicence).
   */
  drivingLicenceRequired?: boolean | null;
  department: string;
  hireDate: ISODate | null;
  probationEnd: ISODate | null;
  contractType: ContractType;
  /** Fixed-term contracts only. */
  contractEnd: ISODate | null;
  payBasis: PayBasis;
  /** Monthly basic salary (company currency, 3 decimals in KWD). */
  basicSalary: number;
  allowances: EmployeeAllowance[];
  /** First four letters of the bank's SWIFT code (see KUWAIT_BANKS) or a bank name. */
  bank: string;
  iban: string;
  /**
   * A bank account or salary card number for salaries paid without an IBAN
   * (salary cards are common for workers); used in the salary file when the
   * IBAN is empty.
   */
  accountNumber?: string;
  /** PIFSS (social security) number of Kuwaiti and GCC staff. */
  pifssNumber: string;
  phone: string;
  email: string;
  status: EmployeeStatus;
  leavingDate: ISODate | null;
  leavingReason: LeavingReason | null;
  notes: string;
  /** The employee's photo: one of their attachments, a small square JPEG. */
  photoId?: ID | null;
  /**
   * Annual leave brought forward when the employee's leave history starts in
   * the app (employees imported from another system); null or missing when
   * leave counts from the hire date.
   */
  leaveOpening?: LeaveOpening | null;
  /**
   * Days of annual leave a year in the employee's contract, in place of the
   * company's (at least 30). Missing or null: the company's leave policy.
   */
  annualLeaveDays?: number | null;
  /**
   * The date annualLeaveDays apply from: before it the company's days count.
   * Missing or null: from the hire date (or opening balance).
   */
  annualLeaveDaysFrom?: ISODate | null;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/** Annual leave brought forward on a date: leave accrues only from that date. */
export interface LeaveOpening {
  date: ISODate;
  /** Days of annual leave brought forward. */
  days: number;
  /** False until someone has checked the figures (an import brings 0 days, not confirmed). */
  confirmed: boolean;
}

/** Kinds of documents with an expiry date that the register tracks. */
export type ComplianceDocumentType =
  // Company
  | 'commercial_licence'
  | 'commercial_registration'
  | 'pam_company_file'
  | 'authorised_signatories'
  | 'pam_salary_certificate'
  | 'mof_tax_card'
  | 'tax_clearance'
  | 'kcci_membership'
  | 'municipality_licence'
  | 'fire_licence'
  | 'lease_contract'
  // Employees (the first six are read from the employee record)
  | 'civil_id'
  | 'passport'
  | 'residency'
  | 'work_permit'
  | 'employment_contract'
  | 'central_agency_card'
  | 'health_insurance'
  | 'driving_licence'
  // Vehicles
  | 'vehicle_registration'
  | 'vehicle_insurance'
  // Contracts and customers' papers (with the register's extras)
  | 'company_contract'
  | 'client_contract'
  | 'customer_cost'
  | 'other';

export type DocumentOwnerType = 'company' | 'employee' | 'vehicle' | 'other';

/** A document kept in the register (company licences, vehicles, extra employee papers). */
export interface ComplianceDocument {
  id: ID;
  companyId: ID;
  type: ComplianceDocumentType;
  /** Free title; the type's name is shown when empty. */
  title: string;
  number: string;
  issuer: string;
  issueDate: ISODate | null;
  expiryDate: ISODate | null;
  /** Expected cost of the next renewal (company currency). */
  renewalCost: number;
  /** Days before expiry to remind, largest first; null uses the company setting. */
  reminderDays: number[] | null;
  ownerType: DocumentOwnerType;
  employeeId: ID | null;
  /** Vehicle (plate or model) or other owner's name. */
  ownerName: string;
  notes: string;
  /** No longer tracked (vehicle sold, licence cancelled); kept with its history. */
  archived: boolean;
  /** What the document is for, from the company's list of purposes. */
  purposeId?: ID | null;
  /** The customer a customer's paper belongs to (owner "other"; ownerName keeps their name). */
  clientId?: ID | null;
  /** The vehicle it belongs to (ownerName keeps the plate). */
  vehicleId?: ID | null;
  /**
   * Seen only by owners, admins and accountants, with its files, renewals
   * and activity (a cost sheet with guards' salaries).
   */
  confidential?: boolean;
  /** The class of a driving licence, as written on it (فئة الرخصة); free text. */
  licenceClass?: string;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/** One renewal of a document: the old and new expiry and the fee paid, if any. */
export interface DocumentRenewal {
  id: ID;
  companyId: ID;
  /** "doc:<id>" for register records, "emp:<employeeId>:<type>" for employee documents. */
  documentKey: string;
  documentId: ID | null;
  employeeId: ID | null;
  type: ComplianceDocumentType;
  renewedOn: ISODate;
  previousExpiry: ISODate | null;
  newExpiry: ISODate;
  /** Fee paid (company currency), 0 when none. */
  fee: number;
  /** Expense recording the fee. */
  expenseId: ID | null;
  note: string;
  /**
   * The document's number after the renewal. Kept here, not on the fee's
   * expense, for employees' documents (older renewals don't have it).
   */
  number?: string;
  /**
   * The file that is the renewed paper's new copy (an attachment marked with
   * the paper's key and valid until the new expiry), once there is one (#18).
   */
  newCopyId?: ID | null;
  createdAt: Timestamp;
}

/** A statutory deadline marked as done, e.g. "income_tax_return:2026-12-31". */
export interface ComplianceMark {
  id: ID;
  companyId: ID;
  key: string;
  doneOn: ISODate;
  note: string;
  createdAt: Timestamp;
}

/** A company vehicle, which its papers in the register belong to. */
export interface Vehicle {
  id: ID;
  companyId: ID;
  plate: string;
  make: string;
  model: string;
  year?: number | null;
  chassisNumber?: string;
  /** The fixed asset it is in the books as. */
  assetId?: ID | null;
  /** The employee who usually drives it (kept here, so its papers are not an employee's). */
  driverEmployeeId?: ID | null;
  notes: string;
  archived: boolean;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/** Employee and compliance settings of a company (one row per company, id = companyId). */
export interface PeopleSettings {
  id: ID;
  companyId: ID;
  /** Kuwaiti share of the workforce to aim for, in percent; null when not set. */
  kuwaitizationTarget: number | null;
  /** Working days in a month used for the daily wage (end of service). */
  eosDailyDivisor: number;
  /** Days before an expiry to remind, largest first (60/30/7). */
  reminderDays: number[];
  /** Months after the year end to file the audited statements with MOCI. */
  auditFilingMonths: number;
  /** Day of the following month PIFSS contributions are paid by. */
  pifssDueDay: number;
  /**
   * The company's employees are found from the other companies on the
   * device too (People → All companies, and search). Missing or false: only
   * from this company, as before.
   */
  groupSearch?: boolean;
  /**
   * The company's departments, with their Arabic names (Employees →
   * Departments). Employees keep the English name in `department`, so links,
   * imports and older versions keep working. Missing or empty: departments
   * are typed freely, as before.
   */
  departments?: Department[];
  /**
   * Employees who drive for work (by their job title, or as set on their
   * page) are flagged when they hold no valid driving licence. Missing or
   * false: nothing is flagged, as before.
   */
  drivingLicences?: boolean;
  /**
   * Days before an expiry to remind, by document type (#18): a type listed
   * here uses its own days instead of `reminderDays` (a document's own days
   * still come first). Missing or empty: every type uses `reminderDays`, as
   * before.
   */
  reminderDaysByType?: Partial<Record<string, number[]>>;
  /**
   * Once a paper has expired, it is reminded of again every this many days
   * until it is renewed (#18). Missing: once when it expires, then only in
   * Sunday's summary, as before.
   */
  expiredRepeatDays?: number;
  /**
   * After a renewal, the new copy (a file marked as the renewed paper, valid
   * until its new expiry) is asked for once this many days have passed (#18).
   * Missing: never asked for, as before.
   */
  newCopyGraceDays?: number;
  /** Renewals recorded from this day on are asked for their new copy (set when it is turned on). */
  newCopySince?: ISODate;
  /**
   * The expiry reminders also appear in Updates (the bell) of the owner and
   * the approvers who get the changes of the team (#18). Missing: they don't.
   */
  expiryUpdates?: boolean;
  /**
   * Employee letters (#19): People → Letters, the Letters tab of each
   * employee and the letter templates. Turned on and off by the owner or an
   * admin; in a company kept in the cloud only once its server has
   * 20261130000000_people_alerts.sql (employee_letters). Missing: off, as
   * before.
   */
  letters?: boolean;
  /**
   * Manpower costing (#3): People → Manpower costing, which prices posts
   * of guards, cleaners and other staff from the company's rate card and
   * makes a quote with sell prices only. Turned on and off by the owner, an
   * admin or an accountant; in a company kept in the cloud only once its
   * server has 20261207000000_staffing_costings.sql (staffing_costings).
   * Missing: off, as before.
   */
  costing?: CostingSettings;
  updatedAt: Timestamp;
}

/** The company's manpower costing (#3): off, 10% overhead and 15% margin until changed. */
export interface CostingSettings {
  on: boolean;
  /** Overhead added to the cost of each post, in percent of that cost. */
  overheadPercent: number;
  /** Margin of a new costing, in percent of its sell price (not a markup on cost). */
  marginPercent: number;
  /**
   * The rate card: pay of each job title that posts are priced from. Missing:
   * the averages of the current salaries, worked out on the device.
   */
  rates?: CostingRate[];
}

/** Kinds of staff a costing prices: Kuwaiti and GCC posts pay the employer's PIFSS share. */
export type CostingCategory = 'kuwaiti' | 'gcc' | 'expat';

/** A job title's pay on the rate card, per person a month (company currency). */
export interface CostingRate {
  id: ID;
  jobTitle: string;
  jobTitleAr?: string;
  category: CostingCategory;
  /** GCC posts: the ISO code of the nationality, for its scheme's rates. */
  nationality?: string;
  basic: number;
  allowances: number;
  /**
   * The part of the allowances the end-of-service indemnity is worked out on
   * (allowances that count for it, as on an employee's record). Missing: all.
   */
  eosAllowances?: number;
  /** Uniform, residency, medical cover, transport and the like, per person a month. */
  otherCosts?: number;
  /** How many current employees the averages were worked out from (none when typed in). */
  count?: number;
}

export type CostingStatus = 'draft' | 'quoted' | 'won' | 'lost';

/**
 * A post of a manpower costing: a job title, how many people, their hours
 * and days, and their pay. Amounts are per person a month in the company
 * currency (KWD to 3 decimals); the worked-out ones are kept as they were
 * last saved (see lib/hr/costing.ts).
 */
export interface CostingPost {
  id: ID;
  jobTitle: string;
  jobTitleAr?: string;
  /** Missing: expatriate (no PIFSS). */
  category?: CostingCategory;
  /** GCC posts: the ISO code of the nationality, for its scheme's rates. */
  nationality?: string;
  headcount: number;
  hoursPerDay: number;
  daysPerMonth: number;
  basic: number;
  allowances: number;
  /** The part of the allowances the indemnity is worked out on. Missing: all of them. */
  eosAllowances?: number;
  /** Worked out: overtime past 8 hours a day at 1.25 and rest days worked at 1.5. */
  overtimeMonthly?: number;
  /** Worked out: the employer's PIFSS share (Kuwaiti and GCC posts only). */
  employerPifss: number;
  /** Worked out: the end-of-service indemnity earned in a month (art. 51). */
  eosiMonthly: number;
  /** Worked out: a month's share of the annual leave's pay. */
  leaveMonthly: number;
  otherCosts: number;
  /** Worked out: what a person costs a month, before overhead. */
  monthlyCost: number;
  /** Worked out: the price to the client per person a month. */
  sellPrice: number;
}

/**
 * A manpower costing (تسعير العمالة, #3): posts priced from staff cost, with
 * overhead and a margin, that make a quote with sell prices only. Private:
 * only owners, admins and accountants see it, like payroll.
 */
export interface StaffingCosting {
  id: ID;
  companyId: ID;
  name: string;
  clientId: ID | null;
  /** The quote made from it (that quote has its id as costingId). */
  quoteId: ID | null;
  status: CostingStatus;
  posts: CostingPost[];
  overheadPercent: number;
  /** In percent of the sell price. */
  marginPercent: number;
  /** Internal notes, never on the quote. */
  notes: string;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/** A department of the company's list (D11: a list of names, never a new enum value). */
export interface Department {
  id: ID;
  /** English name: what employees keep in `department`. */
  name: string;
  nameAr: string;
  /** No longer offered for new choices; the employees in it keep it. */
  archived?: boolean;
}
/* Fixed assets                                                              */
/* -------------------------------------------------------------------------- */

/**
 * What a journal made by the app records: money moved between two of the
 * company's own accounts, cheques clearing or coming back, payroll, monthly
 * depreciation, buying, opening or disposing of a fixed asset, or closing a
 * financial year (levies and transfers to reserves).
 */
export type JournalKind =
  | 'transfer'
  | 'cheque_clearing'
  | 'cheque_return'
  | 'payroll'
  | 'depreciation'
  | 'asset_purchase'
  | 'asset_opening'
  | 'asset_disposal'
  | 'year_end'
  | 'retention_release';

export type DepreciationMethod = 'straight_line' | 'declining_balance';

/**
 * How the cost of an asset reached the books: a bill line (posted by the
 * bill), a purchase paid from a money account, an opening balance for an
 * asset bought before the company used Maham Books, or an entry made some
 * other way (nothing is posted for it).
 */
export type AssetSource = 'bill' | 'purchase' | 'opening' | 'existing';

/** Void assets were entered by mistake; their entries are reversed, never deleted. */
export type AssetStatus = 'active' | 'disposed' | 'void';

/** Sale or scrapping of an asset (company currency). */
export interface AssetDisposal {
  date: ISODate;
  /** Sale price; 0 when the asset was scrapped or written off. */
  proceeds: number;
  /** Bank, cash or receivable account the proceeds went into. */
  depositAccountId: ID | null;
  /** Depreciation from the last run up to the disposal date. */
  depreciation: number;
  /** Gain (positive) or loss (negative) on disposal. */
  gain: number;
  journalId: ID;
  notes: string;
}

/** An item of property and equipment (or an intangible asset) in the fixed asset register. */
export interface FixedAsset {
  id: ID;
  companyId: ID;
  /** e.g. "FA-0001". */
  number: string;
  name: string;
  /** Arabic name, shown in the Arabic interface and Arabic reports. */
  nameAr?: string;
  description: string;
  /** Account holding the cost: the asset category. */
  assetAccountId: ID;
  accumulatedAccountId: ID;
  expenseAccountId: ID;
  purchaseDate: ISODate;
  /** Depreciation is charged from this date (when the asset was put to use). */
  depreciationStart: ISODate;
  /** Company currency. */
  cost: number;
  salvageValue: number;
  usefulLifeMonths: number;
  method: DepreciationMethod;
  /** Declining balance: yearly rate in percent; empty means twice the straight-line rate. */
  decliningRate?: number | null;
  /** Depreciation charged before the asset was entered here. */
  openingDepreciation: number;
  /** Last day the opening depreciation covers. */
  openingDepreciationDate: ISODate | null;
  source: AssetSource;
  /** Bill (and line) the asset was bought on. */
  billId: ID | null;
  billLineId: ID | null;
  vendorId: ID | null;
  /** Purchase: the bank, cash or card account it was paid from. */
  paidFromAccountId: ID | null;
  /** Journal recording the purchase or the opening balance. */
  journalId: ID | null;
  location: string;
  custodian: string;
  serialNumber: string;
  notes: string;
  status: AssetStatus;
  disposal: AssetDisposal | null;
  /** Journal that reversed the purchase or opening balance of a void asset. */
  voidJournalId?: ID | null;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/** A monthly depreciation run: one journal for every asset up to a month end. */
export interface DepreciationRun {
  id: ID;
  companyId: ID;
  /** Month, `yyyy-MM`. */
  period: string;
  /** Last day of the month: the date of the journal. */
  date: ISODate;
  journalId: ID;
  /** Depreciation charged per asset (company currency). */
  lines: { assetId: ID; amount: number }[];
  total: number;
  /** Journal reversing the run when it was undone. */
  reversalJournalId: ID | null;
  reversedAt: Timestamp | null;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/* -------------------------------------------------------------------------- */
/* Year-end close                                                             */
/* -------------------------------------------------------------------------- */

/** Rates of the Kuwaiti levies and the statutory reserve, in percent. */
export interface LevyRates {
  /** Share of the profit moved to the statutory reserve (10%). */
  statutoryReserve: number;
  /** The transfers stop once the reserve reaches this share of the capital (50%). */
  statutoryReserveCap: number;
  /** Kuwait Foundation for the Advancement of Sciences, shareholding companies (1%). */
  kfas: number;
  /** Zakat, shareholding companies (1%, Law 46/2006). */
  zakat: number;
  /** National Labour Support Tax, listed companies (2.5%, Law 19/2000). */
  nlst: number;
  /** Income tax on the foreign-owned share of the profit (15%, Law 2/2008). */
  incomeTax: number;
}

export type YearEndLineKind =
  'statutory_reserve' | 'voluntary_reserve' | 'kfas' | 'zakat' | 'nlst' | 'income_tax';

export interface YearEndLine {
  kind: YearEndLineKind;
  /** Amount the rate was applied to (company currency). */
  base: number;
  /** Percent. */
  rate: number;
  amount: number;
  /** Levy expense or retained earnings. */
  debitAccountId: ID;
  /** Levy payable or the reserve. */
  creditAccountId: ID;
}

/** A closed financial year: levies, transfers to reserves and the lock date set. */
export interface YearEndClose {
  id: ID;
  companyId: ID;
  yearStart: ISODate;
  yearEnd: ISODate;
  /** Profit before levies and income tax (company currency). */
  profitBeforeLevies: number;
  lines: YearEndLine[];
  journalIds: ID[];
  /** Lock date set when the year was closed. */
  lockedTo: ISODate | null;
  /** A reopened year has its entries reversed. */
  status: 'closed' | 'reopened';
  reversalJournalIds: ID[];
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/* -------------------------------------------------------------------------- */
/* Inventory                                                                  */
/* -------------------------------------------------------------------------- */

/** A place stock is kept: a showroom, a store in Shuwaikh or Al-Rai. */
export interface Warehouse {
  id: ID;
  companyId: ID;
  name: string;
  nameAr?: string;
  address: string;
  /** Documents move stock in and out of the default warehouse unless a line says otherwise. */
  isDefault: boolean;
  archived: boolean;
  /**
   * Sub-warehouses: the main warehouse they belong to (stock reaches them by
   * transfer from it). Missing or null for a main warehouse.
   */
  parentId?: ID | null;
  /** The person responsible for the stock kept here, when someone is. */
  keeper?: WarehouseKeeper | null;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/**
 * Who looks after a sub-warehouse: an employee (People), and the account
 * that issues items from it. Their name is kept here, so members who can't
 * see People see it too.
 */
export interface WarehouseKeeper {
  employeeId: ID | null;
  name: string;
  nameAr?: string;
  jobTitle: string;
  jobTitleAr?: string;
  /** The Maham One account that issues items from the sub-warehouse; null when nobody does. */
  userId: string | null;
}

/** Who received issued items, kept on the issue so it reads the same for everyone. */
export interface IssueRecipient {
  employeeId: ID;
  /** Employee number, e.g. "E-0042". */
  number: string;
  name: string;
  nameAr?: string;
  jobTitle: string;
  jobTitleAr?: string;
}

export interface StockIssueLine {
  id: ID;
  productId: ID;
  /** The item's name when it was issued. */
  name: string;
  nameAr?: string;
  unit: string;
  quantity: number;
}

/**
 * Items handed from a warehouse to an employee: uniforms, shoes, badges.
 * Until an approver confirms it, an issue is an approval request (kind
 * `stock_issue`); once confirmed it is kept here, its stock leaves the
 * warehouse at the weighted average cost and the cost is booked as an
 * expense. Void issues stay on record and their stock comes back.
 */
export interface StockIssue {
  id: ID;
  companyId: ID;
  /** e.g. "ISS-0001", given when it is confirmed. */
  number: string;
  date: ISODate;
  warehouseId: ID;
  recipient: IssueRecipient;
  /** The account that issued the items, and their name as shown on the issue. */
  issuedBy: string | null;
  issuedByName: string;
  /** The approval request it was confirmed from; null when an approver issued it. */
  requestId: ID | null;
  approvedBy: string | null;
  approvedByName: string;
  approvedAt: Timestamp | null;
  lines: StockIssueLine[];
  notes: string;
  status: 'posted' | 'void';
  voidedAt?: Timestamp | null;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/** What moved the stock. */
export type StockSourceType =
  | 'bill'
  | 'vendor_credit'
  | 'invoice'
  | 'credit'
  | 'adjustment'
  | 'opening'
  | 'transfer'
  | 'landed_cost'
  | 'issue';

/**
 * One stock item coming into or leaving a warehouse. Movements are derived
 * from issued documents, stock entries and landed costs, and costed at the
 * weighted average in date order (see lib/inventory/costing.ts); those in a
 * locked period keep the values they were posted with.
 */
export interface StockMovement {
  id: ID;
  companyId: ID;
  productId: ID;
  warehouseId: ID;
  date: ISODate;
  /** Positive into stock, negative out of it; 0 for a landed cost, which adds value only. */
  quantity: number;
  /** Company-currency cost of one unit, up to 6 decimals. */
  unitCost: number;
  /** Company-currency value added to (positive) or taken out of (negative) stock. */
  value: number;
  sourceType: StockSourceType;
  /** Document, stock entry or landed cost the movement comes from. */
  sourceId: ID;
  /** Line of the source the movement comes from. */
  lineId: ID | null;
  /** Document whose posting carries the movement (for a landed cost, the bill with the charges). */
  documentId: ID | null;
  /** Number of the source, shown in reports. */
  number: string;
  /**
   * Value the source sets, in the company currency: the bill or vendor credit
   * line, the opening stock or the landed cost. Null for movements costed at
   * the weighted average.
   */
  sourceValue: number | null;
  /** Credit notes: the invoice the goods were sold on, to bring them back at that cost. */
  returnOf?: ID | null;
  /** Landed costs: quantity received on the bill line the cost was allocated to. */
  basisQuantity?: number | null;
  /** Keeps movements of the same day in the order they were recorded. */
  sequence: string;
  notes: string;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/** Stock recorded without a document: opening stock, adjustments and transfers. */
export type StockEntryKind = 'opening' | 'adjustment' | 'transfer';

export type AdjustmentReason = 'damaged' | 'expired' | 'count' | 'other';

export interface StockEntryLine {
  id: ID;
  productId: ID;
  /** Adjustments: positive adds stock, negative removes it. Opening stock and transfers: positive. */
  quantity: number;
  /** Opening stock: cost of one unit (company currency). */
  unitCost?: number | null;
}

/** Void entries stay on record; their movements leave the books. */
export interface StockEntry {
  id: ID;
  companyId: ID;
  kind: StockEntryKind;
  /** e.g. "ADJ-0001". */
  number: string;
  date: ISODate;
  /** Where the stock is (transfers: where it leaves from). */
  warehouseId: ID;
  /** Transfers: where the stock goes. */
  toWarehouseId?: ID | null;
  /** Adjustments: why the stock changed. */
  reason?: AdjustmentReason | null;
  reference: string;
  notes: string;
  lines: StockEntryLine[];
  status: 'posted' | 'void';
  voidedAt?: Timestamp | null;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

export type LandedCostMethod = 'value' | 'quantity';

/**
 * Charges on a bill (customs duty, freight, clearing, insurance) added to
 * the cost of the stock received on the same or another bill. The charges
 * post to inventory instead of an expense, and the cost of the items rises
 * on the date of the bill with the charges.
 */
export interface LandedCost {
  id: ID;
  companyId: ID;
  /** e.g. "LC-0001". */
  number: string;
  /** Bill carrying the charges. */
  billId: ID;
  /** Lines and charges of that bill that are landed costs. */
  sourceLineIds: ID[];
  /** Bill whose stock lines receive the charges (the same bill or another one). */
  targetBillId: ID;
  /** Stock lines of the target bill that share the charges; empty means all of them. */
  targetLineIds: ID[];
  method: LandedCostMethod;
  notes: string;
  status: 'active' | 'void';
  voidedAt?: Timestamp | null;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/* -------------------------------------------------------------------------- */
/* Payroll                                                                    */
/* -------------------------------------------------------------------------- */

/** Social security contribution rates from a date, in percent of the insured salary. */
export interface ContributionRates {
  /** First day the rates apply. */
  from: ISODate;
  employer: number;
  employee: number;
  /** Highest monthly salary contributions are charged on; null for no limit. */
  cap: number | null;
}

/** The home-country scheme of GCC nationals, collected through PIFSS. */
export interface GccScheme {
  /** ISO code of the nationality (SA, AE, BH, QA, OM). */
  country: string;
  employer: number;
  employee: number;
  cap: number | null;
}

/** Accounts the payroll posts to; see PAYROLL_ACCOUNTS in db/payroll.ts. */
export type PayrollAccountKey =
  | 'salaries'
  | 'allowances'
  | 'pifssExpense'
  | 'eosExpense'
  | 'leaveExpense'
  | 'salariesPayable'
  | 'pifssPayable'
  | 'leaveProvision'
  | 'eosProvision'
  | 'advances'
  | 'otherDeductions';

/** Columns a salary transfer (WPS) file can have. */
export type SalaryFileColumn =
  | 'employeeNumber'
  | 'civilId'
  | 'nameEn'
  | 'nameAr'
  | 'iban'
  /** Account or salary card number, for staff paid without an IBAN. */
  | 'accountNumber'
  | 'bankCode'
  | 'swift'
  | 'amount'
  | 'currency'
  | 'period'
  | 'pamFile'
  | 'reference';

export type SalaryPeriodFormat = 'yyyymm' | 'yyyy-mm' | 'mm/yyyy';

/** Layout of the salary transfer file; there is no public standard, so it is set per bank. */
export interface SalaryFileLayout {
  /** Preset the layout started from, or "custom". */
  preset: string;
  columns: SalaryFileColumn[];
  /** First row holds the column names. */
  header: boolean;
  periodFormat: SalaryPeriodFormat;
}

/** Payroll settings of a company (one row per company, id = companyId). */
export interface PayrollSettings {
  id: ID;
  companyId: ID;
  /** Working days in a month for the daily rate (26 for a six-day week, art. 67). */
  dailyDivisor: number;
  /** Overtime and unpaid days are worked out on the basic salary or the whole wage. */
  rateBase: 'basic' | 'wage';
  /** PIFSS rates of Kuwaiti staff, by the date they apply from. */
  pifss: ContributionRates[];
  /** Rates of GCC nationals' home schemes; empty until entered. */
  gcc: GccScheme[];
  /** Monthly minimum wage of the private sector (company currency). */
  minimumWage: number;
  /** Day of the month salaries are paid (the month's last day when shorter). */
  payDay: number;
  /** Bank account salaries are paid from; null uses the main bank account. */
  bankAccountId: ID | null;
  /** Accounts chosen instead of the ones found by code. */
  accounts: Partial<Record<PayrollAccountKey, ID>>;
  /** Post end-of-service and leave salary provisions when a pay run is approved. */
  provisions: boolean;
  /** Include staff insured with PIFSS (Kuwaiti and GCC) in the end-of-service provision. */
  eosForInsured: boolean;
  /** The company's file number with the Public Authority for Manpower. */
  pamFileNumber: string;
  salaryFile: SalaryFileLayout;
  /**
   * The company's annual leave policy, saved from Payroll → Settings. Missing:
   * the law's, as before (see DEFAULT_LEAVE_POLICY).
   */
  leavePolicy?: LeavePolicy;
  /**
   * The company's own leave reasons (Payroll → Leave reasons), archived ones
   * included (D11). Missing: none, as before.
   */
  leaveReasons?: LeaveReason[];
  /**
   * The company's leave reasons are offered when leave is recorded. Missing
   * or false: leave is recorded with the six types only, as before. Leave
   * already recorded with a reason keeps its pay either way.
   */
  leaveReasonsOn?: boolean;
  /**
   * From its date on, a month of service with more than 15 days of unpaid
   * leave earns no annual leave. Missing or null: every month of service
   * earns annual leave, as before.
   */
  leaveAccrualPause?: { from: ISODate } | null;
  updatedAt: Timestamp;
}

/**
 * How leave of one of the company's own reasons is paid, and what it does to
 * balances: on full pay, on half pay, without pay, taken from the annual
 * leave balance (on full pay), or on full pay from a balance of its own that
 * is added to by hand (compensatory days).
 */
export type LeaveReasonPay = 'full' | 'half' | 'unpaid' | 'annual' | 'balance';

/**
 * A leave reason of the company's own (D11), such as emergency leave or
 * compensatory days. Leave recorded with it keeps the reason's `base` in
 * LeaveRecord.type, so older versions read it as that type.
 */
export interface LeaveReason {
  id: ID;
  name: string;
  nameAr: string;
  /** No longer offered for new leave; leave already recorded with it keeps it. */
  archived?: boolean;
  /** The type older versions read: worked out from `pay` (see leaveReasonBase). */
  base: LeaveType;
  pay: LeaveReasonPay;
  /** Most days a calendar year, as the reason counts them; null or missing: no limit. */
  maxDaysPerYear?: number | null;
  /**
   * Offered only for employees of these categories (such as domestic workers,
   * under Law 68/2015); missing or empty: for everyone.
   */
  categories?: EmployeeCategory[];
  /** A note must be given when leave is recorded with it. */
  noteRequired?: boolean;
}

/** Days of annual leave a year, earned from a date on. */
export interface AnnualLeaveDays {
  from: ISODate;
  /** At least 30 (art. 70). */
  days: number;
}

/** How a company gives annual leave; balances before its first date don't change. */
export interface LeavePolicy {
  /** Days a year from each date, oldest first; before the first date, the law's 30. */
  annualDays: AnnualLeaveDays[];
  /** Months of service before annual leave can be taken in the first year (nine, art. 70). */
  firstYearMonths: number;
  /**
   * Most unused days carried into a new calendar year, from the first date
   * on; the rest is lost. Null: every unused day carries forward.
   */
  carryForwardMax: number | null;
  /** How annual leave is counted. Kept once leave is recorded: its days are stored when saved. */
  counting: 'working' | 'calendar';
}

/** Rules a pay run was worked out with, copied from the settings when it was prepared. */
export interface PayRules {
  dailyDivisor: number;
  rateBase: 'basic' | 'wage';
  /** PIFSS rates in force in the month; null when none are set. */
  pifss: ContributionRates | null;
  gcc: GccScheme[];
  minimumWage: number;
}

export type PayRunStatus = 'draft' | 'approved' | 'paid';

/** An addition to or deduction from one employee's pay, with a note. */
export interface PayAdjustment {
  id: ID;
  type: 'addition' | 'deduction';
  amount: number;
  note: string;
}

/** Part of a staff loan recovered from pay or at settlement. */
export interface LoanRecovery {
  loanId: ID;
  amount: number;
}

/** Days paid at a reduced rate, such as sick leave at 75% (art. 69). */
export interface ReducedPayDays {
  /** Share of the daily wage still paid, in percent. */
  percent: number;
  days: number;
}

export interface PayLineAllowance {
  id: ID;
  name: string;
  nameAr: string;
  /** Full monthly amount. */
  monthly: number;
  /** Amount for the days employed in the month. */
  amount: number;
}

/**
 * One employee's pay in a pay run. The employee's details are copied when
 * the run is prepared so a run keeps its history; amounts are worked out by
 * calculatePayLine (lib/hr/payroll.ts) and stored with the run.
 */
export interface PayLine {
  id: ID;
  employeeId: ID;
  number: string;
  name: string;
  nameAr: string;
  jobTitle: string;
  jobTitleAr: string;
  /** The employee's department (English name) when the run was prepared; older runs don't have it. */
  department?: string;
  category: EmployeeCategory;
  nationality: string;
  /** The Civil ID (printed on the payslip, used by the bank's salary file). */
  civilId: string;
  /**
   * A stateless employee's review card number: the bank's salary file uses it
   * when there is no Civil ID. Older runs don't have it.
   */
  centralCardNumber?: string;
  iban: string;
  /** Account or salary card number, for staff paid without an IBAN (older runs don't have it). */
  accountNumber?: string;
  hireDate: ISODate | null;
  leavingDate: ISODate | null;
  permitSalary: number;
  monthlyBasic: number;
  allowances: PayLineAllowance[];
  /** Calendar days employed in the month (joiners and leavers are paid pro rata). */
  daysWorked: number;
  daysInMonth: number;
  /** Overtime hours on normal days (+25%), rest days (+50%) and public holidays (double). */
  overtime: { normal: number; restDay: number; holiday: number };
  /** Unpaid absence entered for the month, in days. */
  absentDays: number;
  /**
   * Unpaid leave and sick leave without pay taken in the month (from leave
   * records), in working days: what versions of the app before October 2026
   * deduct at the daily rate. This version pays from `calendarLeave`.
   */
  unpaidLeaveDays: number;
  /** Sick leave paid at a reduced rate in the month, in working days (as above). */
  reducedPay: ReducedPayDays[];
  /**
   * The month's leave in calendar days (from leave records): the pay it costs
   * is a share of the month's pay (wage × days ÷ days in the month), so a
   * month of unpaid leave pays nothing. Older versions don't know it and keep
   * reading the working days above, which mean to them what they always did.
   */
  calendarLeave?: { unpaidDays: number; reducedPay: ReducedPayDays[] };
  /**
   * 'calendar' on lines prepared on 5 and 6 October 2026, before
   * `calendarLeave`: their unpaidLeaveDays and reducedPay are calendar days.
   */
  leaveBasis?: 'calendar';
  /**
   * The month's leave of the company's own reasons, for the payslip (display
   * only; the pay is worked out from the days above). Set on lines whose
   * month has such leave; lines prepared by older versions don't have it.
   */
  leaveDetail?: PayLineLeave[];
  adjustments: PayAdjustment[];
  loans: LoanRecovery[];
  basic: number;
  allowanceTotal: number;
  overtimePay: number;
  /** Pay not earned for unpaid days and reduced-pay sick days. */
  absenceDeduction: number;
  additions: number;
  gross: number;
  pifssBase: number;
  pifssEmployee: number;
  pifssEmployer: number;
  /**
   * The employee's PIFSS share the month's pay doesn't cover (a month of
   * unpaid leave): owed by the employee instead of a net pay below zero. The
   * pay run records it in staff advances and recovers it from a later salary
   * as a loan (StaffLoan.payRunId).
   */
  pifssOwed?: number;
  loanDeduction: number;
  otherDeductions: number;
  net: number;
}

/** Leave of one of the company's reasons in a pay line's month. */
export interface PayLineLeave {
  reasonId: ID;
  name: string;
  nameAr: string;
  /** Days of it in the month, as the reason counts them. */
  days: number;
  /** Share of pay of those days, in percent. */
  percent: number;
  /** Taken from the annual leave balance. */
  fromAnnual?: boolean;
}

/** One employee's month-end provisions, as a pay run posted them. */
export interface ProvisionLine {
  employeeId: ID;
  /** End-of-service indemnity as at the month end. */
  eos: number;
  /** Unused annual leave days and their value. */
  leaveDays: number;
  leave: number;
}

/** A month's payroll: one per company and month. */
export interface PayRun {
  id: ID;
  companyId: ID;
  /** Month paid, as yyyy-MM. */
  period: string;
  status: PayRunStatus;
  /** Day the salaries are posted: the last day of the month. */
  date: ISODate;
  /** Day the salaries are to be paid. */
  payDate: ISODate;
  lines: PayLine[];
  rules: PayRules;
  /** Account other deductions are credited to; null uses the payroll setting. */
  deductionAccountId: ID | null;
  journalId: ID | null;
  provisionJournalId: ID | null;
  /** Month-end provisions per employee, as posted; null when none were posted. */
  provisions: ProvisionLine[] | null;
  paidOn: ISODate | null;
  paymentJournalId: ID | null;
  bankAccountId: ID | null;
  /** Entries that reversed this run's postings when it was reopened or a payment undone. */
  reversalJournalIds: ID[];
  notes: string;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

export type LeaveType = 'annual' | 'sick' | 'maternity' | 'hajj' | 'bereavement' | 'unpaid';

/**
 * Leave taken by an employee, or a change to the annual leave balance:
 * "opening" sets the balance on `start` (leave before it is not counted),
 * "adjustment" adds days (or removes them when negative).
 */
export interface LeaveRecord {
  id: ID;
  companyId: ID;
  employeeId: ID;
  type: LeaveType;
  kind: 'leave' | 'opening' | 'adjustment';
  start: ISODate;
  end: ISODate;
  /** Days counted (working or calendar days, see LEAVE_TYPES); days added for a balance change. */
  days: number;
  status: 'approved' | 'cancelled';
  notes: string;
  /**
   * The company's leave reason it was recorded with (PayrollSettings.leaveReasons);
   * `type` holds the reason's base. Missing: leave of its type, as before. A
   * balance change with a reason adds days to that reason's own balance.
   */
  reasonId?: ID;
  /**
   * Share of pay, in percent, of unpaid leave paid in part (50 for a reason on
   * half pay), fixed when it is recorded. Missing: unpaid leave pays nothing,
   * as before. Older versions read it as unpaid leave.
   */
  payPercent?: number;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/** An interest-free loan or salary advance to an employee, recovered from pay (art. 59). */
export interface StaffLoan {
  id: ID;
  companyId: ID;
  employeeId: ID;
  /** Day the money was paid to the employee. */
  date: ISODate;
  amount: number;
  /** Deducted from each month's pay until the loan is repaid. */
  instalment: number;
  /** First month an instalment is deducted, as yyyy-MM. */
  firstPeriod: string;
  /** Account the money was paid from; null uses the main bank account. */
  paidFromAccountId: ID | null;
  journalId: ID | null;
  status: 'active' | 'cancelled';
  /** Entry that reversed the loan when it was cancelled. */
  cancelJournalId: ID | null;
  /**
   * The pay run this is the PIFSS share of: what that month's pay didn't
   * cover, owed by the employee. Its entry recorded it (no payment), and
   * reopening the run removes it.
   */
  payRunId?: ID | null;
  notes: string;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/** Salary for the last days worked, paid with the final settlement. */
export interface SettlementSalary {
  period: string;
  days: number;
  daysInMonth: number;
  basic: number;
  allowances: number;
  gross: number;
  pifssEmployee: number;
  pifssEmployer: number;
}

/** What an employee is paid on leaving: indemnity, notice, leave and last salary, less loans. */
export interface FinalSettlement {
  id: ID;
  companyId: ID;
  employeeId: ID;
  status: 'posted' | 'paid' | 'reversed';
  leavingDate: ISODate;
  reason: LeavingReason;
  years: number;
  /** Monthly wage the indemnity is based on. */
  eosWage: number;
  /** Indemnity paid, after the art. 53 share and any PIFSS offset. */
  indemnity: number;
  pifssOffset: number;
  noticeMonths: number;
  noticePay: number;
  leaveDays: number;
  leavePay: number;
  /** Null when the last salary is paid in a pay run. */
  lastSalary: SettlementSalary | null;
  loans: LoanRecovery[];
  otherDeductions: number;
  deductionNote: string;
  /** Provisions released for the employee (their share of the last month-end provision). */
  eosProvision: number;
  leaveProvision: number;
  net: number;
  journalId: ID | null;
  paidOn: ISODate | null;
  paymentJournalId: ID | null;
  bankAccountId: ID | null;
  reversalJournalIds: ID[];
  notes: string;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/* -------------------------------------------------------------------------- */
/* Employee letters                                                           */
/* -------------------------------------------------------------------------- */

export type LetterKind =
  | 'salary_certificate'
  | 'experience_certificate'
  | 'employment_certificate'
  | 'warning'
  | 'noc'
  | 'salary_transfer'
  | 'custom';

/** What makes a letter's draft by itself. */
export type LetterTrigger = 'joining' | 'leaving' | 'salary_change';

export type LetterLanguage = 'en' | 'ar' | 'ar-en';

/** The wording of a kind of HR letter, with fields filled from the employee's record. */
export interface LetterTemplate {
  id: ID;
  companyId: ID;
  kind: LetterKind;
  name: string;
  nameAr?: string;
  language: LetterLanguage;
  subjectEn: string;
  subjectAr: string;
  bodyEn: string;
  bodyAr: string;
  showStamp: boolean;
  showSignature: boolean;
  signatoryName: string;
  signatoryTitle: string;
  /** Events that make a draft of this letter by themselves. */
  autoOn?: LetterTrigger[];
  /**
   * The letter may show the Civil ID, passport number and bank account
   * ({employee.civilId}…): filled in only for the owner, an admin or an
   * approver, and only when the text asks for them. Missing: never shown.
   */
  privateFields?: boolean;
  archived: boolean;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/** A letter to or about an employee: a draft, then numbered and frozen once issued. */
export interface EmployeeLetter {
  id: ID;
  companyId: ID;
  employeeId: ID;
  templateId: ID | null;
  kind: LetterKind;
  /** Empty while a draft; given at issue and never reused. */
  number: string;
  language: LetterLanguage;
  /** Who the letter is addressed to ("To whom it may concern", a bank…). */
  addressee: string;
  purpose: string;
  subject: string;
  /** The filled text, frozen at issue. */
  body: string;
  /** Null while a draft. */
  issuedOn: ISODate | null;
  status: 'draft' | 'issued' | 'void';
  /** The event that made the draft; null for a letter made by hand. */
  trigger: LetterTrigger | null;
  voidReason?: string;
  /**
   * The English half of a letter in Arabic and English (`language` ar-en):
   * `subject` and `body` are then the Arabic. Frozen at issue like them.
   */
  subjectEn?: string;
  bodyEn?: string;
  /** Who signs, and whether the stamp and signature print: the template's, kept at issue. */
  signatoryName?: string;
  signatoryTitle?: string;
  showStamp?: boolean;
  showSignature?: boolean;
  /** The day it was voided. */
  voidedOn?: ISODate;
  /** When it was last printed (Letters to print lists those issued and never printed). */
  printedAt?: Timestamp;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/* -------------------------------------------------------------------------- */
/* Approvals                                                                  */
/* -------------------------------------------------------------------------- */

export type ApprovalKind =
  | 'invoice_edit'
  | 'invoice_void'
  | 'invoice_unvoid'
  | 'cheque_create'
  | 'cheque_edit'
  | 'cheque_delete'
  | 'cheque_replace'
  | 'security_cheque_cash'
  | 'payroll'
  | 'letter'
  | 'stock_issue';

export type ApprovalStatus = 'pending' | 'approved' | 'rejected' | 'cancelled' | 'applied';

/**
 * A change waiting for an approver (an invoice edited after it was issued,
 * a cheque, a pay run). It is private when the record it is about is payroll
 * or people data.
 */
export interface ApprovalRequest {
  id: ID;
  companyId: ID;
  kind: ApprovalKind;
  /** The synced table of the record it is about (documents, payments, payRuns…). */
  subjectTbl: string;
  subjectId: ID;
  /** The record's number or period, to show without opening it. */
  subjectNumber: string;
  /** What the record was when it was asked, where showing the change needs it. */
  before?: Record<string, unknown> | null;
  /** The change asked for: the proposed record, or what to do with it. */
  after?: Record<string, unknown> | null;
  reason: string;
  status: ApprovalStatus;
  /** The account that asked (the server sets it). */
  requestedBy: string;
  /** Their name as the team knows it, to show where the team list can't be read. */
  requestedByName?: string;
  requestedAt: Timestamp;
  /** The account that decided (the server sets it). */
  decidedBy: string | null;
  decidedAt: Timestamp | null;
  decisionNote: string;
  /** Cancelled because it waited longer than the company's rules allow. */
  expired?: boolean;
  /** What carrying it out made, e.g. the payment of a confirmed cheque. */
  resultId?: ID;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}
