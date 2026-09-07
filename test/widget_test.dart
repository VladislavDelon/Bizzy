import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bizzy_app/main.dart';

class MemoryDatabase extends AppointmentsDatabase {
  final contacts = <String, List<Contact>>{
    'clients': [],
    'masters': [],
  };
  final appointments = <Appointment>[];
  final companies = <Company>[];
  final users = <String, String>{};
  bool failContacts = false;
  var _nextCompanyId = 1;

  String _table(ContactType type) => type.table;

  @override
  Future<User> createUser(String login, String password) async {
    final trimmed = login.trim();
    if (users.containsKey(trimmed)) throw StateError('exists');
    users[trimmed] = password;
    return User(id: users.length, login: trimmed);
  }

  @override
  Future<User?> authenticate(String login, String password) async {
    final trimmed = login.trim();
    if (users[trimmed] != password) return null;
    return User(id: 1, login: trimmed);
  }

  @override
  Future<List<Company>> getCompanies(int userId) async =>
      companies.where((c) => c.userId == userId).toList();

  @override
  Future<Company> createCompany(int userId, String name, String type) async {
    final company = Company(
      id: _nextCompanyId++,
      userId: userId,
      name: name.trim(),
      type: type,
    );
    companies.add(company);
    return company;
  }

  @override
  Future<List<Company>> claimOrphanCompanies(int userId) async => [];

  @override
  Future<List<Appointment>> getAll(int companyId) async =>
      appointments.where((a) => a.companyId == companyId).toList();

  @override
  Future<List<Contact>> getContacts(ContactType type, int companyId) async {
    if (failContacts) throw StateError('Unavailable');
    return contacts[_table(type)]!.toList();
  }

  @override
  Future<Contact> saveContact(
    ContactType type,
    int companyId,
    String name,
    String phone,
  ) async {
    final contact = Contact(
      id: contacts[_table(type)]!.length + 1,
      name: name.trim(),
      phone: phone.trim(),
    );
    contacts[_table(type)]!.add(contact);
    return contact;
  }

  @override
  Future<int> insert(Appointment appointment) async {
    appointments.add(appointment);
    return appointments.length;
  }

  @override
  Future<int> delete(int id) async {
    appointments.removeWhere((a) => a.id == id);
    return 1;
  }
}

Future<MemoryDatabase> loggedInDb(WidgetTester tester) async {
  final db = MemoryDatabase();
  db.users['u'] = 'p';
  final company =
      await db.createCompany(1, 'Салон «Тест»', 'Самозанятость');
  SharedPreferences.setMockInitialValues({
    'bizzy_user_id': 1,
    'bizzy_user_login': 'u',
    'bizzy_company_id': company.id,
  });
  await tester.pumpWidget(BizzyApp(database: db));
  await tester.pumpAndSettle();
  return db;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Register shows local-storage warning then company setup',
      (tester) async {
    final db = MemoryDatabase();
    await tester.pumpWidget(BizzyApp(database: db));
    await tester.pumpAndSettle();
    expect(find.text('Вход'), findsWidgets);

    await tester.tap(find.text('Нет аккаунта? Зарегистрироваться'));
    await tester.pumpAndSettle();
    expect(find.text('Регистрация'), findsOneWidget);
    expect(find.textContaining('регистрация происходит локально'),
        findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Логин'), 'владелец');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Пароль'), '1234');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Повторите пароль'), '1234');
    await tester.tap(find.text('Зарегистрироваться'));
    await tester.pumpAndSettle();

    expect(find.text('Мои компании'), findsOneWidget);
    await tester.tap(find.text('Создать компанию'));
    await tester.pumpAndSettle();
    expect(find.text('Назовите свою компанию'), findsOneWidget);
    await tester.tap(find.text('ИП'));
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Название'), 'Салон «Лилия»');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(find.text('Салон «Лилия»'), findsOneWidget);
    expect(find.text('На этот день записей нет.'), findsOneWidget);
  });

  testWidgets('Wrong password shows error', (tester) async {
    final db = MemoryDatabase();
    db.users['u'] = 'right';
    await tester.pumpWidget(BizzyApp(database: db));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Логин'), 'u');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Пароль'), 'wrong');
    await tester.tap(find.text('Войти'));
    await tester.pumpAndSettle();
    expect(find.text('Неверный логин или пароль'), findsOneWidget);
  });

  testWidgets('Schedule shows company directories and switch menu',
      (tester) async {
    await loggedInDb(tester);
    expect(find.text('Салон «Тест»'), findsOneWidget);
    await tester.tap(find.text('Клиенты'));
    await tester.pumpAndSettle();
    expect(find.text('Клиентов пока нет'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Мастера'));
    await tester.pumpAndSettle();
    expect(find.text('Мастеров пока нет'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Сменить компанию'), findsOneWidget);
    expect(find.text('Выйти из аккаунта'), findsOneWidget);
  });

  testWidgets('Client creation validates fields and supports search',
      (tester) async {
    final db = await loggedInDb(tester);
    await tester.tap(find.text('Клиенты'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Введите имя'), findsOneWidget);
    expect(find.text('Введите телефон'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Имя'), ' Анна ');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Телефон'), '+79001234567');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Анна'), findsOneWidget);
    expect(db.contacts['clients']!.single.name, 'Анна');
    await tester.enterText(find.byType(TextField), '7900');
    await tester.pumpAndSettle();
    expect(find.text('Анна'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Борис');
    await tester.pumpAndSettle();
    expect(find.text('Ничего не найдено'), findsOneWidget);
  });

  testWidgets('Appointment selects contacts and fills the client phone',
      (tester) async {
    final db = await loggedInDb(tester);
    await db.saveContact(ContactType.client, 1, 'Анна', '+79001234567');
    await db.saveContact(ContactType.master, 1, 'Мария', '');
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбрать клиента'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Анна'));
    await tester.pumpAndSettle();
    expect(find.text('+79001234567'), findsOneWidget);
    await tester.tap(find.text('Выбрать мастера'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Мария'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Услуга'), 'Стрижка');
    await tester.ensureVisible(find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    final appointment = db.appointments.single;
    expect(appointment.clientName, 'Анна');
    expect(appointment.phone, '+79001234567');
    expect(appointment.master, 'Мария');
    expect(appointment.service, 'Стрижка');
    expect(appointment.companyId, 1);
  });

  testWidgets('Directory loading errors can be retried', (tester) async {
    final db = await loggedInDb(tester);
    db.failContacts = true;
    await tester.tap(find.text('Клиенты'));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось загрузить список'), findsOneWidget);
    db.failContacts = false;
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('Клиентов пока нет'), findsOneWidget);
  });
}
