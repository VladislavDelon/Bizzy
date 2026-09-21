-- Бейджи команды, приватность записей мастера и витрина «Хони».
-- Запускать целиком — идемпотентно.

-- 1. Когда мастер вступил в салон — salon_since. Салон видит
--    только записи, созданные ПОСЛЕ вступления (личные записи
--    мастера до трудоустройства скрыты).
alter table public.master_profiles
  add column if not exists salon_since timestamptz;

-- 2. salon_seen — салон уже видел ответ мастера (бейдж на вкладке
--    «Мастера» показывает только новые принятые приглашения).
alter table public.team_invites
  add column if not exists salon_seen boolean not null default false;

-- 3. Записи мастера видны салону только если созданы после
--    вступления мастера в команду (salon_since NULL = мастер был
--    привязан до появления колонки — показываем всё, обратная
--    совместимость).
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

-- 4. «Хони» — предложения/сертификаты/бонусы от салонов и мастеров.
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

-- Читают все вошедшие (клиенты видят витрину «Хони»).
drop policy if exists "offers_select" on public.offers;
create policy "offers_select" on public.offers
  for select using (auth.uid() is not null);

-- Создаёт и правит только сам салон/мастер.
drop policy if exists "offers_write" on public.offers;
create policy "offers_write" on public.offers
  for all using (auth.uid() = provider_id) with check (auth.uid() = provider_id);
