import 'package:flutter/material.dart';

import '../notifications/push_service.dart';
import 'cloud_service.dart';
import 'master_public_profile.dart';

/// Главный экран клиента: каталог мастеров, мои записи, профиль.
class ClientHome extends StatefulWidget {
  const ClientHome({
    super.key,
    required this.profile,
    required this.onSignOut,
    required this.onDeleteAccount,
  });

  final CloudProfile profile;
  final Future<void> Function() onSignOut;
  final Future<void> Function() onDeleteAccount;

  @override
  State<ClientHome> createState() => _ClientHomeState();
}

class _ClientHomeState extends State<ClientHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      ClientCatalogTab(profile: widget.profile),
      const ClientBookingsTab(),
      _ClientProfileTab(
        profile: widget.profile,
        onSignOut: widget.onSignOut,
        onDeleteAccount: widget.onDeleteAccount,
      ),
    ];
    return Scaffold(
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.person_search_outlined),
            selectedIcon: Icon(Icons.person_search),
            label: 'Мастера',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: 'Записи',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Профиль',
          ),
        ],
      ),
    );
  }
}

// ==================== КАТАЛОГ МАСТЕРОВ ====================

Widget _masterAvatar(BuildContext context, MasterCard master, double radius) {
  final scheme = Theme.of(context).colorScheme;
  return CircleAvatar(
    radius: radius,
    backgroundColor: scheme.primary,
    backgroundImage:
        master.avatarUrl.isNotEmpty ? NetworkImage(master.avatarUrl) : null,
    child: master.avatarUrl.isEmpty
        ? Icon(Icons.person, color: scheme.onPrimary, size: radius)
        : null,
  );
}

class ClientCatalogTab extends StatefulWidget {
  const ClientCatalogTab({super.key, required this.profile});

  final CloudProfile profile;

  @override
  State<ClientCatalogTab> createState() => _ClientCatalogTabState();
}

class _ClientCatalogTabState extends State<ClientCatalogTab> {
  final _cloud = CloudService();
  List<String> _categories = [];
  List<MasterCard> _masters = [];
  String? _category;
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
      final categories = await _cloud.categories();
      final masters = await _cloud.masters(category: _category);
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _masters = masters;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openMaster(MasterCard master) async {
    final booked = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => MasterDetailScreen(master: master),
      ),
    );
    if (booked == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заявка отправлена мастеру')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Привет, ${widget.profile.name.isEmpty ? 'клиент' : widget.profile.name}!',
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Не удалось загрузить каталог'),
                      TextButton(
                          onPressed: _load, child: const Text('Повторить')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      SizedBox(
                        height: 52,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: ChoiceChip(
                                label: const Text('Все'),
                                selected: _category == null,
                                onSelected: (_) {
                                  setState(() => _category = null);
                                  _load();
                                },
                              ),
                            ),
                            for (final c in _categories)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: ChoiceChip(
                                  label: Text(c),
                                  selected: _category == c,
                                  onSelected: (_) {
                                    setState(() => _category = c);
                                    _load();
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_masters.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                            child: Text(
                              'Мастеров в этой категории пока нет',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      for (final m in _masters)
                        Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: ListTile(
                            leading: _masterAvatar(context, m, 24),
                            title: Text(m.name.isEmpty ? 'Мастер' : m.name),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m.category),
                                Row(
                                  children: [
                                    const Icon(Icons.star,
                                        size: 16, color: Colors.amber),
                                    const SizedBox(width: 4),
                                    Text(
                                      m.ratingCount == 0
                                          ? 'Новый'
                                          : '${m.ratingAvg.toStringAsFixed(1)} (${m.ratingCount})',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openMaster(m),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

/// Карточка мастера: профиль, услуги, кнопка записи.
class MasterDetailScreen extends StatefulWidget {
  const MasterDetailScreen({super.key, required this.master});

  final MasterCard master;

  @override
  State<MasterDetailScreen> createState() => _MasterDetailScreenState();
}

class _MasterDetailScreenState extends State<MasterDetailScreen> {
  final _cloud = CloudService();
  MasterCard? _master;
  List<CloudServiceItem> _services = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _master = widget.master;
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _cloud.masterCard(widget.master.userId),
        _cloud.servicesOf(widget.master.userId),
      ]);
      if (!mounted) return;
      setState(() {
        _master = (results[0] as MasterCard?) ?? widget.master;
        _services = results[1] as List<CloudServiceItem>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить профиль мастера';
        _loading = false;
      });
    }
  }

  Future<void> _book() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) =>
          BookAppointmentDialog(master: _master ?? widget.master, services: _services),
    );
    if (result == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ошибка')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!),
              const SizedBox(height: 12),
              TextButton(onPressed: _load, child: const Text('Повторить')),
            ],
          ),
        ),
      );
    }
    return MasterPublicProfileView(
      master: _master ?? widget.master,
      services: _services,
      onBook: _book,
      onRefresh: _load,
    );
  }
}

/// Диалог записи к мастеру: услуга + дата + время + комментарий.
class BookAppointmentDialog extends StatefulWidget {
  const BookAppointmentDialog({
    super.key,
    required this.master,
    required this.services,
  });

  final MasterCard master;
  final List<CloudServiceItem> services;

  @override
  State<BookAppointmentDialog> createState() => _BookAppointmentDialogState();
}

class _BookAppointmentDialogState extends State<BookAppointmentDialog> {
  final _cloud = CloudService();
  final _customService = TextEditingController();
  final _notes = TextEditingController();
  CloudServiceItem? _service;
  DateTime _date = DateTime.now();
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  DateTime? _selectedSlot;
  List<DateTime> _slots = [];
  bool _loadingSlots = false;
  bool _saving = false;
  String? _error;

  static const _workStart = TimeOfDay(hour: 9, minute: 0);
  static const _workEnd = TimeOfDay(hour: 18, minute: 0);
  static const _slotStepMinutes = 60;

  @override
  void initState() {
    super.initState();
    _loadSlots(_date);
  }

  @override
  void dispose() {
    _customService.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadSlots(DateTime day) async {
    if (widget.master.userId.isEmpty) return;
    setState(() => _loadingSlots = true);
    try {
      final bookings =
          await _cloud.masterBookingsForDay(widget.master.userId, day);
      final duration = _service?.durationMinutes ?? 60;
      final slots = <DateTime>[];
      var current = DateTime(
        day.year,
        day.month,
        day.day,
        _workStart.hour,
        _workStart.minute,
      );
      final end = DateTime(
        day.year,
        day.month,
        day.day,
        _workEnd.hour,
        _workEnd.minute,
      ).subtract(Duration(minutes: duration));
      while (!current.isAfter(end)) {
        final slotEnd = current.add(Duration(minutes: duration));
        final overlap = bookings.any((b) {
          final bStart = b.startsAt;
          final bEnd = bStart.add(Duration(minutes: b.durationMinutes));
          return current.isBefore(bEnd) && bStart.isBefore(slotEnd);
        });
        if (!overlap) slots.add(current);
        current = current.add(const Duration(minutes: _slotStepMinutes));
      }
      if (!mounted) return;
      setState(() {
        _slots = slots;
        _selectedSlot = slots.firstOrNull;
        _loadingSlots = false;
        if (_selectedSlot != null) {
          _time = TimeOfDay.fromDateTime(_selectedSlot!);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingSlots = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
      await _loadSlots(picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null && mounted) setState(() => _time = picked);
  }

  Future<void> _submit() async {
    if (_saving) return;
    final custom = _customService.text.trim();
    if (_service == null && custom.isEmpty) {
      setState(() => _error = 'Выберите услугу или напишите свою');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final startsAt = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    try {
      final booking = await _cloud.bookAppointment(
        masterId: widget.master.userId,
        serviceId: _service?.id,
        serviceName: _service?.name ?? custom,
        startsAt: startsAt,
        durationMinutes: _service?.durationMinutes ?? 60,
        notes: _notes.text.trim(),
      );
      await PushNotificationService.sendPush(
        toUserId: booking.masterId,
        title: 'Новая заявка',
        body:
            '${booking.clientName.isEmpty ? 'Клиент' : booking.clientName} записался на ${booking.serviceName}',
        data: {'appointment_id': booking.id, 'status': 'pending'},
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Не удалось отправить заявку';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateText =
        '${_date.day.toString().padLeft(2, '0')}.${_date.month.toString().padLeft(2, '0')}.${_date.year}';
    final timeText =
        '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
    return AlertDialog(
      title: Text('Запись к ${widget.master.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.services.isNotEmpty)
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Услуга',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                isEmpty: _service == null,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<CloudServiceItem?>(
                    value: _service,
                    isExpanded: true,
                    isDense: true,
                    items: [
                      for (final s in widget.services)
                        DropdownMenuItem(
                          value: s,
                          child: Text(
                            '${s.name} • ${s.price.toStringAsFixed(0)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const DropdownMenuItem<CloudServiceItem?>(
                        value: null,
                        child: Text('— Своя услуга —'),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() => _service = v);
                      _loadSlots(_date);
                    },
                  ),
                ),
              ),
            if (_service == null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _customService,
                decoration: const InputDecoration(
                  labelText: 'Название услуги',
                  hintText: 'Например: массаж спины',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(dateText),
                  ),
                ),
                const SizedBox(width: 8),
                if (_slots.isEmpty)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Icons.access_time, size: 18),
                      label: Text(timeText),
                    ),
                  )
                else
                  Expanded(
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: Text(timeText),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loadingSlots)
              const Center(child: CircularProgressIndicator())
            else if (_slots.isEmpty)
              const Text('Свободных часов на эту дату нет.')
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Свободные часы:'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final slot in _slots)
                        ChoiceChip(
                          label: Text(
                            '${slot.hour.toString().padLeft(2, '0')}:${slot.minute.toString().padLeft(2, '0')}',
                          ),
                          selected: _selectedSlot == slot,
                          onSelected: (_) {
                            setState(() {
                              _selectedSlot = slot;
                              _time = TimeOfDay.fromDateTime(slot);
                            });
                          },
                        ),
                    ],
                  ),
                ],
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Комментарий (необязательно)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: const Text('Отправить'),
        ),
      ],
    );
  }
}

// ==================== МОИ ЗАПИСИ ====================

class ClientBookingsTab extends StatefulWidget {
  const ClientBookingsTab({super.key});

  @override
  State<ClientBookingsTab> createState() => _ClientBookingsTabState();
}

class _ClientBookingsTabState extends State<ClientBookingsTab> {
  final _cloud = CloudService();
  List<CloudBooking> _bookings = [];
  Map<int, int> _myRatings = {};
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
      final bookings = await _cloud.clientBookings();
      final ratings = <int, int>{};
      for (final b in bookings) {
        final r = await _cloud.ratingFor(b.id);
        if (r != null) ratings[b.id] = r;
      }
      if (!mounted) return;
      setState(() {
        _bookings = bookings;
        _myRatings = ratings;
      });
      await _scheduleReminders(bookings);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scheduleReminders(List<CloudBooking> bookings) async {
    const reminderMinutes = 30;
    final now = DateTime.now();
    for (final b in bookings) {
      if (b.status == 'cancelled' || b.status == 'completed') {
        await PushNotificationService.cancelCloudReminder(b.id);
        continue;
      }
      if (b.startsAt.isAfter(now)) {
        await PushNotificationService.scheduleCloudReminder(
          id: b.id,
          dateTime: b.startsAt,
          reminderMinutes: reminderMinutes,
          title: 'Скоро запись',
          body: '${b.serviceName} • ${_fmt(b.startsAt)}',
        );
      } else {
        await PushNotificationService.cancelCloudReminder(b.id);
      }
    }
  }

  Future<void> _cancel(CloudBooking b) async {
    try {
      await _cloud.setBookingStatus(b.id, 'cancelled');
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось отменить запись')),
      );
    }
  }

  Future<void> _rate(CloudBooking b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => RateBookingDialog(booking: b),
    );
    if (ok == true) await _load();
  }

  String _statusLabel(String status) => switch (status) {
        'pending' => 'Ожидает мастера',
        'confirmed' => 'Подтверждена',
        'cancelled' => 'Отменена',
        'completed' => 'Завершена',
        _ => status,
      };

  Color _statusColor(String status) => switch (status) {
        'pending' => Colors.orange,
        'confirmed' => Colors.green,
        'cancelled' => Colors.red,
        'completed' => Colors.blueGrey,
        _ => Colors.grey,
      };

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  bool _canRate(CloudBooking b) =>
      b.isPast &&
      (b.status == 'confirmed' || b.status == 'completed') &&
      !_myRatings.containsKey(b.id);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Мои записи')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Не удалось загрузить записи'),
                      TextButton(
                          onPressed: _load, child: const Text('Повторить')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _bookings.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Center(
                              child: Text(
                                'У вас пока нет записей.\nВыберите мастера во вкладке «Мастера».',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: _bookings.length,
                          itemBuilder: (context, index) {
                            final b = _bookings[index];
                            final myRating = _myRatings[b.id];
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            b.serviceName,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                        ),
                                        Chip(
                                          label: Text(_statusLabel(b.status)),
                                          backgroundColor: _statusColor(b.status)
                                              .withValues(alpha: 0.15),
                                          side: BorderSide.none,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                        'Мастер: ${b.masterName.isEmpty ? '—' : b.masterName}'),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_fmt(b.startsAt)} • ${b.durationMinutes} мин',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                    if (myRating != null) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          for (var i = 1; i <= 5; i++)
                                            Icon(
                                              i <= myRating
                                                  ? Icons.star
                                                  : Icons.star_border,
                                              size: 16,
                                              color: Colors.amber,
                                            ),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        if (b.status == 'pending' ||
                                            b.status == 'confirmed')
                                          OutlinedButton.icon(
                                            onPressed: () => _cancel(b),
                                            icon: const Icon(Icons.close),
                                            label: const Text('Отменить'),
                                          ),
                                        if (_canRate(b))
                                          FilledButton.tonalIcon(
                                            onPressed: () => _rate(b),
                                            icon: const Icon(Icons.star),
                                            label: const Text('Оценить'),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}

/// Диалог оценки после записи.
class RateBookingDialog extends StatefulWidget {
  const RateBookingDialog({super.key, required this.booking});

  final CloudBooking booking;

  @override
  State<RateBookingDialog> createState() => _RateBookingDialogState();
}

class _RateBookingDialogState extends State<RateBookingDialog> {
  final _cloud = CloudService();
  final _comment = TextEditingController();
  int _rating = 5;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _cloud.rateBooking(
        appointmentId: widget.booking.id,
        masterId: widget.booking.masterId,
        rating: _rating,
        comment: _comment.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Не удалось отправить оценку';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Оцените мастера'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.booking.serviceName),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  onPressed: () => setState(() => _rating = i),
                  icon: Icon(
                    i <= _rating ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 36,
                  ),
                ),
            ],
          ),
          TextField(
            controller: _comment,
            decoration: const InputDecoration(
              labelText: 'Комментарий (необязательно)',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Позже'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: const Text('Отправить'),
        ),
      ],
    );
  }
}

// ==================== ПРОФИЛЬ КЛИЕНТА ====================

class _ClientProfileTab extends StatelessWidget {
  const _ClientProfileTab({
    required this.profile,
    required this.onSignOut,
    required this.onDeleteAccount,
  });

  final CloudProfile profile;
  final Future<void> Function() onSignOut;
  final Future<void> Function() onDeleteAccount;

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить аккаунт?'),
        content: const Text(
          'Все ваши данные в облаке будут удалены безвозвратно.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await onDeleteAccount();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось удалить аккаунт')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.person),
            title: Text(profile.name.isEmpty ? 'Клиент' : profile.name),
            subtitle: Text(profile.phone),
          ),
          ListTile(
            leading: const Icon(Icons.email),
            title: Text(supabase.auth.currentUser?.email ?? ''),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () => onSignOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Выйти'),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () => _confirmDelete(context),
            icon: const Icon(Icons.delete_forever),
            label: const Text('Удалить аккаунт'),
          ),
        ],
      ),
    );
  }
}
