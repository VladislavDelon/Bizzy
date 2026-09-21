import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Тема оформления приложения: system / light / dark.
/// Светлая тема оформлена в «стеклянном» стиле: полупрозрачные
/// карточки и нижняя навигация с блюром, как на iPhone.
final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.system);

const bizzySeedColor = Color(0xFFFFD600);

const _themePrefsKey = 'bizzy_theme_mode';

ThemeMode themeModeFromString(String? value) {
  return switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

String themeModeToString(ThemeMode value) {
  return switch (value) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    _ => 'system',
  };
}

Future<void> loadAppTheme() async {
  final prefs = await SharedPreferences.getInstance();
  appThemeMode.value = themeModeFromString(prefs.getString(_themePrefsKey));
}

Future<void> saveAppTheme(ThemeMode value) async {
  appThemeMode.value = value;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_themePrefsKey, themeModeToString(value));
}

String themeModeLabel(ThemeMode value) {
  return switch (value) {
    ThemeMode.light => 'Светлая',
    ThemeMode.dark => 'Тёмная',
    _ => 'Системная',
  };
}

/// Диалог «Внешний вид» — доступен из профилей всех ролей.
Future<void> showAppearancePicker(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return ValueListenableBuilder<ThemeMode>(
        valueListenable: appThemeMode,
        builder: (context, current, _) {
          Widget tile(ThemeMode mode, IconData icon, String subtitle) {
            final selected = current == mode;
            return ListTile(
              leading: Icon(icon),
              title: Text(themeModeLabel(mode)),
              subtitle: Text(subtitle),
              trailing: selected ? const Icon(Icons.check_circle) : null,
              onTap: () {
                saveAppTheme(mode);
                Navigator.of(context).pop();
              },
            );
          }

          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                tile(
                  ThemeMode.system,
                  Icons.brightness_auto,
                  'Как в настройках телефона',
                ),
                tile(
                  ThemeMode.light,
                  Icons.light_mode_outlined,
                  'Стеклянный стиль — полупрозрачные панели',
                ),
                tile(
                  ThemeMode.dark,
                  Icons.dark_mode_outlined,
                  'Тёмный фон, спокойный контраст',
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      );
    },
  );
}

/// true, когда сейчас активна светлая «стеклянная» тема —
/// нижняя навигация полупрозрачная, контент заходит под неё.
bool bizzyGlassActive(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light;

/// Обёртка нижней навигации: в светлой теме — плавающая
/// скруглённая «стеклянная» плашка с блюром (как на iPhone),
/// в тёмной — обычная панель.
/// Требует Scaffold(extendBody: true), иначе блюру нечего
/// размывать.
Widget bizzyNavBar(BuildContext context, {required Widget child}) {
  if (!bizzyGlassActive(context)) return child;
  const radius = 30.0;
  return Padding(
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
    // Тень и светлая кромка — снаружи клипа, блюр — внутри.
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: Container(
            color: Colors.white.withValues(alpha: 0.55),
            child: Theme(
              data: Theme.of(context).copyWith(
                navigationBarTheme:
                    Theme.of(context).navigationBarTheme.copyWith(
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                          height: 64,
                        ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

/// FAB во вкладке: в «стеклянной» светлой теме контент заходит под
/// полупрозрачную нижнюю навигацию (extendBody), поэтому FAB
/// поднимаем над ней. На экранах, открытых поверх табов, навигации
/// нет — небольшой подъём там просто визуальный и безвреден.
Widget bizzyTabFab(BuildContext context, {required Widget child}) {
  if (!bizzyGlassActive(context)) return child;
  return Padding(
    padding: const EdgeInsets.only(bottom: 88),
    child: child,
  );
}

/// «Стеклянная» карточка — полупрозрачная белая панель с тонкой
/// светлой кромкой. Используйте на светлой теме поверх фона.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.margin,
    this.padding,
  });

  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    if (!bizzyGlassActive(context)) {
      return Card(margin: margin, child: Padding(
        padding: padding ?? EdgeInsets.zero,
        child: child,
      ));
    }
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.zero,
        child: child,
      ),
    );
  }
}

ThemeData bizzyTheme(Brightness brightness) {
  const seedColor = bizzySeedColor;
  final isLight = brightness == Brightness.light;
  final unselectedColor = isLight ? Colors.grey : Colors.grey[400]!;
  const selectedIconColor = Colors.black;
  final selectedLabelColor = isLight ? Colors.black : Colors.white;
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    ),
    useMaterial3: true,
    // Светлая тема — холодный полупрозрачный фон, чтобы карточки
    // и навигация читались как «стекло».
    scaffoldBackgroundColor:
        isLight ? const Color(0xFFF2F4FA) : Colors.black,
    cardTheme: isLight
        ? CardThemeData(
            color: Colors.white.withValues(alpha: 0.62),
            elevation: 0,
            margin: const EdgeInsets.all(8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          )
        : null,
    dialogTheme: isLight
        ? DialogThemeData(
            backgroundColor: Colors.white.withValues(alpha: 0.92),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          )
        : null,
    // Нижние шторки тоже «матовые» — полупрозрачная белая панель.
    bottomSheetTheme: isLight
        ? BottomSheetThemeData(
            backgroundColor: Colors.white.withValues(alpha: 0.88),
            modalBackgroundColor: Colors.white.withValues(alpha: 0.88),
            shape: const RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(28)),
            ),
          )
        : null,
    appBarTheme: AppBarTheme(
      backgroundColor:
          isLight ? Colors.white.withValues(alpha: 0.7) : Colors.black,
      foregroundColor: isLight ? Colors.black : Colors.white,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(
        color: isLight ? Colors.black : Colors.white,
      ),
      titleTextStyle: TextStyle(
        color: isLight ? Colors.black : Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w500,
      ),
      elevation: 0,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: seedColor,
      foregroundColor: Colors.black,
      extendedTextStyle: TextStyle(color: Colors.black),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor:
          isLight ? Colors.white.withValues(alpha: 0.62) : Colors.black,
      elevation: 0,
      indicatorColor: seedColor,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? selectedIconColor : unselectedColor,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          color: selected ? selectedLabelColor : unselectedColor,
        );
      }),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
      },
    ),
  );
}
