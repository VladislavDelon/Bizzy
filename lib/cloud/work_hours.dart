import 'package:bizzy_app/cloud/cloud_service.dart';
import 'package:flutter/material.dart';

/// Рабочие часы одного дня недели.
class WorkDay {
  WorkDay({
    this.off = false,
    this.start = const TimeOfDay(hour: 9, minute: 0),
    this.end = const TimeOfDay(hour: 18, minute: 0),
    List<(TimeOfDay, TimeOfDay)>? breaks,
  }) : breaks = breaks ?? [];

  bool off;
  TimeOfDay start;
  TimeOfDay end;

  /// Перерывы внутри рабочего дня (обед и т.п.).
  final List<(TimeOfDay, TimeOfDay)> breaks;

  int get startMin => start.hour * 60 + start.minute;
  int get endMin => end.hour * 60 + end.minute;

  WorkDay copy() =>
      WorkDay(off: off, start: start, end: end, breaks: [...breaks]);
}

/// Расписание недели провайдера (мастера или салона).
class WorkWeek {
  WorkWeek() : days = {for (var d = 1; d <= 7; d++) d: WorkDay()};

  /// weekday (1=Пн..7=Вс) → часы дня.
  final Map<int, WorkDay> days;

  static const defaultStart = TimeOfDay(hour: 9, minute: 0);
  static const defaultEnd = TimeOfDay(hour: 18, minute: 0);
  static const dayNames = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
  static const dayNamesFull = [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ];

  WorkDay dayOf(DateTime date) => days[date.weekday] ?? WorkDay();

  /// Задано ли расписание явно (хоть один день включён/выключен вручную).
  bool get isConfigured => days.values.any((d) => d.off || _nonDefault(d));

  bool _nonDefault(WorkDay d) =>
      d.start != defaultStart || d.end != defaultEnd || d.breaks.isNotEmpty;

  Map<String, dynamic> toJson() => {
    for (final e in days.entries)
      '${e.key}': {
        's': _hm(e.value.start),
        'e': _hm(e.value.end),
        'off': e.value.off,
        'b': [
          for (final br in e.value.breaks) [_hm(br.$1), _hm(br.$2)],
        ],
      },
  };

  factory WorkWeek.fromJson(Map<String, dynamic>? json) {
    final w = WorkWeek();
    if (json == null) return w;
    for (var d = 1; d <= 7; d++) {
      final raw = json['$d'];
      if (raw is! Map) continue;
      final day = w.days[d]!;
      day.off = raw['off'] == true;
      final s = _parseHm(raw['s']);
      final e = _parseHm(raw['e']);
      if (s != null) day.start = s;
      if (e != null) day.end = e;
      day.breaks.clear();
      for (final br in (raw['b'] as List? ?? const [])) {
        if (br is List && br.length >= 2) {
          final bs = _parseHm(br[0]);
          final be = _parseHm(br[1]);
          if (bs != null && be != null) day.breaks.add((bs, be));
        }
      }
    }
    return w;
  }

  static String _hm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static TimeOfDay? _parseHm(dynamic v) {
    if (v is! String) return null;
    final parts = v.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  WorkWeek copy() => WorkWeek.fromJson(toJson());
}

/// Свободные слоты дня по расписанию: рабочие часы минус занятые
/// записи и перерывы. [week] == null → дефолт 9:00–18:00 без выходных.
List<DateTime> computeFreeSlots({
  required DateTime day,
  required int durationMinutes,
  required List<CloudBooking> busy,
  WorkWeek? week,
  int stepMinutes = 30,
}) {
  final w = week ?? WorkWeek();
  final wd = w.dayOf(day);
  // Явно заданное расписание: выходной — слотов нет.
  if (week != null && week.isConfigured && wd.off) return const [];
  final startMin = wd.off ? defaultStartMin : wd.startMin;
  final endMin = wd.off ? defaultEndMin : wd.endMin;
  final dayStart = DateTime(day.year, day.month, day.day);
  final slots = <DateTime>[];
  final now = DateTime.now();
  for (var m = startMin; m + durationMinutes <= endMin; m += stepMinutes) {
    final slot = dayStart.add(Duration(minutes: m));
    final slotEnd = slot.add(Duration(minutes: durationMinutes));
    if (slot.isBefore(now)) continue;
    final overlapsBusy = busy.any((b) {
      final bStart = b.startsAt;
      final bEnd = bStart.add(Duration(minutes: b.durationMinutes));
      return slot.isBefore(bEnd) && bStart.isBefore(slotEnd);
    });
    final overlapsBreak = wd.breaks.any((br) {
      final bs = dayStart.add(
        Duration(minutes: br.$1.hour * 60 + br.$1.minute),
      );
      final be = dayStart.add(
        Duration(minutes: br.$2.hour * 60 + br.$2.minute),
      );
      return slot.isBefore(be) && bs.isBefore(slotEnd);
    });
    if (!overlapsBusy && !overlapsBreak) slots.add(slot);
  }
  return slots;
}

int get defaultStartMin =>
    WorkWeek.defaultStart.hour * 60 + WorkWeek.defaultStart.minute;
int get defaultEndMin =>
    WorkWeek.defaultEnd.hour * 60 + WorkWeek.defaultEnd.minute;

String fmtHm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Редактор рабочих часов — используется и на полном экране,
/// и внутри онбординга.
class WorkHoursEditor extends StatefulWidget {
  const WorkHoursEditor({super.key, required this.week, this.onChanged});

  final WorkWeek week;
  final VoidCallback? onChanged;

  @override
  State<WorkHoursEditor> createState() => _WorkHoursEditorState();
}

class _WorkHoursEditorState extends State<WorkHoursEditor> {
  Future<void> _pick(
    TimeOfDay initial,
    ValueChanged<TimeOfDay> onPicked,
  ) async {
    final t = await showTimePicker(context: context, initialTime: initial);
    if (t != null) {
      onPicked(t);
      widget.onChanged?.call();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (var d = 1; d <= 7; d++)
          _dayRow(context, d, widget.week.days[d]!, scheme),
      ],
    );
  }

  Widget _dayRow(BuildContext context, int d, WorkDay day, ColorScheme scheme) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    WorkWeek.dayNamesFull[d - 1],
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  day.off ? 'Выходной' : 'Рабочий',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Switch(
                  value: !day.off,
                  onChanged: (v) {
                    setState(() => day.off = !v);
                    widget.onChanged?.call();
                  },
                ),
              ],
            ),
            if (!day.off) ...[
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () => _pick(day.start, (t) => day.start = t),
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(fmtHm(day.start)),
                  ),
                  const Text('—'),
                  TextButton.icon(
                    onPressed: () => _pick(day.end, (t) => day.end = t),
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(fmtHm(day.end)),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(
                        () => day.breaks.add((
                          const TimeOfDay(hour: 13, minute: 0),
                          const TimeOfDay(hour: 14, minute: 0),
                        )),
                      );
                      widget.onChanged?.call();
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Перерыв'),
                  ),
                ],
              ),
              for (var i = 0; i < day.breaks.length; i++)
                Row(
                  children: [
                    Icon(
                      Icons.coffee_outlined,
                      size: 16,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: () => _pick(day.breaks[i].$1, (t) {
                        setState(() => day.breaks[i] = (t, day.breaks[i].$2));
                      }),
                      child: Text(fmtHm(day.breaks[i].$1)),
                    ),
                    const Text('—'),
                    TextButton(
                      onPressed: () => _pick(day.breaks[i].$2, (t) {
                        setState(() => day.breaks[i] = (day.breaks[i].$1, t));
                      }),
                      child: Text(fmtHm(day.breaks[i].$2)),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Убрать перерыв',
                      onPressed: () {
                        setState(() => day.breaks.removeAt(i));
                        widget.onChanged?.call();
                      },
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Экран «Рабочие часы» у мастера/салона.
class WorkHoursScreen extends StatefulWidget {
  const WorkHoursScreen({super.key});

  @override
  State<WorkHoursScreen> createState() => _WorkHoursScreenState();
}

class _WorkHoursScreenState extends State<WorkHoursScreen> {
  final _cloud = CloudService();
  WorkWeek _week = WorkWeek();
  bool _loading = true;
  bool _saving = false;
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
      final raw = await _cloud.myWorkHours();
      if (!mounted) return;
      setState(() {
        _week = WorkWeek.fromJson(raw);
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

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _cloud.saveWorkHours(_week.toJson());
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Рабочие часы сохранены')));
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Не удалось сохранить')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Рабочие часы'),
        actions: [
          TextButton(
            onPressed: _saving || _loading ? null : _save,
            child: Text(_saving ? 'Сохраняю…' : 'Сохранить'),
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
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(
                  'Клиенты увидят свободные окна только внутри '
                  'рабочих часов. Перерывы тоже вычитаются.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                WorkHoursEditor(week: _week, onChanged: () => setState(() {})),
              ],
            ),
    );
  }
}
