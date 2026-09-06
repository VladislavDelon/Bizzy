# Bizzy — заметки для агентов

Flutter-приложение: календарь записей (sqflite) + справочники «Клиенты» и «Мастера».
Весь код пока в `lib/main.dart`. Тесты: `test/widget_test.dart` (используют `MemoryDatabase`,
мок `AppointmentsDatabase`, чтобы не трогать sqflite в widget-тестах).

## Проверка
- `dart analyze` — работает стабильно.
- `flutter test` — работает, но `flutter.bat` иногда падает (SDK в `C:\Users\ASRock\Desktop\flutter`
  является чекаутом репозитория flutter/flutter, не релизной сборкой). При падении просто повторить.

## Сборка
- `flutter build apk --release` собирает подписанный debug-ключами APK:
  `build\app\outputs\flutter-apk\app-release.apk`.
- Если Gradle-задача падает с "PowerShell executable not found", перед сборкой добавить в PATH:
  `$env:PATH = "C:\Windows\System32\WindowsPowerShell\v1.0;$env:PATH"`.
