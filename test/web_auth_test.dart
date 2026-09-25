import 'package:bizzy_app/app_theme.dart';
import 'package:bizzy_app/web/web_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('web auth screen renders login form', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: bizzyTheme(Brightness.dark),
        // Как в main_web.dart — русская локаль через Global-делегаты.
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: WebAuthScreen(onSignedIn: () {}),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    // По умолчанию — регистрация: новому посетителю сначала
    // нужен аккаунт; «Войти» — текстовая ссылка снизу.
    expect(find.text('Регистрация — клиент'), findsOneWidget);
    expect(find.text('Логин'), findsOneWidget);
    expect(find.text('Пароль'), findsOneWidget);
    expect(find.text('Зарегистрироваться'), findsOneWidget);
    expect(find.text('Войти'), findsOneWidget);
    // Широкий экран — сайт-лендинг: герой-панель о том,
    // что это запись на бьюти-услуги, и переключатель вида.
    expect(find.text('Онлайн-запись на бьюти-услуги'), findsOneWidget);
    expect(find.text('Сайт'), findsOneWidget);
    expect(find.text('Приложение'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web auth compact layout on narrow screen', (tester) async {
    tester.view.physicalSize = const Size(480, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: bizzyTheme(Brightness.dark),
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: WebAuthScreen(onSignedIn: () {}),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    // Узкий экран — телефонная заставка без герой-панели,
    // но переключатель вида доступен и тут.
    expect(find.text('Регистрация — клиент'), findsOneWidget);
    expect(find.text('Онлайн-запись на бьюти-услуги'), findsNothing);
    expect(find.text('Приложение'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
