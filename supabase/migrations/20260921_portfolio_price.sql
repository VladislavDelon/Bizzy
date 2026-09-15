-- Портфолио мастера + снимок цены записи.

-- ========== ПОРТФОЛИО МАСТЕРА ==========
create table if not exists public.master_portfolio (
  id bigint generated always as identity primary key,
  master_id uuid not null references public.profiles(id) on delete cascade,
  image_url text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.master_portfolio enable row level security;

drop policy if exists "master_portfolio_select" on public.master_portfolio;
create policy "master_portfolio_select" on public.master_portfolio
  for select using (auth.uid() is not null);

drop policy if exists "master_portfolio_insert" on public.master_portfolio;
create policy "master_portfolio_insert" on public.master_portfolio
  for insert with check (auth.uid() = master_id);

drop policy if exists "master_portfolio_delete" on public.master_portfolio;
create policy "master_portfolio_delete" on public.master_portfolio
  for delete using (auth.uid() = master_id);

-- Файлы лежат в существующем публичном bucket `avatars`
-- по пути <master_id>/portfolio/<file>.jpg — политики
-- avatars_insert_own/avatars_delete_own уже покрывают эту папку.

-- ========== СНИМОК ЦЕНЫ ЗАПИСИ ==========
alter table public.appointments
  add column if not exists service_price numeric not null default 0;

alter table public.master_appointments
  add column if not exists service_price numeric not null default 0;
