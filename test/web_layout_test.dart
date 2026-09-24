import 'package:bizzy_app/app_theme.dart';
import 'package:bizzy_app/web/web_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('web view mode switcher toggles and persists', (tester) async {
    SharedPreferences.setMockInitialValues({});
    webViewMode.value = WebViewMode.site;
    addTearDown(() => webViewMode.value = WebViewMode.site);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: WebViewModeSwitcher())),
    );
    expect(find.text('Сайт'), findsOneWidget);
    expect(find.text('Приложение'), findsOneWidget);
    // По умолчанию — «Полный сайт».
    expect(webViewMode.value, WebViewMode.site);
    await tester.tap(find.text('Приложение'));
    await tester.pump();
    expect(webViewMode.value, WebViewMode.app);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('bizzy_web_view_mode'), 'app');
    // Загрузка сохранённого выбора.
    await loadWebViewMode();
    expect(webViewMode.value, WebViewMode.app);
  });

  testWidgets('web view mode tile switches site/app', (tester) async {
    SharedPreferences.setMockInitialValues({});
    webViewMode.value = WebViewMode.site;
    addTearDown(() => webViewMode.value = WebViewMode.site);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: WebViewModeTile()),
      ),
    );
    expect(find.text('Полный сайт на большом экране'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(webViewMode.value, WebViewMode.app);
  });
}
