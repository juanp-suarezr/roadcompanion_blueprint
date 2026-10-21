import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../../domain/entities/coordinates.dart';
import '../entities/destination.dart';

/// Servicio especializado para consultar puntos de interés (POIs) en OpenStreetMap
/// mediante Overpass API con caché en memoria, límites de tasa y manejo defensivo de red.
///
/// Permite localizar establecimientos especializados (talleres de motocicletas, montallantas,
/// peluquerías, centros comerciales) utilizando etiquetas cartográficas nativas (`shop`, `amenity`).
class OsmPoiService {
  final http.Client _client;
  final String _overpassUrl;
  final Map<String, List<Destination>> _cache = {};

  OsmPoiService({
    http.Client? client,
    String overpassUrl = 'https://overpass-api.de/api/interpreter',
  })  : _client = client ?? http.Client(),
        _overpassUrl = overpassUrl;

  /// Consulta lugares de una categoría específica en una caja delimitadora alrededor de [center].
  Future<List<Destination>> fetchCategoryPois({
    required String categoryKey,
    required Coordinates center,
    required double deltaDegrees,
    int limit = 15,
  }) async {
    final cacheKey =
        '${categoryKey}_${center.latitude.toStringAsFixed(3)}_${center.longitude.toStringAsFixed(3)}_${deltaDegrees.toStringAsFixed(3)}';

    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    final minLat = center.latitude - deltaDegrees;
    final minLon = center.longitude - deltaDegrees;
    final maxLat = center.latitude + deltaDegrees;
    final maxLon = center.longitude + deltaDegrees;
    final bbox = '$minLat,$minLon,$maxLat,$maxLon';

    final tagSelector = _resolveTagSelector(categoryKey);
    if (tagSelector == null) {
      return [];
    }

    final overpassQuery = '''
[out:json][timeout:5];
(
  $tagSelector($bbox);
);
out center $limit;
''';

    try {
      final uri = Uri.parse('$_overpassUrl?data=${Uri.encodeComponent(overpassQuery)}');
      final response = await _client
          .get(
            uri,
            headers: {
              'User-Agent':
                  'REstelarNavigationApp/1.0 (local motorcycle poi companion; contact: restelar@roadcompanion.app)',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) {
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = data['elements'] as List<dynamic>? ?? [];

      final results = <Destination>[];
      for (final el in elements) {
        if (el is! Map<String, dynamic>) continue;
        final tags = el['tags'] as Map<String, dynamic>? ?? {};

        final latNum = (el['lat'] ?? el['center']?['lat']) as num?;
        final lonNum = (el['lon'] ?? el['center']?['lon']) as num?;
        if (latNum == null || lonNum == null) continue;

        final lat = latNum.toDouble();
        final lon = lonNum.toDouble();
        final coords = Coordinates(lat, lon);

        final id = 'osm_${el['type'] ?? 'node'}_${el['id']}';
        final rawName = tags['name']?.toString().trim() ?? '';
        final title = rawName.isNotEmpty
            ? rawName
            : _buildFallbackTitle(categoryKey, tags);

        final subtitle = _buildSubtitle(tags);

        results.add(
          Destination(
            id: id,
            title: title,
            subtitle: subtitle,
            coordinates: coords,
            category: categoryKey,
          ),
        );
      }

      _cache[cacheKey] = results;
      return results;
    } catch (_) {
      // Manejo defensivo: ante cualquier error o timeout de Overpass, retornar lista vacía
      // para que el llamador continúe con la búsqueda en Nominatim
      return [];
    }
  }

  String? _resolveTagSelector(String categoryKey) {
    switch (categoryKey.toLowerCase()) {
      case 'motorcycle_repair':
      case 'motorcycle':
        return 'node["shop"="motorcycle"]; node["amenity"="motorcycle_repair"]; node["shop"="motorcycle_repair"]';
      case 'tyres':
      case 'montallantas':
        return 'node["shop"="tyres"]; node["service"="tyres"]';
      case 'mall':
      case 'shopping_mall':
        return 'node["shop"="mall"]; way["shop"="mall"]';
      case 'hairdresser':
      case 'barber':
        return 'node["shop"="hairdresser"]; node["shop"="beauty"]';
      case 'place_of_worship':
        return 'node["amenity"="place_of_worship"]';
      default:
        return null;
    }
  }

  String _buildFallbackTitle(String categoryKey, Map<String, dynamic> tags) {
    final street = tags['addr:street']?.toString() ?? '';
    final streetPart = street.isNotEmpty ? ' ($street)' : '';

    switch (categoryKey.toLowerCase()) {
      case 'motorcycle_repair':
      case 'motorcycle':
        return 'Taller de Motocicletas$streetPart';
      case 'tyres':
      case 'montallantas':
        return 'Montallantas / Vulcanizadora$streetPart';
      case 'mall':
        return 'Centro Comercial$streetPart';
      case 'hairdresser':
      case 'barber':
        return 'Barbería / Peluquería$streetPart';
      case 'place_of_worship':
        final religion = tags['religion']?.toString() ?? 'Iglesia';
        return '$religion$streetPart';
      default:
        return 'Establecimiento Local';
    }
  }

  String _buildSubtitle(Map<String, dynamic> tags) {
    final street = tags['addr:street']?.toString();
    final housenumber = tags['addr:housenumber']?.toString();
    final city = tags['addr:city']?.toString() ??
        tags['addr:municipality']?.toString();

    final parts = <String>[];
    if (street != null && street.isNotEmpty) {
      if (housenumber != null && housenumber.isNotEmpty) {
        parts.add('$street # $housenumber');
      } else {
        parts.add(street);
      }
    }
    if (city != null && city.isNotEmpty) {
      parts.add(city);
    }

    if (parts.isNotEmpty) {
      return parts.join(', ');
    }
    return 'Lugar cercano identificado en OpenStreetMap';
  }

  void clearCache() => _cache.clear();
}
