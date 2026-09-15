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

-- 3. Салоны тоже читают отзывы мастеров о клиентах
drop policy if exists "client_reviews_select" on public.client_reviews;
create policy "client_reviews_select" on public.client_reviews
  for select using (
    auth.uid() in (
      select id from public.profiles where role in ('master', 'salon')
    )
  );

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
