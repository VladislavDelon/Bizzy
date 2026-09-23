import 'package:flutter/material.dart';

import '../cloud/blacklist_screen.dart';
import '../cloud/certificates_screen.dart';
import '../cloud/cloud_service.dart';
import '../cloud/provider_reviews_screen.dart';
import '../cloud/provider_stats_screen.dart';
import '../cloud/team_schedule_screen.dart';
import '../cloud/work_hours.dart';
import '../currency.dart';
// Веб-заглушка: sendPush настоящий (Edge Function), локальные
// напоминания не нужны — это браузер.
import '../notifications/push_stub.dart';

/// Веб-кабинет мастера/салона: заявки, статусы, расписание.
/// Локальных данных на вебе нет — всё из Supabase.
class ProviderHomeWeb extends StatefulWidget {
  const ProviderHomeWeb({
    super.key,
    required this.profile,
    required this.onSignOut,
  });

  final CloudProfile profile;
  final Future<void> Function() onSignOut;

  @override
  State<ProviderHomeWeb> createState() => _ProviderHomeWebState();
}

class _ProviderHomeWebState extends State<ProviderHomeWeb> {
  final _cloud = CloudService();
  List<CloudBooking> _bookings = const [];
  bool _loading = true;
  bool _failed = false;
  int _tab = 0;

  bool get _isSalon => widget.profile.role == 'salon';

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
      // Салон видит салонные заявки, мастер — свои личные.
      final bookings = _isSalon
          ? await _cloud.salonBookings()
          : await _cloud.masterBookings();
      if (!mounted) return;
      setState(() {
        _bookings = bookings;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  List<CloudBooking> get _pending =>
      _bookings.where((b) => b.status == 'pending').toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  List<CloudBooking> get _upcoming => _bookings
      .where(
        (b) =>
            b.status == 'confirmed' &&
            b.startsAt.isAfter(
              DateTime.now().subtract(const Duration(hours: 2)),
            ),
      )
      .toList()
    ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  List<CloudBooking> get _history => _bookings
      .where(
        (b) =>
            b.status == 'completed' ||
            b.status == 'cancelled' ||
            (b.status == 'confirmed' &&
                b.startsAt.isBefore(
                  DateTime.now().subtract(const Duration(hours: 2)),
                )),
      )
      .toList()
    ..sort((a, b) => b.startsAt.compareTo(a.startsAt));

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.'
      '${dt.month.toString().padLeft(2, '0')}.${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';

  /// Смена статуса + push клиенту; при отмене — уведомление
  /// листа ожидания об освободившемся окне.
  Future<void> _setStatus(CloudBooking b, String status) async {
    try {
      await _cloud.setBookingStatus(b.id, status);
      final label = switch (status) {
        'confirmed' => 'подтверждена',
        'completed' => 'завершена',
        'cancelled' => 'отменена',
        _ => status,
      };
      await PushNotificationService.sendPush(
        toUserId: b.clientId,
        title: 'Запись $label',
        body: '${b.serviceName} · ${_fmt(b.startsAt)}',
        data: {'appointment_id': b.id, 'status': status},
      );
      if (status == 'cancelled') {
        // Освободилось окно — ждущим клиентам придёт push.
        try {
          await _cloud.notifyWaitlist(b.masterId);
          if (b.salonId.isNotEmpty) await _cloud.notifyWaitlist(b.salonId);
        } catch (_) {}
      }
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось обновить запись')),
      );
    }
  }

  Future<void> _confirmPrepay(CloudBooking b) async {
    try {
      await _cloud.setPrepaymentStatus(b.id, 'confirmed');
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось подтвердить оплату')),
      );
    }
  }

  Widget _bookingCard(CloudBooking b) {
    final name = b.clientName.isEmpty ? 'Клиент' : b.clientName;
    final statusColor = switch (b.status) {
      'pending' => Colors.orange,
      'confirmed' => Colors.green,
      'completed' => Colors.blueGrey,
      _ => Colors.grey,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: statusColor.withValues(alpha: 0.15),
                  child: Icon(Icons.schedule, size: 18, color: statusColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        '${_fmt(b.startsAt)} · ${b.durationMinutes} мин',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (b.servicePrice > 0)
                  Text(
                    formatMoney(b.servicePrice),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 42),
              child: Text(
                b.serviceName.isEmpty ? 'Услуга' : b.serviceName,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            if (_isSalon && b.masterName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 42),
                child: Text(
                  'Мастер: ${b.masterName}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (b.notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 42),
                child: Text(
                  b.notes,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            if (b.prepaymentStatus == 'claimed')
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 42),
                child: ActionChip(
                  avatar: const Icon(Icons.payments_outlined, size: 16),
                  label: const Text('Клиент внёс предоплату — подтвердить'),
                  onPressed: () => _confirmPrepay(b),
                ),
              ),
            if (b.prepaymentStatus == 'confirmed')
              const Padding(
                padding: EdgeInsets.only(top: 4, left: 42),
                child: Chip(
                  avatar: Icon(Icons.check_circle, size: 16),
                  label: Text('Предоплата подтверждена'),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(width: 34),
                if (b.status == 'pending') ...[
                  FilledButton.tonalIcon(
                    onPressed: () => _setStatus(b, 'confirmed'),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Подтвердить'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _setStatus(b, 'cancelled'),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Отклонить'),
                  ),
                ],
                if (b.status == 'confirmed') ...[
                  FilledButton.tonalIcon(
                    onPressed: () => _setStatus(b, 'completed'),
                    icon: const Icon(Icons.done_all, size: 18),
                    label: const Text('Завершить'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _setStatus(b, 'cancelled'),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Отменить'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _pending,
      _upcoming,
      _history.take(100).toList(),
    ];
    final empty = [
      'Нет новых заявок',
      'Нет предстоящих записей',
      'История пуста',
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.profile.name.isEmpty
              ? (_isSalon ? 'Салон' : 'Мастер')
              : widget.profile.name,
        ),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: 'Инструменты',
            onSelected: (v) {
              final Widget? screen = switch (v) {
                'hours' => const WorkHoursScreen(),
                'blocks' => const ScheduleBlocksScreen(),
                'team' => _isSalon ? const TeamScheduleScreen() : null,
                'certs' => const ProviderCertificatesScreen(),
                'blacklist' => const BlacklistScreen(),
                'reviews' => const ProviderReviewsScreen(),
                'stats' => ProviderStatsScreen(isSalon: _isSalon),
                _ => null,
              };
              if (screen != null) {
                Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => screen),
                );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'hours',
                child: ListTile(
                  leading: Icon(Icons.schedule),
                  title: Text('Рабочие часы'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'blocks',
                child: ListTile(
                  leading: Icon(Icons.event_busy),
                  title: Text('Закрытые дни и часы'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (_isSalon)
                const PopupMenuItem(
                  value: 'team',
                  child: ListTile(
                    leading: Icon(Icons.calendar_view_week_outlined),
                    title: Text('Расписание команды'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: 'certs',
                child: ListTile(
                  leading: Icon(Icons.confirmation_number_outlined),
                  title: Text('Сертификаты'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'blacklist',
                child: ListTile(
                  leading: Icon(Icons.block),
                  title: Text('Чёрный список'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'reviews',
                child: ListTile(
                  leading: Icon(Icons.star_outline),
                  title: Text('Отзывы обо мне'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'stats',
                child: ListTile(
                  leading: Icon(Icons.bar_chart),
                  title: Text('Статистика'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Выйти'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) async {
          if (i == 3) {
            await widget.onSignOut();
            return;
          }
          setState(() => _tab = i);
        },
        destinations: [
          NavigationDestination(
            icon: Badge.count(
              count: _pending.length,
              isLabelVisible: _pending.isNotEmpty,
              child: const Icon(Icons.inbox_outlined),
            ),
            label: 'Заявки',
          ),
          const NavigationDestination(
            icon: Icon(Icons.event_available_outlined),
            label: 'Расписание',
          ),
          const NavigationDestination(
            icon: Icon(Icons.history),
            label: 'История',
          ),
          const NavigationDestination(
            icon: Icon(Icons.logout),
            label: 'Выход',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Не удалось загрузить записи'),
                  TextButton(onPressed: _load, child: const Text('Повторить')),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: pages[_tab].isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Center(child: Text(empty[_tab])),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: pages[_tab].length,
                      itemBuilder: (context, i) =>
                          _bookingCard(pages[_tab][i]),
                    ),
            ),
    );
  }
}
