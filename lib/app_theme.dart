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
/// По диагонали от жёлтого к глубокому оранжевому — объёмнее.
const bizzyAccentGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFFFE633), Color(0xFFFFB300), Color(0xFFFF6D00)],
  stops: [0.0, 0.55, 1.0],
);

/// Оранжевый заменитель жёлтого акцента там, где градиент
/// недоступен (индикатор навигации, чипы, иконки).
const bizzyAccentColor = Color(0xFFFF8F00);

/// Тот же градиент, но мягче — для широких поверхностей
/// (индикатор навигации, выбранные чипы), где глубокий
/// оранжевый был бы слишком кричащим.
const bizzySoftGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFFFF176), Color(0xFFFFB74D)],
);

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
Widget bizzyNavBar(
  BuildContext context, {
  required Widget child,
  // «Вид Bizzy» — фишка только клиента: в шелле мастера/салона
  // передаём bizzy=false, чтобы мёдная плашка не «протекала»,
  // если флаг остался включённым после смены аккаунта.
  bool bizzy = true,
}) {
  if (!bizzyGlassActive(context)) {
    // В тёмной теме стекла нет, но лейблы всё равно жмём до 11pt —
    // иначе длинные подписи («Приглашения», «Избранное»)
    // переносятся посреди слова на узких экранах. Системный
    // масштаб шрифта зажимаем: увеличенный шрифт в настройках
    // телефона тоже рвал слова на две строки.
    return MediaQuery.withNoTextScaling(
      child: Theme(
        data: Theme.of(context).copyWith(
          navigationBarTheme: Theme.of(context).navigationBarTheme.copyWith(
            labelTextStyle: WidgetStateProperty.resolveWith(
              (states) => TextStyle(
                fontSize: 11,
                height: 1.1,
                fontWeight: states.contains(WidgetState.selected)
                    ? FontWeight.w600
                    : FontWeight.w500,
              ),
            ),
          ),
        ),
        child: child,
      ),
    );
  }
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
          child: ValueListenableBuilder<bool>(
            valueListenable: appBizzyLook,
            builder: (context, lookOn, _) {
              final look = lookOn && bizzy;
              return Container(
                // Градиент сверху-вниз — эффект iOS-материала:
                // верх светлее, низ прозрачнее, блюр читается.
                // При «Вид Bizzy» плашка тёплая — мёдный градиент.
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: look
                        ? [
                            const Color(0xFFFFE0B2).withValues(alpha: 0.88),
                            const Color(0xFFFFB74D).withValues(alpha: 0.55),
                          ]
                        : [
                            Colors.white.withValues(alpha: 0.72),
                            Colors.white.withValues(alpha: 0.42),
                          ],
                  ),
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    navigationBarTheme: Theme.of(context).navigationBarTheme
                        .copyWith(
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
                  child: MediaQuery.withNoTextScaling(child: child),
                ),
              );
            },
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
  return Padding(padding: const EdgeInsets.only(bottom: 88), child: child);
}

/// «Стеклянная» карточка — полупрозрачная белая панель с тонкой
/// светлой кромкой. Используйте на светлой теме поверх фона.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.margin, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    if (!bizzyGlassActive(context)) {
      return Card(
        margin: margin,
        child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
      );
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
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
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
    scaffoldBackgroundColor: isLight ? const Color(0xFFF2F4FA) : Colors.black,
    cardTheme: isLight
        ? CardThemeData(
            color: Colors.white.withValues(alpha: 0.62),
            elevation: 0,
            margin: const EdgeInsets.all(8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.9)),
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
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
          )
        : null,
    appBarTheme: AppBarTheme(
      backgroundColor: isLight
          ? Colors.white.withValues(alpha: 0.7)
          : Colors.black,
      foregroundColor: isLight ? Colors.black : Colors.white,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: isLight ? Colors.black : Colors.white),
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
      backgroundColor: isLight
          ? Colors.white.withValues(alpha: 0.62)
          : Colors.black,
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
      builders: {TargetPlatform.android: ZoomPageTransitionsBuilder()},
    ),
  );
}

/// Тема клиента при включённом «Вид Bizzy»: жёлтые акценты
/// (primary, индикатор навигации, FAB, чипы) уходят в тёплый
/// оранжевый. Сами кнопки делаются градиентными с аурой через
/// [bizzyFilledButton] и [bizzyFab] — тема умеет только цвета.
ThemeData bizzyClientTheme(ThemeData base) {
  final cs = base.colorScheme;
  return base.copyWith(
    colorScheme: cs.copyWith(
      primary: const Color(0xFFE65100),
      // Тёплые «медовые» поверхности вместо жёлто-серых.
      primaryContainer: const Color(0xFFFFE0B2),
      secondaryContainer: const Color(0xFFFFF3D6),
      tertiaryContainer: const Color(0xFFFFECB3),
      inversePrimary: bizzyAccentColor,
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      indicatorColor: bizzyAccentColor.withValues(alpha: 0.9),
    ),
    floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
      backgroundColor: bizzyAccentColor,
      foregroundColor: Colors.black,
    ),
    progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
      color: bizzyAccentColor,
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      actionTextColor: bizzyAccentColor,
    ),
  );
}

/// Градиентная поверхность «Вид Bizzy» с аурой: в покое — мягкое
/// оранжевое свечение, при нажатии аура разгорается и кнопка
/// слегка ужимается — объёмный отклик как у iOS-кнопок.
class _BizzyGlow extends StatefulWidget {
  const _BizzyGlow({
    required this.onPressed,
    required this.child,
    required this.radius,
    required this.padding,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  State<_BizzyGlow> createState() => _BizzyGlowState();
}

class _BizzyGlowState extends State<_BizzyGlow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: AnimatedScale(
        scale: _pressed ? 0.965 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            gradient: bizzyAccentGradient,
            borderRadius: BorderRadius.circular(widget.radius),
            boxShadow: [
              // Аура — при нажатии оранжевое свечение разгорается.
              BoxShadow(
                color: bizzyAccentColor.withValues(
                  alpha: _pressed ? 0.75 : 0.4,
                ),
                blurRadius: _pressed ? 30 : 16,
                spreadRadius: _pressed ? 2 : 0,
                offset: Offset(0, _pressed ? 3 : 7),
              ),
            ],
          ),
          // Верхний блик — кнопка выглядит выпуклой, как стекло.
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.55],
              colors: [
                Colors.white.withValues(alpha: _pressed ? 0.18 : 0.32),
                Colors.white.withValues(alpha: 0),
              ],
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onPressed,
              onHighlightChanged: enabled
                  ? (h) => setState(() => _pressed = h)
                  : null,
              borderRadius: BorderRadius.circular(widget.radius),
              splashColor: Colors.white.withValues(alpha: 0.4),
              highlightColor: Colors.white.withValues(alpha: 0.12),
              child: Padding(padding: widget.padding, child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Основная кнопка: при «Вид Bizzy» — оранжево-жёлтый градиент
/// с аурой при нажатии, иначе обычный FilledButton.
Widget bizzyFilledButton({
  required VoidCallback? onPressed,
  required Widget child,
  Widget? icon,
}) {
  return ValueListenableBuilder<bool>(
    valueListenable: appBizzyLook,
    builder: (context, on, _) {
      if (!on) {
        return icon == null
            ? FilledButton(onPressed: onPressed, child: child)
            : FilledButton.icon(onPressed: onPressed, icon: icon, label: child);
      }
      return _BizzyGlow(
        onPressed: onPressed,
        radius: 24,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              IconTheme(
                data: const IconThemeData(color: Colors.black, size: 20),
                child: icon,
              ),
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
      );
    },
  );
}

/// FAB: при «Вид Bizzy» — градиентная «капля» с аурой,
/// иначе обычный FloatingActionButton.extended.
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
      return _BizzyGlow(
        onPressed: onPressed,
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
      );
    },
  );
}
