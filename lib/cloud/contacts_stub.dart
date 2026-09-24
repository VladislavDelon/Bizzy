/// Веб-заглушка flutter_contacts: телефонной книги в браузере нет.
/// API повторяет используемую часть пакета, чтобы общий код
/// (импорт контакта в SalonTeamScreen) компилировался и просто
/// сообщал «нет доступа к контактам».
library;

enum PermissionType { read }

enum PermissionStatus { granted, denied, restricted, permanentlyDenied }

enum ContactProperty { phone }

class Phone {
  const Phone(this.number);

  final String number;
}

class Contact {
  const Contact({this.displayName, this.phones = const []});

  final String? displayName;
  final List<Phone> phones;
}

class _Permissions {
  const _Permissions();

  Future<PermissionStatus> request(PermissionType type) async =>
      PermissionStatus.denied;
}

class FlutterContacts {
  const FlutterContacts._();

  static const permissions = _Permissions();

  static Future<List<Contact>> getAll({
    Set<ContactProperty>? properties,
  }) async => const [];
}
