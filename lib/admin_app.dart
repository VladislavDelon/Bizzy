import 'package:flutter/material.dart';

import 'admin/admin_api.dart';
import 'app_theme.dart';

/// АДМИНКА BIZZY — отдельная локальная веб-точка входа.
///
/// Запуск: двойной клик по `start_admin.bat` в корне проекта —
/// он подставляет креды из `admin\admin_config.txt` через
/// --dart-define и открывает http://localhost:8787.
///
/// ВАЖНО: приложение работает на service_role ключе Supabase.
/// Эта точка входа НИКОГДА не должна собираться в публичный
/// веб-деплой — только локальный `flutter run`.
const _adminUser = String.fromEnvironment('ADMIN_USER');
const _adminPass = String.fromEnvironment('ADMIN_PASS');
const _serviceKey = String.fromEnvironment('SERVICE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BizzyAdminApp());
}

class BizzyAdminApp extends StatelessWidget {
  const BizzyAdminApp({
    super.key,
    this.adminUser = _adminUser,
    this.adminPass = _adminPass,
    this.serviceKey = _serviceKey,
    this.api,
  });

  final String adminUser;
  final String adminPass;
  final String serviceKey;

  /// Подмена API в тестах.
  final AdminApiBase? api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bizzy — админка',
      debugShowCheckedModeBanner: false,
      theme: bizzyTheme(Brightness.dark),
      home: adminUser.isEmpty || adminPass.isEmpty || serviceKey.isEmpty
          ? const _SetupScreen()
          : _AdminGate(
              adminUser: adminUser,
              adminPass: adminPass,
              api: api ?? AdminApi(serviceKey),
            ),
    );
  }
}

/// Креды не переданы — инструкция по настройке.
class _SetupScreen extends StatelessWidget {
  const _SetupScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Админка не настроена',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Запустите через start_admin.bat — он читает креды '
                    'из файла admin\\admin_config.txt (три строки):\n\n'
                    '  1. логин админа\n'
                    '  2. пароль админа\n'
                    '  3. service_role ключ Supabase\n\n'
                    'Ключ лежит в Supabase Dashboard → Project Settings '
                    '→ API → service_role (secret). Пример файла — '
                    'admin\\admin_config.example.txt.',
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

/// Экран входа в админку.
class _AdminGate extends StatefulWidget {
  const _AdminGate({
    required this.adminUser,
    required this.adminPass,
    required this.api,
  });

  final String adminUser;
  final String adminPass;
  final AdminApiBase api;

  @override
  State<_AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<_AdminGate> {
  final _loginCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _authed = false;
  String? _error;

  void _signIn() {
    if (_loginCtrl.text.trim() == widget.adminUser &&
        _passCtrl.text == widget.adminPass) {
      setState(() => _authed = true);
    } else {
      setState(() => _error = 'Неверный логин или пароль');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_authed) return AdminDashboard(api: widget.api);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.admin_panel_settings, size: 48),
                  const SizedBox(height: 8),
                  Text(
                    'Вход администратора',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _loginCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Логин',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _signIn(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Пароль',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _signIn(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _signIn,
                      child: const Text('Войти'),
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

/// Главный экран админки: пользователи по ролям + действия.
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key, required this.api});

  final AdminApiBase api;

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  List<AdminUser> _users = const [];
  bool _loading = true;
  String? _error;
  String _roleFilter = 'all';
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await widget.api.listUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  List<AdminUser> get _filtered {
    final q = _search.trim().toLowerCase();
    return _users.where((u) {
      if (_roleFilter != 'all' && u.role != _roleFilter) return false;
      if (q.isEmpty) return true;
      return u.login.toLowerCase().contains(q) ||
          u.name.toLowerCase().contains(q) ||
          u.phone.contains(q);
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> _run(String done, Future<void> Function() op) async {
    try {
      await op();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  Future<void> _editLogin(AdminUser u) async {
    final ctrl = TextEditingController(text: u.login);
    final v = await _prompt(
      title: 'Сменить логин',
      controller: ctrl,
      label: 'Новый логин',
      hint: 'Логин — то, чем пользователь входит (без @bizzy.app)',
    );
    if (v == null || v.trim().isEmpty) return;
    await _run('Логин обновлён', () => widget.api.updateLogin(u.id, v.trim()));
  }

  Future<void> _editPassword(AdminUser u) async {
    final ctrl = TextEditingController();
    final v = await _prompt(
      title: 'Новый пароль',
      controller: ctrl,
      label: 'Пароль (минимум 6 символов)',
      obscure: true,
    );
    if (v == null || v.isEmpty) return;
    await _run('Пароль обновлён', () => widget.api.updatePassword(u.id, v));
  }

  Future<void> _toggleBan(AdminUser u) async {
    final yes = await _confirm(
      u.banned ? 'Разблокировать ${u.login}?' : 'Заблокировать ${u.login}?',
      u.banned
          ? 'Пользователь снова сможет входить.'
          : 'Пользователь не сможет входить, пока не снимете бан.',
    );
    if (yes != true) return;
    await _run(
      u.banned ? 'Разблокирован' : 'Заблокирован',
      () => widget.api.setBanned(u.id, !u.banned),
    );
  }

  Future<void> _delete(AdminUser u) async {
    final yes = await _confirm(
      'Удалить ${u.login}?',
      'Аккаунт, профиль и карточка будут удалены безвозвратно.',
      danger: true,
    );
    if (yes != true) return;
    await _run('Аккаунт удалён', () => widget.api.deleteUser(u.id));
  }

  Future<String?> _prompt({
    required String title,
    required TextEditingController controller,
    required String label,
    String? hint,
    bool obscure = false,
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              obscureText: obscure,
              autofocus: true,
              decoration: InputDecoration(
                labelText: label,
                helperText: hint,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.of(ctx).pop(v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirm(String title, String body, {bool danger = false}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                  )
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bizzy — админка'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Логин, имя или телефон…',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _search = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SegmentedButton<String>(
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                      segments: const [
                        ButtonSegment(value: 'all', label: Text('Все')),
                        ButtonSegment(value: 'client', label: Text('Клиенты')),
                        ButtonSegment(value: 'master', label: Text('Мастера')),
                        ButtonSegment(value: 'salon', label: Text('Салоны')),
                      ],
                      selected: {_roleFilter},
                      onSelectionChanged: (s) =>
                          setState(() => _roleFilter = s.first),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'Не удалось загрузить пользователей:\n$_error',
                                textAlign: TextAlign.center,
                              ),
                            ),
                            FilledButton.tonal(
                              onPressed: _load,
                              child: const Text('Повторить'),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: _filtered.length,
                          itemBuilder: (context, i) =>
                              _userTile(_filtered[i], scheme),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _userTile(AdminUser u, ColorScheme scheme) {
    final roleLabel = switch (u.role) {
      'master' => 'мастер',
      'salon' => 'салон',
      'client' => 'клиент',
      _ => u.role.isEmpty ? 'без роли' : u.role,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          child: Icon(
            u.role == 'salon'
                ? Icons.storefront
                : u.role == 'master'
                ? Icons.content_cut
                : Icons.person,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                u.name.isEmpty ? u.login : u.name,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (u.banned)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Chip(
                  label: const Text('заблокирован'),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: scheme.errorContainer,
                  labelStyle: TextStyle(
                    color: scheme.onErrorContainer,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          '@${u.login} · $roleLabel'
          '${u.phone.isNotEmpty ? ' · ${u.phone}' : ''}'
          '${u.category.isNotEmpty ? ' · ${u.category}' : ''}'
          '${u.isProvider ? ' · ★ ${u.ratingAvg.toStringAsFixed(1)} (${u.ratingCount})' : ''}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.badge_outlined, size: 18),
                label: const Text('Логин'),
                onPressed: () => _editLogin(u),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.key, size: 18),
                label: const Text('Пароль'),
                onPressed: () => _editPassword(u),
              ),
              OutlinedButton.icon(
                icon: Icon(u.banned ? Icons.lock_open : Icons.block, size: 18),
                label: Text(u.banned ? 'Разблокировать' : 'Заблокировать'),
                onPressed: () => _toggleBan(u),
              ),
              OutlinedButton.icon(
                icon: Icon(Icons.delete_outline, size: 18, color: scheme.error),
                label: Text('Удалить', style: TextStyle(color: scheme.error)),
                onPressed: () => _delete(u),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: _ReviewsBlock(api: widget.api, user: u),
          ),
        ],
      ),
    );
  }
}

/// Отзывы на пользователя (из ratings / client_reviews) с удалением.
class _ReviewsBlock extends StatefulWidget {
  const _ReviewsBlock({required this.api, required this.user});

  final AdminApiBase api;
  final AdminUser user;

  @override
  State<_ReviewsBlock> createState() => _ReviewsBlockState();
}

class _ReviewsBlockState extends State<_ReviewsBlock> {
  List<AdminReview>? _reviews;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.reviewsAbout(widget.user);
      if (!mounted) return;
      setState(() {
        _reviews = r;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _delete(AdminReview r) async {
    try {
      await widget.api.deleteReview(r);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Отзыв удалён')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_error != null) {
      return Text('Отзывы не загрузились: $_error');
    }
    final list = _reviews;
    if (list == null) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (list.isEmpty) {
      return Text(
        'Отзывов нет',
        style: TextStyle(color: scheme.onSurfaceVariant),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Отзывы (${list.length})',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        for (final r in list)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Text(
              '★' * r.rating.clamp(0, 5),
              style: TextStyle(color: scheme.primary),
            ),
            title: Text(r.comment.isEmpty ? '— без комментария —' : r.comment),
            subtitle: Text(
              '${r.authorName} · '
              '${r.createdAt.day.toString().padLeft(2, '0')}.'
              '${r.createdAt.month.toString().padLeft(2, '0')}.'
              '${r.createdAt.year}',
            ),
            trailing: IconButton(
              tooltip: 'Удалить отзыв',
              icon: Icon(Icons.delete_outline, color: scheme.error, size: 20),
              onPressed: () => _delete(r),
            ),
          ),
      ],
    );
  }
}
