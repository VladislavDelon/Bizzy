-- Выполнить в Supabase SQL Editor для существующего проекта.

-- 1. Добавляем колонку аватара в профиль мастера.
ALTER TABLE public.master_profiles
ADD COLUMN IF NOT EXISTS avatar_url text NOT NULL DEFAULT '';

-- 2. Создаём публичный bucket для аватаров (id = 'avatars', public = true).
-- Если bucket уже существует — обновляем флаг public.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = true;

-- 3. Политики bucket'а `avatars`.
-- Все могут читать фото. Авторизованный пользователь может загружать/обновлять/удалять
-- только файлы в своей папке <user_id>/... .

drop policy if exists "avatars_select_public" on storage.objects;
create policy "avatars_select_public"
  on storage.objects for select
  using (bucket_id = 'avatars');

drop policy if exists "avatars_insert_own" on storage.objects;
create policy "avatars_insert_own"
  on storage.objects for insert
  with check (
    bucket_id = 'avatars'
    and coalesce((storage.foldername(name))[1], '') = auth.uid()::text
  );

drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own"
  on storage.objects for update
  using (
    bucket_id = 'avatars'
    and coalesce((storage.foldername(name))[1], '') = auth.uid()::text
  );

drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own"
  on storage.objects for delete
  using (
    bucket_id = 'avatars'
    and coalesce((storage.foldername(name))[1], '') = auth.uid()::text
  );
