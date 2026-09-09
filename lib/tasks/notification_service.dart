import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'task_model.dart';

/// Сервис локальных уведомлений для личных дел.
class TaskNotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static bool _init = false;

  /// true, если права на уведомления есть (или не удалось проверить).
  static bool _canNotify = false;

  static bool get canNotify => _canNotify;

  /// Инициализирует плагин. Безопасно вызывать повторно.
  static Future<bool> init() async {
    if (_init) return _canNotify;
    try {
      tz_data.initializeTimeZones();

      const androidSettings =
          AndroidInitializationSettings('@mipmap/launcher_icon');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      final ok = await _plugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (details) {
          // TODO: можно открыть экран дела по payload.
        },
      );
      _init = true;
      _canNotify = ok ?? false;

      // На Android 13+ запрашиваем разрешение на уведомления.
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        final granted = await android?.requestNotificationsPermission();
        _canNotify = granted ?? _canNotify;

        // Запрашиваем точные будильники (Android 12+).
        await android?.requestExactAlarmsPermission();
      }

      return _canNotify;
    } catch (_) {
      // В тестах или при отсутствии плагина просто отключаем.
      _init = true;
      _canNotify = false;
      return false;
    }
  }

  /// Запланировать напоминание о деле.
  /// `notifyMinutes` — за сколько минут до dueAt прислать уведомление.
  /// 0 = не напоминать.
  static Future<void> schedule(TaskItem task) async {
    if (!_init) await init();
    if (!_canNotify || task.id == null || task.notifyMinutes <= 0) return;
    if (task.isDone) return;

    final notifyAt = task.dueAt
        .toUtc()
        .subtract(Duration(minutes: task.notifyMinutes));
    if (notifyAt.isBefore(DateTime.now().toUtc())) return;

    final tzDate = tz.TZDateTime.from(notifyAt, tz.UTC);

    const androidDetails = AndroidNotificationDetails(
      'bizzy_tasks',
      'Bizzy — дела',
      channelDescription: 'Напоминания о личных делах',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/launcher_icon',
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _plugin.zonedSchedule(
        id: task.id!,
        title: 'Напоминание: ${task.title}',
        body: task.description.isNotEmpty
            ? '${task.description} — через ${task.notifyMinutes} мин'
            : 'Через ${task.notifyMinutes} мин',
        scheduledDate: tzDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: task.id.toString(),
      );
    } catch (_) {
      // Не критично — уведомление не придёт, но дело сохранится.
    }
  }

  /// Отменить уведомление дела.
  static Future<void> cancel(int taskId) async {
    try {
      await _plugin.cancel(id: taskId);
    } catch (_) {
      // В тестах плагина может не быть.
    }
  }

  /// Перезапланировать все активные уведомления.
  static Future<void> rescheduleAll(List<TaskItem> tasks) async {
    for (final task in tasks) {
      await cancel(task.id ?? 0);
      if (!task.isDone) await schedule(task);
    }
  }
}
