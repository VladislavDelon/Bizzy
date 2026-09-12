-- Дополнительные поля публичного профиля мастера.

alter table public.master_profiles
  add column if not exists address text not null default '',
  add column if not exists social text not null default '',
  add column if not exists phone_public boolean not null default false;
