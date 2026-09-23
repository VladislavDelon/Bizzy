import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Файловый лог для диагностики облачной синхронизации
/// (мобильная версия — пишет в documents).
class SyncLog {
  static const _fileName = 'bizzy_sync.log';

  static Future<String> _path() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$_fileName';
  }

  static Future<String> read() async {
    try {
      final file = File(await _path());
      if (!await file.exists()) return '';
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  static Future<void> clear() async {
    try {
      final file = File(await _path());
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Future<void> write(String tag, String message) async {
    try {
      final file = File(await _path());
      final now = DateTime.now().toLocal().toIso8601String();
      final line = '[$now] [$tag] $message\n';
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    } catch (_) {
      // Не блокируем работу при ошибке записи лога.
    }
  }
}
