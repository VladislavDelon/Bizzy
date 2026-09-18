-- Bizzy — ремонтный скрипт: догоняет базу до актуальной схемы одним запуском.
-- Идемпотентно: безопасно запускать повторно и на свежей базе.
-- Запустить: Dashboard → SQL Editor → New query → вставить всё → Run.

-- 1. profiles: аватар + адрес/координаты клиента (без них сохранение
--    профиля падало с PGRST204 «Could not find the 'avatar_url' column»).
alter table public.profiles
  add column if not exists avatar_url text not null default '',
  add column if not exists address text not null default '',
  add column if not exists lat double precision,
  add column if not exists lng double precision;

-- 2. master_profiles: геокоординаты + предоплата.
alter table public.master_profiles
  add column if not exists lat double precision,
  add column if not exists lng double precision,
  add column if not exists prepay_enabled boolean not null default false,
  add column if not exists prepay_amount numeric not null default 0,
  add column if not exists prepay_link text not null default '';

-- 3. appointments: статус предоплаты + цена услуги на момент записи.
alter table public.appointments
  add column if not exists prepayment_status text not null default 'none',
  add column if not exists service_price numeric not null default 0;

alter table public.appointments
  drop constraint if exists appointments_prepayment_status_check;
alter table public.appointments
  add constraint appointments_prepayment_status_check
  check (prepayment_status in ('none', 'claimed', 'confirmed'));

-- 4. favorites: избранное клиента (без таблицы сердечки не работали).
create table if not exists public.favorites (
  id bigint generated always as identity primary key,
  client_id uuid not null references public.profiles(id) on delete cascade,
  master_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (client_id, master_id)
);

alter table public.favorites enable row level security;

drop policy if exists "favorites_select" on public.favorites;
drop policy if exists "favorites_insert" on public.favorites;
drop policy if exists "favorites_delete" on public.favorites;
create policy "favorites_select" on public.favorites
  for select using (auth.uid() = client_id);
create policy "favorites_insert" on public.favorites
  for insert with check (auth.uid() = client_id);
create policy "favorites_delete" on public.favorites
  for delete using (auth.uid() = client_id);

-- 5. Роль 'salon' и политики чтения профилей — на случай, если
--    миграция 20260922 не применялась полностью.
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check check (role in ('client', 'master', 'salon'));

drop policy if exists "profiles_select_master" on public.profiles;
create policy "profiles_select_master" on public.profiles
  for select using (role in ('master', 'salon'));

-- 6. Мастер/салон видит профили СВОИХ клиентов (имя и телефон в записях).
--    Иначе в заявках у мастера клиент отображается просто «Клиент».
drop policy if exists "profiles_select_my_clients" on public.profiles;
create policy "profiles_select_my_clients" on public.profiles
  for select using (
    exists (
      select 1 from public.appointments a
      where a.client_id = profiles.id
        and a.master_id = auth.uid()
    )
  );
