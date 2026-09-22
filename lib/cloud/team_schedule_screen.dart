import 'package:bizzy_app/cloud/cloud_service.dart';
import 'package:flutter/material.dart';

/// «Расписание команды» у салона: все салонные заявки выбранного
/// дня, сгруппированные по мастерам. Личные заявки мастеров
/// сюда не попадают — их салону не видно.
class TeamScheduleScreen extends StatefulWidget {
  const TeamScheduleScreen({super.key});

  @override
  State<TeamScheduleScreen> createState() => _TeamScheduleScreenState();
}

class _TeamScheduleScreenState extends State<TeamScheduleScreen> {
  final _cloud = CloudService();
  List<CloudBooking> _bookings = [];
  Map<String, String> _masterNames = {};
  DateTime _day = DateTime.now();
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
      final results = await Future.wait([
        _cloud.salonBookings(),
        _cloud
            .salonMasters()
            .then<List<MasterCard>>((v) => v)
            .catchError((_) => <MasterCard>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _bookings = results[0] as List<CloudBooking>;
        _masterNames = {
          for (final m in results[1] as List<MasterCard>) m.userId: m.name,
        };
        _loading = false;
      });
    } catch (e, st) {
      await SyncLog.write('teamSchedule', '$e\n$st');
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  List<CloudBooking> get _dayBookings {
    return _bookings
        .where(
          (b) =>
              b.startsAt.year == _day.year &&
              b.startsAt.month == _day.month &&
              b.startsAt.day == _day.day &&
              b.status != 'cancelled',
        )
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _day = picked);
  }

  String _fmtTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  Color _statusColor(String s) => switch (s) {
    'pending' => Colors.orange,
    'confirmed' => Colors.green,
    'completed' => Colors.blueGrey,
    _ => Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    final bookings = _dayBookings;
    // Группировка по мастеру: ключ — masterId ('' — неназначенные).
    final groups = <String, List<CloudBooking>>{};
    for (final b in bookings) {
      groups.putIfAbsent(b.masterId, () => []).add(b);
    }
    final masterIds = groups.keys.toList()
      ..sort(
        (a, b) => (_masterNames[a] ?? 'яя').compareTo(_masterNames[b] ?? 'яя'),
      );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Расписание команды'),
        actions: [
          IconButton(
            tooltip: 'Выбрать день',
            onPressed: _pickDay,
            icon: const Icon(Icons.calendar_month),
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
                  const Text('Не удалось загрузить'),
                  TextButton(onPressed: _load, child: const Text('Повторить')),
                ],
              ),
            )
          : Column(
              children: [
                // Быстрый выбор дня — неделя вокруг текущего.
                SizedBox(
                  height: 56,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: 14,
                    itemBuilder: (context, i) {
                      final d = DateTime.now().add(Duration(days: i - 3));
                      final selected =
                          d.year == _day.year &&
                          d.month == _day.month &&
                          d.day == _day.day;
                      const wd = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        child: ChoiceChip(
                          selected: selected,
                          label: Text('${wd[d.weekday - 1]} ${d.day}'),
                          onSelected: (_) => setState(() => _day = d),
                        ),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: bookings.isEmpty
                      ? const Center(child: Text('На этот день записей нет'))
                      : ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            for (final mid in masterIds) ...[
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 8,
                                  bottom: 4,
                                ),
                                child: Text(
                                  mid.isEmpty
                                      ? 'Без мастера'
                                      : (_masterNames[mid]?.isNotEmpty == true
                                            ? _masterNames[mid]!
                                            : (groups[mid]!
                                                          .first
                                                          .masterName
                                                          .isNotEmpty ==
                                                      true
                                                  ? groups[mid]!
                                                        .first
                                                        .masterName
                                                  : 'Мастер')),
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ),
                              for (final b in groups[mid]!)
                                Card(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      radius: 14,
                                      backgroundColor: _statusColor(b.status)
                                          .withValues(alpha: 0.2),
                                      child: Icon(
                                        Icons.schedule,
                                        size: 16,
                                        color: _statusColor(b.status),
                                      ),
                                    ),
                                    title: Text(b.serviceName),
                                    subtitle: Text(
                                      '${_fmtTime(b.startsAt)} • '
                                      '${b.durationMinutes} мин • '
                                      '${b.clientName.isEmpty ? 'Клиент' : b.clientName}',
                                    ),
                                    trailing: b.servicePrice > 0
                                        ? Text(
                                            '${b.servicePrice.toStringAsFixed(0)} ₸',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          )
                                        : null,
                                  ),
                                ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
    );
  }
}
