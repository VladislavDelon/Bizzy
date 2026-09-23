import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Пустая реализация веб-плагина Firebase Messaging.
/// Push-уведомления на вебе не нужны — регистрация no-op,
/// чтобы сгенерированный plugin registrant собирался без
/// dart:html-интеропа настоящего пакета.
class FirebaseMessagingWeb {
  static void registerWith(Registrar registrar) {}
}
