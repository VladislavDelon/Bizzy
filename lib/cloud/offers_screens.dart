import 'package:flutter/material.dart';

import 'cloud_service.dart';

/// Управление «Honey» у салона/мастера: список своих предложений,
/// создание, включение/выключение, удаление.
class SalonOffersScreen extends StatefulWidget {
  const SalonOffersScreen({super.key});

  @override
  State<SalonOffersScreen> createState() => _SalonOffersScreenState();
}

class _SalonOffersScreenState extends State<SalonOffersScreen> {
  final _cloud = CloudService();
  List<SalonOffer> _offers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final offers = await _cloud.myOffers();
      if (!mounted) return;
      setState(() {
        _offers = offers;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _createOffer() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => const _OfferEditDialog(),
    );
    if (created == true) await _load();
  }

  Future<void> _toggle(SalonOffer offer) async {
    try {
      await _cloud.setOfferActive(offer.id, !offer.active);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось обновить: $e')),
      );
    }
  }

  Future<void> _delete(SalonOffer offer) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить «${offer.title}»?'),
        content: const Text('Предложение исчезнет из «Honey» у клиентов.'),
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
      await _cloud.deleteOffer(offer.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Honey')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: _createOffer,
        icon: const Icon(Icons.add),
        label: const Text('Создать Honey'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off, size: 40),
                        const SizedBox(height: 8),
                        Text(
                          'Не удалось загрузить предложения.\n$_error',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () {
                            setState(() => _loading = true);
                            _load();
                          },
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
                        child: Text(
                          'Скидки, сертификаты и бонусы, которые клиенты '
                          'видят во вкладке «Honey».',
                        ),
                      ),
                      if (_offers.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: Text(
                              'Предложений пока нет.\n'
                              'Нажмите «Создать Honey», чтобы добавить первое —\n'
                              'например, «Скидка на первое посещение».',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      for (final o in _offers)
                        Card(
                          child: ListTile(
                            leading: Icon(
                              Icons.card_giftcard,
                              color: o.active
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).disabledColor,
                            ),
                            title: Text(o.title),
                            subtitle: Text(
                              [
                                if (o.value.isNotEmpty) o.value,
                                if (o.description.isNotEmpty) o.description,
                                if (!o.active) 'выключено',
                              ].join(' · '),
                            ),
                            trailing: Switch(
                              value: o.active,
                              onChanged: (_) => _toggle(o),
                            ),
                            onLongPress: () => _delete(o),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

/// Диалог создания предложения «Honey».
class _OfferEditDialog extends StatefulWidget {
  const _OfferEditDialog();

  @override
  State<_OfferEditDialog> createState() => _OfferEditDialogState();
}

class _OfferEditDialogState extends State<_OfferEditDialog> {
  final _title = TextEditingController();
  final _value = TextEditingController();
  final _description = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _value.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название предложения')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await CloudService().createOffer(
        title: title,
        value: _value.text.trim(),
        description: _description.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось создать: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новое Honey'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Название',
                hintText: 'Скидка на первое посещение',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _value,
              decoration: const InputDecoration(
                labelText: 'Выгода',
                hintText: '−20% · 500 ₸ · сертификат',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Описание (необязательно)',
                hintText: 'Действует на все услуги при первой записи',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Создать'),
        ),
      ],
    );
  }
}

/// Вкладка «Honey» у клиента — витрина активных предложений
/// от салонов и мастеров: сертификаты, скидки, бонусы.
class ClientHoneyTab extends StatefulWidget {
  const ClientHoneyTab({super.key, this.onBookProvider});

  /// Открыть запись к салону/мастеру, который дал предложение —
  /// передаётся из ClientHome, чтобы не тянуть сюда каталог.
  final void Function(String providerId)? onBookProvider;

  @override
  State<ClientHoneyTab> createState() => _ClientHoneyTabState();
}

class _ClientHoneyTabState extends State<ClientHoneyTab> {
  final _cloud = CloudService();
  List<SalonOffer> _offers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final offers = await _cloud.activeOffers();
      if (!mounted) return;
      setState(() {
        _offers = offers;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// Карточка предложения во весь экран-шторку: вся информация
  /// и кнопка «Записаться» к этому салону.
  Future<void> _openOffer(SalonOffer offer) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.card_giftcard,
                      color: Theme.of(sheetContext).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        offer.providerName.isNotEmpty
                            ? offer.providerName
                            : 'Салон',
                        style:
                            Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                    ),
                    if (offer.value.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(sheetContext)
                              .colorScheme
                              .primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          offer.value,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  offer.title,
                  style: Theme.of(sheetContext).textTheme.headlineSmall,
                ),
                if (offer.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    offer.description,
                    style: Theme.of(sheetContext).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: widget.onBookProvider == null
                        ? null
                        : () {
                            Navigator.of(sheetContext).pop();
                            widget.onBookProvider!(offer.providerId);
                          },
                    icon: const Icon(Icons.event_available),
                    label: const Text('Записаться'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Honey')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off, size: 40),
                        const SizedBox(height: 8),
                        Text(
                          'Не удалось загрузить предложения.\n$_error',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () {
                            setState(() => _loading = true);
                            _load();
                          },
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _offers.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.all(32),
                          children: const [
                            SizedBox(height: 80),
                            Icon(
                              Icons.card_giftcard_outlined,
                              size: 56,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Здесь будут плюшки от салонов:\n'
                              'скидки на первое посещение, сертификаты, '
                              'бонусы.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                          children: [
                            for (final o in _offers)
                              Card(
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () => _openOffer(o),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.card_giftcard,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              o.providerName.isNotEmpty
                                                  ? o.providerName
                                                  : 'Салон',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelLarge,
                                            ),
                                          ),
                                          if (o.value.isNotEmpty)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primaryContainer,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                o.value,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        o.title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      if (o.description.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(o.description),
                                      ],
                                    ],
                                  ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
    );
  }
}
