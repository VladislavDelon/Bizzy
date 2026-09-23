import 'package:bizzy_app/app_theme.dart';
import 'package:bizzy_app/web/web_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('web auth screen renders login form', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: bizzyTheme(Brightness.dark),
        home: WebAuthScreen(onSignedIn: () {}),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Вход — клиент'), findsOneWidget);
    expect(find.text('Логин'), findsOneWidget);
    expect(find.text('Пароль'), findsOneWidget);
    expect(find.text('Войти'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
