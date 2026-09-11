-- Bizzy — схема базы Supabase
-- Запустить один раз: Dashboard → SQL Editor → New query → вставить всё → Run.

-- ========== ПРОФИЛИ ==========
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('client', 'master')),
  name text not null default '',
  phone text not null default '',
  created_at timestamptz not null default now()
);

-- Профиль создаётся автоматически при регистрации пользователя в auth.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, role, name, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'role', 'client'),
    coalesce(new.raw_user_meta_data ->> 'name', split_part(new.email, '@', 1)),
    coalesce(new.raw_user_meta_data ->> 'phone', '')
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ========== КАТЕГОРИИ МАСТЕРОВ ==========
create table if not exists public.categories (
  id int generated always as identity primary key,
  name text not null unique
);

insert into public.categories (name) values
  ('Массажист'),
  ('Маникюр'),
  ('Педикюр'),
  ('Парикмахер'),
  ('Бровист'),
  ('Ресницы'),
  ('Косметолог'),
  ('Визажист'),
  ('Тату'),
  ('Фитнес'),
  ('Психолог'),
  ('Другое')
on conflict (name) do nothing;

-- ========== ПРОФИЛЬ МАСТЕРА ==========
create table if not exists public.master_profiles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  category text not null default 'Другое',
  description text not null default '',
  avatar_url text not null default '',
  rating_avg numeric(2,1) not null default 0,
  rating_count int not null default 0,
  created_at timestamptz not null default now()
);

-- ========== УСЛУГИ МАСТЕРА (облако) ==========
create table if not exists public.services (
  id bigint generated always as identity primary key,
  master_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  price numeric not null default 0,
  duration_minutes int not null default 60,
  published boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ========== КЛИЕНТЫ МАСТЕРА (облако) ==========
create table if not exists public.master_clients (
  id bigint generated always as identity primary key,
  master_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  phone text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ========== ЗАПИСИ (бронирования) ==========
create table if not exists public.appointments (
  id bigint generated always as identity primary key,
  client_id uuid not null references public.profiles(id) on delete cascade,
  master_id uuid not null references public.profiles(id) on delete cascade,
  service_id bigint references public.services(id) on delete set null,
  service_name text not null,
  starts_at timestamptz not null,
  duration_minutes int not null default 60,
  status text not null default 'pending'
    check (status in ('pending', 'confirmed', 'cancelled', 'completed')),
  notes text not null default '',
  created_at timestamptz not null default now()
);

-- ========== ЗАПИСИ, СОЗДАННЫЕ МАСТЕРОМ ==========
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

-- ========== РЕЙТИНГИ ==========
create table if not exists public.ratings (
  id bigint generated always as identity primary key,
  appointment_id bigint not null references public.appointments(id) on delete cascade,
  client_id uuid not null references public.profiles(id) on delete cascade,
  master_id uuid not null references public.profiles(id) on delete cascade,
  rating int not null check (rating between 1 and 5),
  comment text not null default '',
  created_at timestamptz not null default now(),
  unique (appointment_id)
);

-- Автоматический пересчёт среднего рейтинга мастера.
create or replace function public.update_master_rating()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  update public.master_profiles m
  set rating_avg = coalesce((
        select round(avg(rating)::numeric, 1)
        from public.ratings
        where master_id = coalesce(new.master_id, old.master_id)
      ), 0),
      rating_count = (
        select count(*)
        from public.ratings
        where master_id = coalesce(new.master_id, old.master_id)
      )
  where m.user_id = coalesce(new.master_id, old.master_id);
  return coalesce(new, old);
end;
$$;

drop trigger if exists ratings_update_master on public.ratings;
create trigger ratings_update_master
  after insert or update or delete on public.ratings
  for each row execute function public.update_master_rating();

-- ========== RLS: включаем ==========
alter table public.profiles        enable row level security;
alter table public.categories      enable row level security;
alter table public.master_profiles enable row level security;
alter table public.services        enable row level security;
alter table public.appointments    enable row level security;
alter table public.ratings         enable row level security;

-- profiles: свой профиль видит владелец; мастера видны всем (для каталога).
drop policy if exists "profiles_select_own"    on public.profiles;
drop policy if exists "profiles_select_master" on public.profiles;
drop policy if exists "profiles_update_own"    on public.profiles;
create policy "profiles_select_own"    on public.profiles
  for select using (auth.uid() = id);
create policy "profiles_select_master" on public.profiles
  for select using (role = 'master');
create policy "profiles_update_own"    on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

alter table public.master_clients enable row level security;

-- categories: читают все авторизованные.
drop policy if exists "categories_select" on public.categories;
create policy "categories_select" on public.categories
  for select using (auth.uid() is not null);

-- master_profiles: читают все, пишет только владелец.
drop policy if exists "mp_select"   on public.master_profiles;
drop policy if exists "mp_insert"   on public.master_profiles;
drop policy if exists "mp_update"   on public.master_profiles;
create policy "mp_select" on public.master_profiles
  for select using (auth.uid() is not null);
create policy "mp_insert" on public.master_profiles
  for insert with check (auth.uid() = user_id);
create policy "mp_update" on public.master_profiles
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- services: читают все, пишет только мастер-владелец.
drop policy if exists "services_select" on public.services;
drop policy if exists "services_write"  on public.services;
create policy "services_select" on public.services
  for select using (auth.uid() is not null);
create policy "services_write" on public.services
  for all using (auth.uid() = master_id) with check (auth.uid() = master_id);

-- master_clients: читает и пишет только мастер-владелец.
drop policy if exists "master_clients_select" on public.master_clients;
drop policy if exists "master_clients_write"  on public.master_clients;
create policy "master_clients_select" on public.master_clients
  for select using (auth.uid() = master_id);
create policy "master_clients_write" on public.master_clients
  for all using (auth.uid() = master_id) with check (auth.uid() = master_id);

-- appointments: свои записи видят и клиент, и мастер.
drop policy if exists "appt_select" on public.appointments;
drop policy if exists "appt_insert" on public.appointments;
drop policy if exists "appt_update" on public.appointments;
drop policy if exists "appt_delete" on public.appointments;
create policy "appt_select" on public.appointments
  for select using (auth.uid() = client_id or auth.uid() = master_id);
create policy "appt_insert" on public.appointments
  for insert with check (auth.uid() = client_id);
create policy "appt_update" on public.appointments
  for update using (auth.uid() = client_id or auth.uid() = master_id);
create policy "appt_delete" on public.appointments
  for delete using (auth.uid() = client_id);

alter table public.master_appointments enable row level security;

-- master_appointments: видит и пишет только мастер-владелец.
drop policy if exists "master_appt_select" on public.master_appointments;
drop policy if exists "master_appt_write"  on public.master_appointments;
create policy "master_appt_select" on public.master_appointments
  for select using (auth.uid() = master_id);
create policy "master_appt_write" on public.master_appointments
  for all using (auth.uid() = master_id) with check (auth.uid() = master_id);

-- ratings: читают все, пишет клиент только по своей записи.
drop policy if exists "ratings_select" on public.ratings;
drop policy if exists "ratings_insert" on public.ratings;
drop policy if exists "ratings_update" on public.ratings;
drop policy if exists "ratings_delete" on public.ratings;
create policy "ratings_select" on public.ratings
  for select using (auth.uid() is not null);
create policy "ratings_insert" on public.ratings
  for insert with check (
    auth.uid() = client_id
    and exists (
      select 1 from public.appointments a
      where a.id = appointment_id
        and a.client_id = auth.uid()
    )
  );
create policy "ratings_update" on public.ratings
  for update using (auth.uid() = client_id) with check (auth.uid() = client_id);
create policy "ratings_delete" on public.ratings
  for delete using (auth.uid() = client_id);

-- ========== УДАЛЕНИЕ АККАУНТА ==========
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  delete from auth.users where id = auth.uid();
end;
$$;

grant execute on function public.delete_my_account() to authenticated;

-- ========== АВАТАРЫ МАСТЕРОВ ==========
-- Колонка уже может быть создана выше в master_profiles, но на всякий случай:
alter table public.master_profiles add column if not exists avatar_url text not null default '';

-- Публичный bucket для аватаров.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = true;

drop policy if exists "avatars_select_public" on storage.objects;
create policy "avatars_select_public"
  on storage.objects for select
  using (bucket_id = 'avatars');

drop policy if exists "avatars_insert_own" on storage.objects;
create policy "avatars_insert_own"
  on storage.objects for insert
  with check (
    bucket_id = 'avatars'
    and coalesce((storage.foldername(name))[1], '') = auth.uid()::text
  );

drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own"
  on storage.objects for update
  using (
    bucket_id = 'avatars'
    and coalesce((storage.foldername(name))[1], '') = auth.uid()::text
  );

drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own"
  on storage.objects for delete
  using (
    bucket_id = 'avatars'
    and coalesce((storage.foldername(name))[1], '') = auth.uid()::text
  );
