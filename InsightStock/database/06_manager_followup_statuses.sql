begin;
create or replace function public.manager_followup_statuses()
returns table (decision_id uuid, status text)
language sql stable security definer
set search_path = ''
as $$
  select f.decision_id, f.status
  from public.decision_followups f
  join public.manager_decisions d on d.id = f.decision_id
  where d.owner_id = auth.uid()
    and exists (select 1 from public.app_members m where m.user_id = auth.uid());
$$;
revoke all on function public.manager_followup_statuses() from public, anon, authenticated;
grant execute on function public.manager_followup_statuses() to authenticated;
commit;
