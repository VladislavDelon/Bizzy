import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as phone;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:install_plugin_v3/install_plugin_v3.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';

final ValueNotifier<ThemeMode> _themeMode = ValueNotifier(ThemeMode.system);

enum Currency {
  kzt('₸', 'Тенге (KZT)'),
  rub('₽', 'Рубли (RUB)'),
  usd(r'$', 'Доллары (USD)'),
  eur('€', 'Евро (EUR)');

  final String symbol;
  final String label;

  const Currency(this.symbol, this.label);

  static Currency fromString(String? value) {
    return Currency.values.firstWhere(
      (c) => c.name == value,
      orElse: () => Currency.kzt,
    );
  }
}

final ValueNotifier<Currency> _currency = ValueNotifier(Currency.kzt);

ThemeMode _themeModeFromString(String? value) {
  return switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

String _themeModeToString(ThemeMode value) {
  return switch (value) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    _ => 'system',
  };
}

Future<void> _loadTheme() async {
  final prefs = await SharedPreferences.getInstance();
  _themeMode.value = _themeModeFromString(prefs.getString('bizzy_theme_mode'));
}

Future<void> _loadCurrency() async {
  final prefs = await SharedPreferences.getInstance();
  _currency.value = Currency.fromString(prefs.getString('bizzy_currency'));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru_RU', null);
  await _loadTheme();
  await _loadCurrency();
  runApp(const BizzyApp());
}

class BizzyApp extends StatelessWidget {
  const BizzyApp({super.key, this.database, this.updateService});

  final AppointmentsDatabase? database;
  final UpdateService? updateService;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _themeMode,
      builder: (context, child) => MaterialApp(
        title: 'Bizzy',
        themeMode: _themeMode.value,
        theme: _bizzyTheme(Brightness.light),
        darkTheme: _bizzyTheme(Brightness.dark),
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: AuthGate(database: database, updateService: updateService),
      ),
    );
  }
}

DateTime _startOfDay(DateTime date) => DateTime(date.year, date.month, date.day);

String _formatTime(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _formatDateTime(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '${dateTime.day}.${dateTime.month}.${dateTime.year} $hour:$minute';
}

ThemeData _bizzyTheme(Brightness brightness) {
  const seedColor = Color(0xFFFFD600);
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
    scaffoldBackgroundColor: isLight ? Colors.white : Colors.black,
    appBarTheme: AppBarTheme(
      backgroundColor: isLight ? Colors.white : Colors.black,
      foregroundColor: isLight ? Colors.black : Colors.white,
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
      backgroundColor: isLight ? null : Colors.black,
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

class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.downloadUrl,
    required this.releaseUrl,
  });

  final String version;
  final Uri downloadUrl;
  final Uri releaseUrl;
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

    final releaseUrl = Uri.parse(data['html_url'] as String? ?? '');
    Uri downloadUrl = releaseUrl;
    for (final asset in data['assets'] as List? ?? []) {
      final name = (asset as Map<String, Object?>)['name'] as String? ?? '';
      if (name.endsWith('.apk')) {
        downloadUrl = Uri.parse(asset['browser_download_url'] as String);
        break;
      }
    }
    return AppUpdate(
      version: tag,
      downloadUrl: downloadUrl,
      releaseUrl: releaseUrl,
    );
  }

  Future<void> downloadAndInstall(
    Uri url,
    ValueChanged<double> onProgress,
  ) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Обновления APK доступны только на Android');
    }
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/bizzy_update.apk';
    try {
      final response = await Dio().download(
        url.toString(),
        path,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress(received / total);
        },
        options: Options(
          followRedirects: true,
          maxRedirects: 5,
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ),
      );
      if (response.statusCode != 200) {
        throw Exception('Сервер вернул ${response.statusCode} при загрузке APK');
      }
      final file = File(path);
      if (!file.existsSync()) {
        throw Exception('APK не загрузился');
      }
      final length = await file.length();
      if (length < 1024) {
        throw Exception('APK загружен, но файл слишком мал — возможно, ссылка ведёт не на APK');
      }
      final header = await file.openRead(0, 4).first;
      if (header.isEmpty || String.fromCharCodes(header).startsWith('PK') == false) {
        throw Exception('Загруженный файл не похож на APK (плохая ссылка или redirect)');
      }
      final res = await InstallPlugin.installApk(path);
      if (res is! Map || res['isSuccess'] != true) {
        final message = res is Map ? res['errorMessage'] : res?.toString();
        throw Exception(message ?? 'Не удалось начать установку');
      }
    } finally {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
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

Future<bool> _ensureInstallPermission(BuildContext context) async {
  if (!Platform.isAndroid) return false;
  var status = await Permission.requestInstallPackages.status;
  if (status.isGranted) return true;

  final requested = await Permission.requestInstallPackages.request();
  if (requested.isGranted) return true;

  if (context.mounted) {
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Нужно разрешение'),
        content: const Text(
          'Для установки обновлений Bizzy необходимо разрешить установку '
          'приложений из неизвестных источников. Хотите открыть настройки?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Открыть настройки'),
          ),
        ],
      ),
    );
    if (open == true) {
      await openAppSettings();
    }
  }

  status = await Permission.requestInstallPackages.status;
  return status.isGranted;
}

class UpdateResult {
  const UpdateResult({
    this.success = false,
    this.needsRestart = false,
    this.error,
  });

  final bool success;
  final bool needsRestart;
  final String? error;
}

Future<void> _showUpdateFlow(
  BuildContext context,
  UpdateService service,
  AppUpdate update,
) async {
  if (!Platform.isAndroid) return;
  final hasPermission = await _ensureInstallPermission(context);
  if (!hasPermission) {
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => const AlertDialog(
          title: Text('Не удалось продолжить'),
          content: Text(
            'Без разрешения на установку приложений обновление невозможно. '
            'Включите разрешение «Установка из неизвестных источников» для '
            'Bizzy в настройках телефона и попробуйте снова.',
          ),
        ),
      );
    }
    return;
  }

  if (!context.mounted) return;
  final result = await showDialog<UpdateResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => DownloadUpdateDialog(
      service: service,
      downloadUrl: update.downloadUrl,
    ),
  );

  if (!context.mounted || result == null) return;

  if (result.success && result.needsRestart) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Обновление установлено'),
        content: const Text(
          'Новая версия установлена. Перезапустите приложение, чтобы '
          'использовать обновление.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Позже'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              SystemNavigator.pop();
            },
            child: const Text('Перезапустить'),
          ),
        ],
      ),
    );
    return;
  }

  if (result.success) return;

  final error = result.error?.toLowerCase() ?? '';
  final isPermissionError = error.contains('permission') ||
      error.contains('разрешение') ||
      error.contains('unknown source') ||
      error.contains('неизвестных');
  final isCancel = error.contains('cancel') || error.contains('отмена');
  final isSignature = error.contains('install failed') ||
      error.contains('not installed') ||
      error.contains('не установлено') ||
      error.contains('install error');

  final content = isCancel
      ? 'Установка была отменена.'
      : isPermissionError
          ? 'Не удалось получить разрешение на установку. Включите «Установка из неизвестных источников» для Bizzy.'
          : isSignature
              ? 'Установщик Android отказал. Вероятно, APK подписан другим ключом, чем установленная версия, или установщик не смог обновить приложение. Скачайте APK вручную и установите поверх.'
              : (result.error ?? 'Не удалось обновить. Проверьте подключение к интернету, свободное место и разрешения.');

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Не удалось обновить'),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            launchUrl(
              update.releaseUrl,
              mode: LaunchMode.externalApplication,
            );
          },
          child: const Text('Скачать вручную'),
        ),
      ],
    ),
  );
}

class DownloadUpdateDialog extends StatefulWidget {
  const DownloadUpdateDialog({
    super.key,
    required this.service,
    required this.downloadUrl,
  });

  final UpdateService service;
  final Uri downloadUrl;

  @override
  State<DownloadUpdateDialog> createState() => _DownloadUpdateDialogState();
}

class _DownloadUpdateDialogState extends State<DownloadUpdateDialog> {
  double _progress = 0;
  String _status = 'Загрузка…';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await widget.service.downloadAndInstall(
        widget.downloadUrl,
        (p) => setState(() {
          _progress = p;
          _status = 'Загружено ${(p * 100).toStringAsFixed(0)}%';
        }),
      );
      if (mounted) {
        setState(() => _status = 'Установлено');
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.of(context).pop(
            const UpdateResult(success: true, needsRestart: true),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Ошибка: $e');
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        Navigator.of(context).pop(
          UpdateResult(error: e.toString()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Обновление Bizzy'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_status),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            const Text(
              'Скачиваем обновление, затем запустится установщик Android. '
              'После установки приложение нужно будет перезапустить.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
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

class Service {
  final int? id;
  final int companyId;
  final String name;
  final double price;
  final int durationMinutes;
  final String notes;

  const Service({
    this.id,
    required this.companyId,
    required this.name,
    this.price = 0,
    this.durationMinutes = 60,
    this.notes = '',
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'companyId': companyId,
      'name': name,
      'price': price,
      'durationMinutes': durationMinutes,
      'notes': notes,
    };
  }

  factory Service.fromMap(Map<String, Object?> map) {
    return Service(
      id: map['id'] as int?,
      companyId: map['companyId'] as int? ?? 0,
      name: map['name'] as String,
      price: (map['price'] as num?)?.toDouble() ?? 0,
      durationMinutes: (map['durationMinutes'] as int?) ?? 60,
      notes: (map['notes'] as String?) ?? '',
    );
  }
}

class Appointment {
  final int? id;
  final int companyId;
  final String clientName;
  final String phone;
  final String service;
  final String master;
  final DateTime dateTime;
  final int durationMinutes;
  final int reminderMinutes;
  final String notes;

  Appointment({
    this.id,
    required this.companyId,
    required this.clientName,
    required this.phone,
    required this.service,
    required this.master,
    required this.dateTime,
    this.durationMinutes = 60,
    this.reminderMinutes = 30,
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
      'durationMinutes': durationMinutes,
      'reminderMinutes': reminderMinutes,
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
      durationMinutes: (map['durationMinutes'] as int?) ?? 60,
      reminderMinutes: (map['reminderMinutes'] as int?) ?? 30,
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
      version: 5,
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
        if (oldVersion < 4) {
          await db.execute('''
            ALTER TABLE appointments ADD COLUMN durationMinutes INTEGER NOT NULL DEFAULT 60
          ''');
          await db.execute('''
            ALTER TABLE appointments ADD COLUMN reminderMinutes INTEGER NOT NULL DEFAULT 30
          ''');
        }
        if (oldVersion < 5) {
          await _createServices(db);
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
        durationMinutes INTEGER NOT NULL DEFAULT 60,
        reminderMinutes INTEGER NOT NULL DEFAULT 30,
        notes TEXT NOT NULL
      )
    ''');
    await _createDirectories(db);
    await _createAccounts(db);
    await _createServices(db);
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

  Future<void> _createServices(Database db) async {
    await db.execute('''
      CREATE TABLE services(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        companyId INTEGER NOT NULL DEFAULT 0,
        name TEXT NOT NULL,
        price REAL NOT NULL DEFAULT 0,
        durationMinutes INTEGER NOT NULL DEFAULT 60,
        notes TEXT NOT NULL DEFAULT ''
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

  Future<int> update(Appointment appointment) async {
    final db = await database;
    return db.update(
      'appointments',
      appointment.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [appointment.id],
    );
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

  Future<List<Appointment>> getForDay(
    int companyId,
    DateTime day, {
    String? master,
    int? excludeId,
  }) async {
    final db = await database;
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    var where = 'companyId = ? AND dateTime >= ? AND dateTime < ?';
    final args = <Object?>[
      companyId,
      start.toIso8601String(),
      end.toIso8601String(),
    ];
    if (master != null && master.isNotEmpty) {
      where += ' AND master = ?';
      args.add(master);
    }
    if (excludeId != null) {
      where += ' AND id != ?';
      args.add(excludeId);
    }
    final maps = await db.query(
      'appointments',
      where: where,
      whereArgs: args,
      orderBy: 'dateTime',
    );
    return maps.map(Appointment.fromMap).toList();
  }

  Future<int> delete(int id) async {
    final db = await database;
    return db.delete('appointments', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Service>> getServices(int companyId) async {
    final db = await database;
    final maps = await db.query(
      'services',
      where: 'companyId = ?',
      whereArgs: [companyId],
      orderBy: 'name',
    );
    return maps.map(Service.fromMap).toList();
  }

  Future<Service> createService(Service service) async {
    final db = await database;
    final id = await db.insert('services', {
      'companyId': service.companyId,
      'name': service.name.trim(),
      'price': service.price,
      'durationMinutes': service.durationMinutes,
      'notes': service.notes.trim(),
    });
    return Service(
      id: id,
      companyId: service.companyId,
      name: service.name.trim(),
      price: service.price,
      durationMinutes: service.durationMinutes,
      notes: service.notes.trim(),
    );
  }

  Future<int> updateService(Service service) async {
    final db = await database;
    return db.update(
      'services',
      {
        'name': service.name.trim(),
        'price': service.price,
        'durationMinutes': service.durationMinutes,
        'notes': service.notes.trim(),
      },
      where: 'id = ?',
      whereArgs: [service.id],
    );
  }

  Future<int> deleteService(int id) async {
    final db = await database;
    return db.delete('services', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateContact(
    ContactType type,
    int companyId,
    Contact contact,
    String name,
    String phone,
  ) async {
    final trimmed = name.trim();
    final trimmedPhone = phone.trim();
    if (trimmed.isEmpty ||
        (type == ContactType.client && trimmedPhone.isEmpty)) {
      throw ArgumentError('Имя и телефон клиента обязательны');
    }
    final db = await database;
    return db.update(
      type.table,
      {'companyId': companyId, 'name': trimmed, 'phone': trimmedPhone},
      where: 'id = ?',
      whereArgs: [contact.id],
      conflictAlgorithm: ConflictAlgorithm.rollback,
    );
  }

  Future<int> deleteContact(ContactType type, int id) async {
    final db = await database;
    return db.delete(type.table, where: 'id = ?', whereArgs: [id]);
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

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _options = {
    ThemeMode.system: 'Системная',
    ThemeMode.light: 'Светлая',
    ThemeMode.dark: 'Тёмная',
  };

  late ThemeMode _value = _themeMode.value;

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    _themeMode.value = _value;
    await prefs.setString('bizzy_theme_mode', _themeModeToString(_value));
  }

  Future<void> _checkForUpdate(BuildContext context) async {
    if (!Platform.isAndroid) return;
    final messenger = ScaffoldMessenger.of(context);
    final update = await const UpdateService().check();
    if (!context.mounted) return;
    if (update == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Обновлений пока нет')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => DownloadUpdateDialog(
        service: const UpdateService(),
        downloadUrl: update.downloadUrl,
      ),
    );
    if (!context.mounted) return;
    if (ok != true) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить обновление')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Тема оформления',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<ThemeMode>(
                    multiSelectionEnabled: false,
                    emptySelectionAllowed: false,
                    selected: {_value},
                    onSelectionChanged: (selected) {
                      if (selected.isEmpty) return;
                      setState(() => _value = selected.first);
                      _save();
                    },
                    segments: _options.entries
                        .map((e) => ButtonSegment<ThemeMode>(
                              value: e.key,
                              label: Text(e.value),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Валюта',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<Currency>(
                    valueListenable: _currency,
                    builder: (context, currency, _) => InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Валюта',
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      isEmpty: false,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<Currency>(
                          value: currency,
                          isExpanded: true,
                          isDense: true,
                          items: Currency.values
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c,
                                  child: Text('${c.label} (${c.symbol})'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) async {
                            if (value == null) return;
                            _currency.value = value;
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString(
                                'bizzy_currency', value.name);
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _checkForUpdate(context),
                      icon: const Icon(Icons.system_update),
                      label: const Text('Проверить обновления'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
    final updateService =
        widget.updateService ?? (widget.database == null ? const UpdateService() : null);
    return MainShell(
      database: _db,
      company: _company!,
      user: _user!,
      updateService: updateService,
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
  PackageInfo _info = PackageInfo(
    appName: 'Bizzy',
    packageName: 'com.example.bizzy_app',
    version: '',
    buildNumber: '',
  );

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _info = info);
  }

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

  Widget _logo() {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Center(
        child: Image.asset(
          'assets/icons/logo.png',
          width: 160,
          height: 160,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.calendar_month,
              size: 96,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final versionText = 'Версия ${_info.version}${_info.buildNumber.isNotEmpty ? '+${_info.buildNumber}' : ''}';
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _logo(),
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
                const SizedBox(height: 8),
                Text(
                  versionText,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
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
              heroTag: null,
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

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.database,
    required this.company,
    required this.user,
    this.updateService,
    required this.onSwitchCompany,
    required this.onLogout,
  });

  final AppointmentsDatabase database;
  final Company company;
  final User user;
  final UpdateService? updateService;
  final VoidCallback onSwitchCompany;
  final VoidCallback onLogout;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late final AppointmentsDatabase _db = widget.database;
  late final ValueNotifier<DateTime> _homeDayNotifier;
  int _currentIndex = 0;
  List<Appointment> _allAppointments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _homeDayNotifier = ValueNotifier(_startOfDay(DateTime.now()));
    _loadAppointments();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdates();
    });
  }

  @override
  void dispose() {
    _homeDayNotifier.dispose();
    super.dispose();
  }

  Future<void> _checkUpdates() async {
    if (!Platform.isAndroid) return;
    final service = widget.updateService;
    if (service == null) return;
    try {
      final update = await service.check();
      if (!mounted || update == null) return;
      final shouldInstall = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Доступно обновление'),
          content: Text(
            'Вышла новая версия ${update.version}. '
            'Нажмите «Обновить», чтобы загрузить и установить её.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Позже'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Обновить'),
            ),
          ],
        ),
      );
      if (!mounted || shouldInstall != true) return;
      await _showUpdateFlow(context, service, update);
    } catch (_) {
      // Нет сети или релиз ещё не опубликован — приложение работает офлайн.
    }
  }

  Future<void> _loadAppointments() async {
    final appointments = await _db.getAll(widget.company.id);
    if (!mounted) return;
    setState(() {
      _allAppointments = appointments;
      _loading = false;
    });
  }

  Future<void> _deleteAppointment(int id) async {
    await _db.delete(id);
    await _loadAppointments();
  }

  Future<void> _saveAppointment(Appointment appointment) async {
    final conflicts = await _db.getForDay(
      widget.company.id,
      appointment.dateTime,
      master: appointment.master,
      excludeId: appointment.id,
    );
    final overlapping = conflicts.where((c) {
      final aStart = c.dateTime;
      final aEnd = aStart.add(Duration(minutes: c.durationMinutes));
      final bStart = appointment.dateTime;
      final bEnd = bStart.add(Duration(minutes: appointment.durationMinutes));
      return aStart.isBefore(bEnd) && bStart.isBefore(aEnd);
    }).toList();

    if (overlapping.isNotEmpty && mounted) {
      final conflict = overlapping.first;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Время пересекается'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Новое время накладывается на запись «${conflict.clientName}» '
                '(${conflict.master}, ${_formatDateTime(conflict.dateTime)}).',
              ),
              const SizedBox(height: 8),
              const Text(
                'Сохранить всё равно? Не забудьте предупредить второго клиента.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    if (appointment.id == null) {
      await _db.insert(appointment);
    } else {
      await _db.update(appointment);
    }
    await _loadAppointments();
  }

  Future<void> _showAppointmentDialog({
    Appointment? appointment,
    required DateTime initialDate,
  }) async {
    final result = await showDialog<Appointment>(
      context: context,
      builder: (context) => AppointmentDialog(
        database: _db,
        companyId: widget.company.id,
        initialDate: initialDate,
        appointment: appointment,
      ),
    );
    if (result != null) await _saveAppointment(result);
  }

  void _openAppointmentDialog() {
    _showAppointmentDialog(initialDate: _homeDayNotifier.value);
  }

  void _showNotificationDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => const AlertDialog(
        title: Text('Уведомления'),
        content: Text('Push-уведомления пока не реализованы'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      HomeTab(
        database: _db,
        company: widget.company,
        user: widget.user,
        appointments: _allAppointments,
        selectedDayNotifier: _homeDayNotifier,
        loading: _loading,
        onEdit: _showAppointmentDialog,
        onDelete: _deleteAppointment,
      ),
      CalendarTab(
        database: _db,
        company: widget.company,
        appointments: _allAppointments,
        loading: _loading,
        onEdit: _showAppointmentDialog,
        onDelete: _deleteAppointment,
      ),
      ClientsTab(
        database: _db,
        company: widget.company,
        isVisible: _currentIndex == 2,
      ),
      ServicesTab(
        database: _db,
        company: widget.company,
      ),
      MoreTab(
        database: _db,
        company: widget.company,
        onSwitchCompany: widget.onSwitchCompany,
        onLogout: widget.onLogout,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        title: Image.asset(
          'assets/icons/logo.png',
          height: 40,
          errorBuilder: (context, error, stackTrace) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.calendar_month,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Bizzy',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            onPressed: _showNotificationDialog,
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Уведомления',
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: tabs,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_filled),
            label: 'Главная',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today),
            label: 'Календарь',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            label: 'Клиенты',
          ),
          NavigationDestination(
            icon: Icon(Icons.spa),
            label: 'Услуги',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu),
            label: 'Ещё',
          ),
        ],
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: _openAppointmentDialog,
              icon: const Icon(Icons.add),
              label: const Text('Новая запись'),
            )
          : null,
    );
  }
}

class HomeTab extends StatefulWidget {
  const HomeTab({
    super.key,
    required this.database,
    required this.company,
    required this.user,
    required this.appointments,
    required this.selectedDayNotifier,
    required this.loading,
    required this.onEdit,
    required this.onDelete,
  });

  final AppointmentsDatabase database;
  final Company company;
  final User user;
  final List<Appointment> appointments;
  final ValueNotifier<DateTime> selectedDayNotifier;
  final bool loading;
  final Future<void> Function({
    Appointment? appointment,
    required DateTime initialDate,
  }) onEdit;
  final Future<void> Function(int) onDelete;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = _startOfDay(widget.selectedDayNotifier.value);
    widget.selectedDayNotifier.addListener(_onDayChanged);
  }

  @override
  void didUpdateWidget(covariant HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedDayNotifier != oldWidget.selectedDayNotifier) {
      oldWidget.selectedDayNotifier.removeListener(_onDayChanged);
      _selectedDay = _startOfDay(widget.selectedDayNotifier.value);
      widget.selectedDayNotifier.addListener(_onDayChanged);
    }
  }

  @override
  void dispose() {
    widget.selectedDayNotifier.removeListener(_onDayChanged);
    super.dispose();
  }

  void _onDayChanged() {
    if (!mounted) return;
    setState(() => _selectedDay = _startOfDay(widget.selectedDayNotifier.value));
  }

  void _selectDay(DateTime day) {
    widget.selectedDayNotifier.value = _startOfDay(day);
  }

  DateTime get _weekStart =>
      _selectedDay.subtract(Duration(days: _selectedDay.weekday - 1));

  @override
  Widget build(BuildContext context) {
    final dayAppointments = widget.appointments
        .where((a) => isSameDay(a.dateTime, _selectedDay))
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final todayCount = widget.appointments
        .where((a) => isSameDay(a.dateTime, DateTime.now()))
        .length;
    final hour = DateTime.now().hour;
    final String greeting;
    if (hour < 6) {
      greeting = 'Доброй ночи';
    } else if (hour < 12) {
      greeting = 'Доброе утро';
    } else if (hour < 18) {
      greeting = 'Добрый день';
    } else {
      greeting = 'Добрый вечер';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '$greeting, '),
                    TextSpan(
                      text: widget.user.login,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(text: '! ✨'),
                  ],
                ),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'У вас $todayCount записей сегодня',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey[700],
                    ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: SizedBox(
            height: 72,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 7,
              itemBuilder: (context, index) {
                final day = _weekStart.add(Duration(days: index));
                final selected = isSameDay(day, _selectedDay);
                return GestureDetector(
                  onTap: () => _selectDay(day),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFFFFD600) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat.E('ru_RU').format(day).toUpperCase(),
                          style: TextStyle(
                            color: selected ? Colors.black : Colors.grey[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${day.day}',
                          style: TextStyle(
                            color: selected ? Colors.black : Colors.black87,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        Expanded(
          child: widget.loading
              ? const Center(child: CircularProgressIndicator())
              : dayAppointments.isEmpty
                  ? const Center(
                      child: Text('На этот день записей нет.'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: dayAppointments.length,
                      itemBuilder: (context, index) {
                        final a = dayAppointments[index];
                        final initial = a.clientName.trim().isEmpty
                            ? ''
                            : a.clientName.trim()[0].toUpperCase();
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFFFFD600),
                              foregroundColor: Colors.black,
                              child: initial.isEmpty
                                  ? const Icon(Icons.person_outline)
                                  : Text(initial),
                            ),
                            title: Text(a.clientName),
                            subtitle: Text(a.service),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _formatTime(a.dateTime),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      widget.onEdit(
                                        appointment: a,
                                        initialDate: a.dateTime,
                                      );
                                    } else if (value == 'delete') {
                                      widget.onDelete(a.id!);
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Редактировать'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Удалить'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            onTap: () => widget.onEdit(
                              appointment: a,
                              initialDate: a.dateTime,
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class CalendarTab extends StatefulWidget {
  const CalendarTab({
    super.key,
    required this.database,
    required this.company,
    required this.appointments,
    required this.loading,
    required this.onEdit,
    required this.onDelete,
  });

  final AppointmentsDatabase database;
  final Company company;
  final List<Appointment> appointments;
  final bool loading;
  final Future<void> Function({
    Appointment? appointment,
    required DateTime initialDate,
  }) onEdit;
  final Future<void> Function(int) onDelete;

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  @override
  Widget build(BuildContext context) {
    final dayAppointments = widget.appointments
        .where((a) => isSameDay(a.dateTime, _selectedDay))
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    return widget.loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              TableCalendar<Appointment>(
                locale: 'ru_RU',
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                calendarFormat: _calendarFormat,
                eventLoader: (day) => widget.appointments
                    .where((a) => isSameDay(a.dateTime, day))
                    .toList(),
                availableCalendarFormats: const {
                  CalendarFormat.month: 'Месяц',
                  CalendarFormat.twoWeeks: '2 недели',
                  CalendarFormat.week: 'Неделя',
                },
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                },
                onFormatChanged: (format) {
                  setState(() => _calendarFormat = format);
                },
                onPageChanged: (focusedDay) {
                  _focusedDay = focusedDay;
                },
              ),
              Expanded(
                child: dayAppointments.isEmpty
                    ? const Center(
                        child: Text('На этот день записей нет.'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: dayAppointments.length,
                        itemBuilder: (context, index) {
                          final a = dayAppointments[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            child: ListTile(
                              title: Text(a.clientName),
                              subtitle: Text('${a.master} • ${a.service}'),
                              trailing: Text(_formatTime(a.dateTime)),
                              onTap: () => widget.onEdit(
                                appointment: a,
                                initialDate: a.dateTime,
                              ),
                              onLongPress: () => widget.onDelete(a.id!),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
  }
}

class ClientsTab extends StatefulWidget {
  const ClientsTab({
    super.key,
    required this.database,
    required this.company,
    this.isVisible = false,
  });

  final AppointmentsDatabase database;
  final Company company;
  final bool isVisible;

  @override
  State<ClientsTab> createState() => _ClientsTabState();
}

class _ClientsTabState extends State<ClientsTab> {
  List<Contact> _contacts = [];
  String _query = '';
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVisible) _load();
  }

  @override
  void didUpdateWidget(covariant ClientsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isVisible && widget.isVisible) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final contacts = await widget.database.getContacts(
        ContactType.client,
        widget.company.id,
      );
      if (!mounted) return;
      setState(() => _contacts = contacts);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addClient() async {
    final contact = await showDialog<Contact>(
      context: context,
      builder: (context) => AddContactDialog(
        database: widget.database,
        type: ContactType.client,
        companyId: widget.company.id,
      ),
    );
    if (!mounted || contact == null) return;
    await _load();
  }

  Future<void> _importClients() async {
    final contact = await showDialog<Contact>(
      context: context,
      builder: (context) => ImportContactsDialog(
        database: widget.database,
        type: ContactType.client,
        companyId: widget.company.id,
      ),
    );
    if (!mounted || contact == null) return;
    await _load();
  }

  Future<void> _editClient(Contact contact) async {
    final result = await showDialog<Contact>(
      context: context,
      builder: (context) => AddContactDialog(
        database: widget.database,
        type: ContactType.client,
        companyId: widget.company.id,
        contact: contact,
      ),
    );
    if (!mounted || result == null) return;
    await _load();
  }

  Future<void> _deleteClient(Contact contact) async {
    final inAppointments = await _isContactUsed(contact);
    if (!mounted) return;
    final confirmed = await _confirmDelete(context, contact, inAppointments);
    if (!confirmed || !mounted) return;
    try {
      await widget.database.deleteContact(ContactType.client, contact.id);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось удалить клиента')),
      );
    }
  }

  Future<bool> _isContactUsed(Contact contact) async {
    final appointments =
        await widget.database.getAll(widget.company.id);
    return appointments.any(
      (a) => a.clientName == contact.name || a.master == contact.name,
    );
  }

  Future<bool> _confirmDelete(
    BuildContext context,
    Contact contact,
    bool inAppointments,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Удалить ${contact.name}?'),
            content: inAppointments
                ? const Text(
                    'Записи с этим клиентом/мастером останутся, удалится только '
                    'запись в справочнике.',
                  )
                : const Text('Удалить запись из справочника?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Удалить'),
              ),
            ],
          ),
        ) ??
        false;
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Поиск по имени или телефону',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(
                      () => _query = value.trim().toLowerCase(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _importClients,
                  icon: const Icon(Icons.contacts),
                  tooltip: 'Импорт из телефона',
                ),
              ],
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
                                  ? 'Клиентов пока нет'
                                  : 'Ничего не найдено',
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 88),
                            itemCount: contacts.length,
                            itemBuilder: (context, index) {
                              final contact = contacts[index];
                              return ListTile(
                                leading: const Icon(Icons.person_outline),
                                title: Text(contact.name),
                                subtitle: contact.phone.isEmpty
                                    ? null
                                    : Text(contact.phone),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _editClient(contact);
                                    } else if (value == 'delete') {
                                      _deleteClient(contact);
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Редактировать'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Удалить'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: _addClient,
        icon: const Icon(Icons.add),
        label: const Text('Добавить клиента'),
      ),
    );
  }
}

class AddServiceDialog extends StatefulWidget {
  const AddServiceDialog({
    super.key,
    required this.database,
    required this.companyId,
    this.service,
  });

  final AppointmentsDatabase database;
  final int companyId;
  final Service? service;

  @override
  State<AddServiceDialog> createState() => _AddServiceDialogState();
}

class _AddServiceDialogState extends State<AddServiceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _durationController = TextEditingController();
  final _notesController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = widget.service;
    _nameController.text = s?.name ?? '';
    _priceController.text = s?.price.toString() ?? '';
    _durationController.text = (s?.durationMinutes ?? 60).toString();
    _notesController.text = s?.notes ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _durationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final price = double.tryParse(_priceController.text.trim()) ?? 0;
    final duration = int.tryParse(_durationController.text.trim()) ?? 60;
    final service = Service(
      id: widget.service?.id,
      companyId: widget.companyId,
      name: _nameController.text,
      price: price,
      durationMinutes: duration,
      notes: _notesController.text,
    );
    try {
      final saved = widget.service == null
          ? await widget.database.createService(service)
          : await widget.database.updateService(service).then((_) => service);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
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
    final isEdit = widget.service != null;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(isEdit ? 'Редактирование услуги' : 'Новая услуга'),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Название',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Введите название'
                      : null,
                ),
                const SizedBox(height: 12),
                ListenableBuilder(
                  listenable: _currency,
                  builder: (context, _) => TextFormField(
                    controller: _priceController,
                    enabled: !_saving,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Цена, ${_currency.value.symbol}',
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final n = double.tryParse(value?.trim() ?? '');
                      if (n == null || n < 0) return 'Введите число';
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _durationController,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Длительность, мин',
                    border: OutlineInputBorder(),
                    hintText: '60',
                  ),
                  validator: (value) {
                    final n = int.tryParse(value?.trim() ?? '');
                    if (n == null || n < 1) return 'Введите целое число';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Примечания',
                    border: OutlineInputBorder(),
                  ),
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

class ServicesTab extends StatefulWidget {
  const ServicesTab({
    super.key,
    required this.database,
    required this.company,
  });

  final AppointmentsDatabase database;
  final Company company;

  @override
  State<ServicesTab> createState() => _ServicesTabState();
}

class _ServicesTabState extends State<ServicesTab> {
  List<Service> _services = [];
  String _query = '';
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ServicesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.company.id != widget.company.id) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final services =
          await widget.database.getServices(widget.company.id);
      if (!mounted) return;
      setState(() => _services = services);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addService() async {
    final service = await showDialog<Service>(
      context: context,
      builder: (context) => AddServiceDialog(
        database: widget.database,
        companyId: widget.company.id,
      ),
    );
    if (!mounted || service == null) return;
    await _load();
  }

  Future<void> _editService(Service service) async {
    final result = await showDialog<Service>(
      context: context,
      builder: (context) => AddServiceDialog(
        database: widget.database,
        companyId: widget.company.id,
        service: service,
      ),
    );
    if (!mounted || result == null) return;
    await _load();
  }

  Future<void> _deleteService(Service service) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить услугу?'),
        content: Text('Услуга «${service.name}» будет удалена.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.database.deleteService(service.id!);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось удалить услугу')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayed = _services
        .where(
          (s) => s.name.toLowerCase().contains(_query),
        )
        .toList();
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Поиск по названию',
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
                    : displayed.isEmpty
                        ? Center(
                            child: Text(
                              _query.isEmpty
                                  ? 'Услуг пока нет'
                                  : 'Ничего не найдено',
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 88),
                            itemCount: displayed.length,
                            itemBuilder: (context, index) {
                              final service = displayed[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                child: ListTile(
                                  leading: const Icon(Icons.spa),
                                  title: Text(service.name),
                                  subtitle: ValueListenableBuilder<Currency>(
                                    valueListenable: _currency,
                                    builder: (context, currency, _) => Text(
                                      '${service.price.toStringAsFixed(2)} ${currency.symbol} • ${service.durationMinutes} мин',
                                    ),
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (value) {
                                      if (value == 'edit') {
                                        _editService(service);
                                      } else if (value == 'delete') {
                                        _deleteService(service);
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Редактировать'),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Удалить'),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: _addService,
        icon: const Icon(Icons.add),
        label: const Text('Добавить услугу'),
      ),
    );
  }
}

class MoreTab extends StatefulWidget {
  const MoreTab({
    super.key,
    required this.database,
    required this.company,
    required this.onSwitchCompany,
    required this.onLogout,
  });

  final AppointmentsDatabase database;
  final Company company;
  final VoidCallback onSwitchCompany;
  final VoidCallback onLogout;

  @override
  State<MoreTab> createState() => _MoreTabState();
}

class _MoreTabState extends State<MoreTab> {
  PackageInfo _info = PackageInfo(
    appName: 'Bizzy',
    packageName: '',
    version: '',
    buildNumber: '',
  );

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _info = info);
    } catch (_) {
      // В тестах PackageInfo может быть недоступен.
    }
  }

  Future<void> _checkUpdates() async {
    if (!Platform.isAndroid) return;
    const service = UpdateService();
    try {
      final update = await service.check();
      if (!mounted) return;
      if (update == null) {
        await showDialog<void>(
          context: context,
          builder: (context) => const AlertDialog(
            content: Text('Обновлений пока нет'),
          ),
        );
        return;
      }
      final shouldInstall = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Доступно обновление'),
          content: Text(
            'Вышла новая версия ${update.version}. '
            'Нажмите «Обновить», чтобы загрузить и установить её.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Позже'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Обновить'),
            ),
          ],
        ),
      );
      if (!mounted || shouldInstall != true) return;
      await _showUpdateFlow(context, service, update);
    } catch (_) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => const AlertDialog(
          content: Text('Не удалось проверить обновления'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final version = '${_info.version}${_info.buildNumber.isNotEmpty ? '+${_info.buildNumber}' : ''}';
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        ListTile(
          leading: const Icon(Icons.badge_outlined),
          title: const Text('Мастера'),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (context) => ContactsScreen(
                database: widget.database,
                type: ContactType.master,
                companyId: widget.company.id,
              ),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.settings),
          title: const Text('Настройки'),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (context) => const SettingsScreen(),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.business),
          title: const Text('Сменить компанию'),
          onTap: widget.onSwitchCompany,
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Выйти из аккаунта'),
          onTap: widget.onLogout,
        ),
        if (Platform.isAndroid)
          ListTile(
            leading: const Icon(Icons.system_update),
            title: const Text('Проверить обновления'),
            onTap: _checkUpdates,
          ),
        const Divider(),
        ListTile(
          title: Text(widget.company.name),
          subtitle: Text('Версия $version'),
        ),
      ],
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

  Future<void> _importContacts() async {
    final contact = await showDialog<Contact>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ImportContactsDialog(
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

  Future<void> _editContact(Contact contact) async {
    final result = await showDialog<Contact>(
      context: context,
      builder: (context) => AddContactDialog(
        database: widget.database,
        type: widget.type,
        companyId: widget.companyId,
        contact: contact,
      ),
    );
    if (!mounted || result == null) return;
    if (widget.selectContact) {
      Navigator.of(context).pop(result);
    } else {
      await _load();
    }
  }

  Future<void> _deleteContact(Contact contact) async {
    final inAppointments = await _isContactUsed(contact);
    if (!mounted) return;
    final confirmed = await _confirmDelete(context, contact, inAppointments);
    if (!confirmed || !mounted) return;
    try {
      await widget.database.deleteContact(widget.type, contact.id);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Не удалось удалить ${widget.type == ContactType.client ? 'клиента' : 'мастера'}',
          ),
        ),
      );
    }
  }

  Future<bool> _isContactUsed(Contact contact) async {
    final appointments = await widget.database.getAll(widget.companyId);
    return appointments.any(
      (a) => a.clientName == contact.name || a.master == contact.name,
    );
  }

  Future<bool> _confirmDelete(
    BuildContext context,
    Contact contact,
    bool inAppointments,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Удалить ${contact.name}?'),
            content: inAppointments
                ? const Text(
                    'Записи с этим клиентом/мастером останутся, удалится только '
                    'запись в справочнике.',
                  )
                : const Text('Удалить запись из справочника?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Удалить'),
              ),
            ],
          ),
        ) ??
        false;
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
      appBar: AppBar(
        title: Text(widget.type.title),
        actions: [
          if (!widget.selectContact)
            IconButton(
              onPressed: _importContacts,
              icon: const Icon(Icons.contacts),
              tooltip: 'Импорт из телефона',
            ),
        ],
      ),
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
                                    : PopupMenuButton<String>(
                                        onSelected: (value) {
                                          if (value == 'edit') {
                                            _editContact(contact);
                                          } else if (value == 'delete') {
                                            _deleteContact(contact);
                                          }
                                        },
                                        itemBuilder: (context) => const [
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: Text('Редактировать'),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Удалить'),
                                          ),
                                        ],
                                      ),
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
        heroTag: null,
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
    this.contact,
  });

  final AppointmentsDatabase database;
  final ContactType type;
  final int companyId;
  final Contact? contact;

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
  void initState() {
    super.initState();
    final c = widget.contact;
    if (c != null) {
      _nameController.text = c.name;
      _phoneController.text = c.phone;
    }
  }

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
      final name = _nameController.text;
      final phone = _phoneController.text;
      final contact = widget.contact == null
          ? await widget.database.saveContact(
              widget.type,
              widget.companyId,
              name,
              phone,
            )
          : await widget.database
              .updateContact(
                widget.type,
                widget.companyId,
                widget.contact!,
                name,
                phone,
              )
              .then(
                (_) => Contact(
                  id: widget.contact!.id,
                  name: name.trim(),
                  phone: phone.trim(),
                ),
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

  Future<void> _importFromPhone() async {
    final contact = await showDialog<Contact>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ImportContactsDialog(
        database: widget.database,
        type: widget.type,
        companyId: widget.companyId,
      ),
    );
    if (!mounted || contact == null) return;
    Navigator.of(context).pop(contact);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.contact != null;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(
          isEdit
              ? (widget.type == ContactType.client
                  ? 'Редактировать клиента'
                  : 'Редактировать мастера')
              : widget.type.addTitle,
        ),
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
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _importFromPhone,
                  icon: const Icon(Icons.contacts),
                  label: const Text('Импортировать из телефона'),
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

class ImportContactsDialog extends StatefulWidget {
  const ImportContactsDialog({
    super.key,
    required this.database,
    required this.type,
    required this.companyId,
  });

  final AppointmentsDatabase database;
  final ContactType type;
  final int companyId;

  @override
  State<ImportContactsDialog> createState() => _ImportContactsDialogState();
}

class _ImportContactsDialogState extends State<ImportContactsDialog> {
  List<phone.Contact> _contacts = [];
  final _selectedIds = <String>{};
  final _searchController = TextEditingController();
  bool _loading = true;
  bool _denied = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final status = await phone.FlutterContacts.permissions.request(
      phone.PermissionType.read,
    );
    if (status != phone.PermissionStatus.granted) {
      if (mounted) setState(() => _denied = true);
      return;
    }
    await _load();
  }

  Future<void> _load() async {
    try {
      final list = await phone.FlutterContacts.getAll(
        properties: {phone.ContactProperty.phone},
      );
      list.sort((a, b) => (a.displayName ?? '').compareTo(b.displayName ?? ''));
      if (mounted) {
        setState(() {
          _contacts = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _denied = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _import() async {
    if (_selectedIds.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final selected = _contacts
          .where((c) => c.id != null && _selectedIds.contains(c.id!))
          .toList();
      Contact? first;
      for (final c in selected) {
        final name = (c.displayName ?? '').trim();
        if (name.isEmpty) continue;
        final phoneNumber = c.phones.isNotEmpty ? c.phones.first.number : '';
        if (widget.type == ContactType.client && phoneNumber.trim().isEmpty) {
          continue;
        }
        final saved = await widget.database.saveContact(
          widget.type,
          widget.companyId,
          name,
          phoneNumber,
        );
        first ??= saved;
      }
      if (!mounted) return;
      Navigator.of(context).pop(first);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  bool _matches(phone.Contact c) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    final name = (c.displayName ?? '').toLowerCase();
    if (name.contains(query)) return true;
    for (final p in c.phones) {
      final number = p.number.toLowerCase();
      if (number.contains(query)) return true;
    }
    return false;
  }

  String _subtitle(phone.Contact c) {
    final number = c.phones.isNotEmpty ? c.phones.first.number : '';
    if (widget.type == ContactType.client && number.isEmpty) {
      return 'Нет телефона — не будет импортирован';
    }
    return number;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _contacts.where(_matches).toList();
    final allSelected = filtered.isNotEmpty &&
        filtered.every(
          (c) => c.id != null && _selectedIds.contains(c.id!),
        );

    return AlertDialog(
      title: const Text('Импорт из телефона'),
      content: SizedBox(
        width: double.maxFinite,
        height: 480,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Поиск по имени или телефону',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            if (_denied)
              const Expanded(
                child: Center(
                  child: Text(
                    'Нужно разрешение на доступ к контактам.\n'
                    'Разрешите его в настройках телефона.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('Ничего не найдено'))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final c = filtered[index];
                          final disabled = c.id == null ||
                              (widget.type == ContactType.client &&
                                  c.phones.isEmpty);
                          return CheckboxListTile(
                            value: c.id != null && _selectedIds.contains(c.id!),
                            onChanged: disabled
                                ? null
                                : (selected) {
                                    setState(() {
                                      if (c.id == null) return;
                                      if (selected == true) {
                                        _selectedIds.add(c.id!);
                                      } else {
                                        _selectedIds.remove(c.id!);
                                      }
                                    });
                                  },
                            title: Text(c.displayName ?? ''),
                            subtitle: Text(_subtitle(c)),
                          );
                        },
                      ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        if (!_denied && !_loading)
          TextButton(
            onPressed: () {
              setState(() {
                if (allSelected) {
                  for (final c in filtered) {
                    if (c.id != null) _selectedIds.remove(c.id!);
                  }
                } else {
                  for (final c in filtered) {
                    if (c.id == null) continue;
                    if (widget.type == ContactType.client &&
                        c.phones.isEmpty) {
                      continue;
                    }
                    _selectedIds.add(c.id!);
                  }
                }
              });
            },
            child: Text(allSelected ? 'Снять всё' : 'Выбрать всё'),
          ),
        FilledButton(
          onPressed: _selectedIds.isEmpty || _saving ? null : _import,
          child: Text(_saving
              ? 'Сохранение…'
              : 'Импортировать (${_selectedIds.length})'),
        ),
      ],
    );
  }
}

class AppointmentDialog extends StatefulWidget {
  const AppointmentDialog({
    super.key,
    required this.database,
    required this.companyId,
    required this.initialDate,
    this.appointment,
  });

  final AppointmentsDatabase database;
  final int companyId;
  final DateTime initialDate;
  final Appointment? appointment;

  @override
  State<AppointmentDialog> createState() => _AppointmentDialogState();
}

class _AppointmentDialogState extends State<AppointmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _serviceController = TextEditingController();
  final _notesController = TextEditingController();
  final _durationController = TextEditingController();
  Contact? _client;
  Contact? _master;
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  int _reminderMinutes = 30;
  int? _appointmentId;
  List<Service> _services = [];
  Service? _selectedService;
  bool _loadingServices = true;

  static const _reminderOptions = {
    15: '15 минут',
    30: '30 минут',
    60: '1 час',
    120: '2 часа',
    1440: '1 день',
  };

  @override
  void initState() {
    super.initState();
    final a = widget.appointment;
    _appointmentId = a?.id;
    _selectedDate = a?.dateTime ?? widget.initialDate;
    _selectedTime = a != null
        ? TimeOfDay(hour: a.dateTime.hour, minute: a.dateTime.minute)
        : TimeOfDay.now();
    _client = a != null ? Contact(id: 0, name: a.clientName, phone: a.phone) : null;
    _master = a != null ? Contact(id: 0, name: a.master, phone: '') : null;
    _phoneController.text = a?.phone ?? '';
    _serviceController.text = a?.service ?? '';
    _notesController.text = a?.notes ?? '';
    _durationController.text = (a?.durationMinutes ?? 60).toString();
    _reminderMinutes = a?.reminderMinutes ?? 30;
    _loadServices();
  }

  Future<void> _loadServices() async {
    final services = await widget.database.getServices(widget.companyId);
    if (!mounted) return;
    final a = widget.appointment;
    final match = a == null
        ? null
        : services.cast<Service?>().firstWhere(
              (s) => s!.name == a.service,
              orElse: () => null,
            );
    setState(() {
      _services = services;
      _selectedService = match;
      _loadingServices = false;
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _serviceController.dispose();
    _notesController.dispose();
    _durationController.dispose();
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
      initialValue: isClient ? _client : _master,
      validator: (value) => value == null
          ? (isClient ? 'Выберите клиента' : 'Выберите мастера')
          : null,
      builder: (field) => InputDecorator(
        decoration: InputDecoration(
          labelText: isClient ? 'Клиент' : 'Мастер',
          errorText: field.errorText,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        isEmpty: false,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => _selectContact(type, field),
          icon: Icon(
            isClient ? Icons.person_outline : Icons.badge_outlined,
            size: 20,
          ),
          label: Text(field.value?.name ?? label),
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

  Future<void> _onServiceSelected(Service? value) async {
    if (value == null) {
      setState(() => _selectedService = null);
      _serviceController.text = '';
      return;
    }
    final addNew = Service(
      id: -1,
      companyId: widget.companyId,
      name: '+ Добавить услугу',
      price: 0,
      durationMinutes: 0,
      notes: '',
    );
    if (value.id == addNew.id && value.name == addNew.name) {
      final result = await showDialog<Service>(
        context: context,
        builder: (context) => AddServiceDialog(
          database: widget.database,
          companyId: widget.companyId,
        ),
      );
      if (!mounted) return;
      if (result == null) {
        setState(() {});
        return;
      }
      setState(() {
        _services = [..._services, result]..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        _selectedService = result;
      });
      _serviceController.text = result.name;
      _durationController.text = result.durationMinutes.toString();
      return;
    }
    setState(() => _selectedService = value);
    _serviceController.text = value.name;
    _durationController.text = value.durationMinutes.toString();
  }

  Widget _serviceDropdown() {
    if (_loadingServices) {
      return const InputDecorator(
        decoration: InputDecoration(
          labelText: 'Выбрать услугу',
          border: OutlineInputBorder(),
        ),
        child: SizedBox(
          height: 24,
          child: Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final addNew = Service(
      id: -1,
      companyId: widget.companyId,
      name: '+ Добавить услугу',
      price: 0,
      durationMinutes: 0,
      notes: '',
    );

    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Выбрать услугу',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      isEmpty: false,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Service?>(
          key: const Key('service_dropdown'),
          value: _selectedService,
          isExpanded: true,
          isDense: true,
          items: [
            const DropdownMenuItem<Service?>(
              value: null,
              child: Text('— Своя услуга —'),
            ),
            ..._services.map(
              (s) => DropdownMenuItem(
                value: s,
                child: Text(s.name),
              ),
            ),
            DropdownMenuItem(
              value: addNew,
              child: const Text('+ Добавить услугу'),
            ),
          ],
          onChanged: (value) => _onServiceSelected(value),
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final duration = int.tryParse(_durationController.text.trim()) ?? 60;
    final dateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    Navigator.of(context).pop(
      Appointment(
        id: _appointmentId,
        companyId: widget.companyId,
        clientName: _client!.name,
        phone: _phoneController.text.trim(),
        service: _serviceController.text.trim(),
        master: _master!.name,
        dateTime: dateTime,
        durationMinutes: duration,
        reminderMinutes: _reminderMinutes,
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
    final isEdit = widget.appointment != null;
    return AlertDialog(
      title: Text(isEdit ? 'Редактирование записи' : 'Новая запись'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _contactField(ContactType.client),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Телефон',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                keyboardType: TextInputType.phone,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Введите телефон'
                    : null,
              ),
              const SizedBox(height: 12),
              _serviceDropdown(),
              const SizedBox(height: 12),
              TextFormField(
                controller: _serviceController,
                decoration: const InputDecoration(
                  labelText: 'Услуга',
                  hintText: 'Выберите из списка или введите свою',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onChanged: (_) {
                  final text = _serviceController.text.trim();
                  final match = _services.cast<Service?>().firstWhere(
                        (s) => s!.name == text,
                        orElse: () => null,
                      );
                  setState(() => _selectedService = match);
                },
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Введите услугу'
                    : null,
              ),
              const SizedBox(height: 12),
              _contactField(ContactType.master),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today),
                      label: Text(dateText),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Icons.access_time),
                      label: Text(timeText),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _durationController,
                decoration: const InputDecoration(
                  labelText: 'Продолжительность (мин)',
                  hintText: '60',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  final n = int.tryParse(value?.trim() ?? '');
                  if (n == null || n < 1) return 'Введите целое число минут';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Напомнить за',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                isEmpty: false,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _reminderMinutes,
                    isExpanded: true,
                    isDense: true,
                    items: _reminderOptions.entries
                        .map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _reminderMinutes = value);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Примечания',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
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
