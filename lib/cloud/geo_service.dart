import 'dart:convert';
import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// Точка на карте (широта/долгота).
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;
}

/// Результат обратного геокодинга: координаты + человекочитаемый адрес.
class GeoAddress {
  const GeoAddress(this.point, this.label);

  final GeoPoint point;
  final String label;
}

/// Геокодинг через OpenStreetMap Nominatim — бесплатно, без API-ключа.
/// Nominatim требует осмысленный User-Agent и не любит частые запросы.
class GeoService {
  static const _base = 'https://nominatim.openstreetmap.org';
  static const _headers = {
    'User-Agent': 'BizzyApp/1.8 (appointment manager)',
    'Accept-Language': 'ru',
  };

  /// Адрес → координаты. null, если адрес не найден или сеть недоступна.
  Future<GeoPoint?> geocode(String address) async {
    final q = address.trim();
    if (q.isEmpty) return null;
    try {
      final uri = Uri.parse('$_base/search').replace(queryParameters: {
        'q': q,
        'format': 'jsonv2',
        'limit': '1',
        'addressdetails': '0',
      });
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final list = jsonDecode(res.body);
      if (list is! List || list.isEmpty) return null;
      final first = list.first;
      if (first is! Map) return null;
      final lat = double.tryParse('${first['lat']}');
      final lon = double.tryParse('${first['lon']}');
      if (lat == null || lon == null) return null;
      return GeoPoint(lat, lon);
    } catch (_) {
      return null;
    }
  }

  /// Координаты → адрес (для подстановки в поле после выбора точки на карте).
  Future<GeoAddress?> reverseGeocode(double lat, double lng) async {
    try {
      final uri = Uri.parse('$_base/reverse').replace(queryParameters: {
        'lat': '$lat',
        'lon': '$lng',
        'format': 'jsonv2',
        'zoom': '17',
      });
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      if (data is! Map) return null;
      final label = '${data['display_name']}';
      return GeoAddress(
        GeoPoint(lat, lng),
        label.isEmpty || label == 'null' ? '' : label,
      );
    } catch (_) {
      return null;
    }
  }

  /// Текущая геопозиция устройства. Запрашивает разрешение у пользователя.
  /// Бросает [Exception] с понятным текстом, если выйти не удалось.
  Future<GeoPoint> currentPosition() async {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) {
      throw Exception('Геолокация выключена. Включите GPS в настройках.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw Exception('Нет разрешения на геопозицию.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Доступ к геопозиции запрещён. Разрешите его в настройках приложения.',
      );
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings:
          const LocationSettings(timeLimit: Duration(seconds: 15)),
    );
    return GeoPoint(pos.latitude, pos.longitude);
  }

  /// Расстояние по прямой в километрах (формула гаверсинуса).
  static double distanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const r = 6371.0; // радиус Земли, км
    final dLat = _deg(lat2 - lat1);
    final dLng = _deg(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg(lat1)) * cos(_deg(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _deg(double d) => d * pi / 180;

  /// «800 м» / «3,4 км» — короткая подпись расстояния для карточек.
  static String formatDistance(double km) {
    if (km < 1) return '${(km * 1000).round()} м';
    return '${km.toStringAsFixed(1).replaceAll('.', ',')} км';
  }
}
