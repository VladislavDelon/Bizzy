import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cloud/animated_logo.dart';
import '../cloud/cloud_service.dart';

/// Веб-вход и регистрация: клиент, мастер или салон.
/// Тот же визуал, что у мобильного входа: анимированный логотип
/// со свечением, затем плавно выезжает карточка с формой.
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
      duration: const Duration(milliseconds: 1400),
    );
    _titleOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 0.6, curve: Curves.easeOut),
      ),
    );
    _cardOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.45, 0.85, curve: Curves.easeOut),
      ),
    );
    _cardSlide =
        Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.45, 0.9, curve: Curves.easeOutCubic),
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
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedLogo(animation: _controller, size: 120),
                  const SizedBox(height: 16),
                  FadeTransition(
                    opacity: _titleOpacity,
                    child: Column(
                      children: [
                        Text(
                          'Добро пожаловать в',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'Bizzy',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: scheme.primary,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
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
                          padding: const EdgeInsets.all(24),
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
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 16),
                                SegmentedButton<String>(
                                  segments: const [
                                    ButtonSegment(
                                      value: 'client',
                                      icon: Icon(Icons.person_outline),
                                      label: Text('Клиент'),
                                    ),
                                    ButtonSegment(
                                      value: 'master',
                                      icon: Icon(Icons.content_cut),
                                      label: Text('Мастер'),
                                    ),
                                    ButtonSegment(
                                      value: 'salon',
                                      icon: Icon(Icons.storefront_outlined),
                                      label: Text('Салон'),
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
                                  ),
                                  validator: (v) {
                                    final s = v?.trim() ?? '';
                                    if (s.length < 3) {
                                      return 'Минимум 3 символа';
                                    }
                                    if (s.contains(' ')) return 'Без пробелов';
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
                                  ),
                                  onFieldSubmitted: (_) => _submit(),
                                  validator: (v) => v == null || v.length < 6
                                      ? 'Минимум 6 символов'
                                      : null,
                                ),
                                InkWell(
                                  onTap: _busy
                                      ? null
                                      : () => setState(
                                          () =>
                                              _showPassword = !_showPassword,
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
                                                  () =>
                                                      _showPassword =
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
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
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
                                      labelText: 'Код друга (необязательно)',
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
                                      labelText: 'Ключ салона (необязательно)',
                                      hintText:
                                          'BZ-XXXXXX — если вы сотрудник салона',
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
                                      borderRadius: BorderRadius.circular(14),
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
        ),
      ),
    );
  }
}
