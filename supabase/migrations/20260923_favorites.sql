-- Bizzy — избранное: клиент отмечает мастеров и салоны сердечком.
-- Запустить: Dashboard → SQL Editor → New query → вставить всё → Run.

create table if not exists public.favorites (
  id bigint generated always as identity primary key,
  client_id uuid not null references public.profiles(id) on delete cascade,
  master_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (client_id, master_id)
);

alter table public.favorites enable row level security;

-- Клиент видит и правит только свой список избранного.
drop policy if exists "favorites_select" on public.favorites;
drop policy if exists "favorites_insert" on public.favorites;
drop policy if exists "favorites_delete" on public.favorites;
create policy "favorites_select" on public.favorites
  for select using (auth.uid() = client_id);
create policy "favorites_insert" on public.favorites
  for insert with check (auth.uid() = client_id);
create policy "favorites_delete" on public.favorites
  for delete using (auth.uid() = client_id);
