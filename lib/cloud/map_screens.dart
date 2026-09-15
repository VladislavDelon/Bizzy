import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'cloud_service.dart';
import 'geo_service.dart';

/// Центр по умолчанию — Москва, если ни у клиента, ни у мастеров
/// координат нет.
const LatLng kDefaultMapCenter = LatLng(55.751244, 37.618423);

/// Слой тайлов OpenStreetMap — бесплатно, без API-ключа.
TileLayer osmTileLayer() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.example.bizzy_app',
      maxZoom: 19,
    );

/// Экран выбора точки на карте. Возвращает [LatLng] через Navigator.pop.
/// Тап по карте ставит маркер; кнопка подтверждает выбор.
class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key, this.initial});

  /// Начальная точка (уже сохранённые координаты или результат геокодинга).
  final GeoPoint? initial;

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  LatLng? _picked;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) _picked = LatLng(i.lat, i.lng);
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
            options: MapOptions(
              initialCenter: center,
              initialZoom: _picked != null ? 15 : 10,
              onTap: (tapPosition, point) =>
                  setState(() => _picked = point),
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
                    ? 'Коснитесь карты, чтобы поставить метку'
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
/// [onOpen] вызывается при выборе мастера из всплывающей карточки.
class MastersMapScreen extends StatelessWidget {
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

  LatLng get _initialCenter {
    if (clientLat != null && clientLng != null) {
      return LatLng(clientLat!, clientLng!);
    }
    final withCoords = masters.where((m) => m.hasLocation).toList();
    if (withCoords.isEmpty) return kDefaultMapCenter;
    final lat = withCoords.map((m) => m.lat!).reduce((a, b) => a + b) /
        withCoords.length;
    final lng = withCoords.map((m) => m.lng!).reduce((a, b) => a + b) /
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
                          master.category,
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                        Row(
                          children: [
                            const Icon(Icons.star,
                                size: 14, color: Colors.amber),
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
                  onOpen(master);
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
    final located = masters.where((m) => m.hasLocation).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Мастера на карте')),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: clientLat != null ? 12 : 5,
            ),
            children: [
              osmTileLayer(),
              MarkerLayer(
                markers: [
                  if (clientLat != null && clientLng != null)
                    Marker(
                      point: LatLng(clientLat!, clientLng!),
                      width: 44,
                      height: 44,
                      child: const Icon(
                        Icons.my_location,
                        size: 32,
                        color: Colors.blueAccent,
                      ),
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
                child: const Text(
                  'Пока ни у одного мастера не указан адрес на карте',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
