-- Bizzy — роль «salon» + геоданные (адрес/координаты) для поиска мастеров рядом.
-- Запустить: Dashboard → SQL Editor → New query → вставить всё → Run.

-- 1. Разрешаем роль 'salon' в profiles.role
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check check (role in ('client', 'master', 'salon'));

-- 2. Салоны видны клиентам в каталоге наравне с мастерами
drop policy if exists "profiles_select_master" on public.profiles;
create policy "profiles_select_master" on public.profiles
  for select using (role in ('master', 'salon'));

-- 3. Отзывы мастеров о клиентах: таблица могла отсутствовать в старой базе —
--    создаём при необходимости; салоны читают наравне с мастерами.
create table if not exists public.client_reviews (
  id bigint generated always as identity primary key,
  client_id uuid not null references public.profiles(id) on delete cascade,
  master_id uuid not null references public.profiles(id) on delete cascade,
  booking_id bigint not null references public.appointments(id) on delete cascade,
  rating int not null check (rating between 1 and 5),
  comment text not null default '',
  created_at timestamptz not null default now(),
  unique (client_id, master_id, booking_id)
);

alter table public.client_reviews enable row level security;

drop policy if exists "client_reviews_select" on public.client_reviews;
drop policy if exists "client_reviews_insert" on public.client_reviews;
drop policy if exists "client_reviews_update" on public.client_reviews;
drop policy if exists "client_reviews_delete" on public.client_reviews;

create policy "client_reviews_select" on public.client_reviews
  for select using (
    auth.uid() in (
      select id from public.profiles where role in ('master', 'salon')
    )
  );
create policy "client_reviews_insert" on public.client_reviews
  for insert with check (
    auth.uid() = master_id
    and exists (
      select 1 from public.appointments a
      where a.id = booking_id
        and a.master_id = auth.uid()
        and a.client_id = client_id
    )
  );
create policy "client_reviews_update" on public.client_reviews
  for update using (auth.uid() = master_id) with check (auth.uid() = master_id);
create policy "client_reviews_delete" on public.client_reviews
  for delete using (auth.uid() = master_id);

-- 4. Адрес и координаты клиента (для рекомендаций «рядом»).
--    lat/lng пишет/читает только владелец профиля — в каталог они не попадают.
alter table public.profiles
  add column if not exists address text not null default '',
  add column if not exists lat double precision,
  add column if not exists lng double precision;

-- 5. Координаты мастера/салона — геокодятся из master_profiles.address
--    или выбираются точкой на карте.
alter table public.master_profiles
  add column if not exists lat double precision,
  add column if not exists lng double precision;
