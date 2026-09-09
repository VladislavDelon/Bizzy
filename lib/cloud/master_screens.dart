import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'cloud_service.dart';

/// Экран профиля мастера: категория, описание, рейтинг.
/// Показывается мастеру при первом входе и из «Ещё».
class MasterProfileScreen extends StatefulWidget {
  const MasterProfileScreen({super.key, this.isFirstSetup = false});

  /// true — показываем сразу после первого входа мастера.
  final bool isFirstSetup;

  @override
  State<MasterProfileScreen> createState() => _MasterProfileScreenState();
}

class _MasterProfileScreenState extends State<MasterProfileScreen> {
  final _cloud = CloudService();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _descController = TextEditingController();
  List<String> _categories = [];
  String? _category;
  double _ratingAvg = 0;
  int _ratingCount = 0;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final categories = await _cloud.categories();
      final profile = await _cloud.myProfile();
      final card = await _cloud.myMasterCard();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _nameController.text = profile?.name ?? '';
        _phoneController.text = profile?.phone ?? '';
        _category = card?.category ?? categories.firstOrNull;
        _descController.text = card?.description ?? '';
        _ratingAvg = card?.ratingAvg ?? 0;
        _ratingCount = card?.ratingCount ?? 0;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось загрузить профиль';
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_category == null) {
      setState(() => _error = 'Выберите категорию');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _cloud.updateMyProfile(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
      );
      await _cloud.upsertMasterProfile(
        category: _category!,
        description: _descController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профиль сохранён')),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Не удалось сохранить профиль';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isFirstSetup ? 'Профиль мастера' : 'Мой профиль мастера',
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.isFirstSetup)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Заполните профиль — так вас найдут клиенты '
                      'в каталоге Bizzy.',
                    ),
                  ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: scheme.primary,
                          child: Icon(Icons.star,
                              color: scheme.onPrimary, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _ratingAvg > 0
                                    ? _ratingAvg.toStringAsFixed(1)
                                    : '—',
                                style:
                                    Theme.of(context).textTheme.headlineSmall,
                              ),
                              Text(
                                _ratingCount == 0
                                    ? 'Оценок пока нет'
                                    : 'оценок: $_ratingCount',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Имя / название салона',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Телефон для клиентов',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Категория',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  isEmpty: _category == null,
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _category,
                      isExpanded: true,
                      isDense: true,
                      items: _categories
                          .map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Text(c),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _category = v),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'О себе',
                    hintText: 'Опыт, адрес, особенности…',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: scheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Сохранить'),
                ),
              ],
            ),
    );
  }
}

/// Экран «Заявки клиентов» — записи, которые клиенты
/// сделали к этому мастеру через облако.
class MasterBookingsScreen extends StatefulWidget {
  const MasterBookingsScreen({super.key});

  @override
  State<MasterBookingsScreen> createState() => _MasterBookingsScreenState();
}

class _MasterBookingsScreenState extends State<MasterBookingsScreen> {
  final _cloud = CloudService();
  List<CloudBooking> _bookings = [];
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
      final bookings = await _cloud.masterBookings();
      if (!mounted) return;
      setState(() => _bookings = bookings);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setStatus(CloudBooking b, String status) async {
    try {
      await _cloud.setBookingStatus(b.id, status);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось обновить статус')),
      );
    }
  }

  String _statusLabel(String status) => switch (status) {
        'pending' => 'Новая заявка',
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

  Future<void> _call(String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Заявки клиентов')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Не удалось загрузить заявки'),
                      TextButton(onPressed: _load, child: const Text('Повторить')),
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
                                'Заявок пока нет.\nКак только клиент запишется — '
                                'она появится здесь.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 88),
                          itemCount: _bookings.length,
                          itemBuilder: (context, index) {
                            final b = _bookings[index];
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
                                      '${b.clientName.isEmpty ? 'Клиент' : b.clientName}'
                                      '${b.clientPhone.isEmpty ? '' : ' • ${b.clientPhone}'}',
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_fmt(b.startsAt)} • ${b.durationMinutes} мин',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                    if (b.notes.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        b.notes,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        if (b.status == 'pending') ...[
                                          FilledButton.tonalIcon(
                                            onPressed: () =>
                                                _setStatus(b, 'confirmed'),
                                            icon: const Icon(Icons.check),
                                            label: const Text('Подтвердить'),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: () =>
                                                _setStatus(b, 'cancelled'),
                                            icon: const Icon(Icons.close),
                                            label: const Text('Отклонить'),
                                          ),
                                        ],
                                        if (b.status == 'confirmed') ...[
                                          FilledButton.tonalIcon(
                                            onPressed: () =>
                                                _setStatus(b, 'completed'),
                                            icon: const Icon(Icons.done_all),
                                            label: const Text('Завершить'),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: () =>
                                                _setStatus(b, 'cancelled'),
                                            icon: const Icon(Icons.close),
                                            label: const Text('Отменить'),
                                          ),
                                        ],
                                        if (b.clientPhone.isNotEmpty)
                                          IconButton(
                                            tooltip: 'Позвонить',
                                            onPressed: () =>
                                                _call(b.clientPhone),
                                            icon: const Icon(Icons.call),
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
