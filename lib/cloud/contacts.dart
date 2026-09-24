/// Условный экспорт телефонной книги: на мобильных — пакет
/// flutter_contacts, на вебе — заглушка с тем же API
/// (контактов в браузере нет, импорт вернёт «нет доступа»).
library;

export 'contacts_stub.dart' if (dart.library.io) 'contacts_io.dart';
