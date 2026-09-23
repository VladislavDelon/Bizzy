import 'package:bizzy_app/cloud/cloud_service.dart';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

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

/// Шаг сетки слотов под длительность визита: услуги по 90 минут
/// дают слоты через 90 минут — между ними не остаётся мёртвых дыр,
/// в которые другая запись не помещается. Меньше 15 мин — полчаса.
int slotStepFor(int durationMinutes) =>
    durationMinutes >= 15 ? durationMinutes.clamp(15, 240) : 30;

/// Свободные слоты дня по расписанию: рабочие часы минус занятые
/// записи, перерывы и ручные блокировки ([blocked] — отпуск,
/// закрытые часы). [week] == null → дефолт 9:00–18:00 без выходных.
List<DateTime> computeFreeSlots({
  required DateTime day,
  required int durationMinutes,
  required List<CloudBooking> busy,
  WorkWeek? week,
  int stepMinutes = 30,
  List<(DateTime, DateTime)> blocked = const [],
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
    final overlapsBlock = blocked.any(
      (bl) => slot.isBefore(bl.$2) && bl.$1.isBefore(slotEnd),
    );
    if (!overlapsBusy && !overlapsBreak && !overlapsBlock) slots.add(slot);
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

/// Экран «Закрытые дни и часы»: ручные блокировки поверх
/// рабочего расписания — отпуск, личное, больничный.
/// Салон может открыть его за конкретного мастера ([providerId])
/// или выбрать мастера чипами сверху — тогда заявки к нему
/// на закрытые даты не приходят.
class ScheduleBlocksScreen extends StatefulWidget {
  const ScheduleBlocksScreen({super.key, this.providerId, this.providerName});

  /// Чьё время закрываем; null — текущий пользователь, а у салона
  /// появляется выбор: салон целиком или конкретный мастер.
  final String? providerId;
  final String? providerName;

  @override
  State<ScheduleBlocksScreen> createState() => _ScheduleBlocksScreenState();
}

class _ScheduleBlocksScreenState extends State<ScheduleBlocksScreen> {
  final _cloud = CloudService();
  List<ScheduleBlock> _blocks = const [];
  bool _loading = true;
  bool _failed = false;

  /// Салон: список «кого закрываем» — сам салон + его мастера.
  List<MasterCard> _masters = const [];
  String? _selectedId; // null — ещё не определено (грузим роль)

  bool get _isSalonPicker =>
      widget.providerId == null && _masters.isNotEmpty;

  String get _pid =>
      widget.providerId ?? _selectedId ?? _cloud.uid ?? '';

  @override
  void initState() {
    super.initState();
    _initTargets();
  }

  /// У салона подгружаем команду — появляется выбор мастера.
  Future<void> _initTargets() async {
    if (widget.providerId == null) {
      try {
        final p = await _cloud.myProfile();
        if (p?.role == 'salon') {
          final masters = await _cloud.salonMasters();
          if (mounted) setState(() => _masters = masters);
        }
      } catch (_) {}
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final blocks = await _cloud.scheduleBlocksFor(
        _pid,
        from: DateTime.now().subtract(const Duration(days: 1)),
        to: DateTime.now().add(const Duration(days: 400)),
      );
      if (!mounted) return;
      setState(() {
        _blocks = blocks;
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

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  String _fmtT(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _add() async {
    // Мультивыбор дней: тапаем несколько дат на календаре —
    // закроются все выбранные (отпуск на неделю = одно действие).
    final days = await showModalBottomSheet<List<DateTime>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => const _BlockDaysPicker(),
    );
    if (days == null || days.isEmpty || !mounted) return;

    // «Весь день» или конкретный диапазон часов — одинаково
    // для каждого выбранного дня.
    final span = await showModalBottomSheet<(TimeOfDay, TimeOfDay)>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _BlockSpanPicker(day: days.first),
    );
    if (span == null || !mounted) return;

    final reason = await _askReason();
    if (reason == null || !mounted) return;

    var created = 0;
    for (final day in days) {
      final start = DateTime(
        day.year,
        day.month,
        day.day,
        span.$1.hour,
        span.$1.minute,
      );
      final end = DateTime(
        day.year,
        day.month,
        day.day,
        span.$2.hour,
        span.$2.minute,
      );
      final ok = await _cloud.addScheduleBlock(
        providerId: _pid,
        start: start,
        end: end,
        reason: reason,
      );
      if (ok != null) created++;
    }
    if (!mounted) return;
    if (created == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Не удалось закрыть время')));
      return;
    }
    await _load();
  }

  Future<String?> _askReason() {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Причина (необязательно)'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(
            hintText: 'Отпуск, личное, больничный…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(c.text.trim()),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Future<void> _remove(ScheduleBlock b) async {
    try {
      await _cloud.deleteScheduleBlock(b.id);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось убрать блокировку')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final who = widget.providerName;
    final body = _loading
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
        : _blocks.isEmpty
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Нет закрытых дат.\nЗакройте день или часы — клиенты '
                'не смогут записаться на это время.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: _blocks.length,
            itemBuilder: (context, i) {
              final b = _blocks[i];
              final wholeDay =
                  b.startsAt.hour == 0 &&
                  b.startsAt.minute == 0 &&
                  b.endsAt.hour == 23 &&
                  b.endsAt.minute == 59;
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.event_busy),
                  title: Text(
                    wholeDay
                        ? '${_fmt(b.startsAt)} — весь день'
                        : '${_fmt(b.startsAt)} · ${_fmtT(b.startsAt)}–${_fmtT(b.endsAt)}',
                  ),
                  subtitle: b.reason.isEmpty ? null : Text(b.reason),
                  trailing: IconButton(
                    tooltip: 'Открыть снова',
                    icon: const Icon(Icons.close),
                    onPressed: () => _remove(b),
                  ),
                ),
              );
            },
          );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          who == null ? 'Закрытые дни и часы' : 'Закрытое время · $who',
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.block),
        label: const Text('Закрыть время'),
      ),
      body: Column(
        children: [
          // Салон: выбираем, кому закрываем время — всему салону
          // или конкретному мастеру (отпуск, больничный).
          if (_isSalonPicker)
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: const Text('Весь салон'),
                      selected:
                          _selectedId == null || _selectedId == _cloud.uid,
                      onSelected: (_) {
                        setState(() => _selectedId = _cloud.uid);
                        _load();
                      },
                    ),
                  ),
                  for (final m in _masters)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(m.name.isEmpty ? 'Мастер' : m.name),
                        selected: _selectedId == m.userId,
                        onSelected: (_) {
                          setState(() => _selectedId = m.userId);
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Мультивыбор дней для блокировки: тап по дате добавляет/снимает
/// её, «Закрыть» возвращает список выбранных дней.
class _BlockDaysPicker extends StatefulWidget {
  const _BlockDaysPicker();

  @override
  State<_BlockDaysPicker> createState() => _BlockDaysPickerState();
}

class _BlockDaysPickerState extends State<_BlockDaysPicker> {
  final Set<DateTime> _days = {};
  DateTime _focused = DateTime.now();

  DateTime _d(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final today = _d(DateTime.now());
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Выберите дни',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              _days.isEmpty
                  ? 'Тапайте по датам — можно несколько'
                  : 'Выбрано: ${_days.length}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TableCalendar<void>(
              locale: 'ru_RU',
              firstDay: today,
              lastDay: today.add(const Duration(days: 365)),
              focusedDay: _focused,
              calendarFormat: CalendarFormat.month,
              startingDayOfWeek: StartingDayOfWeek.monday,
              headerStyle: const HeaderStyle(formatButtonVisible: false),
              selectedDayPredicate: (d) => _days.contains(_d(d)),
              onDaySelected: (selected, focused) {
                final d = _d(selected);
                setState(() {
                  _focused = focused;
                  if (!_days.remove(d)) _days.add(d);
                });
              },
              onPageChanged: (f) => _focused = f,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _days.isEmpty
                  ? null
                  : () {
                      final list = _days.toList()..sort();
                      Navigator.of(context).pop(list);
                    },
              child: const Text('Далее'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Выбор диапазона блокировки: «весь день» или часы начала/конца.
class _BlockSpanPicker extends StatefulWidget {
  const _BlockSpanPicker({required this.day});

  final DateTime day;

  @override
  State<_BlockSpanPicker> createState() => _BlockSpanPickerState();
}

class _BlockSpanPickerState extends State<_BlockSpanPicker> {
  bool _wholeDay = true;
  TimeOfDay _from = const TimeOfDay(hour: 12, minute: 0);
  TimeOfDay _to = const TimeOfDay(hour: 15, minute: 0);

  String _hm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Закрыть время',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Весь день'),
              value: _wholeDay,
              onChanged: (v) => setState(() => _wholeDay = v),
            ),
            if (!_wholeDay)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: _from,
                        );
                        if (t != null) setState(() => _from = t);
                      },
                      child: Text('с ${_hm(_from)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: _to,
                        );
                        if (t != null) setState(() => _to = t);
                      },
                      child: Text('до ${_hm(_to)}'),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(
                _wholeDay
                    ? (
                        const TimeOfDay(hour: 0, minute: 0),
                        const TimeOfDay(hour: 23, minute: 59),
                      )
                    : (_from, _to),
              ),
              child: const Text('Далее'),
            ),
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
          IconButton(
            tooltip: 'Закрытые дни и часы',
            icon: const Icon(Icons.event_busy),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const ScheduleBlocksScreen()),
            ),
          ),
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
