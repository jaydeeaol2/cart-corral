-- ============================================================
-- Cart Corral — Supabase schema
-- Run this whole file once in your Supabase project's SQL Editor
-- (Dashboard → SQL Editor → New Query → paste → Run)
-- ============================================================

-- Needed for gen_random_uuid()
create extension if not exists pgcrypto;

-- Needed for distance math (ll_to_earth / earth_distance), used to:
--   1. merge duplicate reports within ~30ft of an existing pin
--   2. check a confirmer is physically near the pin
create extension if not exists cube;
create extension if not exists earthdistance;

-- ------------------------------------------------------------
-- PROFILES
-- One row per user. Created automatically on signup (see trigger below).
-- Points are never written directly by the client — only by the
-- submit_sighting()/flag_sighting() functions below.
-- ------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  points integer not null default 0,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Anyone logged in can read the leaderboard.
create policy "profiles are readable by authenticated users"
  on public.profiles for select
  to authenticated
  using (true);

-- No insert/update/delete policies for profiles on purpose.
-- All writes happen through SECURITY DEFINER functions below,
-- which run with elevated privileges and bypass this restriction
-- in a controlled way. This stops a user from editing their own
-- points from the browser console.

-- When someone signs up, auto-create their profile row from the
-- username they passed in at signup (stored in user metadata).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, username)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1))
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ------------------------------------------------------------
-- SIGHTINGS
-- A reported (or confirmed) shopping cart location.
-- status: 'unconfirmed' -> 'verified' -> (maybe) 'hidden'
-- ------------------------------------------------------------
create table if not exists public.sightings (
  id uuid primary key default gen_random_uuid(),
  lat double precision not null,
  lng double precision not null,
  reporter_id uuid not null references public.profiles(id),
  status text not null default 'unconfirmed'
    check (status in ('unconfirmed', 'verified', 'hidden')),
  note text,
  confirmed_by uuid references public.profiles(id),
  confirmed_at timestamptz,
  flag_count integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists sightings_status_idx on public.sightings(status);

alter table public.sightings enable row level security;

-- Logged-in users can see everything except hidden pins.
create policy "sightings are readable by authenticated users"
  on public.sightings for select
  to authenticated
  using (status <> 'hidden');

-- No direct insert/update policy — all writes go through
-- submit_sighting() and flag_sighting() below.

-- ------------------------------------------------------------
-- FLAGS
-- Tracks who flagged what, so the same person can't flag a pin
-- twice to fake the 3-flag auto-hide threshold.
-- ------------------------------------------------------------
create table if not exists public.flags (
  sighting_id uuid not null references public.sightings(id) on delete cascade,
  flagged_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  primary key (sighting_id, flagged_by)
);

alter table public.flags enable row level security;
-- No client policies at all — only reachable via flag_sighting() below.

-- ------------------------------------------------------------
-- FUNCTION: submit_sighting(lat, lng, note)
--
-- This single function handles BOTH "report a new cart" AND
-- "confirm an existing nearby report", which is how duplicate
-- pins get merged instead of cluttering the map:
--
--   * If there's an existing non-hidden pin within ~30ft (9.14m):
--       - if it was reported by the SAME user  -> no-op, return it
--       - if it's still 'unconfirmed'          -> mark 'verified',
--         award points to both the original reporter and this
--         confirmer (can't confirm your own pin)
--       - if it's already 'verified'           -> no-op, return it
--   * Otherwise: insert a brand new 'unconfirmed' sighting.
--
-- Points start at 0 for a bare report — nothing is awarded until
-- a second, different, physically-nearby person confirms it. That's
-- the anti-gaming rule: you can't farm points by reporting and then
-- "confirming" your own fake pins.
-- ------------------------------------------------------------
create or replace function public.submit_sighting(
  p_lat double precision,
  p_lng double precision,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing record;
  v_new_id uuid;
  v_points_on_confirm integer := 5;
begin
  if auth.uid() is null then
    raise exception 'Must be logged in';
  end if;

  select id, reporter_id, status
  into v_existing
  from public.sightings
  where status <> 'hidden'
    and earth_distance(
      ll_to_earth(lat, lng),
      ll_to_earth(p_lat, p_lng)
    ) <= 9.14  -- ~30 feet
  order by earth_distance(ll_to_earth(lat, lng), ll_to_earth(p_lat, p_lng)) asc
  limit 1;

  if found then
    if v_existing.reporter_id = auth.uid() then
      -- same person reporting near their own pin again: no-op
      return v_existing.id;
    end if;

    if v_existing.status = 'unconfirmed' then
      update public.sightings
      set status = 'verified',
          confirmed_by = auth.uid(),
          confirmed_at = now()
      where id = v_existing.id;

      update public.profiles set points = points + v_points_on_confirm
      where id = v_existing.reporter_id;

      update public.profiles set points = points + v_points_on_confirm
      where id = auth.uid();
    end if;

    return v_existing.id;
  end if;

  insert into public.sightings (lat, lng, reporter_id, note)
  values (p_lat, p_lng, auth.uid(), p_note)
  returning id into v_new_id;

  return v_new_id;
end;
$$;

grant execute on function public.submit_sighting(double precision, double precision, text) to authenticated;

-- ------------------------------------------------------------
-- FUNCTION: flag_sighting(sighting_id)
-- Any logged-in user can flag a pin once. At 3 unique flags,
-- the pin auto-hides from the map (status -> 'hidden').
-- ------------------------------------------------------------
create or replace function public.flag_sighting(p_sighting_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  if auth.uid() is null then
    raise exception 'Must be logged in';
  end if;

  insert into public.flags (sighting_id, flagged_by)
  values (p_sighting_id, auth.uid())
  on conflict do nothing;

  update public.sightings
  set flag_count = (select count(*) from public.flags where sighting_id = p_sighting_id)
  where id = p_sighting_id
  returning flag_count into v_count;

  if v_count >= 3 then
    update public.sightings set status = 'hidden' where id = p_sighting_id;
  end if;
end;
$$;

grant execute on function public.flag_sighting(uuid) to authenticated;

-- ------------------------------------------------------------
-- Done. Next steps (see README.md):
--   1. In Supabase Auth settings, make sure Email provider is on.
--   2. Copy your Project URL + anon public key into config.js.
--   3. Deploy index.html / terms.html / config.js / manifest.json
--      / sw.js / icons/ as static files (e.g. GitHub Pages).
-- ============================================================
