-- Салонная команда: мастера салона, ключ регистрации, автоназначение
-- заявок, видимость телефона клиента. Запускать целиком — идемпотентно.

-- 1. master_profiles: привязка к салону + уникальный ключ + флаг автоназначения.
alter table public.master_profiles
  add column if not exists salon_id uuid references public.profiles(id) on delete set null;
alter table public.master_profiles
  add column if not exists salon_key text;
alter table public.master_profiles
  add column if not exists auto_assign boolean not null default false;

create unique index if not exists master_profiles_salon_key_uidx
  on public.master_profiles (salon_key)
  where salon_key is not null;

-- 2. profiles: клиент сам решает, виден ли его номер мастерам.
alter table public.profiles
  add column if not exists phone_public boolean not null default true;

-- 3. Салон читает заявки своих мастеров.
drop policy if exists "appt_select_salon_team" on public.appointments;
create policy "appt_select_salon_team" on public.appointments
  for select using (
    exists (
      select 1 from public.master_profiles mp
      where mp.user_id = appointments.master_id
        and mp.salon_id = auth.uid()
    )
  );

-- 4. Салон меняет заявки команды (назначить/переназначить мастера).
drop policy if exists "appt_update_salon_team" on public.appointments;
create policy "appt_update_salon_team" on public.appointments
  for update using (
    exists (
      select 1 from public.master_profiles mp
      where mp.user_id = appointments.master_id
        and mp.salon_id = auth.uid()
    )
  ) with check (
    auth.uid() = master_id
    or exists (
      select 1 from public.master_profiles mp
      where mp.user_id = appointments.master_id
        and mp.salon_id = auth.uid()
    )
  );

-- 5. Салон открепляет мастера — обновляет salon_id в чужой карточке,
--    но только своей команды и только в null/себя.
drop policy if exists "mp_update_salon_team" on public.master_profiles;
create policy "mp_update_salon_team" on public.master_profiles
  for update using (salon_id = auth.uid())
  with check (salon_id is null or salon_id = auth.uid());

-- Мастер привязывается сам: обновление своей карточки разрешено mp_update.

-- 6. Салон видит профили клиентов, записавшихся к его мастерам
--    (имя/телефон в заявках команды).
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

-- 7. Автоназначение: наименее загруженный мастер салона на дату.
--    security definer — клиенту не нужны права на чужие записи.
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
