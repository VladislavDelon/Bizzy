-- 20261003_work_and_more.sql
-- Рабочие часы провайдера, мультивыбор услуг, чёрный список,
-- ответ на отзыв, флаг онбординга.

-- ========== РАБОЧИЕ ЧАСЫ ==========
-- master_profiles.work_hours: {"1":{"s":"09:00","e":"19:00","off":false,
-- "b":[["13:00","14:00"]]}, ..., "7":{...}} — ключи = DateTime.weekday (1=Пн).
alter table public.master_profiles
  add column if not exists work_hours jsonb;

-- ========== НЕСКОЛЬКО УСЛУГ ЗА ВИЗИТ ==========
-- Все id выбранных услуг; service_name хранит их через « + »,
-- service_price и duration_minutes — уже суммарные.
alter table public.appointments
  add column if not exists service_ids bigint[];

-- ========== ЧЁРНЫЙ СПИСОК ==========
-- Провайдер блокирует клиента — тот не может записаться к нему
-- (и к салону, если заблокировал салон).
create table if not exists public.blocked_clients (
  provider_id uuid not null references public.profiles(id) on delete cascade,
  client_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (provider_id, client_id)
);

alter table public.blocked_clients enable row level security;

drop policy if exists "blocked_select" on public.blocked_clients;
drop policy if exists "blocked_write"  on public.blocked_clients;
create policy "blocked_select" on public.blocked_clients
  for select using (auth.uid() = provider_id or auth.uid() = client_id);
create policy "blocked_write" on public.blocked_clients
  for all using (auth.uid() = provider_id) with check (auth.uid() = provider_id);

-- Запрет записи на уровне БД: заблокированный клиент не вставит заявку.
drop policy if exists "appt_insert" on public.appointments;
create policy "appt_insert" on public.appointments
  for insert with check (
    auth.uid() = client_id
    and not exists (
      select 1 from public.blocked_clients bc
      where bc.client_id = auth.uid()
        and (bc.provider_id = appointments.master_id
             or bc.provider_id = appointments.salon_id)
    )
  );

-- ========== ОТВЕТ ПРОВАЙДЕРА НА ОТЗЫВ ==========
alter table public.ratings add column if not exists reply text not null default '';
alter table public.ratings add column if not exists replied_at timestamptz;

-- Провайдер (мастер или салон владельца оценки) может ответить.
drop policy if exists "ratings_update_provider" on public.ratings;
create policy "ratings_update_provider" on public.ratings
  for update using (
    auth.uid() = master_id
    or exists (
      select 1 from public.master_profiles mp
      where mp.user_id = ratings.master_id and mp.salon_id = auth.uid()
    )
  ) with check (
    auth.uid() = master_id
    or exists (
      select 1 from public.master_profiles mp
      where mp.user_id = ratings.master_id and mp.salon_id = auth.uid()
    )
  );

-- Но менять может только поля ответа — саму оценку/комментарий трогать
-- нельзя (клиент по-прежнему правит свой отзыв целиком).
create or replace function public.guard_rating_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- Клиенту можно всё; остальным (провайдер/салон) — только reply.
  if auth.uid() is distinct from new.client_id then
    if new.rating is distinct from old.rating
       or new.comment is distinct from old.comment
       or new.client_id is distinct from old.client_id
       or new.master_id is distinct from old.master_id
       or new.appointment_id is distinct from old.appointment_id then
      raise exception 'only reply fields can be changed by provider';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists ratings_guard on public.ratings;
create trigger ratings_guard
  before update on public.ratings
  for each row execute function public.guard_rating_update();

-- ========== ОНБОРДИНГ ==========
-- Уже существующих мастеров/салонов мастер настройки не беспокоит.
alter table public.profiles add column if not exists onboarded boolean not null default false;
update public.profiles set onboarded = true where role in ('master', 'salon');
