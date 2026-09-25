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
import 'web_layout.dart';

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
  DateTime _scheduleDay = DateTime.now();

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

  /// Записи выбранного дня: облачные (не отменённые) + ручные.
  List<(DateTime, Object)> _dayItems(DateTime day) {
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    return [
      for (final b in _bookings)
        if (b.status != 'cancelled' && sameDay(b.startsAt, day))
          (b.startsAt, b as Object),
      for (final a in _manual)
        if (sameDay(a.startsAt, day)) (a.startsAt, a as Object),
    ]..sort((x, y) => x.$1.compareTo(y.$1));
  }

  /// «Расписание» у мастера — веб-аналог «Моих дел» на телефоне:
  /// планировщик дня со всеми записями по часам.
  Widget _scheduleTab() {
    final items = _dayItems(_scheduleDay);
    final now = DateTime.now();
    final isToday =
        _scheduleDay.year == now.year &&
        _scheduleDay.month == now.month &&
        _scheduleDay.day == now.day;
    const weekDays = [
      'Понедельник',
      'Вторник',
      'Среда',
      'Четверг',
      'Пятница',
      'Суббота',
      'Воскресенье',
    ];
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
    final dayLabel =
        '${weekDays[_scheduleDay.weekday - 1]}, '
        '${_scheduleDay.day} ${months[_scheduleDay.month - 1]}';
    final totalMin = items.fold<int>(
      0,
      (sum, item) =>
          sum +
          (item.$2 is CloudBooking
              ? (item.$2 as CloudBooking).durationMinutes
              : (item.$2 as CloudMasterAppointment).durationMinutes),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Предыдущий день',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(
                  () => _scheduleDay = _scheduleDay.subtract(
                    const Duration(days: 1),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      dayLabel,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      items.isEmpty
                          ? 'Свободный день'
                          : '${items.length} запис. · $totalMin мин',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: isToday
                    ? null
                    : () => setState(() => _scheduleDay = DateTime.now()),
                child: const Text('Сегодня'),
              ),
              IconButton(
                tooltip: 'Следующий день',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(
                  () =>
                      _scheduleDay = _scheduleDay.add(const Duration(days: 1)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: items.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Center(
                              child: Text(
                                'На этот день записей нет.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        )
                      : _cardsGrid(items),
                ),
        ),
      ],
    );
  }

  /// Сетка карточек записей: на широком экране (режим сайта)
  /// в 2–3 колонки, на узком — одна лента.
  Widget _cardsGrid(List<(DateTime, Object)> list) {
    return LayoutBuilder(
      builder: (context, bc) {
        final cols = bc.maxWidth > 1500
            ? 3
            : bc.maxWidth > 860
            ? 2
            : 1;
        Widget card(Object item) => item is CloudBooking
            ? _bookingCard(item)
            : _manualCard(item as CloudMasterAppointment);
        if (cols == 1) {
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
            itemCount: list.length,
            itemBuilder: (context, i) => card(list[i].$2),
          );
        }
        final w = (bc.maxWidth - 24 - (cols - 1) * 12) / cols;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
          child: Wrap(
            spacing: 12,
            children: [
              for (final item in list) SizedBox(width: w, child: card(item.$2)),
            ],
          ),
        );
      },
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
          // На широком сайте переключатель не растягиваем
          // на всю колонку — держим компактным по центру.
          child: Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SizedBox(
                width: double.infinity,
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
                      label: _ShrinkLabel('Заявки (${_pending.length})'),
                    ),
                    const ButtonSegment(
                      value: 1,
                      label: _ShrinkLabel('Грядущие'),
                    ),
                    const ButtonSegment(
                      value: 2,
                      label: _ShrinkLabel('История'),
                    ),
                  ],
                  selected: {_segment},
                  onSelectionChanged: (s) => setState(() => _segment = s.first),
                ),
              ),
            ),
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
                      : _cardsGrid(list),
                ),
        ),
      ],
    );
  }

  /// Переключение вкладки; у салона открытие «Мастера»
  /// гасит бейдж ответов.
  void _onNavTap(int index) {
    setState(() => _tab = index);
    if (index == 1 && _isSalon) {
      _cloud
          .markTeamResponsesSeen()
          .catchError((_) {})
          .whenComplete(_loadTeamBadge);
    }
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
        if (!_isSalon)
          // У мастера приглашения салонов — здесь, в «Ещё»
          // (как в приложении: «Мой профиль» → «Приглашения»).
          ListTile(
            leading: Badge(
              isLabelVisible: _teamBadge > 0,
              label: Text('$_teamBadge'),
              child: const Icon(Icons.mark_email_unread_outlined),
            ),
            title: const Text('Приглашения от салонов'),
            subtitle: const Text('Запросы на вступление в команду'),
            onTap: () => _openMore(
              Scaffold(
                appBar: AppBar(title: const Text('Приглашения')),
                body: ProviderInvitesTab(onChanged: _loadTeamBadge),
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
        // Вид веб-версии: полный сайт / как приложение.
        const WebViewModeTile(),
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
          // У мастера вторая вкладка — «Расписание»: планировщик
          // дня (веб-аналог «Моих дел» на телефоне). Приглашения
          // салонов живут в «Ещё», как в приложении.
          : _scheduleTab(),
      const ProviderClientsTab(),
      const ProviderServicesTab(),
      _moreTab(),
    ];
    final fab = _tab == 0
        ? FloatingActionButton.extended(
            heroTag: 'booking_add',
            onPressed: () => _editManual(),
            icon: const Icon(Icons.add),
            label: const Text('Новая запись'),
          )
        : null;
    // Бейджи — как на телефоне: новые заявки на «Клиенты»,
    // ответы мастеров на «Мастера» (салон) / приглашения
    // салонов на «Ещё» (мастер).
    final navItems = [
      const _WebNavItem(icon: Icons.event_note, label: 'Записи'),
      _WebNavItem(
        icon: _isSalon ? Icons.content_cut : Icons.calendar_view_day_outlined,
        label: _isSalon ? 'Мастера' : 'Расписание',
        badgeCount: _isSalon ? _teamBadge : 0,
      ),
      _WebNavItem(
        icon: Icons.people_outline,
        label: 'Клиенты',
        badgeCount: _pending.length,
      ),
      const _WebNavItem(icon: Icons.spa, label: 'Услуги'),
      _WebNavItem(
        icon: Icons.menu,
        label: 'Ещё',
        badgeCount: _isSalon ? 0 : _teamBadge,
      ),
    ];
    return ValueListenableBuilder<WebViewMode>(
      valueListenable: webViewMode,
      builder: (context, mode, _) {
        // Режим «Полный сайт»: боковая навигация слева,
        // контент — широкой колонкой до 1200px по центру.
        if (webSiteLayout(context)) {
          final scheme = Theme.of(context).colorScheme;
          // Прозрачный Scaffold — за контентом виден сезонный
          // анимированный фон сайта.
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _tab,
                  onDestinationSelected: _onNavTap,
                  labelType: NavigationRailLabelType.all,
                  leading: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.spa, color: scheme.primary, size: 30),
                        Text(
                          'Bizzy',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  destinations: [
                    for (final item in navItems)
                      NavigationRailDestination(
                        icon: _RailBadge(
                          count: item.badgeCount,
                          child: Icon(item.icon),
                        ),
                        label: Text(item.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      // Шапка сайта: имя кабинета + обновить.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 12, 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.profile.name.isEmpty
                                    ? (_isSalon ? 'Салон' : 'Мастер')
                                    : widget.profile.name,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
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
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1400),
                            child: IndexedStack(index: _tab, children: tabs),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            floatingActionButton: fab,
          );
        }
        // «Как приложение» / узкий экран: телефонная вёрстка
        // с нижней панелью.
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
            // Своя панель вместо NavigationBar: у стандартной лейбл
            // переносится посреди слова на узких экранах, а softWrap
            // там не выключить. Здесь текст всегда в одну строку.
            child: _WebNavBar(
              selectedIndex: _tab,
              onSelected: _onNavTap,
              items: navItems,
            ),
          ),
          floatingActionButton: fab,
        );
      },
    );
  }
}

/// Иконка пункта rail с бейджем количества (заявки/ответы).
class _RailBadge extends StatelessWidget {
  const _RailBadge({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    return Badge.count(count: count, child: child);
  }
}

/// Подпись, которая не переносится посреди слова: при нехватке
/// места текст ужимается по ширине, но остаётся в одну строку.
class _ShrinkLabel extends StatelessWidget {
  const _ShrinkLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, maxLines: 1, softWrap: false),
    );
  }
}

/// Один пункт нижней навигации веб-кабинета.
class _WebNavItem {
  const _WebNavItem({
    required this.icon,
    required this.label,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;
  final int badgeCount;
}

/// Нижняя навигация веб-кабинета: подписи строго в одну строку
/// (softWrap off + ellipsis) — на узком телефоне слова не рвутся.
class _WebNavBar extends StatelessWidget {
  const _WebNavBar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_WebNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: _WebNavTile(
                  item: items[i],
                  selected: i == selectedIndex,
                  onTap: () => onSelected(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WebNavTile extends StatelessWidget {
  const _WebNavTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _WebNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Badge(
            isLabelVisible: item.badgeCount > 0,
            label: Text('${item.badgeCount}'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
              decoration: BoxDecoration(
                color: selected
                    ? scheme.secondaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(item.icon, size: 22, color: color),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              height: 1.1,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
