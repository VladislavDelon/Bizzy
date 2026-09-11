-- Двусторонняя синхронизация услуг и клиентов между устройствами мастера.

-- Добавляем updated_at к услугам, если ещё нет.
alter table public.services add column if not exists updated_at timestamptz not null default now();

-- Таблица клиентов мастера для синхронизации между устройствами.
create table if not exists public.master_clients (
  id bigint generated always as identity primary key,
  master_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  phone text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.master_clients enable row level security;

drop policy if exists "master_clients_select" on public.master_clients;
drop policy if exists "master_clients_write"  on public.master_clients;
create policy "master_clients_select" on public.master_clients
  for select using (auth.uid() = master_id);
create policy "master_clients_write" on public.master_clients
  for all using (auth.uid() = master_id) with check (auth.uid() = master_id);

-- Таблица собственных записей мастера для синхронизации между устройствами.
create table if not exists public.master_appointments (
  id bigint generated always as identity primary key,
  master_id uuid not null references public.profiles(id) on delete cascade,
  client_name text not null default '',
  client_phone text not null default '',
  service_name text not null default '',
  master_name text not null default '',
  starts_at timestamptz not null,
  duration_minutes int not null default 60,
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.master_appointments enable row level security;

drop policy if exists "master_appt_select" on public.master_appointments;
drop policy if exists "master_appt_write"  on public.master_appointments;
create policy "master_appt_select" on public.master_appointments
  for select using (auth.uid() = master_id);
create policy "master_appt_write" on public.master_appointments
  for all using (auth.uid() = master_id) with check (auth.uid() = master_id);
