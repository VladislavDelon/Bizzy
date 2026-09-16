-- Предоплата: настройки у мастера/салона + статус оплаты в записи.
-- Идемпотентно: можно запускать повторно.

alter table public.master_profiles
  add column if not exists prepay_enabled boolean not null default false,
  add column if not exists prepay_amount numeric not null default 0,
  add column if not exists prepay_link text not null default '';

alter table public.appointments
  add column if not exists prepayment_status text not null default 'none';

-- 'none' — без предоплаты, 'claimed' — клиент отметил оплату,
-- 'confirmed' — мастер подтвердил получение.
alter table public.appointments
  drop constraint if exists appointments_prepayment_status_check;
alter table public.appointments
  add constraint appointments_prepayment_status_check
  check (prepayment_status in ('none', 'claimed', 'confirmed'));
