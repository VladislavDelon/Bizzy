import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_service.dart';

/// Анимированный логотип с масштабом, поворотом, появлением и золотым свечением.
class AnimatedLogo extends StatelessWidget {
  const AnimatedLogo({
    super.key,
    required this.animation,
    this.size = 220,
  });

  final Animation<double> animation;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
      ),
    );
    final opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );
    final rotation = Tween<double>(begin: -0.15, end: 0.0).animate(
      CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOutBack),
      ),
    );
    final glow = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: animation,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOut),
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Transform.rotate(
          angle: rotation.value,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.amber.withValues(alpha: 0.5 * glow.value),
                  blurRadius: 70 * glow.value,
                  spreadRadius: 25 * glow.value,
                ),
              ],
            ),
            child: Opacity(
              opacity: opacity.value,
              child: Transform.scale(
                scale: scale.value,
                child: child,
              ),
            ),
          ),
        );
      },
      child: Image.asset(
        'assets/icons/logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.calendar_month,
          size: size * 0.8,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// Экран «Вы клиент или мастер?» — показывается, когда нет сессии.
class RoleSelectScreen extends StatefulWidget {
  const RoleSelectScreen({super.key, this.skipLogo = false});

  /// Если true, логотип не анимируется — экран сразу показывает приветствие.
  final bool skipLogo;

  @override
  State<RoleSelectScreen> createState() => _RoleSelectScreenState();
}

class _RoleSelectScreenState extends State<RoleSelectScreen>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _welcomeOpacity;
  late final Animation<Offset> _welcomeSlide;
  late final Animation<double> _questionOpacity;
  late final Animation<double> _cardsOpacity;
  late final Animation<Offset> _cardsSlide;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
      value: widget.skipLogo ? 1.0 : 0.0,
    );

    _welcomeOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.35, 0.65, curve: Curves.easeOut),
      ),
    );
    _welcomeSlide = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.35, 0.65, curve: Curves.easeOutCubic),
      ),
    );

    _questionOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.55, 0.75, curve: Curves.easeOut),
      ),
    );

    _cardsOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.65, 0.95, curve: Curves.easeOut),
      ),
    );
    _cardsSlide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.65, 0.95, curve: Curves.easeOutCubic),
      ),
    );

    _controller.forward();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _appVersion =
          '${info.version}${info.buildNumber.isNotEmpty ? '+${info.buildNumber}' : ''}');
    } catch (_) {
      // В тестах/десктопе PackageInfo недоступен — просто не показываем.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick(BuildContext context, String role) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => CloudAuthScreen(role: role),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = scheme.brightness == Brightness.light
        ? [Colors.white, scheme.primary.withValues(alpha: 0.08)]
        : [Colors.black, scheme.primary.withValues(alpha: 0.12)];
    final logo = AnimatedLogo(
      animation: _controller,
      size: 150,
    );

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
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                logo,
                const SizedBox(height: 20),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _welcomeOpacity.value,
                      child: FractionalTranslation(
                        translation: _welcomeSlide.value,
                        child: child,
                      ),
                    );
                  },
                  child: Column(
                    children: [
                      Text(
                        'Добро пожаловать в',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        'Bizzy',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineLarge
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: scheme.primary,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _questionOpacity.value,
                      child: child,
                    );
                  },
                  child: Text(
                    'Кто вы?',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 12),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _cardsOpacity.value,
                      child: FractionalTranslation(
                        translation: _cardsSlide.value,
                        child: child,
                      ),
                    );
                  },
                  child: Column(
                    children: [
                      _RoleCard(
                        icon: Icons.person_search,
                        title: 'Я клиент',
                        subtitle: 'Ищу мастера и хочу записываться на услуги',
                        onTap: () => _pick(context, 'client'),
                      ),
                      const SizedBox(height: 12),
                      _RoleCard(
                        icon: Icons.content_cut,
                        title: 'Я мастер',
                        subtitle: 'Оказываю услуги и веду записи клиентов',
                        onTap: () => _pick(context, 'master'),
                      ),
                      const SizedBox(height: 12),
                      _RoleCard(
                        icon: Icons.storefront,
                        title: 'Салон',
                        subtitle:
                            'Владею салоном — сотрудники, клиенты, расписание',
                        onTap: () => _pick(context, 'salon'),
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 2),
                if (_appVersion.isNotEmpty)
                  Text(
                    'Версия $_appVersion',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.5),
                        ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: scheme.primary,
                child: Icon(icon, color: scheme.onPrimary, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// Вход/регистрация через Supabase (логин + пароль, без email).
class CloudAuthScreen extends StatefulWidget {
  const CloudAuthScreen({super.key, required this.role});

  /// 'client' | 'master' | 'salon'
  final String role;

  @override
  State<CloudAuthScreen> createState() => _CloudAuthScreenState();
}

class _CloudAuthScreenState extends State<CloudAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _cloud = CloudService();
  bool _registerMode = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  String _describeError(Object e) {
    if (e is AuthException) {
      final msg = e.message.toLowerCase();
      if (msg.contains('invalid login') || msg.contains('invalid credentials')) {
        return 'Неверный логин или пароль';
      }
      if (msg.contains('already registered') || msg.contains('already in use')) {
        return 'Такой логин уже занят';
      }
      if (msg.contains('password')) {
        return 'Пароль слишком простой (минимум 6 символов)';
      }
      if (msg.contains('database error')) {
        return 'Ошибка регистрации на сервере. Попробуйте позже.';
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
    final login = _loginController.text.trim();
    final password = _passwordController.text;
    try {
      if (_registerMode) {
        await _cloud.signUp(
          login: login,
          password: password,
          role: widget.role,
          name: _nameController.text.trim(),
        );
      } else {
        await _cloud.signIn(login, password);
      }
      if (mounted) Navigator.of(context).pop();
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
    final roleName = switch (widget.role) {
      'master' => 'мастер',
      'salon' => 'салон',
      _ => 'клиент',
    };
    return Scaffold(
      appBar: AppBar(title: Text(_registerMode ? 'Регистрация' : 'Вход')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _registerMode
                      ? 'Регистрация как $roleName'
                      : 'Вход как $roleName',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 24),
                if (_registerMode) ...[
                  TextFormField(
                    controller: _nameController,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: switch (widget.role) {
                        'salon' => 'Название салона',
                        _ => 'Ваше имя',
                      },
                      hintText: switch (widget.role) {
                        'salon' => 'Как называется ваш салон',
                        'master' => 'Как к вам обращаться',
                        _ => 'Как вас зовут',
                      },
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final s = v?.trim() ?? '';
                      if (s.length < 2) return 'Минимум 2 символа';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Телефон можно будет указать позже в профиле',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
                TextFormField(
                  controller: _loginController,
                  enabled: !_busy,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Логин',
                    hintText: 'Придумайте логин',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.length < 3) return 'Минимум 3 символа';
                    if (s.contains(' ')) return 'Без пробелов';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  enabled: !_busy,
                  obscureText: !_showPassword,
                  decoration: const InputDecoration(
                    labelText: 'Пароль',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.length < 6
                      ? 'Минимум 6 символов'
                      : null,
                ),
                InkWell(
                  onTap: _busy
                      ? null
                      : () => setState(
                          () => _showPassword = !_showPassword),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _showPassword,
                          onChanged: _busy
                              ? null
                              : (v) => setState(
                                  () => _showPassword = v ?? false),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        Text(
                          'Показать пароль',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: Text(_registerMode ? 'Зарегистрироваться' : 'Войти'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _registerMode = !_registerMode;
                            _error = null;
                          }),
                  child: Text(
                    _registerMode
                        ? 'Уже есть аккаунт? Войти'
                        : 'Нет аккаунта? Зарегистрироваться',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
