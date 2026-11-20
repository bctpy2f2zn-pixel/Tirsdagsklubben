-- Tirsdagsklubben: birdie-beskeder som push på telefonen
-- Kør efter schema.sql. Server-funktionen ligger i supabase/functions/birdie-push.

create extension if not exists pg_net;

-- Telefoner der vil have beskeder (én række pr. telefon/browser)
create table if not exists public.push_subs (
  endpoint text primary key,
  pid text not null,
  sub jsonb not null,
  updated_at timestamptz not null default now()
);
-- Birdies der allerede er sendt (så begge markører ikke giver to beskeder)
create table if not exists public.birdie_sent (
  rid text not null, pid text not null, hole int not null, score int,
  sent_at timestamptz not null default now(),
  primary key (rid, pid, hole)
);
-- Nøglepar til push (laves af server-funktionen første gang; den private nøgle kan kun serveren læse)
create table if not exists public.push_keys (
  id int primary key default 1 check (id = 1),
  public_key text not null,
  private_key text not null
);
alter table public.push_subs enable row level security;
alter table public.birdie_sent enable row level security;
alter table public.push_keys enable row level security;
revoke all on public.push_subs, public.birdie_sent, public.push_keys from anon, authenticated;

-- Appen gemmer/fjerner telefonens abonnement for den indloggede spiller
create or replace function public.save_push(p_sub jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare me text := public.my_pid();
begin
  if me is null or coalesce(p_sub->>'endpoint','') !~ '^https://' then raise exception 'not allowed'; end if;
  insert into push_subs(endpoint,pid,sub) values (p_sub->>'endpoint',me,p_sub)
  on conflict (endpoint) do update set pid = excluded.pid, sub = excluded.sub, updated_at = now();
end $$;
create or replace function public.delete_push(p_endpoint text) returns void
language sql security definer set search_path = public as $$
  delete from push_subs where endpoint = p_endpoint and pid = public.my_pid()
$$;
create or replace function public.push_public_key() returns text
language sql stable security definer set search_path = public as $$
  select public_key from push_keys where id = 1
$$;
revoke execute on function public.save_push(jsonb), public.delete_push(text), public.push_public_key() from public, anon;
grant execute on function public.save_push(jsonb), public.delete_push(text), public.push_public_key() to authenticated;

-- Når en score gemmes, bedes server-funktionen tjekke runden for nye birdies
create or replace function public.birdie_hook() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.path like 'rounds/%/entries/%' then
    perform net.http_post(
      url := 'https://zdjknmixpytbpuynyeel.supabase.co/functions/v1/birdie-push',
      body := jsonb_build_object('rid', split_part(new.path,'/',2)),
      headers := '{"Content-Type":"application/json"}'::jsonb);
  end if;
  return new;
end $$;
revoke execute on function public.birdie_hook() from public, anon, authenticated;
drop trigger if exists docs_birdie on public.docs;
create trigger docs_birdie after insert or update on public.docs
  for each row execute function public.birdie_hook();
