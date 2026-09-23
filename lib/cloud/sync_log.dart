// Файловый лог синхронизации: на мобильных — в documents,
// на вебе — в консоль (dart:io недоступен).
export 'sync_log_stub.dart' if (dart.library.io) 'sync_log_io.dart';
