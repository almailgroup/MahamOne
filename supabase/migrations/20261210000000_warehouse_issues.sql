-- =============================================================================
-- Maham One cloud: sub-warehouses, and items issued to employees
-- =============================================================================
--
-- The owner runs this once in the Supabase SQL editor (paste the whole file
-- and press Run), after 20261208000000_ai_assistant.sql. It is safe to run
-- again. If any file from 20261007000000_email_alerts.sql to
-- 20261208000000_ai_assistant.sql is ever run again, run this file again
-- after them. Once items are issued, 20261102000000_tables_v16.sql and
-- 20261207000000_staffing_costings.sql can't run again (they would take
-- stockIssues out of records_tbl_check, so they stop with an error and
-- change nothing).
--
-- Until it runs, the app keeps working as before: sub-warehouses and issuing
-- items to employees are offered only for companies kept on a device, and
-- everything else works the same.
--
-- What it adds
--   * A kind of record, stockIssues: items handed from a warehouse to an
--     employee (uniforms, shoes, badges), kept once an approver confirms
--     them. Only an approver writes one (public.records); anyone else sends
--     the items for approval, as a request of kind stock_issue, and only from
--     a warehouse they may issue from: the sub-warehouse they look after, or
--     any warehouse for the owner, an admin or an accountant. The request
--     names whoever sent it as the one who issued the items (by the
--     warehouse keeper's name and job title when it is theirs). Items issued
--     are never deleted (they are voided instead), nor their stock movements
--     while the issue stands, whatever an older app does.
--   * Sub-warehouses (a warehouse with a parentId, the main warehouse it
--     belongs to) and who looks after a warehouse (its keeper) are set up by
--     the owner, an admin or an accountant. Anyone else records no opening
--     stock, adjustment or transfer of a sub-warehouse, adds or changes no
--     invoice or bill line that moves its stock, and deletes neither a
--     sub-warehouse, its stock entries nor an invoice or bill that moves its
--     stock: its stock comes from the main warehouse and leaves it by items
--     issued.
--   * public.stock_issue_recipients(company): the current employees' number,
--     name, job title and department, for whoever looks after a
--     sub-warehouse (and for the owner, the admins and the accountants), to
--     choose who receives items. Nothing else of People: no salaries,
--     payroll or documents.
--   * The changes of the team (the notification bell and the emails) say who
--     receives items asked for or issued, and what: "1 Trouser, 1 T-shirt".
--   * public.server_features() also answers 'stock_issues'.
--   * The daily clean-up of deletion markers is scheduled when pg_cron is
--     on, as the staffing costings file does, since that file can't run
--     again once items are issued.
--
-- Every function this file replaces is as the latest earlier file left it,
-- with only what is said above added: records_guard as
-- 20261208000000_ai_assistant.sql has it, with every rule it has;
-- can_delete_record as 20261130000000_people_alerts.sql has it;
-- change_details as 20261123000000_change_feed.sql has it; change_kind and
-- record_app as 20261207000000_staffing_costings.sql has them; and
-- server_features as 20261208000000_ai_assistant.sql has it, with every name
-- it answers.
-- =============================================================================

do $$
begin
  if to_regprocedure('almailbooks.switches_ai(text)') is null
    or to_regprocedure('almailbooks.people_shut(text)') is null
    or to_regprocedure('almailbooks.change_details(text,text,jsonb,jsonb,boolean)') is null then
    raise exception 'Run 20261208000000_ai_assistant.sql first, then this file.';
  end if;
end
$$;

-- Tables ------------------------------------------------------------------------

alter table public.records drop constraint if exists records_tbl_check;
alter table public.records
  add constraint records_tbl_check check (tbl in (
    'companies', 'clients', 'products', 'taxRates', 'documents', 'payments', 'recurring',
    'activities', 'accounts', 'journals', 'expenses', 'attachments', 'vatReturns',
    'bankTransactions', 'employees', 'complianceDocuments', 'renewals', 'complianceMarks',
    'peopleSettings', 'securityCheques', 'assets', 'depreciationRuns', 'yearEnds', 'payRuns',
    'payrollSettings', 'leaveRecords', 'staffLoans', 'finalSettlements', 'warehouses',
    'stockMovements', 'stockEntries', 'landedCosts', 'chequeLayouts', 'vehicles', 'approvals',
    'letterTemplates', 'employeeLetters', 'staffingCostings', 'stockIssues'
  ));

-- Helpers (not callable through the API) ---------------------------------------

-- The caller sets up sub-warehouses and changes their stock directly: the
-- owner, an admin or an accountant. Kept the same as managesWarehouses in
-- src/db/stock-issues.ts.
create or replace function almailbooks.manages_warehouses(p_company text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(almailbooks.member_role(p_company)::text, '') in ('owner', 'admin', 'accountant')
$$;

-- A warehouse that only the owner, an admin or an accountant changes: a
-- sub-warehouse, or one someone looks after.
create or replace function almailbooks.warehouse_ruled(p_data jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(p_data ->> 'parentId', '') <> ''
    or coalesce(jsonb_typeof(p_data -> 'keeper'), 'null') = 'object'
$$;

-- The warehouse is a sub-warehouse of the company (it has a main one).
create or replace function almailbooks.is_sub_warehouse(p_company text, p_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(p_id, '') <> '' and exists (
    select 1
    from public.records r
    where r.company_id = p_company
      and r.tbl = 'warehouses'
      and r.id = p_id
      and coalesce(r.data ->> 'parentId', '') <> ''
  )
$$;

-- A stock entry (opening stock, an adjustment, a transfer) moves the stock
-- of a sub-warehouse.
create or replace function almailbooks.entry_in_sub_warehouse(p_company text, p_data jsonb)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select almailbooks.is_sub_warehouse(p_company, p_data ->> 'warehouseId')
    or almailbooks.is_sub_warehouse(p_company, p_data ->> 'toWarehouseId')
$$;

-- The lines of a document that move a sub-warehouse's stock, with the
-- document's type and stage (a draft issued moves them), or [] when it has
-- none: what anyone but the owner, an admin or an accountant may not change.
create or replace function almailbooks.sub_warehouse_lines(p_company text, p_data jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_lines jsonb;
begin
  if p_data is null or jsonb_typeof(p_data -> 'items') <> 'array' then
    return '[]'::jsonb;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', i ->> 'id',
      'productId', i ->> 'productId',
      'warehouseId', i ->> 'warehouseId',
      'quantity', i -> 'quantity'
    ) order by i ->> 'id'), '[]'::jsonb)
  into v_lines
  from jsonb_array_elements(p_data -> 'items') i
  where almailbooks.is_sub_warehouse(p_company, i ->> 'warehouseId');
  if v_lines = '[]'::jsonb then
    return v_lines;
  end if;
  return jsonb_build_object(
    'lines', v_lines,
    'type', p_data ->> 'type',
    'stage', almailbooks.document_stage(p_data ->> 'status')
  );
end
$$;

-- The caller may ask for items to be issued from the warehouse: a member who
-- is the owner, an admin or an accountant, or who looks after the warehouse
-- (a sub-warehouse in use) and isn't a viewer. Kept the same as
-- issuesFromWarehouse in src/cloud/roles.ts.
create or replace function almailbooks.issues_from(p_company text, p_warehouse text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(almailbooks.member_role(p_company)::text, 'viewer') <> 'viewer'
    and (
      almailbooks.manages_warehouses(p_company)
      or exists (
        select 1
        from public.records r
        where r.company_id = p_company
          and r.tbl = 'warehouses'
          and r.id = p_warehouse
          and coalesce(r.data ->> 'parentId', '') <> ''
          and coalesce(r.data ->> 'archived', '') <> 'true'
          and r.data -> 'keeper' ->> 'userId' = auth.uid()::text
      )
    )
$$;

-- Who receives items issued, and what, for the changes of the team. Kept the
-- same as issueSummary in src/cloud/change-feed.ts.
create or replace function almailbooks.issue_summary(p_issue jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'name', nullif(p_issue -> 'recipient' ->> 'name', ''),
    'nameAr', nullif(p_issue -> 'recipient' ->> 'nameAr', ''),
    'jobTitle', nullif(p_issue -> 'recipient' ->> 'jobTitle', ''),
    'jobTitleAr', nullif(p_issue -> 'recipient' ->> 'jobTitleAr', ''),
    'items', (
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'quantity', case when jsonb_typeof(l -> 'quantity') = 'number' then l -> 'quantity' end,
        'name', nullif(l ->> 'name', ''),
        'nameAr', nullif(l ->> 'nameAr', '')
      )) order by n)
      from jsonb_array_elements(
        case when jsonb_typeof(p_issue -> 'lines') = 'array' then p_issue -> 'lines' else '[]'::jsonb end
      ) with ordinality as x(l, n)
    )
  ))
$$;

-- The app a record belongs to, for the owner's limits on a member. As in
-- 20261207000000_staffing_costings.sql, with items issued in Maham Books
-- (its inventory). Kept the same as recordApp in src/cloud/roles.ts.
create or replace function almailbooks.record_app(p_tbl text, p_data jsonb)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_tbl in (
      'employees', 'payRuns', 'payrollSettings', 'peopleSettings', 'leaveRecords', 'staffLoans',
      'finalSettlements', 'letterTemplates', 'employeeLetters', 'staffingCostings'
    ) then 'people'
    -- Payroll entries are made by pay runs.
    when p_tbl = 'journals' and coalesce(p_data ->> 'kind', '') = 'payroll' then 'people'
    -- An employee's own papers are kept with them.
    when p_tbl in ('complianceDocuments', 'renewals')
      and coalesce(p_data ->> 'employeeId', '') <> '' then 'people'
    when p_tbl in ('complianceDocuments', 'renewals', 'complianceMarks', 'vehicles')
      then 'compliance'
    when p_tbl in (
      'clients', 'products', 'taxRates', 'documents', 'payments', 'recurring', 'accounts',
      'journals', 'expenses', 'vatReturns', 'bankTransactions', 'securityCheques', 'assets',
      'depreciationRuns', 'yearEnds', 'warehouses', 'stockMovements', 'stockEntries',
      'landedCosts', 'chequeLayouts', 'stockIssues'
    ) then 'books'
    else null
  end
$$;

-- The kind of change a record makes, for the changes of the team. As in
-- 20261207000000_staffing_costings.sql, with items issued among stock. Kept
-- the same as changeKind in src/cloud/change-feed.ts.
create or replace function almailbooks.change_kind(p_tbl text, p_data jsonb)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_tbl = 'documents' then 'document'
    when p_tbl = 'payments' then
      case when coalesce(p_data ->> 'method', '') = 'cheque' then 'cheque' else 'payment' end
    when p_tbl = 'securityCheques' then 'cheque'
    when p_tbl = 'approvals' then 'approval'
    when p_tbl = 'companies' then 'settings'
    when p_tbl in (
      'employees', 'payRuns', 'payrollSettings', 'peopleSettings', 'leaveRecords', 'staffLoans',
      'finalSettlements', 'letterTemplates', 'employeeLetters', 'staffingCostings'
    ) then 'people'
    when p_tbl in ('complianceDocuments', 'renewals', 'complianceMarks', 'vehicles') then 'compliance'
    when p_tbl = 'clients' then 'contact'
    when p_tbl in (
      'products', 'warehouses', 'stockMovements', 'stockEntries', 'landedCosts', 'stockIssues'
    ) then 'item'
    when p_tbl = 'expenses' then 'expense'
    when p_tbl = 'attachments' then 'file'
    else 'accounting'
  end
$$;

-- What a change did and whether it is important, with a short summary. As in
-- 20261123000000_change_feed.sql, with who receives items issued, and what,
-- on a request to issue them and on the items issued. Kept the same as
-- changeDetails in src/cloud/change-feed.ts.
create or replace function almailbooks.change_details(
  p_company text,
  p_tbl text,
  p_old jsonb,
  p_new jsonb,
  p_private boolean
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_data jsonb := coalesce(p_new, p_old);
  v_what text;
  v_important boolean := false;
  v_summary jsonb;
  v_was text;
  v_now text;
  v_client text;
  v_client_ar text;
  v_changes text[] := '{}';
  v_cheque boolean;
  v_old_rest jsonb;
  v_new_rest jsonb;
  v_issue jsonb;
begin
  v_what := case when p_old is null then 'added' when p_new is null then 'deleted' else 'updated' end;

  -- Payroll and people data: only what happened, and to a pay run its stage.
  if p_private then
    if p_tbl = 'approvals' then
      v_was := coalesce(p_old ->> 'status', 'pending');
      v_now := coalesce(p_new ->> 'status', 'pending');
      if p_old is null then
        v_what := 'requested';
      elsif p_new is not null and v_now <> v_was then
        v_what := v_now;
      end if;
      return jsonb_build_object(
        'important', v_what in ('requested', 'approved', 'rejected'),
        'summary', jsonb_strip_nulls(jsonb_build_object(
          'what', v_what, 'request', v_data ->> 'kind', 'status', v_now
        ))
      );
    end if;
    if p_tbl = 'payRuns' then
      v_was := p_old ->> 'status';
      v_now := p_new ->> 'status';
      if p_old is not null and p_new is not null and v_now is distinct from v_was then
        v_what := coalesce(v_now, 'updated');
      end if;
      return jsonb_build_object(
        'important', v_what <> 'updated' and v_what <> 'draft',
        'summary', jsonb_strip_nulls(jsonb_build_object(
          'what', v_what,
          'status', v_data ->> 'status',
          'was', case when v_what not in ('added', 'deleted') then v_was end,
          'period', case when v_data ->> 'period' ~ '^\d{4}-\d{2}$' then v_data ->> 'period' end
        ))
      );
    end if;
    return jsonb_build_object('important', false, 'summary', jsonb_build_object('what', v_what));
  end if;

  -- The customer or vendor a document, payment or cheque is for.
  if p_tbl in ('documents', 'payments', 'securityCheques')
    and coalesce(v_data ->> 'clientId', '') <> '' then
    select c.data ->> 'name', c.data ->> 'nameAr' into v_client, v_client_ar
    from public.records c
    where c.company_id = p_company and c.tbl = 'clients' and c.id = v_data ->> 'clientId';
  end if;

  if p_tbl = 'documents' then
    v_was := case when p_old is not null then almailbooks.document_stage(p_old ->> 'status') end;
    v_now := case when p_new is not null then almailbooks.document_stage(p_new ->> 'status') end;
    if p_old is not null and p_new is not null then
      v_what := case
        when v_now = 'void' and v_was <> 'void' then 'voided'
        when v_was = 'void' and v_now <> 'void' then 'restored'
        when v_was = 'draft' and v_now = 'issued' then 'issued'
        when v_was = 'issued' and v_now = 'issued'
          and almailbooks.invoice_content(p_old) is distinct from almailbooks.invoice_content(p_new)
          then 'edited'
        else 'updated'
      end;
    end if;
    v_important := coalesce(v_data ->> 'type', '') in ('invoice', 'credit') and (
      v_what in ('voided', 'restored', 'edited')
      or (v_what = 'deleted' and v_was <> 'draft')
    );
    v_summary := jsonb_build_object(
      'what', v_what,
      'type', v_data ->> 'type',
      'number', v_data ->> 'number',
      'status', v_data ->> 'status',
      'was', case
        when p_old is not null and p_new is not null
          and (p_old ->> 'status') is distinct from (p_new ->> 'status') then p_old ->> 'status'
      end,
      'total', case when jsonb_typeof(v_data -> 'totals' -> 'total') = 'number'
        then v_data -> 'totals' -> 'total' end,
      'currency', v_data ->> 'currency',
      'client', v_client,
      'clientAr', v_client_ar
    );
  elsif p_tbl = 'payments' then
    v_cheque := coalesce(p_new ->> 'method', '') = 'cheque' or coalesce(p_old ->> 'method', '') = 'cheque';
    v_was := p_old -> 'cheque' ->> 'status';
    v_now := p_new -> 'cheque' ->> 'status';
    if p_old is not null and p_new is not null then
      v_what := case
        when v_cheque
          and almailbooks.cheque_content(p_old) is distinct from almailbooks.cheque_content(p_new)
          then 'edited'
        when v_cheque and v_now is not null and v_now is distinct from v_was then v_now
        when coalesce(p_new ->> 'voided', '') = 'true' and coalesce(p_old ->> 'voided', '') <> 'true'
          then 'voided'
        when (p_old -> 'amount') is distinct from (p_new -> 'amount')
          or (p_old -> 'currency') is distinct from (p_new -> 'currency')
          or (p_old -> 'date') is distinct from (p_new -> 'date')
          or (p_old -> 'clientId') is distinct from (p_new -> 'clientId')
          then 'edited'
        else 'updated'
      end;
    end if;
    v_important := v_cheque
      and v_what in ('added', 'deleted', 'edited', 'voided', 'returned', 'cancelled');
    v_summary := jsonb_build_object(
      'what', v_what,
      'direction', coalesce(v_data ->> 'direction', 'in'),
      'method', v_data ->> 'method',
      'number', v_data ->> 'number',
      'amount', case when jsonb_typeof(v_data -> 'amount') = 'number' then v_data -> 'amount' end,
      'currency', v_data ->> 'currency',
      'cheque', v_data -> 'cheque' ->> 'number',
      'bank', v_data -> 'cheque' ->> 'bank',
      'status', v_data -> 'cheque' ->> 'status',
      'was', case when v_what = v_now then v_was end,
      'client', v_client,
      'clientAr', v_client_ar
    );
  elsif p_tbl = 'securityCheques' then
    v_was := p_old ->> 'status';
    v_now := p_new ->> 'status';
    if p_old is not null and p_new is not null then
      v_what := case
        when almailbooks.security_cheque_content(p_old)
          is distinct from almailbooks.security_cheque_content(p_new) then 'edited'
        when v_now is not null and v_now is distinct from v_was then v_now
        else 'updated'
      end;
    end if;
    v_important := v_what in ('added', 'deleted', 'edited', 'cashed');
    v_summary := jsonb_build_object(
      'what', v_what,
      'direction', coalesce(v_data ->> 'direction', 'in'),
      'cheque', v_data ->> 'number',
      'bank', v_data ->> 'bank',
      'amount', case when jsonb_typeof(v_data -> 'amount') = 'number' then v_data -> 'amount' end,
      'currency', v_data ->> 'currency',
      'status', v_data ->> 'status',
      'was', case when v_what = v_now then v_was end,
      'client', v_client,
      'clientAr', v_client_ar
    );
  elsif p_tbl = 'approvals' then
    v_was := coalesce(p_old ->> 'status', 'pending');
    v_now := coalesce(p_new ->> 'status', 'pending');
    if p_old is null then
      v_what := 'requested';
    elsif p_new is not null and v_now <> v_was then
      v_what := v_now;
    end if;
    v_important := v_what in ('requested', 'approved', 'rejected');
    v_summary := jsonb_build_object(
      'what', v_what,
      'request', v_data ->> 'kind',
      'subject', v_data ->> 'subjectTbl',
      'number', v_data ->> 'subjectNumber',
      'status', v_now
    );
    -- Items to issue: who receives them, and what.
    if v_data ->> 'kind' = 'stock_issue' and jsonb_typeof(v_data -> 'after') = 'object' then
      v_issue := v_data -> 'after';
      v_summary := v_summary || almailbooks.issue_summary(v_issue);
    end if;
  elsif p_tbl = 'companies' then
    if p_old is not null and p_new is not null then
      if not almailbooks.counters_only(p_old -> 'numbering', p_new -> 'numbering') then
        v_changes := v_changes || 'numbering'::text;
      end if;
      if nullif(p_old -> 'accounting' -> 'lockDate', 'null'::jsonb)
        is distinct from nullif(p_new -> 'accounting' -> 'lockDate', 'null'::jsonb) then
        v_changes := v_changes || 'lockDate'::text;
      end if;
      if nullif(p_old -> 'approvalRules', 'null'::jsonb)
        is distinct from nullif(p_new -> 'approvalRules', 'null'::jsonb) then
        v_changes := v_changes || 'approvalRules'::text;
      end if;
      v_old_rest := p_old - 'numbering' - 'updatedAt' - 'approvalRules' - 'accounting';
      v_new_rest := p_new - 'numbering' - 'updatedAt' - 'approvalRules' - 'accounting';
      if cardinality(v_changes) = 0
        and v_old_rest is not distinct from v_new_rest
        and (
          case when jsonb_typeof(p_old -> 'accounting') = 'object'
            then (p_old -> 'accounting') - 'lockDate' else p_old -> 'accounting' end
        ) is not distinct from (
          case when jsonb_typeof(p_new -> 'accounting') = 'object'
            then (p_new -> 'accounting') - 'lockDate' else p_new -> 'accounting' end
        ) then
        -- Only a document counter moved on (every new invoice does that).
        return null;
      end if;
    end if;
    v_important := cardinality(v_changes) > 0;
    v_summary := jsonb_build_object(
      'what', 'settings',
      'changes', to_jsonb(v_changes),
      'lockDate', case when 'lockDate' = any (v_changes) then p_new -> 'accounting' ->> 'lockDate' end,
      'was', case when 'lockDate' = any (v_changes) then p_old -> 'accounting' ->> 'lockDate' end
    );
  elsif p_tbl = 'clients' then
    v_summary := jsonb_build_object(
      'what', v_what,
      'name', v_data ->> 'name',
      'nameAr', v_data ->> 'nameAr',
      'vendor', case when v_data ->> 'isVendor' = 'true' then true end
    );
  elsif p_tbl = 'products' then
    v_summary := jsonb_build_object(
      'what', v_what, 'name', v_data ->> 'name', 'nameAr', v_data ->> 'nameAr', 'sku', v_data ->> 'sku'
    );
  elsif p_tbl in ('expenses', 'journals') then
    v_summary := jsonb_build_object(
      'what', v_what,
      'number', v_data ->> 'number',
      'amount', case when p_tbl = 'expenses' and jsonb_typeof(v_data -> 'amount') = 'number'
        then v_data -> 'amount' end,
      'currency', case when p_tbl = 'expenses' then v_data ->> 'currency' end
    );
  elsif p_tbl = 'stockIssues' then
    v_summary := jsonb_build_object('what', v_what, 'number', v_data ->> 'number')
      || almailbooks.issue_summary(v_data);
  elsif p_tbl = 'vehicles' then
    v_summary := jsonb_build_object('what', v_what, 'name', v_data ->> 'plate');
  elsif p_tbl = 'complianceDocuments' then
    v_summary := jsonb_build_object('what', v_what, 'name', v_data ->> 'title', 'type', v_data ->> 'type');
  elsif p_tbl = 'attachments' then
    v_summary := jsonb_build_object('what', v_what, 'name', v_data ->> 'name');
  else
    v_summary := jsonb_build_object('what', v_what);
  end if;
  return jsonb_build_object('important', v_important, 'summary', jsonb_strip_nulls(v_summary));
end
$$;

-- What the server checks before a record is stored, after
-- records_before_write (triggers of the same kind run in the order of their
-- names). Only the company record, documents, approval requests, cheque
-- payments, security cheques given, the People settings, employee letters,
-- warehouses, stock entries and items issued are looked at; every other
-- record passes at once. Refusals have the SQL state 42501.
--
-- As in 20261208000000_ai_assistant.sql, with every rule it has, and:
-- sub-warehouses (and who looks after a warehouse) are the owner's, the
-- admins' and the accountants', as are opening stock, adjustments and
-- transfers of a sub-warehouse and document lines that move its stock;
-- items issued are written by approvers only; and a request to issue items
-- comes from whoever may issue from the warehouse, as the one who issued.
create or replace function almailbooks.records_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rules jsonb;
  v_approver boolean;
  v_me text := auth.uid()::text;
  v_now jsonb;
  v_status text;
  v_was text;
  v_key text;
  v_payroll boolean := false;
  v_role public.member_role;
  v_run text;
  v_keeper jsonb;
  v_name text;
begin
  -- The SQL editor and the server's own jobs are not members.
  if new.tbl not in (
      'companies', 'documents', 'approvals', 'payments', 'securityCheques',
      'peopleSettings', 'employeeLetters', 'warehouses', 'stockEntries', 'stockIssues'
    )
    or auth.uid() is null then
    return new;
  end if;
  -- Payments other than cheques, and security cheques received, at once.
  if new.tbl = 'payments'
    and coalesce(new.data ->> 'method', '') <> 'cheque'
    and (tg_op = 'INSERT' or coalesce(old.data ->> 'method', '') <> 'cheque') then
    return new;
  end if;
  if new.tbl = 'securityCheques'
    and coalesce(new.data ->> 'direction', '') <> 'out'
    and (tg_op = 'INSERT' or coalesce(old.data ->> 'direction', '') <> 'out') then
    return new;
  end if;
  -- An upsert runs this as an insert before it turns into an update: a
  -- record that is already there is checked as the update.
  if tg_op = 'INSERT' and exists (
    select 1
    from public.records r
    where r.company_id = new.company_id and r.tbl = new.tbl and r.id = new.id
  ) then
    return new;
  end if;

  -- Sub-warehouses, and who looks after them, are set up by the owner, an
  -- admin or an accountant: anyone else changes no sub-warehouse, and
  -- makes no warehouse one.
  if new.tbl = 'warehouses' then
    if not almailbooks.manages_warehouses(new.company_id) and (
      almailbooks.warehouse_ruled(new.data)
      or (tg_op = 'UPDATE' and almailbooks.warehouse_ruled(old.data))
    ) then
      raise exception 'almail:permission Only the owner, an admin or an accountant sets up sub-warehouses.'
        using errcode = '42501';
    end if;
    return new;
  end if;

  -- The stock of a sub-warehouse comes from the main warehouse and leaves
  -- it by items issued: anyone but the owner, an admin or an accountant
  -- records no opening stock, adjustment or transfer of it.
  if new.tbl = 'stockEntries' then
    if not almailbooks.manages_warehouses(new.company_id) and (
      almailbooks.entry_in_sub_warehouse(new.company_id, new.data)
      or (tg_op = 'UPDATE' and almailbooks.entry_in_sub_warehouse(new.company_id, old.data))
    ) then
      raise exception 'almail:permission Only the owner, an admin or an accountant changes the stock of a sub-warehouse directly.'
        using errcode = '42501';
    end if;
    return new;
  end if;

  -- Items issued to employees are kept once an approver confirms them:
  -- anyone else sends them for approval (a request of kind stock_issue).
  if new.tbl = 'stockIssues' then
    if not almailbooks.is_approver(new.company_id) then
      raise exception 'almail:permission Only an approver records items issued. Send them for approval instead.'
        using errcode = '42501';
    end if;
    return new;
  end if;

  -- Nor does anyone else move a sub-warehouse's stock with an invoice or a
  -- bill: lines of a document that take stock from (or bring it to) a
  -- sub-warehouse are theirs to add or change.
  if new.tbl = 'documents'
    and not almailbooks.manages_warehouses(new.company_id)
    and almailbooks.sub_warehouse_lines(new.company_id, new.data)
      is distinct from almailbooks.sub_warehouse_lines(
        new.company_id,
        case when tg_op = 'UPDATE' then old.data end
      ) then
    raise exception 'almail:permission Only the owner, an admin or an accountant moves the stock of a sub-warehouse on a document.'
      using errcode = '42501';
  end if;

  -- The letters switch (#19) is the owner's and the admins': anyone else's
  -- copy keeps it as it is stored (a copy that hasn't heard of it yet never
  -- turns it off).
  if new.tbl = 'peopleSettings' then
    if coalesce(almailbooks.member_role(new.company_id)::text, '') not in ('owner', 'admin') then
      new.data := almailbooks.kept_key(
        new.data,
        case when tg_op = 'UPDATE' then old.data end,
        'letters'
      );
    end if;
    return new;
  end if;

  -- Employee letters (#19), with the company's letters on: a letter issued
  -- or void stays so, and only the owner, an admin or an approver issues
  -- one, or voids one that is issued. Drafts are anyone's who may write
  -- them, and marking a letter printed changes nothing of it.
  if new.tbl = 'employeeLetters' then
    if not almailbooks.letters_on(new.company_id) then
      return new;
    end if;
    v_was := case when tg_op = 'UPDATE' then coalesce(old.data ->> 'status', 'draft') end;
    v_status := coalesce(new.data ->> 'status', 'draft');
    if v_was in ('issued', 'void') and v_status = 'draft' then
      raise exception 'almail:invalid This letter is already issued, so it stays issued.'
        using errcode = '42501';
    end if;
    -- An issued or void letter stays as it was issued (a void one void):
    -- a copy sent again, older or not, only adds when it was printed, and
    -- an issued one may be voided.
    if v_was in ('issued', 'void') then
      new.data := almailbooks.issued_letter_kept(old.data, new.data);
      v_status := coalesce(new.data ->> 'status', 'draft');
    end if;
    if (v_status <> 'draft' or coalesce(v_was, 'draft') <> 'draft')
      and (
        tg_op = 'INSERT'
        or almailbooks.letter_content(old.data) is distinct from almailbooks.letter_content(new.data)
      )
      and not almailbooks.issues_letters(new.company_id) then
      raise exception 'almail:permission Only the owner, an admin or an approver issues letters. Ask for approval instead.'
        using errcode = '42501';
    end if;
    return new;
  end if;

  if new.tbl = 'companies' then
    -- The AI assistant's switch (Settings → AI assistant) is the owner's and
    -- the admins', whatever apps the owner limited an admin to: anyone
    -- else's copy keeps it as it is stored (a copy that hasn't heard of it
    -- never turns it off, and nobody else turns it on).
    if not almailbooks.switches_ai(new.company_id) then
      new.data := almailbooks.kept_key(
        new.data,
        case when tg_op = 'UPDATE' then old.data end,
        'ai'
      );
    end if;
    -- Only the owner changes the approval rules (by a push or patch_company).
    if nullif(case when tg_op = 'UPDATE' then old.data -> 'approvalRules' end, 'null'::jsonb)
        is distinct from nullif(new.data -> 'approvalRules', 'null'::jsonb)
      and almailbooks.member_role(new.company_id) is distinct from 'owner' then
      raise exception 'almail:permission Only the owner changes the approval rules.'
        using errcode = '42501';
    end if;
    -- The books' settings are Maham Books': not changed by a member the owner
    -- made it view only for (the lock date, numbering, payment details…).
    if tg_op = 'UPDATE'
      and almailbooks.company_books_changed(old.data, new.data)
      and almailbooks.books_limited(new.company_id) then
      raise exception 'almail:permission The owner has made Maham Books view only for you.'
        using errcode = '42501';
    end if;
    return new;
  end if;

  -- An invoice or credit note leaving draft (or new) and issued without a
  -- number, while the company numbers them when they are issued: an older
  -- version of the app issuing a draft that waits for its number.
  if new.tbl = 'documents'
    and coalesce(new.data ->> 'type', '') in ('invoice', 'credit')
    and almailbooks.document_stage(new.data ->> 'status') = 'issued'
    and btrim(coalesce(new.data ->> 'number', '')) = ''
    and (tg_op = 'INSERT' or coalesce(old.data ->> 'status', '') = 'draft')
    and almailbooks.numbers_on_issue(new.company_id) then
    raise exception 'almail:invalid This invoice has no number yet. Update the app on this device, then issue it again.'
      using errcode = '42501';
  end if;

  if new.tbl <> 'approvals' then
    v_rules := almailbooks.approval_rules(new.company_id);
    if v_rules is null then
      return new;
    end if;
  end if;
  v_approver := almailbooks.is_approver(new.company_id);

  if new.tbl in ('payments', 'securityCheques') then
    -- A cheque the rules cover is recorded, changed in what is confirmed on
    -- it, by approvers only; anyone else sends it for confirmation.
    -- Whoever may not write it at all is refused by the row's policies, as before.
    if not v_approver and almailbooks.cheque_change_needs_approver(
      v_rules,
      new.tbl,
      case when tg_op = 'UPDATE' then old.data end,
      new.data
    ) and almailbooks.can_write_record(new.company_id, new.tbl, new.data) then
      raise exception 'almail:approval_required This cheque needs confirmation. Send it for confirmation instead.'
        using errcode = '42501';
    end if;
    return new;
  end if;

  if new.tbl = 'documents' then
    -- New documents and drafts are anyone's to write, and approvers write anything.
    if tg_op = 'INSERT' or v_approver or coalesce(old.data ->> 'status', '') = 'draft'
      or not (
        almailbooks.rules_cover_document(v_rules, old.data ->> 'type')
        or almailbooks.rules_cover_document(v_rules, new.data ->> 'type')
      ) then
      return new;
    end if;
    if almailbooks.invoice_content(old.data) is distinct from almailbooks.invoice_content(new.data)
      or almailbooks.document_stage(old.data ->> 'status')
        <> almailbooks.document_stage(new.data ->> 'status') then
      raise exception 'almail:approval_required This change to an issued document needs approval. Send it for approval instead.'
        using errcode = '42501';
    end if;
    -- Its payment link, once it has one, is changed or removed by approvers
    -- only. Documents travel whole, so anyone else's copy keeps the stored
    -- link instead of being refused: a device that had not yet received the
    -- link (or its change) and records a payment on the invoice must neither
    -- undo it nor lose the payment. The app refuses a change made on purpose
    -- before it is sent (paymentLinkNeedsApprover).
    if almailbooks.payment_link_changed(old.data, new.data) then
      new.data := almailbooks.kept_key(new.data, old.data, 'paymentLink');
    end if;
    return new;
  end if;

  -- Approval requests, whether or not the rules are on.
  v_now := to_jsonb(to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
  -- A pay run's, with salary approval on (#10).
  if coalesce(case when tg_op = 'UPDATE' then old.data else new.data end ->> 'kind', '') = 'payroll'
    and coalesce(
      case when tg_op = 'UPDATE' then old.data else new.data end ->> 'subjectTbl', ''
    ) = 'payRuns' then
    v_payroll := almailbooks.payroll_approval_on(new.company_id);
  end if;
  if tg_op = 'INSERT' then
    -- Items to issue to an employee are asked for by whoever may issue from
    -- the warehouse (its keeper, or the owner, an admin or an accountant),
    -- as themselves.
    if coalesce(new.data ->> 'kind', '') = 'stock_issue' then
      if not almailbooks.issues_from(new.company_id, new.data -> 'after' ->> 'warehouseId') then
        raise exception 'almail:permission You can only issue items from the sub-warehouse you look after.'
          using errcode = '42501';
      end if;
      if jsonb_typeof(new.data -> 'after') = 'object' then
        new.data := jsonb_set(new.data, '{after,issuedBy}', to_jsonb(v_me));
      end if;
      -- Named as the warehouse's keeper (with their job title) when they
      -- look after it; anyone else's name is not taken from their copy (the
      -- app names their account).
      select w.data -> 'keeper' into v_keeper
      from public.records w
      where w.company_id = new.company_id
        and w.tbl = 'warehouses'
        and w.id = new.data -> 'after' ->> 'warehouseId';
      v_name := nullif(btrim(coalesce(v_keeper ->> 'name', '')), '');
      if v_keeper ->> 'userId' = v_me and v_name is not null then
        v_name := v_name
          || coalesce(' (' || nullif(btrim(coalesce(v_keeper ->> 'jobTitle', '')), '') || ')', '');
        new.data := jsonb_set(new.data, '{requestedByName}', to_jsonb(v_name));
        if jsonb_typeof(new.data -> 'after') = 'object' then
          new.data := jsonb_set(new.data, '{after,issuedByName}', to_jsonb(v_name));
        end if;
      else
        new.data := (new.data - 'requestedByName') #- '{after,issuedByName}';
      end if;
    end if;
    if v_approver and coalesce(new.data ->> 'status', 'pending') <> 'pending'
      -- A pay run's sent up already approved by anyone but the owner waits.
      and not (
        v_payroll
        and new.data ->> 'status' in ('approved', 'applied')
        and almailbooks.member_role(new.company_id) is distinct from 'owner'
      ) then
      -- The owner's own copy of a decided request (the company sent up again) is kept.
      if almailbooks.member_role(new.company_id) = 'owner' then
        return new;
      end if;
      -- Anyone else's is asked and decided by them, now, whatever the copy says.
      if new.data ->> 'requestedBy' is distinct from v_me then
        new.data := (new.data - 'requestedByName')
          || jsonb_build_object('requestedBy', v_me, 'requestedAt', v_now);
      end if;
      if new.data ->> 'decidedBy' is distinct from v_me then
        new.data := new.data || jsonb_build_object('decidedBy', v_me, 'decidedAt', v_now);
      end if;
      return new;
    end if;
    -- A new request waits for a decision, asked by whoever sends it, now.
    new.data := (new.data - 'expired' - 'resultId') || jsonb_build_object(
      'status', 'pending',
      'requestedBy', v_me,
      'requestedAt', v_now,
      'decidedBy', null,
      'decidedAt', null,
      'decisionNote', ''
    );
    return new;
  end if;

  v_was := coalesce(old.data ->> 'status', 'pending');
  v_status := coalesce(new.data ->> 'status', v_was);
  if not v_approver then
    -- Whoever isn't an approver changes nothing of a request but taking it back.
    new.data := old.data
      || jsonb_build_object('status', v_status)
      || case
        when new.data ? 'updatedAt' then jsonb_build_object('updatedAt', new.data -> 'updatedAt')
        else '{}'::jsonb
      end;
  end if;
  -- What was asked, by whom and when, never changes.
  foreach v_key in array array[
    'kind', 'subjectTbl', 'subjectId', 'subjectNumber', 'before', 'after', 'reason',
    'requestedBy', 'requestedByName', 'requestedAt', 'createdAt'
  ] loop
    new.data := almailbooks.kept_key(new.data, old.data, v_key);
  end loop;
  if v_status = v_was or v_status = 'pending' or v_was in ('rejected', 'cancelled', 'applied') then
    -- No decision now (an older copy that still waits, sent again), or one
    -- made before: an older copy can't undo it.
    new.data := new.data || jsonb_build_object(
      'status', v_was,
      'decidedBy', old.data -> 'decidedBy',
      'decidedAt', old.data -> 'decidedAt',
      'decisionNote', coalesce(nullif(old.data -> 'decisionNote', 'null'::jsonb), to_jsonb(''::text))
    );
    new.data := almailbooks.kept_key(new.data, old.data, 'expired');
    new.data := almailbooks.kept_key(new.data, old.data, 'resultId');
    return new;
  end if;
  if v_status not in ('approved', 'rejected', 'cancelled', 'applied') then
    raise exception 'almail:invalid A decided request can''t wait again.' using errcode = '42501';
  end if;
  if not v_approver
    and not (
      v_was = 'pending'
      and v_status = 'cancelled'
      and old.data ->> 'requestedBy' = v_me
    )
    -- The approved pay run posted: done, by whoever may post it.
    and not (
      v_payroll
      and v_was = 'approved'
      and v_status = 'applied'
      and almailbooks.can_write_record(new.company_id, 'payRuns', '{}'::jsonb)
    ) then
    -- Whoever asked may only take the request back while it waits.
    raise exception 'almail:permission Only an approver decides approval requests.'
      using errcode = '42501';
  end if;
  -- A pay run's request is decided by approvers who see payroll: not by a
  -- member the owner gave no access to People (they get no email of it
  -- either). Whoever asked may still take it back.
  if v_payroll
    and almailbooks.people_shut(new.company_id)
    and not (v_was = 'pending' and v_status = 'cancelled' and old.data ->> 'requestedBy' = v_me) then
    raise exception 'almail:permission The owner has given you no access to Maham People, so you don''t decide pay runs.'
      using errcode = '42501';
  end if;
  -- A pay run is approved by someone other than whoever sent it (the owner
  -- may approve their own), and only as it was sent. The owner who posts it
  -- carries out a waiting request as it is.
  if v_payroll and v_was = 'pending' and v_status in ('approved', 'applied') then
    v_role := almailbooks.member_role(new.company_id);
    if old.data ->> 'requestedBy' = v_me and v_role is distinct from 'owner' then
      raise exception 'almail:permission Only the owner approves a pay run they sent for approval themselves.'
        using errcode = '42501';
    end if;
    if not (v_status = 'applied' and v_role = 'owner') then
      select r.data ->> 'updatedAt' into v_run
      from public.records r
      where r.company_id = new.company_id and r.tbl = 'payRuns' and r.id = old.data ->> 'subjectId';
      if v_run is distinct from (old.data -> 'after' ->> 'runUpdatedAt') then
        raise exception 'almail:invalid This pay run changed after it was sent for approval. Send it for approval again.'
          using errcode = '42501';
      end if;
    end if;
  end if;
  -- Expired only when an approver cancels a waiting request, and what it
  -- made only when it is carried out.
  if not (v_approver and v_was = 'pending' and v_status = 'cancelled') then
    new.data := almailbooks.kept_key(new.data, old.data, 'expired');
  end if;
  if not (v_approver and v_status = 'applied') then
    new.data := almailbooks.kept_key(new.data, old.data, 'resultId');
  end if;
  if v_was = 'approved' and v_status = 'applied' then
    -- Carried out as approved: the decision stays the approver's.
    new.data := new.data || jsonb_build_object(
      'decidedBy', old.data -> 'decidedBy',
      'decidedAt', old.data -> 'decidedAt',
      'decisionNote', coalesce(nullif(old.data -> 'decisionNote', 'null'::jsonb), to_jsonb(''::text))
    );
  else
    new.data := new.data || jsonb_build_object(
      'decidedBy', v_me,
      'decidedAt', v_now
    );
  end if;
  return new;
end
$$;

-- Whether the caller may delete a record. As in
-- 20261130000000_people_alerts.sql, with: items issued are never deleted
-- (they are voided instead), nor their stock movements while they stand; and
-- a sub-warehouse, a stock entry of one, or an invoice or bill that moves its
-- stock, is deleted by the owner, an admin or an accountant only.
create or replace function almailbooks.can_delete_record(p_company text, p_tbl text, p_data jsonb)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rules jsonb;
begin
  if p_tbl in ('companies', 'approvals', 'stockIssues')
    or not almailbooks.can_write_record(p_company, p_tbl, p_data) then
    return false;
  end if;
  -- A sub-warehouse and its stock entries are deleted by the owner, an
  -- admin or an accountant only.
  if p_tbl in ('warehouses', 'stockEntries') and not almailbooks.manages_warehouses(p_company) then
    return not (
      (p_tbl = 'warehouses' and almailbooks.warehouse_ruled(p_data))
      or (p_tbl = 'stockEntries' and almailbooks.entry_in_sub_warehouse(p_company, p_data))
    );
  end if;
  -- The stock movements of items issued go with them: voiding the issue
  -- takes them out. An app from before this file, which finds no source for
  -- them, deletes none while the issue stands.
  if p_tbl = 'stockMovements' and coalesce(p_data ->> 'sourceType', '') = 'issue' then
    return not exists (
      select 1
      from public.records r
      where r.company_id = p_company
        and r.tbl = 'stockIssues'
        and r.id = p_data ->> 'sourceId'
        and coalesce(r.data ->> 'status', '') = 'posted'
    );
  end if;
  -- Nor does anyone else delete an invoice or a bill that moves a
  -- sub-warehouse's stock.
  if p_tbl = 'documents'
    and not almailbooks.manages_warehouses(p_company)
    and almailbooks.sub_warehouse_lines(p_company, p_data) <> '[]'::jsonb then
    return false;
  end if;
  if p_tbl = 'employeeLetters' then
    return coalesce(p_data ->> 'status', 'draft') = 'draft'
      or not almailbooks.letters_on(p_company);
  end if;
  -- With the letters on, the People settings that hold the switch are
  -- deleted by the owner or an admin only: anyone else's delete would turn
  -- the letters off.
  if p_tbl = 'peopleSettings' then
    return coalesce(p_data ->> 'letters', '') <> 'true'
      or coalesce(almailbooks.member_role(p_company)::text, '') in ('owner', 'admin');
  end if;
  if p_tbl not in ('documents', 'payments', 'securityCheques') then
    return true;
  end if;
  v_rules := almailbooks.approval_rules(p_company);
  if v_rules is null then
    return true;
  end if;
  if p_tbl in ('payments', 'securityCheques') then
    return not (
      almailbooks.cheque_change_needs_approver(v_rules, p_tbl, p_data, null)
      and not almailbooks.is_approver(p_company)
    );
  end if;
  return not (
    almailbooks.rules_cover_document(v_rules, p_data ->> 'type')
    and coalesce(p_data ->> 'status', '') <> 'draft'
    and (
      coalesce(v_rules ->> 'voidInsteadOfDelete', '') = 'true'
      or not almailbooks.is_approver(p_company)
    )
  );
end
$$;

-- Who items can be issued to (#warehouses): the current employees' number,
-- name, job title and department, for whoever looks after a sub-warehouse
-- in use, and for the owner, the admins and the accountants (who see People
-- anyway). Nothing else of People: no salaries, payroll or documents.
create or replace function public.stock_issue_recipients(p_company text)
returns table (
  id text,
  number text,
  name text,
  name_ar text,
  job_title text,
  job_title_ar text,
  department text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if coalesce(almailbooks.member_role(p_company)::text, 'viewer') = 'viewer' or not (
    almailbooks.manages_warehouses(p_company)
    or exists (
      select 1
      from public.records w
      where w.company_id = p_company
        and w.tbl = 'warehouses'
        and coalesce(w.data ->> 'parentId', '') <> ''
        and coalesce(w.data ->> 'archived', '') <> 'true'
        and w.data -> 'keeper' ->> 'userId' = auth.uid()::text
    )
  ) then
    raise exception 'almail:permission Only whoever looks after a sub-warehouse sees who items are issued to.'
      using errcode = '42501';
  end if;
  return query
    select
      e.id,
      coalesce(e.data ->> 'number', ''),
      coalesce(e.data ->> 'name', ''),
      coalesce(e.data ->> 'nameAr', ''),
      coalesce(e.data ->> 'jobTitle', ''),
      coalesce(e.data ->> 'jobTitleAr', ''),
      coalesce(e.data ->> 'department', '')
    from public.records e
    where e.company_id = p_company
      and e.tbl = 'employees'
      and coalesce(e.data ->> 'status', 'active') <> 'left'
    order by coalesce(e.data ->> 'name', ''), e.id;
end
$$;

-- What this server has beyond the first files: as the AI assistant file
-- says, and stock_issues this one.
create or replace function public.server_features()
returns text[]
language sql
stable
set search_path = ''
as $$
  select array[
    'tables_v16', 'super_admin', 'approvals', 'cheque_approvals', 'change_feed',
    'payroll_approvals', 'document_alerts', 'employee_letters', 'staffing_costings',
    'ai_assistant', 'stock_issues'
  ]::text[]
$$;

-- Daily clean-up of deletion markers (when pg_cron is enabled) ---------------------------

-- As 20261207000000_staffing_costings.sql schedules it: once items are issued,
-- that file and the fourth can't run again, so turning pg_cron on and
-- running this file is enough.
do $$
begin
  if exists (select 1 from pg_catalog.pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'almailbooks-purge-deleted-records',
      '17 3 * * *',
      'select almailbooks.purge_all_deleted_records()'
    );
  end if;
end
$$;

-- Who may run what ------------------------------------------------------------------

revoke all on function
  almailbooks.manages_warehouses(text),
  almailbooks.warehouse_ruled(jsonb),
  almailbooks.is_sub_warehouse(text, text),
  almailbooks.entry_in_sub_warehouse(text, jsonb),
  almailbooks.sub_warehouse_lines(text, jsonb),
  almailbooks.issues_from(text, text),
  almailbooks.issue_summary(jsonb),
  almailbooks.change_kind(text, jsonb),
  almailbooks.change_details(text, text, jsonb, jsonb, boolean)
from public, anon, authenticated;
revoke all on function almailbooks.record_app(text, jsonb) from public, anon;
grant execute on function almailbooks.record_app(text, jsonb) to authenticated;
revoke all on function almailbooks.records_guard() from public, anon;
revoke all on function almailbooks.can_delete_record(text, text, jsonb) from public, anon;
grant execute on function almailbooks.can_delete_record(text, text, jsonb) to authenticated;
revoke all on function public.stock_issue_recipients(text) from public, anon;
grant execute on function public.stock_issue_recipients(text) to authenticated;
revoke all on function public.server_features() from public, anon;
grant execute on function public.server_features() to authenticated;

-- The Data API learns about the changes at once.
notify pgrst, 'reload schema';
