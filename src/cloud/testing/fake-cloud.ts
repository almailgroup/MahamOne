import {
  AlertEmailError,
  CloudError,
  type ChangeEvent,
  type ChangeNotificationSettings,
  type CloudApi,
  type CloudCompany,
  type CompanyOp,
  type EmailAlertSettings,
  type Invite,
  type MemberAccess,
  type PulledRow,
  type PushChange,
  type PushResult,
  type RecordKey,
  type StoredFile,
  type TeamMember,
} from '../api';
import {
  appLimit,
  approvalRulesChanged,
  approvalRulesOf,
  canChangeMember,
  canPostPayroll,
  companyBooksChanged,
  canWriteRecord,
  chequeChangeNeedsApprover,
  entryInSubWarehouse,
  issuerName,
  issuesFromWarehouse,
  subWarehouseLines,
  managesWarehouses,
  warehouseRuled,
  warehouseWriteRefusal,
  deleteKeptBy,
  documentChangeNeedsApproval,
  getsChangeFeed,
  getsEmailAlerts,
  grantableRoles,
  guardApprovalWrite,
  isApprover,
  isPayrollApproval,
  isPrivateRecord,
  issuesWithoutNumber,
  keepIssuedLetter,
  keepAiSwitch,
  keepLettersSwitch,
  keepPaymentLink,
  letterKept,
  letterWriteRefusal,
  lettersSwitchedOn,
  peopleSettingsKept,
  limitBlocksWrite,
  MAX_APPROVERS,
  payrollDecisionRefusal,
  readPermissions,
  rulesCoverPayroll,
  sameData,
  seesChange,
  staffCompanyChangeOk,
  type MemberPermissions,
  type MemberRole,
} from '../roles';
import { changeDetails, changeKind, IMMEDIATE_KINDS, isImmediateKind } from '../change-feed';
import { mergeNumbering } from '../numbering';
import { rebaseCompany } from '../company-patch';
import { periodKey } from '@/lib/numbering';
import {
  DOCUMENT_ALERT_KINDS,
  isDocumentAlertKind,
  type DocumentAlertKind,
} from '@/lib/compliance';
import type { CounterReset } from '@/db/types';

/**
 * An in-memory cloud with the database's rules (see the migration): revs,
 * hard deletes with markers, conflicts, the numbering merge, roles and
 * private data. Each `client(userId)` is one person's view of it. For tests
 * of the sync engine only.
 */

interface Row {
  company: string;
  tbl: string;
  id: string;
  data: Record<string, unknown>;
  rev: number;
}

interface Marker {
  company: string;
  tbl: string;
  id: string;
  rev: number;
  deletedAt: number;
  private: boolean;
}

/** A row of public.change_events. */
interface Change {
  company: string;
  id: number;
  at: string;
  actor: string | null;
  op: string;
  tbl: string;
  recordId: string;
  kind: string;
  important: boolean;
  private: boolean;
  count: number;
  foldKey: string;
  summary: Record<string, unknown>;
}

/** A row of public.notification_settings. */
interface ChangeSettings extends Omit<ChangeNotificationSettings, 'functionReady'> {
  appUrl: string;
  emailedUpto: number;
}

const fail = (code: CloudError['code'], detail: string = code) =>
  new CloudError(code, detail, `almail:${code}`);

export class FakeCloud {
  companies = new Map<
    string,
    {
      id: string;
      name: string;
      purgedUntilRev: number;
      createdAt: string;
      /** Set by beginDeleteCompany: uploads are refused until then (ms). */
      deletingUntil?: number;
    }
  >();
  /**
   * A server without the second migration (20261006000000_sync_fixes.sql):
   * patchCompany, reserveNumber, storedFiles and beginDeleteCompany are
   * missing, and createCompany takes up the owner's existing company.
   */
  legacy = false;
  /** What public.server_features answers; a legacy server doesn't have it. */
  features = ['tables_v16'];
  members = new Map<string, Map<string, MemberRole>>();
  /**
   * The owner's limits and approver mark per member, by "company user"
   * (company_members.permissions and can_approve). Missing: none.
   */
  access = new Map<string, { permissions: MemberPermissions; canApprove: boolean }>();
  /** Companies whose owner makes admins and accountants alone (companies.senior_roles_owner_only). */
  seniorRolesOwnerOnly = new Set<string>();
  records = new Map<string, Row>();
  markers = new Map<string, Marker>();
  files = new Map<string, { blob: Blob; createdAt: string; owner: string }>();
  rev = 0;
  /** Every call, as "user method". */
  calls: string[] = [];
  /** While true every call fails as if offline. */
  offline = false;
  /** Errors to throw on the next calls of a method. */
  private failures = new Map<string, CloudError[]>();
  private watchers = new Map<string, Set<() => void>>();
  /** File removals fail while true. */
  storageDown = false;
  /** Email alerts by "company user"; the emails asked for, by the same key. */
  emailAlerts = new Map<string, EmailAlertSettings & { appUrl: string }>();
  alertEmails: string[] = [];
  /** The kinds of paper each person chose (#18), by "company user"; missing: every kind. */
  alertScopes = new Map<string, DocumentAlertKind[] | null>();
  /**
   * The change feed (20261123000000_change_feed.sql, once `features` has
   * 'change_feed'): the changes, each person's choice and how far they read,
   * by "company user".
   */
  changes: Change[] = [];
  changeSettings = new Map<string, ChangeSettings>();
  changeReads = new Map<string, number>();
  private changeSeq = 0;
  private pushSeq = 0;
  private pushTx = 0;

  private key(company: string, tbl: string, id: string) {
    return `${company}/${tbl}/${id}`;
  }

  /** Makes the next `count` calls of `method` fail with `code`. */
  failNext(method: keyof CloudApi, code: CloudError['code'], count = 1) {
    const list = this.failures.get(method) ?? [];
    for (let i = 0; i < count; i++) list.push(fail(code));
    this.failures.set(method, list);
  }

  addMember(company: string, user: string, role: MemberRole) {
    let members = this.members.get(company);
    if (!members) this.members.set(company, (members = new Map()));
    members.set(user, role);
    // As company_members_before_write: the owner has no limits, and only
    // admins and accountants approve.
    const key = `${company} ${user}`;
    const access = this.access.get(key);
    if (access && role === 'owner') this.access.delete(key);
    else if (access && role !== 'admin' && role !== 'accountant') access.canApprove = false;
  }

  /** The owner's limits on a member, written straight into the server (as the owner's RPC would). */
  setAccess(company: string, user: string, permissions: MemberPermissions, canApprove = false) {
    this.access.set(`${company} ${user}`, { permissions, canApprove });
  }

  private permissionsOf(company: string, user: string): MemberPermissions | undefined {
    return this.access.get(`${company} ${user}`)?.permissions;
  }

  private ownerOnly(company: string): boolean {
    return this.seniorRolesOwnerOnly.has(company);
  }

  /**
   * The company's approval rules once the server has them
   * (almailbooks.approval_rules); null without the migration or while they
   * were never turned on.
   */
  private approvalRules(company: string): Record<string, unknown> | null {
    if (!this.features.includes('approvals')) return null;
    return approvalRulesOf(this.records.get(this.key(company, 'companies', company))?.data);
  }

  /**
   * The rules for cheques, once the server has cheque confirmation
   * (cheque_approvals); null before.
   */
  private chequeRules(company: string): Record<string, unknown> | null {
    if (!this.features.includes('cheque_approvals')) return null;
    return this.approvalRules(company);
  }

  private approver(company: string, user: string): boolean {
    return isApprover(this.role(company, user), this.access.get(`${company} ${user}`)?.canApprove);
  }

  /** The server's clock, as records_guard stamps requests and decisions. */
  now = () => new Date().toISOString();

  /** Server-side view of a record. */
  record(company: string, tbl: string, id: string): Record<string, unknown> | undefined {
    return this.records.get(this.key(company, tbl, id))?.data;
  }

  rows(company: string, tbl?: string): Row[] {
    return [...this.records.values()].filter(
      (r) => r.company === company && (!tbl || r.tbl === tbl),
    );
  }

  /** Forgets deletion markers older than `days` (default: all), as the daily job would. */
  purgeMarkers(company: string) {
    const info = this.companies.get(company)!;
    for (const [key, marker] of this.markers) {
      if (marker.company !== company) continue;
      info.purgedUntilRev = Math.max(info.purgedUntilRev, marker.rev);
      this.markers.delete(key);
    }
  }

  private lookup(company: string) {
    return (tbl: string, id: string) => this.records.get(this.key(company, tbl, id))?.data ?? null;
  }

  private role(company: string, user: string): MemberRole | null {
    return this.members.get(company)?.get(user) ?? null;
  }

  private canRead(company: string, user: string, tbl: string, data: Record<string, unknown>) {
    const role = this.role(company, user);
    if (!role) return false;
    if (role === 'owner' || role === 'admin' || role === 'accountant') return true;
    return !isPrivateRecord(tbl, data, this.lookup(company));
  }

  private canWrite(company: string, user: string, tbl: string, data: Record<string, unknown>) {
    const role = this.role(company, user);
    if (!role) return false;
    // As can_write_record: the role, then the owner's limits on the member.
    return (
      canWriteRecord(role, tbl, data, this.lookup(company)) &&
      !limitBlocksWrite(role, this.permissionsOf(company, user), tbl, data, this.lookup(company))
    );
  }

  /** Mirrors almailbooks.can_use_file: files follow their attachment record. */
  private canUseFile(user: string, path: string, write: boolean): boolean {
    const parts = path.split('/');
    if (parts.length !== 2) return false;
    const [company, id] = parts;
    const role = this.role(company, user);
    if (!role) return false;
    const row = this.records.get(this.key(company, 'attachments', id));
    if (row) {
      return write
        ? this.canWrite(company, user, 'attachments', row.data)
        : this.canRead(company, user, 'attachments', row.data);
    }
    if (role === 'owner' || role === 'admin' || role === 'accountant') return true;
    if (role !== 'staff') return false;
    const marker = this.markers.get(this.key(company, 'attachments', id));
    if (marker) return !marker.private;
    // Their own upload on its way (a new upload is theirs).
    const existing = this.files.get(path);
    return existing ? existing.owner === user : write;
  }

  private notify(company: string) {
    for (const watcher of this.watchers.get(company) ?? []) watcher();
  }

  /** Someone of the company asked for its changes (almailbooks.records_change_event's gate). */
  private feedOn(company: string): boolean {
    if (!this.features.includes('change_feed')) return false;
    return [...this.changeSettings].some(
      ([key, settings]) => key.startsWith(`${company} `) && settings.enabled,
    );
  }

  private addChange(change: Omit<Change, 'id' | 'at' | 'count'>) {
    const folded = this.changes.find(
      (c) => c.company === change.company && c.foldKey === change.foldKey,
    );
    if (folded) {
      folded.count += 1;
      folded.op = folded.op === change.op ? folded.op : 'mixed';
      folded.recordId = change.recordId;
      folded.summary = change.summary;
      return;
    }
    this.changes.push({ ...change, id: ++this.changeSeq, at: this.now(), count: 1 });
  }

  /** Mirrors almailbooks.records_change_event: a change of a record, as stored. */
  private recordChange(
    company: string,
    user: string,
    tbl: string,
    id: string,
    before: Record<string, unknown> | null,
    after: Record<string, unknown> | null,
  ) {
    if (!this.feedOn(company) || tbl === 'activities') return;
    if (before && after && sameData(before, after)) return;
    const data = (after ?? before)!;
    const lookup = this.lookup(company);
    const isPrivate =
      isPrivateRecord(tbl, data, lookup) ||
      Boolean(before && after && isPrivateRecord(tbl, before, lookup));
    let kind: string = changeKind(tbl, data);
    if (tbl === 'payments' && kind === 'payment' && before?.method === 'cheque') kind = 'cheque';
    const contact =
      typeof data.clientId === 'string' && data.clientId
        ? this.record(company, 'clients', data.clientId)
        : null;
    const details = changeDetails(tbl, before, after, isPrivate, contact);
    if (!details) return;
    const type = tbl === 'documents' ? String(data.type ?? '') : '';
    this.addChange({
      company,
      actor: user,
      op: !before ? 'insert' : !after ? 'delete' : 'update',
      tbl,
      recordId: id,
      kind,
      important: details.important,
      private: isPrivate,
      foldKey: details.important
        ? `one:${this.changeSeq + 1}`
        : ['tx', this.pushTx, user, tbl, type, kind, isPrivate].join(':'),
      summary: details.summary,
    });
  }

  /** Mirrors almailbooks.company_members_audit, once the feed exists. */
  private recordTeamChange(
    company: string,
    user: string,
    target: string,
    reason: string,
    role: MemberRole | null,
    before: MemberRole | null,
  ) {
    if (!this.features.includes('change_feed')) return;
    this.addChange({
      company,
      actor: user,
      op: reason === 'left' ? 'delete' : 'update',
      tbl: 'company_members',
      recordId: target,
      kind: 'member',
      important: true,
      private: false,
      foldKey: `member:${this.changeSeq + 1}`,
      summary: Object.fromEntries(
        Object.entries({ reason, user: target, role, before }).filter(([, v]) => v !== null),
      ),
    });
  }

  /** The changes `user` is shown, newest first (notification_feed). */
  private visibleChanges(company: string, user: string): Change[] {
    const role = this.role(company, user);
    return this.changes
      .filter((c) => c.company === company && seesChange(c, { userId: user, role }))
      .sort((a, b) => b.id - a.id);
  }

  client(user: string): CloudApi {
    const guard = (method: string) => {
      this.calls.push(`${user} ${method}`);
      if (this.offline) throw fail('offline');
      const queued = this.failures.get(method);
      if (queued?.length) throw queued.shift()!;
    };
    const member = (company: string) => {
      const role = this.role(company, user);
      if (!role) throw fail('not_member');
      return role;
    };

    return {
      createCompany: async (id, name) => {
        guard('createCompany');
        const existing = this.companies.get(id);
        if (existing) {
          const role = this.role(id, user);
          if (this.legacy) {
            if (role !== 'owner') throw fail('company_taken');
          } else {
            if (!role) throw fail('company_taken');
            // Only an empty one of the person's own is taken up again.
            if (role !== 'owner' || this.rows(id).length > 0) throw fail('company_exists');
          }
          existing.name = name;
          return;
        }
        this.companies.set(id, {
          id,
          name,
          purgedUntilRev: 0,
          createdAt: new Date().toISOString(),
        });
        this.addMember(id, user, 'owner');
      },

      myCompanies: async (): Promise<CloudCompany[]> => {
        guard('myCompanies');
        return [...this.companies.values()]
          .filter((c) => this.role(c.id, user))
          .map((c) => ({
            id: c.id,
            name: c.name,
            role: this.role(c.id, user)!,
            createdAt: c.createdAt,
            members: this.members.get(c.id)?.size ?? 0,
          }));
      },

      pushRecords: async (company, changes: PushChange[]): Promise<PushResult[]> => {
        guard('pushRecords');
        const role = member(company);
        // All or nothing, like one database transaction.
        const records = new Map(this.records);
        const markers = new Map(this.markers);
        const rev = this.rev;
        const feed = structuredClone(this.changes);
        const changeSeq = this.changeSeq;
        this.pushTx = ++this.pushSeq;
        try {
          const results = changes.map((change) => this.applyChange(company, user, role, change));
          if (results.length) this.notify(company);
          return results;
        } catch (error) {
          this.records = records;
          this.markers = markers;
          this.rev = rev;
          this.changes = feed;
          this.changeSeq = changeSeq;
          throw error;
        }
      },

      pullRecords: async (company, since, limit): Promise<PulledRow[]> => {
        guard('pullRecords');
        member(company);
        const rows: PulledRow[] = [];
        for (const row of this.records.values()) {
          if (
            row.company === company &&
            row.rev > since &&
            this.canRead(company, user, row.tbl, row.data)
          ) {
            rows.push({
              tbl: row.tbl,
              id: row.id,
              data: structuredClone(row.data),
              rev: row.rev,
              deleted: false,
            });
          }
        }
        const role = this.role(company, user)!;
        for (const marker of this.markers.values()) {
          if (marker.company !== company || marker.rev <= since) continue;
          if (marker.private && !(role === 'owner' || role === 'admin' || role === 'accountant'))
            continue;
          rows.push({ tbl: marker.tbl, id: marker.id, data: null, rev: marker.rev, deleted: true });
        }
        rows.sort((a, b) => a.rev - b.rev);
        const purged = this.companies.get(company)?.purgedUntilRev ?? 0;
        if (since > 0 && since < purged) throw fail('resync');
        return rows.slice(0, limit);
      },

      readRecords: async (company, since, limit): Promise<PulledRow[]> => {
        guard('readRecords');
        member(company);
        const rows: PulledRow[] = [];
        for (const row of this.records.values()) {
          if (
            row.company === company &&
            row.rev > since &&
            this.canRead(company, user, row.tbl, row.data)
          ) {
            rows.push({
              tbl: row.tbl,
              id: row.id,
              data: structuredClone(row.data),
              rev: row.rev,
              deleted: false,
            });
          }
        }
        rows.sort((a, b) => a.rev - b.rev);
        return rows.slice(0, limit);
      },

      recordIds: async (company, after: RecordKey | null, limit, tbl): Promise<RecordKey[]> => {
        guard('recordIds');
        member(company);
        const keys = [...this.records.values()]
          .filter((r) => r.company === company && (!tbl || r.tbl === tbl))
          .filter((r) => this.canRead(company, user, r.tbl, r.data))
          .map((r) => ({ tbl: r.tbl, id: r.id }))
          .sort((a, b) => (a.tbl === b.tbl ? (a.id < b.id ? -1 : 1) : a.tbl < b.tbl ? -1 : 1));
        const start = after
          ? keys.findIndex((k) => k.tbl > after.tbl || (k.tbl === after.tbl && k.id > after.id))
          : 0;
        return start < 0 ? [] : keys.slice(start, start + limit);
      },

      syncInfo: async (company) => {
        guard('syncInfo');
        member(company);
        const visible = [...this.records.values()].filter(
          (r) => r.company === company && this.canRead(company, user, r.tbl, r.data),
        );
        return {
          purgedUntilRev: this.companies.get(company)?.purgedUntilRev ?? 0,
          recordCount: visible.length,
          maxRev: Math.max(0, ...visible.map((r) => r.rev)),
        };
      },

      getRecord: async (company, tbl, id) => {
        guard('getRecord');
        member(company);
        const row = this.records.get(this.key(company, tbl, id));
        if (!row || !this.canRead(company, user, row.tbl, row.data)) return null;
        return { data: structuredClone(row.data), rev: row.rev };
      },

      uploadFile: async (path, data) => {
        guard('uploadFile');
        const [company] = path.split('/');
        member(company);
        if (!this.canUseFile(user, path, true)) throw fail('permission');
        // The owner is deleting the company: no new uploads.
        if ((this.companies.get(company)?.deletingUntil ?? 0) > Date.now()) {
          throw fail('permission');
        }
        this.files.set(path, { blob: data, createdAt: new Date().toISOString(), owner: user });
      },

      downloadFile: async (path) => {
        guard('downloadFile');
        const file = this.files.get(path);
        if (!file || !this.canUseFile(user, path, false)) throw fail('invalid', 'Object not found');
        return file.blob;
      },

      // Like Storage: what the rules hide is skipped without an error; the
      // answer lists what was removed.
      removeFiles: async (paths) => {
        guard('removeFiles');
        if (this.storageDown) throw fail('server');
        const removed: string[] = [];
        for (const path of paths) {
          if (
            this.files.has(path) &&
            this.canUseFile(user, path, false) &&
            this.canUseFile(user, path, true)
          ) {
            this.files.delete(path);
            removed.push(path);
          }
        }
        return removed;
      },

      listFiles: async (company): Promise<StoredFile[]> => {
        guard('listFiles');
        member(company);
        return [...this.files.entries()]
          .filter(([path]) => path.startsWith(`${company}/`) && this.canUseFile(user, path, false))
          .map(([path, file]) => ({ path, createdAt: file.createdAt }));
      },

      storedFiles: async (company, paths) => {
        guard('storedFiles');
        if (this.legacy) return null;
        member(company);
        return paths.filter((path) => path.startsWith(`${company}/`) && this.files.has(path));
      },

      // Mirrors public.patch_company.
      patchCompany: async (company, ops: CompanyOp[]) => {
        guard('patchCompany');
        if (this.legacy) return null;
        const role = member(company);
        const key = this.key(company, 'companies', company);
        const old = this.records.get(key);
        if (!old) return null;
        if (ops.some((change) => change.path[0] === 'id')) throw fail('invalid');
        if (!this.canWrite(company, user, 'companies', old.data)) throw fail('permission');
        const { data, conflicts } = rebaseCompany(old.data, ops);
        if (role === 'staff' && !staffCompanyChangeOk(old.data, data)) throw fail('permission');
        const kept = this.guard(company, user, role, 'companies', old.data, data);
        if (sameData(kept, old.data)) return { rev: old.rev, conflicts };
        const rev = ++this.rev;
        this.records.set(key, { ...old, data: kept, rev });
        this.pushTx = ++this.pushSeq;
        this.recordChange(company, user, 'companies', company, old.data, kept);
        this.notify(company);
        return { rev, conflicts };
      },

      // Mirrors public.reserve_number.
      reserveNumber: async (company, kind, date, min) => {
        guard('reserveNumber');
        if (this.legacy) return null;
        member(company);
        const key = this.key(company, 'companies', company);
        const row = this.records.get(key);
        if (!row) return null;
        if (!this.canWrite(company, user, 'companies', row.data)) throw fail('permission');
        const numbering = (row.data.numbering ?? {}) as Record<string, Record<string, unknown>>;
        const rule = numbering[kind];
        if (!rule) return null;
        const reset = (rule.reset ?? 'never') as CounterReset;
        const period = periodKey(reset, date);
        const rulePeriod = String(rule.period ?? '');
        let counter = typeof rule.next === 'number' ? Math.max(1, Math.trunc(rule.next)) : 1;
        if (reset !== 'never' && rulePeriod !== '' && period !== rulePeriod) {
          if (period < rulePeriod) return null;
          counter = 1;
        }
        counter = Math.max(counter, min, 1);
        const data = {
          ...row.data,
          numbering: { ...numbering, [kind]: { ...rule, next: counter + 1, period } },
        };
        const rev = ++this.rev;
        this.records.set(key, { ...row, data, rev });
        this.notify(company);
        return { counter, period };
      },

      serverFeatures: async (company) => {
        guard('serverFeatures');
        member(company);
        return this.legacy ? [] : [...this.features];
      },

      beginDeleteCompany: async (company) => {
        guard('beginDeleteCompany');
        if (this.legacy) return false;
        if (member(company) !== 'owner') throw fail('permission');
        this.companies.get(company)!.deletingUntil = Date.now() + 60 * 60 * 1000;
        return true;
      },

      stockIssueRecipients: async (company) => {
        guard('stockIssueRecipients');
        const role = member(company);
        // As public.stock_issue_recipients, once the server has the file.
        if (!this.features.includes('stock_issues')) throw fail('server_outdated');
        const keeps = [...this.records.values()].some(
          (r) =>
            r.company === company &&
            r.tbl === 'warehouses' &&
            Boolean(r.data.parentId) &&
            issuesFromWarehouse(role, user, r.data),
        );
        if (!managesWarehouses(role) && !keeps) throw fail('permission');
        return [...this.records.values()]
          .filter((r) => r.company === company && r.tbl === 'employees' && r.data.status !== 'left')
          .map((r) => ({
            id: String(r.data.id ?? ''),
            number: String(r.data.number ?? ''),
            name: String(r.data.name ?? ''),
            nameAr: String(r.data.nameAr ?? ''),
            jobTitle: String(r.data.jobTitle ?? ''),
            jobTitleAr: String(r.data.jobTitleAr ?? ''),
            department: String(r.data.department ?? ''),
          }))
          .sort((a, b) => a.name.localeCompare(b.name));
      },

      companyTeam: async (company): Promise<TeamMember[]> => {
        guard('companyTeam');
        member(company);
        return [...(this.members.get(company) ?? new Map<string, MemberRole>()).entries()].map(
          ([userId, role]) => ({
            userId,
            fullName: userId,
            email: `${userId}@example.com`,
            role,
            joinedAt: '',
          }),
        );
      },

      createInvite: async (company, email, role): Promise<Invite> => {
        guard('createInvite');
        const mine = member(company);
        if (mine !== 'owner' && mine !== 'admin') throw fail('permission');
        if (role === 'owner') throw fail('invalid');
        if (!grantableRoles(mine, this.ownerOnly(company)).includes(role)) {
          throw fail('permission');
        }
        return {
          id: `invite-${email}`,
          email,
          role,
          token: 'f'.repeat(64),
          createdAt: '',
          expiresAt: '',
          invitedByName: user,
        };
      },
      listInvites: async () => {
        guard('listInvites');
        return [];
      },
      revokeInvite: async () => {
        guard('revokeInvite');
      },
      inviteDetails: async () => {
        guard('inviteDetails');
        return null;
      },
      acceptInvite: async () => {
        guard('acceptInvite');
        throw fail('invite_invalid');
      },
      // Mirror public.set_member_role and remove_member (with the owner's switch).
      setMemberRole: async (company, target, role) => {
        guard('setMemberRole');
        const mine = member(company);
        const current = this.role(company, target);
        if (role === 'owner' || !current) throw fail('invalid');
        const ownerOnly = this.ownerOnly(company);
        if (
          !canChangeMember(mine, current, ownerOnly) ||
          !grantableRoles(mine, ownerOnly).includes(role)
        ) {
          throw fail('permission');
        }
        this.addMember(company, target, role);
        if (role !== current) this.recordTeamChange(company, user, target, 'role', role, current);
      },
      removeMember: async (company, target) => {
        guard('removeMember');
        const mine = member(company);
        const current = this.role(company, target);
        if (!current) return;
        if (current === 'owner') throw fail('permission');
        if (target !== user && !canChangeMember(mine, current, this.ownerOnly(company))) {
          throw fail('permission');
        }
        this.members.get(company)?.delete(target);
        this.access.delete(`${company} ${target}`);
        this.changeSettings.delete(`${company} ${target}`);
        this.changeReads.delete(`${company} ${target}`);
        this.recordTeamChange(company, user, target, 'left', null, current);
      },
      transferOwnership: async (company, target) => {
        guard('transferOwnership');
        if (member(company) !== 'owner') throw fail('permission');
        if (!this.role(company, target) || target === user) throw fail('invalid');
        const before = this.role(company, target);
        this.addMember(company, user, 'admin');
        this.addMember(company, target, 'owner');
        this.recordTeamChange(company, user, user, 'role', 'admin', 'owner');
        this.recordTeamChange(company, user, target, 'ownership', 'owner', before);
        this.stopChangesOfNonApprovers(company);
      },

      // Mirror the Super Admin's functions (20261116000000_super_admin_approvals.sql).
      myPermissions: async (company) => {
        guard('myPermissions');
        if (this.legacy || !this.features.includes('super_admin')) return null;
        const role = member(company);
        const access = this.access.get(`${company} ${user}`);
        return {
          permissions: role === 'owner' ? {} : readPermissions(access?.permissions),
          approver: isApprover(role, access?.canApprove),
          owner: role === 'owner',
          seniorRolesOwnerOnly: this.ownerOnly(company),
        };
      },
      teamPermissions: async (company): Promise<MemberAccess[] | null> => {
        guard('teamPermissions');
        if (this.legacy || !this.features.includes('super_admin')) return null;
        const mine = member(company);
        return [...(this.members.get(company) ?? new Map<string, MemberRole>()).entries()]
          .filter(([id]) => mine === 'owner' || mine === 'admin' || id === user)
          .map(([id, role]) => {
            const access = this.access.get(`${company} ${id}`);
            return {
              userId: id,
              permissions: readPermissions(access?.permissions),
              canApprove: isApprover(role, access?.canApprove) && role !== 'owner',
            };
          });
      },
      setMemberPermissions: async (company, target, permissions, canApprove) => {
        guard('setMemberPermissions');
        if (member(company) !== 'owner') throw fail('permission');
        const role = this.role(company, target);
        if (!role) throw fail('invalid');
        if (role === 'owner') throw fail('permission');
        if (canApprove && role !== 'admin' && role !== 'accountant') throw fail('invalid');
        const others = [...(this.members.get(company) ?? new Map<string, MemberRole>())].filter(
          ([id, r]) =>
            id !== target && isApprover(r, this.access.get(`${company} ${id}`)?.canApprove),
        );
        if (canApprove && others.filter(([, r]) => r !== 'owner').length >= MAX_APPROVERS) {
          throw fail('limit');
        }
        this.setAccess(company, target, readPermissions(permissions), canApprove);
        this.recordTeamChange(company, user, target, 'permissions', role, null);
        this.stopChangesOfNonApprovers(company);
      },
      setTeamRules: async (company, rules) => {
        guard('setTeamRules');
        if (member(company) !== 'owner') throw fail('permission');
        if (rules.seniorRolesOwnerOnly) this.seniorRolesOwnerOnly.add(company);
        else this.seniorRolesOwnerOnly.delete(company);
      },
      ownedCompanies: async () => {
        guard('ownedCompanies');
        if (this.legacy || !this.features.includes('super_admin')) return null;
        return [...this.companies.values()]
          .filter((c) => this.role(c.id, user) === 'owner')
          .map((c) => ({
            id: c.id,
            name: c.name,
            members: this.members.get(c.id)?.size ?? 0,
            pendingApprovals: this.rows(c.id, 'approvals').filter(
              (r) => r.data.status === 'pending',
            ).length,
          }));
      },
      deleteCompany: async (company) => {
        guard('deleteCompany');
        if (member(company) !== 'owner') throw fail('permission');
        this.companies.delete(company);
        this.members.delete(company);
        for (const [key, row] of this.records)
          if (row.company === company) this.records.delete(key);
        for (const [key, marker] of this.markers)
          if (marker.company === company) this.markers.delete(key);
      },
      watch: (company, onChange) => {
        let set = this.watchers.get(company);
        if (!set) this.watchers.set(company, (set = new Set()));
        set.add(onChange);
        return () => set.delete(onChange);
      },

      // Mirror public.email_alert_settings and public.set_email_alerts.
      emailAlerts: async (company) => {
        guard('emailAlerts');
        if (this.legacy) return null;
        member(company);
        const saved = this.emailAlerts.get(`${company} ${user}`);
        return {
          enabled: saved?.enabled ?? false,
          topics: saved?.topics ?? ['documents', 'deadlines', 'cheques', 'bills', 'invoices'],
          lastSentAt: saved?.lastSentAt ?? null,
          lastError: saved?.lastError ?? '',
          lastErrorAt: saved?.lastErrorAt ?? null,
          functionReady: true,
        };
      },
      setEmailAlerts: async (company, settings) => {
        guard('setEmailAlerts');
        if (this.legacy) return null;
        const role = member(company);
        // Accountants too once the server has 20261130000000_people_alerts.sql (#18).
        if (!getsEmailAlerts(role, this.features.includes('document_alerts'))) {
          throw fail('permission');
        }
        if (settings.enabled && !settings.topics.length) throw fail('invalid');
        const key = `${company} ${user}`;
        const before = this.emailAlerts.get(key);
        this.emailAlerts.set(key, {
          enabled: settings.enabled,
          topics: [...settings.topics],
          appUrl: settings.appUrl || before?.appUrl || '',
          lastSentAt: before?.lastSentAt ?? null,
          lastError: settings.enabled ? (before?.lastError ?? '') : '',
          lastErrorAt: settings.enabled ? (before?.lastErrorAt ?? null) : null,
          functionReady: true,
        });
        const { appUrl: _appUrl, ...saved } = this.emailAlerts.get(key)!;
        return saved;
      },
      // Mirror public.email_alert_scope and public.set_email_alert_scope (#18).
      emailAlertScope: async (company) => {
        guard('emailAlertScope');
        if (this.legacy || !this.features.includes('document_alerts')) return undefined;
        member(company);
        return this.alertScopes.get(`${company} ${user}`) ?? null;
      },
      setEmailAlertScope: async (company, kinds) => {
        guard('setEmailAlertScope');
        if (this.legacy || !this.features.includes('document_alerts')) return false;
        const role = member(company);
        if (!getsEmailAlerts(role, true)) throw fail('permission');
        if (kinds && kinds.some((k) => !isDocumentAlertKind(k))) throw fail('invalid');
        if (kinds && !kinds.length) throw fail('invalid');
        const chosen = kinds ? DOCUMENT_ALERT_KINDS.filter((k) => kinds.includes(k)) : null;
        this.alertScopes.set(
          `${company} ${user}`,
          chosen && chosen.length < DOCUMENT_ALERT_KINDS.length ? chosen : null,
        );
        return true;
      },
      sendAlertEmail: async (company) => {
        guard('sendAlertEmail');
        const role = member(company);
        if (!getsEmailAlerts(role, this.features.includes('document_alerts'))) {
          throw new AlertEmailError('permission');
        }
        const saved = this.emailAlerts.get(`${company} ${user}`);
        if (!saved?.enabled) throw new AlertEmailError('not_enabled');
        this.alertEmails.push(`${company} ${user}`);
        saved.lastSentAt = new Date().toISOString();
        return { to: `${user}@example.com`, count: 0 };
      },

      // Mirror the change feed's functions (20261123000000_change_feed.sql).
      changeFeedStatus: async (company) => {
        guard('changeFeedStatus');
        if (this.legacy || !this.features.includes('change_feed')) return null;
        member(company);
        if (!this.approver(company, user)) return { enabled: false, unread: 0, latest: 0 };
        const key = `${company} ${user}`;
        const visible = this.visibleChanges(company, user);
        const read = this.changeReads.get(key) ?? 0;
        return {
          enabled: Boolean(this.changeSettings.get(key)?.enabled),
          unread: Math.min(100, visible.filter((c) => c.id > read).length),
          latest: visible[0]?.id ?? 0,
        };
      },
      changeFeed: async (company, page = {}): Promise<ChangeEvent[] | null> => {
        guard('changeFeed');
        if (this.legacy || !this.features.includes('change_feed')) return null;
        member(company);
        if (!this.approver(company, user)) throw fail('permission');
        const read = this.changeReads.get(`${company} ${user}`) ?? 0;
        const limit = Math.min(Math.max(page.limit ?? 50, 1), 200);
        return this.visibleChanges(company, user)
          .filter((c) => c.id > (page.after ?? 0) && (page.before == null || c.id < page.before))
          .slice(0, limit)
          .map((c) => ({
            id: c.id,
            at: c.at,
            actor: c.actor,
            actorName: c.actor ?? '',
            subjectName: c.kind === 'member' ? String(c.summary.user ?? '') : '',
            kind: c.kind,
            op: c.op,
            tbl: c.tbl,
            recordId: c.recordId,
            count: c.count,
            important: c.important,
            private: c.private,
            summary: structuredClone(c.summary),
            unread: c.id > read,
          }));
      },
      markChangesRead: async (company, upto) => {
        guard('markChangesRead');
        member(company);
        if (!this.approver(company, user)) throw fail('permission');
        const key = `${company} ${user}`;
        const newest = Math.max(
          0,
          ...this.changes.filter((c) => c.company === company).map((c) => c.id),
        );
        this.changeReads.set(
          key,
          Math.max(this.changeReads.get(key) ?? 0, Math.min(Math.max(upto, 0), newest)),
        );
      },
      changeNotifications: async (company) => {
        guard('changeNotifications');
        if (this.legacy || !this.features.includes('change_feed')) return null;
        member(company);
        if (!this.approver(company, user)) throw fail('permission');
        return this.changeSettingsOf(company, user);
      },
      setChangeNotifications: async (company, settings) => {
        guard('setChangeNotifications');
        if (this.legacy || !this.features.includes('change_feed')) return null;
        member(company);
        if (!this.approver(company, user)) throw fail('permission');
        if (!settings.immediateKinds.every(isImmediateKind)) throw fail('invalid');
        if (settings.digest !== 'daily' && settings.digest !== 'off') throw fail('invalid');
        const key = `${company} ${user}`;
        const before = this.changeSettings.get(key);
        const newest = Math.max(
          0,
          ...this.changes.filter((c) => c.company === company).map((c) => c.id),
        );
        const turnedOn = settings.enabled && !before?.enabled;
        this.changeSettings.set(key, {
          enabled: settings.enabled,
          immediateKinds: IMMEDIATE_KINDS.filter((k) => settings.immediateKinds.includes(k)),
          digest: settings.digest,
          appUrl: settings.appUrl || before?.appUrl || '',
          lastSentAt: before?.lastSentAt ?? null,
          lastError: settings.enabled ? (before?.lastError ?? '') : '',
          lastErrorAt: settings.enabled ? (before?.lastErrorAt ?? null) : null,
          emailedUpto: turnedOn ? newest : (before?.emailedUpto ?? newest),
        });
        if (turnedOn) this.changeReads.set(key, Math.max(this.changeReads.get(key) ?? 0, newest));
        return this.changeSettingsOf(company, user);
      },
    };
  }

  private changeSettingsOf(company: string, user: string): ChangeNotificationSettings {
    const saved = this.changeSettings.get(`${company} ${user}`);
    return {
      enabled: saved?.enabled ?? false,
      immediateKinds: saved?.immediateKinds ?? [...IMMEDIATE_KINDS],
      digest: saved?.digest ?? 'daily',
      lastSentAt: saved?.lastSentAt ?? null,
      lastError: saved?.lastError ?? '',
      lastErrorAt: saved?.lastErrorAt ?? null,
      functionReady: true,
    };
  }

  /** Mirrors almailbooks.notification_member_changed: only approvers keep getting the changes. */
  private stopChangesOfNonApprovers(company: string) {
    for (const [key, settings] of this.changeSettings) {
      const [id, user] = key.split(' ');
      if (id !== company || !settings.enabled) continue;
      if (!getsChangeFeed(this.role(company, user), this.access.get(key)?.canApprove)) {
        settings.enabled = false;
      }
    }
  }

  /** Mirrors almailbooks.records_guard: what is stored, or the refusal. */
  private guard(
    company: string,
    user: string,
    role: MemberRole,
    tbl: string,
    old: Record<string, unknown> | undefined,
    data: Record<string, unknown>,
  ): Record<string, unknown> {
    // Employee letters (#19), once the server has 20261130000000_people_alerts.sql.
    if (this.features.includes('employee_letters')) {
      if (tbl === 'peopleSettings') return keepLettersSwitch(role, old, data);
      if (tbl === 'employeeLetters' && this.lettersOn(company)) {
        if (letterWriteRefusal(old, data, true) === 'issued') throw fail('invalid');
        // An issued letter stays as it was issued, a void one void.
        const kept = keepIssuedLetter(old, data);
        const refusal = letterWriteRefusal(old, kept, this.issuesLetters(company, user, role));
        if (refusal === 'issuer') throw fail('permission');
        return kept;
      }
    }
    // Sub-warehouses and items issued, once the server has
    // 20261210000000_warehouse_issues.sql.
    if (this.features.includes('stock_issues')) {
      const refusal = warehouseWriteRefusal(
        { role, userId: user, approver: this.approver(company, user) },
        tbl,
        old,
        data,
        (id) => this.record(company, 'warehouses', id),
      );
      if (refusal) throw fail('permission');
      if (tbl === 'approvals' && !old && data.kind === 'stock_issue') {
        // Asked for by whoever sends it, as the one who issued the items:
        // named as the warehouse's keeper when it is theirs.
        const asked = data.after as Record<string, unknown> | null;
        const named = issuerName(
          user,
          this.record(company, 'warehouses', String(asked?.warehouseId ?? '')),
        );
        const { requestedByName: _name, ...request } = data;
        data = named ? { ...request, requestedByName: named } : request;
        if (asked && typeof asked === 'object') {
          const { issuedByName: _issuer, ...issue } = asked;
          data = {
            ...data,
            after: { ...issue, issuedBy: user, ...(named ? { issuedByName: named } : {}) },
          };
        }
      }
    }
    if (tbl === 'companies' && this.features.includes('super_admin')) {
      // The books' settings, for a member the owner made Maham Books view only for.
      const books = appLimit(role, this.permissionsOf(company, user), 'books');
      if ((books === 'view' || books === 'none') && companyBooksChanged(old, data)) {
        throw fail('permission');
      }
    }
    // The AI assistant's switch, once the server has
    // 20261208000000_ai_assistant.sql: kept as stored for anyone but the
    // owner or an admin.
    if (tbl === 'companies' && this.features.includes('ai_assistant')) {
      data = keepAiSwitch(role, old, data);
    }
    if (!this.features.includes('approvals')) return data;
    if (tbl === 'companies') {
      if (role !== 'owner' && approvalRulesChanged(old, data)) throw fail('permission');
      return data;
    }
    if (tbl === 'payments' || tbl === 'securityCheques') {
      const rules = this.chequeRules(company);
      if (
        rules &&
        !this.approver(company, user) &&
        chequeChangeNeedsApprover(rules, tbl, old, data)
      ) {
        throw fail('approval_required');
      }
      return data;
    }
    if (tbl !== 'documents' && tbl !== 'approvals') return data;
    const approver = this.approver(company, user);
    if (tbl === 'approvals') {
      // Salary approval (#10), once the server has 20261130000000_people_alerts.sql.
      const payroll = {
        on:
          this.features.includes('payroll_approvals') &&
          rulesCoverPayroll(this.approvalRules(company)),
        poster: canPostPayroll(role, this.permissionsOf(company, user)),
      };
      // Whether or not the rules are on.
      const write = guardApprovalWrite(
        old,
        data,
        {
          userId: user,
          approver,
          owner: role === 'owner',
          now: this.now(),
        },
        payroll,
      );
      if ('refused' in write) throw fail(write.refused);
      if (payroll.on && isPayrollApproval(old ?? data)) {
        const subject = (old ?? data).subjectId;
        const refusal = payrollDecisionRefusal(
          old,
          data,
          {
            userId: user,
            owner: role === 'owner',
            peopleShut: appLimit(role, this.permissionsOf(company, user), 'people') === 'none',
          },
          typeof subject === 'string' ? this.record(company, 'payRuns', subject) : undefined,
        );
        if (refusal === 'self' || refusal === 'people') throw fail('permission');
        if (refusal === 'stale') throw fail('invalid');
      }
      return write.data;
    }
    const companyData = this.records.get(this.key(company, 'companies', company))?.data;
    if (issuesWithoutNumber(companyData, old, data)) throw fail('invalid');
    const rules = this.approvalRules(company);
    if (rules && old && !approver && documentChangeNeedsApproval(rules, old, data)) {
      throw fail('approval_required');
    }
    // Anyone else's copy keeps the stored payment link (records_guard).
    return rules && old && !approver ? keepPaymentLink(rules, old, data) : data;
  }

  /** Whether the company's letters are on (almailbooks.letters_on). */
  private lettersOn(company: string): boolean {
    return lettersSwitchedOn(this.record(company, 'peopleSettings', company));
  }

  /** The owner, an admin or an approver (almailbooks.issues_letters). */
  private issuesLetters(company: string, user: string, role: MemberRole): boolean {
    return role === 'owner' || role === 'admin' || this.approver(company, user);
  }

  private applyChange(
    company: string,
    user: string,
    role: MemberRole,
    change: PushChange,
  ): PushResult {
    const key = this.key(company, change.tbl, change.id);
    const old = this.records.get(key);
    const visibleOld = old && this.canRead(company, user, old.tbl, old.data) ? old : undefined;
    const marker = this.markers.get(key);
    const base = change.base_rev ?? 0;
    if (change.deleted) {
      // Never stored, or hidden from this person: nothing to do.
      if (!visibleOld)
        return { tbl: change.tbl, id: change.id, rev: marker?.rev ?? null, conflict: false };
      if (
        change.tbl === 'companies' ||
        !this.canWrite(company, user, change.tbl, visibleOld.data) ||
        // As can_delete_record: what the approval rules keep.
        (this.features.includes('approvals') &&
          deleteKeptBy(
            this.approvalRules(company),
            change.tbl,
            visibleOld.data,
            this.approver(company, user),
          ) !== null) ||
        (!this.approver(company, user) &&
          chequeChangeNeedsApprover(
            this.chequeRules(company),
            change.tbl,
            visibleOld.data,
            undefined,
          )) ||
        // An issued letter stays, so its number stays used (#19).
        (this.features.includes('employee_letters') &&
          change.tbl === 'employeeLetters' &&
          this.lettersOn(company) &&
          letterKept(visibleOld.data)) ||
        // The letters switch, deleted by the owner or an admin only.
        (this.features.includes('employee_letters') &&
          change.tbl === 'peopleSettings' &&
          peopleSettingsKept(role, visibleOld.data)) ||
        // Items issued are never deleted; a sub-warehouse and its stock
        // entries only by those who manage warehouses.
        (this.features.includes('stock_issues') &&
          (change.tbl === 'stockIssues' ||
            // The movements of items issued, while the issue stands.
            (change.tbl === 'stockMovements' &&
              visibleOld.data.sourceType === 'issue' &&
              this.record(company, 'stockIssues', String(visibleOld.data.sourceId ?? ''))
                ?.status === 'posted') ||
            (!managesWarehouses(role) &&
              ((change.tbl === 'warehouses' && warehouseRuled(visibleOld.data)) ||
                (change.tbl === 'stockEntries' &&
                  entryInSubWarehouse(visibleOld.data, (id) =>
                    this.record(company, 'warehouses', id),
                  )) ||
                (change.tbl === 'documents' &&
                  subWarehouseLines(visibleOld.data, (id) =>
                    this.record(company, 'warehouses', id),
                  ) !== '[]')))))
      ) {
        throw fail('permission');
      }
      const isPrivate = isPrivateRecord(change.tbl, visibleOld.data, this.lookup(company));
      this.recordChange(company, user, change.tbl, change.id, visibleOld.data, null);
      this.records.delete(key);
      const rev = ++this.rev;
      this.markers.set(key, {
        company,
        tbl: change.tbl,
        id: change.id,
        rev,
        deletedAt: Date.now(),
        private: isPrivate,
      });
      return { tbl: change.tbl, id: change.id, rev, conflict: visibleOld.rev > base };
    }
    let data = structuredClone(change.data ?? {});
    if (JSON.stringify(data).length > 1_048_576) throw fail('too_large');
    if (
      data.id !== change.id ||
      (change.tbl === 'companies' ? change.id !== company : data.companyId !== company)
    ) {
      throw fail('invalid');
    }
    if (old && !visibleOld) throw fail('permission');
    if (old && !this.canWrite(company, user, change.tbl, old.data)) throw fail('permission');
    if (!this.canWrite(company, user, change.tbl, data)) throw fail('permission');
    // A kind of record the server doesn't take before
    // 20261207000000_staffing_costings.sql (records_tbl_check).
    if (change.tbl === 'staffingCostings' && !this.features.includes('staffing_costings')) {
      throw fail('invalid');
    }
    // Nor items issued before 20261210000000_warehouse_issues.sql.
    if (change.tbl === 'stockIssues' && !this.features.includes('stock_issues')) {
      throw fail('invalid');
    }
    if (change.tbl === 'companies' && role === 'staff') {
      if (!old || !staffCompanyChangeOk(old.data, data)) throw fail('permission');
    }
    data = this.guard(company, user, role, change.tbl, old?.data, data);
    if (change.tbl === 'companies' && old) {
      const numbering = mergeNumbering(
        old.data.numbering as Record<string, never>,
        data.numbering as Record<string, never>,
      );
      if (numbering) data = { ...data, numbering };
    }
    const rev = ++this.rev;
    this.records.set(key, { company, tbl: change.tbl, id: change.id, data, rev });
    this.markers.delete(key);
    this.recordChange(company, user, change.tbl, change.id, old?.data ?? null, data);
    const conflict =
      (old !== undefined && old.rev > base && !sameData(old.data, change.data)) ||
      (old === undefined && marker !== undefined && marker.rev > base);
    return { tbl: change.tbl, id: change.id, rev, conflict };
  }
}
