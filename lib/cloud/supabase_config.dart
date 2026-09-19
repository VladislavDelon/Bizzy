/// Подключение к проекту Supabase. Вынесено сюда, чтобы вторичный
/// SupabaseClient (например, регистрация мастера из аккаунта салона
/// без смены своей сессии) мог использовать те же ключи.
const supabaseUrl = 'https://ngnikkkjxyfhnnwqbzma.supabase.co';
const supabasePublishableKey =
    'sb_publishable_K_sBU9qflN7ybTtSSXtjTw_H6CtqpNO';
