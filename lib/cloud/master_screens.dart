import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as phone;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../notifications/push_service.dart';
import 'certificates_screen.dart';
import 'cloud_service.dart';
import 'credentials_dialog.dart';
import 'fan_push.dart';
import 'geo_service.dart';
import 'map_screens.dart';
import 'master_public_profile.dart';
import 'provider_reviews_screen.dart';
import 'qr_share.dart';
import 'team_schedule_screen.dart';
import 'work_hours.dart';

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

  /// Выбранные виды услуг — мастер/салон находится в поиске
  /// по каждой. Первая выбранная = основная (category).
  final Set<String> _pickedCategories = {};

  /// Основная категория — первая из выбранных.
  String? get _category => _pickedCategories.firstOrNull;
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
  bool _prepayNewClients = false;
  final _prepayAmountController = TextEditingController();
  final _prepayLinkController = TextEditingController();

  /// Входящие приглашения от салонов (только у мастера).
  List<TeamInvite> _invites = [];

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
      // Категории, профиль, карточка и портфолио — параллельно.
      final results = await Future.wait([
        _cloud.categories(),
        _cloud.myProfile(),
        _cloud
            .myMasterCard()
            .then<MasterCard?>((v) => v)
            .catchError((_) => null),
        _cloud
            .myPortfolio()
            .then<List<PortfolioPhoto>>((v) => v)
            .catchError((_) => <PortfolioPhoto>[]),
      ]);
      final categories = results[0] as List<String>;
      var profile = results[1] as CloudProfile?;
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
      final card = results[2] as MasterCard?;
      final portfolio = results[3] as List<PortfolioPhoto>;
      List<TeamInvite> invites = [];
      if (!profile.isSalon) {
        try {
          invites = await _cloud.myTeamInvites();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _nameController.text = profile?.name ?? '';
        _phoneController.text = profile?.phone ?? '';
        _isSalon = profile?.isSalon ?? false;
        _pickedCategories
          ..clear()
          ..addAll(
            card != null && card.categories.isNotEmpty
                ? card.categories
                : [
                    if ((card?.category ?? '').isNotEmpty)
                      card!.category
                    else if (categories.isNotEmpty)
                      categories.first,
                  ],
          );
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
        _prepayNewClients = card?.prepayNewClients ?? false;
        _prepayAmountController.text = (card != null && card.prepayAmount > 0)
            ? card.prepayAmount.toStringAsFixed(0)
            : '';
        _prepayLinkController.text = card?.prepayLink ?? '';
        _invites = invites;
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

  /// Мастер отвечает на приглашение салона из профиля.
  Future<void> _respondInvite(TeamInvite invite, bool accept) async {
    try {
      await _cloud.respondTeamInvite(invite, accept);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? 'Вы в команде салона — заявки будут приходить сюда'
                : 'Приглашение отклонено',
          ),
        ),
      );
      _load();
    } catch (e) {
      await SyncLog.write('team_invite', e.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Не удалось ответить: $e')));
    }
  }

  /// Раздел «Приглашения» — список входящих запросов от салонов.
  Future<void> _openInvites() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Приглашения'),
        content: SizedBox(
          width: double.maxFinite,
          child: _invites.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Новых приглашений нет'),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final inv in _invites)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '«${inv.otherName.isEmpty ? 'Салон' : inv.otherName}» '
                                'приглашает вас в команду',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  FilledButton.tonalIcon(
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      _respondInvite(inv, true);
                                    },
                                    icon: const Icon(Icons.check, size: 18),
                                    label: const Text('Принять'),
                                  ),
                                  OutlinedButton(
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      _respondInvite(inv, false);
                                    },
                                    child: const Text('Отклонить'),
                                  ),
                                ],
                              ),
                            ],
                          ),
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
      ),
    );
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
      final url = await _cloud.uploadAvatar(file);
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
      final photo = await _cloud.uploadPortfolioPhoto(file);
      if (!mounted) return;
      setState(() => _portfolio = [..._portfolio, photo]);
      // Фанам — пуш о новой работе в портфолио.
      await notifyFavoriteClients(
        title: 'Новая работа',
        body: 'Ваш избранный мастер/салон добавил фото в портфолио',
      );
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
        () => _portfolio = _portfolio.where((p) => p.id != photo.id).toList(),
      );
    } catch (e, st) {
      await SyncLog.write('portfolio', 'Удаление фото: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Не удалось удалить фото')));
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
      prepayNewClients: _prepayNewClients,
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
    // Часы и отзывы — чтобы предпросмотр совпадал с тем,
    // что реально видит клиент.
    WorkWeek? week;
    List<ProviderRating> ratings = const [];
    try {
      final wh = await _cloud.workHoursOf(_cloud.uid!);
      if (wh != null) week = WorkWeek.fromJson(wh);
      ratings = await _cloud.ratingsAbout(_cloud.uid!);
    } catch (_) {}
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => MasterPublicProfileView(
          master: previewCard,
          services: services,
          portfolio: _portfolio,
          week: week,
          ratings: ratings,
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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
        categories: _pickedCategories.toList(),
        description: _descController.text.trim(),
        address: address,
        lat: lat,
        lng: lng,
        prepayEnabled: _prepayEnabled,
        prepayAmount: prepayAmount,
        prepayLink: _prepayLinkController.text.trim(),
        prepayNewClients: _prepayNewClients,
        social: _socialController.text.trim(),
        phonePublic: _phonePublic,
        avatarUrl: _avatarUrl,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Профиль сохранён')));
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
      appBar: AppBar(title: Text(_isSalon ? 'Профиль салона' : 'Мой профиль')),
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
                                    ? Icon(
                                        Icons.person,
                                        color: scheme.onPrimary,
                                        size: 36,
                                      )
                                    : null,
                              ),
                            ),
                            if (_pickingAvatar)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: scheme.secondary,
                                child: Icon(
                                  Icons.camera_alt,
                                  size: 14,
                                  color: scheme.onSecondary,
                                ),
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
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall,
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
                // Мультивыбор видов услуг: салон «парикмахерская +
                // ресницы» находится в поиске по обоим фильтрам.
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Виды услуг (можно несколько)',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final c in _categories)
                      FilterChip(
                        label: Text(c),
                        selected: _pickedCategories.contains(c),
                        onSelected: _saving
                            ? null
                            : (sel) => setState(() {
                                if (sel) {
                                  _pickedCategories.add(c);
                                } else {
                                  _pickedCategories.remove(c);
                                }
                              }),
                      ),
                  ],
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
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
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
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Предоплата только для новых'),
                    subtitle: const Text(
                      'Первый визит клиента — по предоплате; после '
                      'завершённой записи он считается проверенным',
                    ),
                    value: _prepayNewClients,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _prepayNewClients = v),
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
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    color: scheme.surfaceContainerHighest,
                                    child: const Icon(
                                      Icons.broken_image_outlined,
                                    ),
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
                      onTap: _uploadingPhoto || _saving
                          ? null
                          : _addPortfolioPhoto,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: scheme.outline,
                            style: BorderStyle.solid,
                          ),
                          color: scheme.surfaceContainerHighest.withValues(
                            alpha: 0.4,
                          ),
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
                  Text(_error!, style: TextStyle(color: scheme.error)),
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
                  if (!_isSalon) ...[
                    const SizedBox(height: 12),
                    Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: Badge(
                          isLabelVisible: _invites.isNotEmpty,
                          label: Text('${_invites.length}'),
                          child: const Icon(Icons.mail_outline),
                        ),
                        title: const Text('Приглашения'),
                        subtitle: Text(
                          _invites.isEmpty
                              ? 'Запросы от салонов появятся здесь'
                              : 'Есть новые приглашения',
                        ),
                        onTap: _openInvites,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.schedule),
                          title: const Text('Рабочие часы'),
                          subtitle: const Text(
                            'Когда клиенты могут записаться',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (context) => const WorkHoursScreen(),
                            ),
                          ),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        ListTile(
                          leading: const Icon(Icons.reviews_outlined),
                          title: const Text('Отзывы обо мне'),
                          subtitle: const Text('Оценки клиентов и ответы'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (context) =>
                                  const ProviderReviewsScreen(),
                            ),
                          ),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        ListTile(
                          leading: const Icon(Icons.qr_code),
                          title: const Text('Поделиться профилем'),
                          subtitle: const Text('QR-код для клиентов'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => showProviderQrDialog(
                            context,
                            name: _nameController.text.trim(),
                            userId: _cloud.uid ?? '',
                          ),
                        ),
                      ],
                    ),
                  ),
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
                    onPressed: () => showAppearancePicker(context),
                    icon: const Icon(Icons.palette_outlined),
                    label: Text(
                      'Внешний вид · ${themeModeLabel(appThemeMode.value)}',
                    ),
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
  const MasterBookingsScreen({super.key, this.onBookingChanged});

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
      // Команда, заявки, отзывы и приглашения — параллельно.
      final results = await Future.wait([
        if (isSalon)
          _cloud
              .salonMasters()
              .then<List<MasterCard>>((v) => v)
              .catchError((_) => <MasterCard>[])
        else
          Future.value(<MasterCard>[]),
        if (isSalon)
          _cloud
              .myMasterCard()
              .then<MasterCard?>((v) => v)
              .catchError((_) => null)
        else
          Future<MasterCard?>.value(null),
        isSalon ? _cloud.salonBookings() : _cloud.masterBookings(),
        _cloud
            .myClientReviews()
            .then<List<ClientReview>>((v) => v)
            .catchError((_) => <ClientReview>[]),
        _cloud
            .myTeamInvites()
            .then<List<TeamInvite>>((v) => v)
            .catchError((_) => <TeamInvite>[]),
      ]);
      final team = results[0] as List<MasterCard>;
      final autoAssign = (results[1] as MasterCard?)?.autoAssign ?? false;
      final bookings = results[2] as List<CloudBooking>;
      final reviews = results[3] as List<ClientReview>;
      final invites = results[4] as List<TeamInvite>;
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
          content: Text('Сначала добавьте мастеров во вкладке «Мастера»'),
        ),
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
                  Expanded(child: Text(m.name.isEmpty ? 'Мастер' : m.name)),
                  if (b.masterId == m.userId) const Icon(Icons.check, size: 18),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Не удалось назначить: $e')));
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Не удалось переключить: $e')));
    }
  }

  /// Мастер отвечает на приглашение салона: принять → в команде.
  Future<void> _respondInvite(TeamInvite invite, bool accept) async {
    try {
      await _cloud.respondTeamInvite(invite, accept);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? 'Вы в команде салона — заявки будут приходить сюда'
                : 'Приглашение отклонено',
          ),
        ),
      );
      await _load();
    } catch (e) {
      await SyncLog.write('team_invite', e.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Не удалось ответить: $e')));
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
            'Мастер принял заявку на ${b.serviceName}',
          ),
          'cancelled' => (
            'Запись отменена',
            'Мастер отменил заявку на ${b.serviceName}',
          ),
          'completed' => (
            'Запись завершена',
            'Мастер завершил приём на ${b.serviceName}',
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
      if (status == 'cancelled') {
        // Освободилось окно — пушим подписчиков листа ожидания
        // (провайдера записи и салона, если заявка салонная).
        await _cloud.notifyWaitlist(b.masterId);
        if (b.salonId.isNotEmpty && b.salonId != b.masterId) {
          await _cloud.notifyWaitlist(b.salonId);
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
            IconButton(
              tooltip: 'Расписание команды',
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (context) => const TeamScheduleScreen(),
                ),
              ),
              icon: const Icon(Icons.calendar_view_week_outlined),
            ),
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
                  child: const Text('Автоназначение записей на мастеров'),
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
                      itemCount:
                          _invites.length +
                          _bookings.length +
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
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (_isSalon &&
                                    _masterLabel(b.masterId).isNotEmpty) ...[
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
                                        color: b.prepaymentStatus == 'confirmed'
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
                                        onPressed: () => _call(b.clientPhone),
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
                                        icon: const Icon(
                                          Icons.assignment_ind_outlined,
                                        ),
                                      ),
                                    if (b.prepaymentStatus == 'claimed')
                                      FilledButton.tonalIcon(
                                        onPressed: () => _confirmPrepay(b),
                                        icon: const Icon(
                                          Icons.payments_outlined,
                                        ),
                                        label: const Text('Оплата получена'),
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
  final _prepayAmount = TextEditingController();
  List<ClientReview> _reviews = [];
  bool _loading = true;
  bool _failed = false;
  bool _prepayRequired = false;
  bool _prepayBusy = false;

  /// Клиент в чёрном списке — запись ему запрещена.
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadPrepay();
  }

  @override
  void dispose() {
    _prepayAmount.dispose();
    super.dispose();
  }

  /// Персональное правило предоплаты для этого клиента.
  Future<void> _loadPrepay() async {
    try {
      final rule = await _cloud.clientPrepayRuleFor(widget.clientId);
      if (!mounted || rule == null) return;
      setState(() {
        _prepayRequired = rule.required;
        if (rule.amount > 0) {
          _prepayAmount.text = rule.amount.toStringAsFixed(0);
        }
      });
    } catch (_) {}
  }

  Future<void> _savePrepay() async {
    setState(() => _prepayBusy = true);
    try {
      final amount =
          double.tryParse(_prepayAmount.text.trim().replaceAll(' ', '')) ?? 0;
      await _cloud.setClientPrepay(widget.clientId, _prepayRequired, amount);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _prepayRequired
                ? 'Клиент будет записываться только по предоплате'
                : 'Персональная предоплата выключена',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Не удалось сохранить: $e')));
    } finally {
      if (mounted) setState(() => _prepayBusy = false);
    }
  }

  /// Подарить клиенту один из своих опубликованных Honey.
  Future<void> _giftHoney() async {
    List<SalonOffer> offers;
    try {
      offers = (await _cloud.myOffers()).where((o) => o.isLive).toList();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не удалось загрузить Honey: $e')));
      return;
    }
    if (!mounted) return;
    if (offers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'У вас пока нет активных Honey — создайте '
            'их в разделе Honey',
          ),
        ),
      );
      return;
    }
    final picked = await showDialog<SalonOffer>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Подарить Honey'),
        children: [
          for (final o in offers)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(o),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.card_giftcard),
                title: Text(o.title),
                subtitle: o.value.isNotEmpty ? Text(o.value) : null,
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await _cloud.giftOffer(picked.id, widget.clientId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('«${picked.title}» подарен клиенту')),
      );
      try {
        await PushNotificationService.sendPush(
          toUserId: widget.clientId,
          title: 'Вам подарили Honey',
          body: '«${picked.title}» — откройте вкладку Honey',
        );
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Не удалось подарить: $e')));
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final results = await Future.wait([
        _cloud.clientReviews(widget.clientId),
        _cloud
            .myBlockedClientIds()
            .then<Set<String>>((v) => v)
            .catchError((_) => <String>{}),
      ]);
      if (!mounted) return;
      setState(() {
        _reviews = results[0] as List<ClientReview>;
        _blocked = (results[1] as Set<String>).contains(widget.clientId);
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

  /// Чёрный список: клиент не сможет записаться ко мне/салону.
  Future<void> _toggleBlock() async {
    final name = widget.clientName.isEmpty ? 'Клиента' : widget.clientName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_blocked ? 'Разблокировать?' : 'В чёрный список?'),
        content: Text(
          _blocked
              ? '$name снова сможет записываться к вам.'
              : '$name не сможет записываться к вам — существующие '
                    'записи останутся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_blocked ? 'Разблокировать' : 'Заблокировать'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (_blocked) {
        await _cloud.unblockClient(widget.clientId);
      } else {
        await _cloud.blockClient(widget.clientId);
      }
      if (!mounted) return;
      setState(() => _blocked = !_blocked);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_blocked ? 'Клиент в чёрном списке' : 'Разблокирован'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Не удалось сохранить')));
    }
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
          IconButton(
            tooltip: _blocked ? 'Разблокировать' : 'В чёрный список',
            onPressed: _toggleBlock,
            icon: Icon(
              _blocked ? Icons.block : Icons.block_outlined,
              color: _blocked ? Theme.of(context).colorScheme.error : null,
            ),
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
                  TextButton(onPressed: _load, child: const Text('Повторить')),
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
                  if (_blocked)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer
                          .withValues(alpha: 0.4),
                      child: ListTile(
                        leading: Icon(
                          Icons.block,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        title: const Text('В чёрном списке'),
                        subtitle: const Text('Запись этому клиенту запрещена'),
                      ),
                    ),
                  const SizedBox(height: 8),
                  // Персональная предоплата для этого клиента.
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Принимать по предоплате'),
                            subtitle: const Text(
                              'Клиент увидит сумму предоплаты при записи',
                            ),
                            value: _prepayRequired,
                            onChanged: (v) =>
                                setState(() => _prepayRequired = v),
                          ),
                          if (_prepayRequired)
                            TextField(
                              controller: _prepayAmount,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Сумма предоплаты',
                                hintText: '5000',
                              ),
                            ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _prepayBusy ? null : _savePrepay,
                              child: _prepayBusy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Сохранить'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading: Icon(
                        Icons.card_giftcard,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: const Text('Подарить Honey'),
                      subtitle: const Text(
                        'Скидка или бонус лично этому клиенту',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _giftHoney,
                    ),
                  ),
                  // Сертификат на N визитов — пакетом дешевле,
                  // клиент возвращается за списанием визитов.
                  if (widget.clientId.isNotEmpty)
                    Card(
                      child: ListTile(
                        leading: Icon(
                          Icons.confirmation_number_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: const Text('Выдать сертификат'),
                        subtitle: const Text(
                          'Пакет визитов — клиент оплатит ими записи',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final ok = await showIssueCertificateDialog(
                            context,
                            clientId: widget.clientId,
                            clientName: name,
                          );
                          if (ok == true && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Сертификат выдан')),
                            );
                          }
                        },
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
          Text(
            widget.booking.clientName.isEmpty
                ? 'Клиент'
                : widget.booking.clientName,
          ),
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

/// Шторка записи из календаря («Записи»): детали облачной заявки
/// + завершение, отмена и оценка клиента — те же действия,
/// что в «Заявках клиентов».
class CloudBookingSheet extends StatefulWidget {
  const CloudBookingSheet({super.key, required this.bookingId, this.onChanged});

  final int bookingId;

  /// Дёргается после изменения заявки — родитель перечитывает календарь.
  final VoidCallback? onChanged;

  @override
  State<CloudBookingSheet> createState() => _CloudBookingSheetState();
}

class _CloudBookingSheetState extends State<CloudBookingSheet> {
  final _cloud = CloudService();
  CloudBooking? _booking;
  final _ratedIds = <int>{};
  bool _loading = true;
  bool _failed = false;
  bool _busy = false;

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
      final results = await Future.wait([
        _cloud.bookingById(widget.bookingId),
        _cloud.myClientReviews().catchError((_) => <ClientReview>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _booking = results[0] as CloudBooking?;
        _ratedIds
          ..clear()
          ..addAll([
            for (final r in results[1] as List<ClientReview>) r.bookingId,
          ]);
        _loading = false;
      });
    } catch (e, st) {
      await SyncLog.write('bookingSheet', '$e\n$st');
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
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

  Future<void> _setStatus(CloudBooking b, String status) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _cloud.setBookingStatus(b.id, status);
      widget.onChanged?.call();
      if (b.clientId.isNotEmpty) {
        final (title, body) = switch (status) {
          'confirmed' => (
            'Запись подтверждена',
            'Мастер принял заявку на ${b.serviceName}',
          ),
          'cancelled' => (
            'Запись отменена',
            'Мастер отменил заявку на ${b.serviceName}',
          ),
          'completed' => (
            'Запись завершена',
            'Мастер завершил приём на ${b.serviceName}',
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
      if (status == 'cancelled') {
        await _cloud.notifyWaitlist(b.masterId);
        if (b.salonId.isNotEmpty && b.salonId != b.masterId) {
          await _cloud.notifyWaitlist(b.salonId);
        }
      }
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось обновить статус')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmPrepay(CloudBooking b) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _cloud.setPrepaymentStatus(b.id, 'confirmed');
      widget.onChanged?.call();
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось подтвердить оплату')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rate(CloudBooking b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => RateClientDialog(booking: b),
    );
    if (ok == true) {
      widget.onChanged?.call();
      await _load();
    }
  }

  /// Перенос записи: день → свободный слот → новое время в облаке.
  Future<void> _reschedule(CloudBooking b) async {
    final day = await showDatePicker(
      context: context,
      initialDate: b.startsAt.isAfter(DateTime.now())
          ? b.startsAt
          : DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (day == null || !mounted) return;

    // Свободные слоты дня — по рабочим часам минус занятые записи.
    List<DateTime> slots = [];
    var slotsFailed = false;
    try {
      final results = await Future.wait([
        _cloud.masterBookingsForDay(b.masterId, day),
        _cloud
            .workHoursOf(b.masterId)
            .then<Map<String, dynamic>?>((v) => v)
            .catchError((_) => null),
        _cloud
            .scheduleBlocksFor(
              b.masterId,
              from: day,
              to: day.add(const Duration(days: 1)),
            )
            .then<List<ScheduleBlock>>((v) => v)
            .catchError((_) => <ScheduleBlock>[]),
      ]);
      final blocks = results[2] as List<ScheduleBlock>;
      slots = computeFreeSlots(
        day: day,
        durationMinutes: b.durationMinutes,
        busy: results[0] as List<CloudBooking>,
        week: WorkWeek.fromJson(results[1] as Map<String, dynamic>?),
        stepMinutes: slotStepFor(b.durationMinutes),
        blocked: [for (final bl in blocks) (bl.startsAt, bl.endsAt)],
      );
    } catch (_) {
      slotsFailed = true;
    }
    if (!mounted) return;

    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Свободное время',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (slotsFailed)
                const Text('Не удалось загрузить слоты — попробуйте позже')
              else if (slots.isEmpty)
                const Text('На этот день свободных окон нет')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in slots)
                      ActionChip(
                        label: Text(
                          '${s.hour.toString().padLeft(2, '0')}:'
                          '${s.minute.toString().padLeft(2, '0')}',
                        ),
                        onPressed: () => Navigator.of(ctx).pop(s),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await _cloud.rescheduleBooking(b.id, picked);
      widget.onChanged?.call();
      if (b.clientId.isNotEmpty) {
        await PushNotificationService.sendPush(
          toUserId: b.clientId,
          title: 'Запись перенесена',
          body: '${b.serviceName} — новое время ${_fmt(picked)}',
          data: {'appointment_id': b.id, 'status': b.status},
        );
      }
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось перенести запись')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  Future<void> _call(String phone) async {
    if (phone.isEmpty) return;
    await launchUrl(Uri.parse('tel:$phone'));
  }

  @override
  Widget build(BuildContext context) {
    final b = _booking;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _loading
            ? const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              )
            : _failed || b == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 24),
                  const Text('Не удалось загрузить запись'),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: _load,
                    child: const Text('Повторить'),
                  ),
                  const SizedBox(height: 16),
                ],
              )
            : _buildContent(context, b),
      ),
    );
  }

  Widget _buildContent(BuildContext context, CloudBooking b) {
    final rated = _ratedIds.contains(b.id);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                b.serviceName.isEmpty ? 'Запись' : b.serviceName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Chip(
              label: Text(_statusLabel(b.status)),
              backgroundColor: _statusColor(b.status).withValues(alpha: 0.15),
              side: BorderSide.none,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${b.clientName.isEmpty ? 'Клиент' : b.clientName}'
          '${b.clientPhone.isEmpty ? '' : ' • ${b.clientPhone}'}',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 4),
        Text(
          '${_fmt(b.startsAt)} • ${b.durationMinutes} мин'
          '${b.masterName.isEmpty || b.masterName == 'Я' ? '' : ' • ${b.masterName}'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (b.notes.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(b.notes, style: Theme.of(context).textTheme.bodySmall),
        ],
        if (b.prepaymentStatus != 'none') ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.payments_outlined,
                size: 16,
                color: b.prepaymentStatus == 'confirmed'
                    ? Colors.green
                    : Colors.orange,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  b.prepaymentStatus == 'confirmed'
                      ? 'Предоплата получена'
                      : 'Клиент отметил предоплату — проверьте поступление',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
        const Divider(height: 24),
        if (b.status == 'pending') ...[
          FilledButton.icon(
            onPressed: _busy ? null : () => _setStatus(b, 'confirmed'),
            icon: const Icon(Icons.check),
            label: const Text('Подтвердить'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _reschedule(b),
            icon: const Icon(Icons.schedule),
            label: const Text('Перенести'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _setStatus(b, 'cancelled'),
            icon: const Icon(Icons.close),
            label: const Text('Отклонить'),
          ),
        ],
        if (b.status == 'confirmed') ...[
          FilledButton.icon(
            onPressed: _busy ? null : () => _setStatus(b, 'completed'),
            icon: const Icon(Icons.done_all),
            label: const Text('Завершить'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _reschedule(b),
            icon: const Icon(Icons.schedule),
            label: const Text('Перенести'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _setStatus(b, 'cancelled'),
            icon: const Icon(Icons.close),
            label: const Text('Отменить запись'),
          ),
        ],
        if (b.status == 'completed' && b.clientId.isNotEmpty)
          rated
              ? Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 18,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Оценка отправлена',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                )
              : FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _rate(b),
                  icon: const Icon(Icons.star),
                  label: const Text('Оценить клиента'),
                ),
        if (b.prepaymentStatus == 'claimed') ...[
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : () => _confirmPrepay(b),
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Оплата получена'),
          ),
        ],
        const SizedBox(height: 4),
        Row(
          children: [
            if (b.clientId.isNotEmpty)
              Expanded(
                child: TextButton.icon(
                  onPressed: () => _openClient(b),
                  icon: const Icon(Icons.person),
                  label: const Text('Профиль клиента'),
                ),
              ),
            if (b.clientPhone.isNotEmpty)
              Expanded(
                child: TextButton.icon(
                  onPressed: () => _call(b.clientPhone),
                  icon: const Icon(Icons.call),
                  label: const Text('Позвонить'),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Вкладка «Мастера» у салона: ключ регистрации, команда из облака,
/// создание аккаунтов мастеров + локальный справочник ниже.
class SalonTeamScreen extends StatefulWidget {
  const SalonTeamScreen({super.key, required this.localDirectoryBuilder});

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
      // Ключ, команда и приглашения — параллельно.
      final results = await Future.wait([
        _cloud.ensureSalonKey(),
        _cloud.salonMasters(),
        _cloud
            .sentTeamInvites()
            .then<List<TeamInvite>>((v) => v)
            .catchError((_) => <TeamInvite>[]),
      ]);
      final key = results[0] as String;
      final team = results[1] as List<MasterCard>;
      final invites = results[2] as List<TeamInvite>;
      // Салон открыл «Мастера» — ответы мастеров считаем
      // просмотренными, бейдж на вкладке гаснет.
      try {
        await _cloud.markTeamResponsesSeen();
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
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Ключ скопирован')));
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Не удалось открепить: $e')));
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Не удалось: $e')));
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
  /// закрыты. Салон читает заявки своей команды по RLS-политике;
  /// дополнительно отрезаем записи, созданные до вступления мастера
  /// в салон (salon_since), — его личная история скрыта.
  Future<void> _showBookings(MasterCard m) async {
    List<CloudBooking> bookings;
    try {
      bookings = await _cloud.masterBookingsFor(
        m.userId,
        since: m.salonSince,
        // Только салонные заявки — личные записи мастера скрыты.
        salonId: _cloud.uid,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось загрузить записи: $e')),
      );
      return;
    }
    if (!mounted) return;
    final completed = bookings.where((b) => b.status == 'completed').toList();
    final cancelled = bookings.where((b) => b.status == 'cancelled').length;
    final sum = completed.fold<double>(0, (s, b) => s + b.servicePrice);
    String money(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Данные мастера обновлены')));
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

  /// Выбор контакта из телефонной книги — возвращает (имя, телефон).
  Future<(String, String)?> _pickPhoneContact() async {
    final status = await phone.FlutterContacts.permissions.request(
      phone.PermissionType.read,
    );
    if (status != phone.PermissionStatus.granted) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нет доступа к контактам — разрешите в настройках'),
        ),
      );
      return null;
    }
    if (!mounted) return null;
    return showDialog<(String, String)>(
      context: context,
      builder: (context) => const _PhoneContactPickerDialog(),
    );
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
                  OutlinedButton.icon(
                    onPressed: saving
                        ? null
                        : () async {
                            final picked = await _pickPhoneContact();
                            if (picked == null) return;
                            nameCtrl.text = picked.$1;
                            phoneCtrl.text = picked.$2;
                          },
                    icon: const Icon(Icons.contact_phone_outlined, size: 18),
                    label: const Text('Импорт из телефона'),
                  ),
                  const SizedBox(height: 12),
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
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('Ошибка: $err')));
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
                            _key.isEmpty ? '—' : (_showKey ? _key : '••••••••'),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(letterSpacing: 2),
                          ),
                        ),
                        IconButton(
                          tooltip: _showKey ? 'Скрыть' : 'Показать',
                          onPressed: () => setState(() => _showKey = !_showKey),
                          icon: Icon(
                            _showKey ? Icons.visibility_off : Icons.visibility,
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
                    m.category + (m.managedBySalon ? ' • аккаунт салона' : ''),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Приглашение отправлено')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Не удалось пригласить: $e')));
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
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(child: Center(child: Text('Ошибка: $_error')))
            else if (_searched && _results.isEmpty)
              const Expanded(child: Center(child: Text('Никого не найдено')))
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

/// Выбор одного контакта из телефонной книги — возвращает
/// (имя, телефон) для автозаполнения формы создания мастера.
class _PhoneContactPickerDialog extends StatefulWidget {
  const _PhoneContactPickerDialog();

  @override
  State<_PhoneContactPickerDialog> createState() =>
      _PhoneContactPickerDialogState();
}

class _PhoneContactPickerDialogState extends State<_PhoneContactPickerDialog> {
  List<phone.Contact> _contacts = [];
  final _searchController = TextEditingController();
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final list = await phone.FlutterContacts.getAll(
        properties: {phone.ContactProperty.phone},
      );
      list.sort((a, b) => (a.displayName ?? '').compareTo(b.displayName ?? ''));
      if (mounted) {
        setState(() {
          _contacts = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  bool _matches(phone.Contact c) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    if ((c.displayName ?? '').toLowerCase().contains(query)) return true;
    return c.phones.any((p) => p.number.toLowerCase().contains(query));
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _contacts.where(_matches).toList();
    return AlertDialog(
      title: const Text('Импорт из телефона'),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Поиск по имени или телефону',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_failed)
              const Expanded(
                child: Center(child: Text('Не удалось прочитать контакты')),
              )
            else if (filtered.isEmpty)
              const Expanded(child: Center(child: Text('Ничего не найдено')))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final c = filtered[i];
                    final number = c.phones.isNotEmpty
                        ? c.phones.first.number
                        : '';
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_outline),
                      title: Text(c.displayName ?? 'Без имени'),
                      subtitle: number.isEmpty ? null : Text(number),
                      onTap: () =>
                          Navigator.of(context)
                              .pop(((c.displayName ?? '').trim(), number)),
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
          child: const Text('Отмена'),
        ),
      ],
    );
  }
}
