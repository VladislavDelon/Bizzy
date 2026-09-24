import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../cloud/blacklist_screen.dart';
import '../cloud/certificates_screen.dart';
import '../cloud/cloud_service.dart';
import '../cloud/credentials_dialog.dart';
import '../cloud/master_screens.dart';
import '../cloud/offers_screens.dart';
import '../cloud/provider_reviews_screen.dart';
import '../cloud/provider_stats_screen.dart';
import '../cloud/team_schedule_screen.dart';
import '../cloud/work_hours.dart';
import '../currency.dart';
// Веб-заглушка: sendPush настоящий (Edge Function), локальные
// напоминания не нужны — это браузер.
import '../notifications/push_stub.dart';
import 'provider_tabs.dart';

/// Веб-кабинет мастера/салона — те же 5 разделов, что в мобильном
/// приложении: Записи, Мастера/Приглашения, Клиенты, Услуги, Ещё.
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
  List<CloudMasterAppointment> _manual = const [];
  bool _loading = true;
  bool _failed = false;
  int _tab = 0;
  int _segment = 0;
  int _teamBadge = 0;

  bool get _isSalon => widget.profile.role == 'salon';

  @override
  void initState() {
    super.initState();
    _load();
    _loadTeamBadge();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      // Салон видит салонные заявки, мастер — свои личные.
      // Ручные записи (телефон/вживую) лежат в master_appointments.
      final results = await Future.wait([
        _isSalon ? _cloud.salonBookings() : _cloud.masterBookings(),
        _cloud.myMasterAppointments().catchError(
          (_) => <CloudMasterAppointment>[],
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _bookings = results[0] as List<CloudBooking>;
        _manual = results[1] as List<CloudMasterAppointment>;
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

  /// Бейдж: салону — ответы мастеров на приглашения, мастеру —
  /// входящие приглашения от салонов.
  Future<void> _loadTeamBadge() async {
    try {
      final count = _isSalon
          ? await _cloud.unseenTeamResponses()
          : (await _cloud.myTeamInvites())
                .where((i) => i.status == 'pending')
                .length;
      if (!mounted) return;
      setState(() => _teamBadge = count);
    } catch (_) {}
  }

  List<CloudBooking> get _pending =>
      _bookings.where((b) => b.status == 'pending').toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  /// (время, запись) — облачные брони и ручные записи в одной ленте.
  List<(DateTime, Object)> get _upcoming {
    final cutoff = DateTime.now().subtract(const Duration(hours: 2));
    return [
      for (final b in _bookings)
        if (b.status == 'confirmed' && b.startsAt.isAfter(cutoff))
          (b.startsAt, b as Object),
      for (final a in _manual)
        if (a.startsAt.isAfter(cutoff)) (a.startsAt, a as Object),
    ]..sort((x, y) => x.$1.compareTo(y.$1));
  }

  List<(DateTime, Object)> get _history {
    final cutoff = DateTime.now().subtract(const Duration(hours: 2));
    return [
      for (final b in _bookings)
        if (b.status == 'completed' ||
            b.status == 'cancelled' ||
            (b.status == 'confirmed' && b.startsAt.isBefore(cutoff)))
          (b.startsAt, b as Object),
      for (final a in _manual)
        if (a.startsAt.isBefore(cutoff)) (a.startsAt, a as Object),
    ]..sort((x, y) => y.$1.compareTo(x.$1));
  }

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.'
      '${dt.month.toString().padLeft(2, '0')}.${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';

  /// Тап по заявке — шторка с деталями и действиями (как на телефоне).
  Future<void> _openBooking(CloudBooking b) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          CloudBookingSheet(bookingId: b.id, onChanged: _load),
    );
    await _load();
  }

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

  Future<void> _editManual([CloudMasterAppointment? a]) async {
    final saved = await showWebAppointmentDialog(
      context,
      isSalon: _isSalon,
      providerName: widget.profile.name,
      existing: a,
    );
    if (saved != null) await _load();
  }

  Future<void> _deleteManual(CloudMasterAppointment a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить запись?'),
        content: Text(
          '${a.clientName.isEmpty ? 'Клиент' : a.clientName} — '
          '${a.serviceName.isEmpty ? 'услуга' : a.serviceName}, '
          '${_fmt(a.startsAt)}',
        ),
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
    if (ok != true) return;
    try {
      await _cloud.deleteMasterAppointment(a.id);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось удалить запись')),
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
      child: InkWell(
        onTap: () => _openBooking(b),
        borderRadius: BorderRadius.circular(12),
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
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(fontStyle: FontStyle.italic),
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
      ),
    );
  }

  Widget _manualCard(CloudMasterAppointment a) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _editManual(a),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .tertiaryContainer,
                    child: const Icon(Icons.edit_calendar, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.clientName.isEmpty ? 'Клиент' : a.clientName,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          '${_fmt(a.startsAt)} · ${a.durationMinutes} мин · вручную',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (a.servicePrice > 0)
                    Text(
                      formatMoney(a.servicePrice),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 42),
                child: Text(
                  a.serviceName.isEmpty ? 'Услуга' : a.serviceName,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (a.masterName.isNotEmpty && _isSalon)
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 42),
                  child: Text(
                    'Мастер: ${a.masterName}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              Row(
                children: [
                  const SizedBox(width: 34),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Удалить',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _deleteManual(a),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bookingsTab() {
    final list = switch (_segment) {
      0 => _pending.map((b) => (b.startsAt, b as Object)).toList(),
      1 => _upcoming,
      _ => _history.take(100).toList(),
    };
    final empty = switch (_segment) {
      0 => 'Нет новых заявок',
      1 => 'Нет предстоящих записей',
      _ => 'История пуста',
    };
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: SegmentedButton<int>(
            style: const ButtonStyle(
              // Узкий экран — иначе «Предстоящие» переносится
              // посреди слова.
              textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11)),
              padding: WidgetStatePropertyAll(EdgeInsets.zero),
              visualDensity: VisualDensity.compact,
            ),
            segments: [
              ButtonSegment(
                value: 0,
                label: Text('Заявки (${_pending.length})'),
              ),
              const ButtonSegment(value: 1, label: Text('Грядущие')),
              const ButtonSegment(value: 2, label: Text('История')),
            ],
            selected: {_segment},
            onSelectionChanged: (s) => setState(() => _segment = s.first),
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
                      const Text('Не удалось загрузить записи'),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: list.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 120),
                            Center(child: Text(empty)),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                          itemCount: list.length,
                          itemBuilder: (context, i) {
                            final item = list[i].$2;
                            return item is CloudBooking
                                ? _bookingCard(item)
                                : _manualCard(item as CloudMasterAppointment);
                          },
                        ),
                ),
        ),
      ],
    );
  }

  void _openMore(Widget screen) {
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => screen));
  }

  Widget _moreTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        ListTile(
          leading: const Icon(Icons.storefront_outlined),
          title: Text(_isSalon ? 'Профиль салона' : 'Мой профиль'),
          subtitle: const Text('Категория, описание, фото для клиентов'),
          onTap: () => _openMore(
            MasterProfileScreen(
              role: widget.profile.role,
              // На вебе услуги уже в облаке — синхронизировать нечего.
              onSyncServices: () async {},
              onDeleteAccount: () =>
                  _cloud.deleteMyAccount().then((_) => widget.onSignOut()),
            ),
          ),
        ),
        if (_isSalon)
          ListTile(
            leading: const Icon(Icons.calendar_view_week_outlined),
            title: const Text('Расписание команды'),
            subtitle: const Text('Записи мастеров по дням'),
            onTap: () => _openMore(const TeamScheduleScreen()),
          ),
        ListTile(
          leading: const Icon(Icons.schedule),
          title: const Text('Рабочие часы'),
          subtitle: const Text('Когда вы принимаете клиентов'),
          onTap: () => _openMore(const WorkHoursScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.event_busy),
          title: const Text('Закрытые дни и часы'),
          subtitle: const Text('Отпуск, личное — слоты закрываются'),
          onTap: () => _openMore(const ScheduleBlocksScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.confirmation_number_outlined),
          title: const Text('Сертификаты'),
          subtitle: const Text('Пакеты визитов, выданные клиентам'),
          onTap: () => _openMore(const ProviderCertificatesScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.block),
          title: const Text('Чёрный список'),
          subtitle: const Text('Клиенты без права записи'),
          onTap: () => _openMore(const BlacklistScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.star_outline),
          title: const Text('Отзывы обо мне'),
          onTap: () => _openMore(const ProviderReviewsScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.bar_chart),
          title: const Text('Статистика'),
          onTap: () => _openMore(ProviderStatsScreen(isSalon: _isSalon)),
        ),
        ListTile(
          leading: const Icon(Icons.local_offer_outlined),
          title: const Text('Honey и акции'),
          subtitle: const Text('Скидки, сертификаты, приведи друга'),
          onTap: () => _openMore(const SalonOffersScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.key_outlined),
          title: const Text('Логин и пароль'),
          onTap: () => showCredentialsEditor(context),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Выйти из аккаунта'),
          onTap: widget.onSignOut,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      _bookingsTab(),
      _isSalon
          ? SalonTeamScreen(
              localDirectoryBuilder: (onAddMaster) =>
                  WebTeamDirectory(onAddMaster: onAddMaster),
            )
          : ProviderInvitesTab(onChanged: _loadTeamBadge),
      const ProviderClientsTab(),
      const ProviderServicesTab(),
      _moreTab(),
    ];
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          widget.profile.name.isEmpty
              ? (_isSalon ? 'Салон' : 'Мастер')
              : widget.profile.name,
        ),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: () {
              _load();
              _loadTeamBadge();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: tabs),
      bottomNavigationBar: bizzyNavBar(
        context,
        bizzy: false,
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (index) {
            setState(() => _tab = index);
            // Салон открыл «Мастера» — ответы считаются просмотренными.
            if (index == 1 && _isSalon) {
              _cloud
                  .markTeamResponsesSeen()
                  .catchError((_) {})
                  .whenComplete(_loadTeamBadge);
            }
          },
          destinations: [
            NavigationDestination(
              icon: Badge.count(
                count: _pending.length,
                isLabelVisible: _pending.isNotEmpty,
                child: const Icon(Icons.event_note),
              ),
              label: 'Записи',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: _teamBadge > 0,
                label: Text('$_teamBadge'),
                child: Icon(
                  _isSalon
                      ? Icons.content_cut
                      : Icons.mark_email_unread_outlined,
                ),
              ),
              label: _isSalon ? 'Мастера' : 'Салоны',
            ),
            const NavigationDestination(
              icon: Icon(Icons.people_outline),
              label: 'Клиенты',
            ),
            const NavigationDestination(icon: Icon(Icons.spa), label: 'Услуги'),
            const NavigationDestination(icon: Icon(Icons.menu), label: 'Ещё'),
          ],
        ),
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              heroTag: 'booking_add',
              onPressed: () => _editManual(),
              icon: const Icon(Icons.add),
              label: const Text('Новая запись'),
            )
          : null,
    );
  }
}
