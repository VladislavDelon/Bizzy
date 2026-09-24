import 'package:bizzy_app/app_theme.dart';
import 'package:bizzy_app/cloud/cloud_service.dart';
import 'package:bizzy_app/web/provider_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
  theme: bizzyTheme(Brightness.dark),
  locale: const Locale('ru'),
  supportedLocales: const [Locale('ru'), Locale('en')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: child,
);

void main() {
  setUp(() {
    // Без Supabase облачные вызовы падают — вкладки показывают
    // свои состояния ошибки, а навигация остаётся рабочей.
  });

  testWidgets('салон: пять вкладок как в мобильном приложении', (tester) async {
    // Высокий вьюпорт — весь список «Ещё» помещается без скролла.
    tester.view.physicalSize = const Size(900, 1700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        ProviderHomeWeb(
          profile: const CloudProfile(
            id: 'salon-1',
            role: 'salon',
            name: 'Салон Люкс',
            phone: '',
          ),
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pump();
    for (final label in ['Записи', 'Мастера', 'Клиенты', 'Услуги', 'Ещё']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(tester.takeException(), isNull);

    // «Ещё» — разделы салона.
    await tester.tap(find.text('Ещё'));
    await tester.pump();
    for (final label in [
      'Профиль салона',
      'Расписание команды',
      'Рабочие часы',
      'Закрытые дни и часы',
      'Сертификаты',
      'Чёрный список',
      'Отзывы обо мне',
      'Статистика',
      'Honey и акции',
      'Логин и пароль',
      'Выйти из аккаунта',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('мастер: вторая вкладка — приглашения от салонов', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        ProviderHomeWeb(
          profile: const CloudProfile(
            id: 'master-1',
            role: 'master',
            name: 'Ольга',
            phone: '',
          ),
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pump();
    for (final label in ['Записи', 'Салоны', 'Клиенты', 'Услуги', 'Ещё']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    // FAB «Новая запись» на вкладке записей.
    expect(find.text('Новая запись'), findsOneWidget);

    await tester.tap(find.text('Ещё'));
    await tester.pump();
    expect(find.text('Мой профиль'), findsWidgets);
    // У мастера-одиночки нет «Расписание команды».
    expect(find.text('Расписание команды'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
