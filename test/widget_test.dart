import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bizzy_app/main.dart';

class MemoryDatabase extends AppointmentsDatabase {
  final contacts = <ContactType, List<Contact>>{
    ContactType.client: [],
    ContactType.master: [],
  };
  final appointments = <Appointment>[];
  bool failContacts = false;

  @override
  Future<List<Appointment>> getAll() async => appointments.toList();

  @override
  Future<List<Contact>> getContacts(ContactType type) async {
    if (failContacts) throw StateError('Unavailable');
    return contacts[type]!.toList();
  }

  @override
  Future<Contact> saveContact(ContactType type, String name, String phone) async {
    final contact = Contact(
      id: contacts[type]!.length + 1,
      name: name.trim(),
      phone: phone.trim(),
    );
    contacts[type]!.add(contact);
    return contact;
  }

  @override
  Future<int> insert(Appointment appointment) async {
    appointments.add(appointment);
    return appointments.length;
  }
}

void main() {
  testWidgets('Schedule and separate directories are accessible', (tester) async {
    await tester.pumpWidget(BizzyApp(database: MemoryDatabase()));
    await tester.pumpAndSettle();
    expect(find.text('На этот день записей нет.'), findsOneWidget);
    await tester.tap(find.text('Клиенты'));
    await tester.pumpAndSettle();
    expect(find.text('Клиентов пока нет'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Мастера'));
    await tester.pumpAndSettle();
    expect(find.text('Мастеров пока нет'), findsOneWidget);
  });

  testWidgets('Client creation validates fields and supports search', (tester) async {
    final database = MemoryDatabase();
    await tester.pumpWidget(BizzyApp(database: database));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Клиенты'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Введите имя'), findsOneWidget);
    expect(find.text('Введите телефон'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Имя'), ' Анна ');
    await tester.enterText(find.widgetWithText(TextFormField, 'Телефон'), '+79001234567');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Анна'), findsOneWidget);
    expect(database.contacts[ContactType.client]!.single.name, 'Анна');
    await tester.enterText(find.byType(TextField), '7900');
    await tester.pumpAndSettle();
    expect(find.text('Анна'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Борис');
    await tester.pumpAndSettle();
    expect(find.text('Ничего не найдено'), findsOneWidget);
  });

  testWidgets('Master can be created without a phone', (tester) async {
    final database = MemoryDatabase();
    await tester.pumpWidget(BizzyApp(database: database));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Мастера'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Имя'), 'Мария');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(database.contacts[ContactType.master]!.single.name, 'Мария');
    expect(database.contacts[ContactType.client], isEmpty);
  });

  testWidgets('Appointment selects contacts and fills the client phone', (tester) async {
    final database = MemoryDatabase();
    await database.saveContact(ContactType.client, 'Анна', '+79001234567');
    await database.saveContact(ContactType.master, 'Мария', '');
    await tester.pumpWidget(BizzyApp(database: database));
    await tester.pumpAndSettle();
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
    await tester.enterText(find.widgetWithText(TextFormField, 'Услуга'), 'Стрижка');
    await tester.ensureVisible(find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    final appointment = database.appointments.single;
    expect(appointment.clientName, 'Анна');
    expect(appointment.phone, '+79001234567');
    expect(appointment.master, 'Мария');
    expect(appointment.service, 'Стрижка');
  });

  testWidgets('Directory loading errors can be retried', (tester) async {
    final database = MemoryDatabase()..failContacts = true;
    await tester.pumpWidget(BizzyApp(database: database));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Клиенты'));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось загрузить список'), findsOneWidget);
    database.failContacts = false;
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('Клиентов пока нет'), findsOneWidget);
  });
}
