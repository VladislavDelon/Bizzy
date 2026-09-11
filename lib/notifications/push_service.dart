import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../cloud/cloud_service.dart';

/// Глобальный обработчик фоновых сообщений FCM.
/// Должен быть top-level или static, иначе плагин его не найдёт.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await _showLocalNotification(
    title: message.notification?.title ?? message.data['title'] ?? 'Bizzy',
    body: message.notification?.body ?? message.data['body'] ?? '',
    payload: jsonEncode(message.data),
  );
}

const _androidChannel = AndroidNotificationDetails(
  'bizzy_push',
  'Bizzy push',
  channelDescription: 'Push-уведомления Bizzy',
  importance: Importance.max,
  priority: Priority.high,
  icon: '@mipmap/launcher_icon',
);

const _iosDetails = DarwinNotificationDetails();

const _notificationDetails = NotificationDetails(
  android: _androidChannel,
  iOS: _iosDetails,
);

Future<void> _showLocalNotification({
  required String title,
  required String body,
  String? payload,
}) async {
  try {
    await FlutterLocalNotificationsPlugin().show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: _notificationDetails,
      payload: payload,
    );
  } catch (_) {}
}

class PushNotificationService {
  static final _messaging = FirebaseMessaging.instance;
  static final _local = FlutterLocalNotificationsPlugin();
  static bool _init = false;
  static String? _fcmToken;

  static Future<void> init() async {
    if (_init) return;
    _init = true;

    try {
      tz_data.initializeTimeZones();

      await Firebase.initializeApp();

      // Запрос разрешений. На iOS обязателен, на Android 13+ тоже.
      if (!kIsWeb) {
        await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      // Локальные уведомления.
      const androidSettings =
          AndroidInitializationSettings('@mipmap/launcher_icon');
      const iosSettings = DarwinInitializationSettings();
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      await _local.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (details) {
          // TODO: обработать tap, открыть нужный экран.
        },
      );

      // Показывать push, пока приложение открыто.
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);

      FirebaseMessaging.onMessage.listen((message) {
        _showLocalNotification(
          title: message.notification?.title ?? message.data['title'] ?? 'Bizzy',
          body: message.notification?.body ?? message.data['body'] ?? '',
          payload: jsonEncode(message.data),
        );
      });

      // Получаем и сохраняем токен.
      _fcmToken = await _messaging.getToken();
      if (_fcmToken != null && cloudSignedIn) {
        await _saveToken(_fcmToken!);
      }

      _messaging.onTokenRefresh.listen((token) async {
        _fcmToken = token;
        if (cloudSignedIn) await _saveToken(token);
      });
    } catch (e) {
      debugPrint('PushNotificationService init error: $e');
    }
  }

  static Future<void> _saveToken(String token) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      await Supabase.instance.client.from('fcm_tokens').upsert(
        {
          'user_id': user.id,
          'token': token,
          'platform': Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'other'),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,token',
      );
    } catch (_) {}
  }

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

  /// Запланировать локальное напоминание перед записью.
  static Future<void> scheduleAppointmentReminder({
    required int? id,
    required DateTime dateTime,
    required int reminderMinutes,
    required String clientName,
    required String service,
  }) async {
    if (id == null || reminderMinutes <= 0) return;
    final notifyAt = dateTime.toUtc().subtract(Duration(minutes: reminderMinutes));
    if (notifyAt.isBefore(DateTime.now().toUtc())) return;

    final tzDate = tz.TZDateTime.from(notifyAt, tz.UTC);

    const androidDetails = AndroidNotificationDetails(
      'bizzy_appointments',
      'Bizzy — записи',
      channelDescription: 'Напоминания о записях',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/launcher_icon',
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: _iosDetails,
    );

    try {
      // ID + 1 000 000, чтобы не пересекаться с делами.
      await _local.zonedSchedule(
        id: id + 1000000,
        title: 'Напоминание о записи',
        body: '$clientName — $service',
        scheduledDate: tzDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: jsonEncode({'appointment_id': id}),
      );
    } catch (_) {}
  }

  static Future<void> cancelAppointmentReminder(int? id) async {
    if (id == null) return;
    try {
      await _local.cancel(id: id + 1000000);
    } catch (_) {}
  }
}
