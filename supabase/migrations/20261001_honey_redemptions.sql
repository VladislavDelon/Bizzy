-- Погашения Honey (разовое использование) + оценки клиентов от салона.
-- Идемпотентно — можно запускать повторно.

-- 1. offer_redemptions: факт использования Honey клиентом при записи.
--    unique(offer_id, client_id) — один и тот же Honey не применить дважды
--    даже при гонке двух записей.
create table if not exists public.offer_redemptions (
  id bigint generated always as identity primary key,
  offer_id bigint not null references public.offers(id) on delete cascade,
  client_id uuid not null references public.profiles(id) on delete cascade,
  appointment_id bigint references public.appointments(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (offer_id, client_id)
);

alter table public.offer_redemptions enable row level security;

-- Клиент видит свои погашения и создаёт их при записи.
drop policy if exists "redemption_client" on public.offer_redemptions;
create policy "redemption_client" on public.offer_redemptions
  for all using (auth.uid() = client_id) with check (auth.uid() = client_id);

-- Провайдер видит погашения СВОИХ предложений (кто уже использовал).
drop policy if exists "redemption_provider_read" on public.offer_redemptions;
create policy "redemption_provider_read" on public.offer_redemptions
  for select using (
    exists (
      select 1 from public.offers o
      where o.id = offer_id and o.provider_id = auth.uid()
    )
  );

-- 2. Салон оценивает клиентов своей команды: запись принадлежит
--    мастеру, у которого master_profiles.salon_id = этот салон,
--    либо самому салону (запись без автоназначения мастеру).
drop policy if exists "client_reviews_insert" on public.client_reviews;
create policy "client_reviews_insert" on public.client_reviews
  for insert with check (
    auth.uid() = master_id
    and exists (
      select 1
      from public.appointments a
      left join public.master_profiles mp on mp.user_id = a.master_id
      where a.id = booking_id
        and a.client_id = client_id
        and (
          a.master_id = auth.uid()
          or mp.salon_id = auth.uid()
        )
    )
  );
