import 'package:bizzy_app/admin/admin_api.dart';
import 'package:bizzy_app/admin_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeApi implements AdminApiBase {
  final users = <AdminUser>[
    AdminUser(
      id: 'u1',
      login: 'anna',
      role: 'client',
      name: 'Анна',
      phone: '+7999',
      banned: false,
      createdAt: DateTime(2026, 1, 10),
    ),
    AdminUser(
      id: 'u2',
      login: 'master_pro',
      role: 'master',
      name: 'Ольга',
      phone: '',
      banned: true,
      createdAt: DateTime(2026, 1, 5),
      category: 'nails',
      ratingAvg: 4.8,
      ratingCount: 12,
    ),
  ];

  @override
  Future<List<AdminUser>> listUsers() async => users;
  @override
  Future<List<AdminReview>> reviewsAbout(AdminUser u) async => const [];
  @override
  Future<void> updateLogin(String id, String login) async {}
  @override
  Future<void> updatePassword(String id, String pass) async {}
  @override
  Future<void> setBanned(String id, bool b) async {}
  @override
  Future<void> deleteUser(String id) async {}
  @override
  Future<void> deleteReview(AdminReview r) async {}
}

Widget _app() => BizzyAdminApp(
  adminUser: 'root',
  adminPass: 'toor',
  serviceKey: 'key',
  api: _FakeApi(),
);

void main() {
  testWidgets('Admin login: показывает форму, ругается на неверные креды', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text('Вход администратора'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'bad');
    await tester.enterText(find.byType(TextField).at(1), 'creds');
    await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
    await tester.pump();
    expect(find.text('Неверный логин или пароль'), findsOneWidget);
  });

  testWidgets('Admin login: верные креды → список пользователей', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'root');
    await tester.enterText(find.byType(TextField).at(1), 'toor');
    await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
    await tester.pumpAndSettle();

    expect(find.text('Bizzy — админка'), findsOneWidget);
    expect(find.text('Анна'), findsOneWidget);
    expect(find.text('Ольга'), findsOneWidget);
    expect(find.text('заблокирован'), findsOneWidget);
  });
}
