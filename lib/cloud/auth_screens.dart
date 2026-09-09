import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_service.dart';

/// Экран «Вы клиент или мастер?» — показывается, когда нет сессии.
class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

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
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Image.asset(
                  'assets/icons/logo.png',
                  width: 140,
                  height: 140,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.calendar_month,
                    size: 120,
                    color: scheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Bizzy',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Кто вы?',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              _RoleCard(
                icon: Icons.person_search,
                title: 'Я клиент',
                subtitle: 'Ищу мастера и хочу записываться на услуги',
                onTap: () => _pick(context, 'client'),
              ),
              const SizedBox(height: 16),
              _RoleCard(
                icon: Icons.content_cut,
                title: 'Я мастер',
                subtitle: 'Оказываю услуги и веду записи клиентов',
                onTap: () => _pick(context, 'master'),
              ),
              const Spacer(),
            ],
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

/// Вход/регистрация через Supabase (email + пароль).
class CloudAuthScreen extends StatefulWidget {
  const CloudAuthScreen({super.key, required this.role});

  /// 'client' | 'master'
  final String role;

  @override
  State<CloudAuthScreen> createState() => _CloudAuthScreenState();
}

class _CloudAuthScreenState extends State<CloudAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cloud = CloudService();
  bool _registerMode = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String _describeError(Object e) {
    if (e is AuthException) {
      final msg = e.message.toLowerCase();
      if (msg.contains('invalid login') || msg.contains('invalid credentials')) {
        return 'Неверный email или пароль';
      }
      if (msg.contains('already registered') || msg.contains('already in use')) {
        return 'Такой email уже зарегистрирован';
      }
      if (msg.contains('password')) {
        return 'Пароль слишком простой (минимум 6 символов)';
      }
      if (msg.contains('email')) {
        return 'Проверьте email';
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
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    try {
      if (_registerMode) {
        await _cloud.signUp(
          email: email,
          password: password,
          role: widget.role,
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
        );
      } else {
        await _cloud.signIn(email, password);
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
    final roleName = widget.role == 'master' ? 'мастер' : 'клиент';
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
                    decoration: const InputDecoration(
                      labelText: 'Имя',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Введите имя' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    enabled: !_busy,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Телефон',
                      hintText: '+7 ___ ___ __ __',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Введите телефон'
                        : null,
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _emailController,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || !v.contains('@')
                      ? 'Введите email'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  enabled: !_busy,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Пароль',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.length < 6
                      ? 'Минимум 6 символов'
                      : null,
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
