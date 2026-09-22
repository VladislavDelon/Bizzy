import 'package:bizzy_app/cloud/cloud_service.dart';
import 'package:bizzy_app/cloud/work_hours.dart';
import 'package:flutter/material.dart';

/// Мастер настройки для новых мастеров и салонов:
/// виды услуг → услуги → адрес/описание → рабочие часы.
/// Каждый шаг можно пропустить — «Пропустить всё» выходит сразу.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.isSalon});

  final bool isSalon;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _cloud = CloudService();
  final _page = PageController();
  int _step = 0;
  bool _saving = false;

  // Шаг 1: виды услуг.
  List<String> _allCategories = [];
  final Set<String> _pickedCategories = {};

  // Шаг 2: услуги.
  final List<({String name, double price, int duration})> _services = [];

  // Шаг 3: адрес и описание.
  final _address = TextEditingController();
  final _desc = TextEditingController();

  // Шаг 4: рабочие часы.
  final WorkWeek _week = WorkWeek();

  static const _stepCount = 4;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _page.dispose();
    _address.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await _cloud.categories();
      if (mounted) setState(() => _allCategories = cats);
    } catch (_) {}
  }

  /// Сохраняет текущий шаг (если там есть что сохранять) и идёт дальше.
  Future<void> _next({bool skip = false}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (!skip) await _saveStep(_step);
      if (_step >= _stepCount - 1) {
        await _finish();
        return;
      }
      setState(() {
        _step++;
        _saving = false;
      });
      _page.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить — попробуйте ещё')),
      );
    }
  }

  /// Сохраняет данные конкретного шага. Пустой шаг просто пропускается.
  Future<void> _saveStep(int step) async {
    switch (step) {
      case 0:
        if (_pickedCategories.isNotEmpty) {
          await _cloud.patchMasterProfile({
            'category': _pickedCategories.first,
            'categories': _pickedCategories.toList(),
          });
        }
      case 1:
        for (final s in _services) {
          await _cloud.addService(
            name: s.name,
            price: s.price,
            durationMinutes: s.duration,
          );
        }
        _services.clear();
      case 2:
        final address = _address.text.trim();
        final desc = _desc.text.trim();
        if (address.isNotEmpty || desc.isNotEmpty) {
          await _cloud.patchMasterProfile({
            if (address.isNotEmpty) 'address': address,
            if (desc.isNotEmpty) 'description': desc,
          });
        }
      case 3:
        if (_week.isConfigured) {
          await _cloud.saveWorkHours(_week.toJson());
        }
    }
  }

  /// «Пропустить всё» / финиш: помечаем онбординг пройденным и выходим.
  Future<void> _finish() async {
    try {
      await _cloud.markOnboarded();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _addService() async {
    final name = TextEditingController();
    final price = TextEditingController();
    final duration = TextEditingController(text: '60');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новая услуга'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(
                labelText: 'Название',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Цена',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: duration,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Длительность, мин',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty && mounted) {
      setState(
        () => _services.add((
          name: name.text.trim(),
          price: double.tryParse(price.text.trim()) ?? 0,
          duration: int.tryParse(duration.text.trim()) ?? 60,
        )),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final who = widget.isSalon ? 'салона' : 'мастера';
    return Scaffold(
      appBar: AppBar(
        title: Text('Настройка $who'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _finish,
            child: const Text('Пропустить всё'),
          ),
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(value: (_step + 1) / _stepCount),
          Expanded(
            child: PageView(
              controller: _page,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _stepCategories(),
                _stepServices(),
                _stepAddress(),
                _stepHours(),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => _next(skip: true),
                    child: const Text('Пропустить'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving ? null : () => _next(),
                    child: Text(_step >= _stepCount - 1 ? 'Готово' : 'Далее'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepHeader(String title, String subtitle) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );

  Widget _stepCategories() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _stepHeader(
          'Чем вы занимаетесь?',
          'Клиенты найдут вас в поиске по каждому виду услуг.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final c in _allCategories)
              FilterChip(
                label: Text(c),
                selected: _pickedCategories.contains(c),
                onSelected: (v) => setState(
                  () => v
                      ? _pickedCategories.add(c)
                      : _pickedCategories.remove(c),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _stepServices() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _stepHeader(
          'Ваши услуги',
          'Название, цена и длительность — то, что видит клиент при записи.',
        ),
        for (var i = 0; i < _services.length; i++)
          Card(
            child: ListTile(
              title: Text(_services[i].name),
              subtitle: Text(
                '${_services[i].price.toStringAsFixed(0)} • ${_services[i].duration} мин',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _services.removeAt(i)),
              ),
            ),
          ),
        TextButton.icon(
          onPressed: _addService,
          icon: const Icon(Icons.add),
          label: const Text('Добавить услугу'),
        ),
      ],
    );
  }

  Widget _stepAddress() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _stepHeader(
          'Где вы принимаете?',
          'Адрес и пара слов о себе — это увидят клиенты в профиле.',
        ),
        TextField(
          controller: _address,
          decoration: const InputDecoration(
            labelText: 'Адрес',
            hintText: 'Город, улица, дом',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _desc,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'О себе',
            hintText: 'Опыт, подход, особенности',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _stepHours() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _stepHeader(
          'Рабочие часы',
          'Клиенты смогут записаться только внутри этих окон.',
        ),
        WorkHoursEditor(week: _week, onChanged: () => setState(() {})),
      ],
    );
  }
}
