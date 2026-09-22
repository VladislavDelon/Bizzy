import 'package:bizzy_app/cloud/cloud_service.dart';
import 'package:bizzy_app/currency.dart';
import 'package:flutter/material.dart';

/// «Статистика» для мастера и салона: выручка, топ-услуги,
/// разбивка по мастерам — считается по облачным заявкам,
/// поэтому у салона видны и дела команды.
class ProviderStatsScreen extends StatefulWidget {
  const ProviderStatsScreen({super.key, required this.isSalon});

  final bool isSalon;

  @override
  State<ProviderStatsScreen> createState() => _ProviderStatsScreenState();
}

enum _Period { week, month, all }

class _ProviderStatsScreenState extends State<ProviderStatsScreen> {
  final _cloud = CloudService();
  List<CloudBooking> _bookings = [];
  bool _loading = true;
  bool _failed = false;
  _Period _period = _Period.month;

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
      final bookings = widget.isSalon
          ? await _cloud.salonBookings()
          : await _cloud.masterBookings();
      if (!mounted) return;
      setState(() {
        _bookings = bookings;
        _loading = false;
      });
    } catch (e, st) {
      await SyncLog.write('providerStats', '$e\n$st');
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  DateTime? get _from {
    final now = DateTime.now();
    return switch (_period) {
      _Period.week => now.subtract(const Duration(days: 7)),
      _Period.month => DateTime(now.year, now.month - 1, now.day),
      _Period.all => null,
    };
  }

  /// Завершённые заявки за период — это и есть «сделанные».
  List<CloudBooking> get _done {
    final now = DateTime.now();
    final from = _from;
    return _bookings
        .where(
          (b) =>
              b.status == 'completed' &&
              b.startsAt.isBefore(now) &&
              (from == null || !b.startsAt.isBefore(from)),
        )
        .toList();
  }

  List<CloudBooking> get _upcoming {
    final now = DateTime.now();
    return _bookings
        .where(
          (b) =>
              (b.status == 'confirmed' || b.status == 'pending') &&
              b.startsAt.isAfter(now),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = _done;
    final revenue = done.fold<double>(0, (s, b) => s + b.servicePrice);
    final avgCheck = done.isEmpty ? 0.0 : revenue / done.length;
    final upcoming = _upcoming;

    // Топ-5 услуг по количеству.
    final byService = <String, ({int count, double sum})>{};
    for (final b in done) {
      final cur = byService[b.serviceName] ?? (count: 0, sum: 0.0);
      byService[b.serviceName] = (
        count: cur.count + 1,
        sum: cur.sum + b.servicePrice,
      );
    }
    final topServices = byService.entries.toList()
      ..sort((a, b) => b.value.count.compareTo(a.value.count));

    // По мастерам — у салона.
    final byMaster = <String, ({int count, double sum})>{};
    if (widget.isSalon) {
      for (final b in done) {
        final key = b.masterName.isEmpty ? 'Мастер' : b.masterName;
        final cur = byMaster[key] ?? (count: 0, sum: 0.0);
        byMaster[key] = (count: cur.count + 1, sum: cur.sum + b.servicePrice);
      }
    }
    final masters = byMaster.entries.toList()
      ..sort((a, b) => b.value.sum.compareTo(a.value.sum));

    return Scaffold(
      appBar: AppBar(title: const Text('Статистика')),
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
                Row(
                  children: [
                    for (final p in _Period.values) ...[
                      ChoiceChip(
                        label: Text(switch (p) {
                          _Period.week => 'Неделя',
                          _Period.month => 'Месяц',
                          _Period.all => 'Всё время',
                        }),
                        selected: _period == p,
                        onSelected: (_) => setState(() => _period = p),
                      ),
                      if (p != _Period.values.last) const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _statCard(
                      context,
                      'Выручка',
                      formatMoney(revenue),
                      Icons.payments_outlined,
                    ),
                    const SizedBox(width: 8),
                    _statCard(
                      context,
                      'Записей',
                      '${done.length}',
                      Icons.event_available,
                    ),
                    const SizedBox(width: 8),
                    _statCard(
                      context,
                      'Средний чек',
                      formatMoney(avgCheck),
                      Icons.receipt_long,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.upcoming_outlined,
                      color: scheme.primary,
                    ),
                    title: const Text('Предстоящие записи'),
                    trailing: Text(
                      '${upcoming.length}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                if (topServices.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Топ услуг',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < topServices.length && i < 5; i++)
                          ListTile(
                            dense: true,
                            leading: Text(
                              '${i + 1}',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(color: scheme.primary),
                            ),
                            title: Text(topServices[i].key),
                            subtitle: Text(
                              '${topServices[i].value.count} записей',
                            ),
                            trailing: Text(
                              formatMoney(topServices[i].value.sum),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (masters.length > 1) ...[
                  const SizedBox(height: 16),
                  Text(
                    'По мастерам',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Card(
                    child: Column(
                      children: [
                        for (final m in masters)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.person_outline),
                            title: Text(m.key),
                            subtitle: Text('${m.value.count} записей'),
                            trailing: Text(formatMoney(m.value.sum)),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _statCard(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(height: 6),
              Text(
                value,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
