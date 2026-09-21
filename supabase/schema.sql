-- Bizzy — схема базы Supabase
-- Запустить один раз: Dashboard → SQL Editor → New query → вставить всё → Run.

-- ========== ПРОФИЛИ ==========
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('client', 'master', 'salon')),
  name text not null default '',
  phone text not null default '',
  avatar_url text not null default '',
  address text not null default '',
  lat double precision,
  lng double precision,
  -- Клиент сам решает, виден ли его номер мастерам.
  phone_public boolean not null default true,
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
  address text not null default '',
  lat double precision,
  lng double precision,
  social text not null default '',
  phone_public boolean not null default false,
  rating_avg numeric(2,1) not null default 0,
  rating_count int not null default 0,
  -- Предоплата: мастер/салон включает приём оплаты до записи.
  prepay_enabled boolean not null default false,
  prepay_amount numeric not null default 0,
  prepay_link text not null default '',
  -- Салонная команда: мастер привязан к салону; у салона — ключ регистрации
  -- мастеров и флаг автоназначения заявок.
  salon_id uuid references public.profiles(id) on delete set null,
  salon_key text,
  auto_assign boolean not null default false,
  -- true у мастеров, которых салон создал через «Новый мастер» —
  -- только им салон может менять логин/пароль.
  managed_by_salon boolean not null default false,
  -- Когда мастер вступил в текущий салон. Салону видны только
  -- записи, созданные ПОСЛЕ вступления — личная история мастера
  -- до трудоустройства скрыта. NULL у привязанных до появления
  -- колонки = показывать всё (обратная совместимость).
  salon_since timestamptz,
  created_at timestamptz not null default now()
);

create unique index if not exists master_profiles_salon_key_uidx
  on public.master_profiles (salon_key)
  where salon_key is not null;

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

-- ========== FCM-ТОКЕНЫ ДЛЯ PUSH ==========
create table if not exists public.fcm_tokens (
  user_id uuid not null references public.profiles(id) on delete cascade,
  token text not null,
  platform text not null default 'other',
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);

alter table public.fcm_tokens enable row level security;

drop policy if exists "fcm_tokens_select" on public.fcm_tokens;
drop policy if exists "fcm_tokens_write"  on public.fcm_tokens;
create policy "fcm_tokens_select" on public.fcm_tokens
  for select using (auth.uid() = user_id);
create policy "fcm_tokens_write" on public.fcm_tokens
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

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
  prepayment_status text not null default 'none'
    check (prepayment_status in ('none', 'claimed', 'confirmed')),
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
  for select using (role in ('master', 'salon'));
-- Мастер/салон видит профили своих клиентов (имя/телефон в записях).
drop policy if exists "profiles_select_my_clients" on public.profiles;
create policy "profiles_select_my_clients" on public.profiles
  for select using (
    exists (
      select 1 from public.appointments a
      where a.client_id = profiles.id
        and a.master_id = auth.uid()
    )
  );
create policy "profiles_update_own"    on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert with check (auth.uid() = id);

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

-- ========== ИЗБРАННОЕ (клиент → мастер/салон) ==========
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

-- ========== ОТЗЫВЫ МАСТЕРОВ О КЛИЕНТАХ ==========
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

-- ========== САЛОННАЯ КОМАНДА ==========
-- Салон читает заявки своих мастеров.
drop policy if exists "appt_select_salon_team" on public.appointments;
create policy "appt_select_salon_team" on public.appointments
  for select using (
    exists (
      select 1 from public.master_profiles mp
      where mp.user_id = appointments.master_id
        and mp.salon_id = auth.uid()
        and appointments.created_at >= coalesce(
              mp.salon_since, '-infinity'::timestamptz)
    )
  );

-- Салон меняет заявки команды (назначить/переназначить мастера).
drop policy if exists "appt_update_salon_team" on public.appointments;
create policy "appt_update_salon_team" on public.appointments
  for update using (
    exists (
      select 1 from public.master_profiles mp
      where mp.user_id = appointments.master_id
        and mp.salon_id = auth.uid()
        and appointments.created_at >= coalesce(
              mp.salon_since, '-infinity'::timestamptz)
    )
  ) with check (
    auth.uid() = master_id
    or exists (
      select 1 from public.master_profiles mp
      where mp.user_id = appointments.master_id
        and mp.salon_id = auth.uid()
    )
  );

-- Салон открепляет мастера (salon_id -> null) в чужой карточке своей команды.
drop policy if exists "mp_update_salon_team" on public.master_profiles;
create policy "mp_update_salon_team" on public.master_profiles
  for update using (salon_id = auth.uid())
  with check (salon_id is null or salon_id = auth.uid());

-- Салон видит профили клиентов, записавшихся к его мастерам.
drop policy if exists "profiles_select_team_clients" on public.profiles;
create policy "profiles_select_team_clients" on public.profiles
  for select using (
    exists (
      select 1
      from public.appointments a
      join public.master_profiles mp on mp.user_id = a.master_id
      where a.client_id = profiles.id
        and mp.salon_id = auth.uid()
    )
  );

-- Автоназначение: наименее загруженный мастер салона на дату.
-- security definer — клиенту не нужны права на чужие записи.
create or replace function public.pick_salon_master(p_salon uuid, p_day date)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_master uuid;
begin
  select mp.user_id into v_master
  from public.master_profiles mp
  where mp.salon_id = p_salon
  order by (
    select count(*)
    from public.appointments a
    where a.master_id = mp.user_id
      and a.starts_at >= p_day::timestamptz
      and a.starts_at < (p_day + 1)::timestamptz
      and a.status <> 'cancelled'
  ) asc, mp.user_id
  limit 1;
  return v_master;
end;
$$;

-- ========== ПРИГЛАШЕНИЯ В САЛОН ==========
create table if not exists public.team_invites (
  id bigint generated always as identity primary key,
  salon_id uuid not null references public.profiles(id) on delete cascade,
  master_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'declined')),
  -- Салон уже видел ответ мастера (бейдж на вкладке «Мастера»).
  salon_seen boolean not null default false,
  created_at timestamptz not null default now(),
  unique (salon_id, master_id)
);

alter table public.team_invites enable row level security;

drop policy if exists "ti_salon" on public.team_invites;
create policy "ti_salon" on public.team_invites
  for all using (auth.uid() = salon_id) with check (auth.uid() = salon_id);

drop policy if exists "ti_master_read" on public.team_invites;
create policy "ti_master_read" on public.team_invites
  for select using (auth.uid() = master_id);
drop policy if exists "ti_master_update" on public.team_invites;
create policy "ti_master_update" on public.team_invites
  for update using (auth.uid() = master_id) with check (auth.uid() = master_id);

-- ========== «ХОНИ» — ПРЕДЛОЖЕНИЯ САЛОНОВ ==========
-- Сертификаты, скидки на первое посещение, бонусы. Создаёт
-- салон/мастер, клиенты видят витрину во вкладке «Хони».
create table if not exists public.offers (
  id bigint generated always as identity primary key,
  provider_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  description text not null default '',
  value text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.offers enable row level security;

drop policy if exists "offers_select" on public.offers;
create policy "offers_select" on public.offers
  for select using (auth.uid() is not null);

drop policy if exists "offers_write" on public.offers;
create policy "offers_write" on public.offers
  for all using (auth.uid() = provider_id) with check (auth.uid() = provider_id);
