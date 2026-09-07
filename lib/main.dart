import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const BizzyApp());

class BizzyApp extends StatelessWidget {
  const BizzyApp({super.key, this.database, this.updateService});

  final AppointmentsDatabase? database;
  final UpdateService? updateService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bizzy',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: AuthGate(database: database, updateService: updateService),
    );
  }
}

class AppUpdate {
  const AppUpdate({required this.version, required this.downloadUrl});

  final String version;
  final Uri downloadUrl;
}

class UpdateService {
  const UpdateService({this.owner = 'VladislavDelon', this.repo = 'Bizzy'});

  final String owner;
  final String repo;

  Future<AppUpdate?> check() async {
    final info = await PackageInfo.fromPlatform();
    final uri = Uri.parse(
      'https://api.github.com/repos/$owner/$repo/releases/latest',
    );
    final response = await http
        .get(uri, headers: {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, Object?>;
    final tag = (data['tag_name'] as String? ?? '').replaceFirst('v', '');
    final current = '${info.version}+${info.buildNumber}';
    if (tag.isEmpty || !_isNewer(tag, current)) return null;

    Uri url = Uri.parse(data['html_url'] as String? ?? '');
    for (final asset in data['assets'] as List? ?? []) {
      final name = (asset as Map<String, Object?>)['name'] as String? ?? '';
      if (name.endsWith('.apk')) {
        url = Uri.parse(asset['browser_download_url'] as String);
        break;
      }
    }
    return AppUpdate(version: tag, downloadUrl: url);
  }

  static bool _isNewer(String remote, String local) {
    List<int> parts(String v) =>
        v.split('+').first.split('.').map(int.parse).toList();
    int build(String v) =>
        int.tryParse(v.contains('+') ? v.split('+').last : '0') ?? 0;
    try {
      final remoteParts = parts(remote);
      final localParts = parts(local);
      for (var i = 0; i < 3; i++) {
        final r = i < remoteParts.length ? remoteParts[i] : 0;
        final l = i < localParts.length ? localParts[i] : 0;
        if (r != l) return r > l;
      }
      return build(remote) > build(local);
    } on FormatException {
      return false;
    }
  }
}

class User {
  const User({required this.id, required this.login});

  final int id;
  final String login;
}

class Company {
  const Company({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
  });

  final int id;
  final int userId;
  final String name;
  final String type;

  factory Company.fromMap(Map<String, Object?> map) => Company(
    id: map['id'] as int,
    userId: map['userId'] as int,
    name: map['name'] as String,
    type: map['type'] as String? ?? '',
  );

  String get label => type.isEmpty ? name : '$name ($type)';
}

class Appointment {
  final int? id;
  final int companyId;
  final String clientName;
  final String phone;
  final String service;
  final String master;
  final DateTime dateTime;
  final String notes;

  Appointment({
    this.id,
    required this.companyId,
    required this.clientName,
    required this.phone,
    required this.service,
    required this.master,
    required this.dateTime,
    required this.notes,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'companyId': companyId,
      'clientName': clientName,
      'phone': phone,
      'service': service,
      'master': master,
      'dateTime': dateTime.toIso8601String(),
      'notes': notes,
    };
  }

  factory Appointment.fromMap(Map<String, Object?> map) {
    return Appointment(
      id: map['id'] as int?,
      companyId: map['companyId'] as int? ?? 0,
      clientName: map['clientName'] as String,
      phone: map['phone'] as String,
      service: map['service'] as String,
      master: map['master'] as String,
      dateTime: DateTime.parse(map['dateTime'] as String),
      notes: map['notes'] as String,
    );
  }
}

enum ContactType {
  client('clients', 'Клиенты', 'Клиентов пока нет', 'Новый клиент'),
  master('masters', 'Мастера', 'Мастеров пока нет', 'Новый мастер');

  const ContactType(this.table, this.title, this.emptyText, this.addTitle);

  final String table;
  final String title;
  final String emptyText;
  final String addTitle;
}

class Contact {
  const Contact({required this.id, required this.name, required this.phone});

  final int id;
  final String name;
  final String phone;

  factory Contact.fromMap(Map<String, Object?> map) => Contact(
    id: map['id'] as int,
    name: map['name'] as String,
    phone: map['phone'] as String,
  );
}

class AppointmentsDatabase {
  static Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final pathString = p.join(databasesPath, 'bizzy.db');
    return openDatabase(
      pathString,
      version: 3,
      onCreate: (db, version) => _createAll(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createDirectories(db);
          await db.execute('''
            INSERT OR IGNORE INTO clients(companyId, name, phone)
            SELECT DISTINCT 0, TRIM(clientName), TRIM(phone) FROM appointments
            WHERE TRIM(clientName) != ''
          ''');
          await db.execute('''
            INSERT OR IGNORE INTO masters(companyId, name, phone)
            SELECT DISTINCT 0, TRIM(master), '' FROM appointments
            WHERE TRIM(master) != ''
          ''');
        }
        if (oldVersion < 3) {
          await _createAccounts(db);
          await _migrateToCompanies(db);
        }
      },
    );
  }

  Future<void> _createAll(Database db) async {
    await db.execute('''
      CREATE TABLE appointments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        companyId INTEGER NOT NULL DEFAULT 0,
        clientName TEXT NOT NULL,
        phone TEXT NOT NULL,
        service TEXT NOT NULL,
        master TEXT NOT NULL,
        dateTime TEXT NOT NULL,
        notes TEXT NOT NULL
      )
    ''');
    await _createDirectories(db);
    await _createAccounts(db);
  }

  Future<void> _createDirectories(Database db) async {
    for (final type in ContactType.values) {
      await db.execute('''
        CREATE TABLE ${type.table}(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          companyId INTEGER NOT NULL DEFAULT 0,
          name TEXT NOT NULL,
          phone TEXT NOT NULL DEFAULT '',
          UNIQUE(companyId, name, phone)
        )
      ''');
    }
  }

  Future<void> _createAccounts(Database db) async {
    await db.execute('''
      CREATE TABLE users(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        login TEXT NOT NULL UNIQUE,
        passwordHash TEXT NOT NULL,
        salt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE companies(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER NOT NULL,
        name TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT ''
      )
    ''');
  }

  Future<void> _migrateToCompanies(Database db) async {
    for (final table in ['appointments', 'clients', 'masters']) {
      await db.execute(
        'ALTER TABLE $table ADD COLUMN companyId INTEGER NOT NULL DEFAULT 0',
      );
    }
    final id = await db.insert('companies', {
      'userId': 0,
      'name': 'Моя компания',
      'type': '',
    });
    for (final table in ['appointments', 'clients', 'masters']) {
      await db.update(
        table,
        {'companyId': id},
        where: 'companyId = 0',
      );
    }
  }

  String _hash(String password, String salt) =>
      sha256.convert(utf8.encode('$salt$password')).toString();

  Future<User> createUser(String login, String password) async {
    final db = await database;
    final trimmed = login.trim();
    if (trimmed.isEmpty || password.isEmpty) {
      throw ArgumentError('Логин и пароль обязательны');
    }
    final salt = base64Url.encode(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    final id = await db.insert('users', {
      'login': trimmed,
      'passwordHash': _hash(password, salt),
      'salt': salt,
    });
    return User(id: id, login: trimmed);
  }

  Future<User?> authenticate(String login, String password) async {
    final db = await database;
    final rows = await db.query(
      'users',
      where: 'login = ?',
      whereArgs: [login.trim()],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    if (_hash(password, row['salt'] as String) != row['passwordHash']) {
      return null;
    }
    return User(id: row['id'] as int, login: row['login'] as String);
  }

  Future<List<Company>> getCompanies(int userId) async {
    final db = await database;
    final maps = await db.query(
      'companies',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'name',
    );
    return maps.map(Company.fromMap).toList();
  }

  Future<Company> createCompany(int userId, String name, String type) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Название компании обязательно');
    final db = await database;
    final id = await db.insert('companies', {
      'userId': userId,
      'name': trimmed,
      'type': type,
    });
    return Company(id: id, userId: userId, name: trimmed, type: type);
  }

  Future<List<Company>> claimOrphanCompanies(int userId) async {
    final db = await database;
    final orphans = await db.query('companies', where: 'userId = 0');
    if (orphans.isEmpty) return [];
    await db.update(
      'companies',
      {'userId': userId},
      where: 'userId = 0',
    );
    return orphans.map(Company.fromMap).toList();
  }

  Future<List<Contact>> getContacts(ContactType type, int companyId) async {
    final db = await database;
    final maps = await db.query(
      type.table,
      where: 'companyId = ?',
      whereArgs: [companyId],
    );
    final contacts = maps.map(Contact.fromMap).toList();
    contacts.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return contacts;
  }

  Future<Contact> saveContact(
    ContactType type,
    int companyId,
    String name,
    String phone,
  ) async {
    final values = {'name': name.trim(), 'phone': phone.trim()};
    if (values['name']!.isEmpty ||
        (type == ContactType.client && values['phone']!.isEmpty)) {
      throw ArgumentError('Имя и телефон клиента обязательны');
    }
    final db = await database;
    return db.transaction((txn) async {
      await txn.insert(type.table, {
        'companyId': companyId,
        ...values,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      final rows = await txn.query(
        type.table,
        where: 'companyId = ? AND name = ? AND phone = ?',
        whereArgs: [companyId, values['name'], values['phone']],
      );
      return Contact.fromMap(rows.single);
    });
  }

  Future<int> insert(Appointment appointment) async {
    final db = await database;
    return db.insert('appointments', appointment.toMap());
  }

  Future<List<Appointment>> getAll(int companyId) async {
    final db = await database;
    final maps = await db.query(
      'appointments',
      where: 'companyId = ?',
      whereArgs: [companyId],
      orderBy: 'dateTime DESC',
    );
    return maps.map(Appointment.fromMap).toList();
  }

  Future<int> delete(int id) async {
    final db = await database;
    return db.delete('appointments', where: 'id = ?', whereArgs: [id]);
  }
}

class SessionStore {
  static const _userKey = 'bizzy_user_id';
  static const _loginKey = 'bizzy_user_login';
  static const _companyKey = 'bizzy_company_id';

  Future<int?> get userId async =>
      (await SharedPreferences.getInstance()).getInt(_userKey);

  Future<String?> get login async =>
      (await SharedPreferences.getInstance()).getString(_loginKey);

  Future<int?> get companyId async =>
      (await SharedPreferences.getInstance()).getInt(_companyKey);

  Future<void> save(int userId, String login, int companyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_userKey, userId);
    await prefs.setString(_loginKey, login);
    await prefs.setInt(_companyKey, companyId);
  }

  Future<void> saveCompany(int companyId) async =>
      (await SharedPreferences.getInstance()).setInt(_companyKey, companyId);

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.remove(_loginKey);
    await prefs.remove(_companyKey);
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, this.database, this.updateService});

  final AppointmentsDatabase? database;
  final UpdateService? updateService;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AppointmentsDatabase _db = widget.database ?? AppointmentsDatabase();
  final SessionStore _session = SessionStore();
  User? _user;
  Company? _company;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final userId = await _session.userId;
    final login = await _session.login;
    final companyId = await _session.companyId;
    if (userId == null || login == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final companies = await _db.getCompanies(userId);
    if (!mounted) return;
    final company = companies
        .where((c) => c.id == companyId)
        .firstOrNull ?? companies.firstOrNull;
    setState(() {
      _user = User(id: userId, login: login);
      _company = company;
      _loading = false;
    });
  }

  Future<void> _onAuthed(User user) async {
    final orphans = await _db.claimOrphanCompanies(user.id);
    var companies = await _db.getCompanies(user.id);
    if (orphans.isNotEmpty) companies = [...orphans, ...companies];
    if (!mounted) return;
    setState(() {
      _user = user;
      _company = companies.firstOrNull;
    });
    await _session.save(user.id, user.login, _company?.id ?? 0);
  }

  Future<void> _onCompanyChosen(Company company) async {
    if (_user == null) return;
    await _session.save(_user!.id, _user!.login, company.id);
    if (mounted) setState(() => _company = company);
  }

  Future<void> _logout() async {
    await _session.clear();
    if (mounted) {
      setState(() {
        _user = null;
        _company = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_user == null) {
      return AuthScreen(database: _db, onAuthed: _onAuthed);
    }
    if (_company == null) {
      return CompanySelectScreen(
        database: _db,
        userId: _user!.id,
        onChosen: _onCompanyChosen,
      );
    }
    return ScheduleScreen(
      database: _db,
      company: _company!,
      updateService: widget.updateService,
      onSwitchCompany: () => setState(() => _company = null),
      onLogout: _logout,
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.database, required this.onAuthed});

  final AppointmentsDatabase database;
  final ValueChanged<User> onAuthed;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _registerMode = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
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
        final user = await widget.database.createUser(login, password);
        if (!mounted) return;
        widget.onAuthed(user);
      } else {
        final user = await widget.database.authenticate(login, password);
        if (!mounted) return;
        if (user == null) {
          setState(() {
            _busy = false;
            _error = 'Неверный логин или пароль';
          });
        } else {
          widget.onAuthed(user);
        }
      }
    } on DatabaseException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Такой логин уже занят';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Не удалось выполнить. Попробуйте ещё раз.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bizzy')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _registerMode ? 'Регистрация' : 'Вход',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _loginController,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Логин',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Введите логин'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  enabled: !_busy,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Пароль',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Введите пароль'
                      : _registerMode && value.length < 4
                          ? 'Пароль должен быть не короче 4 символов'
                          : null,
                ),
                if (_registerMode) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmController,
                    enabled: !_busy,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Повторите пароль',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value != _passwordController.text
                        ? 'Пароли не совпадают'
                        : null,
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(
                    _busy
                        ? 'Подождите…'
                        : _registerMode
                            ? 'Зарегистрироваться'
                            : 'Войти',
                  ),
                ),
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
                if (_registerMode)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Text(
                      'Обратите внимание: в текущей версии регистрация '
                      'происходит локально — все данные хранятся только на '
                      'этом устройстве. Запомните логин и пароль: при их '
                      'утере восстановить доступ не получится. Перенос '
                      'аккаунта на другой телефон пока недоступен.',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
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

class CompanySelectScreen extends StatefulWidget {
  const CompanySelectScreen({
    super.key,
    required this.database,
    required this.userId,
    required this.onChosen,
  });

  final AppointmentsDatabase database;
  final int userId;
  final ValueChanged<Company> onChosen;

  @override
  State<CompanySelectScreen> createState() => _CompanySelectScreenState();
}

class _CompanySelectScreenState extends State<CompanySelectScreen> {
  List<Company> _companies = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final companies = await widget.database.getCompanies(widget.userId);
    if (!mounted) return;
    setState(() {
      _companies = companies;
      _loading = false;
    });
  }

  Future<void> _addCompany() async {
    final company = await showDialog<Company>(
      context: context,
      builder: (context) => AddCompanyDialog(
        database: widget.database,
        userId: widget.userId,
      ),
    );
    if (!mounted || company == null) return;
    widget.onChosen(company);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Мои компании')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _companies.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'У вас пока нет компании.\nСоздайте первую, чтобы начать.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _addCompany,
                          icon: const Icon(Icons.add_business),
                          label: const Text('Создать компанию'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _companies.length,
                  itemBuilder: (context, index) {
                    final company = _companies[index];
                    return ListTile(
                      leading: const Icon(Icons.business),
                      title: Text(company.name),
                      subtitle:
                          company.type.isEmpty ? null : Text(company.type),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => widget.onChosen(company),
                    );
                  },
                ),
      floatingActionButton: _companies.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _addCompany,
              icon: const Icon(Icons.add),
              label: const Text('Новая компания'),
            ),
    );
  }
}

class AddCompanyDialog extends StatefulWidget {
  const AddCompanyDialog({
    super.key,
    required this.database,
    required this.userId,
  });

  final AppointmentsDatabase database;
  final int userId;

  @override
  State<AddCompanyDialog> createState() => _AddCompanyDialogState();
}

class _AddCompanyDialogState extends State<AddCompanyDialog> {
  static const _types = ['Самозанятость', 'ИП', 'ООО', 'Другое'];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String _type = _types.first;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final company = await widget.database.createCompany(
        widget.userId,
        _nameController.text,
        _type == 'Другое' ? '' : _type,
      );
      if (!mounted) return;
      Navigator.of(context).pop(company);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('Назовите свою компанию'),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    for (final type in _types)
                      ChoiceChip(
                        label: Text(type),
                        selected: _type == type,
                        onSelected:
                            _saving ? null : (_) => setState(() => _type = type),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Название',
                    hintText: 'Например: Салон «Лилия»',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Введите название'
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Сохранение…' : 'Сохранить'),
          ),
        ],
      ),
    );
  }
}

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    super.key,
    this.database,
    this.updateService,
    required this.company,
    required this.onSwitchCompany,
    required this.onLogout,
  });

  final AppointmentsDatabase? database;
  final UpdateService? updateService;
  final Company company;
  final VoidCallback onSwitchCompany;
  final VoidCallback onLogout;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  late final AppointmentsDatabase _db = widget.database ?? AppointmentsDatabase();
  late final UpdateService? _updateService =
      widget.updateService ?? (widget.database == null ? const UpdateService() : null);
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  List<Appointment> _allAppointments = [];
  List<Appointment> _dayAppointments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadAppointments();
    _checkUpdates();
  }

  Future<void> _checkUpdates() async {
    final service = _updateService;
    if (service == null) return;
    try {
      final update = await service.check();
      if (!mounted || update == null) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Доступно обновление'),
          content: Text(
            'Вышла новая версия ${update.version}. '
            'Нажмите «Обновить», чтобы скачать её.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Позже'),
            ),
            FilledButton(
              onPressed: () {
                launchUrl(update.downloadUrl,
                    mode: LaunchMode.externalApplication);
                Navigator.of(context).pop();
              },
              child: const Text('Обновить'),
            ),
          ],
        ),
      );
    } catch (_) {
      // Нет сети или релиз ещё не опубликован — приложение работает офлайн.
    }
  }

  Future<void> _loadAppointments() async {
    final appointments = await _db.getAll(widget.company.id);
    if (!mounted) return;
    setState(() {
      _allAppointments = appointments;
      _dayAppointments = _appointmentsFor(_selectedDay!);
      _loading = false;
    });
  }

  List<Appointment> _appointmentsFor(DateTime day) {
    return _allAppointments
        .where((a) => isSameDay(a.dateTime, day))
        .toList();
  }

  List<Appointment> _eventsForDay(DateTime day) {
    return _appointmentsFor(day);
  }

  Future<void> _addAppointment(Appointment appointment) async {
    await _db.insert(appointment);
    await _loadAppointments();
  }

  Future<void> _deleteAppointment(int id) async {
    await _db.delete(id);
    await _loadAppointments();
  }

  Future<void> _showAddDialog() async {
    final result = await showDialog<Appointment>(
      context: context,
      builder: (context) => AddAppointmentDialog(
        database: _db,
        companyId: widget.company.id,
        initialDate: _selectedDay!,
      ),
    );
    if (result != null) {
      await _addAppointment(result);
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '${dateTime.day}.${dateTime.month}.${dateTime.year} $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.company.name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          for (final type in ContactType.values)
            TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (context) => ContactsScreen(
                    database: _db,
                    type: type,
                    companyId: widget.company.id,
                  ),
                ),
              ),
              child: Text(type.title),
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'switch') widget.onSwitchCompany();
              if (value == 'logout') widget.onLogout();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'switch', child: Text('Сменить компанию')),
              PopupMenuItem(value: 'logout', child: Text('Выйти из аккаунта')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                TableCalendar(
                  locale: 'ru_RU',
                  firstDay: DateTime.utc(2020, 1, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  calendarFormat: _calendarFormat,
                  eventLoader: _eventsForDay,
                  availableCalendarFormats: const {
                    CalendarFormat.month: 'Месяц',
                    CalendarFormat.twoWeeks: '2 недели',
                    CalendarFormat.week: 'Неделя',
                  },
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                      _dayAppointments = _appointmentsFor(selectedDay);
                    });
                  },
                  onFormatChanged: (format) {
                    setState(() {
                      _calendarFormat = format;
                    });
                  },
                  onPageChanged: (focusedDay) {
                    _focusedDay = focusedDay;
                  },
                ),
                Expanded(
                  child: _dayAppointments.isEmpty
                      ? const Center(
                          child: Text('На этот день записей нет.'),
                        )
                      : ListView.builder(
                          itemCount: _dayAppointments.length,
                          itemBuilder: (context, index) {
                            final a = _dayAppointments[index];
                            return ListTile(
                              title: Text(a.clientName),
                              subtitle: Text(
                                '${a.master} • ${a.service}\n${_formatDateTime(a.dateTime)}',
                              ),
                              trailing: Text(a.phone),
                              isThreeLine: true,
                              onLongPress: () => _deleteAppointment(a.id!),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({
    super.key,
    required this.database,
    required this.type,
    required this.companyId,
    this.selectContact = false,
  });

  final AppointmentsDatabase database;
  final ContactType type;
  final int companyId;
  final bool selectContact;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Contact> _contacts = [];
  String _query = '';
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final contacts =
          await widget.database.getContacts(widget.type, widget.companyId);
      if (!mounted) return;
      setState(() => _contacts = contacts);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addContact() async {
    final contact = await showDialog<Contact>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AddContactDialog(
        database: widget.database,
        type: widget.type,
        companyId: widget.companyId,
      ),
    );
    if (!mounted || contact == null) return;
    if (widget.selectContact) {
      Navigator.of(context).pop(contact);
    } else {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = _contacts
        .where(
          (contact) =>
              contact.name.toLowerCase().contains(_query) ||
              contact.phone.contains(_query),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.type.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Поиск по имени или телефону',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _failed
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Не удалось загрузить список'),
                            TextButton(
                              onPressed: _load,
                              child: const Text('Повторить'),
                            ),
                          ],
                        ),
                      )
                    : contacts.isEmpty
                        ? Center(
                            child: Text(
                              _query.isEmpty
                                  ? widget.type.emptyText
                                  : 'Ничего не найдено',
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 88),
                            itemCount: contacts.length,
                            itemBuilder: (context, index) {
                              final contact = contacts[index];
                              return ListTile(
                                leading: Icon(
                                  widget.type == ContactType.client
                                      ? Icons.person_outline
                                      : Icons.badge_outlined,
                                ),
                                title: Text(contact.name),
                                subtitle: contact.phone.isEmpty
                                    ? null
                                    : Text(contact.phone),
                                trailing: widget.selectContact
                                    ? const Icon(Icons.chevron_right)
                                    : null,
                                onTap: widget.selectContact
                                    ? () => Navigator.of(context).pop(contact)
                                    : null,
                              );
                            },
                          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addContact,
        icon: const Icon(Icons.add),
        label: Text(widget.type.addTitle),
      ),
    );
  }
}

class AddContactDialog extends StatefulWidget {
  const AddContactDialog({
    super.key,
    required this.database,
    required this.type,
    required this.companyId,
  });

  final AppointmentsDatabase database;
  final ContactType type;
  final int companyId;

  @override
  State<AddContactDialog> createState() => _AddContactDialogState();
}

class _AddContactDialogState extends State<AddContactDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final contact = await widget.database.saveContact(
        widget.type,
        widget.companyId,
        _nameController.text,
        _phoneController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(contact);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Не удалось сохранить. Попробуйте ещё раз.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(widget.type.addTitle),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Имя'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Введите имя'
                      : null,
                ),
                TextFormField(
                  controller: _phoneController,
                  enabled: !_saving,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: widget.type == ContactType.client
                        ? 'Телефон'
                        : 'Телефон (необязательно)',
                  ),
                  validator: (value) =>
                      widget.type == ContactType.client &&
                              (value == null || value.trim().isEmpty)
                          ? 'Введите телефон'
                          : null,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Сохранение…' : 'Сохранить'),
          ),
        ],
      ),
    );
  }
}

class AddAppointmentDialog extends StatefulWidget {
  const AddAppointmentDialog({
    super.key,
    required this.database,
    required this.companyId,
    required this.initialDate,
  });

  final AppointmentsDatabase database;
  final int companyId;
  final DateTime initialDate;

  @override
  State<AddAppointmentDialog> createState() => _AddAppointmentDialogState();
}

class _AddAppointmentDialogState extends State<AddAppointmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _serviceController = TextEditingController();
  final _notesController = TextEditingController();
  Contact? _client;
  Contact? _master;
  late DateTime _selectedDate = widget.initialDate;
  TimeOfDay _selectedTime = TimeOfDay.now();

  @override
  void dispose() {
    _phoneController.dispose();
    _serviceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectContact(
    ContactType type,
    FormFieldState<Contact> field,
  ) async {
    final contact = await Navigator.of(context).push<Contact>(
      MaterialPageRoute(
        builder: (context) => ContactsScreen(
          database: widget.database,
          type: type,
          companyId: widget.companyId,
          selectContact: true,
        ),
      ),
    );
    if (!mounted || contact == null) return;
    setState(() {
      if (type == ContactType.client) {
        _client = contact;
        _phoneController.text = contact.phone;
      } else {
        _master = contact;
      }
    });
    field.didChange(contact);
  }

  Widget _contactField(ContactType type) {
    final isClient = type == ContactType.client;
    final label = isClient ? 'Выбрать клиента' : 'Выбрать мастера';
    return FormField<Contact>(
      validator: (value) => value == null
          ? (isClient ? 'Выберите клиента' : 'Выберите мастера')
          : null,
      builder: (field) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: isClient ? 'Клиент' : 'Мастер',
            errorText: field.errorText,
            border: const OutlineInputBorder(),
          ),
          child: TextButton.icon(
            onPressed: () => _selectContact(type, field),
            icon: Icon(
              isClient ? Icons.person_outline : Icons.badge_outlined,
            ),
            label: Text(field.value?.name ?? label),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030, 12, 31),
    );
    if (mounted && picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked =
        await showTimePicker(context: context, initialTime: _selectedTime);
    if (mounted && picked != null) setState(() => _selectedTime = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final dateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    Navigator.of(context).pop(
      Appointment(
        companyId: widget.companyId,
        clientName: _client!.name,
        phone: _phoneController.text.trim(),
        service: _serviceController.text.trim(),
        master: _master!.name,
        dateTime: dateTime,
        notes: _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateText =
        '${_selectedDate.day}.${_selectedDate.month}.${_selectedDate.year}';
    final timeText =
        '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';
    return AlertDialog(
      title: const Text('Новая запись'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _contactField(ContactType.client),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Телефон'),
                keyboardType: TextInputType.phone,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Введите телефон'
                    : null,
              ),
              TextFormField(
                controller: _serviceController,
                decoration: const InputDecoration(labelText: 'Услуга'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Введите услугу'
                    : null,
              ),
              _contactField(ContactType.master),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _pickDate,
                      child: Text(dateText),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: _pickTime,
                      child: Text(timeText),
                    ),
                  ),
                ],
              ),
              TextField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Примечания'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        TextButton(onPressed: _save, child: const Text('Сохранить')),
      ],
    );
  }
}
