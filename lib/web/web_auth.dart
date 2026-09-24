import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cloud/animated_logo.dart';
import '../cloud/cloud_service.dart';

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
  bool _register = false;
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
    final roleName = switch (_role) {
      'master' => 'мастер',
      'salon' => 'салон',
      _ => 'клиент',
    };
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
              final logoSize = c.maxWidth > 760 ? 88.0 : 84.0;
              final startSize = logoSize * 1.9;
              final endTop = (c.maxHeight * 0.04).clamp(10.0, 36.0);
              // Стартовая позиция — центр экрана, конечная — верх.
              final startTop = math.max(
                c.maxHeight / 2 - startSize / 2,
                endTop,
              );
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
                        top: endTop + logoSize + 6,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
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
                                  constraints: const BoxConstraints(
                                    maxWidth: 440,
                                  ),
                                  child: Card(
                                    elevation: 10,
                                    shadowColor: scheme.primary.withValues(
                                      alpha: 0.25,
                                    ),
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
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding: WidgetStatePropertyAll(
                                                  EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                  ),
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
                                                  : (s) => setState(
                                                      () => _role = s.first,
                                                    ),
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
                                                  border:
                                                      const OutlineInputBorder(),
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
                                              onFieldSubmitted: (_) =>
                                                  _submit(),
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
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 4,
                                                    ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Checkbox(
                                                      value: _showPassword,
                                                      onChanged: _busy
                                                          ? null
                                                          : (v) => setState(
                                                              () =>
                                                                  _showPassword =
                                                                      v ??
                                                                      false,
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
                                            if (_register &&
                                                _role == 'client') ...[
                                              TextFormField(
                                                controller: _refCode,
                                                enabled: !_busy,
                                                autocorrect: false,
                                                textCapitalization:
                                                    TextCapitalization
                                                        .characters,
                                                decoration:
                                                    const InputDecoration(
                                                      labelText: 'Код друга (необязательно)',
                                                      hintText: 'BZ-XXXXXX — скидка вам и другу',
                                                      border:
                                                          OutlineInputBorder(),
                                                    ),
                                              ),
                                              const SizedBox(height: 12),
                                            ],
                                            if (_register &&
                                                _role == 'master') ...[
                                              TextFormField(
                                                controller: _salonKey,
                                                enabled: !_busy,
                                                autocorrect: false,
                                                decoration:
                                                    const InputDecoration(
                                                      labelText: 'Ключ салона (необязательно)',
                                                      hintText: 'BZ-XXXXXX — если вы сотрудник салона',
                                                      border:
                                                          OutlineInputBorder(),
                                                    ),
                                              ),
                                              const SizedBox(height: 12),
                                            ],
                                            if (_error != null) ...[
                                              Text(
                                                _error!,
                                                style: TextStyle(
                                                  color: scheme.error,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                            ],
                                            const SizedBox(height: 4),
                                            FilledButton(
                                              onPressed: _busy ? null : _submit,
                                              style: FilledButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 14,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                ),
                                              ),
                                              child: Text(
                                                _busy
                                                    ? 'Подождите…'
                                                    : (_register
                                                          ? 'Создать аккаунт'
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
                                                _register
                                                    ? 'Уже есть аккаунт — войти'
                                                    : 'Нет аккаунта — зарегистрироваться',
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
                      // Логотип: появляется по центру экрана,
                      // затем поднимается наверх и уменьшается.
                      Positioned(
                        top: logoTop,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Center(
                            child: AnimatedLogo(
                              animation: _controller,
                              size: curSize,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
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
