begin;
create or replace function public.advance_followup_status(p_decision_id uuid, p_current_status text)
returns text language plpgsql security definer set search_path = '' as $$
declare next_status text;
begin
  next_status := case p_current_status when 'NEW' then 'IN_PROGRESS' when 'IN_PROGRESS' then 'DONE' end;
  if next_status is null then raise exception 'This status has no next step.'; end if;
  update public.decision_followups f set status = next_status
  from public.manager_decisions d
  where f.decision_id = p_decision_id and d.id = f.decision_id and d.owner_id = auth.uid()
    and exists (select 1 from public.app_members m where m.user_id = auth.uid())
    and f.status = p_current_status;
  if not found then raise exception 'Task unavailable or status changed. Reload the dashboard.'; end if;
  return next_status;
end;
$$;
revoke all on function public.advance_followup_status(uuid,text) from public, anon, authenticated;
grant execute on function public.advance_followup_status(uuid,text) to authenticated;
commit;
