import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../notifications/push_service.dart';
import 'cloud_service.dart';
import 'master_public_profile.dart';

/// Экран профиля мастера: категория, описание, рейтинг.
/// Показывается мастеру при первом входе и из «Ещё».
class MasterProfileScreen extends StatefulWidget {
  const MasterProfileScreen({
    super.key,
    this.isFirstSetup = false,
    this.onDeleteAccount,
  });

  /// true — показываем сразу после первого входа мастера.
  final bool isFirstSetup;

  /// Колбэк удаления аккаунта.
  final Future<void> Function()? onDeleteAccount;

  @override
  State<MasterProfileScreen> createState() => _MasterProfileScreenState();
}

class _MasterProfileScreenState extends State<MasterProfileScreen> {
  final _cloud = CloudService();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _descController = TextEditingController();
  final _addressController = TextEditingController();
  final _socialController = TextEditingController();
  List<String> _categories = [];
  String? _category;
  String _avatarUrl = '';
  bool _phonePublic = false;
  bool _pickingAvatar = false;
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
    _addressController.dispose();
    _socialController.dispose();
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
        _addressController.text = card?.address ?? '';
        _socialController.text = card?.social ?? '';
        _phonePublic = card?.phonePublic ?? false;
        _avatarUrl = card?.avatarUrl ?? '';
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

  Future<void> _pickAvatar() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      setState(() => _pickingAvatar = true);
      final url = await _cloud.uploadAvatar(file.path);
      await _cloud.updateAvatarUrl(url);
      if (!mounted) return;
      setState(() => _avatarUrl = url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить фото')),
      );
    } finally {
      if (mounted) setState(() => _pickingAvatar = false);
    }
  }

  Future<void> _deleteAccount() async {
    if (widget.onDeleteAccount == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить аккаунт?'),
        content: const Text(
          'Все данные профиля, услуги и записи в облаке будут удалены безвозвратно.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.onDeleteAccount!();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Не удалось удалить аккаунт';
      });
    }
  }

  Future<void> _preview() async {
    final previewCard = MasterCard(
      userId: _cloud.uid ?? '',
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      category: _category ?? 'Другое',
      description: _descController.text.trim(),
      address: _addressController.text.trim(),
      social: _socialController.text.trim(),
      phonePublic: _phonePublic,
      avatarUrl: _avatarUrl,
      ratingAvg: _ratingAvg,
      ratingCount: _ratingCount,
    );
    List<CloudServiceItem> services = [];
    try {
      services = await _cloud.myServices();
      services = services.where((s) => s.published).toList();
    } catch (_) {
      // Если нет сети — предпросмотр без услуг.
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => MasterPublicProfileView(
          master: previewCard,
          services: services,
          isPreview: true,
        ),
      ),
    );
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
        address: _addressController.text.trim(),
        social: _socialController.text.trim(),
        phonePublic: _phonePublic,
        avatarUrl: _avatarUrl,
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
                        Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            GestureDetector(
                              onTap: _pickingAvatar ? null : _pickAvatar,
                              child: CircleAvatar(
                                radius: 40,
                                backgroundColor: scheme.primary,
                                backgroundImage: _avatarUrl.isNotEmpty
                                    ? NetworkImage(_avatarUrl)
                                    : null,
                                child: _avatarUrl.isEmpty
                                    ? Icon(Icons.person,
                                        color: scheme.onPrimary, size: 36)
                                    : null,
                              ),
                            ),
                            if (_pickingAvatar)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            else
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: scheme.secondary,
                                child: Icon(Icons.camera_alt,
                                    size: 14, color: scheme.onSecondary),
                              ),
                          ],
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
                              if (_avatarUrl.isEmpty)
                                Text(
                                  'Нажмите на кружок, чтобы добавить фото',
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
                  controller: _addressController,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Адрес',
                    hintText: 'Город, улица, кабинет…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _socialController,
                  decoration: const InputDecoration(
                    labelText: 'Соцсети',
                    hintText: 'Instagram, Telegram, VK…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Показывать телефон клиентам'),
                  subtitle: const Text('Номер будет виден в вашей карточке'),
                  value: _phonePublic,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _phonePublic = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'О себе',
                    hintText: 'Опыт, особенности…',
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
                FilledButton.tonalIcon(
                  onPressed: _saving ? null : _preview,
                  icon: const Icon(Icons.visibility),
                  label: const Text('Посмотреть, как видят клиенты'),
                ),
                const SizedBox(height: 12),
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
                if (!widget.isFirstSetup) ...[
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _saving ? null : _deleteAccount,
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('Удалить аккаунт'),
                  ),
                ],
              ],
            ),
    );
  }
}

/// Экран «Заявки клиентов» — записи, которые клиенты
/// сделали к этому мастеру через облако.
class MasterBookingsScreen extends StatefulWidget {
  const MasterBookingsScreen({
    super.key,
    this.onBookingChanged,
  });

  /// Вызывается при изменении статуса заявки.
  /// Можно синхронизировать с локальным календарём.
  final Future<void> Function(CloudBooking booking)? onBookingChanged;

  @override
  State<MasterBookingsScreen> createState() => _MasterBookingsScreenState();
}

class _MasterBookingsScreenState extends State<MasterBookingsScreen> {
  final _cloud = CloudService();
  List<CloudBooking> _bookings = [];
  List<ClientReview> _myClientReviews = [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Set<int> get _reviewedBookingIds =>
      _myClientReviews.map((r) => r.bookingId).toSet();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final results = await Future.wait([
        _cloud.masterBookings(),
        _cloud.myClientReviews(),
      ]);
      if (!mounted) return;
      setState(() {
        _bookings = results[0] as List<CloudBooking>;
        _myClientReviews = results[1] as List<ClientReview>;
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

  Future<void> _setStatus(CloudBooking b, String status) async {
    try {
      await _cloud.setBookingStatus(b.id, status);
      final updated = b.copyWith(status: status);
      await widget.onBookingChanged?.call(updated);
      if (b.clientId.isNotEmpty) {
        final (title, body) = switch (status) {
          'confirmed' => (
              'Запись подтверждена',
              'Мастер принял заявку на ${b.serviceName}'
            ),
          'cancelled' => (
              'Запись отменена',
              'Мастер отменил заявку на ${b.serviceName}'
            ),
          'completed' => (
              'Запись завершена',
              'Мастер завершил приём на ${b.serviceName}'
            ),
          _ => (null, null),
        };
        if (title != null && body != null) {
          await PushNotificationService.sendPush(
            toUserId: b.clientId,
            title: title,
            body: body,
            data: {'appointment_id': b.id, 'status': status},
          );
        }
      }
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

  Future<void> _openClient(CloudBooking b) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => ClientDetailScreen(
          clientId: b.clientId,
          clientName: b.clientName,
          clientPhone: b.clientPhone,
        ),
      ),
    );
  }

  Future<void> _rateClient(CloudBooking b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => RateClientDialog(booking: b),
    );
    if (ok == true) await _load();
  }

  bool _canReviewClient(CloudBooking b) =>
      b.status == 'completed' &&
      b.clientId.isNotEmpty &&
      !_reviewedBookingIds.contains(b.id);

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
                                        if (b.clientId.isNotEmpty)
                                          IconButton(
                                            tooltip: 'Профиль клиента',
                                            onPressed: () => _openClient(b),
                                            icon: const Icon(Icons.person),
                                          ),
                                        if (_canReviewClient(b))
                                          FilledButton.tonalIcon(
                                            onPressed: () => _rateClient(b),
                                            icon: const Icon(Icons.star),
                                            label: const Text('Оценить клиента'),
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

/// Карточка клиента с отзывами от других мастеров.
class ClientDetailScreen extends StatefulWidget {
  const ClientDetailScreen({
    super.key,
    required this.clientId,
    required this.clientName,
    required this.clientPhone,
  });

  final String clientId;
  final String clientName;
  final String clientPhone;

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  final _cloud = CloudService();
  List<ClientReview> _reviews = [];
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
      final reviews = await _cloud.clientReviews(widget.clientId);
      if (!mounted) return;
      setState(() {
        _reviews = reviews;
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

  Future<void> _call() async {
    if (widget.clientPhone.isEmpty) return;
    final uri = Uri.parse('tel:${widget.clientPhone}');
    await launchUrl(uri);
  }

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';

  @override
  Widget build(BuildContext context) {
    final name = widget.clientName.isEmpty ? 'Клиент' : widget.clientName;
    final average = _reviews.isEmpty
        ? 0.0
        : _reviews.map((r) => r.rating).reduce((a, b) => a + b) /
            _reviews.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          if (widget.clientPhone.isNotEmpty)
            IconButton(
              tooltip: 'Позвонить',
              onPressed: _call,
              icon: const Icon(Icons.call),
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
                      const Text('Не удалось загрузить отзывы'),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: Text(name),
                          subtitle: widget.clientPhone.isEmpty
                              ? null
                              : Text(widget.clientPhone),
                        ),
                      ),
                      if (_reviews.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber),
                            const SizedBox(width: 8),
                            Text(
                              '${average.toStringAsFixed(1)} • ${_reviews.length} оценок',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (_reviews.isEmpty)
                        const Text(
                          'Отзывов пока нет.\nКогда мастера оставят оценки — '
                          'они появятся здесь.',
                          textAlign: TextAlign.center,
                        ),
                      for (final r in _reviews)
                        Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        r.masterName.isEmpty
                                            ? 'Мастер'
                                            : r.masterName,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                      ),
                                    ),
                                    Text(_fmt(r.createdAt ?? DateTime.now())),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    for (var i = 1; i <= 5; i++)
                                      Icon(
                                        i <= r.rating
                                            ? Icons.star
                                            : Icons.star_border,
                                        size: 16,
                                        color: Colors.amber,
                                      ),
                                  ],
                                ),
                                if (r.comment.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(r.comment),
                                ],
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
    );
  }
}

/// Диалог оценки клиента мастером.
class RateClientDialog extends StatefulWidget {
  const RateClientDialog({super.key, required this.booking});

  final CloudBooking booking;

  @override
  State<RateClientDialog> createState() => _RateClientDialogState();
}

class _RateClientDialogState extends State<RateClientDialog> {
  final _cloud = CloudService();
  final _comment = TextEditingController();
  int _rating = 5;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _cloud.addClientReview(
        clientId: widget.booking.clientId,
        bookingId: widget.booking.id,
        rating: _rating,
        comment: _comment.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Не удалось отправить оценку';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Оцените клиента'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.booking.clientName.isEmpty
              ? 'Клиент'
              : widget.booking.clientName),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  onPressed: () => setState(() => _rating = i),
                  icon: Icon(
                    i <= _rating ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 36,
                  ),
                ),
            ],
          ),
          TextField(
            controller: _comment,
            decoration: const InputDecoration(
              labelText: 'Комментарий (необязательно)',
              border: OutlineInputBorder(),
            ),
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
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Позже'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: const Text('Отправить'),
        ),
      ],
    );
  }
}
