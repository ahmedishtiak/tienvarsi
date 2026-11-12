-- Tienvarsi: database setup for Supabase
-- Run this once: Supabase dashboard > SQL Editor > New query > paste everything > Run.
-- It is safe to run again; it only creates what is missing and refreshes the rules.

create extension if not exists pgcrypto;

-- 1. Reports: prices, updates, new places and offers sent from the site
create table if not exists public.reports (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  category    text not null check (category in ('fuel','ev','parking','wash','drive','offer')),
  place_key   text not null check (char_length(place_key) between 3 and 80),
  place_name  text check (char_length(place_name) <= 120),
  lat         double precision check (lat between 59.3 and 70.2),
  lon         double precision check (lon between 19.0 and 31.7),
  data        jsonb not null default '{}'::jsonb
              check (jsonb_typeof(data) = 'object' and pg_column_size(data) <= 4000),
  note        text check (char_length(note) <= 500),
  client_id   text not null check (char_length(client_id) between 8 and 64),
  lang        text check (lang in ('en','fi','sv')),
  constraint reports_location_chk check (category = 'offer' or (lat is not null and lon is not null))
);

create index if not exists reports_place_idx on public.reports (place_key, created_at desc);
create index if not exists reports_geo_idx   on public.reports (lat, lon);
create index if not exists reports_cat_idx   on public.reports (category, created_at desc);
create index if not exists reports_client_idx on public.reports (client_id, created_at desc);

-- 2. Votes: "Still right" (+1) / "Wrong" (-1), one vote per report per browser
create table if not exists public.votes (
  report_id  uuid not null references public.reports(id) on delete cascade,
  client_id  text not null check (char_length(client_id) between 8 and 64),
  value      smallint not null check (value in (-1, 1)),
  created_at timestamptz not null default now(),
  primary key (report_id, client_id)
);

create or replace view public.vote_totals with (security_invoker = true) as
  select report_id,
         count(*) filter (where value = 1)  as up,
         count(*) filter (where value = -1) as down
  from public.votes
  group by report_id;

-- 3. Checks on every new report: sensible numbers and a simple rate limit
create or replace function public.reports_guard() returns trigger
language plpgsql set search_path = public as $$
declare
  k text;
  v numeric;
  recent int;
begin
  -- at most 6 reports per browser in 10 minutes
  select count(*) into recent from public.reports
   where client_id = new.client_id and created_at > now() - interval '10 minutes';
  if recent >= 6 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;

  new.created_at := now();

  if new.category = 'fuel' then
    for k in select jsonb_object_keys(new.data) loop
      if k in ('e95','e98','diesel','hvo','e85','biogas') then
        v := (new.data->>k)::numeric;
        if v < 0.5 or v > 4.5 then raise exception 'bad_value:%', k using errcode = 'P0001'; end if;
      end if;
    end loop;
  elsif new.category = 'ev' then
    if new.data ? 'price_kwh' and (new.data->>'price_kwh')::numeric not between 0 and 2    then raise exception 'bad_value:price_kwh' using errcode = 'P0001'; end if;
    if new.data ? 'price_min' and (new.data->>'price_min')::numeric not between 0 and 2    then raise exception 'bad_value:price_min' using errcode = 'P0001'; end if;
    if new.data ? 'start_fee' and (new.data->>'start_fee')::numeric not between 0 and 10   then raise exception 'bad_value:start_fee' using errcode = 'P0001'; end if;
    if new.data ? 'max_kw'    and (new.data->>'max_kw')::numeric    not between 0 and 1000 then raise exception 'bad_value:max_kw'    using errcode = 'P0001'; end if;
    if new.data ? 'status' and new.data->>'status' not in ('working','broken') then raise exception 'bad_value:status' using errcode = 'P0001'; end if;
  elsif new.category = 'parking' then
    if new.data ? 'price_h' and (new.data->>'price_h')::numeric not between 0 and 30 then raise exception 'bad_value:price_h' using errcode = 'P0001'; end if;
    if new.data ? 'max_h'   and (new.data->>'max_h')::numeric   not between 0 and 72 then raise exception 'bad_value:max_h'   using errcode = 'P0001'; end if;
    if new.data ? 'fee' and new.data->>'fee' not in ('free','disc','paid') then raise exception 'bad_value:fee' using errcode = 'P0001'; end if;
  elsif new.category = 'wash' then
    if new.data ? 'price' and (new.data->>'price')::numeric not between 0 and 300 then raise exception 'bad_value:price' using errcode = 'P0001'; end if;
  elsif new.category = 'drive' then
    if new.data ? 'drive' and new.data->>'drive' not in ('yes','no') then raise exception 'bad_value:drive' using errcode = 'P0001'; end if;
  elsif new.category = 'offer' then
    if coalesce(new.data->>'brand','') = '' or coalesce(new.data->>'title','') = '' then raise exception 'bad_value:offer' using errcode = 'P0001'; end if;
    if new.data ? 'url' and new.data->>'url' !~* '^https://' then raise exception 'bad_value:url' using errcode = 'P0001'; end if;
  end if;

  return new;
end $$;

drop trigger if exists reports_guard on public.reports;
create trigger reports_guard before insert on public.reports
  for each row execute function public.reports_guard();

-- 4. Access rules: anyone can read and add; nobody can edit or delete from the site.
--    You can still delete bad reports yourself in Table Editor.
alter table public.reports enable row level security;
alter table public.votes   enable row level security;

drop policy if exists "reports are public"      on public.reports;
drop policy if exists "anyone can add a report" on public.reports;
drop policy if exists "votes are public"        on public.votes;
drop policy if exists "anyone can vote"         on public.votes;

create policy "reports are public"      on public.reports for select to anon, authenticated using (true);
create policy "anyone can add a report" on public.reports for insert to anon, authenticated with check (true);
create policy "votes are public"        on public.votes   for select to anon, authenticated using (true);
create policy "anyone can vote"         on public.votes   for insert to anon, authenticated with check (true);

grant select, insert on public.reports to anon, authenticated;
grant select, insert on public.votes   to anon, authenticated;
grant select on public.vote_totals     to anon, authenticated;
