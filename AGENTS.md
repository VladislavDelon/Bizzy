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

## Подпись релизных APK

- GitHub Actions (`.github/workflows/release.yml`) ищет секреты `KEYSTORE_BASE64`,
  `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.
- Если секреты не заданы, CI собирает APK с автоматическим debug-ключом раннера.
  Debug-ключ разный на каждом раннере, поэтому **обновление поверх старого APK
  будет невозможно** — Android ругается на разную подпись.
- Для стабильных обновлений нужен один и тот же release-keystore, загруженный
  в GitHub Secrets. Файл с секретами и сам `.jks` не должны попадать в репозиторий.
- Сгенерированный keystore и инструкции: `C:\Users\ASRock\Desktop\Bizzy\bizzy-release-secrets.txt`.
- После смены ключа пользователь должен один раз удалить приложение и поставить
  новый APK вручную; дальнейшие обновления поверх уже будут работать.

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

## Push-уведомления (с v1.8.0)
- Используются `firebase_core` + `firebase_messaging`.
- FCM-токены хранятся в таблице `fcm_tokens` Supabase.
- Для отправки push используется Edge Function `send-push`.
  Ей нужна переменная окружения `FCM_SERVER_KEY` из Firebase Console
  (Cloud Messaging → Server key).
- Для Android: заменить заглушку `android/app/google-services.json` на настоящий
  файл из Firebase проекта.
- Локальные напоминания о записях работают через `flutter_local_notifications`
  и не требуют Firebase.
