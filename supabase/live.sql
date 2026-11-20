-- "Se med"-link (?se=1): gæster kan følge Live uden login.
-- Returnerer kun den aktive (ellers seneste) runde, dens indtastninger, spillernes navn/handicap, baner og ture.
create or replace function public.live_snapshot() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rid text; rdata jsonb; res jsonb;
begin
  select split_part(path,'/',2), data into rid, rdata from docs
   where path ~ '^rounds/[^/]+$'
   order by (data->>'status'='live') desc, split_part(path,'/',2) desc limit 1;
  if rid is null then return jsonb_build_object('rounds','{}'::jsonb); end if;
  select jsonb_build_object(
    'rounds', jsonb_build_object(rid, rdata),
    'entries', jsonb_build_object(rid, coalesce((select jsonb_object_agg(split_part(path,'/',4), data) from docs where path like 'rounds/'||rid||'/entries/%'),'{}'::jsonb)),
    'players', coalesce((select jsonb_object_agg(split_part(path,'/',2), jsonb_build_object('name',data->'name','hi',data->'hi','guest',data->'guest'))
                from docs where path ~ '^players/[^/]+$' and split_part(path,'/',2) in (select jsonb_array_elements_text(coalesce(rdata->'players','[]'::jsonb)))),'{}'::jsonb),
    'courses', coalesce((select jsonb_object_agg(split_part(path,'/',2), data) from docs where path ~ '^courses/[^/]+$'),'{}'::jsonb),
    'trips', coalesce((select data from docs where path='config/trips'),'{}'::jsonb)
  ) into res;
  return res;
end $$;
revoke all on function public.live_snapshot() from public;
grant execute on function public.live_snapshot() to anon, authenticated;
