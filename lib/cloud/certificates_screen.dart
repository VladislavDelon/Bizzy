import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../currency.dart';
import 'cloud_service.dart';

/// Сертификаты провайдера: выданные клиентам пакеты визитов,
/// остаток, отключение и удаление.
class ProviderCertificatesScreen extends StatefulWidget {
  const ProviderCertificatesScreen({super.key});

  @override
  State<ProviderCertificatesScreen> createState() =>
      _ProviderCertificatesScreenState();
}

class _ProviderCertificatesScreenState
    extends State<ProviderCertificatesScreen> {
  final _cloud = CloudService();
  List<Certificate> _certs = const [];
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
      final certs = await _cloud.certificatesIssued();
      if (!mounted) return;
      setState(() {
        _certs = certs;
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

  Future<void> _toggle(Certificate c) async {
    try {
      await _cloud.setCertificateActive(c.id, !c.active);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось обновить сертификат')),
      );
    }
  }

  Future<void> _delete(Certificate c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить сертификат?'),
        content: Text(
          '«${c.title}» — клиент ${c.clientName.isEmpty ? '' : c.clientName} '
          'потеряет оставшиеся ${c.remaining} визитов.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _cloud.deleteCertificate(c.id);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Не удалось удалить')));
    }
  }

  /// Выдать сертификат прямо с экрана: выбираем клиента
  /// из тех, кто уже записывался к нам (мастеру — свои заявки,
  /// салону — салонные).
  Future<void> _issue() async {
    final client = await showModalBottomSheet<({String id, String name})>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => const _CertClientPicker(),
    );
    if (client == null || !mounted) return;
    final issued = await showIssueCertificateDialog(
      context,
      clientId: client.id,
      clientName: client.name,
    );
    if (issued == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Сертификаты')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: _issue,
        icon: const Icon(Icons.card_giftcard),
        label: const Text('Выдать'),
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
          : _certs.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Сертификатов пока нет.\nНажмите «Выдать» и выберите '
                  'клиента — он получит пакет визитов.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: _certs.length,
              itemBuilder: (context, i) {
                final c = _certs[i];
                return Card(
                  child: ListTile(
                    leading: Icon(
                      c.exhausted
                          ? Icons.card_giftcard_outlined
                          : Icons.card_giftcard,
                      color: c.active ? scheme.primary : scheme.outline,
                    ),
                    title: Text(c.title),
                    subtitle: Text(
                      '${c.clientName.isEmpty ? 'Клиент' : c.clientName} · '
                      'осталось ${c.remaining} из ${c.totalVisits}'
                      '${c.price > 0 ? ' · ${formatMoney(c.price)}' : ''}'
                      '${c.active ? '' : ' · отключён'}',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'toggle') _toggle(c);
                        if (v == 'delete') _delete(c);
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'toggle',
                          child: Text(
                            c.active ? 'Отключить' : 'Включить снова',
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Удалить'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Диалог выдачи сертификата клиенту из карточки клиента.
/// Возвращает true при успешной выдаче.
Future<bool?> showIssueCertificateDialog(
  BuildContext context, {
  required String clientId,
  required String clientName,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) =>
        _IssueCertificateDialog(clientId: clientId, clientName: clientName),
  );
}

class _IssueCertificateDialog extends StatefulWidget {
  const _IssueCertificateDialog({
    required this.clientId,
    required this.clientName,
  });

  final String clientId;
  final String clientName;

  @override
  State<_IssueCertificateDialog> createState() =>
      _IssueCertificateDialogState();
}

class _IssueCertificateDialogState extends State<_IssueCertificateDialog> {
  final _cloud = CloudService();
  final _title = TextEditingController(text: 'Абонемент');
  final _visits = TextEditingController(text: '5');
  final _price = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _visits.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final visits = int.tryParse(_visits.text.trim()) ?? 0;
    if (visits <= 0) {
      setState(() => _error = 'Укажите число визитов');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _cloud.createCertificate(
        clientId: widget.clientId,
        title: _title.text.trim().isEmpty ? 'Сертификат' : _title.text.trim(),
        totalVisits: visits,
        price: double.tryParse(_price.text.trim().replaceAll(',', '.')) ?? 0,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Не удалось выдать сертификат';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Сертификат — ${widget.clientName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Название',
              hintText: 'Например: Абонемент на стрижки',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _visits,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Количество визитов',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Цена пакета (необязательно)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Клиент будет оплачивать записи этим пакетом — '
            'каждая запись спишет один визит.',
            style: Theme.of(context).textTheme.bodySmall,
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
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Выдаю…' : 'Выдать'),
        ),
      ],
    );
  }
}

/// Выбор клиента для выдачи сертификата: уникальные клиенты
/// из облачных записей провайдера (мастер — свои, салон — салонные).
class _CertClientPicker extends StatefulWidget {
  const _CertClientPicker();

  @override
  State<_CertClientPicker> createState() => _CertClientPickerState();
}

class _CertClientPickerState extends State<_CertClientPicker> {
  final _cloud = CloudService();
  List<({String id, String name})> _clients = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await _cloud.myProfile();
      final bookings = profile?.role == 'salon'
          ? await _cloud.salonBookings()
          : await _cloud.masterBookings();
      // Уникальные клиенты с аккаунтом — сертификат привязан к user id.
      final seen = <String, String>{};
      for (final b in bookings) {
        if (b.clientId.isNotEmpty) {
          seen[b.clientId] = b.clientName.isEmpty ? 'Клиент' : b.clientName;
        }
      }
      if (!mounted) return;
      setState(() {
        _clients = [
          for (final e in seen.entries) (id: e.key, name: e.value),
        ]..sort((a, b) => a.name.compareTo(b.name));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            )
          : _clients.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Пока нет клиентов с аккаунтом.\nСертификат можно '
                'выдать тому, кто уже записывался к вам.',
                textAlign: TextAlign.center,
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Кому выдать сертификат',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c in _clients)
                        ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person_outline),
                          ),
                          title: Text(c.name),
                          onTap: () => Navigator.of(context).pop(c),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// «Мои сертификаты» у клиента: пакеты визитов от мастеров/салонов.
class MyCertificatesScreen extends StatefulWidget {
  const MyCertificatesScreen({super.key});

  @override
  State<MyCertificatesScreen> createState() => _MyCertificatesScreenState();
}

class _MyCertificatesScreenState extends State<MyCertificatesScreen> {
  final _cloud = CloudService();
  List<Certificate> _certs = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final certs = await _cloud.myCertificates();
      if (!mounted) return;
      setState(() {
        _certs = certs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Мои сертификаты')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _certs.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Пока нет сертификатов.\nПакет визитов вам может '
                  'выдать мастер или салон.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _certs.length,
              itemBuilder: (context, i) {
                final c = _certs[i];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: c.exhausted
                          ? scheme.surfaceContainerHighest
                          : scheme.primaryContainer,
                      child: Icon(
                        Icons.card_giftcard,
                        color: c.exhausted
                            ? scheme.outline
                            : scheme.onPrimaryContainer,
                      ),
                    ),
                    title: Text(c.title),
                    subtitle: Text(
                      '${c.providerName.isEmpty ? 'Провайдер' : c.providerName} · '
                      'осталось ${c.remaining} из ${c.totalVisits} визитов'
                      '${c.active ? '' : ' · отключён'}',
                    ),
                    trailing: c.exhausted ? const Text('использован') : null,
                  ),
                );
              },
            ),
    );
  }
}
