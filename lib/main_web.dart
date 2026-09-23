import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';
import 'cloud/client_app.dart';
import 'cloud/cloud_service.dart';
import 'cloud/supabase_config.dart';
import 'web/provider_home.dart';
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
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ru'), Locale('en')],
          locale: const Locale('ru'),
          // Десктопный браузер: контент по центру, не растягиваем
          // телефонные экраны на весь монитор.
          builder: (context, child) => Container(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: ClipRect(child: child),
              ),
            ),
          ),
          home: _loading
              ? const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                )
              : _profile == null
              ? WebAuthScreen(onSignedIn: _resolveSession)
              : _profile!.role == 'client'
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
                ),
        );
      },
    );
  }
}
