begin;
create table if not exists public.review_ai_results (
  response_id text primary key,
  review_id text not null check (length(btrim(review_id)) > 0),
  review_text text not null check (length(btrim(review_text)) > 0),
  category text not null check (category in ('FIT_SIZE','QUALITY_DEFECT','DESCRIPTION_MISMATCH','DELIVERY','NO_COMPLAINT','UNCLEAR')),
  evidence text not null,
  explanation text not null check (length(btrim(explanation)) > 0),
  model text not null,
  prompt_version text not null,
  needs_human_review boolean not null default true,
  created_at timestamptz not null default now(),
  check ((evidence = '' and category in ('NO_COMPLAINT','UNCLEAR'))
         or (length(btrim(evidence)) > 0 and position(evidence in review_text) > 0))
);
alter table public.review_ai_results enable row level security;
revoke all on public.review_ai_results from public, anon, authenticated;
grant select, insert on public.review_ai_results to service_role;

create or replace view public.product_review_excerpts with (security_invoker = true) as
select p.id as snapshot_id, p.record_id, p.sku, p.record_id || '-EX' || e.slot as review_id, e.review_text, p.source
from public.product_snapshots_raw p
cross join lateral (values ('1', p.review_excerpt_1), ('2', p.review_excerpt_2)) as e(slot,review_text)
where nullif(btrim(e.review_text),'') is not null;

create or replace view public.pending_product_review_excerpts with (security_invoker = true) as
select e.* from public.product_review_excerpts e
where not exists (
  select 1 from public.review_ai_results r
  where r.review_id=e.review_id and r.review_text=e.review_text and r.prompt_version='complaint-v2'
);
revoke all on public.product_review_excerpts, public.pending_product_review_excerpts from public, anon, authenticated;
grant select on public.product_review_excerpts, public.pending_product_review_excerpts to service_role;
grant select (id,record_id,sku,review_excerpt_1,review_excerpt_2,source) on public.product_snapshots_raw to service_role;
commit;
