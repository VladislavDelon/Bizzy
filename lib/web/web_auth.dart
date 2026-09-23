import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cloud/cloud_service.dart';

/// Веб-вход и регистрация: клиент, мастер или салон.
/// Без локальной базы — только облачные аккаунты (веб-версия
/// работает поверх тех же данных, что и приложение).
class WebAuthScreen extends StatefulWidget {
  const WebAuthScreen({super.key, required this.onSignedIn});

  final VoidCallback onSignedIn;

  @override
  State<WebAuthScreen> createState() => _WebAuthScreenState();
}

class _WebAuthScreenState extends State<WebAuthScreen> {
  final _cloud = CloudService();
  final _formKey = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _refCode = TextEditingController();
  final _salonKey = TextEditingController();

  String _role = 'client';
  bool _register = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
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
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.content_cut,
                    size: 56,
                    color: scheme.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Bizzy',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _register
                        ? 'Регистрация — $roleName'
                        : 'Вход — $roleName',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
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
                        : (s) => setState(() => _role = s.first),
                  ),
                  const SizedBox(height: 20),
                  if (_register) ...[
                    TextFormField(
                      controller: _name,
                      enabled: !_busy,
                      textCapitalization: TextCapitalization.words,
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
                      if (s.length < 3) return 'Минимум 3 символа';
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
                            () => _showPassword = !_showPassword,
                          ),
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
                                    () => _showPassword = v ?? false,
                                  ),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                          Text(
                            'Показать пароль',
                            style: Theme.of(context).textTheme.bodySmall,
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
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Код друга (необязательно)',
                        hintText: 'BZ-XXXXXX — скидка вам и другу',
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
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        _busy
                            ? 'Подождите…'
                            : (_register ? 'Создать аккаунт' : 'Войти'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
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
    );
  }
}
