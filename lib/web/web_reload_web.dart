// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Веб: жёсткая перезагрузка страницы — после смены режима
/// «Сайт / Приложение» приложение стартует заново уже
/// в новой вёрстке (сессия Supabase сохраняется).
void reloadPage() => html.window.location.reload();
