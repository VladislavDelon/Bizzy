import 'dart:convert';

import 'package:http/http.dart' as http;

import '../cloud/cloud_service.dart' show loginToEmail, emailToLogin;
import '../cloud/supabase_config.dart' show supabaseUrl;

/// Пользователь системы в админке: auth-аккаунт + профиль
/// + карточка мастера/салона (рейтинг).
class AdminUser {
  AdminUser({
    required this.id,
    required this.login,
    required this.role,
    required this.name,
    required this.phone,
    required this.banned,
    required this.createdAt,
    this.category = '',
    this.ratingAvg = 0,
    this.ratingCount = 0,
  });

  final String id;
  final String login;
  final String role; // client | master | salon | (пусто)
  final String name;
  final String phone;
  final bool banned;
  final DateTime createdAt;
  String category;
  double ratingAvg;
  int ratingCount;

  bool get isProvider => role == 'master' || role == 'salon';
}

/// Отзыв для показа в админке (из `ratings` или `client_reviews`).
class AdminReview {
  const AdminReview({
    required this.id,
    required this.table,
    required this.rating,
    required this.comment,
    required this.authorName,
    required this.createdAt,
  });

  final String id;

  /// 'ratings' | 'client_reviews' — откуда удалять.
  final String table;
  final int rating;
  final String comment;
  final String authorName;
  final DateTime createdAt;
}

/// REST-клиент на service_role ключе: управление auth-пользователями
/// (логин/пароль/бан/удаление) и строками таблиц мимо RLS.
/// Используется только локальной админкой — ключ нигде не публикуем.
abstract class AdminApiBase {
  Future<List<AdminUser>> listUsers();
  Future<void> updateLogin(String userId, String newLogin);
  Future<void> updatePassword(String userId, String newPassword);
  Future<void> setBanned(String userId, bool banned);
  Future<void> deleteUser(String userId);
  Future<List<AdminReview>> reviewsAbout(AdminUser user);
  Future<void> deleteReview(AdminReview review);
}

class AdminApi implements AdminApiBase {
  AdminApi(this.serviceKey);

  final String serviceKey;

  Map<String, String> get _headers => {
    'apikey': serviceKey,
    'Authorization': 'Bearer $serviceKey',
    'Content-Type': 'application/json',
  };

  Future<dynamic> _get(String path) async {
    final r = await http.get(Uri.parse('$supabaseUrl$path'), headers: _headers);
    if (r.statusCode >= 400) {
      throw Exception('GET $path → ${r.statusCode}: ${r.body}');
    }
    return jsonDecode(r.body);
  }

  Future<dynamic> _send(String method, String path, [Object? body]) async {
    final req = http.Request(method, Uri.parse('$supabaseUrl$path'))
      ..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    final r = await http.Response.fromStream(await req.send());
    if (r.statusCode >= 400) {
      throw Exception('$method $path → ${r.statusCode}: ${r.body}');
    }
    return r.body.isEmpty ? null : jsonDecode(r.body);
  }

  @override
  Future<List<AdminUser>> listUsers() async {
    // GoTrue admin: список auth-пользователей (нужен service_role).
    final auth = await _get('/auth/v1/admin/users?per_page=1000');
    final rawUsers = auth is Map
        ? (auth['users'] as List? ?? const [])
        : (auth as List? ?? const []);

    // Профили и карточки мастеров — PostgREST тем же ключом (без RLS).
    final profiles =
        (await _get('/rest/v1/profiles?select=id,name,phone,role')) as List;
    final profileById = {for (final p in profiles) p['id'] as String: p};
    List cards = const [];
    try {
      cards = await _get(
        '/rest/v1/master_profiles?select=user_id,category,rating_avg,rating_count',
      ) as List;
    } catch (_) {}
    final cardByUser = {for (final c in cards) c['user_id'] as String: c};

    return [
      for (final u in rawUsers)
        if (u is Map)
          () {
            final id = u['id'] as String? ?? '';
            final email = u['email'] as String? ?? '';
            final bannedUntil = DateTime.tryParse(
              u['banned_until'] as String? ?? '',
            );
            final p = profileById[id];
            final c = cardByUser[id];
            return AdminUser(
              id: id,
              login: emailToLogin(email),
              role:
                  p?['role'] as String? ??
                  u['user_metadata']?['role'] as String? ??
                  '',
              name:
                  p?['name'] as String? ??
                  u['user_metadata']?['name'] as String? ??
                  '',
              phone: p?['phone'] as String? ?? '',
              banned:
                  bannedUntil != null && bannedUntil.isAfter(DateTime.now()),
              createdAt:
                  DateTime.tryParse(u['created_at'] as String? ?? '') ??
                  DateTime.fromMillisecondsSinceEpoch(0),
              category: c?['category'] as String? ?? '',
              ratingAvg: (c?['rating_avg'] as num?)?.toDouble() ?? 0,
              ratingCount: (c?['rating_count'] as num?)?.toInt() ?? 0,
            );
          }(),
    ];
  }

  @override
  Future<void> updateLogin(String userId, String newLogin) => _send(
    'PUT',
    '/auth/v1/admin/users/$userId',
    {'email': loginToEmail(newLogin)},
  );

  @override
  Future<void> updatePassword(String userId, String newPassword) =>
      _send('PUT', '/auth/v1/admin/users/$userId', {'password': newPassword});

  @override
  Future<void> setBanned(String userId, bool banned) => _send(
    'PUT',
    '/auth/v1/admin/users/$userId',
    // GoTrue: ban_duration — строка длительности, 'none' снимает бан.
    {'ban_duration': banned ? '876000h' : 'none'},
  );

  @override
  Future<void> deleteUser(String userId) async {
    // Сначала строки справочников (если нет каскада), затем auth.
    try {
      await _send('DELETE', '/rest/v1/master_profiles?user_id=eq.$userId');
    } catch (_) {}
    try {
      await _send('DELETE', '/rest/v1/profiles?id=eq.$userId');
    } catch (_) {}
    await _send('DELETE', '/auth/v1/admin/users/$userId');
  }

  @override
  Future<List<AdminReview>> reviewsAbout(AdminUser user) async {
    final reviews = <AdminReview>[];
    final nameOf = await _namesResolver();

    if (user.isProvider) {
      // Отзывы клиентов на провайдера — ratings.master_id/salon_id.
      final rows = await _get(
        '/rest/v1/ratings?or=(master_id.eq.${user.id},salon_id.eq.${user.id})'
        '&select=id,client_id,rating,comment,created_at'
        '&order=created_at.desc',
      ) as List;
      for (final r in rows) {
        reviews.add(
          AdminReview(
            id: r['id'].toString(),
            table: 'ratings',
            rating: (r['rating'] as num?)?.toInt() ?? 0,
            comment: r['comment'] as String? ?? '',
            authorName: nameOf(r['client_id'] as String? ?? ''),
            createdAt:
                DateTime.tryParse(r['created_at'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
          ),
        );
      }
    }
    if (user.role == 'client') {
      // Отзывы провайдеров на клиента — client_reviews.client_id.
      try {
        final rows = await _get(
          '/rest/v1/client_reviews?client_id=eq.${user.id}'
          '&select=id,master_id,rating,comment,created_at'
          '&order=created_at.desc',
        ) as List;
        for (final r in rows) {
          reviews.add(
            AdminReview(
              id: r['id'].toString(),
              table: 'client_reviews',
              rating: (r['rating'] as num?)?.toInt() ?? 0,
              comment: r['comment'] as String? ?? '',
              authorName: nameOf(r['master_id'] as String? ?? ''),
              createdAt:
                  DateTime.tryParse(r['created_at'] as String? ?? '') ??
                  DateTime.fromMillisecondsSinceEpoch(0),
            ),
          );
        }
      } catch (_) {}
    }
    return reviews;
  }

  /// Имена авторов отзывов пачкой из profiles.
  Future<String Function(String)> _namesResolver() async {
    try {
      final rows = await _get('/rest/v1/profiles?select=id,name') as List;
      final names = {for (final p in rows) p['id'] as String: p['name']};
      return (id) => names[id] as String? ?? 'Пользователь';
    } catch (_) {
      return (_) => 'Пользователь';
    }
  }

  @override
  Future<void> deleteReview(AdminReview review) =>
      _send('DELETE', '/rest/v1/${review.table}?id=eq.${review.id}');
}
