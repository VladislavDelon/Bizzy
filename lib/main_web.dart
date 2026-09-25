import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';
import 'cloud/client_app.dart';
import 'cloud/cloud_service.dart';
import 'cloud/supabase_config.dart';
import 'web/provider_home.dart';
import 'web/seasonal_background.dart';
import 'web/web_auth.dart';

/// Веб-версия Bizzy: только облако — регистрация/вход клиента,
/// мастера и салона, записи и расписание синхронизированы
/// с мобильным приложением через тот же Supabase.
///
/// Сборка: flutter build web --release -t lib/main_web.dart
/// --base-href /Bizzy/
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
    );
  } catch (_) {
    // Повторная инициализация при hot-restart — не страшно.
  }
  await loadAppTheme();
  await loadBizzyLook();
  await loadWebViewMode();
  // Русские месяцы/дни в TableCalendar («Закрытые дни и часы»).
  await initializeDateFormatting('ru_RU', null);
  runApp(const BizzyWebApp());
}

class BizzyWebApp extends StatefulWidget {
  const BizzyWebApp({super.key});

  @override
  State<BizzyWebApp> createState() => _BizzyWebAppState();
}

class _BizzyWebAppState extends State<BizzyWebApp> {
  final _cloud = CloudService();
  CloudProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolveSession();
    // Смена сессии (вход/выход в другой вкладке) — перечитываем профиль.
    _cloud.authChanges.listen((_) => _resolveSession());
  }

  Future<void> _resolveSession() async {
    if (!cloudSignedIn) {
      if (mounted) {
        setState(() {
          _profile = null;
          _loading = false;
        });
      }
      return;
    }
    try {
      final p = await _cloud.myProfile();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    await _cloud.signOut();
    await _resolveSession();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Bizzy',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: bizzyTheme(Brightness.light),
          darkTheme: bizzyTheme(Brightness.dark),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ru'), Locale('en')],
          locale: const Locale('ru'),
          home: _loading
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : _profile == null
              // Экран входа — на весь экран со своим градиентом.
              ? WebAuthScreen(onSignedIn: _resolveSession)
              // Внутренние экраны: на широком окне не растягиваем
              // телефонную разметку на весь монитор — по центру.
              : LayoutBuilder(
                  builder: (context, c) {
                    final Widget home = _profile!.role == 'client'
                        ? ClientHome(
                            profile: _profile!,
                            onSignOut: _signOut,
                            onDeleteAccount: () async {
                              await _cloud.deleteMyAccount();
                              await _resolveSession();
                            },
                            onProfileUpdated: _resolveSession,
                          )
                        : ProviderHomeWeb(
                            profile: _profile!,
                            onSignOut: _signOut,
                          );
                    if (c.maxWidth <= 720) return home;
                    // На широком экране за всем — сезонный
                    // анимированный фон (снег/лепестки/пыльца/
                    // листопад). В режиме «сайт» внутренние
                    // Scaffold прозрачные и фон виден за
                    // контентом; в режиме «приложение» — по
                    // краям телефонной рамки.
                    return SeasonalBackdrop(
                      child: ValueListenableBuilder<WebViewMode>(
                        valueListenable: webViewMode,
                        builder: (context, mode, _) {
                          // Режим «Полный сайт»: контент на всю ширину,
                          // навигация сбоку — внутри самих экранов.
                          if (mode == WebViewMode.site) return home;
                          // Режим «Как приложение»: телефонная колонка
                          // 430px в скруглённой рамке с тенью по центру;
                          // позади — сезонный фон сайта.
                          final scheme = Theme.of(context).colorScheme;
                          final dark = scheme.brightness == Brightness.dark;
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 430,
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(
                                      color: dark
                                          ? Colors.white.withValues(alpha: 0.14)
                                          : Colors.black.withValues(
                                              alpha: 0.10,
                                            ),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: dark ? 0.6 : 0.18,
                                        ),
                                        blurRadius: 48,
                                        offset: const Offset(0, 18),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(30),
                                    child: home,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
