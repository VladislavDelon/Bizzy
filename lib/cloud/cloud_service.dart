import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// Точка доступа к Supabase-клиенту.
SupabaseClient get supabase => Supabase.instance.client;

/// true, если Supabase инициализирован и есть активная сессия.
/// Безопасно вызывать и в режиме без облака (тесты/локальный вход).
bool get cloudSignedIn =>
    Supabase.instance.isInitialized &&
    Supabase.instance.client.auth.currentUser != null;

/// Домен технических email — пользователь вводит только логин,
/// Supabase Auth внутри работает с email вида `<логин>@bizzy.app`.
const String kLoginEmailDomain = 'bizzy.app';

/// Превращает логин в email для Supabase Auth.
/// - Ввод с '@' — это настоящий email старого аккаунта, возвращаем как есть.
/// - ASCII-логин [a-z0-9._-] — `логин@bizzy.app`.
/// - Любой другой (кириллица и т.п.) — `u<base64url>@bizzy.app`,
///   чтобы остаться в допустимом формате email и не терять уникальность.
String loginToEmail(String input) {
  final login = input.trim().toLowerCase();
  if (login.contains('@')) return login;
  if (RegExp(r'^[a-z0-9._-]+$').hasMatch(login)) {
    return '$login@$kLoginEmailDomain';
  }
  final encoded =
      base64UrlEncode(utf8.encode(login)).replaceAll('=', '');
  return 'u$encoded@$kLoginEmailDomain';
}

/// Обратная операция: достаёт логин из технического email.
/// Если email настоящий (не наш домен) — возвращает его целиком.
String emailToLogin(String email) {
  const suffix = '@$kLoginEmailDomain';
  if (!email.endsWith(suffix)) return email;
  final local = email.substring(0, email.length - suffix.length);
  if (local.startsWith('u') && local.length > 1) {
    try {
      var b64 = local.substring(1);
      b64 = b64.padRight((b64.length + 3) ~/ 4 * 4, '=');
      return utf8.decode(base64Url.decode(b64));
    } catch (_) {
      return local;
    }
  }
  return local;
}

/// Пароль, который реально уходит в Supabase Auth.
///
/// Supabase отклоняет «слишком простые» пароли: проверка по слитым базам
/// (HaveIBeenPwned) и требования к символам включены на сервере и из кода
/// не отключаются. Поэтому приложение принимает ЛЮБОЙ пароль от 6 знаков,
/// а на сервер отправляет производную 'Bz!9' + sha256(пароль): 68 символов,
/// все классы (заглавные/строчные/цифры/символ) — серверные проверки
/// пройдут всегда, а знания производной достаточно для входа.
///
/// Аккаунты, созданные до этого изменения, хранят «сырой» пароль —
/// для них signIn делает запасную попытку с исходным вариантом.
String hardPassword(String raw) =>
    'Bz!9${sha256.convert(utf8.encode(raw))}';

// ---------- Безопасный парсинг ответов Supabase ----------
String _parseString(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  if (value is String) return value;
  return value.toString();
}

int _parseInt(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

/// true, если ошибка Postgrest означает «колонки нет в таблице»
/// (например, старая база без миграции published/service_price).
bool _isMissingColumn(PostgrestException e, String column) =>
    e.code == '42703' || e.message.contains(column);

/// Имя отсутствующей колонки из ошибки Postgrest:
/// PGRST204 «Could not find the 'avatar_url' column of 'profiles'...»
/// или 42703 «column master_profiles.address does not exist».
String? _missingColumnName(PostgrestException e) =>
    RegExp(r"'(\w+)' column").firstMatch(e.message)?.group(1) ??
    RegExp(r'column\s+(?:\w+\.)?(\w+)\s+does not exist')
        .firstMatch(e.message)
        ?.group(1);

/// Выполняет [run] с [payload]; при PGRST204 выкидывает отсутствующую
/// колонку из payload и повторяет — старые базы без свежих миграций
/// продолжают сохранять основные поля.
Future<void> _runWithMissingColumnFallback(
  Map<String, dynamic> payload,
  Future<void> Function(Map<String, dynamic>) run,
) async {
  for (var attempt = 0; attempt <= payload.length; attempt++) {
    try {
      await run(payload);
      return;
    } on PostgrestException catch (e) {
      final col = _missingColumnName(e);
      if (col == null || !payload.containsKey(col)) rethrow;
      payload.remove(col);
    }
  }
}

/// SELECT с фолбэком: при PGRST204 убирает отсутствующую колонку
/// из выборки и повторяет — работает на старых базах без миграций.
extension _ResilientSelect on CloudService {
  Future<List<dynamic>> _selectResilient(
    String table,
    List<String> fields, {
    String? inColumn,
    List<Object>? inValues,
    String? eqColumn,
    Object? eqValue,
    String? orderBy,
    bool ascending = false,
  }) async {
    var cols = List<String>.of(fields);
    for (var attempt = 0; attempt <= fields.length; attempt++) {
      try {
        var q = supabase.from(table).select(cols.join(', '));
        if (inColumn != null && inValues != null) {
          q = q.inFilter(inColumn, inValues);
        }
        if (eqColumn != null) {
          q = q.eq(eqColumn, eqValue as Object);
        }
        if (orderBy != null && cols.contains(orderBy)) {
          return await q.order(orderBy, ascending: ascending);
        }
        return await q;
      } on PostgrestException catch (e) {
        final col = _missingColumnName(e);
        if (col == null || !cols.contains(col)) rethrow;
        cols = List.of(cols)..remove(col);
      }
    }
    return const [];
  }
}

/// «На Bizzy с …»: человекочитаемый стаж аккаунта.
String bizzySince(DateTime? createdAt) {
  if (createdAt == null) return '';
  final days = DateTime.now().difference(createdAt).inDays;
  if (days < 30) return 'новичок на Bizzy';
  const months = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  return 'на Bizzy с ${months[createdAt.month - 1]} ${createdAt.year}';
}

double _parseDouble(dynamic value, {double fallback = 0}) {
  if (value == null) return fallback;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

bool _parseBool(dynamic value, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value.toInt() == 1;
  if (value is String) {
    final s = value.trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 't';
  }
  return fallback;
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  if (value is String) {
    final dt = DateTime.tryParse(value);
    return dt?.toLocal();
  }
  return null;
}

/// Вытаскивает Map из одиночного объекта или первого элемента списка.
/// Нужно, потому что Supabase в embedded-запросах может вернуть Map или List.
Map<String, dynamic>? _pickProfileMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is List && value.isNotEmpty) {
    final first = value.first;
    if (first is Map<String, dynamic>) return first;
  }
  return null;
}

/// Файловый лог для диагностики облачной синхронизации.
class SyncLog {
  static const _fileName = 'bizzy_sync.log';

  static Future<String> _path() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$_fileName';
  }

  static Future<String> read() async {
    try {
      final file = File(await _path());
      if (!await file.exists()) return '';
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  static Future<void> clear() async {
    try {
      final file = File(await _path());
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Future<void> write(String tag, String message) async {
    try {
      final file = File(await _path());
      final now = DateTime.now().toLocal().toIso8601String();
      final line = '[$now] [$tag] $message\n';
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    } catch (_) {
      // Не блокируем работу при ошибке записи лога.
    }
  }
}

/// Профиль пользователя из облачной таблицы `profiles`.
class CloudProfile {
  const CloudProfile({
    required this.id,
    required this.role,
    required this.name,
    required this.phone,
    this.avatarUrl = '',
    this.address = '',
    this.lat,
    this.lng,
    this.createdAt,
    this.phonePublic = true,
  });

  final String id;
  final String role; // 'client' | 'master' | 'salon'
  final String name;
  final String phone;
  final String avatarUrl;
  final String address;
  final double? lat;
  final double? lng;
  final DateTime? createdAt;

  /// Клиент разрешает показывать свой номер мастерам/салонам.
  final bool phonePublic;

  bool get isMaster => role == 'master';
  bool get isSalon => role == 'salon';
  bool get isClient => role == 'client';
  bool get hasLocation => lat != null && lng != null;

  factory CloudProfile.fromMap(Map<String, dynamic> map) => CloudProfile(
        id: _parseString(map['id']),
        role: _parseString(map['role'], fallback: 'client'),
        name: _parseString(map['name']),
        phone: _parseString(map['phone']),
        avatarUrl: _parseString(map['avatar_url']),
        address: _parseString(map['address']),
        lat: map['lat'] == null ? null : _parseDouble(map['lat']),
        lng: map['lng'] == null ? null : _parseDouble(map['lng']),
        createdAt: _parseDateTime(map['created_at']),
        phonePublic: _parseBool(map['phone_public'], fallback: true),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'role': role,
        'name': name,
        'phone': phone,
        'avatar_url': avatarUrl,
        'address': address,
        'lat': lat,
        'lng': lng,
        'created_at': createdAt?.toIso8601String(),
        'phone_public': phonePublic,
      };
}

/// Профиль мастера + имя/телефон из `profiles`.
class MasterCard {
  const MasterCard({
    required this.userId,
    required this.name,
    required this.phone,
    required this.category,
    required this.description,
    required this.address,
    required this.social,
    required this.phonePublic,
    required this.avatarUrl,
    required this.ratingAvg,
    required this.ratingCount,
    this.role = 'master',
    this.lat,
    this.lng,
    this.prepayEnabled = false,
    this.prepayAmount = 0,
    this.prepayLink = '',
    this.createdAt,
    this.salonId,
    this.salonKey = '',
    this.autoAssign = false,
  });

  final String userId;
  final String name;
  final String phone;
  final String role; // 'master' | 'salon' — салон = компания, мастер = частник
  final String category;
  final String description;
  final String address;
  final String social;
  final bool phonePublic;
  final String avatarUrl;
  final double ratingAvg;
  final int ratingCount;
  final double? lat;
  final double? lng;

  /// Мастер принимает предоплату — клиент платит до записи.
  final bool prepayEnabled;

  /// Сумма предоплаты в валюте мастера.
  final double prepayAmount;

  /// Pay-ссылка банка мастера (Kaspi, Halyk и т.п.).
  final String prepayLink;

  /// Дата регистрации профиля — «на Bizzy с …».
  final DateTime? createdAt;

  /// id салона-работодателя (null — самозанятый мастер).
  final String? salonId;

  /// Уникальный ключ салона для регистрации его мастеров.
  final String salonKey;

  /// Салон: автоматически распределять заявки между своими мастерами.
  final bool autoAssign;

  bool get hasLocation => lat != null && lng != null;
  bool get isSalon => role == 'salon';

  factory MasterCard.fromMap(
    Map<String, dynamic> map, {
    Map<String, dynamic>? fallbackProfile,
  }) {
    final profile = _pickProfileMap(map['profiles']) ?? fallbackProfile;
    return MasterCard(
      // У «бескарточных» провайдеров (собранных из profiles) user_id
      // в map отсутствует — берём id профиля, иначе избранное и запись
      // падают на пустом uuid.
      userId: map['user_id'] != null
          ? _parseString(map['user_id'])
          : _parseString(profile?['id']),
      name: profile != null ? _parseString(profile['name']) : '',
      phone: profile != null ? _parseString(profile['phone']) : '',
      role: profile != null
          ? _parseString(profile['role'], fallback: 'master')
          : 'master',
      category: _parseString(map['category'], fallback: 'Другое'),
      description: _parseString(map['description']),
      address: _parseString(map['address']),
      social: _parseString(map['social']),
      phonePublic: _parseBool(map['phone_public'], fallback: false),
      avatarUrl: _parseString(map['avatar_url']),
      ratingAvg: _parseDouble(map['rating_avg']),
      ratingCount: _parseInt(map['rating_count']),
      lat: map['lat'] == null ? null : _parseDouble(map['lat']),
      lng: map['lng'] == null ? null : _parseDouble(map['lng']),
      prepayEnabled: _parseBool(map['prepay_enabled'], fallback: false),
      prepayAmount: _parseDouble(map['prepay_amount']),
      prepayLink: _parseString(map['prepay_link']),
      createdAt: _parseDateTime(profile?['created_at']),
      salonId: map['salon_id'] == null
          ? null
          : _parseString(map['salon_id']),
      salonKey: _parseString(map['salon_key']),
      autoAssign: _parseBool(map['auto_assign'], fallback: false),
    );
  }

  MasterCard copyWith({
    String? userId,
    String? name,
    String? phone,
    String? role,
    String? category,
    String? description,
    String? address,
    String? social,
    bool? phonePublic,
    String? avatarUrl,
    double? ratingAvg,
    int? ratingCount,
    double? lat,
    double? lng,
    bool? prepayEnabled,
    double? prepayAmount,
    String? prepayLink,
  }) =>
      MasterCard(
        userId: userId ?? this.userId,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        role: role ?? this.role,
        category: category ?? this.category,
        description: description ?? this.description,
        address: address ?? this.address,
        social: social ?? this.social,
        phonePublic: phonePublic ?? this.phonePublic,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        ratingAvg: ratingAvg ?? this.ratingAvg,
        ratingCount: ratingCount ?? this.ratingCount,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        prepayEnabled: prepayEnabled ?? this.prepayEnabled,
        prepayAmount: prepayAmount ?? this.prepayAmount,
        prepayLink: prepayLink ?? this.prepayLink,
      );
}

/// Услуга мастера в облаке.
class CloudServiceItem {
  const CloudServiceItem({
    required this.id,
    required this.masterId,
    required this.name,
    required this.price,
    required this.durationMinutes,
    this.published = true,
    this.updatedAt,
  });

  final int id;
  final String masterId;
  final String name;
  final double price;
  final int durationMinutes;
  final bool published;
  final DateTime? updatedAt;

  factory CloudServiceItem.fromMap(Map<String, dynamic> map) =>
      CloudServiceItem(
        id: _parseInt(map['id']),
        masterId: _parseString(map['master_id']),
        name: _parseString(map['name']),
        price: _parseDouble(map['price']),
        durationMinutes: _parseInt(map['duration_minutes'], fallback: 60),
        published: _parseBool(map['published'], fallback: true),
        updatedAt: _parseDateTime(map['updated_at']),
      );

  CloudServiceItem copyWith({bool? published}) => CloudServiceItem(
        id: id,
        masterId: masterId,
        name: name,
        price: price,
        durationMinutes: durationMinutes,
        published: published ?? this.published,
      );
}

/// Запись/бронь клиент→мастер.
class CloudBooking {
  const CloudBooking({
    required this.id,
    required this.clientId,
    required this.masterId,
    this.serviceId,
    required this.serviceName,
    required this.startsAt,
    required this.durationMinutes,
    required this.status,
    required this.notes,
    this.clientName = '',
    this.clientPhone = '',
    this.masterName = '',
    this.masterAddress = '',
    this.servicePrice = 0,
    this.prepaymentStatus = 'none',
  });

  final int id;
  final String clientId;
  final String masterId;
  final int? serviceId;
  final String serviceName;
  final DateTime startsAt;
  final int durationMinutes;
  final String status; // pending | confirmed | cancelled | completed
  final String notes;
  final String clientName;
  final String clientPhone;
  final String masterName;

  /// Адрес мастера/салона из `master_profiles` (может быть пустым).
  final String masterAddress;

  /// Цена услуги на момент записи (снимок).
  final double servicePrice;

  /// 'none' | 'claimed' (клиент отметил оплату) | 'confirmed' (мастер подтвердил).
  final String prepaymentStatus;

  bool get isPast => startsAt.isBefore(DateTime.now());

  CloudBooking copyWith({
    int? id,
    String? clientId,
    String? masterId,
    int? serviceId,
    String? serviceName,
    DateTime? startsAt,
    int? durationMinutes,
    String? status,
    String? notes,
    String? clientName,
    String? clientPhone,
    String? masterName,
    String? masterAddress,
    double? servicePrice,
    String? prepaymentStatus,
  }) =>
      CloudBooking(
        id: id ?? this.id,
        clientId: clientId ?? this.clientId,
        masterId: masterId ?? this.masterId,
        serviceId: serviceId ?? this.serviceId,
        serviceName: serviceName ?? this.serviceName,
        startsAt: startsAt ?? this.startsAt,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        status: status ?? this.status,
        notes: notes ?? this.notes,
        clientName: clientName ?? this.clientName,
        clientPhone: clientPhone ?? this.clientPhone,
        masterName: masterName ?? this.masterName,
        masterAddress: masterAddress ?? this.masterAddress,
        servicePrice: servicePrice ?? this.servicePrice,
        prepaymentStatus: prepaymentStatus ?? this.prepaymentStatus,
      );

  factory CloudBooking.fromMap(Map<String, dynamic> map) {
    final client = _pickProfileMap(map['client']);
    final master = _pickProfileMap(map['master']);
    return CloudBooking(
      id: _parseInt(map['id']),
      clientId: _parseString(map['client_id']),
      masterId: _parseString(map['master_id']),
      serviceId: map['service_id'] == null ? null : _parseInt(map['service_id']),
      serviceName: _parseString(map['service_name']),
      startsAt: _parseDateTime(map['starts_at']) ?? DateTime.now(),
      durationMinutes: _parseInt(map['duration_minutes'], fallback: 60),
      status: _parseString(map['status'], fallback: 'pending'),
      notes: _parseString(map['notes']),
      clientName: client != null ? _parseString(client['name']) : '',
      clientPhone: client != null ? _parseString(client['phone']) : '',
      masterName: master != null ? _parseString(master['name']) : '',
      servicePrice: _parseDouble(map['service_price']),
      prepaymentStatus: _parseString(
        map['prepayment_status'],
        fallback: 'none',
      ),
    );
  }
}

/// Фото из портфолио мастера (работы, которые видят клиенты).
class PortfolioPhoto {
  const PortfolioPhoto({
    required this.id,
    required this.masterId,
    required this.imageUrl,
    this.sortOrder = 0,
    this.createdAt,
  });

  final int id;
  final String masterId;
  final String imageUrl;
  final int sortOrder;
  final DateTime? createdAt;

  factory PortfolioPhoto.fromMap(Map<String, dynamic> map) => PortfolioPhoto(
        id: _parseInt(map['id']),
        masterId: _parseString(map['master_id']),
        imageUrl: _parseString(map['image_url']),
        sortOrder: _parseInt(map['sort_order']),
        createdAt: _parseDateTime(map['created_at']),
      );
}

/// Отзыв мастера о клиенте (виден другим мастерам).
class ClientReview {
  const ClientReview({
    required this.id,
    required this.clientId,
    required this.masterId,
    required this.masterName,
    required this.bookingId,
    required this.rating,
    required this.comment,
    this.createdAt,
  });

  final int id;
  final String clientId;
  final String masterId;
  final String masterName;
  final int bookingId;
  final int rating;
  final String comment;
  final DateTime? createdAt;

  factory ClientReview.fromMap(Map<String, dynamic> map) {
    final profile = _pickProfileMap(map['profiles']);
    return ClientReview(
      id: _parseInt(map['id']),
      clientId: _parseString(map['client_id']),
      masterId: _parseString(map['master_id']),
      masterName: profile != null ? _parseString(profile['name']) : '',
      bookingId: _parseInt(map['booking_id']),
      rating: _parseInt(map['rating'], fallback: 0),
      comment: _parseString(map['comment']),
      createdAt: _parseDateTime(map['created_at']),
    );
  }
}

/// Облачный сервис: авторизация + данные.
class CloudService {
  // ---------- Auth ----------
  Session? get session => supabase.auth.currentSession;
  String? get uid => supabase.auth.currentUser?.id;
  String? get email => supabase.auth.currentUser?.email;
  Stream<AuthState> get authChanges => supabase.auth.onAuthStateChange;

  /// Логин для показа пользователю: из metadata, иначе вырезанный из
  /// технического email. Для старых аккаунтов — настоящий email.
  String get displayLogin {
    final meta = supabase.auth.currentUser?.userMetadata;
    final login = meta?['login'];
    if (login is String && login.isNotEmpty) return login;
    return emailToLogin(email ?? '');
  }

  /// Вход по логину (внутри — технический email). Сначала пробуем
  /// производный пароль [hardPassword]; если аккаунт старый и хранит
  /// «сырой» пароль — повторяем с исходным.
  Future<void> signIn(String login, String password) async {
    final email = loginToEmail(login);
    try {
      await supabase.auth.signInWithPassword(
        email: email,
        password: hardPassword(password),
      );
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      final wrongCreds = msg.contains('invalid') ||
          msg.contains('credential') ||
          msg.contains('wrong');
      if (!wrongCreds) rethrow;
      await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
    }
  }

  Future<void> signUp({
    required String login,
    required String password,
    required String role,
    String name = '',
    String phone = '',
    String salonKey = '',
  }) =>
      supabase.auth.signUp(
        email: loginToEmail(login),
        password: hardPassword(password),
        data: {
          'role': role,
          // Без имени показываем логин — имя задаётся позже в профиле.
          'name': name.isEmpty ? login.trim() : name,
          'phone': phone,
          'login': login.trim(),
          if (salonKey.isNotEmpty) 'salon_key': salonKey,
        },
      );

  Future<void> signOut() => supabase.auth.signOut();

  /// Удаляет облачный аккаунт (auth.users + связанные public-данные).
  Future<void> deleteMyAccount() async {
    await supabase.rpc('delete_my_account');
    await signOut();
  }

  // ---------- Profiles ----------
  Future<CloudProfile?> myProfile() async {
    final id = uid;
    if (id == null) return null;
    final row =
        await supabase.from('profiles').select().eq('id', id).maybeSingle();
    return row == null ? null : CloudProfile.fromMap(row);
  }

  Future<CloudProfile> ensureProfile({
    required String role,
    String name = '',
    String phone = '',
  }) async {
    final existing = await myProfile();
    if (existing != null) return existing;
    await supabase.from('profiles').insert({
      'id': uid,
      'role': role,
      'name': name,
      'phone': phone,
    });
    return (await myProfile())!;
  }

  Future<void> updateMyProfile({
    String? name,
    String? phone,
    String? avatarUrl,
    String? address,
    double? lat,
    double? lng,
    bool? phonePublic,
    bool clearLocation = false,
  }) =>
      _runWithMissingColumnFallback(<String, dynamic>{
        'name': ?name,
        'phone': ?phone,
        'avatar_url': ?avatarUrl,
        'address': ?address,
        'lat': ?lat,
        'lng': ?lng,
        'phone_public': ?phonePublic,
        if (clearLocation) ...{'lat': null, 'lng': null},
      }, (p) => supabase.from('profiles').update(p).eq('id', uid!));

  /// Обновляет логин и/или пароль текущего пользователя в Supabase Auth.
  /// [login] — то, что вводит пользователь; внутри превращается в email.
  Future<void> updateAuth({String? login, String? password}) async {
    final email = login == null || login.isEmpty ? null : loginToEmail(login);
    if (email == null && (password == null || password.isEmpty)) {
      return;
    }
    final res = await supabase.auth.updateUser(
      UserAttributes(
        email: email,
        password:
            password?.isNotEmpty == true ? hardPassword(password!) : null,
        // Дублируем логин в metadata — displayLogin читает его оттуда.
        data: login == null || login.isEmpty ? null : {'login': login.trim()},
      ),
    );
    if (res.user == null) {
      throw Exception('Не удалось обновить данные авторизации');
    }
  }

  // ---------- Categories ----------
  Future<List<String>> categories() async {
    try {
      final rows =
          await supabase.from('categories').select('name').order('name');
      final list = [for (final r in rows) r['name'] as String];
      if (list.isNotEmpty) return list;
    } catch (_) {}
    return const [
      'Массажист',
      'Маникюр',
      'Педикюр',
      'Парикмахер',
      'Бровист',
      'Косметолог',
      'Мастер по ресницам',
      'Другое',
    ];
  }

  // ---------- Master profiles ----------
  Future<List<MasterCard>> masters({String? category}) async {
    const fields = [
      'user_id',
      'category',
      'description',
      'address',
      'lat',
      'lng',
      'social',
      'phone_public',
      'avatar_url',
      'rating_avg',
      'rating_count',
      'prepay_enabled',
      'prepay_amount',
      'prepay_link',
      'salon_id',
      'salon_key',
      'auto_assign',
    ];
    try {
      final rows = await _selectResilient(
        'master_profiles',
        fields,
        eqColumn: category == null || category.isEmpty ? null : 'category',
        eqValue: category,
        orderBy: 'rating_avg',
      );

      // Одним запросом — все профили мастеров/салонов: и для имён
      // карточек, и чтобы провайдеры без карточки не терялись.
      final profileMap = <String, Map<String, dynamic>>{};
      try {
        final profiles = await _selectResilient(
          'profiles',
          const ['id', 'name', 'phone', 'role', 'created_at', 'phone_public'],
          inColumn: 'role',
          inValues: const ['master', 'salon'],
        );
        for (final p in profiles) {
          profileMap[_parseString(p['id'])] = p;
        }
      } catch (_) {
        // Профили не критичны — карточки всё равно отобразятся.
      }

      final result = <MasterCard>[
        for (final r in rows)
          MasterCard.fromMap(
            r,
            fallbackProfile: profileMap[_parseString(r['user_id'])],
          )
      ];

      // Провайдеры без карточки в master_profiles — показываем по профилю
      // (иначе они невидимы клиентам до первого сохранения анкеты).
      final known = result.map((c) => c.userId).toSet();
      for (final p in profileMap.values) {
        final pid = _parseString(p['id']);
        if (pid.isEmpty || known.contains(pid)) continue;
        if (category != null && category.isNotEmpty && category != 'Другое') {
          continue; // у безкарточных категория всегда «Другое»
        }
        result.add(MasterCard.fromMap(const {}, fallbackProfile: p));
      }
      return result;
    } catch (e, st) {
      await SyncLog.write('masters', 'unexpected error: $e\n$st');
      rethrow;
    }
  }

  Future<MasterCard?> masterCard(String masterId) async {
    const fields = [
      'user_id',
      'category',
      'description',
      'address',
      'lat',
      'lng',
      'social',
      'phone_public',
      'avatar_url',
      'rating_avg',
      'rating_count',
      'prepay_enabled',
      'prepay_amount',
      'prepay_link',
      'salon_id',
      'salon_key',
      'auto_assign',
    ];
    final rows = await _selectResilient(
      'master_profiles',
      fields,
      eqColumn: 'user_id',
      eqValue: masterId,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;

    Map<String, dynamic>? profile;
    try {
      final p = await _selectResilient(
        'profiles',
        const ['id', 'name', 'phone', 'role', 'created_at', 'phone_public'],
        eqColumn: 'id',
        eqValue: masterId,
      );
      if (p.isNotEmpty) profile = p.first as Map<String, dynamic>;
    } catch (_) {}

    return MasterCard.fromMap(
      row as Map<String, dynamic>,
      fallbackProfile: profile,
    );
  }

  Future<MasterCard?> myMasterCard() async {
    final id = uid;
    if (id == null) return null;
    return masterCard(id);
  }

  /// Создаёт пустую карточку мастера/салона, если её ещё нет —
  /// чтобы аккаунт сразу был виден клиентам в каталоге.
  /// Мастеру с ключом салона в metadata сразу ставит привязку.
  Future<void> ensureMasterCard() async {
    if (uid == null) return;
    if (await myMasterCard() == null) {
      await upsertMasterProfile(category: 'Другое', description: '');
      final meta = supabase.auth.currentUser?.userMetadata ?? const {};
      if (meta['role'] == 'master') {
        try {
          await _applySalonKeyIfAny();
        } catch (e, st) {
          await SyncLog.write('salon_key_apply', '$e\n$st');
        }
      }
    }
  }

  Future<void> upsertMasterProfile({
    required String category,
    required String description,
    String address = '',
    double? lat,
    double? lng,
    String social = '',
    bool phonePublic = false,
    String avatarUrl = '',
    bool prepayEnabled = false,
    double prepayAmount = 0,
    String prepayLink = '',
  }) async {
    final payload = <String, dynamic>{
      'user_id': uid,
      'category': category,
      'description': description,
      'address': address,
      'lat': ?lat,
      'lng': ?lng,
      'social': social,
      'phone_public': phonePublic,
      'avatar_url': avatarUrl,
      'prepay_enabled': prepayEnabled,
      'prepay_amount': prepayAmount,
      'prepay_link': prepayLink,
    };
    // Старая база без свежих миграций — сохраняем без отсутствующих полей.
    await _runWithMissingColumnFallback(
        payload, (p) => supabase.from('master_profiles').upsert(p));
  }

  Future<void> updateAvatarUrl(String url) =>
      supabase.from('master_profiles').update({'avatar_url': url}).eq('user_id', uid as Object);

  /// Загружает файл в публичный bucket `avatars/<user_id>/avatar.jpg`.
  /// Возвращает публичный URL.
  Future<String> uploadAvatar(String filePath) async {
    final userId = uid;
    if (userId == null) throw Exception('Не авторизован');
    final dest = '$userId/avatar.jpg';
    await supabase.storage.from('avatars').upload(
          dest,
          File(filePath),
          fileOptions: const FileOptions(upsert: true),
        );
    return supabase.storage.from('avatars').getPublicUrl(dest);
  }

  // ---------- Services (cloud) ----------
  /// Все услуги мастера (для редактирования).
  Future<List<CloudServiceItem>> myServices() async {
    final rows = await supabase
        .from('services')
        .select()
        .eq('master_id', uid!)
        .order('name');
    return [for (final r in rows) CloudServiceItem.fromMap(r)];
  }

  /// Услуги мастера (видны клиентам после фильтрации по published).
  Future<List<CloudServiceItem>> servicesOf(String masterId) async {
    final rows = await supabase
        .from('services')
        .select()
        .eq('master_id', masterId)
        .order('name');
    return [for (final r in rows) CloudServiceItem.fromMap(r)];
  }

  Future<CloudServiceItem> addService({
    required String name,
    required double price,
    required int durationMinutes,
    bool published = true,
  }) async {
    final payload = <String, dynamic>{
      'master_id': uid,
      'name': name,
      'price': price,
      'duration_minutes': durationMinutes,
      'published': published,
    };
    try {
      final row = await supabase
          .from('services')
          .insert(payload)
          .select()
          .single();
      return CloudServiceItem.fromMap(row);
    } on PostgrestException catch (e) {
      if (!_isMissingColumn(e, 'published')) rethrow;
      final row = await supabase
          .from('services')
          .insert(payload..remove('published'))
          .select()
          .single();
      return CloudServiceItem.fromMap(row);
    }
  }

  Future<CloudServiceItem> updateService(CloudServiceItem s) async {
    final payload = <String, dynamic>{
      'name': s.name,
      'price': s.price,
      'duration_minutes': s.durationMinutes,
      'published': s.published,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      final row = await supabase
          .from('services')
          .update(payload)
          .eq('id', s.id)
          .select()
          .single();
      return CloudServiceItem.fromMap(row);
    } on PostgrestException catch (e) {
      if (!_isMissingColumn(e, 'published')) rethrow;
      final row = await supabase
          .from('services')
          .update(payload..remove('published'))
          .eq('id', s.id)
          .select()
          .single();
      return CloudServiceItem.fromMap(row);
    }
  }

  Future<void> deleteService(int id) =>
      supabase.from('services').delete().eq('id', id);

  // ---------- Портфолио мастера ----------
  /// Фото работ текущего мастера.
  Future<List<PortfolioPhoto>> myPortfolio() async {
    final rows = await supabase
        .from('master_portfolio')
        .select()
        .eq('master_id', uid!)
        .order('sort_order')
        .order('created_at');
    return [for (final r in rows) PortfolioPhoto.fromMap(r)];
  }

  /// Фото работ мастера для клиентского просмотра.
  Future<List<PortfolioPhoto>> portfolioOf(String masterId) async {
    final rows = await supabase
        .from('master_portfolio')
        .select()
        .eq('master_id', masterId)
        .order('sort_order')
        .order('created_at');
    return [for (final r in rows) PortfolioPhoto.fromMap(r)];
  }

  /// Загружает фото работы в bucket `avatars/<uid>/portfolio/…`
  /// (политики bucket уже разрешают владельцу писать в свою папку)
  /// и создаёт запись в master_portfolio.
  Future<PortfolioPhoto> uploadPortfolioPhoto(String filePath) async {
    final userId = uid;
    if (userId == null) throw Exception('Не авторизован');
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final dest = '$userId/portfolio/$fileName';
    await supabase.storage
        .from('avatars')
        .upload(dest, File(filePath));
    final url = supabase.storage.from('avatars').getPublicUrl(dest);
    final row = await supabase
        .from('master_portfolio')
        .insert({'master_id': userId, 'image_url': url})
        .select()
        .single();
    return PortfolioPhoto.fromMap(row);
  }

  /// Удаляет фото: запись в таблице + файл в storage (по URL).
  Future<void> deletePortfolioPhoto(PortfolioPhoto photo) async {
    await supabase
        .from('master_portfolio')
        .delete()
        .eq('id', photo.id);
    final marker = '/storage/v1/object/public/avatars/';
    final idx = photo.imageUrl.indexOf(marker);
    if (idx >= 0) {
      final path = photo.imageUrl.substring(idx + marker.length);
      try {
        await supabase.storage.from('avatars').remove([path]);
      } catch (_) {
        // Файл мог быть удалён ранее — записи уже нет.
      }
    }
  }

  /// Полностью перезаписывает список услуг мастера в облаке
  /// (простой способ синхронизации локального справочника).
  Future<void> replaceMyServices(
    List<({String name, double price, int durationMinutes, bool published})>
        items,
  ) async {
    final id = uid;
    if (id == null) return;
    await supabase.from('services').delete().eq('master_id', id);
    if (items.isEmpty) return;
    await supabase.from('services').insert([
      for (final s in items)
        {
          'master_id': id,
          'name': s.name,
          'price': s.price,
          'duration_minutes': s.durationMinutes,
          'published': s.published,
        },
    ]);
  }

  // ---------- Appointments ----------
  Future<CloudBooking> bookAppointment({
    required String masterId,
    int? serviceId,
    required String serviceName,
    required DateTime startsAt,
    required int durationMinutes,
    double servicePrice = 0,
    String notes = '',
    String prepaymentStatus = 'none',
  }) async {
    final payload = <String, dynamic>{
      'client_id': uid,
      'master_id': masterId,
      'service_id': serviceId,
      'service_name': serviceName,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'duration_minutes': durationMinutes,
      'service_price': servicePrice,
      'prepayment_status': prepaymentStatus,
      'notes': notes,
    };
    // Повторяем вставку, убирая колонки, которых нет в старой базе.
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final row = await supabase
            .from('appointments')
            .insert(payload)
            .select()
            .single();
        return CloudBooking.fromMap(row);
      } on PostgrestException catch (e) {
        if (_isMissingColumn(e, 'service_price') &&
            payload.containsKey('service_price')) {
          payload.remove('service_price');
          continue;
        }
        if (_isMissingColumn(e, 'prepayment_status') &&
            payload.containsKey('prepayment_status')) {
          payload.remove('prepayment_status');
          continue;
        }
        rethrow;
      }
    }
    throw Exception('Не удалось создать запись');
  }

  /// Записи текущего пользователя как клиента.
  Future<List<CloudBooking>> clientBookings() async {
    final rows = await supabase
        .from('appointments')
        .select('*, master:profiles!appointments_master_id_fkey(name)')
        .eq('client_id', uid!)
        .order('starts_at', ascending: false);
    final bookings = [for (final r in rows) CloudBooking.fromMap(r)];

    // Подтягиваем адреса мастеров из master_profiles отдельным запросом —
    // appointments.master_id ссылается на profiles, а не на master_profiles.
    final masterIds =
        bookings.map((b) => b.masterId).where((id) => id.isNotEmpty).toSet();
    if (masterIds.isNotEmpty) {
      try {
        final mpRows = await supabase
            .from('master_profiles')
            .select('user_id, address, phone_public')
            .inFilter('user_id', masterIds.toList());
        final addr = <String, String>{};
        for (final r in mpRows) {
          addr[_parseString(r['user_id'])] = _parseString(r['address']);
        }
        return [
          for (final b in bookings)
            b.copyWith(masterAddress: addr[b.masterId] ?? ''),
        ];
      } catch (_) {
        // Адрес не критичен — вернём записи без него.
      }
    }
    return bookings;
  }

  /// Записи текущего пользователя как мастера.
  Future<List<CloudBooking>> masterBookings() async {
    final rows = await supabase
        .from('appointments')
        .select('*, client:profiles!appointments_client_id_fkey(name, phone), master:profiles!appointments_master_id_fkey(name)')
        .eq('master_id', uid!)
        .order('starts_at');
    return [for (final r in rows) CloudBooking.fromMap(r)];
  }

  /// Записи конкретного мастера за конкретный день.
  /// Используется клиентом при выборе свободных часов.
  Future<List<CloudBooking>> masterBookingsForDay(
    String masterId,
    DateTime day,
  ) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final rows = await supabase
        .from('appointments')
        .select('*, client:profiles!appointments_client_id_fkey(name, phone), master:profiles!appointments_master_id_fkey(name)')
        .eq('master_id', masterId)
        .gte('starts_at', start.toUtc().toIso8601String())
        .lt('starts_at', end.toUtc().toIso8601String())
        .neq('status', 'cancelled')
        .order('starts_at');
    return [for (final r in rows) CloudBooking.fromMap(r)];
  }

  Future<void> setBookingStatus(int id, String status) =>
      supabase.from('appointments').update({'status': status}).eq('id', id);

  /// Мастер подтверждает получение предоплаты по записи.
  Future<void> setPrepaymentStatus(int id, String status) => supabase
      .from('appointments')
      .update({'prepayment_status': status}).eq('id', id);

  // ---------- Favorites (избранные мастера/салоны клиента) ----------

  /// id мастеров/салонов, которых клиент добавил в избранное.
  Future<Set<String>> myFavoriteIds() async {
    final rows = await supabase
        .from('favorites')
        .select('master_id')
        .eq('client_id', uid!);
    return {for (final r in rows) _parseString(r['master_id'])};
  }

  /// Карточки избранных мастеров/салонов.
  Future<List<MasterCard>> favoriteMasters() async {
    final ids = await myFavoriteIds();
    if (ids.isEmpty) return [];
    final rows = await _selectResilient(
      'master_profiles',
      const [
        'user_id',
        'category',
        'description',
        'address',
        'lat',
        'lng',
        'social',
        'phone_public',
        'avatar_url',
        'rating_avg',
        'rating_count',
        'prepay_enabled',
        'prepay_amount',
        'prepay_link',
        'salon_id',
        'salon_key',
        'auto_assign',
      ],
      inColumn: 'user_id',
      inValues: ids.toList(),
    );
    final profileRows = await _selectResilient(
      'profiles',
      const ['id', 'name', 'phone', 'role', 'created_at', 'phone_public'],
      inColumn: 'id',
      inValues: ids.toList(),
    );
    final profileMap = <String, Map<String, dynamic>>{
      for (final p in profileRows) _parseString(p['id']): p,
    };
    final result = [
      for (final r in rows)
        MasterCard.fromMap(
          r,
          fallbackProfile: profileMap[_parseString(r['user_id'])],
        ),
    ];
    // Избранное не должно теряться: если у мастера/салона ещё нет
    // карточки в master_profiles — показываем профиль как есть.
    final found = result.map((c) => c.userId).toSet();
    for (final id in ids) {
      final p = profileMap[id];
      if (!found.contains(id) && p != null) {
        result.add(MasterCard.fromMap(const {}, fallbackProfile: p));
      }
    }
    return result;
  }

  Future<bool> isFavorite(String masterId) async {
    final row = await supabase
        .from('favorites')
        .select('id')
        .eq('client_id', uid!)
        .eq('master_id', masterId)
        .maybeSingle();
    return row != null;
  }

  /// Добавить/убрать из избранного. Возвращает новое состояние.
  Future<bool> toggleFavorite(String masterId) async {
    if (await isFavorite(masterId)) {
      await supabase
          .from('favorites')
          .delete()
          .eq('client_id', uid!)
          .eq('master_id', masterId);
      return false;
    }
    try {
      await supabase
          .from('favorites')
          .insert({'client_id': uid, 'master_id': masterId});
    } on PostgrestException catch (e) {
      // 23505 — уже есть в избранном: считаем успехом.
      if (e.code == '23505') return true;
      // 23503 — нет своей строки в profiles (старый аккаунт,
      // регистрация до триггера): создаём профиль и повторяем.
      if (e.code != '23503') rethrow;
      final meta = supabase.auth.currentUser?.userMetadata ?? const {};
      await ensureProfile(
        role: meta['role'] as String? ?? 'client',
        name: meta['name'] as String? ?? '',
        phone: meta['phone'] as String? ?? '',
      );
      await supabase
          .from('favorites')
          .insert({'client_id': uid, 'master_id': masterId});
    }
    return true;
  }

  // ---------- Ratings ----------
  Future<void> rateBooking({
    required int appointmentId,
    required String masterId,
    required int rating,
    String comment = '',
  }) =>
      supabase.from('ratings').insert({
        'appointment_id': appointmentId,
        'client_id': uid,
        'master_id': masterId,
        'rating': rating,
        'comment': comment,
      });

  Future<int?> ratingFor(int appointmentId) async {
    final row = await supabase
        .from('ratings')
        .select('rating')
        .eq('appointment_id', appointmentId)
        .maybeSingle();
    return (row?['rating'] as num?)?.toInt();
  }

  // ---------- Client reviews (master -> client) ----------
  Future<List<ClientReview>> clientReviews(String clientId) async {
    final rows = await supabase
        .from('client_reviews')
        .select(
            'id, client_id, master_id, booking_id, rating, comment, created_at, profiles!client_reviews_master_id_fkey(name)')
        .eq('client_id', clientId)
        .order('created_at', ascending: false);
    return [for (final r in rows) ClientReview.fromMap(r)];
  }

  Future<List<ClientReview>> myClientReviews() async {
    final id = uid;
    if (id == null) return [];
    final rows = await supabase
        .from('client_reviews')
        .select(
            'id, client_id, master_id, booking_id, rating, comment, created_at')
        .eq('master_id', id)
        .order('created_at', ascending: false);
    return [for (final r in rows) ClientReview.fromMap(r)];
  }

  Future<ClientReview> addClientReview({
    required String clientId,
    required int bookingId,
    required int rating,
    String comment = '',
  }) async {
    final row = await supabase
        .from('client_reviews')
        .insert({
          'client_id': clientId,
          'master_id': uid,
          'booking_id': bookingId,
          'rating': rating,
          'comment': comment,
        })
        .select(
            'id, client_id, master_id, booking_id, rating, comment, created_at')
        .single();
    return ClientReview.fromMap(row);
  }

  // ---------- Master clients ----------
  Future<List<CloudClient>> myClients() async {
    final rows = await supabase
        .from('master_clients')
        .select()
        .eq('master_id', uid!)
        .order('name');
    return [for (final r in rows) CloudClient.fromMap(r)];
  }

  Future<CloudClient> addClient({
    required String name,
    required String phone,
  }) async {
    final row = await supabase
        .from('master_clients')
        .insert({
          'master_id': uid,
          'name': name,
          'phone': phone,
        })
        .select()
        .single();
    return CloudClient.fromMap(row);
  }

  Future<CloudClient> updateClient(CloudClient c) async {
    final row = await supabase
        .from('master_clients')
        .update({
          'name': c.name,
          'phone': c.phone,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', c.id)
        .select()
        .single();
    return CloudClient.fromMap(row);
  }

  Future<void> deleteClient(int id) =>
      supabase.from('master_clients').delete().eq('id', id);

  // ---------- Master appointments ----------
  Future<List<CloudMasterAppointment>> myMasterAppointments() async {
    final rows = await supabase
        .from('master_appointments')
        .select()
        .eq('master_id', uid!)
        .order('starts_at');
    return [for (final r in rows) CloudMasterAppointment.fromMap(r)];
  }

  Future<CloudMasterAppointment> addMasterAppointment({
    required String clientName,
    required String clientPhone,
    required String serviceName,
    required String masterName,
    required DateTime startsAt,
    required int durationMinutes,
    double servicePrice = 0,
    String notes = '',
  }) async {
    final payload = <String, dynamic>{
      'master_id': uid,
      'client_name': clientName,
      'client_phone': clientPhone,
      'service_name': serviceName,
      'master_name': masterName,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'duration_minutes': durationMinutes,
      'service_price': servicePrice,
      'notes': notes,
    };
    try {
      final row = await supabase
          .from('master_appointments')
          .insert(payload)
          .select()
          .single();
      return CloudMasterAppointment.fromMap(row);
    } on PostgrestException catch (e) {
      if (!_isMissingColumn(e, 'service_price')) rethrow;
      final row = await supabase
          .from('master_appointments')
          .insert(payload..remove('service_price'))
          .select()
          .single();
      return CloudMasterAppointment.fromMap(row);
    }
  }

  Future<CloudMasterAppointment> updateMasterAppointment(
    CloudMasterAppointment a,
  ) async {
    final payload = <String, dynamic>{
      'client_name': a.clientName,
      'client_phone': a.clientPhone,
      'service_name': a.serviceName,
      'master_name': a.masterName,
      'starts_at': a.startsAt.toUtc().toIso8601String(),
      'duration_minutes': a.durationMinutes,
      'service_price': a.servicePrice,
      'notes': a.notes,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      final row = await supabase
          .from('master_appointments')
          .update(payload)
          .eq('id', a.id)
          .select()
          .single();
      return CloudMasterAppointment.fromMap(row);
    } on PostgrestException catch (e) {
      if (!_isMissingColumn(e, 'service_price')) rethrow;
      final row = await supabase
          .from('master_appointments')
          .update(payload..remove('service_price'))
          .eq('id', a.id)
          .select()
          .single();
      return CloudMasterAppointment.fromMap(row);
    }
  }

  Future<void> deleteMasterAppointment(int id) =>
      supabase.from('master_appointments').delete().eq('id', id);

  // ---------- Salon team (мастера салона) ----------

  /// Профиль любого пользователя по id — для «Информации» о клиенте.
  Future<CloudProfile?> profileById(String id) async {
    final rows = await _selectResilient(
      'profiles',
      const [
        'id',
        'name',
        'phone',
        'role',
        'created_at',
        'phone_public',
        'avatar_url'
      ],
      eqColumn: 'id',
      eqValue: id,
    );
    if (rows.isEmpty) return null;
    return CloudProfile.fromMap(rows.first as Map<String, dynamic>);
  }

  /// Мастера, привязанные к моему салону (master_profiles.salon_id = я).
  Future<List<MasterCard>> salonMasters() async {
    final rows = await _selectResilient(
      'master_profiles',
      const [
        'user_id',
        'category',
        'description',
        'address',
        'lat',
        'lng',
        'social',
        'phone_public',
        'avatar_url',
        'rating_avg',
        'rating_count',
        'prepay_enabled',
        'prepay_amount',
        'prepay_link',
        'salon_id',
        'salon_key',
        'auto_assign',
      ],
      eqColumn: 'salon_id',
      eqValue: uid!,
    );
    if (rows.isEmpty) return [];
    final ids = [for (final r in rows) _parseString(r['user_id'])];
    final profileRows = await _selectResilient(
      'profiles',
      const ['id', 'name', 'phone', 'role', 'created_at', 'phone_public'],
      inColumn: 'id',
      inValues: ids,
    );
    final profileMap = <String, Map<String, dynamic>>{
      for (final p in profileRows) _parseString(p['id']): p,
    };
    return [
      for (final r in rows)
        MasterCard.fromMap(
          r as Map<String, dynamic>,
          fallbackProfile: profileMap[_parseString(r['user_id'])],
        ),
    ];
  }

  /// Уникальный ключ салона: возвращает существующий или генерирует.
  /// Мастера вводят его при регистрации, чтобы привязаться к салону.
  Future<String> ensureSalonKey() async {
    await ensureMasterCard();
    final card = await myMasterCard();
    if (card != null && card.salonKey.isNotEmpty) return card.salonKey;
    final key =
        'BZ-${uid!.replaceAll('-', '').substring(0, 6).toUpperCase()}';
    await supabase
        .from('master_profiles')
        .update({'salon_key': key}).eq('user_id', uid!);
    return key;
  }

  /// Привязка мастера к салону по ключу из metadata регистрации.
  /// Вызывается при создании карточки мастера.
  Future<void> _applySalonKeyIfAny() async {
    final meta = supabase.auth.currentUser?.userMetadata ?? const {};
    final key = meta['salon_key'];
    if (key is! String || key.trim().isEmpty) return;
    final rows = await supabase
        .from('master_profiles')
        .select('user_id')
        .eq('salon_key', key.trim())
        .neq('user_id', uid!);
    if (rows.isEmpty) return;
    await supabase
        .from('master_profiles')
        .update({'salon_id': rows.first['user_id']})
        .eq('user_id', uid!);
  }

  /// Салон: открепить мастера (он становится самозанятым).
  Future<void> detachMaster(String masterId) => supabase
      .from('master_profiles')
      .update({'salon_id': null}).eq('user_id', masterId);

  /// Салон: создать аккаунт мастера, не выходя из своей сессии —
  /// регистрация идёт через отдельный SupabaseClient.
  /// Возвращает null при успехе или текст ошибки.
  Future<String?> createMasterAccount({
    required String login,
    required String password,
    required String name,
    required String phone,
  }) async {
    final key = await ensureSalonKey();
    final temp = SupabaseClient(supabaseUrl, supabasePublishableKey);
    try {
      await temp.auth.signUp(
        email: loginToEmail(login),
        password: hardPassword(password),
        data: {
          'role': 'master',
          'name': name,
          'phone': phone,
          'login': login.trim(),
          'salon_key': key,
        },
      );
      return null;
    } on AuthException catch (e) {
      return e.message;
    } finally {
      await temp.dispose();
    }
  }

  /// Салон: переключатель автоназначения заявок на мастеров.
  Future<void> setAutoAssign(bool value) => supabase
      .from('master_profiles')
      .update({'auto_assign': value}).eq('user_id', uid!);

  /// Салон: назначить заявку конкретному мастеру.
  Future<void> assignBooking(int bookingId, String masterId) => supabase
      .from('appointments')
      .update({'master_id': masterId}).eq('id', bookingId);

  /// Заявки салона: свои + все записи своих мастеров.
  Future<List<CloudBooking>> salonBookings() async {
    final team = <String>{uid!};
    for (final m in await salonMasters()) {
      if (m.userId.isNotEmpty) team.add(m.userId);
    }
    final rows = await supabase
        .from('appointments')
        .select(
            '*, client:profiles!appointments_client_id_fkey(name, phone)')
        .inFilter('master_id', team.toList())
        .order('starts_at');
    return [for (final r in rows) CloudBooking.fromMap(r)];
  }

  /// Автоназначение: мастер салона с наименьшим числом записей
  /// на выбранную дату — через RPC pick_salon_master (security
  /// definer, клиенту не нужны права на чужие записи).
  /// Возвращает null, если мастеров нет или функция не задеплоена.
  Future<String?> pickSalonMaster(String salonId, DateTime day) async {
    final res = await supabase.rpc(
      'pick_salon_master',
      params: {
        'p_salon': salonId,
        'p_day':
            '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
      },
    );
    return res == null ? null : _parseString(res);
  }
}

/// Клиент мастера в облаке.
class CloudClient {
  const CloudClient({
    required this.id,
    required this.masterId,
    required this.name,
    required this.phone,
    this.updatedAt,
  });

  final int id;
  final String masterId;
  final String name;
  final String phone;
  final DateTime? updatedAt;

  factory CloudClient.fromMap(Map<String, dynamic> map) => CloudClient(
        id: _parseInt(map['id']),
        masterId: _parseString(map['master_id']),
        name: _parseString(map['name']),
        phone: _parseString(map['phone']),
        updatedAt: _parseDateTime(map['updated_at']),
      );
}

/// Запись, созданная мастером самостоятельно (не клиентская заявка).
class CloudMasterAppointment {
  const CloudMasterAppointment({
    required this.id,
    required this.masterId,
    required this.clientName,
    required this.clientPhone,
    required this.serviceName,
    required this.masterName,
    required this.startsAt,
    required this.durationMinutes,
    this.servicePrice = 0,
    this.notes = '',
    this.updatedAt,
  });

  final int id;
  final String masterId;
  final String clientName;
  final String clientPhone;
  final String serviceName;
  final String masterName;
  final DateTime startsAt;
  final int durationMinutes;

  /// Цена услуги на момент записи (снимок).
  final double servicePrice;
  final String notes;
  final DateTime? updatedAt;

  factory CloudMasterAppointment.fromMap(Map<String, dynamic> map) =>
      CloudMasterAppointment(
        id: _parseInt(map['id']),
        masterId: _parseString(map['master_id']),
        clientName: _parseString(map['client_name']),
        clientPhone: _parseString(map['client_phone']),
        serviceName: _parseString(map['service_name']),
        masterName: _parseString(map['master_name']),
        startsAt: _parseDateTime(map['starts_at']) ?? DateTime.now(),
        durationMinutes: _parseInt(map['duration_minutes'], fallback: 60),
        servicePrice: _parseDouble(map['service_price']),
        notes: _parseString(map['notes']),
        updatedAt: _parseDateTime(map['updated_at']),
      );
}
