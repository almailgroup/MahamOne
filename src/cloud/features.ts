import { db } from '@/db/db';
import type { CloudLink } from './types';

/**
 * What a company's server has beyond the first migrations, as
 * public.server_features reports it. A feature that keeps records the
 * server must know about stays hidden until the owner has run the
 * migration that adds them: an older server would refuse every one of them.
 * The answer is kept on the link and asked again as the company syncs (see
 * refreshFeatures in sync.ts).
 */
export type ServerFeature =
  /** 20261102000000_tables_v16.sql: cheque layouts, vehicles, approvals and letters. */
  | 'tables_v16'
  /**
   * 20261116000000_super_admin_approvals.sql: the owner's limits per member,
   * approvers, and the owner's switch for admins and accountants.
   */
  | 'super_admin'
  /**
   * The same file: approval requests staff may make, the rules that keep
   * issued invoices and credit notes for approvers to change (Settings →
   * Approvals) and Void instead of delete.
   */
  | 'approvals'
  /**
   * The same file: cheques an approver confirms (Settings → Approvals →
   * Cheques); recorded by anyone else, they wait as requests.
   */
  | 'cheque_approvals'
  /**
   * 20261123000000_change_feed.sql: the changes of the team for the owner and
   * approvers (the bell, Updates, and Settings → Email alerts → Changes by
   * your team). Only ever for companies kept in the cloud.
   */
  | 'change_feed'
  /**
   * 20261130000000_people_alerts.sql: salary approval by the Super Admin
   * (Settings → Approvals → Pay runs): the cloud keeps a pay run's approval
   * honest, and emails the approvers its totals by department and position.
   */
  | 'payroll_approvals'
  /**
   * The same file: accountants get the morning email alerts too, and each
   * person chooses the kinds of paper they are told about (Settings → Email
   * alerts); the expiry reminders can show in Updates (#18).
   */
  | 'document_alerts'
  /**
   * The same file: employee letters (#19). With the company's letters on,
   * the cloud lets only the owner, an admin or an approver issue, change or
   * void a letter, never takes an issued one back to a draft nor deletes it,
   * and keeps the letters switch for the owner and admins.
   */
  | 'employee_letters'
  /**
   * 20261207000000_staffing_costings.sql: manpower costings of Maham People
   * (#3), private like payroll, and their activity.
   */
  | 'staffing_costings'
  /**
   * 20261208000000_ai_assistant.sql: the cloud keeps the AI assistant's
   * switch (Settings → AI assistant) for the owner and the admins. Nothing
   * waits for it: until it runs the device keeps the switch for them, so
   * the app works the same either way.
   */
  | 'ai_assistant'
  /**
   * 20261210000000_warehouse_issues.sql: sub-warehouses with the person who
   * looks after them, and items issued to employees, confirmed by an
   * approver. Until it runs, the cloud has neither and the app offers them
   * only for companies kept on this device.
   */
  | 'stock_issues';

/**
 * Whether a company may use a feature: always when it is kept on this
 * device only (`link` null), in the cloud once its server has said it has it.
 */
export function linkHasFeature(link: CloudLink | null, feature: ServerFeature): boolean {
  if (link === null) return true;
  return link.features?.includes(feature) ?? false;
}

/** linkHasFeature for a company, outside React. */
export async function companyHasFeature(
  companyId: string,
  feature: ServerFeature,
): Promise<boolean> {
  return linkHasFeature((await db.syncState.get(companyId)) ?? null, feature);
}
