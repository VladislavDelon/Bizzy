-- 20261004 — лист ожидания, ручные блокировки времени,
-- предоплата для новых клиентов, сертификаты на N визитов,
-- реферальная программа, отзывы по услуге и по салону.

-- ========== РУЧНЫЕ БЛОКИРОВКИ ВРЕМЕНИ ==========
-- Мастер/салон закрывает день или диапазон часов (отпуск, личное).
-- Слоты клиентов вычитают эти интервалы наряду с записями.
create table if not exists public.schedule_blocks (
  id bigint generated always as identity primary key,
  provider_id uuid not null references public.profiles(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  reason text not null default '',
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

alter table public.schedule_blocks enable row level security;

-- Читают все: клиент считает свободные слоты провайдера.
drop policy if exists "blocks_select" on public.schedule_blocks;
create policy "blocks_select" on public.schedule_blocks
  for select using (true);

-- Управляет владелец; салон может закрывать время своих мастеров.
drop policy if exists "blocks_write" on public.schedule_blocks;
create policy "blocks_write" on public.schedule_blocks
  for all using (
    auth.uid() = provider_id
    or exists (
      select 1 from public.master_profiles mp
      where mp.user_id = provider_id and mp.salon_id = auth.uid()
    )
  ) with check (
    auth.uid() = provider_id
    or exists (
      select 1 from public.master_profiles mp
      where mp.user_id = provider_id and mp.salon_id = auth.uid()
    )
  );

-- ========== ЛИСТ ОЖИДАНИЯ ==========
-- Клиент подписывается на освобождение окна у провайдера.
-- При отмене записи всем ждущим уходит push; подписка остаётся,
-- notified_at не даёт спамить чаще, чем раз в сутки.
create table if not exists public.waitlist (
  id bigint generated always as identity primary key,
  provider_id uuid not null references public.profiles(id) on delete cascade,
  client_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  notified_at timestamptz,
  unique (provider_id, client_id)
);

alter table public.waitlist enable row level security;

drop policy if exists "waitlist_client" on public.waitlist;
create policy "waitlist_client" on public.waitlist
  for all using (auth.uid() = client_id)
  with check (auth.uid() = client_id);

-- Провайдер видит, кто ждёт окно, и помечает notified_at.
drop policy if exists "waitlist_provider" on public.waitlist;
create policy "waitlist_provider" on public.waitlist
  for select using (
    auth.uid() = provider_id
    or exists (
      select 1 from public.master_profiles mp
      where mp.user_id = provider_id and mp.salon_id = auth.uid()
    )
  );

drop policy if exists "waitlist_provider_update" on public.waitlist;
create policy "waitlist_provider_update" on public.waitlist
  for update using (
    auth.uid() = provider_id
    or exists (
      select 1 from public.master_profiles mp
      where mp.user_id = provider_id and mp.salon_id = auth.uid()
    )
  );

-- Окно освободилось: отменяющая сторона (клиент или провайдер)
-- вызывает функцию — она возвращает клиентов, которым пора слать
-- push, и сразу отмечает notified_at (анти-спам: не чаще раза
-- в сутки на клиента). Обычный select/update им не доступен по RLS.
create or replace function public.due_waitlist_notifications(
  p_provider_id uuid
)
returns setof uuid
language plpgsql
security definer set search_path = public
as $$
begin
  return query
    update public.waitlist w
    set notified_at = now()
    where w.provider_id = p_provider_id
      and (w.notified_at is null
           or w.notified_at < now() - interval '24 hours')
    returning w.client_id;
end;
$$;

-- ========== ПРЕДОПЛАТА ДЛЯ НОВЫХ КЛИЕНТОВ ==========
-- Провайдер включает «новым клиентам — по предоплате».
-- «Проверенный» = есть завершённая запись к этому провайдеру.
alter table public.master_profiles
  add column if not exists prepay_new_clients boolean not null default false;

-- ========== СЕРТИФИКАТЫ НА N ВИЗИТОВ ==========
-- Провайдер «продаёт» клиенту пакет визитов; при записи клиент
-- оплачивает визит сертификатом — used_visits увеличивается.
create table if not exists public.certificates (
  id bigint generated always as identity primary key,
  provider_id uuid not null references public.profiles(id) on delete cascade,
  client_id uuid not null references public.profiles(id) on delete cascade,
  title text not null default 'Сертификат',
  total_visits int not null check (total_visits > 0),
  used_visits int not null default 0 check (used_visits >= 0),
  price numeric(10,2) not null default 0,
  -- Ограничение по услугам; null/пусто — любые услуги провайдера.
  service_ids bigint[],
  active boolean not null default true,
  created_at timestamptz not null default now(),
  check (used_visits <= total_visits)
);

alter table public.certificates enable row level security;

drop policy if exists "cert_client_read" on public.certificates;
create policy "cert_client_read" on public.certificates
  for select using (auth.uid() = client_id);

drop policy if exists "cert_provider" on public.certificates;
create policy "cert_provider" on public.certificates
  for all using (
    auth.uid() = provider_id
    or exists (
      select 1 from public.master_profiles mp
      where mp.user_id = provider_id and mp.salon_id = auth.uid()
    )
  ) with check (
    auth.uid() = provider_id
    or exists (
      select 1 from public.master_profiles mp
      where mp.user_id = provider_id and mp.salon_id = auth.uid()
    )
  );

-- Клиент только тратит визит при записи (used_visits +1, без права
-- менять остальное — гарантирует триггер).
drop policy if exists "cert_client_spend" on public.certificates;
create policy "cert_client_spend" on public.certificates
  for update using (auth.uid() = client_id);

create or replace function public.guard_certificate_update()
returns trigger
language plpgsql
as $$
begin
  -- Клиент (не владелец сертификата и не его салон) может только
  -- инкрементировать used_visits на 1.
  if auth.uid() = new.client_id
     and auth.uid() is distinct from old.provider_id then
    if new.used_visits <> old.used_visits + 1
       or new.total_visits <> old.total_visits
       or new.provider_id <> old.provider_id
       or new.client_id <> old.client_id
       or new.price <> old.price
       or new.title <> old.title
       or new.active <> old.active
       or new.service_ids is distinct from old.service_ids then
      raise exception 'certificate: only used_visits++ allowed';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists certificates_guard on public.certificates;
create trigger certificates_guard
  before update on public.certificates
  for each row execute function public.guard_certificate_update();

-- ========== РЕФЕРАЛЬНАЯ ПРОГРАММА ==========
alter table public.profiles
  add column if not exists ref_code text;
alter table public.profiles
  add column if not exists referred_by uuid references public.profiles(id);
alter table public.profiles
  add column if not exists ref_discount int not null default 0;

create unique index if not exists profiles_ref_code_uidx
  on public.profiles (ref_code) where ref_code is not null;

-- Бонус: после первого завершённого визита приглашённого —
-- скидка 10% на следующую запись ему и пригласившему.
create or replace function public.grant_referral_bonus()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  ref uuid;
  first_completed boolean;
begin
  if new.status <> 'completed' then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.status = 'completed' then
    return new;
  end if;
  select p.referred_by into ref from public.profiles p
    where p.id = new.client_id;
  if ref is null then
    return new;
  end if;
  select not exists (
    select 1 from public.appointments a
    where a.client_id = new.client_id
      and a.status = 'completed'
      and a.id <> new.id
  ) into first_completed;
  if first_completed then
    update public.profiles set ref_discount = greatest(ref_discount, 10)
      where id = new.client_id;
    update public.profiles set ref_discount = greatest(ref_discount, 10)
      where id = ref;
  end if;
  return new;
end;
$$;

drop trigger if exists appointments_referral on public.appointments;
create trigger appointments_referral
  after update of status on public.appointments
  for each row execute function public.grant_referral_bonus();

-- Запись, созданная сразу завершённой (задним числом), тоже
-- засчитывает первый визит.
drop trigger if exists appointments_referral_ins on public.appointments;
create trigger appointments_referral_ins
  after insert on public.appointments
  for each row execute function public.grant_referral_bonus();

-- Применение реф-кода при регистрации: клиент не может читать
-- чужие профили (RLS), поэтому привязка — через функцию.
create or replace function public.apply_referral(p_code text)
returns boolean
language plpgsql
security definer set search_path = public
as $$
declare
  ref uuid;
begin
  if auth.uid() is null then return false; end if;
  select id into ref from public.profiles
    where ref_code = upper(trim(p_code));
  if ref is null or ref = auth.uid() then return false; end if;
  update public.profiles set referred_by = ref
    where id = auth.uid() and referred_by is null;
  return found;
end;
$$;

-- Защита реферальных полей от прямой накрутки клиентом:
-- через API владелец может только обнулить скидку (расход при
-- записи) и один раз присвоить себе ref_code. Бонусы и привязка
-- referred_by меняются только функциями (current_user = postgres).
create or replace function public.guard_profile_referral()
returns trigger
language plpgsql
as $$
begin
  if current_user = 'authenticated' then
    if new.referred_by is distinct from old.referred_by then
      raise exception 'referred_by is managed by apply_referral()';
    end if;
    if new.ref_discount > old.ref_discount then
      raise exception 'ref_discount can only be spent, not raised';
    end if;
    if new.ref_code is distinct from old.ref_code
       and old.ref_code is not null then
      raise exception 'ref_code is assigned once';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_ref_guard on public.profiles;
create trigger profiles_ref_guard
  before update on public.profiles
  for each row execute function public.guard_profile_referral();

-- ========== ОТЗЫВЫ: ПО УСЛУГЕ И ПО САЛОНУ ==========
-- service_id — за какую услугу оценка; salon_id — салон, через
-- который прошла запись (отзыв виден и у мастера, и у салона).
alter table public.ratings add column if not exists service_id bigint;
alter table public.ratings
  add column if not exists salon_id uuid references public.profiles(id);

-- Рейтинг салона теперь считает и отзывы, оставленные его мастерам
-- через салонные записи (salon_id в ratings).
create or replace function public.update_master_rating()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  targets uuid[];
  t uuid;
begin
  targets := array[coalesce(new.master_id, old.master_id)];
  if coalesce(new.salon_id, old.salon_id) is not null
     and coalesce(new.salon_id, old.salon_id)
         is distinct from coalesce(new.master_id, old.master_id) then
    targets := targets || coalesce(new.salon_id, old.salon_id);
  end if;
  foreach t in array targets loop
    update public.master_profiles m
    set rating_avg = coalesce((
          select round(avg(rating)::numeric, 1)
          from public.ratings
          where master_id = t or salon_id = t
        ), 0),
        rating_count = (
          select count(*)
          from public.ratings
          where master_id = t or salon_id = t
        )
    where m.user_id = t;
  end loop;
  return coalesce(new, old);
end;
$$;
