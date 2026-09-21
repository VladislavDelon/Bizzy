-- Несколько категорий у мастера/салона: «Парикмахер» + «Мастер
-- по ресницам» — провайдер находится по каждому фильтру поиска.
-- Основная категория остаётся в `category` (первый элемент списка)
-- для совместимости со старыми версиями приложения.
-- Запускать целиком — идемпотентно.

alter table public.master_profiles
  add column if not exists categories text[] not null default '{}';

-- Заполняем массив из существующей одиночной категории.
update public.master_profiles
  set categories = array[category]
  where categories = '{}' and category is not null and category <> '';
