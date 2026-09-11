-- Push-уведомления: FCM-токены.

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
