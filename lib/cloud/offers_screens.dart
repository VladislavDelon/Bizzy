import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../currency.dart';
import 'cloud_service.dart';
import 'fan_push.dart';

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
    if (created == true) {
      await _load();
      // Фанам (клиенты, добавившие нас в избранное) — push о новом Honey.
      await notifyFavoriteClients(
        title: 'Новое Honey',
        body: 'Ваш избранный мастер/салон опубликовал Honey — '
            'загляните во вкладку Honey',
      );
    }
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
                            leading: o.imageUrl.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      o.imageUrl,
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : Icon(
                                    Icons.card_giftcard,
                                    color: o.isLive
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).disabledColor,
                                  ),
                            title: Text(o.title),
                            subtitle: Text(
                              [
                                if (o.value.isNotEmpty) o.value,
                                if (o.discountPercent > 0)
                                  '−${_fmtNum(o.discountPercent)}%',
                                if (!o.allServices)
                                  'выбранные услуги',
                                _fmtValidity(o),
                                if (!o.active) 'выключено',
                                if (o.active && !o.isLive) 'срок истёк',
                              ]
                                  .where((e) => e.isNotEmpty)
                                  .join(' · '),
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
  final _cloud = CloudService();
  final _title = TextEditingController();
  final _value = TextEditingController();
  final _description = TextEditingController();
  final _discount = TextEditingController();
  final _link = TextEditingController();
  bool _busy = false;
  bool _allServices = true;
  final Set<int> _serviceIds = {};
  List<CloudServiceItem> _services = [];
  DateTime? _validFrom;
  DateTime? _validUntil;
  String? _imagePath;
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  Future<void> _loadServices() async {
    try {
      final services = await _cloud.myServices();
      if (!mounted) return;
      setState(() => _services = services);
    } catch (_) {}
  }

  @override
  void dispose() {
    _title.dispose();
    _value.dispose();
    _description.dispose();
    _discount.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (file == null || !mounted) return;
    setState(() => _imagePath = file.path);
  }

  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_validFrom ?? now) : (_validUntil ?? now),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      helpText: isFrom ? 'Действует с' : 'Действует до',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _validFrom = picked;
      } else {
        // «До» включает весь выбранный день.
        _validUntil = DateTime(picked.year, picked.month, picked.day, 23, 59);
      }
    });
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название предложения')),
      );
      return;
    }
    if (!_allServices && _serviceIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите хотя бы одну услугу')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      // Картинка-фон — заливаем в storage до создания записи.
      var imageUrl = _imageUrl ?? '';
      if (_imagePath != null) {
        imageUrl = await _cloud.uploadOfferImage(_imagePath!);
      }
      await _cloud.createOffer(
        title: title,
        value: _value.text.trim(),
        description: _description.text.trim(),
        imageUrl: imageUrl,
        linkUrl: _link.text.trim(),
        discountPercent: double.tryParse(_discount.text.trim()) ?? 0,
        allServices: _allServices,
        serviceIds: _allServices ? const [] : _serviceIds.toList(),
        validFrom: _validFrom,
        validUntil: _validUntil,
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
          crossAxisAlignment: CrossAxisAlignment.start,
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _value,
                    decoration: const InputDecoration(
                      labelText: 'Выгода',
                      hintText: '−20% · 500 ₸ · сертификат',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _discount,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Скидка, %',
                      hintText: '10',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Описание (необязательно)',
                hintText: 'Действует при первой записи',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _link,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Ссылка (необязательно)',
                hintText: 'https://instagram.com/…',
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 12),
            // Картинка-фон для рекламы процедуры.
            OutlinedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.image_outlined),
              label: Text(
                _imagePath == null ? 'Фото-фон (необязательно)' : 'Заменить фото',
              ),
            ),
            if (_imagePath != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(_imagePath!),
                  height: 110,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            const SizedBox(height: 8),
            // На все услуги или только на выбранные.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('На все услуги'),
              subtitle: const Text('Выключите, чтобы выбрать конкретные'),
              value: _allServices,
              onChanged: (v) => setState(() => _allServices = v),
            ),
            if (!_allServices)
              _services.isEmpty
                  ? const Text('У вас пока нет услуг в каталоге')
                  : Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final s in _services)
                          FilterChip(
                            label: Text(s.name),
                            selected: _serviceIds.contains(s.id),
                            onSelected: (sel) => setState(() {
                              if (sel) {
                                _serviceIds.add(s.id);
                              } else {
                                _serviceIds.remove(s.id);
                              }
                            }),
                          ),
                      ],
                    ),
            const Divider(height: 20),
            // Срок действия: с… по… — по истечении Honey сам
            // исчезает из витрины.
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(true),
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(
                      _validFrom == null ? 'С…' : 'с ${_fmtDate(_validFrom!)}',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(false),
                    icon: const Icon(Icons.event_busy, size: 18),
                    label: Text(
                      _validUntil == null
                          ? 'По…'
                          : 'по ${_fmtDate(_validUntil!)}',
                    ),
                  ),
                ),
              ],
            ),
            if (_validFrom != null || _validUntil != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() {
                    _validFrom = null;
                    _validUntil = null;
                  }),
                  child: const Text('Бессрочно'),
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
/// Отдельным блоком сверху — Honey, подаренные именно этому клиенту.
class ClientHoneyTab extends StatefulWidget {
  const ClientHoneyTab({super.key, this.onBookOffer});

  /// Открыть запись по предложению — скидка/услуга из Honey
  /// переходят в диалог записи.
  final void Function(SalonOffer offer)? onBookOffer;

  @override
  State<ClientHoneyTab> createState() => _ClientHoneyTabState();
}

class _ClientHoneyTabState extends State<ClientHoneyTab> {
  final _cloud = CloudService();
  List<SalonOffer> _offers = [];
  List<SalonOffer> _gifts = [];
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
      // Подарки — отдельно: если миграция offer_gifts ещё не
      // применена, витрина всё равно работает.
      List<SalonOffer> gifts = [];
      try {
        gifts = await _cloud.giftedOffers();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _offers = offers;
        _gifts = gifts;
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

  /// Шторка предложения: фото-фон, описание, срок, услуги
  /// со скидкой (зачёркнутая цена → итог) и кнопка «Записаться».
  Future<void> _openOffer(SalonOffer offer) async {
    // Услуги провайдера — чтобы показать цены со скидкой.
    List<CloudServiceItem> services = [];
    try {
      services = (await _cloud.servicesOf(offer.providerId))
          .where((s) => s.published)
          .toList();
    } catch (_) {}
    if (!mounted) return;
    final covered = offer.allServices
        ? services
        : services.where((s) => offer.serviceIds.contains(s.id)).toList();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (offer.imageUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    child: Image.network(
                      offer.imageUrl,
                      height: 170,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, e, s) => const SizedBox.shrink(),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            offer.isGift
                                ? Icons.redeem
                                : Icons.card_giftcard,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              offer.providerName.isNotEmpty
                                  ? offer.providerName
                                  : 'Салон',
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          if (offer.value.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
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
                      if (offer.isGift)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Подарено вам',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        offer.title,
                        style: theme.textTheme.headlineSmall,
                      ),
                      if (offer.description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          offer.description,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                      if (_fmtValidity(offer).isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.event,
                              size: 16,
                              color: theme.colorScheme.outline,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _fmtValidity(offer),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                      // Услуги со скидкой: зачёркнутая цена → итог.
                      if (offer.discountPercent > 0 &&
                          covered.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          offer.allServices
                              ? 'Скидка −${_fmtNum(offer.discountPercent)}% '
                                  'на все услуги:'
                              : 'Скидка −${_fmtNum(offer.discountPercent)}% '
                                  'на услуги:',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 6),
                        for (final s in covered)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    s.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '${formatMoney(s.price)}  ',
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(
                                    decoration:
                                        TextDecoration.lineThrough,
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                                Text(
                                  formatMoney(
                                    offer.discountedPrice(s.price),
                                  ),
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ] else if (!offer.allServices &&
                          covered.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Действует на: '
                          '${covered.map((s) => s.name).join(', ')}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                      if (offer.linkUrl.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () {
                            final uri = Uri.tryParse(
                              offer.linkUrl.startsWith('http')
                                  ? offer.linkUrl
                                  : 'https://${offer.linkUrl}',
                            );
                            if (uri != null) {
                              launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                          icon: const Icon(Icons.link, size: 18),
                          label: const Text('Открыть ссылку'),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: widget.onBookOffer == null
                              ? null
                              : () {
                                  Navigator.of(sheetContext).pop();
                                  widget.onBookOffer!(offer);
                                },
                          icon: const Icon(Icons.event_available),
                          label: const Text('Записаться'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _offerCard(SalonOffer o) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openOffer(o),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (o.imageUrl.isNotEmpty)
              Image.network(
                o.imageUrl,
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, e, s) => const SizedBox.shrink(),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        o.isGift ? Icons.redeem : Icons.card_giftcard,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          o.providerName.isNotEmpty
                              ? o.providerName
                              : 'Салон',
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                      if (o.value.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
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
                    style: theme.textTheme.titleMedium,
                  ),
                  if (o.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      o.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (_fmtValidity(o).isNotEmpty ||
                      o.discountPercent > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (o.discountPercent > 0)
                          '−${_fmtNum(o.discountPercent)}%',
                        if (!o.allServices) 'на выбранные услуги',
                        _fmtValidity(o),
                      ].where((e) => e.isNotEmpty).join(' · '),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final empty = _offers.isEmpty && _gifts.isEmpty;
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
                  child: empty
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
                            if (_gifts.isNotEmpty) ...[
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(4, 4, 4, 8),
                                child: Text(
                                  'Подарено вам',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                ),
                              ),
                              for (final o in _gifts) _offerCard(o),
                              const Divider(height: 24),
                            ],
                            for (final o in _offers) _offerCard(o),
                          ],
                        ),
                ),
    );
  }
}

/// «10» вместо «10.0» — процент без лишних нулей.
String _fmtNum(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

/// «действует с 01.10 по 31.10» / «до 31.10» — срок Honey.
String _fmtValidity(SalonOffer o) {
  if (o.validFrom == null && o.validUntil == null) return '';
  if (o.validFrom != null && o.validUntil != null) {
    return 'с ${_fmtDate(o.validFrom!)} по ${_fmtDate(o.validUntil!)}';
  }
  if (o.validFrom != null) return 'с ${_fmtDate(o.validFrom!)}';
  return 'до ${_fmtDate(o.validUntil!)}';
}
