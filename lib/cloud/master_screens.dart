import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../notifications/push_service.dart';
import 'cloud_service.dart';
import 'geo_service.dart';
import 'map_screens.dart';
import 'master_public_profile.dart';

/// Экран профиля мастера: категория, описание, рейтинг.
/// Показывается мастеру при первом входе и из «Ещё».
class MasterProfileScreen extends StatefulWidget {
  const MasterProfileScreen({
    super.key,
    this.isFirstSetup = false,
    this.onDeleteAccount,
    this.onSyncServices,
  });

  /// true — показываем сразу после первого входа мастера.
  final bool isFirstSetup;

  /// Колбэк удаления аккаунта.
  final Future<void> Function()? onDeleteAccount;

  /// Вызывается перед предпросмотром — пушит локальные услуги в облако,
  /// чтобы «как видят клиенты» показывал актуальный список.
  final Future<void> Function()? onSyncServices;

  @override
  State<MasterProfileScreen> createState() => _MasterProfileScreenState();
}

class _MasterProfileScreenState extends State<MasterProfileScreen> {
  final _cloud = CloudService();
  final _geo = GeoService();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
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
  double? _lat;
  double? _lng;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<PortfolioPhoto> _portfolio = [];
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
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
      List<PortfolioPhoto> portfolio = [];
      try {
        portfolio = await _cloud.myPortfolio();
      } catch (e, st) {
        await SyncLog.write('portfolio', 'Загрузка портфолио: $e\n$st');
      }
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _nameController.text = profile?.name ?? '';
        _phoneController.text = profile?.phone ?? '';
        _emailController.text = _cloud.displayLogin;
        _category = card?.category ?? categories.firstOrNull;
        _descController.text = card?.description ?? '';
        _addressController.text = card?.address ?? '';
        _socialController.text = card?.social ?? '';
        _phonePublic = card?.phonePublic ?? false;
        _avatarUrl = card?.avatarUrl ?? '';
        _ratingAvg = card?.ratingAvg ?? 0;
        _ratingCount = card?.ratingCount ?? 0;
        _lat = card?.lat;
        _lng = card?.lng;
        _portfolio = portfolio;
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

  Future<void> _addPortfolioPhoto() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      setState(() => _uploadingPhoto = true);
      final photo = await _cloud.uploadPortfolioPhoto(file.path);
      if (!mounted) return;
      setState(() => _portfolio = [..._portfolio, photo]);
    } catch (e, st) {
      await SyncLog.write('portfolio', 'Загрузка фото: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить фото')),
      );
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _removePortfolioPhoto(PortfolioPhoto photo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить фото?'),
        content: const Text('Фото пропадёт из вашего публичного профиля.'),
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
      await _cloud.deletePortfolioPhoto(photo);
      setState(
          () => _portfolio = _portfolio.where((p) => p.id != photo.id).toList());
    } catch (e, st) {
      await SyncLog.write('portfolio', 'Удаление фото: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось удалить фото')),
      );
    }
  }

  /// Отдельный компактный диалог смены пароля:
  /// сперва новый пароль, затем повтор.
  Future<void> _changePassword() async {
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Сменить пароль'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: newCtrl,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Новый пароль',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.length < 6)
                    ? 'Минимум 6 символов'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Повторите новый пароль',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v != newCtrl.text ? 'Пароли не совпадают' : null,
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
    final password = newCtrl.text;
    newCtrl.dispose();
    confirmCtrl.dispose();
    if (ok != true || !mounted) return;
    try {
      await _cloud.updateAuth(password: password);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пароль обновлён')),
      );
    } catch (e) {
      await SyncLog.write('password_change', e.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сменить пароль')),
      );
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
    // Сначала доталкиваем локальные услуги в облако, чтобы
    // предпросмотр показывал то же, что видят клиенты.
    try {
      await widget.onSyncServices?.call();
    } catch (_) {
      // Нет сети — покажем то, что уже в облаке.
    }
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
          portfolio: _portfolio,
          isPreview: true,
        ),
      ),
    );
  }

  /// Открывает карту для выбора точки мастера; после выбора подставляет
  /// адрес через обратный геокодинг.
  Future<void> _pickLocationOnMap() async {
    GeoPoint? initial;
    if (_lat != null && _lng != null) {
      initial = GeoPoint(_lat!, _lng!);
    } else if (_addressController.text.trim().isNotEmpty) {
      // Пробуем найти введённый адрес, чтобы карта открылась рядом.
      initial = await _geo.geocode(_addressController.text);
    }
    if (!mounted) return;
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (context) => MapPickerScreen(initial: initial),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _lat = picked.latitude;
      _lng = picked.longitude;
    });
    final addr = await _geo.reverseGeocode(picked.latitude, picked.longitude);
    if (!mounted) return;
    if (addr != null && addr.label.isNotEmpty) {
      setState(() => _addressController.text = addr.label);
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
      final login = _emailController.text.trim();
      final needLogin = !widget.isFirstSetup &&
          login.isNotEmpty &&
          login != _cloud.displayLogin;
      if (needLogin) {
        await _cloud.updateAuth(login: login);
      }

      // Координаты: выбранные на карте, либо геокодинг из текста адреса.
      final address = _addressController.text.trim();
      var lat = _lat;
      var lng = _lng;
      if ((lat == null || lng == null) && address.isNotEmpty) {
        final point = await _geo.geocode(address);
        if (point != null) {
          lat = point.lat;
          lng = point.lng;
          if (mounted) {
            setState(() {
              _lat = lat;
              _lng = lng;
            });
          }
        }
      }

      await _cloud.updateMyProfile(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        avatarUrl: _avatarUrl,
      );
      await _cloud.upsertMasterProfile(
        category: _category!,
        description: _descController.text.trim(),
        address: address,
        lat: lat,
        lng: lng,
        social: _socialController.text.trim(),
        phonePublic: _phonePublic,
        avatarUrl: _avatarUrl,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профиль сохранён')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      await SyncLog.write('master_profile_edit', e.toString());
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Не удалось сохранить: $e';
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
                InkWell(
                  onTap: _saving
                      ? null
                      : () => setState(() => _phonePublic = !_phonePublic),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _phonePublic,
                          onChanged: _saving
                              ? null
                              : (v) =>
                                  setState(() => _phonePublic = v ?? false),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        Text(
                          'Показывать номер',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _emailController,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Логин',
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
                      hint: const Text('Выберите категорию'),
                      items: _categories
                          .map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Text(c),
                            ),
                          )
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _category = v),
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
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _saving ? null : _pickLocationOnMap,
                    icon: Icon(
                      _lat != null ? Icons.edit_location_alt : Icons.map,
                      size: 18,
                    ),
                    label: Text(
                      _lat != null
                          ? 'Точка на карте указана — изменить'
                          : 'Указать точку на карте',
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
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
                const SizedBox(height: 20),
                Text(
                  'Портфолио — фото работ',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Эти фото видят клиенты в вашей карточке',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    for (final photo in _portfolio)
                      Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              photo.imageUrl,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, progress) =>
                                  progress == null
                                      ? child
                                      : Container(
                                          color: scheme.surfaceContainerHighest,
                                          child: const Center(
                                            child:
                                                CircularProgressIndicator(
                                                    strokeWidth: 2),
                                          ),
                                        ),
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                color: scheme.surfaceContainerHighest,
                                child: const Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: InkWell(
                              onTap: _saving
                                  ? null
                                  : () => _removePortfolioPhoto(photo),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(4),
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    InkWell(
                      onTap:
                          _uploadingPhoto || _saving ? null : _addPortfolioPhoto,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: scheme.outline,
                            style: BorderStyle.solid,
                          ),
                          color: scheme.surfaceContainerHighest
                              .withValues(alpha: 0.4),
                        ),
                        child: Center(
                          child: _uploadingPhoto
                              ? const CircularProgressIndicator(strokeWidth: 2)
                              : Icon(
                                  Icons.add_photo_alternate_outlined,
                                  color: scheme.primary,
                                ),
                        ),
                      ),
                    ),
                  ],
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
                    onPressed: _saving ? null : _changePassword,
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Сменить пароль'),
                  ),
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
      final bookings = await _cloud.masterBookings();
      List<ClientReview> reviews = [];
      try {
        reviews = await _cloud.myClientReviews();
      } catch (e, st) {
        await SyncLog.write('myClientReviews', '$e\n$st');
      }
      if (!mounted) return;
      setState(() {
        _bookings = bookings;
        _myClientReviews = reviews;
        _loading = false;
      });
    } catch (e, st) {
      await SyncLog.write('masterBookings', '$e\n$st');
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
