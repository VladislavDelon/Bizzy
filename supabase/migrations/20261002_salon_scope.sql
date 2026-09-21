-- Приватность заявок мастера: салон видит только заявки,
-- пришедшие через салон (назначенные им или записанные на него).
-- Личные заявки мастера салону недоступны.
-- Запускать целиком — идемпотентно.

-- 1. appointments.salon_id — «заявка принадлежит салону».
alter table public.appointments
  add column if not exists salon_id uuid references public.profiles(id);

-- 2. Бэкфилл: заявки, которые салон уже видит сегодня (мастер в
--    команде + созданы после его вступления), помечаем salon_id —
--    не забираем у салона то, что он и так видел. Личные заявки,
--    созданные ДО вступления мастера, помеченными не становятся.
update public.appointments a
set salon_id = mp.salon_id
from public.master_profiles mp
where mp.user_id = a.master_id
  and mp.salon_id is not null
  and a.salon_id is null
  and a.created_at >= coalesce(mp.salon_since, '-infinity'::timestamptz);

-- 3. Салон читает только «салонные» заявки: свои (master_id = я —
--    это appt_select) и помеченные salon_id = я. Личные заявки
--    мастеров команды больше не видны.
drop policy if exists "appt_select_salon_team" on public.appointments;
create policy "appt_select_salon_team" on public.appointments
  for select using (salon_id = auth.uid());

-- 4. Салон правит свои и салонные заявки; назначение на мастера
--    команды разрешено (with check по новой строке).
drop policy if exists "appt_update_salon_team" on public.appointments;
create policy "appt_update_salon_team" on public.appointments
  for update using (
    auth.uid() = master_id or salon_id = auth.uid()
  ) with check (
    auth.uid() = master_id
    or salon_id = auth.uid()
    or exists (
      select 1 from public.master_profiles mp
      where mp.user_id = appointments.master_id
        and mp.salon_id = auth.uid()
    )
  );
