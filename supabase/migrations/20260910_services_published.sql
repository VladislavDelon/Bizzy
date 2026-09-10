alter table public.services
add column if not exists published boolean not null default true;
