import { NavLink, useNavigate, useParams } from 'react-router';
import { CalendarCheck } from 'lucide-react';
import { cn } from '@/lib/cn';
import { msg, t } from '@/i18n';
import { ButtonLink } from '@/components/ui/button';
import { PageHeader } from '@/components/ui/misc';
import { Select } from '@/components/ui/form';
import { ReportLanguageProvider } from '@/apps/books/features/reports/report-language';
import { PayrollNotIncluded } from '@/features/cloud/role-gates';
import type { StatementId } from '@/apps/books/features/reports/model';
import { GeneralLedgerReport, StatementReport } from './financial';
import { AuditorPack } from './auditor-pack';
import { SalesReports, type SalesReportId } from './sales';
import { INVENTORY_REPORTS, InventoryReports, type InventoryReportId } from './inventory';
import { ReceivablesReports, type ReceivablesReportId } from './receivables';

const GROUPS = [
  {
    title: msg('Financial statements'),
    items: [
      { id: 'balance-sheet', label: msg('Balance sheet') },
      { id: 'profit-and-loss', label: msg('Profit and loss') },
      { id: 'changes-in-equity', label: msg('Changes in equity') },
      { id: 'cash-flow', label: msg('Cash flow') },
    ],
  },
  {
    title: msg('Accounting'),
    items: [
      { id: 'trial-balance', label: msg('Trial balance') },
      { id: 'general-ledger', label: msg('General ledger') },
      { id: 'asset-schedule', label: msg('Fixed asset schedule') },
      { id: 'auditor-pack', label: msg('Auditor pack') },
    ],
  },
  {
    title: msg('Sales'),
    items: [
      { id: 'aging', label: msg('Receivables aging') },
      { id: 'tax', label: msg('Tax summary') },
      { id: 'sales', label: msg('Sales by client') },
      { id: 'payments', label: msg('Payments received') },
    ],
  },
  {
    title: msg('Credit control'),
    items: [
      { id: 'statements', label: msg('Statements of account') },
      { id: 'exposure', label: msg('Customer exposure') },
      { id: 'retentions', label: msg('Retentions') },
    ],
  },
  {
    title: msg('Purchases'),
    items: [
      { id: 'payables', label: msg('Payables aging') },
      { id: 'purchases', label: msg('Purchases by vendor') },
      { id: 'payments-made', label: msg('Payments made') },
    ],
  },
  {
    title: msg('Inventory'),
    items: [
      { id: 'stock-on-hand', label: msg('Stock on hand') },
      { id: 'stock-valuation', label: msg('Stock valuation') },
      { id: 'stock-movements', label: msg('Stock movements') },
      { id: 'low-stock', label: msg('Low stock') },
      { id: 'issued-items', label: msg('Issued items') },
    ],
  },
];

const STATEMENTS: StatementId[] = [
  'balance-sheet',
  'profit-and-loss',
  'changes-in-equity',
  'cash-flow',
  'trial-balance',
  'asset-schedule',
];

const RECEIVABLES: ReceivablesReportId[] = ['statements', 'exposure', 'retentions'];

const SALES: SalesReportId[] = [
  'aging',
  'tax',
  'sales',
  'payments',
  'payables',
  'purchases',
  'payments-made',
];

export default function ReportsPage() {
  const { report = 'profit-and-loss' } = useParams();
  const navigate = useNavigate();
  const known = GROUPS.some((g) => g.items.some((i) => i.id === report));
  const current = known ? report : 'profit-and-loss';

  return (
    <ReportLanguageProvider>
      <PageHeader
        title={t('Reports')}
        description={t('Financial statements, sales, purchases and stock, from your own books.')}
        actions={
          <ButtonLink to="/year-end" variant="outline">
            <CalendarCheck /> {t('Year-end close')}
          </ButtonLink>
        }
      />
      <div className="grid gap-6 lg:grid-cols-[220px_minmax(0,1fr)]">
        <nav aria-label={t('Reports')} className="hidden lg:block">
          {GROUPS.map((group) => (
            <div key={group.title} className="mb-5">
              <p className="mb-1 px-3 text-xs font-semibold tracking-wide text-slate-500 uppercase">
                {t(group.title)}
              </p>
              {group.items.map((item) => (
                <NavLink
                  key={item.id}
                  to={`/reports/${item.id}`}
                  className={() =>
                    cn(
                      'block rounded-lg px-3 py-1.5 text-sm',
                      current === item.id
                        ? 'bg-primary-50 text-primary-700 font-medium'
                        : 'text-slate-600 hover:bg-slate-100 hover:text-slate-900',
                    )
                  }
                >
                  {t(item.label)}
                </NavLink>
              ))}
            </div>
          ))}
        </nav>
        <div className="min-w-0">
          <div className="mb-4 lg:hidden">
            <Select
              aria-label={t('Report')}
              value={current}
              onChange={(e) => navigate(`/reports/${e.target.value}`)}
            >
              {GROUPS.map((group) => (
                <optgroup key={group.title} label={t(group.title)}>
                  {group.items.map((item) => (
                    <option key={item.id} value={item.id}>
                      {t(item.label)}
                    </option>
                  ))}
                </optgroup>
              ))}
            </Select>
          </div>
          {STATEMENTS.includes(current as StatementId) ||
          current === 'general-ledger' ||
          current === 'auditor-pack' ? (
            <PayrollNotIncluded className="mb-4" />
          ) : null}
          {STATEMENTS.includes(current as StatementId) ? (
            <StatementReport key={current} id={current as StatementId} />
          ) : null}
          {current === 'general-ledger' ? <GeneralLedgerReport /> : null}
          {current === 'auditor-pack' ? <AuditorPack /> : null}
          {SALES.includes(current as SalesReportId) ? (
            <SalesReports report={current as SalesReportId} />
          ) : null}
          {INVENTORY_REPORTS.includes(current as InventoryReportId) ? (
            <InventoryReports report={current as InventoryReportId} />
          ) : null}
          {RECEIVABLES.includes(current as ReceivablesReportId) ? (
            <ReceivablesReports key={current} report={current as ReceivablesReportId} />
          ) : null}
        </div>
      </div>
    </ReportLanguageProvider>
  );
}
