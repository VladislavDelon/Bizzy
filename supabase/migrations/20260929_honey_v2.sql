-- Honey v2: картинка-фон, ссылка, скидка в %, привязка к услугам,
-- срок действия, подарки клиентам и предоплата по клиенту.
-- Запускать целиком — идемпотентно.

-- 1. Новые поля offers.
alter table public.offers
  add column if not exists image_url text not null default '',
  add column if not exists link_url text not null default '',
  add column if not exists discount_percent numeric not null default 0,
  add column if not exists all_services boolean not null default true,
  add column if not exists service_ids bigint[] not null default '{}',
  add column if not exists valid_from timestamptz,
  add column if not exists valid_until timestamptz;

-- 2. Подаренные Honey: салон/мастер дарит конкретному клиенту —
-- клиент видит их в своей вкладке Honey отдельным блоком.
create table if not exists public.offer_gifts (
  id bigint generated always as identity primary key,
  offer_id bigint not null references public.offers(id) on delete cascade,
  provider_id uuid not null references public.profiles(id) on delete cascade,
  client_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (offer_id, client_id)
);

alter table public.offer_gifts enable row level security;

-- Провайдер дарит только СВОИ предложения (проверка владения offer).
drop policy if exists "gift_provider" on public.offer_gifts;
create policy "gift_provider" on public.offer_gifts
  for all using (auth.uid() = provider_id)
  with check (
    auth.uid() = provider_id
    and exists (
      select 1 from public.offers o
      where o.id = offer_id and o.provider_id = auth.uid()
    )
  );

drop policy if exists "gift_client_read" on public.offer_gifts;
create policy "gift_client_read" on public.offer_gifts
  for select using (auth.uid() = client_id);

-- Клиент может «погасить» подарок после записи (one-time use).
drop policy if exists "gift_client_delete" on public.offer_gifts;
create policy "gift_client_delete" on public.offer_gifts
  for delete using (auth.uid() = client_id);

-- 3. Провайдер видит, кто добавил его в избранное — нужно для
--    push-уведомлений фанам о новых услугах/Honey.
drop policy if exists "favorites_select" on public.favorites;
create policy "favorites_select" on public.favorites
  for select using (auth.uid() = client_id or auth.uid() = master_id);

-- 4. Предоплата по конкретному клиенту: мастер/салон помечает,
--    кого принимает только с предоплатой и на какую сумму.
create table if not exists public.client_prepay_rules (
  id bigint generated always as identity primary key,
  provider_id uuid not null references public.profiles(id) on delete cascade,
  client_id uuid not null references public.profiles(id) on delete cascade,
  prepay_required boolean not null default true,
  amount numeric not null default 0,
  created_at timestamptz not null default now(),
  unique (provider_id, client_id)
);

alter table public.client_prepay_rules enable row level security;

drop policy if exists "prepay_provider" on public.client_prepay_rules;
create policy "prepay_provider" on public.client_prepay_rules
  for all using (auth.uid() = provider_id) with check (auth.uid() = provider_id);

drop policy if exists "prepay_client_read" on public.client_prepay_rules;
create policy "prepay_client_read" on public.client_prepay_rules
  for select using (auth.uid() = client_id);

-- 5. Ссылка записи на Honey — аудит: по какой акции клиент записался.
alter table public.appointments
  add column if not exists offer_id bigint;
