ALTER TABLE public.master_profiles ADD COLUMN IF NOT EXISTS avatar_url text NOT NULL DEFAULT '';

-- Создать публичный bucket для аватаров (Storage → New bucket):
-- name: avatars
-- Public: true

-- RLS-политики для bucket `avatars` (чтобы авторизованные пользователи могли загружать свои файлы,
-- а все могли читать).
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = true;

create policy if not exists "avatars_select_public"
  on storage.objects for select
  using (bucket_id = 'avatars');

create policy if not exists "avatars_insert_own"
  on storage.objects for insert
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy if not exists "avatars_update_own"
  on storage.objects for update
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy if not exists "avatars_delete_own"
  on storage.objects for delete
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
