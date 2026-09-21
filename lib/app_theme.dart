import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Тема оформления приложения: system / light / dark.
/// Светлая тема оформлена в «стеклянном» стиле: полупрозрачные
/// карточки и нижняя навигация с блюром, как на iPhone.
final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.system);

const bizzySeedColor = Color(0xFFFFD600);

/// Клиентская фишка «Вид Bizzy»: жёлтые акценты превращаются
/// в оранжево-жёлтый градиент. Только для роли «клиент».
final ValueNotifier<bool> appBizzyLook = ValueNotifier(false);

/// Оранжево-жёлтый градиент «Вид Bizzy» — на кнопках и акцентах.
const bizzyAccentGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFFFF8F00), Color(0xFFFFD600)],
);

/// Оранжевый заменитель жёлтого акцента там, где градиент
/// недоступен (индикатор навигации, чипы, иконки).
const bizzyAccentColor = Color(0xFFFF8F00);

const _themePrefsKey = 'bizzy_theme_mode';
const _bizzyLookKey = 'bizzy_look';

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

Future<void> loadBizzyLook() async {
  final prefs = await SharedPreferences.getInstance();
  appBizzyLook.value = prefs.getBool(_bizzyLookKey) ?? false;
}

Future<void> saveBizzyLook(bool value) async {
  appBizzyLook.value = value;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_bizzyLookKey, value);
}

String themeModeLabel(ThemeMode value) {
  return switch (value) {
    ThemeMode.light => 'Светлая',
    ThemeMode.dark => 'Тёмная',
    _ => 'Системная',
  };
}

/// Диалог «Внешний вид» — доступен из профилей всех ролей.
/// [showBizzyLook] — у клиентов добавляет переключатель «Вид Bizzy»
/// (оранжево-жёлтый градиент на кнопках и акцентах).
Future<void> showAppearancePicker(
  BuildContext context, {
  bool showBizzyLook = false,
}) async {
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
                if (showBizzyLook)
                  ValueListenableBuilder<bool>(
                    valueListenable: appBizzyLook,
                    builder: (context, on, _) => SwitchListTile(
                      secondary: const Icon(Icons.auto_awesome),
                      title: const Text('Вид Bizzy'),
                      subtitle: const Text(
                        'Оранжево-жёлтый градиент на кнопках и акцентах',
                      ),
                      value: on,
                      onChanged: saveBizzyLook,
                    ),
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
    // Узкие поля — плашка шире, лейблы вкладок не обрезаются.
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
    // Тень и светлая кромка — снаружи клипа, блюр — внутри.
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.95),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 32,
            offset: const Offset(0, 10),
          ),
          // Верхний «блик» — как у настоящего стекла.
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.7),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
          child: Container(
            // Градиент сверху-вниз — эффект iOS-материала:
            // верх светлее, низ прозрачнее, блюр читается.
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.72),
                  Colors.white.withValues(alpha: 0.42),
                ],
              ),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(
                navigationBarTheme:
                    Theme.of(context).navigationBarTheme.copyWith(
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                          height: 64,
                          // 11pt — «Избранное» и «Профиль»
                          // помещаются целиком в одну строку.
                          labelTextStyle: WidgetStateProperty.resolveWith(
                            (states) => TextStyle(
                              fontSize: 11,
                              height: 1.1,
                              fontWeight: states.contains(WidgetState.selected)
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: states.contains(WidgetState.selected)
                                  ? Colors.black
                                  : Colors.grey[700],
                            ),
                          ),
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

/// Тема клиента при включённом «Вид Bizzy»: жёлтые акценты
/// (primary, индикатор навигации, FAB) уходят в оранжевый.
/// Сами кнопки делаются градиентными через [bizzyFilledButton]
/// и [bizzyFab] — тема не умеет градиенты, только цвета.
ThemeData bizzyClientTheme(ThemeData base) {
  final cs = base.colorScheme;
  return base.copyWith(
    colorScheme: cs.copyWith(
      primary: const Color(0xFFE65100),
      inversePrimary: bizzyAccentColor,
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      indicatorColor: bizzyAccentColor.withValues(alpha: 0.85),
    ),
    floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
      backgroundColor: bizzyAccentColor,
      foregroundColor: Colors.black,
    ),
    progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
      color: bizzyAccentColor,
    ),
  );
}

/// Основная кнопка: при «Вид Bizzy» — оранжево-жёлтый градиент,
/// иначе обычный FilledButton. Использовать в клиентских экранах.
Widget bizzyFilledButton({
  required VoidCallback? onPressed,
  required Widget child,
  IconData? icon,
}) {
  return ValueListenableBuilder<bool>(
    valueListenable: appBizzyLook,
    builder: (context, on, _) {
      if (!on) {
        return icon == null
            ? FilledButton(onPressed: onPressed, child: child)
            : FilledButton.icon(
                onPressed: onPressed,
                icon: Icon(icon),
                label: child,
              );
      }
      return Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              gradient: bizzyAccentGradient,
              borderRadius: BorderRadius.circular(24),
            ),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 20, color: Colors.black),
                      const SizedBox(width: 8),
                    ],
                    DefaultTextStyle(
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                      ),
                      child: child,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// FAB с градиентом при «Вид Bizzy», иначе обычный.
Widget bizzyFab({
  required VoidCallback? onPressed,
  required IconData icon,
  required String label,
}) {
  return ValueListenableBuilder<bool>(
    valueListenable: appBizzyLook,
    builder: (context, on, _) {
      if (!on) {
        return FloatingActionButton.extended(
          heroTag: null,
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        );
      }
      return Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: bizzyAccentGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: bizzyAccentColor.withValues(alpha: 0.4),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 14,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.black),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
