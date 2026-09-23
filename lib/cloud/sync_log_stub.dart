import 'package:flutter/foundation.dart';

/// Веб-заглушка файлового лога: на вебе нет documents-каталога,
/// пишем только в консоль браузера.
class SyncLog {
  static Future<String> read() async => '';

  static Future<void> clear() async {}

  static Future<void> write(String tag, String message) async {
    debugPrint('[SyncLog] [$tag] $message');
  }
}
