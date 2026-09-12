-- Отзывы мастеров о клиентах (видны другим мастерам).

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
    auth.uid() in (select id from public.profiles where role = 'master')
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
