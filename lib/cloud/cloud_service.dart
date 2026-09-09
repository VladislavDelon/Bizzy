import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Точка доступа к Supabase-клиенту.
SupabaseClient get supabase => Supabase.instance.client;

/// true, если Supabase инициализирован и есть активная сессия.
/// Безопасно вызывать и в режиме без облака (тесты/локальный вход).
bool get cloudSignedIn =>
    Supabase.instance.isInitialized &&
    Supabase.instance.client.auth.currentUser != null;

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
        id: map['id'] as String,
        role: map['role'] as String? ?? 'client',
        name: map['name'] as String? ?? '',
        phone: map['phone'] as String? ?? '',
      );
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
      userId: map['user_id'] as String,
      name: profile is Map ? (profile['name'] as String? ?? '') : '',
      category: map['category'] as String? ?? 'Другое',
      description: map['description'] as String? ?? '',
      avatarUrl: map['avatar_url'] as String? ?? '',
      ratingAvg: (map['rating_avg'] as num?)?.toDouble() ?? 0,
      ratingCount: (map['rating_count'] as num?)?.toInt() ?? 0,
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
  });

  final int id;
  final String masterId;
  final String name;
  final double price;
  final int durationMinutes;

  factory CloudServiceItem.fromMap(Map<String, dynamic> map) =>
      CloudServiceItem(
        id: (map['id'] as num).toInt(),
        masterId: map['master_id'] as String,
        name: map['name'] as String? ?? '',
        price: (map['price'] as num?)?.toDouble() ?? 0,
        durationMinutes: (map['duration_minutes'] as num?)?.toInt() ?? 60,
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
      id: (map['id'] as num).toInt(),
      clientId: map['client_id'] as String,
      masterId: map['master_id'] as String,
      serviceId: (map['service_id'] as num?)?.toInt(),
      serviceName: map['service_name'] as String? ?? '',
      startsAt: DateTime.parse(map['starts_at'] as String).toLocal(),
      durationMinutes: (map['duration_minutes'] as num?)?.toInt() ?? 60,
      status: map['status'] as String? ?? 'pending',
      notes: map['notes'] as String? ?? '',
      clientName:
          client is Map ? (client['name'] as String? ?? '') : '',
      clientPhone:
          client is Map ? (client['phone'] as String? ?? '') : '',
      masterName:
          master is Map ? (master['name'] as String? ?? '') : '',
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
  }) async {
    final row = await supabase
        .from('services')
        .insert({
          'master_id': uid,
          'name': name,
          'price': price,
          'duration_minutes': durationMinutes,
        })
        .select()
        .single();
    return CloudServiceItem.fromMap(row);
  }

  Future<void> updateService(CloudServiceItem s) =>
      supabase.from('services').update({
        'name': s.name,
        'price': s.price,
        'duration_minutes': s.durationMinutes,
      }).eq('id', s.id);

  Future<void> deleteService(int id) =>
      supabase.from('services').delete().eq('id', id);

  /// Полностью перезаписывает список услуг мастера в облаке
  /// (простой способ синхронизации локального справочника).
  Future<void> replaceMyServices(
    List<({String name, double price, int durationMinutes})> items,
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
}
