import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../currency.dart';
// На вебе dart:io/FCM недоступны — заглушка с тем же API,
// sendPush внутри неё настоящий (Supabase Edge Function).
import '../notifications/push_stub.dart'
    if (dart.library.io) '../notifications/push_service.dart';
import 'cloud_service.dart';
import 'credentials_dialog.dart';
import 'geo_service.dart';
import 'map_screens.dart';
import 'master_public_profile.dart';
import 'offers_screens.dart';
import 'qr_share.dart';
import 'work_hours.dart';

/// Главный экран клиента: каталог мастеров, мои записи, профиль.
class ClientHome extends StatefulWidget {
  const ClientHome({
    super.key,
    required this.profile,
    required this.onSignOut,
    required this.onDeleteAccount,
    this.onProfileUpdated,
  });

  final CloudProfile profile;
  final Future<void> Function() onSignOut;
  final Future<void> Function() onDeleteAccount;
  final VoidCallback? onProfileUpdated;

  @override
  State<ClientHome> createState() => _ClientHomeState();
}

class _ClientHomeState extends State<ClientHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      ClientCatalogTab(profile: widget.profile),
      const ClientFavoritesTab(),
      ClientHoneyTab(
        // «Записаться» из предложения — профиль салона/мастера
        // с его услугами и кнопкой записи; само Honey едет
        // в диалог записи и режет цену на скидку.
        onBookOffer: (offer) => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (context) => MasterDetailScreen(
              offer: offer,
              // Карточка-заглушка: экран сам подтянет полный
              // профиль провайдера из облака.
              master: MasterCard(
                userId: offer.providerId,
                name: '',
                phone: '',
                category: '',
                description: '',
                address: '',
                social: '',
                phonePublic: false,
                avatarUrl: '',
                ratingAvg: 0,
                ratingCount: 0,
              ),
            ),
          ),
        ),
      ),
      const ClientBookingsTab(),
      _ClientProfileTab(
        profile: widget.profile,
        onSignOut: widget.onSignOut,
        onDeleteAccount: widget.onDeleteAccount,
        onProfileUpdated: widget.onProfileUpdated,
      ),
    ];
    return ValueListenableBuilder<bool>(
      valueListenable: appBizzyLook,
      builder: (context, look, _) {
        // «Вид Bizzy» — жёлтые акценты клиентского приложения
        // уходят в оранжевый; кнопки сами становятся градиентными
        // через bizzyFilledButton/bizzyFab.
        final scaffold = Scaffold(
          // Стеклянная тема: контент заходит под полупрозрачную
          // навигацию с блюром.
          extendBody: bizzyGlassActive(context),
          body: pages[_tab],
          bottomNavigationBar: bizzyNavBar(
            context,
            child: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.room_service_outlined),
                  selectedIcon: Icon(Icons.room_service),
                  label: 'Услуги',
                ),
                NavigationDestination(
                  icon: Icon(Icons.favorite_outline),
                  selectedIcon: Icon(Icons.favorite),
                  label: 'Избранное',
                ),
                NavigationDestination(
                  icon: Icon(Icons.card_giftcard_outlined),
                  selectedIcon: Icon(Icons.card_giftcard),
                  label: 'Honey',
                ),
                NavigationDestination(
                  icon: Icon(Icons.event_note_outlined),
                  selectedIcon: Icon(Icons.event_note),
                  label: 'Записи',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Профиль',
                ),
              ],
            ),
          ),
        );
        if (!look) return scaffold;
        return Theme(
          data: bizzyClientTheme(Theme.of(context)),
          child: scaffold,
        );
      },
    );
  }
}

// ==================== КАТАЛОГ МАСТЕРОВ ====================

Widget _masterAvatar(BuildContext context, MasterCard master, double radius) {
  final scheme = Theme.of(context).colorScheme;
  return CircleAvatar(
    radius: radius,
    backgroundColor: scheme.primary,
    backgroundImage: master.avatarUrl.isNotEmpty
        ? NetworkImage(master.avatarUrl)
        : null,
    child: master.avatarUrl.isEmpty
        ? Icon(Icons.person, color: scheme.onPrimary, size: radius)
        : null,
  );
}

class ClientCatalogTab extends StatefulWidget {
  const ClientCatalogTab({super.key, required this.profile});

  final CloudProfile profile;

  @override
  State<ClientCatalogTab> createState() => _ClientCatalogTabState();
}

class _ClientCatalogTabState extends State<ClientCatalogTab> {
  final _cloud = CloudService();
  final _geo = GeoService();
  final _searchController = TextEditingController();
  List<String> _categories = [];
  List<MasterCard> _masters = [];
  Set<String> _favorites = {};
  String? _category;
  String _kindFilter = 'all'; // 'all' | 'salon' | 'master'
  bool _loading = true;
  bool _failed = false;
  String _lastError = '';

  /// Координаты клиента: из профиля, либо определённые по GPS в этой сессии.
  double? _myLat;
  double? _myLng;

  @override
  void initState() {
    super.initState();
    _myLat = widget.profile.lat;
    _myLng = widget.profile.lng;
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Расстояние от клиента до мастера в км. null — если нет координат.
  double? _distanceTo(MasterCard m) {
    final lat = _myLat;
    final lng = _myLng;
    if (lat == null || lng == null || !m.hasLocation) return null;
    return GeoService.distanceKm(lat, lng, m.lat!, m.lng!);
  }

  /// Сначала мастера с координатами — по возрастанию расстояния,
  /// без координат — в конце в исходном порядке (по рейтингу).
  List<MasterCard> _sortedByDistance(List<MasterCard> list) {
    if (_myLat == null || _myLng == null) return list;
    final withDist = <(MasterCard, double)>[];
    final rest = <MasterCard>[];
    for (final m in list) {
      final d = _distanceTo(m);
      if (d == null) {
        rest.add(m);
      } else {
        withDist.add((m, d));
      }
    }
    withDist.sort((a, b) => a.$2.compareTo(b.$2));
    return [...withDist.map((e) => e.$1), ...rest];
  }

  /// Применяет фильтры «салон/частник» и поиск по адресу.
  List<MasterCard> get _visibleMasters {
    var list = _masters;
    if (_kindFilter == 'salon') {
      list = list.where((m) => m.isSalon).toList();
    } else if (_kindFilter == 'master') {
      list = list.where((m) => !m.isSalon).toList();
    }
    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where(
            (m) =>
                m.address.toLowerCase().contains(q) ||
                m.name.toLowerCase().contains(q),
          )
          .toList();
    }
    return list;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      // Категории, мастера и избранное — параллельно, каталог
      // открывается за один раунд-трип.
      final results = await Future.wait([
        _cloud.categories(),
        _cloud.masters(category: _category),
        _cloud
            .myFavoriteIds()
            .then<Set<String>>((v) => v)
            .catchError((_) => <String>{}),
      ]);
      final categories = results[0] as List<String>;
      final masters = results[1] as List<MasterCard>;
      final favorites = results[2] as Set<String>;
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _masters = _sortedByDistance(masters);
        _favorites = favorites;
      });
    } catch (e, st) {
      await SyncLog.write('client_catalog', '$e\n$st');
      if (!mounted) return;
      setState(() {
        _failed = true;
        _lastError = '$e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Определяет положение клиента по GPS и пересортировывает список.
  /// Тихий режим — без снэкбаров (вызывается при открытии карты).
  Future<void> _detectLocation({bool quiet = false}) async {
    try {
      final point = await _geo.currentPosition();
      if (!mounted) return;
      setState(() {
        _myLat = point.lat;
        _myLng = point.lng;
        _masters = _sortedByDistance(_masters);
      });
      if (!quiet && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Геопозиция определена')));
      }
    } catch (e) {
      if (!mounted || quiet) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _toggleFavorite(MasterCard m) async {
    try {
      final added = await _cloud.toggleFavorite(m.userId);
      if (!mounted) return;
      setState(() {
        if (added) {
          _favorites.add(m.userId);
        } else {
          _favorites.remove(m.userId);
        }
      });
    } catch (e) {
      await SyncLog.write('favorite_toggle', e.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось обновить избранное: $e')),
      );
    }
  }

  void _openMap() {
    // Геопозиция определяется внутри карты автоматически;
    // если уже известна — передаём, чтобы центрировать мгновенно.
    if (_myLat == null) _detectLocation(quiet: true);
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => MastersMapScreen(
          masters: _visibleMasters,
          clientLat: _myLat,
          clientLng: _myLng,
          onOpen: _openMaster,
        ),
      ),
    );
  }

  Future<void> _openMaster(MasterCard master) async {
    final booked = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => MasterDetailScreen(master: master),
      ),
    );
    if (booked == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заявка отправлена мастеру')),
      );
    }
  }

  /// Сканирование QR провайдера: код несёт его userId,
  /// после сканирования сразу открываем публичный профиль.
  Future<void> _openQrScanner() async {
    final providerId = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ProviderQrScanScreen()),
    );
    if (providerId == null || providerId.isEmpty || !mounted) return;
    try {
      final master = await _cloud.masterCard(providerId);
      if (!mounted) return;
      if (master == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Профиль по этому QR не найден')),
        );
        return;
      }
      await _openMaster(master);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть профиль')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Привет, ${widget.profile.name.isEmpty ? 'клиент' : widget.profile.name}!',
        ),
        actions: [
          IconButton(
            tooltip: 'Сканировать QR мастера',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _openQrScanner,
          ),
          IconButton(
            tooltip: 'Мастера на карте',
            icon: const Icon(Icons.map_outlined),
            onPressed: _loading ? null : _openMap,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Не удалось загрузить каталог'),
                    if (_lastError.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _lastError,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    TextButton(
                      onPressed: _load,
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Город, район, улица или имя…',
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        border: const OutlineInputBorder(),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () =>
                                    setState(() => _searchController.clear()),
                              ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 52,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: const Text('Все'),
                            selected: _kindFilter == 'all',
                            onSelected: (_) =>
                                setState(() => _kindFilter = 'all'),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            avatar: const Icon(Icons.storefront, size: 16),
                            label: const Text('Салоны'),
                            selected: _kindFilter == 'salon',
                            onSelected: (_) =>
                                setState(() => _kindFilter = 'salon'),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            avatar: const Icon(Icons.person, size: 16),
                            label: const Text('Частные мастера'),
                            selected: _kindFilter == 'master',
                            onSelected: (_) =>
                                setState(() => _kindFilter = 'master'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 52,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: const Text('Все категории'),
                            selected: _category == null,
                            onSelected: (_) {
                              setState(() => _category = null);
                              _load();
                            },
                          ),
                        ),
                        for (final c in _categories)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Text(c),
                              selected: _category == c,
                              onSelected: (_) {
                                setState(() => _category = c);
                                _load();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_visibleMasters.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          _masters.isEmpty
                              ? 'Пока нет ни одного мастера или салона.\n'
                                    'Они появятся в каталоге после регистрации.'
                              : 'По вашему запросу никого не нашлось',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  for (final m in _visibleMasters)
                    Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: ListTile(
                        leading: _masterAvatar(context, m, 24),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                m.name.isEmpty
                                    ? (m.isSalon ? 'Салон' : 'Мастер')
                                    : m.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (m.isSalon) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.storefront,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ],
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.category),
                            Row(
                              children: [
                                const Icon(
                                  Icons.star,
                                  size: 16,
                                  color: Colors.amber,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  m.ratingCount == 0
                                      ? 'Новый'
                                      : '${m.ratingAvg.toStringAsFixed(1)} (${m.ratingCount})',
                                ),
                              ],
                            ),
                            if (_distanceTo(m) != null)
                              Row(
                                children: [
                                  Icon(
                                    Icons.place_outlined,
                                    size: 14,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${GeoService.formatDistance(_distanceTo(m)!)} от вас',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                  ),
                                ],
                              ),
                            if (bizzySince(m.createdAt).isNotEmpty)
                              Text(
                                bizzySince(m.createdAt),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          icon: Icon(
                            _favorites.contains(m.userId)
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: _favorites.contains(m.userId)
                                ? Colors.redAccent
                                : null,
                          ),
                          onPressed: () => _toggleFavorite(m),
                        ),
                        onTap: () => _openMaster(m),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

// ==================== ИЗБРАННОЕ ====================

/// Вкладка «Избранное»: любимые мастера и салоны клиента.
/// Отсюда можно сразу открыть профиль и записаться.
class ClientFavoritesTab extends StatefulWidget {
  const ClientFavoritesTab({super.key});

  @override
  State<ClientFavoritesTab> createState() => _ClientFavoritesTabState();
}

class _ClientFavoritesTabState extends State<ClientFavoritesTab> {
  final _cloud = CloudService();
  List<MasterCard> _masters = [];
  bool _loading = true;
  bool _failed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
      _error = null;
    });
    try {
      final masters = await _cloud.favoriteMasters();
      if (!mounted) return;
      setState(() => _masters = masters);
    } catch (e, st) {
      await SyncLog.write('client_favorites', '$e\n$st');
      if (!mounted) return;
      setState(() {
        _failed = true;
        _error = '$e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove(MasterCard m) async {
    try {
      await _cloud.toggleFavorite(m.userId);
      if (!mounted) return;
      setState(() => _masters.removeWhere((x) => x.userId == m.userId));
    } catch (e) {
      await SyncLog.write('favorite_remove', e.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось убрать из избранного: $e')),
      );
    }
  }

  Future<void> _openMaster(MasterCard master) async {
    final booked = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => MasterDetailScreen(master: master),
      ),
    );
    if (booked == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заявка отправлена мастеру')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Избранное')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Не удалось загрузить избранное'),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  TextButton(onPressed: _load, child: const Text('Повторить')),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: _masters.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Text(
                            'Пока пусто.\nОтметьте мастера сердечком '
                            'во вкладке «Услуги».',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        for (final m in _masters)
                          Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            child: ListTile(
                              leading: _masterAvatar(context, m, 24),
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      m.name.isEmpty
                                          ? (m.isSalon ? 'Салон' : 'Мастер')
                                          : m.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (m.isSalon) ...[
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.storefront,
                                      size: 16,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m.category),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.star,
                                        size: 16,
                                        color: Colors.amber,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        m.ratingCount == 0
                                            ? 'Новый'
                                            : '${m.ratingAvg.toStringAsFixed(1)} (${m.ratingCount})',
                                      ),
                                    ],
                                  ),
                                  if (m.address.isNotEmpty)
                                    Text(
                                      m.address,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.favorite,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () => _remove(m),
                              ),
                              onTap: () => _openMaster(m),
                            ),
                          ),
                      ],
                    ),
            ),
    );
  }
}

/// Карточка мастера: профиль, услуги, кнопка записи.
class MasterDetailScreen extends StatefulWidget {
  const MasterDetailScreen({
    super.key,
    required this.master,
    this.offer,
    this.prebookServiceIds = const [],
  });

  final MasterCard master;

  /// Honey, из которого пришёл клиент — скидка применится
  /// к цене в диалоге записи.
  final SalonOffer? offer;

  /// «Записаться снова»: id услуг прошлого визита — после загрузки
  /// профиля диалог записи откроется сразу с выбранными услугами.
  final List<int> prebookServiceIds;

  @override
  State<MasterDetailScreen> createState() => _MasterDetailScreenState();
}

class _MasterDetailScreenState extends State<MasterDetailScreen> {
  final _cloud = CloudService();
  MasterCard? _master;
  List<CloudServiceItem> _services = [];
  List<PortfolioPhoto> _portfolio = [];
  List<SalonOffer> _offers = [];
  Set<String> _favoriteIds = {};
  WorkWeek? _week;
  List<ProviderRating> _ratings = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _master = widget.master;
    _load();
  }

  Future<void> _toggleFavorite() async {
    final id = widget.master.userId;
    final was = _favoriteIds.contains(id);
    setState(() => was ? _favoriteIds.remove(id) : _favoriteIds.add(id));
    try {
      await _cloud.toggleFavorite(id);
    } catch (e) {
      await SyncLog.write('favorite_toggle', e.toString());
      if (mounted) {
        setState(() => was ? _favoriteIds.add(id) : _favoriteIds.remove(id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось обновить избранное: $e')),
        );
      }
    }
  }

  Future<void> _load() async {
    try {
      // Всё независимое — параллельно: профиль открывается за один
      // раунд-трип. Вторичные блоки (портфолио, избранное, Honey)
      // не валят экран при ошибке.
      final pid = widget.master.userId;
      final results = await Future.wait([
        _cloud.masterCard(pid),
        _cloud.servicesOf(pid),
        _cloud
            .portfolioOf(pid)
            .then<List<PortfolioPhoto>>((v) => v)
            .catchError((_) => <PortfolioPhoto>[]),
        _cloud
            .myFavoriteIds()
            .then<Set<String>>((v) => v)
            .catchError((_) => <String>{}),
        _cloud
            .offersOf(pid)
            .then<List<SalonOffer>>((v) => v)
            .catchError((_) => <SalonOffer>[]),
        _cloud
            .myRedeemedOfferIds()
            .then<Set<int>>((v) => v)
            .catchError((_) => <int>{}),
        // Часы работы и отзывы — секции публичного профиля.
        _cloud.workHoursOf(pid).catchError((_) => null),
        _cloud
            .ratingsAbout(pid)
            .then<List<ProviderRating>>((v) => v)
            .catchError((_) => <ProviderRating>[]),
      ]);
      final rawServices = results[1] as List<CloudServiceItem>;
      final portfolio = results[2] as List<PortfolioPhoto>;
      final favs = results[3] as Set<String>;
      final usedIds = results[5] as Set<int>;
      final offers = [
        for (final o in results[4] as List<SalonOffer>)
          usedIds.contains(o.id) ? o.copyUsed() : o,
      ];
      if (!mounted) return;
      setState(() {
        _master = (results[0] as MasterCard?) ?? widget.master;
        _services = rawServices.where((s) => s.published).toList();
        _portfolio = portfolio;
        _favoriteIds = favs;
        _offers = offers;
        final wh = results[6] as Map<String, dynamic>?;
        _week = wh == null ? null : WorkWeek.fromJson(wh);
        _ratings = results[7] as List<ProviderRating>;
        _loading = false;
      });
      // «Записаться снова» — открываем диалог с услугами прошлого визита.
      if (widget.prebookServiceIds.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _book(null, null, widget.prebookServiceIds);
        });
      }
    } catch (e, st) {
      await SyncLog.write('master_detail', '$e\n$st');
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить профиль мастера';
        _loading = false;
      });
    }
  }

  Future<void> _book([
    CloudServiceItem? service,
    SalonOffer? offer,
    List<int> serviceIds = const [],
  ]) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => BookAppointmentDialog(
        master: _master ?? widget.master,
        services: _services,
        offer: offer ?? widget.offer,
        initialService: service,
        initialServiceIds: serviceIds,
      ),
    );
    if (result == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ошибка')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!),
              const SizedBox(height: 12),
              TextButton(onPressed: _load, child: const Text('Повторить')),
            ],
          ),
        ),
      );
    }
    return MasterPublicProfileView(
      master: _master ?? widget.master,
      services: _services,
      portfolio: _portfolio,
      offers: _offers,
      week: _week,
      ratings: _ratings,
      onBook: () => _book(),
      // Тап по услуге — запись сразу с выбранной услугой.
      onBookService: _book,
      // Тап по Honey — запись сразу с этой скидкой.
      onBookOffer: (o) => _book(null, o),
      onRefresh: _load,
      isFavorite: _favoriteIds.contains(widget.master.userId),
      onToggleFavorite: _toggleFavorite,
    );
  }
}

/// Диалог записи к мастеру: услуга + дата + время + комментарий.
class BookAppointmentDialog extends StatefulWidget {
  const BookAppointmentDialog({
    super.key,
    required this.master,
    required this.services,
    this.offer,
    this.initialService,
    this.initialServiceIds = const [],
  });

  final MasterCard master;
  final List<CloudServiceItem> services;

  /// Honey, по которому записывается клиент: действующая скидка
  /// режет цену выбранной услуги, подарок гасится после записи.
  final SalonOffer? offer;

  /// Услуга, по которой тапнули в профиле — сразу выбрана.
  final CloudServiceItem? initialService;

  /// «Записаться снова»: id услуг прошлого визита — совпавшие
  /// с текущим прайсом выбираются сразу.
  final List<int> initialServiceIds;

  @override
  State<BookAppointmentDialog> createState() => _BookAppointmentDialogState();
}

class _BookAppointmentDialogState extends State<BookAppointmentDialog> {
  final _cloud = CloudService();
  final _customService = TextEditingController();
  final _notes = TextEditingController();

  /// Выбранные услуги — клиент может взять несколько за один визит.
  final Set<CloudServiceItem> _services = {};
  DateTime _date = DateTime.now();
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  DateTime? _selectedSlot;
  List<DateTime> _slots = [];
  bool _loadingSlots = false;
  bool _saving = false;
  String? _error;
  bool _prepayDone = false;

  /// Расписание провайдера — слоты строятся только внутри рабочих часов.
  WorkWeek? _week;

  /// Провайдер добавил клиента в чёрный список — запись закрыта.
  bool _blocked = false;

  /// Персональное правило предоплаты от мастера/салона
  /// (сильнее общего prepayEnabled — задаётся конкретному клиенту).
  ({double amount})? _clientPrepay;

  /// У провайдера включена «предоплата для новых», а у меня ещё
  /// нет завершённых визитов к нему — запись только по предоплате.
  bool _newClientPrepay = false;

  /// Я подписан на освобождение окна у этого провайдера.
  bool _waiting = false;

  /// Действующие сертификаты этого провайдера у меня.
  List<Certificate> _certs = const [];

  /// Выбранный для оплаты визита сертификат.
  Certificate? _selectedCert;

  /// Моя реферальная скидка в % (применяется к этой записи).
  int _refDiscount = 0;

  bool get _needsPrepay =>
      // Визит по сертификату уже оплачен пакетом — предоплата не нужна.
      _selectedCert == null &&
      (_clientPrepay != null ||
          widget.master.prepayEnabled ||
          _newClientPrepay);

  /// Сумма предоплаты: персональная по клиенту, иначе общая у мастера.
  double get _prepayAmount => _clientPrepay != null && _clientPrepay!.amount > 0
      ? _clientPrepay!.amount
      : widget.master.prepayAmount;

  /// Суммарная длительность визита: выбранные услуги складываются.
  int get _totalDuration => _services.isEmpty
      ? 60
      : _services.fold(0, (sum, s) => sum + s.durationMinutes);

  /// Полная цена без скидки.
  double get _fullPrice => _services.fold(0.0, (sum, s) => sum + s.price);

  /// Действует ли скидка Honey хотя бы на одну выбранную услугу.
  /// Использованный Honey скидку не даёт — только инфо-баннер.
  bool get _offerApplies {
    final o = widget.offer;
    return o != null &&
        o.isLive &&
        !o.used &&
        o.discountPercent > 0 &&
        (_services.isEmpty
            ? o.appliesTo(null)
            : _services.any((s) => o.appliesTo(s.id)));
  }

  /// Итоговая цена: скидка применяется к каждой услуге, на которую
  /// действует Honey; остальные идут по полной цене.
  double get _finalPrice {
    final o = widget.offer;
    if (o == null || !o.isLive || o.used || o.discountPercent <= 0) {
      return _fullPrice;
    }
    if (_services.isEmpty) {
      return o.appliesTo(null) ? o.discountedPrice(0) : 0;
    }
    return _services.fold(
      0.0,
      (sum, s) =>
          sum + (o.appliesTo(s.id) ? o.discountedPrice(s.price) : s.price),
    );
  }

  /// Сколько останется доплатить на месте после предоплаты (не ниже 0).
  double get _remainingAfterPrepay {
    final left = _priceAfterRef - _prepayAmount;
    return left < 0 ? 0 : left;
  }

  /// Цена после реферальной скидки «приведи друга».
  double get _priceAfterRef =>
      _finalPrice * (100 - _refDiscount.clamp(0, 100)) / 100;

  /// Сумма, которая пойдёт в запись: визит по сертификату — 0.
  double get _chargePrice => _selectedCert != null ? 0 : _priceAfterRef;

  @override
  void initState() {
    super.initState();
    // Тап по услуге в профиле — она сразу выбрана в диалоге.
    if (widget.initialService != null) _services.add(widget.initialService!);
    // «Записаться снова» — предвыбор услуг прошлого визита.
    for (final id in widget.initialServiceIds) {
      for (final s in widget.services) {
        if (s.id == id) _services.add(s);
      }
    }
    _loadSlots(_date);
    _loadClientPrepay();
    _loadWorkHours();
    _checkBlocked();
    _loadExtras();
  }

  /// Лист ожидания, сертификаты, реферальная скидка и статус
  /// «проверенный клиент» — всё фоново, без блокировки диалога.
  Future<void> _loadExtras() async {
    if (widget.master.userId.isEmpty) return;
    final pid = widget.master.userId;
    try {
      final results = await Future.wait([
        _cloud.isWaitingFor(pid),
        _cloud.myCertificates().then<List<Certificate>>((v) => v),
        _cloud.myProfile(),
        _cloud.completedVisitsTo(pid),
      ]);
      if (!mounted) return;
      final certs = results[1] as List<Certificate>;
      final profile = results[2] as CloudProfile?;
      final visits = results[3] as int;
      setState(() {
        _waiting = results[0] as bool;
        _certs = certs
            .where(
              (c) =>
                  c.providerId == pid &&
                  !c.exhausted &&
                  c.covers(_services.map((s) => s.id).toList()),
            )
            .toList();
        _refDiscount = profile?.refDiscount ?? 0;
        _newClientPrepay = widget.master.prepayNewClients && visits == 0;
      });
    } catch (_) {}
  }

  /// Расписание мастера/салона: слоты строятся внутри рабочих часов,
  /// выходные без окон. Не задано — дефолтные 9:00–18:00 каждый день.
  Future<void> _loadWorkHours() async {
    if (widget.master.userId.isEmpty) return;
    try {
      final raw = await _cloud.workHoursOf(widget.master.userId);
      if (!mounted) return;
      setState(() => _week = WorkWeek.fromJson(raw));
      // Часы пришли позже первой загрузки — пересчитываем слоты.
      await _loadSlots(_date);
    } catch (_) {}
  }

  /// Чёрный список: провайдер закрыл запись этому клиенту.
  Future<void> _checkBlocked() async {
    if (widget.master.userId.isEmpty) return;
    try {
      final blocked = await _cloud.isBlockedBy(widget.master.userId);
      if (blocked && mounted) setState(() => _blocked = true);
    } catch (_) {}
  }

  /// Персональная предоплата: мастер/салон мог пометить именно
  /// этого клиента как «только по предоплате» со своей суммой.
  Future<void> _loadClientPrepay() async {
    if (widget.master.userId.isEmpty) return;
    try {
      final rule = await _cloud.clientPrepayRule(widget.master.userId);
      if (!mounted || rule == null) return;
      setState(() => _clientPrepay = rule);
    } catch (_) {}
  }

  @override
  void dispose() {
    _customService.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadSlots(DateTime day) async {
    if (widget.master.userId.isEmpty) return;
    setState(() => _loadingSlots = true);
    try {
      final results = await Future.wait([
        _cloud.masterBookingsForDay(widget.master.userId, day),
        _cloud
            .scheduleBlocksFor(
              widget.master.userId,
              from: day,
              to: day.add(const Duration(days: 1)),
            )
            .then<List<ScheduleBlock>>((v) => v),
      ]);
      final bookings = results[0] as List<CloudBooking>;
      final blocks = results[1] as List<ScheduleBlock>;
      final slots = computeFreeSlots(
        day: day,
        durationMinutes: _totalDuration,
        busy: bookings,
        week: _week,
        // Шаг сетки — под длительность выбранных услуг: между
        // слотами не остаётся дыр, куда запись не помещается.
        stepMinutes: slotStepFor(_totalDuration),
        blocked: [for (final b in blocks) (b.startsAt, b.endsAt)],
      );
      if (!mounted) return;
      setState(() {
        _slots = slots;
        _selectedSlot = slots.firstOrNull;
        _loadingSlots = false;
        if (_selectedSlot != null) {
          _time = TimeOfDay.fromDateTime(_selectedSlot!);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingSlots = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
      await _loadSlots(picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null && mounted) setState(() => _time = picked);
  }

  /// Открывает pay-ссылку мастера (Kaspi и т.п.) во внешнем приложении.
  Future<void> _pay() async {
    final link = widget.master.prepayLink.trim();
    if (link.isEmpty) return;
    final uri = Uri.tryParse(link);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ссылка на оплату недоступна')),
      );
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Связаться с мастером/салоном для внесения предоплаты:
  /// сначала звонок, если телефона нет — соцсеть/мессенджер.
  Future<void> _contactMaster() async {
    final phone = widget.master.phone.trim();
    if (phone.isNotEmpty) {
      await launchUrl(Uri(scheme: 'tel', path: phone));
      return;
    }
    final social = widget.master.social.trim();
    if (social.isNotEmpty) {
      final uri = Uri.tryParse(
        social.startsWith('http') ? social : 'https://$social',
      );
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Контакты не указаны')));
    }
  }

  Future<void> _submit() async {
    if (_saving) return;
    final custom = _customService.text.trim();
    if (_services.isEmpty && custom.isEmpty) {
      setState(() => _error = 'Выберите услугу или напишите свою');
      return;
    }
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
    try {
      var masterId = widget.master.userId;
      // Салон с автоназначением: заявку получает наименее
      // загруженный на дату мастер. При ошибке — как раньше, салону.
      if (widget.master.isSalon && widget.master.autoAssign) {
        try {
          final picked = await _cloud.pickSalonMaster(masterId, startsAt);
          if (picked != null) masterId = picked;
        } catch (_) {}
      }
      // Заметка «по Honey» — мастер видит, что запись пришла
      // по акции, даже без отдельного поля в старой базе.
      var notes = _notes.text.trim();
      final offer = widget.offer;
      // Разовое использование: если Honey уже погашен — записываем
      // без скидки? Нет: предложение использовано — отменяем запись
      // по нему, пусть клиент бронирует обычную цену осознанно.
      if (offer != null && offer.isLive && !offer.used) {
        try {
          if (await _cloud.hasRedeemed(offer.id)) {
            if (!mounted) return;
            setState(() {
              _saving = false;
              _error = 'Вы уже использовали этот Honey';
            });
            return;
          }
        } catch (_) {}
      }
      if (offer != null && offer.isLive) {
        notes = notes.isEmpty
            ? 'По Honey «${offer.title}»'
            : '$notes · По Honey «${offer.title}»';
      }
      if (_selectedCert != null) {
        notes = notes.isEmpty
            ? 'Оплачено сертификатом «${_selectedCert!.title}»'
            : '$notes · Оплачено сертификатом «${_selectedCert!.title}»';
      }
      if (_refDiscount > 0 && _selectedCert == null) {
        notes = notes.isEmpty
            ? 'Реферальная скидка $_refDiscount%'
            : '$notes · Реферальная скидка $_refDiscount%';
      }
      final booking = await _cloud.bookAppointment(
        masterId: masterId,
        serviceId: _services.isEmpty ? null : _services.first.id,
        serviceIds: _services.isEmpty
            ? null
            : _services.map((s) => s.id).toList(),
        serviceName: _services.isEmpty
            ? custom
            : _services.map((s) => s.name).join(' + '),
        // Запись «в салон» — салон видит её и после назначения
        // мастеру. У частного мастера заявка личная.
        salonId: widget.master.isSalon ? widget.master.userId : null,
        startsAt: startsAt,
        durationMinutes: _totalDuration,
        // Цена УЖЕ со скидками (Honey + реферальная); по
        // сертификату визит оплачен пакетом — сумма 0.
        servicePrice: _chargePrice,
        offerId: offer?.id,
        notes: notes,
        prepaymentStatus: _needsPrepay ? 'claimed' : 'none',
      );
      // Погашаем Honey: подарок исчезает из блока «Подарено вам»,
      // а в offer_redemptions остаётся отметка «Использовано» —
      // повторно это предложение применить нельзя.
      if (offer != null && offer.isLive && !offer.used) {
        try {
          await _cloud.redeemOffer(offer.id, booking.id);
        } catch (_) {}
        if (offer.isGift) {
          try {
            await _cloud.consumeGift(offer.id);
          } catch (_) {}
        }
      }
      // Списываем визит сертификата и реферальную скидку —
      // обе «валюты» расходуются в момент успешной записи.
      final cert = _selectedCert;
      if (cert != null) {
        try {
          await _cloud.spendCertificate(cert);
        } catch (_) {}
      }
      if (_refDiscount > 0) {
        try {
          await _cloud.consumeRefDiscount();
        } catch (_) {}
      }
      // Записавшийся клиент больше не ждёт окно у этого провайдера.
      try {
        await _cloud.leaveWaitlist(widget.master.userId);
      } catch (_) {}
      await PushNotificationService.sendPush(
        toUserId: booking.masterId,
        title: 'Новая заявка',
        body:
            '${booking.clientName.isEmpty ? 'Клиент' : booking.clientName} записался на ${booking.serviceName}',
        data: {'appointment_id': booking.id, 'status': 'pending'},
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Не удалось отправить заявку';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateText =
        '${_date.day.toString().padLeft(2, '0')}.${_date.month.toString().padLeft(2, '0')}.${_date.year}';
    final timeText =
        '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
    return AlertDialog(
      title: Text('Запись к ${widget.master.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Баннер Honey, из которого пришла запись.
            if (widget.offer != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiaryContainer
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.offer!.isGift ? Icons.redeem : Icons.card_giftcard,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.offer!.used
                            ? 'Honey «${widget.offer!.title}» уже использован'
                            : widget.offer!.isLive
                            ? 'Honey «${widget.offer!.title}»'
                                  '${widget.offer!.discountPercent > 0 ? ' · −${widget.offer!.discountPercent.toStringAsFixed(0)}%' : ''}'
                            : 'Срок Honey «${widget.offer!.title}» истёк — '
                                  'скидка не применяется',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (widget.services.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Услуги — можно выбрать несколько',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final s in widget.services)
                    FilterChip(
                      label: Text('${s.name} • ${s.price.toStringAsFixed(0)}'),
                      selected: _services.contains(s),
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _services.add(s);
                          } else {
                            _services.remove(s);
                          }
                        });
                        _loadSlots(_date);
                      },
                    ),
                ],
              ),
            ],
            // Своя услуга — только когда ничего не выбрано из списка.
            if (_services.isEmpty) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _customService,
                decoration: const InputDecoration(
                  labelText: 'Название услуги',
                  hintText: 'Например: массаж спины',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            // Сумма визита: со скидкой Honey — зачёркнутая старая + итоговая.
            if (_services.isNotEmpty && _fullPrice > 0) ...[
              const SizedBox(height: 8),
              if (_offerApplies)
                Row(
                  children: [
                    Text(
                      formatMoney(_fullPrice),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        decoration: TextDecoration.lineThrough,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      formatMoney(_priceAfterRef),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  'Итого: ${formatMoney(_priceAfterRef)} • $_totalDuration мин',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(dateText),
                  ),
                ),
                const SizedBox(width: 8),
                if (_slots.isEmpty)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Icons.access_time, size: 18),
                      label: Text(timeText),
                    ),
                  )
                else
                  Expanded(
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      child: Text(timeText),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loadingSlots)
              const Center(child: CircularProgressIndicator())
            else if (_slots.isEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Свободных часов на эту дату нет.'),
                  const SizedBox(height: 8),
                  // Лист ожидания: провайдер отменит чужую запись —
                  // клиенту придёт push «освободилось окно».
                  OutlinedButton.icon(
                    onPressed: _waiting
                        ? () async {
                            await _cloud.leaveWaitlist(widget.master.userId);
                            if (mounted) {
                              setState(() => _waiting = false);
                            }
                          }
                        : () async {
                            await _cloud.joinWaitlist(widget.master.userId);
                            if (!context.mounted) return;
                            setState(() => _waiting = true);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Сообщим, когда освободится окно',
                                ),
                              ),
                            );
                          },
                    icon: Icon(
                      _waiting
                          ? Icons.notifications_active
                          : Icons.notifications_none,
                      size: 18,
                    ),
                    label: Text(
                      _waiting
                          ? 'Вы в листе ожидания — убрать подписку'
                          : 'Сообщить, когда освободится',
                    ),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Свободные часы:'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final slot in _slots)
                        ChoiceChip(
                          label: Text(
                            '${slot.hour.toString().padLeft(2, '0')}:${slot.minute.toString().padLeft(2, '0')}',
                          ),
                          selected: _selectedSlot == slot,
                          onSelected: (_) {
                            setState(() {
                              _selectedSlot = slot;
                              _time = TimeOfDay.fromDateTime(slot);
                            });
                          },
                        ),
                    ],
                  ),
                ],
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Комментарий (необязательно)',
                border: OutlineInputBorder(),
              ),
            ),
            // Сертификаты: визит можно оплатить пакетом — сумма 0.
            if (_certs.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final c in _certs)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _selectedCert?.id == c.id,
                  onChanged: _saving
                      ? null
                      : (v) => setState(
                          () => _selectedCert = v == true ? c : null,
                        ),
                  title: Text(c.title),
                  subtitle: Text(
                    'Осталось визитов: ${c.remaining} из ${c.totalVisits}'
                    '${c.providerName.isEmpty ? '' : ' · ${c.providerName}'}',
                  ),
                ),
            ],
            if (_refDiscount > 0 && _selectedCert == null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.card_giftcard,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Реферальная скидка $_refDiscount%: '
                      '${formatMoney(_priceAfterRef)} вместо '
                      '${formatMoney(_finalPrice)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
            if (_needsPrepay) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer
                      .withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.payments_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${widget.master.isSalon ? 'Салон' : 'Мастер'} '
                            'принимает вас по предоплате: '
                            '${formatMoney(_prepayAmount)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _newClientPrepay
                            ? 'Предоплата нужна только на первый визит '
                                  '— дальше запись без неё.'
                            : 'Предоплата засчитывается в стоимость услуги.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (_services.isNotEmpty && _fullPrice > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Стоимость посещения после предоплаты: '
                          '${formatMoney(_remainingAfterPrepay)}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Если вы не придёте, предоплата сгорает.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Для внесения предоплаты свяжитесь с '
                        '${widget.master.isSalon ? 'салоном' : 'мастером'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: _contactMaster,
                      icon: const Icon(Icons.phone_outlined, size: 18),
                      label: Text(
                        'Связаться с ${widget.master.isSalon ? 'салоном' : 'мастером'}',
                      ),
                    ),
                    if (widget.master.prepayLink.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      TextButton.icon(
                        onPressed: _pay,
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Оплатить по ссылке'),
                      ),
                    ],
                    InkWell(
                      onTap: _saving
                          ? null
                          : () => setState(() => _prepayDone = !_prepayDone),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Checkbox(
                              value: _prepayDone,
                              onChanged: _saving
                                  ? null
                                  : (v) => setState(
                                      () => _prepayDone = v ?? false,
                                    ),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                            const Expanded(child: Text('Я внёс предоплату')),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_blocked) ...[
              const SizedBox(height: 8),
              Text(
                '${widget.master.isSalon ? 'Салон' : 'Мастер'} '
                'ограничил запись для вашего аккаунта',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        bizzyFilledButton(
          onPressed: (_saving || _blocked || (_needsPrepay && !_prepayDone))
              ? null
              : _submit,
          child: Text(
            _needsPrepay && !_prepayDone
                ? 'Сначала внесите предоплату'
                : 'Записаться',
          ),
        ),
      ],
    );
  }
}

// ==================== МОИ ЗАПИСИ ====================

class ClientBookingsTab extends StatefulWidget {
  const ClientBookingsTab({super.key});

  @override
  State<ClientBookingsTab> createState() => _ClientBookingsTabState();
}

class _ClientBookingsTabState extends State<ClientBookingsTab> {
  final _cloud = CloudService();
  List<CloudBooking> _bookings = [];
  Map<int, int> _myRatings = {};
  bool _loading = true;
  bool _failed = false;

  /// За сколько минут до записи приходит напоминание (настраивается).
  int _reminderMinutes = 60;
  static const _reminderKey = 'cloud_reminder_minutes';

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
      // Записи и мои оценки — одним параллельным запросом вместо
      // серии ratingFor по каждой записи.
      final results = await Future.wait([
        _cloud.clientBookings(),
        _cloud
            .myRatings()
            .then<Map<int, int>>((v) => v)
            .catchError((_) => <int, int>{}),
      ]);
      final bookings = results[0] as List<CloudBooking>;
      final ratings = results[1] as Map<int, int>;
      final prefs = await SharedPreferences.getInstance();
      _reminderMinutes = prefs.getInt(_reminderKey) ?? 60;
      if (!mounted) return;
      setState(() {
        _bookings = bookings;
        _myRatings = ratings;
      });
      await _scheduleReminders(bookings);
      await _maybeNudgeRevisit(bookings);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scheduleReminders(List<CloudBooking> bookings) async {
    final reminderMinutes = _reminderMinutes;
    final now = DateTime.now();
    for (final b in bookings) {
      if (b.status == 'cancelled' || b.status == 'completed') {
        await PushNotificationService.cancelCloudReminder(b.id);
        continue;
      }
      if (b.startsAt.isAfter(now)) {
        await PushNotificationService.scheduleCloudReminder(
          id: b.id,
          dateTime: b.startsAt,
          reminderMinutes: reminderMinutes,
          title: 'Скоро запись',
          body: '${b.serviceName} • ${_fmt(b.startsAt)}',
        );
      } else {
        await PushNotificationService.cancelCloudReminder(b.id);
      }
    }
  }

  /// «Давно не были»: если после последнего завершённого визита к мастеру
  /// прошло 21+ дней и нет активной записи — мягкое локальное напоминание.
  /// Не чаще раза в 14 дней на одного мастера.
  Future<void> _maybeNudgeRevisit(List<CloudBooking> bookings) async {
    final now = DateTime.now();
    final lastVisit = <String, DateTime>{};
    final nameByMaster = <String, String>{};
    for (final b in bookings) {
      nameByMaster[b.masterId] = b.masterName;
      if (b.status == 'completed' &&
          (lastVisit[b.masterId]?.isBefore(b.startsAt) ?? true)) {
        lastVisit[b.masterId] = b.startsAt;
      }
    }
    final activeMasters = bookings
        .where(
          (b) =>
              (b.status == 'pending' || b.status == 'confirmed') &&
              b.startsAt.isAfter(now),
        )
        .map((b) => b.masterId)
        .toSet();
    final prefs = await SharedPreferences.getInstance();
    for (final e in lastVisit.entries) {
      if (activeMasters.contains(e.key)) continue;
      if (now.difference(e.value).inDays < 21) continue;
      final key = 'revisit_nudge_${e.key}';
      final lastNudge = DateTime.fromMillisecondsSinceEpoch(
        prefs.getInt(key) ?? 0,
      );
      if (now.difference(lastNudge).inDays < 14) continue;
      await prefs.setInt(key, now.millisecondsSinceEpoch);
      final name = nameByMaster[e.key] ?? '';
      await PushNotificationService.showLocal(
        title: 'Давно не были${name.isEmpty ? '' : ' у $name'}',
        body: 'Запишитесь снова — откройте Bizzy и выберите время',
        payload: jsonEncode({'master_id': e.key}),
      );
    }
  }

  Future<void> _cancel(CloudBooking b) async {
    try {
      await _cloud.setBookingStatus(b.id, 'cancelled');
      // Освободилось окно — уведомляем лист ожидания провайдера
      // (и салона, если запись проходила через него).
      await _cloud.notifyWaitlist(b.masterId);
      if (b.salonId.isNotEmpty && b.salonId != b.masterId) {
        await _cloud.notifyWaitlist(b.salonId);
      }
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось отменить запись')),
      );
    }
  }

  Future<void> _rate(CloudBooking b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => RateBookingDialog(booking: b),
    );
    if (ok == true) await _load();
  }

  String _statusLabel(String status) => switch (status) {
    'pending' => 'Ожидает мастера',
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

  bool _canRate(CloudBooking b) =>
      b.isPast &&
      (b.status == 'confirmed' || b.status == 'completed') &&
      !_myRatings.containsKey(b.id);

  static const _months = [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];

  String _monthLabel(DateTime d) => '${_months[d.month - 1]} ${d.year}';

  /// Повторная запись: открывает профиль того же провайдера
  /// (салон — если запись была через салон) с предвыбранными услугами.
  Future<void> _repeat(CloudBooking b) async {
    try {
      final master = await _cloud.masterCard(
        b.salonId.isNotEmpty ? b.salonId : b.masterId,
      );
      if (!mounted) return;
      if (master == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Профиль мастера сейчас недоступен')),
        );
        return;
      }
      final booked = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => MasterDetailScreen(
            master: master,
            prebookServiceIds: b.serviceIds.isNotEmpty
                ? b.serviceIds
                : [if (b.serviceId != null) b.serviceId!],
          ),
        ),
      );
      if (booked == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Заявка отправлена мастеру')),
        );
        await _load();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть мастера')),
      );
    }
  }

  /// Перенос записи клиентом: день → свободный слот → новое время.
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

    List<DateTime> slots = [];
    var failed = false;
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
        busy: (results[0] as List<CloudBooking>)
            .where((x) => x.id != b.id)
            .toList(),
        week: WorkWeek.fromJson(results[1] as Map<String, dynamic>?),
        stepMinutes: slotStepFor(b.durationMinutes),
        blocked: [for (final bl in blocks) (bl.startsAt, bl.endsAt)],
      );
    } catch (_) {
      failed = true;
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
              if (failed)
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

    try {
      await _cloud.rescheduleBooking(b.id, picked);
      await PushNotificationService.cancelCloudReminder(b.id);
      await PushNotificationService.scheduleCloudReminder(
        id: b.id,
        dateTime: picked,
        reminderMinutes: _reminderMinutes,
        title: 'Скоро запись',
        body: '${b.serviceName} • ${_fmt(picked)}',
      );
      if (b.masterId.isNotEmpty) {
        await PushNotificationService.sendPush(
          toUserId: b.masterId,
          title: 'Запись перенесена',
          body:
              '${b.clientName.isEmpty ? 'Клиент' : b.clientName} '
              'перенёс запись на ${_fmt(picked)}',
          data: {'appointment_id': b.id, 'status': b.status},
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Запись перенесена')));
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось перенести запись')),
      );
    }
  }

  /// Выбор интервала напоминания: сохраняется и применяется к записям.
  Future<void> _setReminderMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_reminderKey, minutes);
    if (!mounted) return;
    setState(() => _reminderMinutes = minutes);
    await _scheduleReminders(_bookings);
  }

  /// Детали записи + действия: повторить, перенести, оценить, отменить.
  Future<void> _showDetails(CloudBooking b) async {
    final myRating = _myRatings[b.id];
    // Если я уже оценил визит — подтягиваю ответ мастера/салона.
    final reply = myRating == null ? '' : await _cloud.ratingReplyFor(b.id);
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      b.serviceName,
                      style: Theme.of(ctx).textTheme.titleLarge,
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
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.person_outline, color: scheme.primary),
                title: Text(b.masterName.isEmpty ? 'Мастер' : b.masterName),
                subtitle: b.masterAddress.isNotEmpty
                    ? Text(b.masterAddress)
                    : null,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.schedule, color: scheme.primary),
                title: Text(_fmt(b.startsAt)),
                subtitle: Text(
                  '${b.durationMinutes} мин'
                  '${b.servicePrice > 0 ? ' • ${formatMoney(b.servicePrice)}' : ''}',
                ),
              ),
              if (b.prepaymentStatus != 'none')
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.payments_outlined,
                    color: b.prepaymentStatus == 'confirmed'
                        ? Colors.green
                        : Colors.orange,
                  ),
                  title: Text(
                    b.prepaymentStatus == 'confirmed'
                        ? 'Предоплата подтверждена мастером'
                        : 'Предоплата внесена — ждёт подтверждения',
                  ),
                ),
              if (b.notes.isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.notes_outlined, color: scheme.primary),
                  title: Text(b.notes),
                ),
              if (myRating != null) ...[
                Row(
                  children: [
                    Icon(Icons.star, size: 16, color: Colors.amber),
                    const SizedBox(width: 6),
                    Text('Ваша оценка: $myRating из 5'),
                  ],
                ),
                if (reply.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ответ '
                          '${b.masterName.isEmpty ? 'мастера' : b.masterName}',
                          style: Theme.of(ctx).textTheme.labelSmall
                              ?.copyWith(color: scheme.primary),
                        ),
                        const SizedBox(height: 2),
                        Text(reply),
                      ],
                    ),
                  ),
              ],
              // Напоминание: за сколько до визита предупредить клиента.
              if ((b.status == 'pending' || b.status == 'confirmed') &&
                  b.startsAt.isAfter(DateTime.now())) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      Icons.notifications_outlined,
                      size: 18,
                      color: scheme.primary,
                    ),
                    const Text('Напомнить за:'),
                    for (final m in [30, 60, 180, 1440])
                      ChoiceChip(
                        label: Text(
                          m >= 1440
                              ? '${m ~/ 1440} д'
                              : m >= 60
                              ? '${m ~/ 60} ч'
                              : '$m мин',
                        ),
                        selected: _reminderMinutes == m,
                        onSelected: (_) => _setReminderMinutes(m),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_canRate(b))
                    bizzyFilledButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _rate(b);
                      },
                      icon: const Icon(Icons.star),
                      child: const Text('Поставить оценку'),
                    ),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _repeat(b);
                    },
                    icon: const Icon(Icons.repeat),
                    label: const Text('Записаться снова'),
                  ),
                  if ((b.status == 'pending' || b.status == 'confirmed') &&
                      b.startsAt.isAfter(DateTime.now()))
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _reschedule(b);
                      },
                      icon: const Icon(Icons.schedule),
                      label: const Text('Перенести'),
                    ),
                  if (b.status == 'pending' || b.status == 'confirmed')
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _cancel(b);
                      },
                      icon: const Icon(Icons.close),
                      label: const Text('Отменить'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Мои записи')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Не удалось загрузить записи'),
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
                            'У вас пока нет записей.\nВыберите мастера во вкладке «Услуги».',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: _bookings.length,
                      itemBuilder: (context, index) {
                        final b = _bookings[index];
                        final myRating = _myRatings[b.id];
                        // Заголовок месяца — перед первой записью нового месяца.
                        final showMonthHeader =
                            index == 0 ||
                            _bookings[index - 1].startsAt.month !=
                                b.startsAt.month ||
                            _bookings[index - 1].startsAt.year !=
                                b.startsAt.year;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showMonthHeader)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  4,
                                ),
                                child: Text(
                                  _monthLabel(b.startsAt),
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ),
                            Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              child: InkWell(
                                onTap: () => _showDetails(b),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                            backgroundColor: _statusColor(
                                              b.status,
                                            ).withValues(alpha: 0.15),
                                            side: BorderSide.none,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        b.masterName.isEmpty
                                            ? 'Мастер'
                                            : b.masterName,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${_fmt(b.startsAt)} • ${b.durationMinutes} мин'
                                        '${b.servicePrice > 0 ? ' • ${formatMoney(b.servicePrice)}' : ''}'
                                        '${b.prepaymentStatus != 'none' ? ' • предоплата' : ''}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                      if (b.masterAddress.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 4,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.place_outlined,
                                                size: 14,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                              ),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  b.masterAddress,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      if (myRating != null) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            for (var i = 1; i <= 5; i++)
                                              Icon(
                                                i <= myRating
                                                    ? Icons.star
                                                    : Icons.star_border,
                                                size: 16,
                                                color: Colors.amber,
                                              ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
    );
  }
}

/// Диалог оценки после записи.
class RateBookingDialog extends StatefulWidget {
  const RateBookingDialog({super.key, required this.booking});

  final CloudBooking booking;

  @override
  State<RateBookingDialog> createState() => _RateBookingDialogState();
}

class _RateBookingDialogState extends State<RateBookingDialog> {
  final _cloud = CloudService();
  final _comment = TextEditingController();
  int _rating = 5;
  bool _saving = false;
  String? _error;

  /// Оценка идёт конкретному исполнителю; если запись прошла
  /// через салон — отзыв учитывается и в рейтинге салона.
  bool _countsForSalon = false;
  String _targetName = '';

  @override
  void initState() {
    super.initState();
    _targetName = widget.booking.masterName;
    _resolveTarget();
  }

  Future<void> _resolveTarget() async {
    if (widget.booking.salonId.isNotEmpty) {
      if (mounted) setState(() => _countsForSalon = true);
      return;
    }
    try {
      final card = await _cloud.masterCard(widget.booking.masterId);
      if (card != null && card.name.isNotEmpty) {
        _targetName = card.name;
      }
      final salonId = card?.salonId;
      final hasSalon =
          (salonId != null && salonId.isNotEmpty) || (card?.isSalon ?? false);
      if (!mounted) return;
      setState(() => _countsForSalon = hasSalon);
    } catch (_) {}
  }

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
      await _cloud.rateBooking(
        appointmentId: widget.booking.id,
        masterId: widget.booking.masterId,
        rating: _rating,
        comment: _comment.text.trim(),
        // Отзыв привязан к услуге; для салонной записи — и к салону.
        serviceId: widget.booking.serviceIds.isNotEmpty
            ? widget.booking.serviceIds.first
            : widget.booking.serviceId,
        salonId: widget.booking.salonId.isEmpty ? null : widget.booking.salonId,
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
      title: const Text('Оцените работу'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _targetName.isNotEmpty
                ? '$_targetName • ${widget.booking.serviceName}'
                : widget.booking.serviceName,
            textAlign: TextAlign.center,
          ),
          if (_countsForSalon)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Отзыв учтётся и в рейтинге салона',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
        bizzyFilledButton(
          onPressed: _saving ? null : _submit,
          child: const Text('Отправить'),
        ),
      ],
    );
  }
}

// ==================== ПРОФИЛЬ КЛИЕНТА ====================

class _ClientProfileTab extends StatelessWidget {
  const _ClientProfileTab({
    required this.profile,
    required this.onSignOut,
    required this.onDeleteAccount,
    this.onProfileUpdated,
  });

  final CloudProfile profile;
  final Future<void> Function() onSignOut;
  final Future<void> Function() onDeleteAccount;
  final VoidCallback? onProfileUpdated;

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить аккаунт?'),
        content: const Text(
          'Все ваши данные в облаке будут удалены безвозвратно.',
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
    if (ok != true || !context.mounted) return;
    try {
      await onDeleteAccount();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось удалить аккаунт')),
      );
    }
  }

  Future<void> _edit(BuildContext context) async {
    final updated = await Navigator.of(context).push<CloudProfile>(
      MaterialPageRoute(
        builder: (context) => ClientProfileEditScreen(profile: profile),
      ),
    );
    if (updated != null) onProfileUpdated?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Мой профиль')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: scheme.primary,
                    backgroundImage: profile.avatarUrl.isNotEmpty
                        ? NetworkImage(profile.avatarUrl)
                        : null,
                    child: profile.avatarUrl.isEmpty
                        ? Icon(Icons.person, color: scheme.onPrimary, size: 36)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name.isEmpty ? 'Клиент' : profile.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (profile.phone.isNotEmpty) Text(profile.phone),
                        Text(CloudService().displayLogin),
                        if (profile.address.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.place_outlined,
                                  size: 16,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    profile.address,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _edit(context),
            icon: const Icon(Icons.edit),
            label: const Text('Изменить профиль'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => showCredentialsEditor(context),
            icon: const Icon(Icons.key_outlined),
            label: const Text('Изменить логин и пароль'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => showAppearancePicker(context, showBizzyLook: true),
            icon: const Icon(Icons.palette_outlined),
            label: Text('Внешний вид · ${themeModeLabel(appThemeMode.value)}'),
          ),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            onPressed: () => onSignOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Выйти'),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () => _confirmDelete(context),
            icon: const Icon(Icons.delete_forever),
            label: const Text('Удалить аккаунт'),
          ),
          const SizedBox(height: 24),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snap) {
              final v = snap.data?.version ?? '';
              if (v.isEmpty) return const SizedBox.shrink();
              final build = snap.data?.buildNumber ?? '';
              return Text(
                'Версия $v${build.isNotEmpty ? '+$build' : ''}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.5)),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Экран редактирования профиля клиента.
class ClientProfileEditScreen extends StatefulWidget {
  const ClientProfileEditScreen({super.key, required this.profile});

  final CloudProfile profile;

  @override
  State<ClientProfileEditScreen> createState() =>
      _ClientProfileEditScreenState();
}

class _ClientProfileEditScreenState extends State<ClientProfileEditScreen> {
  final _cloud = CloudService();
  final _geo = GeoService();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  String _avatarUrl = '';
  double? _lat;
  double? _lng;
  bool _phonePublic = true;
  bool _pickingAvatar = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.profile.name;
    _phoneController.text = widget.profile.phone;
    _addressController.text = widget.profile.address;
    _avatarUrl = widget.profile.avatarUrl;
    _lat = widget.profile.lat;
    _lng = widget.profile.lng;
    _phonePublic = widget.profile.phonePublic;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  /// Выбор своей точки на карте; после выбора адрес подставляется
  /// обратным геокодингом.
  Future<void> _pickLocationOnMap() async {
    GeoPoint? initial;
    if (_lat != null && _lng != null) {
      initial = GeoPoint(_lat!, _lng!);
    } else if (_addressController.text.trim().isNotEmpty) {
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Геопозиция определена')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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
      final url = await _cloud.uploadAvatar(file);
      await _cloud.updateMyProfile(avatarUrl: url);
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

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final address = _addressController.text.trim();

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      // Координаты: выбранные на карте, либо геокодинг из текста адреса.
      var lat = _lat;
      var lng = _lng;
      if ((lat == null || lng == null) && address.isNotEmpty) {
        final point = await _geo.geocode(address);
        if (point != null) {
          lat = point.lat;
          lng = point.lng;
        }
      }
      final cleared = address.isEmpty;

      await _cloud.updateMyProfile(
        name: name,
        phone: phone,
        avatarUrl: _avatarUrl,
        address: address,
        lat: cleared ? null : lat,
        lng: cleared ? null : lng,
        phonePublic: _phonePublic,
        clearLocation: cleared,
      );

      final updated = await _cloud.myProfile();
      if (!mounted) return;
      if (updated == null) throw Exception('Не удалось загрузить профиль');
      Navigator.of(context).pop(updated);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Профиль сохранён')));
    } catch (e) {
      await SyncLog.write('client_profile_edit', e.toString());
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
      appBar: AppBar(title: const Text('Мой профиль')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor: scheme.primary,
                  backgroundImage: _avatarUrl.isNotEmpty
                      ? NetworkImage(_avatarUrl)
                      : null,
                  child: _avatarUrl.isEmpty
                      ? Icon(Icons.person, color: scheme.onPrimary, size: 40)
                      : null,
                ),
                if (_pickingAvatar)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: scheme.secondary,
                    child: IconButton(
                      onPressed: _pickAvatar,
                      icon: const Icon(Icons.camera_alt, size: 16),
                      color: scheme.onSecondary,
                      padding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Имя',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Телефон',
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
                        : (v) => setState(() => _phonePublic = v ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: Text(
                      'Показывать номер мастерам и салонам',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Мой адрес',
              hintText: 'Город, улица — для поиска мастеров рядом',
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
          FilledButton.tonalIcon(
            onPressed: _saving ? null : () => showCredentialsEditor(context),
            icon: const Icon(Icons.key_outlined),
            label: const Text('Изменить логин и пароль'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
          const SizedBox(height: 24),
          bizzyFilledButton(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
}
