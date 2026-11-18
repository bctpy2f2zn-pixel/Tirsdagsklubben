-- Tirsdagsklubben: database og adgangsregler (Supabase / Postgres)
-- Alt app-data ligger i "docs" som (path, data). Stierne er de samme som i testversionen:
--   players/<pid>, logins/<pid>, config/<id>, courses/<id>, rounds/<dato>,
--   rounds/<dato>/entries/<pid>, signups/<dato>/entries/<pid|g-id>

create table if not exists public.docs (
  path text primary key check (path ~ '^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$'),
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create table if not exists public.admins (pid text primary key);

alter table public.docs enable row level security;
alter table public.admins enable row level security;

-- Spiller-id for den indloggede bruger (fra logins/<pid>.uid)
create or replace function public.my_pid() returns text
language sql stable security definer set search_path = public as $$
  select split_part(path,'/',2) from docs
  where path like 'logins/%' and data->>'uid' = auth.uid()::text limit 1
$$;
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from admins where pid = public.my_pid())
$$;

-- Må den indloggede bruger skrive dette dokument? op: i(nsert), u(pdate), d(elete)
create or replace function public.can_write(p_path text, p_data jsonb, p_op text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare seg text[] := string_to_array(p_path,'/'); me text := public.my_pid(); n int := array_length(seg,1);
begin
  if auth.uid() is null then return false; end if;
  if public.is_admin() then return true; end if;
  -- Første gang: vælg et ledigt navn (kun ét pr. login)
  if seg[1]='logins' and n=2 then
    if p_op='i' then
      return me is null and p_data->>'uid' = auth.uid()::text
        and exists(select 1 from docs where path='players/'||seg[2])
        and not exists(select 1 from docs where path=p_path);
    elsif p_op='u' then
      return seg[2]=me and p_data->>'uid' = auth.uid()::text;
    end if;
    return false;
  end if;
  if me is null then return false; end if;
  -- Egne spillerdata (navn, handicap, tee), men ikke admin-flaget
  if seg[1]='players' and n=2 and p_op='u' then
    return seg[2]=me and coalesce((p_data->>'admin')::boolean,false)=false;
  end if;
  -- Scorer: kun ens eget indtastningsark
  if seg[1]='rounds' and n=4 and seg[3]='entries' then
    return seg[4]=me and p_op in ('i','u');
  end if;
  -- Tilmelding: sig selv, eller egne gæster
  if seg[1]='signups' and n=4 and seg[3]='entries' then
    return seg[4]=me or (coalesce((p_data->>'guest')::boolean,false) and p_data->>'by'=me);
  end if;
  return false;
end $$;

drop policy if exists docs_read on public.docs;
drop policy if exists docs_ins on public.docs;
drop policy if exists docs_upd on public.docs;
drop policy if exists docs_del on public.docs;
create policy docs_read on public.docs for select to authenticated using (true);
create policy docs_ins on public.docs for insert to authenticated with check (public.can_write(path,data,'i'));
create policy docs_upd on public.docs for update to authenticated using (public.can_write(path,data,'u')) with check (public.can_write(path,data,'u'));
create policy docs_del on public.docs for delete to authenticated using (public.can_write(path,data,'d'));

drop policy if exists admins_read on public.admins;
create policy admins_read on public.admins for select to authenticated using (true);

-- Flet felter ind i et dokument (som Firestore update): data || patch. Kører med brugerens rettigheder.
create or replace function public.patch_doc(p_path text, p_patch jsonb) returns jsonb
language plpgsql security invoker set search_path = public as $$
declare res jsonb;
begin
  update docs set data = data || p_patch, updated_at = now() where path = p_path returning data into res;
  if res is null then
    insert into docs(path,data) values (p_path,p_patch) returning data into res;
  end if;
  return res;
end $$;

create or replace function public.touch() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;
drop trigger if exists docs_touch on public.docs;
create trigger docs_touch before update on public.docs for each row execute function public.touch();

-- Live-opdateringer
alter table public.docs replica identity full;
do $$ begin
  alter publication supabase_realtime add table public.docs;
exception when duplicate_object then null; end $$;

-- Administrator
insert into public.admins(pid) values ('kim-holtum') on conflict do nothing;
