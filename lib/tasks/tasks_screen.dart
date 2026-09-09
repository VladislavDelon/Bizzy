import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../main.dart';
import 'notification_service.dart';
import 'task_model.dart';

/// Экран личных дел: список + календарь + напоминания.
class TasksScreen extends StatefulWidget {
  const TasksScreen({
    super.key,
    required this.database,
    required this.user,
  });

  final AppointmentsDatabase database;
  final User user;

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  List<TaskItem> _tasks = [];
  bool _loading = true;
  bool _failed = false;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  @override
  void initState() {
    super.initState();
    TaskNotificationService.init();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final tasks =
          await widget.database.getTasks(widget.user.id, includeDone: false);
      if (!mounted) return;
      setState(() => _tasks = tasks);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<TaskItem> _tasksForDay(DateTime day) => _tasks
      .where(
        (t) =>
            t.dueAt.year == day.year &&
            t.dueAt.month == day.month &&
            t.dueAt.day == day.day,
      )
      .toList();

  Future<void> _add() async {
    final task = await showDialog<TaskItem>(
      context: context,
      builder: (context) => _TaskEditDialog(userId: widget.user.id),
    );
    if (task == null || !mounted) return;
    try {
      final id = await widget.database.addTask(task);
      final saved = task.copyWith(id: id);
      await TaskNotificationService.schedule(saved);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить дело')),
      );
    }
  }

  Future<void> _edit(TaskItem task) async {
    final updated = await showDialog<TaskItem>(
      context: context,
      builder: (context) => _TaskEditDialog(task: task, userId: task.userId),
    );
    if (updated == null || !mounted) return;
    try {
      await widget.database.updateTask(updated);
      await TaskNotificationService.cancel(updated.id ?? 0);
      await TaskNotificationService.schedule(updated);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось обновить дело')),
      );
    }
  }

  Future<void> _toggleDone(TaskItem task) async {
    final done = !task.isDone;
    try {
      await widget.database.setTaskDone(task.id!, done);
      if (done) await TaskNotificationService.cancel(task.id!);
      if (!done) await TaskNotificationService.schedule(task.copyWith(isDone: false));
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось изменить статус')),
      );
    }
  }

  Future<void> _delete(TaskItem task) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить дело?'),
        content: Text('«${task.title}» будет удалено.'),
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
    if (ok != true || !mounted) return;
    try {
      await TaskNotificationService.cancel(task.id!);
      await widget.database.deleteTask(task.id!);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось удалить дело')),
      );
    }
  }

  String _time(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final selected = _selectedDay ?? _focusedDay;
    final dayTasks = _tasksForDay(selected);
    return Scaffold(
      appBar: AppBar(title: const Text('Мои дела')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Не удалось загрузить дела'),
                      TextButton(
                          onPressed: _load, child: const Text('Повторить')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    TableCalendar<TaskItem>(
                      firstDay: DateTime.now()
                          .subtract(const Duration(days: 365)),
                      lastDay:
                          DateTime.now().add(const Duration(days: 365)),
                      focusedDay: _focusedDay,
                      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                      onDaySelected: (selected, focused) {
                        setState(() {
                          _selectedDay = selected;
                          _focusedDay = focused;
                        });
                      },
                      onPageChanged: (focused) => _focusedDay = focused,
                      calendarFormat: _calendarFormat,
                      onFormatChanged: (format) =>
                          setState(() => _calendarFormat = format),
                      eventLoader: _tasksForDay,
                      calendarStyle: CalendarStyle(
                        markerSize: 6,
                        markersMaxCount: 3,
                        markerDecoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: dayTasks.isEmpty
                          ? const Center(
                              child: Text(
                                'На этот день дел нет.\nНажмите +, чтобы создать.',
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.only(bottom: 80),
                              itemCount: dayTasks.length,
                              itemBuilder: (context, index) {
                                final t = dayTasks[index];
                                final isPast = t.dueAt.isBefore(DateTime.now());
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  child: ListTile(
                                    leading: Checkbox(
                                      value: t.isDone,
                                      onChanged: (_) => _toggleDone(t),
                                    ),
                                    title: Text(
                                      t.title,
                                      style: TextStyle(
                                        decoration: t.isDone
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(_time(t.dueAt)),
                                        if (t.description.isNotEmpty)
                                          Text(t.description),
                                        if (t.notifyMinutes > 0)
                                          Text(
                                            'Напомнить за ${t.notifyMinutes} мин',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                      ],
                                    ),
                                    isThreeLine:
                                        t.description.isNotEmpty,
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isPast && !t.isDone)
                                          const Icon(Icons.warning,
                                              color: Colors.orange,
                                              size: 20),
                                        IconButton(
                                          icon: const Icon(Icons.edit),
                                          onPressed: () => _edit(t),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete),
                                          onPressed: () => _delete(t),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Новое дело'),
      ),
    );
  }
}

/// Диалог создания/редактирования дела.
class _TaskEditDialog extends StatefulWidget {
  const _TaskEditDialog({this.task, required this.userId});

  final TaskItem? task;
  final int userId;

  @override
  State<_TaskEditDialog> createState() => _TaskEditDialogState();
}

class _TaskEditDialogState extends State<_TaskEditDialog> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.now();
  int _notifyBefore = 15;

  static const _notifyOptions = [
    (label: 'Без напоминания', value: 0),
    (label: 'За 5 мин', value: 5),
    (label: 'За 15 мин', value: 15),
    (label: 'За 30 мин', value: 30),
    (label: 'За 1 час', value: 60),
    (label: 'За 1 день', value: 1440),
  ];

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    if (t != null) {
      _title.text = t.title;
      _desc.text = t.description;
      _date = t.dueAt;
      _time = TimeOfDay(hour: t.dueAt.hour, minute: t.dueAt.minute);
      _notifyBefore = t.notifyMinutes;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked =
        await showTimePicker(context: context, initialTime: _time);
    if (picked != null && mounted) setState(() => _time = picked);
  }

  void _save() {
    if (_title.text.trim().isEmpty) return;
    final due = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    final task = TaskItem(
      id: widget.task?.id,
      userId: widget.task?.userId ?? widget.userId,
      title: _title.text.trim(),
      description: _desc.text.trim(),
      dueAt: due,
      notifyMinutes: _notifyBefore,
      isDone: widget.task?.isDone ?? false,
      createdAt: widget.task?.createdAt ?? DateTime.now(),
    );
    Navigator.of(context).pop(task);
  }

  @override
  Widget build(BuildContext context) {
    final dateText =
        '${_date.day.toString().padLeft(2, '0')}.${_date.month.toString().padLeft(2, '0')}.${_date.year}';
    final timeText =
        '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
    return AlertDialog(
      title: Text(widget.task == null ? 'Новое дело' : 'Редактировать дело'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Название',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Описание',
                border: OutlineInputBorder(),
              ),
            ),
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
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.access_time, size: 18),
                    label: Text(timeText),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Напомнить',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              isEmpty: false,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _notifyBefore,
                  isExpanded: true,
                  isDense: true,
                  items: _notifyOptions
                      .map(
                        (o) => DropdownMenuItem(
                          value: o.value,
                          child: Text(o.label),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _notifyBefore = v);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
