import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:bizzy_app/main.dart';

class MemoryDatabase extends AppointmentsDatabase {
  final contacts = <String, List<Contact>>{
    'clients': [],
    'masters': [],
  };
  final appointments = <Appointment>[];
  final companies = <Company>[];
  final users = <String, String>{};
  final services = <Service>[];
  bool failContacts = false;
  var _nextCompanyId = 1;
  var _nextAppointmentId = 1;
  var _nextContactId = 1;
  var _nextServiceId = 1;

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
      id: _nextContactId++,
      name: name.trim(),
      phone: phone.trim(),
    );
    contacts[_table(type)]!.add(contact);
    return contact;
  }

  @override
  Future<int> updateContact(
    ContactType type,
    int companyId,
    Contact contact,
    String name,
    String phone,
  ) async {
    final index =
        contacts[_table(type)]!.indexWhere((c) => c.id == contact.id);
    if (index < 0) throw StateError('contact not found');
    contacts[_table(type)]![index] = Contact(
      id: contact.id,
      name: name.trim(),
      phone: phone.trim(),
    );
    return 1;
  }

  @override
  Future<int> deleteContact(ContactType type, int id) async {
    contacts[_table(type)]!.removeWhere((c) => c.id == id);
    return 1;
  }

  @override
  Future<List<Service>> getServices(int companyId) async {
    return services.where((s) => s.companyId == companyId).toList();
  }

  @override
  Future<Service> createService(Service service) async {
    final saved = Service(
      id: _nextServiceId++,
      companyId: service.companyId,
      name: service.name.trim(),
      price: service.price,
      durationMinutes: service.durationMinutes,
      notes: service.notes.trim(),
    );
    services.add(saved);
    return saved;
  }

  @override
  Future<int> updateService(Service service) async {
    final index = services.indexWhere((s) => s.id == service.id);
    if (index < 0) throw StateError('service not found');
    services[index] = service;
    return 1;
  }

  @override
  Future<int> deleteService(int id) async {
    services.removeWhere((s) => s.id == id);
    return 1;
  }

  @override
  Future<int> insert(Appointment appointment) async {
    final saved = Appointment(
      id: _nextAppointmentId++,
      companyId: appointment.companyId,
      clientName: appointment.clientName,
      phone: appointment.phone,
      service: appointment.service,
      master: appointment.master,
      dateTime: appointment.dateTime,
      durationMinutes: appointment.durationMinutes,
      reminderMinutes: appointment.reminderMinutes,
      notes: appointment.notes,
    );
    appointments.add(saved);
    return saved.id!;
  }

  @override
  Future<int> update(Appointment appointment) async {
    final index = appointments.indexWhere((a) => a.id == appointment.id);
    if (index < 0) throw StateError('appointment not found');
    appointments[index] = appointment;
    return 1;
  }

  @override
  Future<List<Appointment>> getForDay(
    int companyId,
    DateTime day, {
    String? master,
    int? excludeId,
  }) async {
    return appointments.where((a) {
      final sameDay = a.dateTime.year == day.year &&
          a.dateTime.month == day.month &&
          a.dateTime.day == day.day;
      if (a.companyId != companyId) return false;
      if (!sameDay) return false;
      if (master != null && a.master != master) return false;
      if (excludeId != null && a.id == excludeId) return false;
      return true;
    }).toList();
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
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('ru_RU', null);
    await sb.Supabase.initialize(
      url: 'https://test.supabase.co',
      publishableKey: 'test',
    );
  });

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
    await tester.tap(find.text('Клиенты'));
    await tester.pumpAndSettle();
    expect(find.text('Клиентов пока нет'), findsOneWidget);
    await tester.tap(find.text('Ещё'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Мастера'));
    await tester.pumpAndSettle();
    expect(find.text('Мастеров пока нет'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ещё'));
    await tester.pumpAndSettle();
    expect(find.text('Салон «Тест»'), findsOneWidget);
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

  testWidgets('Appointment can be edited and warns on overlap',
      (tester) async {
    final db = MemoryDatabase();
    db.users['u'] = 'p';
    final company = await db.createCompany(1, 'Салон «Тест»', 'Самозанятость');
    final base = DateTime.now();
    final day = DateTime(base.year, base.month, base.day, 13, 0);
    db.appointments.addAll([
      Appointment(
        id: 1,
        companyId: company.id,
        clientName: 'Анна',
        phone: '+1',
        service: 'Стрижка',
        master: 'Мария',
        dateTime: day,
        durationMinutes: 60,
        notes: '',
      ),
      Appointment(
        id: 2,
        companyId: company.id,
        clientName: 'Борис',
        phone: '+2',
        service: 'Окрашивание',
        master: 'Мария',
        dateTime: day.add(const Duration(minutes: 30)),
        durationMinutes: 60,
        notes: '',
      ),
    ]);
    SharedPreferences.setMockInitialValues({
      'bizzy_user_id': 1,
      'bizzy_user_login': 'u',
      'bizzy_company_id': company.id,
    });
    await tester.pumpWidget(BizzyApp(database: db));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Анна'));
    await tester.pumpAndSettle();
    expect(find.text('Редактирование записи'), findsOneWidget);

    await tester.ensureVisible(find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Время пересекается'), findsOneWidget);
    expect(find.textContaining('предупредить второго клиента'), findsOneWidget);
  });

  testWidgets('Service can be created in services directory', (tester) async {
    final db = await loggedInDb(tester);
    await tester.tap(find.text('Услуги'));
    await tester.pumpAndSettle();
    expect(find.text('Услуг пока нет'), findsOneWidget);
    await tester.tap(find.text('Добавить услугу'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Название'), 'Стрижка');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Цена, ₸'), '1500');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Длительность, мин'), '90');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Стрижка'), findsOneWidget);
    expect(find.text('1500.00 ₸ • 90 мин'), findsOneWidget);
    expect(db.services.length, 1);
    expect(db.services.single.name, 'Стрижка');
    expect(db.services.single.price, 1500);
    expect(db.services.single.durationMinutes, 90);
  });

  testWidgets('Appointment dialog selects service and fills duration',
      (tester) async {
    final db = await loggedInDb(tester);
    await db.saveContact(ContactType.client, 1, 'Анна', '+79001234567');
    await db.saveContact(ContactType.master, 1, 'Мария', '');
    await db.createService(
      const Service(
        companyId: 1,
        name: 'Стрижка',
        price: 1500,
        durationMinutes: 90,
      ),
    );
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Выбрать клиента'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Анна'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбрать мастера'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Мария'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('service_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Стрижка').last);
    await tester.pumpAndSettle();

    final durationField =
        find.widgetWithText(TextFormField, 'Продолжительность (мин)');
    expect(
      (tester.widget(durationField) as TextFormField).controller?.text,
      '90',
    );

    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    final appointment = db.appointments.single;
    expect(appointment.clientName, 'Анна');
    expect(appointment.master, 'Мария');
    expect(appointment.service, 'Стрижка');
    expect(appointment.durationMinutes, 90);
  });

  testWidgets('Client can be edited', (tester) async {
    final db = await loggedInDb(tester);
    await db.saveContact(ContactType.client, 1, 'Анна', '+79001234567');
    await tester.tap(find.text('Клиенты'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Редактировать'));
    await tester.pumpAndSettle();
    expect(find.text('Редактировать клиента'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Имя'), 'Анна И.');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Анна И.'), findsOneWidget);
    expect(db.contacts['clients']!.single.name, 'Анна И.');
  });

  testWidgets('Client can be deleted', (tester) async {
    final db = await loggedInDb(tester);
    await db.saveContact(ContactType.client, 1, 'Анна', '+79001234567');
    await tester.tap(find.text('Клиенты'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();
    expect(find.text('Анна'), findsNothing);
    expect(find.text('Клиентов пока нет'), findsOneWidget);
    expect(db.contacts['clients']!, isEmpty);
  });
}
