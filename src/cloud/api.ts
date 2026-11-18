import { msg, t } from '@/i18n';
import type { AlertTopic } from '@/alerts/topics';
import type { MemberPermissions, MemberRole } from './roles';
import type { ChangeDigest, ImmediateKind } from './change-feed';
import type { DocumentAlertKind } from '@/lib/compliance';

/**
 * What the app asks of the cloud. The sync engine only talks to this
 * interface: in the app it is Supabase (see supabase-api.ts), in tests an
 * in-memory server with the same rules.
 */

export interface PushChange {
  tbl: string;
  id: string;
  data?: Record<string, unknown>;
  deleted?: boolean;
  /** Server version this device last had, if any. */
  base_rev?: number | null;
}

export interface PushResult {
  tbl: string;
  id: string;
  /** New server version; null for deleting something that was never stored. */
  rev: number | null;
  /** The server had a newer version (or a newer delete) that this one replaced. */
  conflict: boolean;
}

export interface PulledRow {
  tbl: string;
  id: string;
  /** Null for a deleted record. */
  data: Record<string, unknown> | null;
  rev: number;
  deleted: boolean;
}

export interface SyncInfo {
  purgedUntilRev: number;
  recordCount: number;
  maxRev: number;
}

export interface CloudCompany {
  id: string;
  name: string;
  role: MemberRole;
  createdAt: string;
  members: number;
}

/** An employee items can be issued to, as stock_issue_recipients gives them. */
export interface IssueRecipientRow {
  id: string;
  number: string;
  name: string;
  nameAr: string;
  jobTitle: string;
  jobTitleAr: string;
  department: string;
}

export interface TeamMember {
  userId: string;
  fullName: string;
  email: string;
  role: MemberRole;
  joinedAt: string;
}

/** The signed-in person's own limits in a company (my_permissions). */
export interface MyPermissions {
  permissions: MemberPermissions;
  /** Decides approval requests: the owner, or an admin or accountant the owner allowed. */
  approver: boolean;
  /** The owner of the company: its Super Admin. */
  owner: boolean;
  /** Only the owner makes admins and accountants. */
  seniorRolesOwnerOnly: boolean;
}

/** A member's limits and approver mark, as the owner set them (team_permissions). */
export interface MemberAccess {
  userId: string;
  permissions: MemberPermissions;
  canApprove: boolean;
}

/** A company the signed-in person owns, for Settings → Companies. */
export interface OwnedCompany {
  id: string;
  name: string;
  members: number;
  /** Approval requests waiting for a decision. */
  pendingApprovals: number;
}

export interface Invite {
  id: string;
  email: string;
  role: MemberRole;
  token: string;
  createdAt: string;
  expiresAt: string;
  invitedByName: string;
}

export interface InviteDetails {
  companyId: string;
  companyName: string;
  invitedByName: string;
  email: string;
  role: MemberRole;
  expiresAt: string;
  status: 'pending' | 'expired' | 'revoked' | 'accepted';
  emailMatches: boolean;
}

export interface StoredFile {
  /** Path in the bucket: {companyId}/{fileId}. */
  path: string;
  createdAt: string | null;
}

export interface RecordKey {
  tbl: string;
  id: string;
}

/**
 * One field of the company record that changed on this device: set to
 * `value`, or removed. `base` is what it was in the copy this device last
 * had from the cloud (left out when it had none).
 */
export interface CompanyOp {
  path: string[];
  value?: unknown;
  remove?: true;
  base?: unknown;
}

export interface CompanyPatchResult {
  /** New server version of the company record. */
  rev: number;
  /** Fields that had also changed in the cloud; this device's value was kept. */
  conflicts: string[][];
}

/** A document counter taken on the server for one new number. */
export interface ReservedCounter {
  counter: number;
  /** Period the counter belongs to ("2026", "2026-10" or "" for counters that never reset). */
  period: string;
}

/** The signed-in person's morning email for a company (Settings → Email alerts). */
export interface EmailAlertSettings {
  enabled: boolean;
  topics: AlertTopic[];
  lastSentAt: string | null;
  /** The last problem sending it; empty when there is none. */
  lastError: string;
  lastErrorAt: string | null;
  /** The email-alerts function has been published and has run at least once. */
  functionReady: boolean;
}

/**
 * A change of the team's, from the change feed (notification_feed): who
 * made it, what kind of record and what happened. Folds of ordinary changes
 * of one sync have a count above 1.
 */
export interface ChangeEvent {
  id: number;
  at: string;
  /** The account that made it; null for the server's own changes. */
  actor: string | null;
  actorName: string;
  /** For team changes: the member it was about. */
  subjectName: string;
  /** document, payment, cheque, approval, settings, member, people… (see change-feed.ts). */
  kind: string;
  /** insert, update, delete, or mixed for a fold. */
  op: string;
  tbl: string;
  recordId: string;
  count: number;
  important: boolean;
  /** About payroll or people data: no names or amounts in it. */
  private: boolean;
  summary: Record<string, unknown>;
  unread: boolean;
}

/** Whether the person gets the changes of the team, and what is unread (notification_status). */
export interface ChangeFeedStatus {
  enabled: boolean;
  /** Unread changes, counted up to 100. */
  unread: number;
  /** The newest change the person may see; 0 when there is none. */
  latest: number;
}

/** The person's choice for the changes of the team (Settings → Email alerts). */
export interface ChangeNotificationSettings {
  enabled: boolean;
  /** Important changes of these kinds are emailed within minutes. */
  immediateKinds: ImmediateKind[];
  /** Everything else in a summary at 8:00 Kuwait time, or not by email. */
  digest: ChangeDigest;
  lastSentAt: string | null;
  lastError: string;
  lastErrorAt: string | null;
  /** The email-alerts function has been published and has run at least once. */
  functionReady: boolean;
}

export type AlertEmailErrorCode =
  | 'offline'
  | 'auth'
  | 'permission'
  | 'invalid'
  | 'not_enabled'
  | 'too_soon'
  | 'no_company'
  | 'not_configured'
  | 'not_ready'
  | 'not_deployed'
  | 'send_failed'
  | 'failed';

const ALERT_EMAIL_ERROR_CODES: readonly string[] = [
  'offline',
  'auth',
  'permission',
  'invalid',
  'not_enabled',
  'too_soon',
  'no_company',
  'not_configured',
  'not_ready',
  'not_deployed',
  'send_failed',
  'failed',
];

export function isAlertEmailErrorCode(value: unknown): value is AlertEmailErrorCode {
  return typeof value === 'string' && ALERT_EMAIL_ERROR_CODES.includes(value);
}

/** "Send it now" did not work; `detail` is the email service's own words, if any. */
export class AlertEmailError extends Error {
  constructor(
    readonly code: AlertEmailErrorCode,
    readonly detail = '',
  ) {
    super(detail || code);
    this.name = 'AlertEmailError';
  }
}

export interface CloudApi {
  createCompany(id: string, name: string): Promise<void>;
  myCompanies(): Promise<CloudCompany[]>;
  pushRecords(companyId: string, changes: PushChange[]): Promise<PushResult[]>;
  pullRecords(companyId: string, since: number, limit: number): Promise<PulledRow[]>;
  recordIds(
    companyId: string,
    after: RecordKey | null,
    limit: number,
    table?: string,
  ): Promise<RecordKey[]>;
  syncInfo(companyId: string): Promise<SyncInfo>;
  /** One record as the cloud has it (and this person may see it), or null. */
  getRecord(
    companyId: string,
    table: string,
    id: string,
  ): Promise<{ data: Record<string, unknown>; rev: number } | null>;
  uploadFile(path: string, data: Blob, contentType: string): Promise<void>;
  downloadFile(path: string): Promise<Blob>;
  /** Removes files; returns the paths that were removed (what Storage hides is skipped). */
  removeFiles(paths: string[]): Promise<string[]>;
  listFiles(companyId: string): Promise<StoredFile[]>;
  /** Which of these files of the company are still stored; null when the server can't tell. */
  storedFiles(companyId: string, paths: string[]): Promise<string[] | null>;
  /**
   * Applies changed fields to the cloud's copy of the company record. Null
   * when the server can't (an older version) or the record isn't there yet:
   * the whole record is sent instead.
   */
  patchCompany(companyId: string, ops: CompanyOp[]): Promise<CompanyPatchResult | null>;
  /**
   * Takes the next counter for a new number of `kind` (an invoice…) dated
   * `date`, never below `min`. Null when the server can't, or numbers this
   * one on the device (a date in an earlier period).
   */
  reserveNumber(
    companyId: string,
    kind: string,
    date: string,
    min: number,
  ): Promise<ReservedCounter | null>;
  /**
   * What the server has beyond the first migrations ('tables_v16'…), from
   * public.server_features; empty on a server without it. The same for every
   * company today, asked per company so a later server may answer per company.
   */
  serverFeatures(companyId: string): Promise<string[]>;
  /**
   * Owners: starts deleting the company in the cloud (new uploads are
   * refused meanwhile). False when the server can't (an older version);
   * throws when the person is not the owner.
   */
  beginDeleteCompany(companyId: string): Promise<boolean>;
  companyTeam(companyId: string): Promise<TeamMember[]>;
  /**
   * Who items can be issued to: the current employees' number, name, job
   * title and department (public.stock_issue_recipients, once the server has
   * 'stock_issues'), for whoever looks after a sub-warehouse. Nothing else of
   * People.
   */
  stockIssueRecipients(companyId: string): Promise<IssueRecipientRow[]>;
  createInvite(companyId: string, email: string, role: MemberRole): Promise<Invite>;
  listInvites(companyId: string): Promise<Invite[]>;
  revokeInvite(inviteId: string): Promise<void>;
  inviteDetails(token: string): Promise<InviteDetails | null>;
  acceptInvite(
    token: string,
  ): Promise<{ companyId: string; companyName: string; role: MemberRole }>;
  setMemberRole(companyId: string, userId: string, role: MemberRole): Promise<void>;
  removeMember(companyId: string, userId: string): Promise<void>;
  transferOwnership(companyId: string, userId: string): Promise<void>;
  /**
   * The signed-in person's limits in the company; null when the server
   * doesn't have them yet (the owner hasn't run the Super Admin script).
   */
  myPermissions(companyId: string): Promise<MyPermissions | null>;
  /** Every member's limits (the caller's own unless owner or admin); null as above. */
  teamPermissions(companyId: string): Promise<MemberAccess[] | null>;
  /** The owner sets a member's limits and approver mark. */
  setMemberPermissions(
    companyId: string,
    userId: string,
    permissions: MemberPermissions,
    canApprove: boolean,
  ): Promise<void>;
  /** The owner's switch: only the owner makes admins and accountants. */
  setTeamRules(companyId: string, rules: { seniorRolesOwnerOnly: boolean }): Promise<void>;
  /** The companies the signed-in person owns; null when the server doesn't have it yet. */
  ownedCompanies(): Promise<OwnedCompany[] | null>;
  deleteCompany(companyId: string): Promise<void>;
  /** Calls `onChange` when the company changes in the cloud; returns a stop function. */
  watch(companyId: string, onChange: () => void): () => void;
  /**
   * The signed-in person's email alerts for a company. Null when the server
   * doesn't have them yet (the owner hasn't run the email alerts script).
   */
  emailAlerts(companyId: string): Promise<EmailAlertSettings | null>;
  /** Saves them (owners and admins only); null when the server doesn't have them yet. */
  setEmailAlerts(
    companyId: string,
    settings: { enabled: boolean; topics: AlertTopic[]; appUrl: string },
  ): Promise<EmailAlertSettings | null>;
  /**
   * Emails the signed-in person what needs attention in the company now.
   * Throws AlertEmailError.
   */
  sendAlertEmail(companyId: string): Promise<{ to: string; count: number }>;
  /**
   * The kinds of paper the signed-in person is told about (#18): null for
   * every kind. Undefined when the server doesn't have the choice yet
   * (20261130000000_people_alerts.sql).
   */
  emailAlertScope(companyId: string): Promise<DocumentAlertKind[] | null | undefined>;
  /** Chooses them (null: every kind); false when the server doesn't have the choice yet. */
  setEmailAlertScope(companyId: string, kinds: DocumentAlertKind[] | null): Promise<boolean>;
  /**
   * Whether the signed-in person gets the changes of the team (the owner or
   * an approver who turned them on) and how many are unread. Null when the
   * server doesn't have the change feed yet.
   */
  changeFeedStatus(companyId: string): Promise<ChangeFeedStatus | null>;
  /**
   * The changes of the team, newest first, after or before a change (owner
   * and approvers only). Null when the server doesn't have the feed yet.
   */
  changeFeed(
    companyId: string,
    page?: { after?: number; before?: number; limit?: number },
  ): Promise<ChangeEvent[] | null>;
  /** Marks the changes up to `upto` as read. */
  markChangesRead(companyId: string, upto: number): Promise<void>;
  /** The person's choice for the changes of the team; null as above. */
  changeNotifications(companyId: string): Promise<ChangeNotificationSettings | null>;
  /** Saves it (owner and approvers only); null when the server doesn't have the feed yet. */
  setChangeNotifications(
    companyId: string,
    settings: {
      enabled: boolean;
      immediateKinds: ImmediateKind[];
      digest: ChangeDigest;
      appUrl: string;
    },
  ): Promise<ChangeNotificationSettings | null>;
}

/* -------------------------------------------------------------------------- */
/* Errors                                                                     */
/* -------------------------------------------------------------------------- */

export type CloudErrorCode =
  | 'offline'
  | 'auth'
  | 'permission'
  | 'not_member'
  | 'invalid'
  | 'too_large'
  | 'resync'
  | 'company_taken'
  | 'company_exists'
  | 'limit'
  | 'already_member'
  | 'invite_invalid'
  | 'invite_revoked'
  | 'invite_used'
  | 'invite_expired'
  | 'invite_wrong_email'
  | 'email_unconfirmed'
  | 'server'
  /** The company's server lacks a migration the record needs: it waits here until it is run. */
  | 'server_outdated'
  /** The company's approval rules: an approver must make this change (send it for approval). */
  | 'approval_required';

/** A request the cloud refused or could not answer, with a code the app acts on. */
export class CloudError extends Error {
  constructor(
    readonly code: CloudErrorCode,
    message: string,
    /** The server's own words, for the record. */
    readonly detail = '',
  ) {
    super(message);
    this.name = 'CloudError';
  }

  /** Worth trying again later as it is (connection, server, session). */
  get retryable(): boolean {
    return this.code === 'offline' || this.code === 'server' || this.code === 'auth';
  }
}

/** What each code means for the person, in plain words (English keys). */
export const CLOUD_ERROR_MESSAGES: Record<CloudErrorCode, string> = {
  offline: msg('No connection. Changes are kept on this device and sync when you are back online.'),
  auth: msg('Your session has ended. Sign in again to sync.'),
  permission: msg('Your role does not allow this change.'),
  not_member: msg('You are no longer a member of this company.'),
  invalid: msg('The cloud did not accept this change.'),
  too_large: msg('This record is too large to sync. Remove some images or attachments.'),
  resync: msg('This device needs a full sync.'),
  company_taken: msg('This company is already in the cloud under another account.'),
  company_exists: msg('This company is already in your cloud account. Download it instead.'),
  limit: msg('You have reached the limit for this account.'),
  already_member: msg('This person is already a member.'),
  invite_invalid: msg('This invitation link is not valid.'),
  invite_revoked: msg('This invitation was cancelled. Ask for a new one.'),
  invite_used: msg('This invitation has already been used.'),
  invite_expired: msg('This invitation has expired. Ask for a new one.'),
  invite_wrong_email: msg('This invitation is for another email address.'),
  email_unconfirmed: msg('Confirm your email address first.'),
  server: msg('The cloud is not answering right now. We will try again.'),
  server_outdated: msg(
    'The cloud needs the latest database script first. Ask the owner of the company to run it.',
  ),
  approval_required: msg('This change needs approval. Send it for approval instead.'),
};

const CODES = new Set<string>(Object.keys(CLOUD_ERROR_MESSAGES));

/**
 * Turns what the database or the network said into a CloudError. The
 * database's own errors start with "almail:<code>"; row-level security
 * refusals have the SQL state 42501.
 */
export function cloudError(error: unknown): CloudError {
  if (error instanceof CloudError) return error;
  const e = (error ?? {}) as { message?: string; code?: string; status?: number; name?: string };
  const message = String(e.message ?? error ?? '');
  const tagged = /almail:([a-z_]+)/.exec(message)?.[1];
  const make = (code: CloudErrorCode) =>
    new CloudError(code, t(CLOUD_ERROR_MESSAGES[code]), message);
  if (tagged && CODES.has(tagged)) return make(tagged as CloudErrorCode);
  if (e.code === '42501' || /row-level security|permission denied/i.test(message)) {
    return make('permission');
  }
  if (e.code === '23514' || e.code === '22023' || e.code === '23505') return make('invalid');
  if (e.status === 401 || /jwt|token is expired|not authenticated/i.test(message)) {
    return make('auth');
  }
  if (
    e.name === 'TypeError' ||
    /failed to fetch|networkerror|load failed|network request failed|fetch failed/i.test(message) ||
    (typeof navigator !== 'undefined' && navigator.onLine === false)
  ) {
    return make('offline');
  }
  return make('server');
}

/**
 * Turns what Storage said into a CloudError. A refusal (4xx: the rules, a
 * file too large or of a kind the bucket doesn't take) is not worth trying
 * again as it is; network trouble, rate limits and server errors are.
 */
export function storageCloudError(error: unknown): CloudError {
  if (error instanceof CloudError) return error;
  const e = (error ?? {}) as { message?: string; status?: number; statusCode?: string | number };
  const message = String(e.message ?? error ?? '');
  const status = Number(e.statusCode) || Number(e.status) || 0;
  const make = (code: CloudErrorCode) =>
    new CloudError(code, t(CLOUD_ERROR_MESSAGES[code]), message);
  if (status === 401 || /jwt|token is expired|not authenticated|invalid token/i.test(message)) {
    return make('auth');
  }
  if (status === 403 || /row-level security|access denied|unauthorized/i.test(message)) {
    return make('permission');
  }
  if (status === 413 || /too large|exceeded the maximum/i.test(message)) return make('too_large');
  if (status === 429 || status >= 500) return make('server');
  if (status >= 400) return make('invalid');
  return cloudError(error);
}

/** The message to show for any error from the cloud. */
export function cloudErrorMessage(error: unknown): string {
  return cloudError(error).message;
}
