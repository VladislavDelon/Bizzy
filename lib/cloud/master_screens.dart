import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../notifications/push_service.dart';
import 'cloud_service.dart';
import 'credentials_dialog.dart';
import 'geo_service.dart';
import 'map_screens.dart';
import 'master_public_profile.dart';

/// Экран профиля мастера/салона: категория, описание, рейтинг.
/// Показывается при первом входе мастера и из «Ещё».
class MasterProfileScreen extends StatefulWidget {
  const MasterProfileScreen({
    super.key,
    this.isFirstSetup = false,
    this.role = '',
    this.onDeleteAccount,
    this.onSyncServices,
  });

  /// true — показываем сразу после первого входа мастера.
  final bool isFirstSetup;

  /// 'master' | 'salon' — нужен сразу, чтобы заголовок
  /// не мигал «мастер → салон» пока грузится профиль.
  final String role;

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
  bool _isSalon = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<PortfolioPhoto> _portfolio = [];
  bool _uploadingPhoto = false;
  bool _prepayEnabled = false;
  final _prepayAmountController = TextEditingController();
  final _prepayLinkController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _isSalon = widget.role == 'salon';
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _descController.dispose();
    _addressController.dispose();
    _socialController.dispose();
    _prepayAmountController.dispose();
    _prepayLinkController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final categories = await _cloud.categories();
      var profile = await _cloud.myProfile();
      if (profile == null) {
        // Профиль мог не создаться при старой сломанной регистрации —
        // создаём по роли из metadata, иначе сохранение не сработает.
        final meta = supabase.auth.currentUser?.userMetadata ?? const {};
        profile = await _cloud.ensureProfile(
          role: meta['role'] as String? ?? 'master',
          name: meta['name'] as String? ?? '',
          phone: meta['phone'] as String? ?? '',
        );
      }
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
        _isSalon = profile?.isSalon ?? false;
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
        _prepayEnabled = card?.prepayEnabled ?? false;
        _prepayAmountController.text = (card != null && card.prepayAmount > 0)
            ? card.prepayAmount.toStringAsFixed(0)
            : '';
        _prepayLinkController.text = card?.prepayLink ?? '';
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
      role: _isSalon ? 'salon' : 'master',
      category: _category ?? 'Другое',
      description: _descController.text.trim(),
      address: _addressController.text.trim(),
      social: _socialController.text.trim(),
      phonePublic: _phonePublic,
      avatarUrl: _avatarUrl,
      prepayEnabled: _prepayEnabled,
      prepayAmount:
          double.tryParse(_prepayAmountController.text.replaceAll(',', '.')) ??
              0,
      prepayLink: _prepayLinkController.text.trim(),
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

  /// Определяет точку по GPS и подставляет адрес обратным геокодингом.
  Future<void> _useMyLocation() async {
    try {
      final point = await _geo.currentPosition();
      if (!mounted) return;
      setState(() {
        _lat = point.lat;
        _lng = point.lng;
      });
      final addr = await _geo.reverseGeocode(point.lat, point.lng);
      if (!mounted) return;
      if (addr != null && addr.label.isNotEmpty) {
        setState(() => _addressController.text = addr.label);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Точка определена по геопозиции')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
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
    final prepayAmount =
        double.tryParse(_prepayAmountController.text.replaceAll(',', '.')) ?? 0;
    if (_prepayEnabled && prepayAmount <= 0) {
      setState(() => _error = 'Укажите сумму предоплаты');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
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
        prepayEnabled: _prepayEnabled,
        prepayAmount: prepayAmount,
        prepayLink: _prepayLinkController.text.trim(),
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
        title: Text(_isSalon ? 'Профиль салона' : 'Мой профиль'),
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
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Категория',
                    border: OutlineInputBorder(),
                  ),
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
                Row(
                  children: [
                    Expanded(
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
                          alignment: Alignment.centerLeft,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _saving ? null : _useMyLocation,
                      icon: const Icon(Icons.my_location, size: 18),
                      label: const Text('По геопозиции'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
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
                  'Предоплата',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Работа по предоплате'),
                  subtitle: const Text(
                    'Клиент внесёт предоплату перед записью, '
                    'вы подтвердите получение',
                  ),
                  value: _prepayEnabled,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _prepayEnabled = v),
                ),
                if (_prepayEnabled) ...[
                  TextField(
                    controller: _prepayAmountController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Сумма предоплаты',
                      hintText: 'Например: 2000',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _prepayLinkController,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Ссылка на оплату',
                      hintText: 'Kaspi, Halyk, Сбербанк — pay-ссылка или QR',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Клиент нажмёт «Оплатить» при записи — '
                    'откроется эта ссылка в его банковском приложении',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
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
                    onPressed: _saving
                        ? null
                        : () => showCredentialsEditor(context),
                    icon: const Icon(Icons.key_outlined),
                    label: const Text('Изменить логин и пароль'),
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

  /// Салон: мастера команды и флаг автоназначения.
  bool _isSalon = false;
  List<MasterCard> _team = [];
  bool _autoAssign = false;

  /// Входящие приглашения от салонов (для мастера).
  List<TeamInvite> _invites = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Set<int> get _reviewedBookingIds =>
      _myClientReviews.map((r) => r.bookingId).toSet();

  /// Имя исполнителя заявки для салона (пусто — сам салон).
  String _masterLabel(String masterId) {
    if (masterId == _cloud.uid) return '';
    for (final m in _team) {
      if (m.userId == masterId) {
        return m.name.isEmpty ? 'Мастер' : m.name;
      }
    }
    return '';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final profile = await _cloud.myProfile();
      final isSalon = profile?.isSalon ?? false;
      List<MasterCard> team = [];
      var autoAssign = false;
      List<CloudBooking> bookings;
      if (isSalon) {
        try {
          team = await _cloud.salonMasters();
          autoAssign = (await _cloud.myMasterCard())?.autoAssign ?? false;
        } catch (_) {}
        bookings = await _cloud.salonBookings();
      } else {
        bookings = await _cloud.masterBookings();
      }
      List<ClientReview> reviews = [];
      try {
        reviews = await _cloud.myClientReviews();
      } catch (e, st) {
        await SyncLog.write('myClientReviews', '$e\n$st');
      }
      List<TeamInvite> invites = [];
      try {
        invites = await _cloud.myTeamInvites();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _isSalon = isSalon;
        _team = team;
        _autoAssign = autoAssign;
        _bookings = bookings;
        _myClientReviews = reviews;
        _invites = invites;
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

  /// Салон: выбор мастера для заявки.
  Future<void> _assignTo(CloudBooking b) async {
    if (_team.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Сначала добавьте мастеров во вкладке «Мастера»')),
      );
      return;
    }
    final picked = await showDialog<MasterCard>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Назначить мастера'),
        children: [
          for (final m in _team)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(m),
              child: Row(
                children: [
                  const Icon(Icons.content_cut, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(m.name.isEmpty ? 'Мастер' : m.name),
                  ),
                  if (b.masterId == m.userId)
                    const Icon(Icons.check, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await _cloud.assignBooking(b.id, picked.userId);
      if (picked.userId.isNotEmpty) {
        await PushNotificationService.sendPush(
          toUserId: picked.userId,
          title: 'Новая запись',
          body:
              'Салон назначил вам заявку на ${b.serviceName} ${_fmt(b.startsAt)}',
          data: {'appointment_id': b.id, 'status': b.status},
        );
      }
      await _load();
    } catch (e) {
      await SyncLog.write('assignBooking', e.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось назначить: $e')),
      );
    }
  }

  /// Салон: переключение «Автоматическое назначение / Вручную».
  Future<void> _toggleAutoAssign() async {
    final next = !_autoAssign;
    try {
      await _cloud.setAutoAssign(next);
      if (!mounted) return;
      setState(() => _autoAssign = next);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            next
                ? 'Автоназначение включено: заявки распределяются между мастерами'
                : 'Автоназначение выключено: назначаете вручную',
          ),
        ),
      );
    } catch (e) {
      await SyncLog.write('auto_assign', e.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось переключить: $e')),
      );
    }
  }

  /// Мастер отвечает на приглашение салона: принять → в команде.
  Future<void> _respondInvite(TeamInvite invite, bool accept) async {
    try {
      await _cloud.respondTeamInvite(invite, accept);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept
              ? 'Вы в команде салона — заявки будут приходить сюда'
              : 'Приглашение отклонено'),
        ),
      );
      await _load();
    } catch (e) {
      await SyncLog.write('team_invite', e.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось ответить: $e')),
      );
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

  /// Мастер подтверждает, что предоплата реально пришла.
  Future<void> _confirmPrepay(CloudBooking b) async {
    try {
      await _cloud.setPrepaymentStatus(b.id, 'confirmed');
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось подтвердить оплату')),
      );
    }
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
      appBar: AppBar(
        title: const Text('Заявки клиентов'),
        actions: [
          if (_isSalon)
            PopupMenuButton<String>(
              tooltip: 'Назначение записей',
              onSelected: (v) {
                if (v == 'auto') _toggleAutoAssign();
              },
              itemBuilder: (context) => [
                CheckedPopupMenuItem(
                  value: 'auto',
                  checked: _autoAssign,
                  child: const Text(
                      'Автоназначение записей на мастеров'),
                ),
              ],
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
                      const Text('Не удалось загрузить заявки'),
                      TextButton(onPressed: _load, child: const Text('Повторить')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _bookings.isEmpty && _invites.isEmpty
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
                          itemCount: _invites.length + _bookings.length +
                              (_bookings.isEmpty ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index < _invites.length) {
                              final inv = _invites[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Приглашение в салон',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '«${inv.otherName.isEmpty ? 'Салон' : inv.otherName}» '
                                        'приглашает вас в свою команду.',
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        children: [
                                          FilledButton.tonalIcon(
                                            onPressed: () =>
                                                _respondInvite(inv, true),
                                            icon: const Icon(Icons.check),
                                            label: const Text('Принять'),
                                          ),
                                          OutlinedButton(
                                            onPressed: () =>
                                                _respondInvite(inv, false),
                                            child: const Text('Отклонить'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                            index -= _invites.length;
                            if (_bookings.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.all(32),
                                child: Center(
                                  child: Text(
                                    'Заявок пока нет.',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              );
                            }
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
                                    if (_isSalon &&
                                        _masterLabel(b.masterId)
                                            .isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.assignment_ind_outlined,
                                            size: 16,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Мастер: ${_masterLabel(b.masterId)}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    if (b.notes.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        b.notes,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                    if (b.prepaymentStatus != 'none') ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.payments_outlined,
                                            size: 16,
                                            color: b.prepaymentStatus ==
                                                    'confirmed'
                                                ? Colors.green
                                                : Colors.orange,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              b.prepaymentStatus == 'confirmed'
                                                  ? 'Предоплата получена'
                                                  : 'Клиент отметил '
                                                      'предоплату — проверьте '
                                                      'поступление',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                          ),
                                        ],
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
                                        if (_isSalon)
                                          IconButton(
                                            tooltip: 'Назначить мастера',
                                            onPressed: () => _assignTo(b),
                                            icon: const Icon(Icons
                                                .assignment_ind_outlined),
                                          ),
                                        if (b.prepaymentStatus == 'claimed')
                                          FilledButton.tonalIcon(
                                            onPressed: () => _confirmPrepay(b),
                                            icon: const Icon(
                                                Icons.payments_outlined),
                                            label: const Text(
                                                'Оплата получена'),
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

/// Вкладка «Мастера» у салона: ключ регистрации, команда из облака,
/// создание аккаунтов мастеров + локальный справочник ниже.
class SalonTeamScreen extends StatefulWidget {
  const SalonTeamScreen({
    super.key,
    required this.localDirectoryBuilder,
  });

  /// Локальный справочник мастеров — встраивается под облачным
  /// блоком. [onAddMaster] пробрасывается в FAB «Новый мастер»,
  /// чтобы кнопка создавала облачный аккаунт.
  final Widget Function(VoidCallback onAddMaster) localDirectoryBuilder;

  @override
  State<SalonTeamScreen> createState() => _SalonTeamScreenState();
}

class _SalonTeamScreenState extends State<SalonTeamScreen> {
  final _cloud = CloudService();
  String _key = '';
  bool _showKey = false;
  List<MasterCard> _team = [];
  List<TeamInvite> _invites = [];
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
      final key = await _cloud.ensureSalonKey();
      final team = await _cloud.salonMasters();
      List<TeamInvite> invites = [];
      try {
        invites = await _cloud.sentTeamInvites();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _key = key;
        _team = team;
        _invites = invites;
        _loading = false;
      });
    } catch (e, st) {
      await SyncLog.write('salon_team', '$e\n$st');
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _copyKey() async {
    await Clipboard.setData(ClipboardData(text: _key));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ключ скопирован')),
    );
  }

  /// Открепить мастера от салона — он станет самозанятым.
  Future<void> _detach(MasterCard m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Открепить ${m.name.isEmpty ? 'мастера' : m.name}?'),
        content: const Text(
          'Мастер останется в Bizzy как самозанятый и пропадёт из вашей команды.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Открепить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _cloud.detachMaster(m.userId);
      await _load();
    } catch (e) {
      await SyncLog.write('detach_master', e.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открепить: $e')),
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

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  /// Отозвать отправленное приглашение (ещё не принятое).
  Future<void> _revokeInvite(TeamInvite inv) async {
    try {
      await supabase.from('team_invites').delete().eq('id', inv.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось: $e')),
      );
    }
  }

  /// Поиск самозанятых мастеров по имени/телефону/ID и отправка
  /// приглашения — мастер подтверждает у себя и попадает в команду.
  Future<void> _openSearch() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _MasterSearchDialog(
        cloud: _cloud,
        teamIds: _team.map((m) => m.userId).toSet(),
        onInvite: (m) async {
          await _cloud.sendTeamInvite(m.userId);
          await PushNotificationService.sendPush(
            toUserId: m.userId,
            title: 'Приглашение в салон',
            body: 'Салон приглашает вас в команду — откройте «Заявки»',
          );
        },
        onChanged: _load,
      ),
    );
  }

  /// «Информация о записях»: сколько записей у мастера и на какую сумму
  /// закрыты. Салон читает заявки своей команды по RLS-политике.
  Future<void> _showBookings(MasterCard m) async {
    List<CloudBooking> bookings;
    try {
      bookings = await _cloud.masterBookingsFor(m.userId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось загрузить записи: $e')),
      );
      return;
    }
    if (!mounted) return;
    final completed =
        bookings.where((b) => b.status == 'completed').toList();
    final cancelled =
        bookings.where((b) => b.status == 'cancelled').length;
    final sum = completed.fold<double>(0, (s, b) => s + b.servicePrice);
    String money(double v) => v == v.roundToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(2);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              m.name.isEmpty ? 'Мастер' : m.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Всего: ${bookings.length}')),
                Chip(label: Text('Завершено: ${completed.length}')),
                Chip(label: Text('Отменено: $cancelled')),
                Chip(label: Text('Закрыто на ${money(sum)}')),
              ],
            ),
            const SizedBox(height: 12),
            if (bookings.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Записей пока нет')),
              )
            else
              for (final b in bookings)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(b.serviceName),
                  subtitle: Text(
                    '${_fmt(b.startsAt)} • '
                    '${b.clientName.isEmpty ? 'Клиент' : b.clientName}',
                  ),
                  trailing: Text(
                    '${_statusLabel(b.status)}\n${money(b.servicePrice)}',
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
          ],
        ),
      ),
    );
  }

  /// Смена логина/пароля мастера — через Edge Function salon-master-auth.
  Future<void> _editCredentials(MasterCard m) async {
    final loginCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Данные входа: ${m.name.isEmpty ? 'мастер' : m.name}'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: loginCtrl,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Новый логин',
                  hintText: 'Пусто — не менять',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Новый пароль',
                  hintText: 'Пусто — не менять',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v != null && v.isNotEmpty && v.length < 6)
                    ? 'Минимум 6 символов'
                    : null,
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
    final login = loginCtrl.text.trim();
    final password = passCtrl.text;
    loginCtrl.dispose();
    passCtrl.dispose();
    if (ok != true || !mounted) return;
    if (login.isEmpty && password.isEmpty) return;
    try {
      final res = await supabase.functions.invoke(
        'salon-master-auth',
        body: {
          'master_id': m.userId,
          if (login.isNotEmpty) 'login': login,
          if (password.isNotEmpty) 'password': password,
        },
      );
      final err = res.data is Map ? res.data['error'] : null;
      if (err != null) throw Exception('$err');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Данные мастера обновлены')),
      );
    } catch (e) {
      await SyncLog.write('master_credentials', e.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Не удалось обновить: $e\n'
            'Проверьте, что функция salon-master-auth задеплоена.',
          ),
        ),
      );
    }
  }

  /// Создание аккаунта мастера — второй клиент, сессия салона не слетает.
  Future<void> _createMaster() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final loginCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var saving = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Аккаунт мастера'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Имя мастера',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().length < 2) ? 'Имя?' : null,
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
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: loginCtrl,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Логин',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final s = v?.trim() ?? '';
                      if (s.length < 3) return 'Минимум 3 символа';
                      if (s.contains(' ')) return 'Без пробелов';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: passCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Пароль',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.length < 6)
                        ? 'Минимум 6 символов'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Мастер войдёт через «Вход как мастер» с этими логином и паролем.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => saving = true);
                      String? err;
                      try {
                        err = await _cloud.createMasterAccount(
                          login: loginCtrl.text.trim(),
                          password: passCtrl.text,
                          name: nameCtrl.text.trim(),
                          phone: phoneCtrl.text.trim(),
                        );
                      } catch (e) {
                        err = e.toString();
                      }
                      if (!context.mounted) return;
                      if (err == null) {
                        Navigator.of(context).pop(true);
                      } else {
                        setDialogState(() => saving = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Ошибка: $err')),
                        );
                      }
                    },
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    phoneCtrl.dispose();
    loginCtrl.dispose();
    passCtrl.dispose();
    if (ok != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Аккаунт создан — мастер появится в команде после входа'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Уникальный ключ для регистрации мастеров',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Отправьте его мастеру — при регистрации он '
                      'автоматически попадёт в вашу команду.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _key.isEmpty
                                ? '—'
                                : (_showKey ? _key : '••••••••'),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(letterSpacing: 2),
                          ),
                        ),
                        IconButton(
                          tooltip: _showKey ? 'Скрыть' : 'Показать',
                          onPressed: () =>
                              setState(() => _showKey = !_showKey),
                          icon: Icon(
                            _showKey
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Скопировать',
                          onPressed: _key.isEmpty ? null : _copyKey,
                          icon: const Icon(Icons.copy),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_failed)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('Не удалось загрузить команду'),
                  TextButton(onPressed: _load, child: const Text('Повторить')),
                ],
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Моя команда (${_team.length})',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _openSearch,
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('Найти мастера'),
                  ),
                ],
              ),
            ),
            if (_team.isEmpty && _invites.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Пока никого нет — отправьте ключ мастеру, найдите его '
                  'поиском или создайте аккаунт кнопкой «+» внизу.',
                  textAlign: TextAlign.center,
                ),
              )
            else ...[
              for (final m in _team)
                ListTile(
                  leading: CircleAvatar(
                    backgroundImage: m.avatarUrl.isNotEmpty
                        ? NetworkImage(m.avatarUrl)
                        : null,
                    child: m.avatarUrl.isEmpty
                        ? const Icon(Icons.content_cut)
                        : null,
                  ),
                  title: Text(m.name.isEmpty ? 'Мастер' : m.name),
                  subtitle: Text(
                    m.category +
                        (m.managedBySalon ? ' • аккаунт салона' : ''),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'creds') _editCredentials(m);
                      if (v == 'detach') _detach(m);
                    },
                    itemBuilder: (context) => [
                      // Логин/пароль менять можно только у аккаунтов,
                      // созданных салоном — приглашённым нельзя.
                      if (m.managedBySalon)
                        const PopupMenuItem(
                          value: 'creds',
                          child: Text('Сменить логин и пароль'),
                        ),
                      const PopupMenuItem(
                        value: 'detach',
                        child: Text('Уволить'),
                      ),
                    ],
                  ),
                  onTap: () => _showBookings(m),
                ),
              for (final inv in _invites.where((i) => i.status == 'pending'))
                ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: Text(
                    inv.otherName.isEmpty ? 'Приглашение' : inv.otherName,
                  ),
                  subtitle: const Text('Приглашение отправлено — ждём'),
                  trailing: IconButton(
                    tooltip: 'Отозвать приглашение',
                    icon: const Icon(Icons.close),
                    onPressed: () => _revokeInvite(inv),
                  ),
                ),
            ],
          ],
          Divider(color: scheme.outlineVariant),
          Expanded(child: widget.localDirectoryBuilder(_createMaster)),
        ],
      ),
    );
  }
}

/// Диалог поиска мастера по имени/телефону/ID — для приглашения
/// самозанятого мастера в команду салона.
class _MasterSearchDialog extends StatefulWidget {
  const _MasterSearchDialog({
    required this.cloud,
    required this.teamIds,
    required this.onInvite,
    required this.onChanged,
  });

  final CloudService cloud;
  final Set<String> teamIds;
  final Future<void> Function(MasterCard) onInvite;
  final VoidCallback onChanged;

  @override
  State<_MasterSearchDialog> createState() => _MasterSearchDialogState();
}

class _MasterSearchDialogState extends State<_MasterSearchDialog> {
  final _controller = TextEditingController();
  List<MasterCard> _results = [];
  bool _searching = false;
  bool _searched = false;
  String? _error;

  /// userId мастеров, которым приглашение уже отправлено в этом диалоге.
  final Set<String> _invited = {};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final res = await widget.cloud.searchFreeMasters(_controller.text);
      if (!mounted) return;
      setState(() {
        _results = res;
        _searched = true;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _searching = false;
      });
    }
  }

  Future<void> _invite(MasterCard m) async {
    try {
      await widget.onInvite(m);
      if (!mounted) return;
      setState(() => _invited.add(m.userId));
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Приглашение отправлено')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось пригласить: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Найти мастера'),
      content: SizedBox(
        width: double.maxFinite,
        height: 380,
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Имя, телефон или ID мастера',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _search,
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 8),
            if (_searching)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Expanded(child: Center(child: Text('Ошибка: $_error')))
            else if (_searched && _results.isEmpty)
              const Expanded(
                child: Center(child: Text('Никого не найдено')),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, i) {
                    final m = _results[i];
                    final inTeam = widget.teamIds.contains(m.userId);
                    final busy =
                        m.salonId != null && !widget.teamIds.contains(m.userId);
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundImage: m.avatarUrl.isNotEmpty
                            ? NetworkImage(m.avatarUrl)
                            : null,
                        child: m.avatarUrl.isEmpty
                            ? const Icon(Icons.content_cut)
                            : null,
                      ),
                      title: Text(m.name.isEmpty ? 'Мастер' : m.name),
                      subtitle: Text(
                        [
                          m.category,
                          if (m.phone.isNotEmpty) m.phone,
                        ].join(' • '),
                      ),
                      trailing: inTeam
                          ? const Text('В команде')
                          : busy
                              ? const Text('В другом салоне')
                              : _invited.contains(m.userId)
                                  ? const Text('Отправлено')
                                  : TextButton(
                                      onPressed: () => _invite(m),
                                      child: const Text('Пригласить'),
                                    ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}
