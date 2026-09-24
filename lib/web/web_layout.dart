import 'package:flutter/material.dart';

import '../app_theme.dart';

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
          onSelectionChanged: (s) => saveWebViewMode(s.first),
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
        onChanged: (v) =>
            saveWebViewMode(v ? WebViewMode.site : WebViewMode.app),
      ),
    );
  }
}
