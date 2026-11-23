-- Run after 01_analysis_and_decisions.sql, as project administrator.
-- Compatible with the follow-up table created during the guided setup.
begin;
create table if not exists public.decision_followups (
    decision_id uuid primary key references public.manager_decisions(id),
    product text not null,
    sku text not null,
    action text not null,
    note text not null default '',
    responsible text not null default '',
    risk text not null,
    status text not null default 'NEW',
    created_at timestamptz not null default now(),
    notified_at timestamptz
);
alter table public.decision_followups
    add column if not exists notified_at timestamptz;
alter table public.decision_followups enable row level security;
revoke all on public.decision_followups from public, anon, authenticated;
grant usage on schema public to service_role;
grant select on public.manager_decisions to service_role;
grant select, insert on public.decision_followups to service_role;
grant update (notified_at) on public.decision_followups to service_role;
commit;
-- status NEW is a task placeholder; notification delivery uses notified_at.
-- No claim/lease or exactly-once notification guarantee is implemented.
