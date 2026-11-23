-- 1. Create a confirmed manager user under Authentication > Users.
-- 2. Replace REPLACE_WITH_YOUR_EMAIL below with that user's email.
-- 3. Run this whole file as the project administrator in SQL Editor.
-- Includes the final analysis views, so it also works if the previous SQL file
-- has not been run. Source rows and existing decisions are not deleted.
begin;
set local app.owner_email = 'REPLACE_WITH_YOUR_EMAIL';

alter table public.product_snapshots_raw enable row level security;

create or replace view public.product_snapshot_checks
with (security_invoker = true) as
with duplicates as (
    select r.*,
        count(*) over (partition by snapshot_date, record_id) as record_copies,
        count(*) over (partition by snapshot_date, upper(btrim(sku))) as sku_copies
    from public.product_snapshots_raw r
), history_checks as (
    select d.*,
        case
            when record_id is null or btrim(record_id) = '' then 'MISSING_RECORD_ID'
            when sku is null or btrim(sku) = ''
                or return_sku is null or btrim(return_sku) = '' then 'MISSING_SKU'
            when record_copies > 1 or sku_copies > 1 then 'DUPLICATE_SNAPSHOT'
            when sold_eligible_90d is null then 'MISSING_SALES'
            when sold_eligible_90d <= 0 then 'INVALID_SALES'
            when returned_in_30d_window is null then 'MISSING_RETURNS'
            when returned_in_30d_window < 0
                or returned_in_30d_window > sold_eligible_90d then 'INVALID_RETURN_COUNT'
            when btrim(sku) <> btrim(return_sku) then 'SKU_MISMATCH'
            when cohort_start_date is null or cohort_end_date is null
                or snapshot_date is null or return_window_days is null then 'MISSING_DATES_OR_WINDOW'
            when not isfinite(cohort_start_date) or not isfinite(cohort_end_date)
                or not isfinite(snapshot_date) then 'INVALID_DATES'
            when return_window_days <> 30 then 'UNSUPPORTED_RETURN_WINDOW'
            when cohort_end_date - cohort_start_date + 1 <> 90 then 'INVALID_COHORT_PERIOD'
            when cohort_end_date + return_window_days > snapshot_date then 'RETURN_WINDOW_OPEN'
            else 'VALID_HISTORY'
        end as history_status,
        case
            when total_reviews is null or negative_review_mentions is null then false
            when total_reviews < 0 or negative_review_mentions < 0
                or negative_review_mentions > total_reviews then false
            when review_start_date is null or review_end_date is null
                or snapshot_date is null then false
            when not isfinite(review_start_date) or not isfinite(review_end_date)
                or not isfinite(snapshot_date) then false
            when review_start_date > review_end_date or review_end_date > snapshot_date then false
            else true
        end as review_inputs_valid
    from duplicates d
)
select h.*,
    case
        when history_status <> 'VALID_HISTORY' then history_status
        when not review_inputs_valid then 'INVALID_REVIEW_DATA'
        when stock_on_hand is null or stock_on_hand < 0 then 'INVALID_STOCK'
        when sold_eligible_90d < 20 then 'SMALL_SAMPLE'
        else 'READY'
    end as review_status,
    case when history_status = 'VALID_HISTORY'
        then round(100.0 * returned_in_30d_window / nullif(sold_eligible_90d, 0), 1)
        else null
    end as historical_return_rate_pct,
    case when review_inputs_valid and total_reviews > 0
        then round(100.0 * negative_review_mentions / nullif(total_reviews, 0), 1)
        else null
    end as complaint_share_pct
from history_checks h;

create or replace view public.manager_review_queue
with (security_invoker = true) as
select c.*,
    case
        when review_status <> 'READY' then 'NOT SCORED'
        when 1.0 * returned_in_30d_window / nullif(sold_eligible_90d, 0) >= 0.20
            or (
                1.0 * returned_in_30d_window / nullif(sold_eligible_90d, 0) >= 0.10
                and 1.0 * negative_review_mentions / nullif(total_reviews, 0) >= 0.25
                and negative_review_mentions >= 5
            ) then 'HIGH'
        when 1.0 * returned_in_30d_window / nullif(sold_eligible_90d, 0) >= 0.10
            or (
                1.0 * negative_review_mentions / nullif(total_reviews, 0) >= 0.20
                and negative_review_mentions >= 5
            ) then 'MEDIUM'
        else 'LOW'
    end as risk_category,
    case when review_inputs_valid and negative_review_mentions >= 5
        and 1.0 * negative_review_mentions / nullif(total_reviews, 0) >= 0.20
        then true else false
    end as complaint_warning,
    'DEMO-RETURN-RULES-v1'::text as rule_version,
    md5(to_jsonb(c)::text || 'DEMO-RETURN-RULES-v1') as input_fingerprint
from public.product_snapshot_checks c;

-- Views inherit the underlying table's RLS. No client access is granted here.
-- An explicit owner login policy will be added in the connection step.
revoke all on public.product_snapshot_checks from public, anon, authenticated;
revoke all on public.manager_review_queue from public, anon, authenticated;

comment on view public.product_snapshot_checks is
    'Synthetic aggregate snapshots: separate historical validity, assessment eligibility, and review evidence. First blocking reason only. Duplicates are checked within snapshot_date; corrections require an explicit versioning/import strategy.';
comment on view public.manager_review_queue is
    'Illustrative rule categories, not validated predictions. No calibrated confidence. Stock affects exposure, not the category. Requires explicit owner access before frontend use.';

-- This file is included in 01_connect_supabase.sql by the build script.
-- Access is limited to accounts explicitly enabled by the project administrator.

create table if not exists public.app_members (
    user_id uuid primary key references auth.users(id) on delete cascade,
    enabled_at timestamptz not null default now()
);
alter table public.app_members enable row level security;
revoke all on public.app_members from public, anon, authenticated;
grant select on public.app_members to authenticated;
drop policy if exists "members_read_own_membership" on public.app_members;
create policy "members_read_own_membership" on public.app_members
    for select to authenticated using (user_id = (select auth.uid()));

-- Only an administrator can change this allowlist. Client signups do not grant access.
do $$
begin
    if current_setting('app.owner_email', true) is null
       or position('@' in current_setting('app.owner_email')) = 0 then
        raise exception 'Replace REPLACE_WITH_YOUR_EMAIL at the top with the email of your manager Auth user.';
    end if;
    if not exists (
        select 1 from auth.users
        where lower(email) = lower(current_setting('app.owner_email'))
          and email_confirmed_at is not null and is_anonymous is not true
    ) then
        raise exception 'Create and confirm this email under Authentication > Users first, then rerun this file.';
    end if;
    insert into public.app_members(user_id)
    select id from auth.users
    where lower(email) = lower(current_setting('app.owner_email'))
      and email_confirmed_at is not null and is_anonymous is not true
    on conflict (user_id) do nothing;
end;
$$;

revoke all on public.product_snapshots_raw from public, anon, authenticated;
grant select on public.product_snapshots_raw to authenticated;
drop policy if exists "enabled_managers_read_snapshots" on public.product_snapshots_raw;
create policy "enabled_managers_read_snapshots" on public.product_snapshots_raw
    for select to authenticated using (
        exists (select 1 from public.app_members where user_id = (select auth.uid()))
    );

-- Add a deterministic input-version identifier to the analysis layer.
-- This is an idempotency/version token, not a password or integrity signature.
create or replace view public.manager_review_queue
with (security_invoker = true) as
select c.*,
    case
        when review_status <> 'READY' then 'NOT SCORED'
        when 1.0 * returned_in_30d_window / nullif(sold_eligible_90d, 0) >= 0.20
            or (1.0 * returned_in_30d_window / nullif(sold_eligible_90d, 0) >= 0.10
                and 1.0 * negative_review_mentions / nullif(total_reviews, 0) >= 0.25
                and negative_review_mentions >= 5) then 'HIGH'
        when 1.0 * returned_in_30d_window / nullif(sold_eligible_90d, 0) >= 0.10
            or (1.0 * negative_review_mentions / nullif(total_reviews, 0) >= 0.20
                and negative_review_mentions >= 5) then 'MEDIUM'
        else 'LOW'
    end as risk_category,
    case when review_inputs_valid and negative_review_mentions >= 5
        and 1.0 * negative_review_mentions / nullif(total_reviews, 0) >= 0.20
        then true else false
    end as complaint_warning,
    'DEMO-RETURN-RULES-v1'::text as rule_version,
    md5(to_jsonb(c)::text || 'DEMO-RETURN-RULES-v1') as input_fingerprint
from public.product_snapshot_checks c;

revoke all on public.product_snapshot_checks, public.manager_review_queue from public, anon, authenticated;
grant select on public.product_snapshot_checks, public.manager_review_queue to authenticated;

create table if not exists public.manager_decisions (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
    snapshot_id bigint not null references public.product_snapshots_raw(id) on delete restrict,
    input_fingerprint text not null,
    rule_version text not null,
    input_snapshot jsonb not null,
    assessment jsonb not null,
    action text not null check (action in (
        'Investigate product issue', 'Review evidence / monitor', 'Monitor only',
        'Request data / fix records', 'No action yet'
    )),
    note text not null default '' check (char_length(note) <= 500),
    responsible text not null default '' check (responsible in (
        '', 'Inventory manager', 'E-commerce manager', 'Customer service team', 'Quality / supplier team'
    )),
    created_at timestamptz not null default now(),
    constraint one_decision_per_input_version unique (owner_id, snapshot_id, input_fingerprint, rule_version)
);
alter table public.manager_decisions enable row level security;
revoke all on public.manager_decisions from public, anon, authenticated;
grant select, insert on public.manager_decisions to authenticated;
-- Explicit backend read access for n8n; secret keys still need table grants.
grant select on public.manager_decisions to service_role;
drop policy if exists "managers_read_own_decisions" on public.manager_decisions;
drop policy if exists "managers_insert_own_decisions" on public.manager_decisions;
create policy "managers_read_own_decisions" on public.manager_decisions
    for select to authenticated using (
        owner_id = (select auth.uid())
        and exists (select 1 from public.app_members where user_id = (select auth.uid()))
    );
create policy "managers_insert_own_decisions" on public.manager_decisions
    for insert to authenticated with check (
        owner_id = (select auth.uid())
        and exists (select 1 from public.app_members where user_id = (select auth.uid()))
    );

create or replace function public.capture_manager_decision()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
    evidence jsonb;
    inputs jsonb;
    suggested_action text;
begin
    if auth.uid() is null or new.owner_id is distinct from auth.uid() then
        raise exception 'Sign in with an enabled manager account.' using errcode = '42501';
    end if;
    if not exists (select 1 from public.app_members where user_id = auth.uid()) then
        raise exception 'This manager account has not been enabled.' using errcode = '42501';
    end if;
    -- Lock the source row so a concurrent input edit cannot change the evidence
    -- between validation and the insertion of this decision.
    select to_jsonb(r) into inputs from public.product_snapshots_raw r
    where r.id = new.snapshot_id for share;
    if inputs is null then
        raise exception 'Snapshot is unavailable. Reload the product queue.' using errcode = '42501';
    end if;
    select to_jsonb(q) into evidence from public.manager_review_queue q where q.id = new.snapshot_id;
    if evidence is null then
        raise exception 'Assessment is unavailable. Reload the product queue.' using errcode = '42501';
    end if;
    if new.input_fingerprint is distinct from evidence->>'input_fingerprint'
        or new.rule_version is distinct from evidence->>'rule_version' then
        raise exception 'Product inputs changed. Reload the queue and review the updated evidence.' using errcode = '40001';
    end if;
    suggested_action := case evidence->>'risk_category'
        when 'HIGH' then 'Investigate product issue'
        when 'MEDIUM' then 'Review evidence / monitor'
        when 'LOW' then 'Monitor only'
        else 'Request data / fix records' end;
    new.note := btrim(coalesce(new.note, ''));
    if new.action is distinct from suggested_action and new.note = '' then
        raise exception 'An override requires a reason.' using errcode = '23514';
    end if;
    -- The server captures these fields; the browser cannot forge assessment evidence.
    new.input_snapshot := inputs;
    new.assessment := evidence;
    new.created_at := clock_timestamp();
    return new;
end;
$$;
revoke all on function public.capture_manager_decision() from public, anon, authenticated;
drop trigger if exists capture_manager_decision on public.manager_decisions;
create trigger capture_manager_decision before insert on public.manager_decisions
    for each row execute function public.capture_manager_decision();

comment on table public.manager_decisions is
    'Append-only manager decisions with server-captured input and assessment evidence; retries for the same owner, snapshot, input version, and rule version do not create duplicate decisions. No automated purchasing or notifications.';

commit;
select record_id, product, review_status, historical_return_rate_pct, risk_category
from public.manager_review_queue order by record_id;
