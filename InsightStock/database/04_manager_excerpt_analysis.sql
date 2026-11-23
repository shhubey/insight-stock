begin;

create or replace function public.manager_excerpt_analysis()
returns table (
  snapshot_id bigint, review_id text, review_text text,
  category text, needs_human_review boolean
)
language sql stable security definer
set search_path = ''
as $function$
  select e.snapshot_id::bigint, e.review_id, e.review_text,
         latest.category, latest.needs_human_review
  from (
    select x.*, count(*) over (partition by x.review_id) as id_count
    from public.product_review_excerpts as x
  ) as e
  cross join lateral (
    select r.category, r.needs_human_review
    from public.review_ai_results as r
    where r.review_id = e.review_id
      and r.review_text = e.review_text
      and r.prompt_version = 'complaint-v2'
    order by r.created_at desc, r.response_id desc
    limit 1
  ) as latest
  where e.id_count = 1 and exists (
    select 1 from public.app_members m where m.user_id = (select auth.uid())
  );
$function$;

revoke all on function public.manager_excerpt_analysis() from public, anon, authenticated;
grant execute on function public.manager_excerpt_analysis() to authenticated;
commit;
