import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cloud/cloud_service.dart';
import '../currency.dart';

/// Веб-вкладка «Услуги»: каталог услуг мастера/салона из облака.
/// Цена и длительность подтягиваются в заявки клиентов.
class ProviderServicesTab extends StatefulWidget {
  const ProviderServicesTab({super.key});

  @override
  State<ProviderServicesTab> createState() => _ProviderServicesTabState();
}

class _ProviderServicesTabState extends State<ProviderServicesTab> {
  final _cloud = CloudService();
  List<CloudServiceItem> _items = const [];
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
      final items = await _cloud.myServices();
      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _edit([CloudServiceItem? item]) async {
    final nameCtrl = TextEditingController(text: item?.name ?? '');
    final priceCtrl = TextEditingController(
      text: item == null || item.price == 0
          ? ''
          : item.price.toStringAsFixed(0),
    );
    final durCtrl = TextEditingController(
      text: '${item?.durationMinutes ?? 60}',
    );
    var published = item?.published ?? true;
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(item == null ? 'Новая услуга' : 'Услуга'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Название',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Введите название'
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: priceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Цена, ₸',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: durCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Минут',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) =>
                            (int.tryParse(v ?? '') ?? 0) <= 0 ? '≥ 1' : null,
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Видна клиентам'),
                  value: published,
                  onChanged: (v) => setDialogState(() => published = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(context).pop(true);
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    final name = nameCtrl.text.trim();
    final price = double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0;
    final duration = int.tryParse(durCtrl.text) ?? 60;
    nameCtrl.dispose();
    priceCtrl.dispose();
    durCtrl.dispose();
    if (saved != true) return;
    try {
      if (item == null) {
        await _cloud.addService(
          name: name,
          price: price,
          durationMinutes: duration,
          published: published,
        );
      } else {
        await _cloud.updateService(
          CloudServiceItem(
            id: item.id,
            masterId: item.masterId,
            name: name,
            price: price,
            durationMinutes: duration,
            published: published,
          ),
        );
      }
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить услугу')),
      );
    }
  }

  Future<void> _toggle(CloudServiceItem item, bool published) async {
    try {
      await _cloud.updateService(item.copyWith(published: published));
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось обновить услугу')),
      );
    }
  }

  Widget _serviceCard(CloudServiceItem s) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: const Icon(Icons.spa_outlined),
        ),
        title: Text(s.name),
        subtitle: Text(
          '${formatMoney(s.price)} · ${s.durationMinutes} мин · '
          '${s.published ? 'видна клиентам' : 'скрыта'}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Свитч публикации: «Видна» — услуга в каталоге клиентов,
            // «Скрыта» — клиенты её не видят и записаться не могут.
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: s.published
                      ? 'Скрыть от клиентов'
                      : 'Показывать клиентам в каталоге',
                  child: Switch(
                    value: s.published,
                    onChanged: (v) => _toggle(s, v),
                  ),
                ),
                Text(
                  s.published ? 'Видна' : 'Скрыта',
                  style: TextStyle(
                    fontSize: 10,
                    color: s.published
                        ? Colors.green.shade700
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') _edit(s);
                if (v == 'del') _delete(s);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('Изменить')),
                PopupMenuItem(value: 'del', child: Text('Удалить')),
              ],
            ),
          ],
        ),
        onTap: () => _edit(s),
      ),
    );
  }

  Future<void> _delete(CloudServiceItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить услугу?'),
        content: Text('«${item.name}» исчезнет из каталога клиентов.'),
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
      await _cloud.deleteService(item.id);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось удалить услугу')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'service_add',
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Услуга'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Не удалось загрузить услуги'),
                  TextButton(onPressed: _load, child: const Text('Повторить')),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Text(
                            'Нет услуг.\nНажмите «Услуга», чтобы добавить первую.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    )
                  : LayoutBuilder(
                      builder: (context, bc) {
                        // Широкий экран (режим сайта) — услуги
                        // сеткой в 2–3 колонки, а не одной лентой.
                        final cols = bc.maxWidth > 1500
                            ? 3
                            : bc.maxWidth > 860
                            ? 2
                            : 1;
                        if (cols == 1) {
                          return ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                            itemCount: _items.length,
                            itemBuilder: (context, i) =>
                                _serviceCard(_items[i]),
                          );
                        }
                        final w = (bc.maxWidth - 24 - (cols - 1) * 12) / cols;
                        return SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                          child: Wrap(
                            spacing: 12,
                            children: [
                              for (final s in _items)
                                SizedBox(width: w, child: _serviceCard(s)),
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

/// Веб-вкладка «Клиенты»: облачный справочник клиентов провайдера.
class ProviderClientsTab extends StatefulWidget {
  const ProviderClientsTab({super.key});

  @override
  State<ProviderClientsTab> createState() => _ProviderClientsTabState();
}

class _ProviderClientsTabState extends State<ProviderClientsTab> {
  final _cloud = CloudService();
  final _searchCtrl = TextEditingController();
  List<CloudClient> _items = const [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final items = await _cloud.myClients();
      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _edit([CloudClient? item]) async {
    final nameCtrl = TextEditingController(text: item?.name ?? '');
    final phoneCtrl = TextEditingController(text: item?.phone ?? '');
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item == null ? 'Новый клиент' : 'Клиент'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Имя',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Введите имя' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Телефон',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    final name = nameCtrl.text.trim();
    final phone = phoneCtrl.text.trim();
    nameCtrl.dispose();
    phoneCtrl.dispose();
    if (saved != true) return;
    try {
      if (item == null) {
        await _cloud.addClient(name: name, phone: phone);
      } else {
        await _cloud.updateClient(
          CloudClient(
            id: item.id,
            masterId: item.masterId,
            name: name,
            phone: phone,
          ),
        );
      }
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить клиента')),
      );
    }
  }

  Future<void> _delete(CloudClient item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить клиента?'),
        content: Text('«${item.name}» исчезнет из справочника.'),
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
      await _cloud.deleteClient(item.id);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось удалить клиента')),
      );
    }
  }

  Future<void> _call(CloudClient c) async {
    if (c.phone.isEmpty) return;
    await launchUrl(Uri.parse('tel:${c.phone}'));
  }

  Widget _clientCard(CloudClient c) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase()),
        ),
        title: Text(c.name.isEmpty ? 'Клиент' : c.name),
        subtitle: c.phone.isEmpty ? null : Text(c.phone),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (c.phone.isNotEmpty)
              IconButton(
                tooltip: 'Позвонить',
                icon: const Icon(Icons.call_outlined),
                onPressed: () => _call(c),
              ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') _edit(c);
                if (v == 'del') _delete(c);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('Изменить')),
                PopupMenuItem(value: 'del', child: Text('Удалить')),
              ],
            ),
          ],
        ),
        onTap: () => _edit(c),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _items
        : _items
              .where(
                (c) =>
                    c.name.toLowerCase().contains(query) ||
                    c.phone.toLowerCase().contains(query),
              )
              .toList();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'client_add',
        onPressed: () => _edit(),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Клиент'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Поиск по имени или телефону',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
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
                        const Text('Не удалось загрузить клиентов'),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: filtered.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 120),
                              Center(
                                child: Text(
                                  'Клиентов пока нет.\nОни появятся после записей '
                                  'или добавьте вручную.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          )
                        : LayoutBuilder(
                            builder: (context, bc) {
                              // Широкий экран (режим сайта) —
                              // сетка в 2–3 колонки.
                              final cols = bc.maxWidth > 1500
                                  ? 3
                                  : bc.maxWidth > 860
                                  ? 2
                                  : 1;
                              if (cols == 1) {
                                return ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    4,
                                    12,
                                    88,
                                  ),
                                  itemCount: filtered.length,
                                  itemBuilder: (context, i) =>
                                      _clientCard(filtered[i]),
                                );
                              }
                              final w =
                                  (bc.maxWidth - 24 - (cols - 1) * 12) / cols;
                              return SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  4,
                                  12,
                                  88,
                                ),
                                child: Wrap(
                                  spacing: 12,
                                  children: [
                                    for (final c in filtered)
                                      SizedBox(width: w, child: _clientCard(c)),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Веб-вкладка мастера «Приглашения»: заявки салонов в команду.
/// На телефоне это «Мои дела» (локальные задачи) — в браузере
/// их нет, зато здесь видно и принимаются приглашения салонов.
class ProviderInvitesTab extends StatefulWidget {
  const ProviderInvitesTab({super.key, this.onChanged});

  final VoidCallback? onChanged;

  @override
  State<ProviderInvitesTab> createState() => _ProviderInvitesTabState();
}

class _ProviderInvitesTabState extends State<ProviderInvitesTab> {
  final _cloud = CloudService();
  List<TeamInvite> _items = const [];
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
      final items = await _cloud.myTeamInvites();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
      widget.onChanged?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _respond(TeamInvite invite, bool accept) async {
    try {
      await _cloud.respondTeamInvite(invite, accept);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept ? 'Вы в команде салона' : 'Приглашение отклонено',
          ),
        ),
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Не удалось ответить')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _items.where((i) => i.status == 'pending').toList();
    final answered = _items.where((i) => i.status != 'pending').toList();
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : _failed
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Не удалось загрузить приглашения'),
                TextButton(onPressed: _load, child: const Text('Повторить')),
              ],
            ),
          )
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 120),
                    child: Center(
                      child: Text(
                        'Приглашений нет.\nСалон приглашает мастера по ключу '
                        'или поиском — заявки появятся здесь.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                for (final inv in pending)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.storefront_outlined),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  inv.otherName.isEmpty
                                      ? 'Салон'
                                      : inv.otherName,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Приглашает вас в команду',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: () => _respond(inv, true),
                                icon: const Icon(Icons.check, size: 18),
                                label: const Text('Принять'),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: () => _respond(inv, false),
                                icon: const Icon(Icons.close, size: 18),
                                label: const Text('Отклонить'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                if (answered.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'История',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  for (final inv in answered)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        inv.status == 'accepted'
                            ? Icons.check_circle_outline
                            : Icons.cancel_outlined,
                        color: inv.status == 'accepted'
                            ? Colors.green
                            : Colors.grey,
                      ),
                      title: Text(
                        inv.otherName.isEmpty ? 'Салон' : inv.otherName,
                      ),
                      subtitle: Text(
                        inv.status == 'accepted' ? 'Вы в команде' : 'Отклонено',
                      ),
                    ),
                ],
              ],
            ),
          );
  }
}

/// Салон на вебе: нижняя часть экрана «Мастера» — вместо
/// локального справочника кнопка создания аккаунта мастера.
class WebTeamDirectory extends StatelessWidget {
  const WebTeamDirectory({super.key, required this.onAddMaster});

  final VoidCallback onAddMaster;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  'Мастер ещё не зарегистрирован?',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  'Создайте ему аккаунт сами — логин и пароль '
                  'придумываете вы, мастер просто войдёт в приложение.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: onAddMaster,
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Создать аккаунт мастера'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Диалог «Новая запись» — ручная запись провайдера (клиент пришёл
/// по телефону/вживую). Пишется в master_appointments и синхронно
/// видна в мобильном приложении.
Future<CloudMasterAppointment?> showWebAppointmentDialog(
  BuildContext context, {
  required bool isSalon,
  required String providerName,
  CloudMasterAppointment? existing,
}) async {
  final cloud = CloudService();
  List<CloudServiceItem> services = const [];
  List<MasterCard> team = const [];
  try {
    final results = await Future.wait<dynamic>([
      cloud.myServices(),
      if (isSalon) cloud.salonMasters(),
    ]);
    services = results[0] as List<CloudServiceItem>;
    if (isSalon) team = results[1] as List<MasterCard>;
  } catch (_) {}

  if (!context.mounted) return null;
  return showDialog<CloudMasterAppointment>(
    context: context,
    builder: (context) => _WebAppointmentDialog(
      isSalon: isSalon,
      providerName: providerName,
      services: services,
      team: team,
      existing: existing,
    ),
  );
}

class _WebAppointmentDialog extends StatefulWidget {
  const _WebAppointmentDialog({
    required this.isSalon,
    required this.providerName,
    required this.services,
    required this.team,
    this.existing,
  });

  final bool isSalon;
  final String providerName;
  final List<CloudServiceItem> services;
  final List<MasterCard> team;
  final CloudMasterAppointment? existing;

  @override
  State<_WebAppointmentDialog> createState() => _WebAppointmentDialogState();
}

class _WebAppointmentDialogState extends State<_WebAppointmentDialog> {
  final _cloud = CloudService();
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController(
    text: widget.existing?.clientName ?? '',
  );
  late final _phoneCtrl = TextEditingController(
    text: widget.existing?.clientPhone ?? '',
  );
  late final _notesCtrl = TextEditingController(
    text: widget.existing?.notes ?? '',
  );
  late final _priceCtrl = TextEditingController(
    text: widget.existing == null || widget.existing!.servicePrice == 0
        ? ''
        : widget.existing!.servicePrice.toStringAsFixed(0),
  );
  late final _durCtrl = TextEditingController(
    text: '${widget.existing?.durationMinutes ?? 60}',
  );
  CloudServiceItem? _service;
  MasterCard? _master;
  late DateTime _date = widget.existing?.startsAt ?? DateTime.now();
  late TimeOfDay _time = TimeOfDay.fromDateTime(
    widget.existing?.startsAt ?? DateTime.now().add(const Duration(hours: 1)),
  );
  bool _saving = false;
  String? _error;

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ru'),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
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
    final masterName = widget.isSalon
        ? (_master?.name ?? '')
        : widget.providerName;
    final serviceName = _service?.name ?? '';
    try {
      final price = double.tryParse(_priceCtrl.text.replaceAll(',', '.')) ?? 0;
      final duration = int.tryParse(_durCtrl.text) ?? 60;
      final existing = widget.existing;
      final saved = existing == null
          ? await _cloud.addMasterAppointment(
              clientName: _nameCtrl.text.trim(),
              clientPhone: _phoneCtrl.text.trim(),
              serviceName: serviceName,
              masterName: masterName,
              startsAt: startsAt,
              durationMinutes: duration,
              servicePrice: price,
              notes: _notesCtrl.text.trim(),
            )
          : await _cloud.updateMasterAppointment(
              CloudMasterAppointment(
                id: existing.id,
                masterId: existing.masterId,
                clientName: _nameCtrl.text.trim(),
                clientPhone: _phoneCtrl.text.trim(),
                serviceName: serviceName,
                masterName: masterName,
                startsAt: startsAt,
                durationMinutes: duration,
                servicePrice: price,
                notes: _notesCtrl.text.trim(),
              ),
            );
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Не удалось сохранить: $e';
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    _priceCtrl.dispose();
    _durCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Новая запись' : 'Запись'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Имя клиента',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Введите имя' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Телефон',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<CloudServiceItem>(
                  initialValue: _service,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Услуга',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final s in widget.services)
                      DropdownMenuItem(value: s, child: Text(s.name)),
                  ],
                  onChanged: (s) => setState(() {
                    _service = s;
                    if (s != null) {
                      _priceCtrl.text = s.price.toStringAsFixed(0);
                      _durCtrl.text = '${s.durationMinutes}';
                    }
                  }),
                  validator: (v) => v == null ? 'Выберите услугу' : null,
                ),
                if (widget.isSalon && widget.team.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<MasterCard>(
                    initialValue: _master,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Мастер',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final m in widget.team)
                        DropdownMenuItem(
                          value: m,
                          child: Text(m.name.isEmpty ? 'Мастер' : m.name),
                        ),
                    ],
                    onChanged: (m) => setState(() => _master = m),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(_fmtDate(_date)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickTime,
                        icon: const Icon(Icons.schedule, size: 16),
                        label: Text(_time.format(context)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _durCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Минут',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _priceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Цена, ₸',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Заметка',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}

/// Маленькая кнопка копирования — телефон/текст в буфер.
Future<void> copyText(BuildContext context, String text, String label) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label скопирован')));
  }
}
