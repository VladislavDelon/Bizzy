import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../cloud/cloud_service.dart';

/// Эран ближайших записей: показывает мастеру и клиенту
/// предстоящие записи на ближайшие 7 дней.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _cloud = CloudService();
  List<_NotificationItem> _items = [];
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
      final profile = await _cloud.myProfile();
      final now = DateTime.now();
      final end = now.add(const Duration(days: 7));
      final items = <_NotificationItem>[];

      if (profile?.isMaster ?? false) {
        final masterAppointments = await _cloud.myMasterAppointments();
        final clientBookings = await _cloud.masterBookings();
        for (final a in masterAppointments) {
          if (a.startsAt.isAfter(now) && a.startsAt.isBefore(end)) {
            items.add(_NotificationItem(
              title: a.clientName.isEmpty ? 'Запись' : a.clientName,
              subtitle: a.serviceName,
              time: a.startsAt,
              role: 'master',
            ));
          }
        }
        for (final b in clientBookings) {
          if ((b.status == 'confirmed' || b.status == 'pending') &&
              b.startsAt.isAfter(now) &&
              b.startsAt.isBefore(end)) {
            items.add(_NotificationItem(
              title: b.clientName.isEmpty ? 'Клиент' : b.clientName,
              subtitle: b.serviceName,
              time: b.startsAt,
              role: 'master',
            ));
          }
        }
      } else {
        final bookings = await _cloud.clientBookings();
        for (final b in bookings) {
          if ((b.status == 'confirmed' || b.status == 'pending') &&
              b.startsAt.isAfter(now) &&
              b.startsAt.isBefore(end)) {
            items.add(_NotificationItem(
              title: b.masterName.isEmpty ? 'Мастер' : b.masterName,
              subtitle: b.serviceName,
              time: b.startsAt,
              role: 'client',
            ));
          }
        }
      }

      items.sort((a, b) => a.time.compareTo(b.time));
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  String _fmt(DateTime dt) {
    final date = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}';
    final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final weekday = DateFormat.E('ru_RU').format(dt);
    return '$date ($weekday) $time';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ближайшие записи'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Не удалось загрузить записи'),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                )
              : _items.isEmpty
                  ? const Center(
                      child: Text(
                        'Ближайших записей нет',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            child: ListTile(
                              leading: const Icon(Icons.event_note),
                              title: Text(item.title),
                              subtitle: Text('${item.subtitle} • ${_fmt(item.time)}'),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _NotificationItem {
  const _NotificationItem({
    required this.title,
    required this.subtitle,
    required this.time,
    required this.role,
  });

  final String title;
  final String subtitle;
  final DateTime time;
  final String role;
}
