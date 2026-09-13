-- Аватар клиента в таблице profiles + insert-RLS для резервного создания профиля.

alter table public.profiles
  add column if not exists avatar_url text not null default '';

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert with check (auth.uid() = id);
