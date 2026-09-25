import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cloud/animated_logo.dart';
import '../cloud/cloud_service.dart';
import 'web_layout.dart';

/// Веб-вход и регистрация: клиент, мастер или салон.
/// Интро: логотип появляется по центру экрана, затем поднимается
/// наверх, под ним плавно выезжает карточка с формой.
/// Карточка адаптивна: на десктопе — по центру ~440px, на
/// мобильном браузере — почти во всю ширину.
class WebAuthScreen extends StatefulWidget {
  const WebAuthScreen({super.key, required this.onSignedIn});

  final VoidCallback onSignedIn;

  @override
  State<WebAuthScreen> createState() => _WebAuthScreenState();
}

class _WebAuthScreenState extends State<WebAuthScreen>
    with TickerProviderStateMixin {
  final _cloud = CloudService();
  final _formKey = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _refCode = TextEditingController();
  final _salonKey = TextEditingController();

  late final AnimationController _controller;
  late final Animation<double> _lift;
  late final Animation<double> _titleOpacity;
  late final Animation<double> _cardOpacity;
  late final Animation<Offset> _cardSlide;

  String _role = 'client';
  // По умолчанию — регистрация: новым посетителям сайта
  // сначала нужен аккаунт, вход — ссылкой снизу.
  bool _register = true;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2300),
    );
    // Логотип появляется по центру экрана, затем поднимается наверх.
    _lift = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.32, 0.62, curve: Curves.easeInOutCubic),
      ),
    );
    _titleOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.48, 0.72, curve: Curves.easeOut),
      ),
    );
    _cardOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.58, 0.92, curve: Curves.easeOut),
      ),
    );
    _cardSlide = Tween<Offset>(begin: const Offset(0, 0.14), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.58, 0.95, curve: Curves.easeOutCubic),
          ),
        );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _login.dispose();
    _password.dispose();
    _name.dispose();
    _refCode.dispose();
    _salonKey.dispose();
    super.dispose();
  }

  String _describeError(Object e) {
    if (e is AuthException) {
      final msg = e.message.toLowerCase();
      if (msg.contains('invalid') || msg.contains('credential')) {
        return 'Неверный логин или пароль';
      }
      if (msg.contains('already') || msg.contains('registered')) {
        return 'Такой логин уже занят';
      }
      if (msg.contains('password')) {
        return 'Пароль слишком простой (минимум 6 символов)';
      }
      return e.message;
    }
    return 'Нет подключения к серверу. Проверьте интернет.';
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await _cloud.signUp(
          login: _login.text.trim(),
          password: _password.text,
          role: _role,
          name: _name.text.trim(),
          salonKey: _role == 'master' ? _salonKey.text.trim() : '',
        );
        // Реферальный код друга — только у клиента.
        final code = _refCode.text.trim();
        if (_role == 'client' && code.isNotEmpty) {
          try {
            await _cloud.applyReferralCode(code);
          } catch (_) {}
        }
      } else {
        await _cloud.signIn(_login.text.trim(), _password.text);
      }
      widget.onSignedIn();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _describeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = scheme.brightness == Brightness.light
        ? [Colors.white, scheme.primary.withValues(alpha: 0.08)]
        : [Colors.black, scheme.primary.withValues(alpha: 0.12)];

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: background,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) {
              // Широкий экран — сайт-лендинг: презентация сервиса
              // слева, карточка входа справа. Узкий — телефонная
              // заставка: логотип по центру поднимается наверх.
              if (c.maxWidth > 880) return _buildWide(context, c, scheme);
              return _buildCompact(context, c, scheme);
            },
          ),
        ),
      ),
    );
  }

  /// Телефонная заставка: логотип появляется по центру экрана,
  /// поднимается наверх, под ним выезжает карточка входа.
  Widget _buildCompact(
    BuildContext context,
    BoxConstraints c,
    ColorScheme scheme, {
    bool hero = false,
  }) {
    final roleName = switch (_role) {
      'master' => 'мастер',
      'salon' => 'салон',
      _ => 'клиент',
    };
    final logoSize = c.maxWidth > 760 ? 88.0 : 84.0;
    final startSize = logoSize * 1.9;
    final endTop = (c.maxHeight * 0.04).clamp(10.0, 36.0);
    // Стартовая позиция — центр экрана, конечная — верх.
    final startTop = math.max(c.maxHeight / 2 - startSize / 2, endTop);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final lift = _lift.value;
        final logoTop = startTop + (endTop - startTop) * lift;
        final curSize = startSize + (logoSize - startSize) * lift;

        return Stack(
          children: [
            // Заголовок и карточка — под конечной позицией логотипа.
            // На десктопе всё помещается без прокрутки; скролл —
            // только запасной вариант для низких окон.
            Positioned.fill(
              top: hero ? 8 : endTop + logoSize + 6,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight:
                        c.maxHeight - (hero ? 8 : endTop + logoSize + 6) - 16,
                  ),
                  child: Column(
                    // В широкой вёрстке карточка стоит
                    // по центру правой колонки.
                    mainAxisAlignment: hero
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    mainAxisSize: hero ? MainAxisSize.max : MainAxisSize.min,
                    children: [
                      FadeTransition(
                        opacity: _titleOpacity,
                        child: Text.rich(
                          TextSpan(
                            text: 'Добро пожаловать в ',
                            children: [
                              TextSpan(
                                text: 'Bizzy',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: scheme.primary,
                                ),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Карточка входа — выезжает снизу после логотипа.
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) => Opacity(
                          opacity: _cardOpacity.value,
                          child: FractionalTranslation(
                            translation: _cardSlide.value,
                            child: child,
                          ),
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: Card(
                            elevation: 10,
                            shadowColor: scheme.primary.withValues(alpha: 0.25),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      _register
                                          ? 'Регистрация — $roleName'
                                          : 'Вход — $roleName',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge,
                                    ),
                                    const SizedBox(height: 16),
                                    SegmentedButton<String>(
                                      style: const ButtonStyle(
                                        // Узкий экран телефона:
                                        // компактнее, лейбл жмётся,
                                        // слово не рвётся пополам.
                                        visualDensity: VisualDensity.compact,
                                        padding: WidgetStatePropertyAll(
                                          EdgeInsets.symmetric(horizontal: 6),
                                        ),
                                      ),
                                      segments: const [
                                        ButtonSegment(
                                          value: 'client',
                                          icon: Icon(
                                            Icons.person_outline,
                                            size: 18,
                                          ),
                                          label: _NoWrapLabel('Клиент'),
                                        ),
                                        ButtonSegment(
                                          value: 'master',
                                          icon: Icon(
                                            Icons.content_cut,
                                            size: 18,
                                          ),
                                          label: _NoWrapLabel('Мастер'),
                                        ),
                                        ButtonSegment(
                                          value: 'salon',
                                          icon: Icon(
                                            Icons.storefront_outlined,
                                            size: 18,
                                          ),
                                          label: _NoWrapLabel('Салон'),
                                        ),
                                      ],
                                      selected: {_role},
                                      onSelectionChanged: _busy
                                          ? null
                                          : (s) =>
                                                setState(() => _role = s.first),
                                    ),
                                    const SizedBox(height: 16),
                                    if (_register) ...[
                                      TextFormField(
                                        controller: _name,
                                        enabled: !_busy,
                                        textCapitalization:
                                            TextCapitalization.words,
                                        decoration: InputDecoration(
                                          labelText: _role == 'salon'
                                              ? 'Название салона'
                                              : 'Ваше имя',
                                          border: const OutlineInputBorder(),
                                        ),
                                        validator: (v) =>
                                            (v?.trim().length ?? 0) < 2
                                            ? 'Минимум 2 символа'
                                            : null,
                                      ),
                                      const SizedBox(height: 12),
                                    ],
                                    TextFormField(
                                      controller: _login,
                                      enabled: !_busy,
                                      autocorrect: false,
                                      decoration: const InputDecoration(
                                        labelText: 'Логин',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      validator: (v) {
                                        final s = v?.trim() ?? '';
                                        if (s.length < 3) {
                                          return 'Минимум 3 символа';
                                        }
                                        if (s.contains(' ')) {
                                          return 'Без пробелов';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _password,
                                      enabled: !_busy,
                                      obscureText: !_showPassword,
                                      decoration: const InputDecoration(
                                        labelText: 'Пароль',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      onFieldSubmitted: (_) => _submit(),
                                      validator: (v) =>
                                          v == null || v.length < 6
                                          ? 'Минимум 6 символов'
                                          : null,
                                    ),
                                    InkWell(
                                      onTap: _busy
                                          ? null
                                          : () => setState(
                                              () => _showPassword =
                                                  !_showPassword,
                                            ),
                                      borderRadius: BorderRadius.circular(8),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 4,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Checkbox(
                                              value: _showPassword,
                                              onChanged: _busy
                                                  ? null
                                                  : (v) => setState(
                                                      () => _showPassword =
                                                          v ?? false,
                                                    ),
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            Text(
                                              'Показать пароль',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (_register && _role == 'client') ...[
                                      TextFormField(
                                        controller: _refCode,
                                        enabled: !_busy,
                                        autocorrect: false,
                                        textCapitalization:
                                            TextCapitalization.characters,
                                        decoration: const InputDecoration(
                                          labelText:
                                              'Код друга (необязательно)',
                                          hintText:
                                              'BZ-XXXXXX — скидка вам и другу',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                    ],
                                    if (_register && _role == 'master') ...[
                                      TextFormField(
                                        controller: _salonKey,
                                        enabled: !_busy,
                                        autocorrect: false,
                                        decoration: const InputDecoration(
                                          labelText:
                                              'Ключ салона (необязательно)',
                                          hintText: 'BZ-XXXXXX — если вы сотрудник салона',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                    ],
                                    if (_error != null) ...[
                                      Text(
                                        _error!,
                                        style: TextStyle(color: scheme.error),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                    const SizedBox(height: 4),
                                    FilledButton(
                                      onPressed: _busy ? null : _submit,
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        _busy
                                            ? 'Подождите…'
                                            : (_register
                                                  ? 'Зарегистрироваться'
                                                  : 'Войти'),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => setState(() {
                                              _register = !_register;
                                              _error = null;
                                            }),
                                      child: Text(
                                        _register ? 'Войти' : 'Нет аккаунта — зарегистрироваться',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Логотип: появляется по центру экрана,
            // затем поднимается наверх и уменьшается.
            // В широкой вёрстке логотип живёт в герой-
            // панели слева — здесь не дублируем.
            if (!hero)
              Positioned(
                top: logoTop,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: AnimatedLogo(animation: _controller, size: curSize),
                  ),
                ),
              ),
            // Переключатель «Сайт / Приложение» — угол.
            if (!hero)
              Positioned(
                top: 4,
                right: 4,
                child: FadeTransition(
                  opacity: _titleOpacity,
                  child: const WebViewModeSwitcher(),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Широкая вёрстка — полноценный сайт-лендинг: слева
  /// презентация сервиса (что это — запись на бьюти-услуги),
  /// справа знакомая карточка входа с той же анимацией.
  Widget _buildWide(
    BuildContext context,
    BoxConstraints c,
    ColorScheme scheme,
  ) {
    return Stack(
      children: [
        Row(
          children: [
            Expanded(flex: 11, child: _heroPanel(context, scheme)),
            Expanded(
              flex: 9,
              child: _buildCompact(context, c, scheme, hero: true),
            ),
          ],
        ),
        // Переключатель «Сайт / Приложение» — сверху справа.
        Positioned(
          top: 8,
          right: 16,
          child: FadeTransition(
            opacity: _titleOpacity,
            child: const WebViewModeSwitcher(),
          ),
        ),
      ],
    );
  }

  /// Левая панель сайта: логотип, что за сервис, категории
  /// бьюти-услуг — чтобы было ясно, куда попал посетитель.
  Widget _heroPanel(BuildContext context, ColorScheme scheme) {
    final theme = Theme.of(context);
    return FadeTransition(
      opacity: _titleOpacity,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(48, 16, 24, 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedLogo(animation: _controller, size: 110),
                const SizedBox(width: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bizzy',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      ),
                    ),
                    Text(
                      'Онлайн-запись на бьюти-услуги',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 32),
            Text(
              'Стрижка, наращивание, маникюр —\n'
              'запишитесь к мастеру в пару кликов',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Клиентам — мастера и салоны рядом, свободные окна,\n'
              'рейтинг и отзывы. Мастерам и салонам — расписание,\n'
              'клиенты, услуги и статистика в одном кабинете.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 26),
            const Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _HeroTile(Icons.content_cut, 'Стрижки'),
                _HeroTile(Icons.face_retouching_natural, 'Наращивание'),
                _HeroTile(Icons.brush_outlined, 'Маникюр'),
                _HeroTile(Icons.spa_outlined, 'Массаж и уход'),
                _HeroTile(Icons.auto_awesome, 'Макияж'),
              ],
            ),
            const SizedBox(height: 26),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                // Прямая ссылка на свежий APK из последнего релиза.
                FilledButton.tonalIcon(
                  onPressed: () => launchUrl(
                    Uri.parse(
                      'https://github.com/VladislavDelon/Bizzy/'
                      'releases/latest/download/app-release.apk',
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.android),
                  label: const Text('Скачать приложение для Android'),
                ),
                // iOS: неподписанный .ipa из релиза + инструкция
                // по установке через Sideloadly/AltStore.
                OutlinedButton.icon(
                  onPressed: () => _showIosInstallDialog(context),
                  icon: const Icon(Icons.phone_iphone),
                  label: const Text('Установить на iPhone'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Подпись сегмента выбора роли: на узком экране ужимается
/// по ширине (FittedBox), но никогда не переносит слово
/// посередине — «Клиент» остаётся «Клиент» в одну строку.
class _NoWrapLabel extends StatelessWidget {
  const _NoWrapLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, maxLines: 1, softWrap: false),
    );
  }
}

/// Диалог «Установить на iPhone»: шаги для бесплатной
/// установки неподписанного .ipa через Sideloadly/AltStore.
void _showIosInstallDialog(BuildContext context) {
  const steps = [
    'Скачайте файл bizzy-ios-unsigned.ipa кнопкой ниже.',
    'На компьютере (Windows или Mac) установите бесплатную '
        'программу Sideloadly (sideloadly.io) или AltStore.',
    'Подключите iPhone кабелем, перетащите .ipa в Sideloadly, '
        'введите свой Apple ID и нажмите Start.',
    'На iPhone откройте «Настройки → Основные → VPN и '
        'управление устройством» и нажмите «Доверять» '
        'вашему Apple ID.',
    'Бесплатная подпись живёт 7 дней — потом повторите '
        'шаг 3, все данные в приложении сохранятся.',
  ];
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(
        Icons.phone_iphone,
        size: 40,
        color: Theme.of(ctx).colorScheme.primary,
      ),
      title: const Text('Установка на iPhone', textAlign: TextAlign.center),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('${i + 1}. ${steps[i]}'),
              ),
            const SizedBox(height: 4),
            Text(
              'Push-уведомления в бесплатной установке не работают — '
              'весь остальной функционал как на Android и на сайте.',
              style: Theme.of(ctx).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton.icon(
          onPressed: () => launchUrl(
            Uri.parse(
              'https://github.com/VladislavDelon/Bizzy/'
              'releases/latest/download/bizzy-ios-unsigned.ipa',
            ),
            mode: LaunchMode.externalApplication,
          ),
          icon: const Icon(Icons.download),
          label: const Text('Скачать .ipa'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Закрыть'),
        ),
      ],
    ),
  );
}

/// Что показать по тапу на плитку категории на лендинге.
const Map<String, String> _heroTileInfo = {
  'Стрижки':
      'Женские и мужские стрижки, укладка, окрашивание, '
      'уход за волосами. Найдите парикмахера рядом и '
      'запишитесь на свободное окно за пару кликов.',
  'Наращивание':
      'Наращивание волос, ресниц и ногтей. Смотрите '
      'портфолио мастера, рейтинг и отзывы клиентов '
      'перед записью.',
  'Маникюр':
      'Маникюр и педикюр, гель-лак, укрепление и дизайн '
      'ногтей. Частные мастера и салоны с актуальным '
      'расписанием.',
  'Массаж и уход':
      'Массаж, уход за кожей, SPA-процедуры. Выбирайте '
      'специалиста по рейтингу и отзывам, записывайтесь '
      'онлайн без звонков.',
  'Макияж':
      'Дневной, вечерний и свадебный макияж, брови, '
      'обучение. Запишитесь к визажисту на удобное '
      'время прямо с сайта.',
};

/// Плитка категории услуг на герой-панели сайта — градиентная
/// «карточка-фото» с иконкой. При наведении приподнимается
/// и чуть увеличивается; по тапу показывает, что за услуги
/// в этой категории.
class _HeroTile extends StatefulWidget {
  const _HeroTile(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  State<_HeroTile> createState() => _HeroTileState();
}

class _HeroTileState extends State<_HeroTile> {
  bool _hover = false;

  void _showInfo(BuildContext context) {
    final text = _heroTileInfo[widget.label] ?? '';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          widget.icon,
          size: 40,
          color: Theme.of(ctx).colorScheme.primary,
        ),
        title: Text(widget.label, textAlign: TextAlign.center),
        content: Text(text, textAlign: TextAlign.center),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => _showInfo(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: 122,
          height: 118,
          padding: const EdgeInsets.all(10),
          // Наведение: плитка приподнимается и чуть растёт.
          transform: Matrix4.identity()
            ..translateByDouble(0.0, _hover ? -6.0 : 0.0, 0.0, 1.0)
            ..scaleByDouble(_hover ? 1.05 : 1.0, _hover ? 1.05 : 1.0, 1.0, 1.0),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? [
                      scheme.primary.withValues(alpha: _hover ? 0.42 : 0.30),
                      scheme.surfaceContainerHighest,
                    ]
                  : [
                      scheme.primary.withValues(alpha: _hover ? 0.34 : 0.22),
                      scheme.primaryContainer,
                    ],
            ),
            border: Border.all(
              color: scheme.primary.withValues(alpha: _hover ? 0.45 : 0.18),
            ),
            boxShadow: _hover
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.25),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 34, color: scheme.primary),
              const SizedBox(height: 10),
              // Подпись ужимается по ширине, но слово не рвётся.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  widget.label,
                  maxLines: 1,
                  softWrap: false,
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
