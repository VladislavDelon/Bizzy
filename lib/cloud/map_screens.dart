import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'cloud_service.dart';
import 'geo_service.dart';

/// Центр по умолчанию — Москва, если ни у клиента, ни у мастеров
/// координат нет.
const LatLng kDefaultMapCenter = LatLng(55.751244, 37.618423);

/// Тайлы CARTO Voyager — чистая быстрая карта с подписями на
/// языке региона (в РУ/КЗ — на русском). Работает без ключа,
/// тайлы отдаются с CDN — грузится быстрее Wikimedia/OSM.
TileLayer osmTileLayer() => TileLayer(
  urlTemplate:
      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
  subdomains: const ['a', 'b', 'c', 'd'],
  userAgentPackageName: 'com.example.bizzy_app',
  maxZoom: 19,
);

/// Синяя точка «я на карте».
class _MyLocationMarker extends StatelessWidget {
  const _MyLocationMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: Colors.blueAccent,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
    );
  }
}

/// Экран выбора точки на карте. Возвращает [LatLng] через Navigator.pop.
/// Тап по карте ставит маркер; кнопка подтверждает выбор.
/// Если точка не задана — карта сама определяет геопозицию.
class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key, this.initial});

  /// Начальная точка (уже сохранённые координаты или результат геокодинга).
  final GeoPoint? initial;

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final _mapController = MapController();
  LatLng? _picked;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      _picked = LatLng(i.lat, i.lng);
    } else {
      // Авто-геопозиция: карта сразу открывается на точке
      // пользователя — остаётся только подтвердить/подвинуть метку.
      _locate();
    }
  }

  Future<void> _locate() async {
    try {
      final p = await GeoService().currentPosition();
      if (!mounted) return;
      final point = LatLng(p.lat, p.lng);
      setState(() => _picked = point);
      _mapController.move(point, 15);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final center = _picked ?? kDefaultMapCenter;
    return Scaffold(
      appBar: AppBar(title: const Text('Укажите точку на карте')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: _picked != null ? 15 : 10,
              onTap: (tapPosition, point) => setState(() => _picked = point),
            ),
            children: [
              osmTileLayer(),
              if (_picked != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _picked!,
                      width: 44,
                      height: 44,
                      child: Icon(
                        Icons.location_pin,
                        size: 44,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
              const SimpleAttributionWidget(
                source: Text('© OpenStreetMap contributors © CARTO'),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _picked == null
                    ? 'Определяем ваше положение…\n'
                          'Можно коснуться карты и поставить метку'
                    : 'Метку можно передвинуть новым касанием',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _picked == null
                ? null
                : () => Navigator.of(context).pop(_picked),
            icon: const Icon(Icons.check),
            label: const Text('Выбрать эту точку'),
          ),
        ),
      ),
    );
  }
}

/// Карта со всеми мастерами, у которых заданы координаты.
/// При открытии сама определяет геопозицию клиента и центрируется
/// на ней — кнопки «найти меня» не нужно.
/// [onOpen] вызывается при выборе мастера из всплывающей карточки.
class MastersMapScreen extends StatefulWidget {
  const MastersMapScreen({
    super.key,
    required this.masters,
    required this.onOpen,
    this.clientLat,
    this.clientLng,
  });

  final List<MasterCard> masters;
  final void Function(MasterCard master) onOpen;
  final double? clientLat;
  final double? clientLng;

  @override
  State<MastersMapScreen> createState() => _MastersMapScreenState();
}

class _MastersMapScreenState extends State<MastersMapScreen> {
  final _mapController = MapController();
  double? _myLat;
  double? _myLng;

  /// Фильтры карты: тип провайдера и категория услуг.
  /// 'all' — и мастера, и салоны.
  String _roleFilter = 'all';
  String? _categoryFilter;

  @override
  void initState() {
    super.initState();
    _myLat = widget.clientLat;
    _myLng = widget.clientLng;
    if (_myLat == null) _locate();
  }

  /// Авто-геопозиция при открытии карты: находим клиента,
  /// ставим синюю точку и подъезжаем камерой.
  Future<void> _locate() async {
    try {
      final p = await GeoService().currentPosition();
      if (!mounted) return;
      setState(() {
        _myLat = p.lat;
        _myLng = p.lng;
      });
      _mapController.move(LatLng(p.lat, p.lng), 13);
    } catch (_) {}
  }

  LatLng get _initialCenter {
    if (_myLat != null && _myLng != null) {
      return LatLng(_myLat!, _myLng!);
    }
    final withCoords = widget.masters.where((m) => m.hasLocation).toList();
    if (withCoords.isEmpty) return kDefaultMapCenter;
    final lat =
        withCoords.map((m) => m.lat!).reduce((a, b) => a + b) /
        withCoords.length;
    final lng =
        withCoords.map((m) => m.lng!).reduce((a, b) => a + b) /
        withCoords.length;
    return LatLng(lat, lng);
  }

  void _showMaster(BuildContext context, MasterCard master) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: scheme.primary,
                    backgroundImage: master.avatarUrl.isNotEmpty
                        ? NetworkImage(master.avatarUrl)
                        : null,
                    child: master.avatarUrl.isEmpty
                        ? Icon(Icons.person, color: scheme.onPrimary)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          master.name.isEmpty ? 'Мастер' : master.name,
                          style: Theme.of(ctx).textTheme.titleMedium,
                        ),
                        Text(
                          master.categories.isNotEmpty
                              ? master.categories.join(' · ')
                              : master.category,
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                        Row(
                          children: [
                            const Icon(
                              Icons.star,
                              size: 14,
                              color: Colors.amber,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              master.ratingCount == 0
                                  ? 'Новый'
                                  : '${master.ratingAvg.toStringAsFixed(1)} '
                                        '(${master.ratingCount})',
                              style: Theme.of(ctx).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (master.address.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.place, size: 16, color: scheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        master.address,
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  widget.onOpen(master);
                },
                child: const Text('Открыть профиль'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Фильтрация: тип (мастер/салон) + категория услуг.
    final located = widget.masters.where((m) {
      if (!m.hasLocation) return false;
      if (_roleFilter != 'all' && m.role != _roleFilter) return false;
      if (_categoryFilter != null &&
          !m.categories.contains(_categoryFilter) &&
          m.category != _categoryFilter) {
        return false;
      }
      return true;
    }).toList();
    // Все категории, которые встречаются у мастеров на карте.
    final allCategories = <String>{
      for (final m in widget.masters)
        ...(m.categories.isNotEmpty
            ? m.categories
            : [if (m.category.isNotEmpty) m.category]),
    }.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Рядом на карте')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: _myLat != null ? 13 : 5,
            ),
            children: [
              osmTileLayer(),
              MarkerLayer(
                markers: [
                  if (_myLat != null && _myLng != null)
                    Marker(
                      point: LatLng(_myLat!, _myLng!),
                      width: 24,
                      height: 24,
                      child: const _MyLocationMarker(),
                    ),
                  for (final m in located)
                    Marker(
                      point: LatLng(m.lat!, m.lng!),
                      width: 44,
                      height: 44,
                      child: GestureDetector(
                        onTap: () => _showMaster(context, m),
                        child: Icon(
                          Icons.location_pin,
                          size: 44,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
              const SimpleAttributionWidget(
                source: Text('© OpenStreetMap contributors © CARTO'),
              ),
            ],
          ),
          if (located.isEmpty)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.masters.any((m) => m.hasLocation)
                      ? 'По выбранным фильтрам никого нет'
                      : 'Пока ни у одного мастера не указан адрес на карте',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          // Фильтры: тип провайдера + категория. Плавающая панель
          // снизу — не мешает тапать по карте.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 8),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: const Text('Все'),
                              selected: _roleFilter == 'all',
                              onSelected: (_) =>
                                  setState(() => _roleFilter = 'all'),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              avatar: const Icon(Icons.person, size: 16),
                              label: const Text('Мастера'),
                              selected: _roleFilter == 'master',
                              onSelected: (_) =>
                                  setState(() => _roleFilter = 'master'),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              avatar: const Icon(Icons.storefront, size: 16),
                              label: const Text('Салоны'),
                              selected: _roleFilter == 'salon',
                              onSelected: (_) =>
                                  setState(() => _roleFilter = 'salon'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (allCategories.length > 1)
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: ChoiceChip(
                                label: const Text('Все услуги'),
                                selected: _categoryFilter == null,
                                onSelected: (_) =>
                                    setState(() => _categoryFilter = null),
                              ),
                            ),
                            for (final cat in allCategories)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: ChoiceChip(
                                  label: Text(cat),
                                  selected: _categoryFilter == cat,
                                  onSelected: (_) =>
                                      setState(() => _categoryFilter = cat),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
