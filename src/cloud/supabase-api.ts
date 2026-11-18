import type { SupabaseClient } from '@supabase/supabase-js';
import { ALERT_TOPICS, isAlertTopic } from '@/alerts/topics';
import { isDocumentAlertKind } from '@/lib/compliance';
import { isMemberRole, readPermissions, type MemberRole } from './roles';
import { IMMEDIATE_KINDS, isImmediateKind } from './change-feed';
import { FILES_BUCKET } from './config';
import {
  AlertEmailError,
  cloudError,
  isAlertEmailErrorCode,
  storageCloudError,
  type ChangeEvent,
  type ChangeNotificationSettings,
  type CloudApi,
  type EmailAlertSettings,
  type CloudCompany,
  type Invite,
  type InviteDetails,
  type MemberAccess,
  type OwnedCompany,
  type PulledRow,
  type PushResult,
  type RecordKey,
  type StoredFile,
  type IssueRecipientRow,
  type TeamMember,
} from './api';

/** A database function this server doesn't have (the owner hasn't run the latest migration). */
const MISSING = Symbol('missing');

/** How long a missing function is taken as missing before asking again. */
const RECHECK_MS = 10 * 60 * 1000;

interface EmailAlertRow {
  enabled: boolean | null;
  topics: string[] | null;
  last_sent_at: string | null;
  last_error: string | null;
  last_error_at: string | null;
  function_ready: boolean | null;
}

function emailAlertSettings(row: EmailAlertRow | undefined): EmailAlertSettings {
  return {
    enabled: Boolean(row?.enabled),
    topics: (row?.topics ?? [...ALERT_TOPICS]).filter(isAlertTopic),
    lastSentAt: row?.last_sent_at ?? null,
    lastError: row?.last_error ?? '',
    lastErrorAt: row?.last_error_at ?? null,
    functionReady: Boolean(row?.function_ready),
  };
}

interface ChangeSettingsRow {
  enabled: boolean | null;
  immediate_kinds: string[] | null;
  digest: string | null;
  last_sent_at: string | null;
  last_error: string | null;
  last_error_at: string | null;
  function_ready: boolean | null;
}

function changeSettings(row: ChangeSettingsRow | undefined): ChangeNotificationSettings {
  return {
    enabled: Boolean(row?.enabled),
    immediateKinds: (row?.immediate_kinds ?? [...IMMEDIATE_KINDS]).filter(isImmediateKind),
    digest: row?.digest === 'off' ? 'off' : 'daily',
    lastSentAt: row?.last_sent_at ?? null,
    lastError: row?.last_error ?? '',
    lastErrorAt: row?.last_error_at ?? null,
    functionReady: Boolean(row?.function_ready),
  };
}

interface ChangeRow {
  id: number | string;
  at: string;
  actor: string | null;
  actor_name: string | null;
  subject_name: string | null;
  kind: string;
  op: string;
  tbl: string;
  record_id: string;
  count: number | string;
  important: boolean;
  private: boolean;
  summary: unknown;
  unread: boolean;
}

function changeEvent(row: ChangeRow): ChangeEvent {
  const summary = row.summary;
  return {
    id: Number(row.id),
    at: row.at,
    actor: row.actor ?? null,
    actorName: row.actor_name ?? '',
    subjectName: row.subject_name ?? '',
    kind: String(row.kind ?? ''),
    op: String(row.op ?? ''),
    tbl: String(row.tbl ?? ''),
    recordId: String(row.record_id ?? ''),
    count: Math.max(1, Number(row.count) || 1),
    important: Boolean(row.important),
    private: Boolean(row.private),
    summary:
      summary && typeof summary === 'object' && !Array.isArray(summary)
        ? (summary as Record<string, unknown>)
        : {},
    unread: Boolean(row.unread),
  };
}

/** What went wrong calling the email-alerts function, from its answer. */
async function alertEmailError(error: unknown): Promise<AlertEmailError> {
  const context = (error as { context?: unknown } | null)?.context;
  if (context instanceof Response) {
    // Null when it isn't the function's own answer.
    const body = (await context
      .clone()
      .json()
      .catch(() => null)) as { error?: unknown; message?: unknown } | null;
    if (body && isAlertEmailErrorCode(body.error)) {
      return new AlertEmailError(body.error, typeof body.message === 'string' ? body.message : '');
    }
    // Supabase answers for a function that isn't there.
    if (context.status === 404) return new AlertEmailError('not_deployed');
    return new AlertEmailError('failed', `HTTP ${context.status}`);
  }
  const name = (error as Error | null)?.name;
  if (name === 'FunctionsFetchError') return new AlertEmailError('offline');
  if (name === 'FunctionsRelayError') return new AlertEmailError('not_deployed');
  return new AlertEmailError('failed', (error as Error | null)?.message ?? '');
}

/** The cloud as Supabase: the database's functions, Storage and Realtime. */
export function supabaseApi(supabase: SupabaseClient): CloudApi {
  async function rpc<T>(name: string, args: Record<string, unknown> = {}): Promise<T> {
    const { data, error, status } = await supabase.rpc(name, args);
    if (error)
      throw cloudError({
        ...error,
        status: status || undefined,
        name: status === 0 ? 'TypeError' : '',
      });
    return data as T;
  }
  const missingUntil = new Map<string, number>();
  /**
   * A function added by a later migration: MISSING when the server doesn't
   * have it yet (PostgREST answers PGRST202 or 404), so the caller does what
   * the older server allows.
   */
  async function optionalRpc<T>(
    name: string,
    args: Record<string, unknown>,
  ): Promise<T | typeof MISSING> {
    if ((missingUntil.get(name) ?? 0) > Date.now()) return MISSING;
    const { data, error, status } = await supabase.rpc(name, args);
    if (error) {
      if (error.code === 'PGRST202' || status === 404) {
        missingUntil.set(name, Date.now() + RECHECK_MS);
        return MISSING;
      }
      throw cloudError({
        ...error,
        status: status || undefined,
        name: status === 0 ? 'TypeError' : '',
      });
    }
    // These functions always answer with a body; none means a stand-in that doesn't know them.
    if (status === 204 || data === null || data === undefined) return MISSING;
    return data as T;
  }
  const files = () => supabase.storage.from(FILES_BUCKET);
  const role = (value: unknown): MemberRole => (isMemberRole(value) ? value : 'viewer');

  return {
    async createCompany(id, name) {
      await rpc('create_company', { p_id: id, p_name: name });
    },

    async myCompanies() {
      const rows =
        await rpc<
          { id: string; name: string; role: string; created_at: string; members: number }[]
        >('my_companies');
      return rows.map((r): CloudCompany => ({
        id: r.id,
        name: r.name,
        role: role(r.role),
        createdAt: r.created_at,
        members: Number(r.members),
      }));
    },

    async pushRecords(companyId, changes) {
      const rows = await rpc<PushResult[]>('push_records', {
        p_company: companyId,
        p_changes: changes,
      });
      return rows.map((r) => ({ ...r, rev: r.rev === null ? null : Number(r.rev) }));
    },

    async pullRecords(companyId, since, limit) {
      const rows = await rpc<PulledRow[]>('pull_records', {
        p_company: companyId,
        p_since: since,
        p_limit: limit,
      });
      return rows.map((r) => ({ ...r, rev: Number(r.rev) }));
    },

    async recordIds(companyId, after: RecordKey | null, limit, table) {
      return rpc<RecordKey[]>('company_record_ids', {
        p_company: companyId,
        p_tbl: table ?? null,
        p_after_tbl: after?.tbl ?? '',
        p_after_id: after?.id ?? '',
        p_limit: limit,
      });
    },

    async syncInfo(companyId) {
      const [row] = await rpc<
        { purged_until_rev: number; record_count: number; max_rev: number }[]
      >('company_sync_info', { p_company: companyId });
      return {
        purgedUntilRev: Number(row?.purged_until_rev ?? 0),
        recordCount: Number(row?.record_count ?? 0),
        maxRev: Number(row?.max_rev ?? 0),
      };
    },

    async getRecord(companyId, table, id) {
      const { data, error, status } = await supabase
        .from('records')
        .select('data, rev')
        .eq('company_id', companyId)
        .eq('tbl', table)
        .eq('id', id)
        .maybeSingle();
      if (error) throw cloudError({ ...error, status: status || undefined });
      if (!data) return null;
      const row = data as { data: Record<string, unknown>; rev: number };
      return { data: row.data, rev: Number(row.rev) };
    },

    async uploadFile(path, data, contentType) {
      const { error } = await files().upload(path, data, { contentType, upsert: true });
      if (error) throw storageCloudError(error);
    },

    async downloadFile(path) {
      const { data, error } = await files().download(path);
      if (error) throw storageCloudError(error);
      return data;
    },

    async removeFiles(paths) {
      const removed: string[] = [];
      for (let i = 0; i < paths.length; i += 100) {
        const batch = paths.slice(i, i + 100);
        const { data, error } = await files().remove(batch);
        if (error) throw storageCloudError(error);
        // Storage answers with the objects it removed; what the rules hide is skipped.
        for (const item of data ?? []) {
          const name = String(item.name ?? '');
          const path = batch.includes(name) ? name : batch.find((p) => p.endsWith(`/${name}`));
          if (path) removed.push(path);
        }
      }
      return removed;
    },

    async listFiles(companyId) {
      const found: StoredFile[] = [];
      for (let offset = 0; ; offset += 1000) {
        const { data, error } = await files().list(companyId, {
          limit: 1000,
          offset,
          sortBy: { column: 'name', order: 'asc' },
        });
        if (error) throw storageCloudError(error);
        for (const item of data ?? []) {
          if (item.id)
            found.push({ path: `${companyId}/${item.name}`, createdAt: item.created_at });
        }
        if (!data || data.length < 1000) return found;
      }
    },

    async storedFiles(companyId, paths) {
      if (paths.length === 0) return [];
      const result = await optionalRpc<string[]>('stored_files', {
        p_company: companyId,
        p_names: paths,
      });
      return result === MISSING ? null : result.map(String);
    },

    async patchCompany(companyId, ops) {
      const result = await optionalRpc<{ rev: number; conflicts: unknown }[]>('patch_company', {
        p_company: companyId,
        p_ops: ops,
      });
      if (result === MISSING) return null;
      const [row] = result;
      if (!row) return null;
      const conflicts = Array.isArray(row.conflicts) ? (row.conflicts as unknown[][]) : [];
      return { rev: Number(row.rev), conflicts: conflicts.map((path) => path.map(String)) };
    },

    async reserveNumber(companyId, kind, date, min) {
      const result = await optionalRpc<{ counter: number; period: string }[]>('reserve_number', {
        p_company: companyId,
        p_kind: kind,
        p_date: date,
        p_min: min,
      });
      if (result === MISSING) return null;
      const [row] = result;
      return row ? { counter: Number(row.counter), period: String(row.period ?? '') } : null;
    },

    async serverFeatures() {
      const result = await optionalRpc<unknown>('server_features', {});
      if (result === MISSING || !Array.isArray(result)) return [];
      return result.filter((feature): feature is string => typeof feature === 'string');
    },

    async beginDeleteCompany(companyId) {
      const result = await optionalRpc<boolean>('begin_delete_company', { p_company: companyId });
      return result === true;
    },

    async companyTeam(companyId) {
      const rows = await rpc<
        { user_id: string; full_name: string; email: string; role: string; joined_at: string }[]
      >('company_team', { p_company: companyId });
      return rows.map((r): TeamMember => ({
        userId: r.user_id,
        fullName: r.full_name,
        email: r.email,
        role: role(r.role),
        joinedAt: r.joined_at,
      }));
    },

    async stockIssueRecipients(companyId) {
      const rows = await rpc<
        {
          id: string;
          number: string;
          name: string;
          name_ar: string;
          job_title: string;
          job_title_ar: string;
          department: string;
        }[]
      >('stock_issue_recipients', { p_company: companyId });
      return rows.map((r): IssueRecipientRow => ({
        id: r.id,
        number: r.number,
        name: r.name,
        nameAr: r.name_ar,
        jobTitle: r.job_title,
        jobTitleAr: r.job_title_ar,
        department: r.department,
      }));
    },

    async createInvite(companyId, email, inviteRole) {
      const [row] = await rpc<
        { id: string; token: string; email: string; role: string; expires_at: string }[]
      >('create_invite', { p_company: companyId, p_email: email, p_role: inviteRole });
      return {
        id: row.id,
        token: row.token,
        email: row.email,
        role: role(row.role),
        createdAt: new Date().toISOString(),
        expiresAt: row.expires_at,
        invitedByName: '',
      };
    },

    async listInvites(companyId) {
      const rows = await rpc<
        {
          id: string;
          email: string;
          role: string;
          token: string;
          created_at: string;
          expires_at: string;
          invited_by_name: string;
        }[]
      >('list_invites', { p_company: companyId });
      return rows.map((r): Invite => ({
        id: r.id,
        email: r.email,
        role: role(r.role),
        token: r.token,
        createdAt: r.created_at,
        expiresAt: r.expires_at,
        invitedByName: r.invited_by_name,
      }));
    },

    async revokeInvite(inviteId) {
      await rpc('revoke_invite', { p_invite: inviteId });
    },

    async inviteDetails(token) {
      const [row] = await rpc<
        {
          company_id: string;
          company_name: string;
          invited_by_name: string;
          email: string;
          role: string;
          expires_at: string;
          status: InviteDetails['status'];
          email_matches: boolean;
        }[]
      >('invite_details', { p_token: token });
      if (!row) return null;
      return {
        companyId: row.company_id,
        companyName: row.company_name,
        invitedByName: row.invited_by_name,
        email: row.email,
        role: role(row.role),
        expiresAt: row.expires_at,
        status: row.status,
        emailMatches: row.email_matches,
      };
    },

    async acceptInvite(token) {
      const [row] = await rpc<{ company_id: string; company_name: string; role: string }[]>(
        'accept_invite',
        { p_token: token },
      );
      return { companyId: row.company_id, companyName: row.company_name, role: role(row.role) };
    },

    async setMemberRole(companyId, userId, newRole) {
      await rpc('set_member_role', { p_company: companyId, p_user: userId, p_role: newRole });
    },

    async removeMember(companyId, userId) {
      await rpc('remove_member', { p_company: companyId, p_user: userId });
    },

    async transferOwnership(companyId, userId) {
      await rpc('transfer_ownership', { p_company: companyId, p_user: userId });
    },

    async myPermissions(companyId) {
      const rows = await optionalRpc<
        {
          permissions: unknown;
          can_approve: boolean | null;
          is_owner: boolean | null;
          senior_roles_owner_only: boolean | null;
        }[]
      >('my_permissions', { p_company: companyId });
      if (rows === MISSING) return null;
      const [row] = rows;
      return {
        permissions: readPermissions(row?.permissions),
        approver: Boolean(row?.can_approve),
        owner: Boolean(row?.is_owner),
        seniorRolesOwnerOnly: Boolean(row?.senior_roles_owner_only),
      };
    },

    async teamPermissions(companyId) {
      const rows = await optionalRpc<
        { user_id: string; permissions: unknown; can_approve: boolean | null }[]
      >('team_permissions', { p_company: companyId });
      if (rows === MISSING) return null;
      return rows.map((r): MemberAccess => ({
        userId: r.user_id,
        permissions: readPermissions(r.permissions),
        canApprove: Boolean(r.can_approve),
      }));
    },

    async setMemberPermissions(companyId, userId, permissions, canApprove) {
      await rpc('set_member_permissions', {
        p_company: companyId,
        p_user: userId,
        p_permissions: permissions,
        p_can_approve: canApprove,
      });
    },

    async setTeamRules(companyId, rules) {
      await rpc('set_team_rules', {
        p_company: companyId,
        p_senior_roles_owner_only: rules.seniorRolesOwnerOnly,
      });
    },

    async ownedCompanies() {
      const rows = await optionalRpc<
        { company_id: string; name: string; members: number; pending_approvals: number }[]
      >('owned_companies_overview', {});
      if (rows === MISSING) return null;
      return rows.map((r): OwnedCompany => ({
        id: r.company_id,
        name: r.name,
        members: Number(r.members),
        pendingApprovals: Number(r.pending_approvals),
      }));
    },

    async deleteCompany(companyId) {
      await rpc('delete_company', { p_company: companyId });
    },

    watch(companyId, onChange) {
      const channel = supabase
        .channel(`company:${companyId}`)
        .on(
          'postgres_changes',
          {
            event: '*',
            schema: 'public',
            table: 'sync_signals',
            filter: `company_id=eq.${companyId}`,
          },
          () => onChange(),
        )
        .subscribe();
      return () => {
        void supabase.removeChannel(channel);
      };
    },

    async emailAlerts(companyId) {
      const rows = await optionalRpc<EmailAlertRow[]>('email_alert_settings', {
        p_company: companyId,
      });
      return rows === MISSING ? null : emailAlertSettings(rows[0]);
    },

    async setEmailAlerts(companyId, settings) {
      const rows = await optionalRpc<EmailAlertRow[]>('set_email_alerts', {
        p_company: companyId,
        p_enabled: settings.enabled,
        p_topics: settings.topics,
        p_app_url: settings.appUrl,
      });
      return rows === MISSING ? null : emailAlertSettings(rows[0]);
    },

    async emailAlertScope(companyId) {
      const rows = await optionalRpc<{ document_kinds: string[] | null }[]>('email_alert_scope', {
        p_company: companyId,
      });
      if (rows === MISSING) return undefined;
      const kinds = rows[0]?.document_kinds;
      return Array.isArray(kinds) ? kinds.filter(isDocumentAlertKind) : null;
    },

    async setEmailAlertScope(companyId, kinds) {
      const { error, status } = await supabase.rpc('set_email_alert_scope', {
        p_company: companyId,
        p_kinds: kinds,
      });
      if (error) {
        if (error.code === 'PGRST202' || status === 404) return false;
        throw cloudError({
          ...error,
          status: status || undefined,
          name: status === 0 ? 'TypeError' : '',
        });
      }
      return true;
    },

    async sendAlertEmail(companyId) {
      const { data, error } = await supabase.functions.invoke<{ to: string; count: number }>(
        'email-alerts',
        { body: { action: 'send', companyId } },
      );
      if (error || !data) throw await alertEmailError(error);
      return { to: data.to, count: data.count };
    },

    async changeFeedStatus(companyId) {
      const rows = await optionalRpc<
        { enabled: boolean | null; unread: number | string; latest: number | string }[]
      >('notification_status', { p_company: companyId });
      if (rows === MISSING) return null;
      const [row] = rows;
      return {
        enabled: Boolean(row?.enabled),
        unread: Number(row?.unread ?? 0) || 0,
        latest: Number(row?.latest ?? 0) || 0,
      };
    },

    async changeFeed(companyId, page = {}) {
      const rows = await optionalRpc<ChangeRow[]>('notification_feed', {
        p_company: companyId,
        p_after: page.after ?? 0,
        p_before: page.before ?? null,
        p_limit: page.limit ?? 50,
      });
      return rows === MISSING ? null : rows.map(changeEvent);
    },

    async markChangesRead(companyId, upto) {
      await rpc('mark_notifications_read', { p_company: companyId, p_upto: upto });
    },

    async changeNotifications(companyId) {
      const rows = await optionalRpc<ChangeSettingsRow[]>('change_notification_settings', {
        p_company: companyId,
      });
      return rows === MISSING ? null : changeSettings(rows[0]);
    },

    async setChangeNotifications(companyId, settings) {
      const rows = await optionalRpc<ChangeSettingsRow[]>('set_change_notifications', {
        p_company: companyId,
        p_enabled: settings.enabled,
        p_immediate_kinds: settings.immediateKinds,
        p_digest: settings.digest,
        p_app_url: settings.appUrl,
      });
      return rows === MISSING ? null : changeSettings(rows[0]);
    },
  };
}
