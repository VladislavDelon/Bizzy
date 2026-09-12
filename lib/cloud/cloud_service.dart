import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Точка доступа к Supabase-клиенту.
SupabaseClient get supabase => Supabase.instance.client;

/// true, если Supabase инициализирован и есть активная сессия.
/// Безопасно вызывать и в режиме без облака (тесты/локальный вход).
bool get cloudSignedIn =>
    Supabase.instance.isInitialized &&
    Supabase.instance.client.auth.currentUser != null;

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
  });

  final String id;
  final String role; // 'client' | 'master'
  final String name;
  final String phone;

  bool get isMaster => role == 'master';
  bool get isClient => role == 'client';

  factory CloudProfile.fromMap(Map<String, dynamic> map) => CloudProfile(
        id: _parseString(map['id']),
        role: _parseString(map['role'], fallback: 'client'),
        name: _parseString(map['name']),
        phone: _parseString(map['phone']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'role': role,
        'name': name,
        'phone': phone,
      };
}

/// Профиль мастера + имя из `profiles`.
class MasterCard {
  const MasterCard({
    required this.userId,
    required this.name,
    required this.category,
    required this.description,
    required this.avatarUrl,
    required this.ratingAvg,
    required this.ratingCount,
  });

  final String userId;
  final String name;
  final String category;
  final String description;
  final String avatarUrl;
  final double ratingAvg;
  final int ratingCount;

  factory MasterCard.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'];
    return MasterCard(
      userId: _parseString(map['user_id']),
      name: profile is Map ? _parseString(profile['name']) : '',
      category: _parseString(map['category'], fallback: 'Другое'),
      description: _parseString(map['description']),
      avatarUrl: _parseString(map['avatar_url']),
      ratingAvg: _parseDouble(map['rating_avg']),
      ratingCount: _parseInt(map['rating_count']),
    );
  }
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
      );

  factory CloudBooking.fromMap(Map<String, dynamic> map) {
    final client = map['client'];
    final master = map['master'];
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
      clientName: client is Map ? _parseString(client['name']) : '',
      clientPhone: client is Map ? _parseString(client['phone']) : '',
      masterName: master is Map ? _parseString(master['name']) : '',
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

  Future<void> signIn(String email, String password) =>
      supabase.auth.signInWithPassword(email: email, password: password);

  Future<void> signUp({
    required String email,
    required String password,
    required String role,
    required String name,
    required String phone,
  }) =>
      supabase.auth.signUp(
        email: email,
        password: password,
        data: {'role': role, 'name': name, 'phone': phone},
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

  Future<void> updateMyProfile({String? name, String? phone}) =>
      supabase.from('profiles').update({
        'name': ?name,
        'phone': ?phone,
      }).eq('id', uid!);

  // ---------- Categories ----------
  Future<List<String>> categories() async {
    final rows =
        await supabase.from('categories').select('name').order('name');
    return [for (final r in rows) r['name'] as String];
  }

  // ---------- Master profiles ----------
  Future<List<MasterCard>> masters({String? category}) async {
    var query = supabase.from('master_profiles').select(
        'user_id, category, description, avatar_url, rating_avg, rating_count, profiles!inner(name)');
    if (category != null && category.isNotEmpty) {
      query = query.eq('category', category);
    }
    final rows = await query.order('rating_avg', ascending: false);
    return [for (final r in rows) MasterCard.fromMap(r)];
  }

  Future<MasterCard?> masterCard(String masterId) async {
    final row = await supabase
        .from('master_profiles')
        .select(
            'user_id, category, description, avatar_url, rating_avg, rating_count, profiles!inner(name)')
        .eq('user_id', masterId)
        .maybeSingle();
    return row == null ? null : MasterCard.fromMap(row);
  }

  Future<MasterCard?> myMasterCard() async {
    final id = uid;
    if (id == null) return null;
    return masterCard(id);
  }

  Future<void> upsertMasterProfile({
    required String category,
    required String description,
    String avatarUrl = '',
  }) =>
      supabase.from('master_profiles').upsert({
        'user_id': uid,
        'category': category,
        'description': description,
        'avatar_url': avatarUrl,
      });

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

  /// Опубликованные услуги мастера (видны клиентам).
  Future<List<CloudServiceItem>> servicesOf(String masterId) async {
    final rows = await supabase
        .from('services')
        .select()
        .eq('master_id', masterId)
        .eq('published', true)
        .order('name');
    return [for (final r in rows) CloudServiceItem.fromMap(r)];
  }

  Future<CloudServiceItem> addService({
    required String name,
    required double price,
    required int durationMinutes,
    bool published = true,
  }) async {
    final row = await supabase
        .from('services')
        .insert({
          'master_id': uid,
          'name': name,
          'price': price,
          'duration_minutes': durationMinutes,
          'published': published,
        })
        .select()
        .single();
    return CloudServiceItem.fromMap(row);
  }

  Future<CloudServiceItem> updateService(CloudServiceItem s) async {
    final row = await supabase
        .from('services')
        .update({
          'name': s.name,
          'price': s.price,
          'duration_minutes': s.durationMinutes,
          'published': s.published,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', s.id)
        .select()
        .single();
    return CloudServiceItem.fromMap(row);
  }

  Future<void> deleteService(int id) =>
      supabase.from('services').delete().eq('id', id);

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
    String notes = '',
  }) async {
    final row = await supabase
        .from('appointments')
        .insert({
          'client_id': uid,
          'master_id': masterId,
          'service_id': serviceId,
          'service_name': serviceName,
          'starts_at': startsAt.toUtc().toIso8601String(),
          'duration_minutes': durationMinutes,
          'notes': notes,
        })
        .select()
        .single();
    return CloudBooking.fromMap(row);
  }

  /// Записи текущего пользователя как клиента.
  Future<List<CloudBooking>> clientBookings() async {
    final rows = await supabase
        .from('appointments')
        .select('*, master:profiles!appointments_master_id_fkey(name)')
        .eq('client_id', uid!)
        .order('starts_at', ascending: false);
    return [for (final r in rows) CloudBooking.fromMap(r)];
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
    String notes = '',
  }) async {
    final row = await supabase
        .from('master_appointments')
        .insert({
          'master_id': uid,
          'client_name': clientName,
          'client_phone': clientPhone,
          'service_name': serviceName,
          'master_name': masterName,
          'starts_at': startsAt.toUtc().toIso8601String(),
          'duration_minutes': durationMinutes,
          'notes': notes,
        })
        .select()
        .single();
    return CloudMasterAppointment.fromMap(row);
  }

  Future<CloudMasterAppointment> updateMasterAppointment(
    CloudMasterAppointment a,
  ) async {
    final row = await supabase
        .from('master_appointments')
        .update({
          'client_name': a.clientName,
          'client_phone': a.clientPhone,
          'service_name': a.serviceName,
          'master_name': a.masterName,
          'starts_at': a.startsAt.toUtc().toIso8601String(),
          'duration_minutes': a.durationMinutes,
          'notes': a.notes,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', a.id)
        .select()
        .single();
    return CloudMasterAppointment.fromMap(row);
  }

  Future<void> deleteMasterAppointment(int id) =>
      supabase.from('master_appointments').delete().eq('id', id);
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
        notes: _parseString(map['notes']),
        updatedAt: _parseDateTime(map['updated_at']),
      );
}
