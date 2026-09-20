-- Приглашения мастеров в салон + флаг «аккаунт создан салоном».
-- Запускать целиком — идемпотентно.

-- 1. managed_by_salon: true только у мастеров, которых салон создал
--    через «Новый мастер». Для таких салон может менять логин/пароль.
--    Приглашённые/зарегистрированные по ключу — false (только «уволить»).
alter table public.master_profiles
  add column if not exists managed_by_salon boolean not null default false;

-- 2. Приглашения в команду: салон находит мастера поиском и шлёт запрос,
--    мастер подтверждает у себя.
create table if not exists public.team_invites (
  id bigint generated always as identity primary key,
  salon_id uuid not null references public.profiles(id) on delete cascade,
  master_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  unique (salon_id, master_id)
);

alter table public.team_invites enable row level security;

-- Салон управляет своими приглашениями.
drop policy if exists "ti_salon" on public.team_invites;
create policy "ti_salon" on public.team_invites
  for all using (auth.uid() = salon_id) with check (auth.uid() = salon_id);

-- Мастер читает приглашения, адресованные ему, и отвечает на них.
drop policy if exists "ti_master_read" on public.team_invites;
create policy "ti_master_read" on public.team_invites
  for select using (auth.uid() = master_id);
drop policy if exists "ti_master_update" on public.team_invites;
create policy "ti_master_update" on public.team_invites
  for update using (auth.uid() = master_id) with check (auth.uid() = master_id);
