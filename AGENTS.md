# Bizzy — заметки для агентов

Flutter-приложение: календарь записей (sqflite) + справочники «Клиенты» и «Мастера»
+ локальная регистрация + несколько компаний на одном аккаунте.
Весь код пока в `lib/main.dart`. Тесты: `test/widget_test.dart` (используют `MemoryDatabase`,
мок `AppointmentsDatabase`, чтобы не трогать sqflite в widget-тестах).

## Модель данных
- SQLite версии 4: `users`, `companies`, `appointments`, `clients`, `masters`.
- Все справочники и записи привязаны к `companyId`. Один пользователь может владеть
  несколькими компаниями; между ними можно переключаться.
- Запись теперь имеет `durationMinutes` (по умолчанию 60 мин) и `reminderMinutes`
  (по умолчанию 30 мин). При сохранении проверяется пересечение с другими записями
  того же мастера.
- Пароли хранятся в виде `sha256(salt + password)`.

## Проверка
- `dart analyze` — работает стабильно.
- `flutter test` — работает, но `flutter.bat` иногда падает (SDK в `C:\Users\ASRock\Desktop\flutter`
  является чекаутом репозитория flutter/flutter, не релизной сборкой). При падении просто повторить.

## Сборка
- `flutter build apk --release` собирает подписанный debug-ключами APK:
  `build\app\outputs\flutter-apk\app-release.apk`.
- Если Gradle-задача падает с "PowerShell executable not found", перед сборкой добавить в PATH:
  `$env:PATH = "C:\Windows\System32\WindowsPowerShell\v1.0;$env:PATH"`.

## Git / релизы
- Репозиторий: https://github.com/VladislavDelon/Bizzy (public, ветка main).
- На этой машине есть только mingit из SDK — для push/pull использовать полный Git:
  `C:\Program Files\Git\cmd\git.exe`.
- В hosts заблокирован api.github.com — локально API дёргать через
  `curl.exe --resolve api.github.com:443:140.82.121.6`.
- Версия приложения = `version` в pubspec.yaml. Релиз: поднять версию → commit →
  `git tag vX.Y.Z` → push тега → Actions сам собирает APK в Releases.
- Приложение при запуске проверяет /releases/latest через UpdateService в main.dart
  и предлагает скачать и установить APK поверх через `install_plugin_v3` и `dio`
  (прогресс-бар, без открытия браузера).
