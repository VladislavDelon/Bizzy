import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'web_reload_stub.dart' if (dart.library.html) 'web_reload_web.dart';

/// Переключатель вида веб-версии: «Полный сайт» (широкая
/// вёрстка с боковой навигацией) или «Как приложение»
/// (телефонная колонка в рамке). Выбор сохраняется и
/// действует сразу — на входе и внутри кабинета.
class WebViewModeSwitcher extends StatelessWidget {
  const WebViewModeSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WebViewMode>(
      valueListenable: webViewMode,
      builder: (context, mode, _) {
        return SegmentedButton<WebViewMode>(
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 10),
            ),
          ),
          segments: const [
            ButtonSegment(
              value: WebViewMode.site,
              icon: Icon(Icons.web, size: 16),
              label: Text('Сайт'),
            ),
            ButtonSegment(
              value: WebViewMode.app,
              icon: Icon(Icons.phone_iphone, size: 16),
              label: Text('Приложение'),
            ),
          ],
          selected: {mode},
          // Сохраняем выбор и перезагружаем страницу —
          // сайт/приложение открывается заново в новой вёрстке.
          onSelectionChanged: (s) async {
            await saveWebViewMode(s.first);
            reloadPage();
          },
        );
      },
    );
  }
}

/// Та же настройка строкой для меню «Ещё»/профиля.
class WebViewModeTile extends StatelessWidget {
  const WebViewModeTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WebViewMode>(
      valueListenable: webViewMode,
      builder: (context, mode, _) => SwitchListTile(
        secondary: const Icon(Icons.web),
        title: const Text('Полный сайт на большом экране'),
        subtitle: const Text('Выкл — вид как в мобильном приложении'),
        value: mode == WebViewMode.site,
        onChanged: (v) async {
          await saveWebViewMode(v ? WebViewMode.site : WebViewMode.app);
          reloadPage();
        },
      ),
    );
  }
}
