import { DOCUMENT_ROUTES } from '@/app/company';
import type { ChangeEvent } from '@/cloud/api';
import { isKnown } from '@/lib/known';

/**
 * Where a change of the team opens in the app: the record when it has a
 * page of its own, otherwise its list or its settings. A fold of several
 * changes opens the list. Null when there is nothing to open (a deleted
 * record has only its list).
 */
export function changeLink(event: ChangeEvent): string | null {
  const s = event.summary;
  const one = event.count === 1 && event.op !== 'delete' && event.op !== 'mixed';
  const id = encodeURIComponent(event.recordId);
  // An expiry reminder (#18): the paper, or the employee whose paper it is.
  if (event.kind === 'document_expiry') {
    if (event.tbl === 'employees') return `/employees/${id}`;
    return event.recordId ? `/compliance/documents?doc=${id}` : '/compliance/documents';
  }
  switch (event.tbl) {
    case 'documents': {
      const type = String(s.type ?? '');
      if (!isKnown(DOCUMENT_ROUTES, type)) return null;
      return one ? `${DOCUMENT_ROUTES[type]}/${id}` : DOCUMENT_ROUTES[type];
    }
    case 'payments': {
      const base = s.direction === 'out' ? '/payments-made' : '/payments';
      return one ? `${base}/${id}` : base;
    }
    case 'securityCheques':
      return '/cheques';
    case 'approvals':
      return '/approvals';
    case 'company_members':
      return '/settings/team';
    case 'companies': {
      const changes = Array.isArray(s.changes) ? s.changes.map(String) : [];
      if (changes.includes('approvalRules')) return '/settings/approvals';
      if (changes.includes('lockDate')) return '/settings/accounting';
      if (changes.includes('numbering')) return '/settings/numbering';
      return '/settings/company';
    }
    case 'clients': {
      const base = s.vendor === true ? '/vendors' : '/clients';
      return one ? `${base}/${id}` : base;
    }
    case 'products':
    case 'warehouses':
      return '/products';
    case 'stockMovements':
    case 'stockEntries':
    case 'landedCosts':
      return '/inventory';
    case 'stockIssues':
      return one ? `/inventory/issues/${id}` : '/inventory/issues';
    case 'expenses':
      return '/expenses';
    case 'journals':
      return one ? `/journals/${id}` : '/journals';
    case 'accounts':
      return '/accounts';
    case 'employees':
      return one ? `/employees/${id}` : '/employees';
    case 'payRuns':
      return one ? `/payroll/runs/${id}` : '/payroll';
    case 'leaveRecords':
      return '/payroll/leave';
    case 'staffLoans':
      return '/payroll/loans';
    case 'employeeLetters':
      return '/people/letters';
    case 'letterTemplates':
      return '/people/letters/templates';
    case 'staffingCostings':
      return one ? `/people/costing/${id}` : '/people/costing';
    case 'complianceDocuments':
    case 'renewals':
    case 'complianceMarks':
      return '/compliance/documents';
    case 'vehicles':
      return '/compliance/vehicles';
    default:
      return null;
  }
}
