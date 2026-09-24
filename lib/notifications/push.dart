/// Условный экспорт PushNotificationService: на вебе — заглушка
/// (dart:io, firebase_messaging и локальные уведомления недоступны),
/// на мобильных — настоящий сервис.
library;

export 'push_stub.dart' if (dart.library.io) 'push_service.dart';
