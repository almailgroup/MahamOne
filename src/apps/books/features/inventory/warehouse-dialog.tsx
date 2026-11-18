import { useEffect, useMemo, useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { toast } from 'sonner';
import { db } from '@/db/db';
import { saveWarehouse } from '@/db/inventory';
import type { Warehouse } from '@/db/types';
import { useCompany } from '@/app/company';
import { useCloudLink } from '@/cloud/hooks';
import { useCloud } from '@/cloud/store';
import type { TeamMember } from '@/cloud/api';
import { isCurrent } from '@/lib/hr/employees';
import { t } from '@/i18n';
import { localName } from '@/i18n/names';
import { Button } from '@/components/ui/button';
import { Combobox } from '@/components/ui/combobox';
import { Field, Input, Select, Switch, Textarea } from '@/components/ui/form';
import { Dialog, DialogBody, DialogContent, DialogFooter } from '@/components/ui/overlay';
import { recipientOf, useWarehouseAccess } from '@/features/inventory/issues';

/** The members of the company, from the cloud (a company kept on this device has none). */
function useTeam(): TeamMember[] {
  const company = useCompany();
  const link = useCloudLink(company.id);
  const { api } = useCloud();
  const [team, setTeam] = useState<TeamMember[]>([]);
  useEffect(() => {
    if (!api || !link) return;
    let cancelled = false;
    api
      .companyTeam(company.id)
      .then((members) => {
        if (!cancelled) setTeam(members);
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
  }, [api, company.id, link]);
  return team;
}

/**
 * Adds or edits a warehouse (a showroom, a store in Shuwaikh or Al-Rai). The
 * owner, an admin or an accountant also make it a sub-warehouse of a main
 * one, looked after by an employee, whose account issues items from it.
 */
export function WarehouseDialog({
  warehouse,
  onClose,
}: {
  warehouse: Warehouse;
  onClose: () => void;
}) {
  const company = useCompany();
  const access = useWarehouseAccess();
  const [draft, setDraft] = useState(warehouse);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const isNew = !warehouse.name;
  const set = (patch: Partial<Warehouse>) => setDraft((d) => ({ ...d, ...patch }));
  const warehouses = useLiveQuery(
    () => db.warehouses.where('companyId').equals(company.id).toArray(),
    [company.id],
  );
  const employees = useLiveQuery(
    () => db.employees.where('companyId').equals(company.id).toArray(),
    [company.id],
  );
  const team = useTeam();
  const subs = access?.offered && access.manages;
  const hasSubs = (warehouses ?? []).some((w) => w.parentId === warehouse.id && !w.archived);
  // Main warehouses it may belong to: in use, not itself, not a sub-warehouse.
  const mains = (warehouses ?? []).filter(
    (w) => w.id !== warehouse.id && !w.archived && !w.parentId,
  );
  const people = useMemo(
    () =>
      (employees ?? [])
        .filter((e) => isCurrent(e) || e.id === draft.keeper?.employeeId)
        .sort((a, b) => localName(a).localeCompare(localName(b)))
        .map((e) => ({
          value: e.id,
          label: localName(e),
          detail: [e.number, e.jobTitle].filter(Boolean).join(' · '),
          keywords: `${e.name} ${e.nameAr ?? ''} ${e.jobTitle}`,
        })),
    [employees, draft.keeper?.employeeId],
  );
  const accounts = team.filter((m) => m.role !== 'viewer');

  const chooseKeeper = (employeeId: string) => {
    const employee = employees?.find((e) => e.id === employeeId);
    if (!employee) {
      set({
        keeper: draft.keeper?.userId
          ? {
              ...draft.keeper,
              employeeId: null,
              name: '',
              nameAr: '',
              jobTitle: '',
              jobTitleAr: '',
            }
          : null,
      });
      return;
    }
    const r = recipientOf(employee);
    setDraft((d) => ({
      ...d,
      // A new sub-warehouse is named after whoever looks after it.
      ...(d.name.trim() ? {} : { name: r.name, nameAr: r.nameAr ?? '' }),
      keeper: {
        employeeId: employee.id,
        name: r.name,
        nameAr: r.nameAr,
        jobTitle: r.jobTitle,
        jobTitleAr: r.jobTitleAr,
        userId: d.keeper?.userId ?? null,
      },
    }));
    setError('');
  };

  const save = async () => {
    if (!draft.name.trim()) {
      setError(t('Enter a name for the warehouse.'));
      return;
    }
    setSaving(true);
    try {
      await saveWarehouse(draft);
      toast.success(t('{name} saved', { name: draft.name.trim() }));
      onClose();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : t('Could not save.'));
      setSaving(false);
    }
  };

  const isSub = Boolean(draft.parentId);
  return (
    <Dialog open onOpenChange={(open) => !open && onClose()}>
      <DialogContent
        title={
          isNew
            ? isSub
              ? t('New sub-warehouse')
              : t('New warehouse')
            : t('Edit {name}', { name: warehouse.name })
        }
        description={
          isSub
            ? t(
                'Stock reaches it from the main warehouse, and whoever looks after it issues items from it.',
              )
            : t('A place you keep stock, such as a showroom or a store.')
        }
      >
        <DialogBody>
          {subs && !warehouse.isDefault && !hasSubs && mains.length > 0 ? (
            <Field
              label={t('Belongs to')}
              hint={t('A sub-warehouse gets its stock from its main warehouse.')}
            >
              {(id) => (
                <Select
                  id={id}
                  value={draft.parentId ?? ''}
                  onChange={(e) => set({ parentId: e.target.value || null, isDefault: false })}
                >
                  <option value="">{t('Nothing: it is a main warehouse')}</option>
                  {mains.map((w) => (
                    <option key={w.id} value={w.id}>
                      {localName(w)}
                    </option>
                  ))}
                </Select>
              )}
            </Field>
          ) : null}
          {subs && isSub ? (
            <Field
              label={t('Looked after by')}
              optional
              hint={t('The employee responsible for the stock kept here.')}
            >
              {(id) => (
                <Combobox
                  id={id}
                  value={draft.keeper?.employeeId ?? ''}
                  onChange={chooseKeeper}
                  options={[{ value: '', label: t('Nobody') }, ...people]}
                  placeholder={t('Choose an employee…')}
                  searchPlaceholder={t('Search employees…')}
                  emptyText={t('No matches')}
                />
              )}
            </Field>
          ) : null}
          <Field label={t('Name')} error={error}>
            {(id) => (
              <Input
                id={id}
                value={draft.name}
                onChange={(e) => {
                  set({ name: e.target.value });
                  setError('');
                }}
                placeholder={isSub ? t('e.g. Ahmed’s store') : t('e.g. Shuwaikh store')}
                autoFocus={!subs}
                aria-invalid={Boolean(error)}
              />
            )}
          </Field>
          <Field label={t('Arabic name')} optional>
            {(id) => (
              <Input
                id={id}
                dir="rtl"
                lang="ar"
                value={draft.nameAr ?? ''}
                onChange={(e) => set({ nameAr: e.target.value })}
              />
            )}
          </Field>
          {subs && isSub && accounts.length > 0 ? (
            <Field
              label={t('Issues items from it')}
              optional
              hint={t(
                'The Maham One account that issues items to employees from this sub-warehouse. Each issue waits for an approver.',
              )}
            >
              {(id) => (
                <Select
                  id={id}
                  value={draft.keeper?.userId ?? ''}
                  onChange={(e) => {
                    const userId = e.target.value || null;
                    set({
                      keeper: draft.keeper
                        ? { ...draft.keeper, userId }
                        : userId
                          ? { employeeId: null, name: '', jobTitle: '', userId }
                          : null,
                    });
                  }}
                >
                  <option value="">
                    {t('Nobody: only the owner, admins and accountants issue')}
                  </option>
                  {accounts.map((m) => (
                    <option key={m.userId} value={m.userId}>
                      {m.fullName || m.email}
                    </option>
                  ))}
                </Select>
              )}
            </Field>
          ) : null}
          <Field label={t('Address')} optional>
            {(id) => (
              <Textarea
                id={id}
                rows={2}
                value={draft.address}
                onChange={(e) => set({ address: e.target.value })}
              />
            )}
          </Field>
          {isSub ? null : (
            <Switch
              checked={draft.isDefault}
              onChange={(isDefault) => set({ isDefault })}
              disabled={warehouse.isDefault}
              label={t('Default warehouse')}
              description={t('Bills and invoices move stock here unless a line says otherwise.')}
            />
          )}
        </DialogBody>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>
            {t('Cancel')}
          </Button>
          <Button onClick={save} loading={saving}>
            {t('Save')}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
