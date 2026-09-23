import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cloud/cloud_service.dart';

/// Веб-заглушка PushNotificationService: dart:io, firebase_messaging и
/// flutter_local_notifications на вебе недоступны, поэтому тот же API
/// без локальных напоминаний. sendPush работает — это вызов
/// Supabase Edge Function, платформенные плагины не нужны.
class PushNotificationService {
  static final navigatorKey = GlobalKey<NavigatorState>();
  static bool pendingNotification = false;

  static Future<void> init() async {}

  /// Отправляет push другому пользователю через Edge Function.
  static Future<void> sendPush({
    required String toUserId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    if (!cloudSignedIn) return;
    try {
      await Supabase.instance.client.functions.invoke(
        'send-push',
        body: {
          'to_user_id': toUserId,
          'title': title,
          'body': body,
          'data': data ?? <String, dynamic>{},
        },
      );
    } catch (e) {
      debugPrint('sendPush error: $e');
    }
  }

  /// На вебе локальных напоминаний нет — push придёт от сервера,
  /// а локальные уведомления живут только на устройстве клиента.
  static Future<void> scheduleAppointmentReminder({
    required int? id,
    required DateTime dateTime,
    required int reminderMinutes,
    required String clientName,
    required String service,
  }) async {}

  static Future<void> cancelAppointmentReminder(int? id) async {}

  static Future<void> scheduleCloudReminder({
    required int id,
    required DateTime dateTime,
    required int reminderMinutes,
    required String title,
    required String body,
  }) async {}

  static Future<void> cancelCloudReminder(int id) async {}

  static Future<void> showLocal({
    required String title,
    required String body,
    String? payload,
  }) async {}
}
